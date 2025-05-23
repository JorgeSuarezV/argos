defmodule Argos.ConfigValidatorTest do
  use ExUnit.Case, async: true

  alias Argos.Monitors.ConfigValidator
  # Types alias removed as it's no longer needed after replacing struct usage with maps

  # --- Mock Monitor Schemas ---
  defp mock_schemas do
    %{
      http: [
        %{
          name: :url,
          type: :string,
          required: true,
          validation: %{pattern: "^https?://.*"}
        },
        %{name: :method, type: :string, default: "GET"},
        %{name: :timeout, type: :integer, validation: %{min: 100, max: 5000}},
        %{name: :headers, type: :map, required: false},
        %{name: :is_test, type: :boolean, default: false}
      ],
      custom_type: [
        %{name: :api_key, type: :string, required: true},
        %{
          name: :port,
          type: :integer,
          required: true,
          validation: %{
            custom: fn p -> if p == 8080, do: :ok, else: {:error, "port must be 8080"} end
          }
        },
        %{name: :endpoints, type: {:list, :string}, required: true},
        %{name: :level, type: {:enum, ["info", "warn", "error"]}, default: "info"}
      ]
    }
  end

  # --- Valid Base Config Parts ---
  defp valid_retry_policy_json,
    do: %{"max_retries" => 3, "retry_timeout" => 1000, "backoff_strategy" => "exponential"}

  defp valid_http_config_json, do: %{"url" => "http://example.com", "timeout" => 1000}

  defp valid_custom_type_config_json,
    do: %{"api_key" => "secret", "port" => 8080, "endpoints" => ["/a", "/b"]}

  # --- Tests ---

  test "validates a completely correct configuration" do
    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "http_monitor_1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => valid_retry_policy_json()
          },
          %{
            "name" => "custom_monitor_1",
            "type" => "custom_type",
            "config" => valid_custom_type_config_json(),
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [
        %{"name" => "rule1", "monitor" => "http_monitor_1"},
        %{"name" => "rule2", "monitor" => ["custom_monitor_1", "http_monitor_1"]}
      ]
    }

    assert {:ok, validated} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert length(validated) == 2

    http_mon = Enum.find(validated, &(&1.monitor_id == "http_monitor_1"))
    assert http_mon.monitor_type == :http
    assert http_mon.monitor_config.url == "http://example.com"
    assert http_mon.monitor_config.timeout == 1000
    # default value
    assert http_mon.monitor_config.is_test == false
    assert http_mon.retry_policy.max_retries == 3
    assert Map.has_key?(http_mon, :inform_to)
    assert "rule1" in http_mon.inform_to
    assert "rule2" in http_mon.inform_to

    custom_mon = Enum.find(validated, &(&1.monitor_id == "custom_monitor_1"))
    assert custom_mon.monitor_type == :custom_type
    assert custom_mon.monitor_config.port == 8080
    assert custom_mon.monitor_config.level == "info"
    assert "rule2" in custom_mon.inform_to
  end

  # --- Basic Monitor Field Validations ---
  test "error if monitor 'name' is missing or invalid" do
    config_json = %{"monitors" => %{"single" => [%{"type" => "http"}]}}
    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/must have a non-empty string 'name' field/))

    config_json2 = %{"monitors" => %{"single" => [%{"name" => 123, "type" => "http"}]}}
    assert {:error, reasons2} = ConfigValidator.validate_config(config_json2, mock_schemas())
    assert Enum.any?(reasons2, &(&1 =~ ~r/must have a non-empty string 'name' field/))
  end

  test "error if monitor 'type' is missing, invalid, or unsupported" do
    config_json = %{"monitors" => %{"single" => [%{"name" => "m1"}]}}
    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/'type' field is required/))

    config_json2 = %{"monitors" => %{"single" => [%{"name" => "m1", "type" => 123}]}}
    assert {:error, reasons2} = ConfigValidator.validate_config(config_json2, mock_schemas())
    assert Enum.any?(reasons2, &(&1 =~ ~r/'type' field must be a string/))

    config_json3 = %{"monitors" => %{"single" => [%{"name" => "m1", "type" => "unknown_type"}]}}
    assert {:error, reasons3} = ConfigValidator.validate_config(config_json3, mock_schemas())
    assert Enum.any?(reasons3, &(&1 =~ ~r/unsupported monitor type 'unknown_type'/))
  end

  test "error if monitor 'config' is missing or not a map" do
    monitor_base = %{
      "name" => "m1",
      "type" => "http",
      "retry_policy" => valid_retry_policy_json()
    }

    config_json = %{
      "monitors" => %{"single" => [Map.delete(monitor_base, "config")]},
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    # If config is missing, specific config validation handles it, but general structure check is good.
    # The error comes from validate_monitor_specific_config due to missing required field :url
    # Or if config field itself is totally missing, it can be caught by `validate_monitor_entry`
    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    # This will actually fail because http schema requires :url
    assert Enum.any?(reasons, &(&1 =~ ~r/config.url: is required but missing/))

    config_json2 = %{
      "monitors" => %{"single" => [Map.put(monitor_base, "config", "not_a_map")]},
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons2} = ConfigValidator.validate_config(config_json2, mock_schemas())
    assert Enum.any?(reasons2, &(&1 =~ ~r/'config' field is required and must be a map/))
  end

  test "error if monitor 'retry_policy' is missing or not a map" do
    monitor_base = %{"name" => "m1", "type" => "http", "config" => valid_http_config_json()}

    config_json = %{
      "monitors" => %{"single" => [Map.delete(monitor_base, "retry_policy")]},
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/'retry_policy' field is required and must be a map/))

    config_json2 = %{
      "monitors" => %{"single" => [Map.put(monitor_base, "retry_policy", "not_a_map")]},
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons2} = ConfigValidator.validate_config(config_json2, mock_schemas())
    assert Enum.any?(reasons2, &(&1 =~ ~r/'retry_policy' field is required and must be a map/))
  end

  # --- Retry Policy Validations ---
  test "retry_policy: validates required fields and values" do
    # Test max_retries validation
    policy = Map.put(valid_retry_policy_json(), "max_retries", "not_an_integer")

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(
             reasons,
             &(&1 =~ ~r/'max_retries' is required and must be a positive integer, 0 or null/)
           ),
           "Expected max_retries error for non-integer value"

    # Test max_retries = -1 (negative integer)
    policy = Map.put(valid_retry_policy_json(), "max_retries", -1)

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(
             reasons,
             &(&1 =~ ~r/'max_retries' is required and must be a positive integer, 0 or null/)
           ),
           "Expected max_retries error for zero value"

    # Test retry_timeout validation
    policy = Map.put(valid_retry_policy_json(), "retry_timeout", "not_an_integer")

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(
             reasons,
             &(&1 =~ ~r/'retry_timeout' is required and must be a positive integer/)
           ),
           "Expected retry_timeout error for non-integer value"

    # Test retry_timeout = 0 (non-positive)
    policy = Map.put(valid_retry_policy_json(), "retry_timeout", 0)

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(
             reasons,
             &(&1 =~ ~r/'retry_timeout' is required and must be a positive integer/)
           ),
           "Expected retry_timeout error for zero value"

    # Test backoff_strategy validation
    policy = Map.put(valid_retry_policy_json(), "backoff_strategy", nil)

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(reasons, &(&1 =~ ~r/'backoff_strategy' is required/)),
           "Expected backoff_strategy required error"

    # Test backoff_strategy invalid value
    policy = Map.put(valid_retry_policy_json(), "backoff_strategy", "invalid_strategy")

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => policy
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

    assert Enum.any?(reasons, &(&1 =~ ~r/'backoff_strategy' must be one of/)),
           "Expected backoff_strategy invalid value error"
  end

  # --- Monitor Specific Config Schema Validations ---
  test "config: required field missing" do
    bad_config = Map.delete(valid_http_config_json(), "url")

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => bad_config,
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/config.url: is required but missing/))
  end

  test "config: unexpected field" do
    bad_config = Map.put(valid_http_config_json(), "unexpected_field", "value")

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => bad_config,
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/config: unexpected field 'unexpected_field'/))
  end

  # Type Validations

  test "config: validates type constraints" do
    # HTTP type validations
    http_tests = [
      {:url, 123, ~r/config.url: must be a string/},
      {:timeout, "string", ~r/config.timeout: must be an integer/},
      {:is_test, "string", ~r/config.is_test: must be a boolean/},
      {:headers, "string", ~r/config.headers: must be a map/}
    ]

    Enum.each(http_tests, fn {field, invalid_value, pattern} ->
      base_config = valid_http_config_json()
      bad_config = Map.put(base_config, Atom.to_string(field), invalid_value)

      config_json = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "m1",
              "type" => "http",
              "config" => bad_config,
              "retry_policy" => valid_retry_policy_json()
            }
          ]
        },
        "rules" => [%{"name" => "r1", "monitor" => "m1"}]
      }

      assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

      assert Enum.any?(reasons, &(&1 =~ pattern)),
             "Expected pattern #{inspect(pattern)} for field #{field}, got: #{inspect(reasons)}"
    end)

    # Custom type validations
    custom_tests = [
      {:port, "string", ~r/config.port: must be an integer/},
      {:endpoints, [%{not: "a string"}], ~r/config.endpoints\[0\]: must be a string/},
      {:level, "debug", ~r/config.level: must be one of/}
    ]

    Enum.each(custom_tests, fn {field, invalid_value, pattern} ->
      base_config = valid_custom_type_config_json()
      bad_config = Map.put(base_config, Atom.to_string(field), invalid_value)

      config_json = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "m1",
              "type" => "custom_type",
              "config" => bad_config,
              "retry_policy" => valid_retry_policy_json()
            }
          ]
        },
        "rules" => [%{"name" => "r1", "monitor" => "m1"}]
      }

      assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

      assert Enum.any?(reasons, &(&1 =~ pattern)),
             "Expected pattern #{inspect(pattern)} for field #{field}, got: #{inspect(reasons)}"
    end)
  end

  test "config: validates validation rules" do
    # HTTP validation rules
    http_validation_tests = [
      {:url, "ftp://example.com", ~r/config.url: must match pattern/},
      {:timeout, 50, ~r/config.timeout: must be >= 100/},
      {:timeout, 6000, ~r/config.timeout: must be <= 5000/}
    ]

    Enum.each(http_validation_tests, fn {field, invalid_value, pattern} ->
      base_config = valid_http_config_json()
      bad_config = Map.put(base_config, Atom.to_string(field), invalid_value)

      config_json = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "m1",
              "type" => "http",
              "config" => bad_config,
              "retry_policy" => valid_retry_policy_json()
            }
          ]
        },
        "rules" => [%{"name" => "r1", "monitor" => "m1"}]
      }

      assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

      assert Enum.any?(reasons, &(&1 =~ pattern)),
             "Expected pattern #{inspect(pattern)} for field #{field}, got: #{inspect(reasons)}"
    end)

    # Custom type validation rules
    custom_validation_tests = [
      {:port, 8081, ~r/config.port: custom validation failed - port must be 8080/}
    ]

    Enum.each(custom_validation_tests, fn {field, invalid_value, pattern} ->
      base_config = valid_custom_type_config_json()
      bad_config = Map.put(base_config, Atom.to_string(field), invalid_value)

      config_json = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "m1",
              "type" => "custom_type",
              "config" => bad_config,
              "retry_policy" => valid_retry_policy_json()
            }
          ]
        },
        "rules" => [%{"name" => "r1", "monitor" => "m1"}]
      }

      assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())

      assert Enum.any?(reasons, &(&1 =~ pattern)),
             "Expected pattern #{inspect(pattern)} for field #{field}, got: #{inspect(reasons)}"
    end)
  end

  test "config: default values are applied" do
    config_no_defaults = %{"url" => "http://default.com", "timeout" => 300}

    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => config_no_defaults,
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [%{"name" => "r1", "monitor" => "m1"}]
    }

    assert {:ok, [monitor]} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert monitor.monitor_config.method == "GET"
    assert monitor.monitor_config.is_test == false
  end

  # --- Rules and inform_to Logic ---
  test "error if top-level 'rules' is not a list" do
    config_json = %{"monitors" => %{"single" => []}, "rules" => "not_a_list"}
    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/Top-level 'rules' must be a list/))
  end

  test "error if a rule entry is not a map or missing 'name' or 'monitor' for linking" do
    rule_base = %{
      "name" => "m1",
      "type" => "http",
      "config" => valid_http_config_json(),
      "retry_policy" => valid_retry_policy_json()
    }

    config1 = %{"monitors" => %{"single" => [rule_base]}, "rules" => ["not_a_map"]}
    assert {:error, r1} = ConfigValidator.validate_config(config1, mock_schemas())
    assert Enum.any?(r1, &(&1 =~ ~r/Rule entry must be a map/))

    config2 = %{"monitors" => %{"single" => [rule_base]}, "rules" => [%{"monitor" => "m1"}]}
    assert {:error, r2} = ConfigValidator.validate_config(config2, mock_schemas())
    assert Enum.any?(r2, &(&1 =~ ~r/must have a non-empty string 'name' field for linking/))

    config3 = %{"monitors" => %{"single" => [rule_base]}, "rules" => [%{"name" => "r1"}]}
    assert {:error, r3} = ConfigValidator.validate_config(config3, mock_schemas())
    assert Enum.any?(r3, &(&1 =~ ~r/Rule 'r1' must have a 'monitor' field .* for linking/))

    config4 = %{
      "monitors" => %{"single" => [rule_base]},
      "rules" => [%{"name" => "r1", "monitor" => 123}]
    }

    assert {:error, r4} = ConfigValidator.validate_config(config4, mock_schemas())
    assert Enum.any?(r4, &(&1 =~ ~r/Rule 'r1' must have a 'monitor' field .* for linking/))
  end

  test "error if a valid monitor is not targeted by any rule" do
    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "http1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => valid_retry_policy_json()
          },
          %{
            "name" => "http2",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [
        %{"name" => "rule_for_http1", "monitor" => "http1"}
        # http2 is not targeted
      ]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/Monitor 'http2' is not targeted by any rule/))
  end

  test "monitor targeted by a rule with list of monitors gets informed" do
    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => [%{"name" => "rule_group", "monitor" => ["m1", "m2"]}]
    }

    assert {:ok, [monitor]} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert "rule_group" in monitor.inform_to
  end

  # --- Edge Cases & Aggregation ---
  test "handles empty monitors list" do
    config_json = %{"monitors" => %{"single" => []}, "rules" => []}
    assert {:ok, []} = ConfigValidator.validate_config(config_json, mock_schemas())
  end

  test "handles empty rules list (monitors will error due to no targeting)" do
    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => valid_http_config_json(),
            "retry_policy" => valid_retry_policy_json()
          }
        ]
      },
      "rules" => []
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/Monitor 'm1' is not targeted by any rule/))
  end

  test "aggregates multiple errors correctly" do
    config_json = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "bad_http",
            "type" => "http",
            "config" => %{"url" => 123},
            "retry_policy" => %{"max_retries" => 0}
          },
          %{
            "name" => "ok_custom",
            "type" => "custom_type",
            "config" => valid_custom_type_config_json(),
            "retry_policy" => valid_retry_policy_json()
          }
          # ok_custom will error because it's not targeted by any rule
        ]
      },
      # Malformed rule
      "rules" => [%{"name" => "r_bad", "monitor" => %{}}]
    }

    assert {:error, reasons} = ConfigValidator.validate_config(config_json, mock_schemas())
    assert Enum.any?(reasons, &(&1 =~ ~r/Monitor 'bad_http'.*config.url: must be a string/))

    assert Enum.any?(
             reasons,
             &(&1 =~ ~r/Rule 'UNKNOWN' must have a 'monitor' field .* for linking/)
           )

    assert Enum.any?(reasons, &(&1 =~ ~r/Monitor 'ok_custom' is not targeted by any rule/))
    # Ensure errors are unique if they happen to be duplicated before uniq
    assert length(Enum.uniq(reasons)) == length(reasons)
  end
end
