defmodule Argos.Monitors.MqttMonitorTest do
  use ExUnit.Case
  require Logger
  @moduletag :capture_log

  test "mqtt monitor subscribes and logs normalized output" do
    config = %{
      monitor_id: "test_mqtt_sub",
      host: "localhost",
      port: 1883,
      topics: ["test/topic1"],
      interval: 1000
    }
    pid = start_supervised!({Argos.Monitors.MqttMonitor, config})
    assert Process.alive?(pid)
    # Wait for at least one poll
    :timer.sleep(1500)
    # No assertion on output, but should see log in captured log
  end

  test "mqtt_monitor_detects_published_message" do
    topic1 = "test/topic2"
    topic2 = "test/topic1"
    payload = "hello_mqtt_monitor_detects_published_message"
    config = %{
      monitor_id: "test_mqtt_pub",
      host: "localhost",
      port: 1883,
      topics: [topic1, topic2],
      interval: 1000
    }

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        pid = start_supervised!({Argos.Monitors.MqttMonitor, config})
        assert Process.alive?(pid)
        # Give the monitor time to subscribe
        :timer.sleep(1500)
        # Publish a message to the topic
        :os.cmd(to_charlist("mosquitto_pub -h localhost -p 1883 -t #{topic1} -m #{payload}"))
        :os.cmd(to_charlist("mosquitto_pub -h localhost -p 1883 -t #{topic2} -m #{payload}"))
        # Wait for the monitor to (potentially) log the message
        :timer.sleep(1500)
      end)
    assert log =~ "Received message on [\"test\", \"topic1\"]: \"#{payload}\""
    assert log =~ "Received message on [\"test\", \"topic2\"]: \"#{payload}\""
  end
end
