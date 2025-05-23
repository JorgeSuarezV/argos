defmodule Argos.HttpMonitorInitTest do
  use ExUnit.Case, async: true
  require Logger


  setup do
    # Start the registry for this test
    start_supervised!({Registry, keys: :duplicate, name: :argos_rules_registry})

    # Start the MockRule
    mock_rule_pid = start_supervised!(Argos.Rules.MockRule)

    {:ok, mock_rule_pid: mock_rule_pid}
  end

  test "init/1", %{mock_rule_pid: mock_rule_pid} do
    config = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => %{
              "url" => "http://localhost:8080/success",
              "timeout" => 1000,
              "interval" => 1000
            },
            "retry_policy" => %{
              "max_retries" => 3,
              "retry_timeout" => 1000,
              "backoff_strategy" => "fixed"
            }
          }
        ]
      },
      "rules" => [
        %{
          "name" => "mock_rule",
          "monitor" => "m1"
        }
      ]
    }

    assert {:ok, pid} = Argos.Monitors.MonitorSupervisor.start_link(config)

    # Just wait a short time for any async operations
    Process.sleep(1000)

    state = GenServer.call(mock_rule_pid, {:get_data, nil})
    assert state.data.data.status_code == 200
    assert state.data.data.body["message"] == "Success"
    assert state.data.data.body["status"] == "ok"
    assert state.data.monitor_id == "m1"

    # Clean up
    Process.exit(pid, :normal)
  end

  test "init/1 with error", %{mock_rule_pid: mock_rule_pid} do
    config = %{
      "monitors" => %{
        "single" => [
          %{
            "name" => "m1",
            "type" => "http",
            "config" => %{
              "url" => "http://localhost:8080/not_found",
              "timeout" => 1000,
              "interval" => 1000
            },
            "retry_policy" => %{
              "max_retries" => 3,
              "retry_timeout" => 1000,
              "backoff_strategy" => "fixed"
            }
          }
        ]
      },
      "rules" => [
        %{
          "name" => "mock_rule",
          "monitor" => "m1"
        }
      ]
    }


    assert {:ok, pid} = Argos.Monitors.MonitorSupervisor.start_link(config)

    # Just wait a short time for any async operations
    Process.sleep(1000)

    state = GenServer.call(mock_rule_pid, {:get_data, nil})
    Logger.info("state data#{inspect(state)}")
    assert state.error.error.details.status_code == 404
    assert state.error.error.details.body["message"] == "Not found"
    assert state.error.error.details.body["status"] == "error"
    assert state.error.monitor_id == "m1"
    end

end
