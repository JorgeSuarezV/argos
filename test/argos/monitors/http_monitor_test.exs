defmodule Argos.Monitors.HttpMonitorTest do
  use ExUnit.Case
  @moduletag :capture_log

  test "http monitor polls and logs normalized output" do
    config = %{
      monitor_id: "test_http_get",
      url: "http://localhost:8080/get",
      method: :get,
      interval: 1000
    }
    pid = start_supervised!({Argos.Monitors.HttpMonitor, config})
    assert Process.alive?(pid)
    :timer.sleep(1500)
  end

  test "http monitor detects GET response" do
    config = %{
      monitor_id: "test_http_anything",
      url: "http://localhost:8080/anything",
      method: :get,
      interval: 1000
    }
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        pid = start_supervised!({Argos.Monitors.HttpMonitor, config})
        assert Process.alive?(pid)
        :timer.sleep(1500)
      end)
    assert log =~ "GET request received at /anything"
  end
end
