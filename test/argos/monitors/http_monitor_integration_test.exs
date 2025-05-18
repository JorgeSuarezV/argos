defmodule Argos.Monitors.HttpMonitorIntegrationTest do
  use ExUnit.Case, async: false
  require Logger

  alias Argos.Monitors.{MonitorSupervisor, StateManager}

  describe "Basic HTTP monitor" do
    test "Simple HTTP monitor succeeds to make a request" do
      # Define test configurations
      config = %{
        "monitors" => %{
          "single" => [
            # Working HTTP monitor - should succeed
            %{
              "name" => "test_http_success",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/success",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 5000
              },
              "retry_policy" => %{
                "backoff_strategy" => "exponential",
                "max_retries" => 3,
                "retry_timeout" => 1000
              }
            }
          ]
        }
      }

      start_supervised!(MonitorSupervisor)
      {:ok, _pids} = MonitorSupervisor.start_monitors(config)

      # Wait for initial requests to complete
      Process.sleep(1000)

      # Check successful monitor
      assert {:ok, current_data} = StateManager.get_state(StateManager, "test_http_success")
      assert current_data.status == :ok
      assert current_data.data.status_code == 200
    end

    test "HTTP monitor fails immediately with no retries" do
      # Define test configuration for failing monitor
      failing_config = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "test_http_fail_immediate",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/not_found",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 1000
              },
              "retry_policy" => %{
                "backoff_strategy" => "linear",
                "max_retries" => 0,
                "retry_timeout" => 1000
              }
            }
          ]
        }
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_supervised!(MonitorSupervisor)
          {:ok, _pids} = MonitorSupervisor.start_monitors(failing_config)

          # Wait for initial request to complete
          Process.sleep(2000)
        end)

      IO.inspect("log: #{log}")

      assert log =~ "Monitor test_http_fail_immediate shutting down after 0 retries"

      # Check that monitor has shut down and state is cleaned up
      assert {:error, :not_found} =
               StateManager.get_state(StateManager, "test_http_fail_immediate")
    end

    test "HTTP monitor fails after 3 retries with linear backoff" do
      # Define test configuration for failing monitor
      failing_config = %{
        "monitors" => %{
          "single" => [
            %{
              "name" => "test_http_fail_retry",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/not_found",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 500
              },
              "retry_policy" => %{
                "backoff_strategy" => "fixed",
                "max_retries" => 3,
                "retry_timeout" => 1000
              }
            }
          ]
        }
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_supervised!(MonitorSupervisor)
          {:ok, _pids} = MonitorSupervisor.start_monitors(failing_config)

          Process.sleep(6000)
        end)

      IO.inspect("log: #{log}")
      assert log =~
               "[ErrorHandler] Calculated backoff delay: 1000ms for attempt 1 using fixed strategy"

      assert log =~
               "[ErrorHandler] Calculated backoff delay: 1000ms for attempt 2 using fixed strategy"

      assert log =~
               "[ErrorHandler] Calculated backoff delay: 1000ms for attempt 3 using fixed strategy"

      assert not (log =~
                    "[ErrorHandler] Calculated backoff delay: 1000ms for attempt 4 using fixed strategy")

      assert log =~ "Monitor test_http_fail_retry shutting down after 3 retries"

      assert {:error, :not_found} = StateManager.get_state(StateManager, "test_http_fail_retry")
    end

    test "multiple HTTP monitors handles success and failure scenarios correctly" do
      # Define test configurations
      multiple_config = %{
        "monitors" => %{
          "single" => [
            # Working HTTP monitor - should succeed
            %{
              "name" => "test_http_success",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/success",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 5000
              },
              "retry_policy" => %{
                "backoff_strategy" => "exponential",
                "max_retries" => 3,
                "retry_timeout" => 1000
              }
            },
            # Failing HTTP monitor - should fail immediately with no retries
            %{
              "name" => "test_http_fail_immediate",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/not_found",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 1000
              },
              "retry_policy" => %{
                "backoff_strategy" => "linear",
                "max_retries" => 0,
                "retry_timeout" => 1000
              }
            },
            # Failing HTTP monitor - should retry 3 times
            %{
              "name" => "test_http_fail_retry",
              "type" => "http",
              "config" => %{
                "url" => "http://localhost:8080/timeout",
                "method" => "GET",
                "interval" => 1000,
                "timeout" => 500
              },
              "retry_policy" => %{
                "backoff_strategy" => "fixed",
                "max_retries" => 3,
                "retry_timeout" => 3000
              }
            }
          ]
        }
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_supervised!(MonitorSupervisor)
          {:ok, _pids} = MonitorSupervisor.start_monitors(multiple_config)

          # Wait for initial requests to complete
          Process.sleep(2000)

          # Check successful monitor
          assert {:ok, current_data} = StateManager.get_state(StateManager, "test_http_success")
          assert current_data.status == :ok
          assert current_data.data.status_code == 200

          # Check immediate failure monitor
          assert {:error, :not_found} =
                   StateManager.get_state(StateManager, "test_http_fail_immediate")

          # Check retry failure monitor
          # Should still be running since only 2000ms have passed
          # assert {:ok, retry_state} = StateManager.get_state(StateManager, "test_http_fail_retry")
          # assert retry_state.current_data.status == :error
          # error_history = StateManager.get_error_history(StateManager, "test_http_fail_retry")
          # assert length(error_history) == 1

          Process.sleep(8000)
        end)



      assert log =~
               "[ErrorHandler] Calculated backoff delay: 3000ms for attempt 1 using fixed strategy for monitor test_http_fail_retry"

      assert log =~
               "[ErrorHandler] Calculated backoff delay: 3000ms for attempt 2 using fixed strategy for monitor test_http_fail_retry"

      assert log =~
               "[ErrorHandler] Calculated backoff delay: 3000ms for attempt 3 using fixed strategy for monitor test_http_fail_retry"

      assert not (log =~
                    "[ErrorHandler] Calculated backoff delay: 3000ms for attempt 4 using fixed strategy for monitor test_http_fail_retry")

      assert log =~ "Monitor test_http_fail_retry shutting down after 3 retries"
    end
  end
end
