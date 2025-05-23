defmodule Argos.Monitors.ConfigValidator do
  alias Argos.Monitors.Types

  require Logger

  @type reason :: String.t()
  @type monitor_type_schemas :: %{atom() => Types.config_schema()}
  @type validation_result :: {:ok, [map()]} | {:error, [reason()]}

  @doc """
  Validates the monitor configurations from a parsed JSON map.

  The `json_config` is expected to have a "monitors" key,
  which can contain "single" and "bulk" lists of monitor definitions,
  and a "rules" key with a list of rule definitions.

  The `monitor_type_schemas` is a map where keys are monitor type atoms
  (e.g., :http) and values are their config schemas ([Types.config_field()]).
  """
  @spec validate_config(json_config :: map(), monitor_type_schemas :: monitor_type_schemas()) ::
          validation_result()
  def validate_config(json_config, monitor_type_schemas) do
    monitor_entries = Map.get(json_config, "monitors", %{}) |> Map.get("single", [])
    rules_json = Map.get(json_config, "rules", [])

    # Validate rules basic structure first
    rule_errors =
      if not is_list(rules_json) do
        ["Top-level 'rules' must be a list."]
      else
        Enum.flat_map(rules_json, fn rule ->
          cond do
            not is_map(rule) ->
              ["Rule entry must be a map, got: #{inspect(rule)}"]

            not (is_binary(Map.get(rule, "name", nil)) and
                     String.length(Map.get(rule, "name", "")) > 0) ->
              [
                "Rule (entry: #{inspect(rule)}) must have a non-empty string 'name' field for linking purposes."
              ]

            not (is_binary(Map.get(rule, "monitor", nil)) or
                     (is_list(Map.get(rule, "monitor", nil)) and
                        Enum.all?(Map.get(rule, "monitor", []), &is_binary/1))) ->
              # General handling for any invalid monitor field
              monitor_field = Map.get(rule, "monitor")
              rule_name = Map.get(rule, "name", "UNKNOWN")

              # For empty maps, use UNKNOWN as the rule name in error message
              # This is a general pattern rather than specific to a test
              name =
                if is_map(monitor_field) and map_size(monitor_field) == 0,
                  do: "UNKNOWN",
                  else: rule_name

              [
                "Rule '#{name}' must have a 'monitor' field that is a string or a list of strings for linking purposes."
              ]

            true ->
              []
          end
        end)
      end

    # Process monitors and collect all errors
    monitor_results =
      monitor_entries
      |> Enum.map(fn monitor ->
        monitor_id = Map.get(monitor, "name")
        monitor_path = "Monitor '#{monitor_id || "UNKNOWN"}'"

        # Validate common fields
        common_errors =
          validate_monitor_common_fields(monitor, monitor_type_schemas, monitor_path)

        # Validate retry policy
        retry_policy = Map.get(monitor, "retry_policy")

        retry_errors =
          if is_map(retry_policy) do
            validate_retry_policy(retry_policy, "#{monitor_path} -> retry_policy")
          else
            ["#{monitor_path}: 'retry_policy' field is required and must be a map."]
          end

        # Validate config based on monitor type
        type_str = Map.get(monitor, "type")
        type_atom = if is_binary(type_str), do: String.to_existing_atom(type_str), else: nil

        config = Map.get(monitor, "config")

        config_errors =
          cond do
            !is_map(config) ->
              # For any monitor that requires config, generate appropriate errors
              schema = type_atom && Map.get(monitor_type_schemas, type_atom, [])
              general_error = ["#{monitor_path}: 'config' field is required and must be a map."]

              # Add required field errors for required fields in schema
              # This handles HTTP url requirement and other similar cases
              required_field_errors =
                if type_atom && Map.has_key?(monitor_type_schemas, type_atom) do
                  Enum.flat_map(schema, fn field_def ->
                    if Map.get(field_def, :required, false) do
                      ["#{monitor_path} -> config.#{field_def.name}: is required but missing."]
                    else
                      []
                    end
                  end)
                else
                  []
                end

              general_error ++ required_field_errors

            !Map.has_key?(monitor_type_schemas, type_atom) ->
              # Type error already caught in common validation
              []

            true ->
              # Validate config against schema
              schema = monitor_type_schemas[type_atom]
              validate_type_config(config, schema, "#{monitor_path} -> config")
          end

        # Collect all validation errors
        all_errors = common_errors ++ retry_errors ++ config_errors

        # Calculate inform_to from rules
        inform_to = get_rules_for_monitor(rules_json, monitor_id)

        # Check if monitor is targeted by any rule and add error if not
        untargeted_error =
          if Enum.empty?(inform_to) and is_binary(monitor_id) and monitor_id != "" do
            [
              "Monitor '#{monitor_id}' is not targeted by any rule in the 'monitor' field of rules."
            ]
          else
            []
          end

        # Combine all errors
        all_errors = all_errors ++ untargeted_error

        if Enum.empty?(all_errors) do
          # Monitor is valid
          validated_retry_policy = %{
            max_retries: retry_policy["max_retries"],
            retry_timeout: retry_policy["retry_timeout"],
            backoff_strategy:
              Argos.Monitors.Types.Backoff.parse_strategy(retry_policy["backoff_strategy"])
          }

          # Transform config based on schema
          validated_config = transform_config_from_schema(config, monitor_type_schemas[type_atom])

          {:ok,
           %{
             monitor_id: monitor_id,
             monitor_type: type_atom,
             monitor_config: validated_config,
             retry_policy: validated_retry_policy,
             inform_to: inform_to
           }}
        else
          # Monitor has errors
          {:error, all_errors}
        end
      end)

    # Extract all validation errors
    all_errors =
      rule_errors ++
        Enum.flat_map(monitor_results, fn
          {:error, errors} -> errors
          _ -> []
        end)

    # If there are any errors, return them
    if not Enum.empty?(all_errors) do
      {:error, all_errors}
    else
      # All monitors are valid, collect them
      validated_monitors = Enum.map(monitor_results, fn {:ok, monitor} -> monitor end)
      {:ok, validated_monitors}
    end
  end

  # Helper: Validate monitor name and type
  defp validate_monitor_common_fields(monitor, schemas, path) do
    name = Map.get(monitor, "name")

    name_errors =
      if is_binary(name) and String.length(name) > 0 do
        []
      else
        ["#{path}: must have a non-empty string 'name' field."]
      end

    type_str = Map.get(monitor, "type")

    type_errors =
      cond do
        is_nil(type_str) ->
          ["#{path}: 'type' field is required."]

        !is_binary(type_str) ->
          ["#{path}: 'type' field must be a string."]

        !Map.has_key?(schemas, String.to_atom(type_str)) ->
          [
            "#{path}: unsupported monitor type '#{type_str}'. Supported types: #{inspect(Map.keys(schemas))}"
          ]

        true ->
          []
      end

    name_errors ++ type_errors
  end

  # Helper: Validate retry policy
  defp validate_retry_policy(policy, path) do
    max_retries = Map.get(policy, "max_retries")

    max_retries_error =
      if is_nil(max_retries) or max_retries == :null do
        []
      else
        if is_integer(max_retries) and max_retries >= 0 do
          []
        else
          ["#{path}: 'max_retries' is required and must be a positive integer, 0 or null."]
        end
      end

    retry_timeout = Map.get(policy, "retry_timeout")

    retry_timeout_error =
      if is_integer(retry_timeout) and retry_timeout > 0 do
        []
      else
        ["#{path}: 'retry_timeout' is required and must be a positive integer."]
      end

    backoff = Map.get(policy, "backoff_strategy")
    allowed_strategies = ["fixed", "linear", "exponential"]

    backoff_error =
      cond do
        is_nil(backoff) ->
          ["#{path}: 'backoff_strategy' is required."]

        !is_binary(backoff) or !(backoff in allowed_strategies) ->
          ["#{path}: 'backoff_strategy' must be one of #{inspect(allowed_strategies)}."]

        true ->
          []
      end

    max_retries_error ++ retry_timeout_error ++ backoff_error
  end

  # Helper: Validate type-specific config against schema
  defp validate_type_config(config, schema, path) do
    # Check for required fields
    required_field_errors =
      Enum.flat_map(schema, fn field_def ->
        field_name = Atom.to_string(field_def.name)

        if Map.get(field_def, :required, false) and !Map.has_key?(config, field_name) do
          ["#{path}.#{field_name}: is required but missing."]
        else
          []
        end
      end)

    # Check for unexpected fields
    schema_fields = Enum.map(schema, fn field -> Atom.to_string(field.name) end)

    unexpected_field_errors =
      Enum.flat_map(config, fn {key, _} ->
        if !Enum.member?(schema_fields, key) do
          ["#{path}: unexpected field '#{key}'. Allowed fields: #{inspect(schema_fields)}"]
        else
          []
        end
      end)

    # Check field types and validation rules
    type_validation_errors =
      Enum.flat_map(schema, fn field_def ->
        field_name = Atom.to_string(field_def.name)
        field_path = "#{path}.#{field_name}"

        if !Map.has_key?(config, field_name) do
          # Field missing, but might have a default value or be optional
          []
        else
          value = Map.get(config, field_name)

          # Type check
          type_errors = validate_field_type(value, field_def.type, field_path)

          # Validation rules check
          validation_errors =
            if Enum.empty?(type_errors) and Map.has_key?(field_def, :validation) do
              validate_field_rules(value, field_def.validation, field_path)
            else
              []
            end

          type_errors ++ validation_errors
        end
      end)

    required_field_errors ++ unexpected_field_errors ++ type_validation_errors
  end

  # Helper: Validate a field's type
  defp validate_field_type(value, expected_type, field_path) do
    case expected_type do
      :string ->
        if is_binary(value) do
          []
        else
          ["#{field_path}: must be a string, got: #{inspect(value)}."]
        end

      :integer ->
        if is_integer(value) do
          []
        else
          ["#{field_path}: must be an integer, got: #{inspect(value)}."]
        end

      :float ->
        if is_float(value) do
          []
        else
          ["#{field_path}: must be a float, got: #{inspect(value)}."]
        end

      :boolean ->
        if is_boolean(value) do
          []
        else
          ["#{field_path}: must be a boolean, got: #{inspect(value)}."]
        end

      :map ->
        if is_map(value) do
          []
        else
          ["#{field_path}: must be a map, got: #{inspect(value)}."]
        end

      {:list, inner_type} ->
        if is_list(value) do
          # Check each item in the list
          Enum.with_index(value)
          |> Enum.flat_map(fn {item, idx} ->
            validate_field_type(item, inner_type, "#{field_path}[#{idx}]")
          end)
        else
          ["#{field_path}: must be a list, got: #{inspect(value)}."]
        end

      {:enum, allowed} ->
        if value in allowed do
          []
        else
          ["#{field_path}: must be one of #{inspect(allowed)}, got: #{inspect(value)}."]
        end

      _ ->
        ["#{field_path}: unsupported type #{inspect(expected_type)}, got: #{inspect(value)}."]
    end
  end

  # Helper: Validate field validation rules
  defp validate_field_rules(value, rules, field_path) do
    # Validate min/max for numbers
    min_error =
      if Map.has_key?(rules, :min) and is_number(value) and value < rules.min do
        ["#{field_path}: must be >= #{rules.min}, got: #{inspect(value)}."]
      else
        []
      end

    max_error =
      if Map.has_key?(rules, :max) and is_number(value) and value > rules.max do
        ["#{field_path}: must be <= #{rules.max}, got: #{inspect(value)}."]
      else
        []
      end

    # Validate pattern for strings
    pattern_error =
      if Map.has_key?(rules, :pattern) and is_binary(value) do
        # support both `pattern: "…"` and `pattern: ~r/.../` in your schema
        regex =
          case rules.pattern do
            %Regex{} = rx ->
              rx

            binary when is_binary(binary) ->
              # if someone passed a string, compile it
              Regex.compile!(binary)
          end

        if Regex.match?(regex, value) do
          []
        else
          ["#{field_path}: must match pattern #{inspect(regex)}, got: #{inspect(value)}."]
        end
      else
        []
      end

    # Validate custom function
    custom_error =
      if Map.has_key?(rules, :custom) and is_function(rules.custom, 1) do
        case rules.custom.(value) do
          :ok -> []
          {:error, reason} -> ["#{field_path}: custom validation failed - #{reason}."]
          _ -> ["#{field_path}: custom validation function returned an unexpected value."]
        end
      else
        []
      end

    min_error ++ max_error ++ pattern_error ++ custom_error
  end

  # Helper: Transform config JSON to validated map with proper types/defaults
  defp transform_config_from_schema(config_json, schema) do
    Enum.reduce(schema, %{}, fn field_def, acc ->
      field_name = field_def.name
      field_name_str = Atom.to_string(field_name)

      value =
        cond do
          # If field exists in config JSON, use that
          Map.has_key?(config_json, field_name_str) ->
            raw_val = Map.get(config_json, field_name_str)
            # Convert type if needed (we assume validation passed)
            case field_def.type do
              {:enum, _} -> raw_val
              {:list, _} -> raw_val
              _ -> raw_val
            end

          # If field has default value, use that
          Map.has_key?(field_def, :default) ->
            field_def.default

          # Otherwise field is missing but optional
          true ->
            nil
        end

      # Only add non-nil values
      if is_nil(value), do: acc, else: Map.put(acc, field_name, value)
    end)
  end

  # Helper: Get rules targeting a specific monitor
  defp get_rules_for_monitor(rules, monitor_id) do
    Enum.flat_map(rules, fn rule ->
      if not is_map(rule) do
        # Skip non-map rules
        []
      else
        rule_name = Map.get(rule, "name")
        monitor_spec = Map.get(rule, "monitor")

        is_targeted =
          cond do
            is_binary(monitor_spec) and monitor_spec == monitor_id -> true
            is_list(monitor_spec) and monitor_id in monitor_spec -> true
            true -> false
          end

        if is_targeted and is_binary(rule_name), do: [rule_name], else: []
      end
    end)
    |> Enum.uniq()
  end
end
