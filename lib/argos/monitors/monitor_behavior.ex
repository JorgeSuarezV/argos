defmodule Argos.Monitors.Behavior do
  @moduledoc """
  This behaviour defines the contract that all monitor protocols must implement.

  Monitors have a single responsibility: gather data from their configured source
  based on their configuration (intervals, subscriptions, etc.) and send it to
  the system for processing.

  Monitors should:
  - Be implemented as proper OTP processes (usually GenServer)
  - Handle their own data gathering based on configuration
  - Send gathered data through the configured channel
  - Define their configuration schema through config_schema/0

  Monitors should not handle:
  - Connection management (handled by ConnectionManager)
  - Error handling (handled by ErrorHandler)
  - State management (handled by StateManager)
  - Retry logic (handled by the system)
  - Data normalization (handled by Normalize)

  For proper cleanup, monitors should implement the standard OTP lifecycle
  callbacks (terminate/2 for GenServer, etc.) to handle any necessary
  cleanup like closing connections or unsubscribing from topics.
  """

  alias Argos.Monitors.Types

  @doc """
  Returns all modules that implement this protocol.
  This is used by the supervisor to discover available monitor implementations.
  """
  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)

    quote do
      @behaviour Argos.Monitors.Behavior
      use GenServer

      @monitor_type unquote(type)
      Module.register_attribute(__MODULE__, :monitor_type, persist: true)

      def __monitor_type__, do: @monitor_type

      @spec start_link(Types.monitor_config()) :: GenServer.on_start()
      def start_link(config) do
        GenServer.start_link(__MODULE__, config)
      end

      @impl true
      def config_schema, do: raise("Monitor #{__MODULE__} must implement config_schema/0")

      defoverridable config_schema: 0
    end
  end

  @doc """
  Returns the configuration schema for this monitor type.
  This is used to validate configuration at load time and provide
  documentation about the required configuration.

  The schema defines:
  - Required and optional fields
  - Field types and validation rules
  - Default values
  - Field descriptions for documentation

  Example:
  ```
  def config_schema do
    %{
      type: :http,
      description: "HTTP endpoint monitor",
      fields: [
        %{
          name: :url,
          type: :string,
          required: true,
          description: "The URL to monitor",
          validation: %{pattern: ~r/^https?:\/\/.+/}
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
  ```
  """
  @callback config_schema() :: Types.config_schema()

  @doc """
  Executes a recovery action for the monitor.
  The recovery action specifies what the monitor should do to recover from an error,
  such as retrying after a delay or shutting down.

  The monitor should handle the recovery command appropriately based on its implementation.
  """
  @callback recover(Types.error_response_type()) :: :ok | {:error, String.t()}
end
