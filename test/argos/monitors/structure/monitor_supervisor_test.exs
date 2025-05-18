defmodule Argos.Monitors.MonitorSupervisorTest do
  use ExUnit.Case, async: false
  require Logger

  alias Argos.Monitors.{
    MonitorSupervisor,
    StateManager,
    ErrorHandler,
    ConfigValidator
  }

  # Mock HTTP Monitor implementation for testing
  defmodule MockHTTPMonitor do
    @behaviour Argos.Monitors.MonitorProtocol
    use GenServer

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    @impl true
    def init(config) do
      {:ok, config}
    end

    @impl true
    def config_schema do
      %{
        type: :http,
        description: "HTTP Monitor for Testing",
        fields: [
          %{
            name: :url,
            type: :string,
            required: true,
            description: "The URL to monitor",
            validation: %{pattern: ~r/^https?:\/\/.+/}
          },
          %{
            name: :method,
            type: :string,
            required: true,
            description: "HTTP method to use",
            validation: %{pattern: ~r/^(GET|POST|PUT|DELETE)$/}
          },
          %{
            name: :interval,
            type: :integer,
            required: true,
            description: "Polling interval in ms",
            validation: %{min: 1000, max: 3_600_000}
          }
        ]
      }
    end

    @impl true
    def init_monitor(config) do
      # Validate retry policy first
      with {:ok, _} <- ConfigValidator.validate_retry_policy(config.retry_policy) do
        {:ok, config}
      else
        {:error, reason} -> {:error, reason}
      end
    end

    @impl true
    def recover(_recovery_action) do
      :ok
    end
  end

  setup do
    # Start the supervisor with its children
    # MonitorSupervisor will automatically start StateManager and ErrorHandler
    start_supervised!(MonitorSupervisor)

    # Define test configuration
    config = %{
      id: "test_http_monitor",
      type: :http,
      url: "https://api.example.com/test",
      method: "GET",
      interval: 5000,
      retry_policy: %{
        max_retries: 3,
        backoff_strategy: :exponential,
        retry_timeout: 1000
      }
    }

    # Set up mocking
    :ok = :meck.new(MonitorSupervisor, [:passthrough])
    :ok = :meck.expect(MonitorSupervisor, :get_protocol_monitor, fn
      :http -> {:ok, MockHTTPMonitor}
      _ -> {:error, :not_found}
    end)

    on_exit(fn ->
      # Ensure meck is unloaded even if test fails
      :meck.unload()
    end)

    {:ok, config: config}
  end

  describe "start_monitor/1" do
    test "successfully initializes an HTTP monitor with valid config", %{config: config} do
      # Start the monitor
      assert {:ok, base_pid} = MonitorSupervisor.start_monitor(config)

      # Verify BaseMonitor process is running
      assert Process.alive?(base_pid)

      # Verify StateManager has the monitor state
      assert {:ok, state} = StateManager.get_state(StateManager, config.id)
      assert state.monitor_id == config.id
      assert state.config.url == config.url
      assert state.connection_status == :disconnected
      assert state.error_history == []

      # Verify retry policy was validated and stored
      assert state.retry_policy.max_retries == 3
      assert state.retry_policy.backoff_strategy == :exponential
      assert state.retry_policy.retry_timeout == 1000

      # Verify ErrorHandler is running
      assert Process.whereis(ErrorHandler) != nil
    end

    test "handles invalid configuration", %{config: config} do
      # Create invalid config by removing required field
      invalid_config = Map.delete(config, :url)

      # Attempt to start monitor with invalid config
      assert {:error, reason} = MonitorSupervisor.start_monitor(invalid_config)
      assert is_binary(reason)
      assert String.contains?(reason, "Required field url is missing")

      # Verify no state was created
      assert {:error, :not_found} = StateManager.get_state(StateManager, invalid_config.id)
    end

    test "handles invalid URL format", %{config: config} do
      # Create config with invalid URL
      invalid_config = %{config | url: "not_a_url"}

      # Attempt to start monitor with invalid URL
      assert {:error, reason} = MonitorSupervisor.start_monitor(invalid_config)
      assert is_binary(reason)
      assert String.contains?(reason, "does not match pattern")

      # Verify no state was created
      assert {:error, :not_found} = StateManager.get_state(StateManager, invalid_config.id)
    end

    test "handles invalid retry policy", %{config: config} do
      # Test cases for invalid retry policies
      invalid_retry_policies = [
        %{config | retry_policy: %{max_retries: 0}},
        %{config | retry_policy: %{max_retries: 3, backoff_strategy: :invalid}},
        %{config | retry_policy: %{max_retries: 3, backoff_strategy: :exponential, retry_timeout: 0}},
        %{config | retry_policy: Map.delete(config.retry_policy, :backoff_strategy)}
      ]

      for invalid_config <- invalid_retry_policies do
        # Attempt to start monitor with invalid retry policy
        assert {:error, reason} = MonitorSupervisor.start_monitor(invalid_config)
        assert is_binary(reason)
        assert String.contains?(reason, "Invalid retry policy")

        # Verify no state was created
        assert {:error, :not_found} = StateManager.get_state(StateManager, invalid_config.id)
      end
    end
  end
end
