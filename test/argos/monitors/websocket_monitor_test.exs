defmodule Argos.Monitors.WebSocketMonitorTest do
  use ExUnit.Case
  @moduletag :capture_log

  test "websocket monitor connects and logs normalized output" do
    config = %{
      monitor_id: "test_ws",
      url: "ws://localhost:8081",
      topics: ["test/topic1", "test/topic2"],
      retry_policy: %{
        max_retries: 1,
        retry_timeout: 1000,
        backoff_strategy: :exponential
      }
    }
    pid = start_supervised!({Argos.Monitors.WebSocketMonitor, config})
    assert Process.alive?(pid)
    # Wait for at least one poll
    :timer.sleep(1500)
    # No assertion on output, but should see log in captured log
  end

  test "websocket monitor detects echoed message" do
    payload = "hello_ws_websocket_monitor_detects_echoed_message"
    config = %{
      monitor_id: "test_ws_echo",
      url: "ws://localhost:8081",
      interval: 1000
    }
    IO.puts("wscat -c ws://localhost:8081 -x #{payload}")
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        pid = start_supervised!({Argos.Monitors.WebSocketMonitor, config})
        assert Process.alive?(pid)
        # Give the monitor time to connect
        :timer.sleep(1000)
        # Send a message to the echo server using wscat (must be installed)
        :os.cmd("wscat -c ws://localhost:8081 -x #{payload}")
        # Wait for the monitor to (potentially) log the message
        :timer.sleep(1500)
      end)
    IO.puts("log: #{log}")
    assert log =~ payload
  end
end
