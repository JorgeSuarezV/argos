defmodule Argos.Monitors.MonitorSupervisor do
  @moduledoc """
  Supervisor responsible for managing monitor processes and their dependencies.
  It handles:
  - Monitor configuration validation
  - Component initialization (BaseMonitor, StateManager, ErrorHandler)
  - Protocol monitor registration and validation
  - Error handling and reporting
  """

  use Supervisor
  require Logger

  alias Argos.Monitors.{
    BaseMonitor,
    StateManager,
    ErrorHandler,
    ConfigValidator,
    Registry
  }

  @type monitor_config :: map()
  @type monitor_type :: atom()

  # Client API

  @doc """
  Starts the monitor supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts multiple monitors from a configuration map following the technical requirements format.
  The configuration map should have the following structure:
  %{
    "monitors" => %{
      "single" => [
        %{
          "name" => String.t(),
          "type" => String.t(),
          "config" => map(),
          "retry_policy" => map()
        },
        ...
      ]
    }
  }
  """
  @spec start_monitors(map()) :: {:ok, [pid()]} | {:error, term()}
  def start_monitors(%{"monitors" => %{"single" => monitors}}) do
    results = Enum.map(monitors, fn monitor ->
      # Convert the monitor config to our internal format
      retry_policy = Map.new(monitor["retry_policy"], fn
        {"backoff_strategy", v} -> {:backoff_strategy, String.to_atom(v)}
        {k, v} -> {String.to_atom(k), v}
      end)

      config = %{
        id: monitor["name"],
        type: String.to_atom(monitor["type"]),
        retry_policy: retry_policy
      }
      |> Map.merge(Map.new(monitor["config"], fn {k, v} -> {String.to_atom(k), v} end))

      start_monitor(config)
    end)

    # Check if any monitor failed to start
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, pid} -> pid end)}
      error -> error
    end
  end

  def start_monitors(_), do: {:error, "Invalid monitor configuration format"}

  @doc """
  Starts a new monitor with the given configuration.
  """
  @spec start_monitor(monitor_config()) :: {:ok, pid()} | {:error, term()}
  def start_monitor(config) do
    with {:ok, protocol_monitor} <- get_protocol_monitor(config.type),
         {:ok, _} <- validate_retry_policy(config),
         {:ok, validated_config} <- validate_monitor_config(protocol_monitor, config) do
      start_monitor_components(validated_config, protocol_monitor)
    else
      {:error, reason} = error ->
        report_error(config, reason)
        error
    end
  end

  @doc """
  Gets the protocol monitor module for a given type.
  """
  @spec get_protocol_monitor(monitor_type()) :: {:ok, module()} | {:error, String.t()}
  def get_protocol_monitor(type) when is_atom(type) do
    case Registry.get_monitor(type) do
      {:ok, module} = result ->
        if Registry.implements_protocol?(module), do: result, else: {:error, "Invalid monitor implementation"}
      error -> error
    end
  end

  # Supervisor Callbacks

  @impl true
  def init(_init_arg) do
    children = [
      # Start StateManager with registered name
      %{
        id: StateManager,
        start: {StateManager, :start_link, [[name: StateManager]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },
      # Start ErrorHandler with registered name
      %{
        id: ErrorHandler,
        start: {ErrorHandler, :start_link, [[name: ErrorHandler]]},
        type: :worker,
      restart: :permanent,
        shutdown: 5000
      }
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end

  # Private Functions

  defp validate_retry_policy(config) do
    case ConfigValidator.validate_retry_policy(config.retry_policy) do
      {:ok, validated_policy} -> {:ok, Map.put(config, :retry_policy, validated_policy)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_monitor_config(protocol_monitor, config) do
    # Get schema from protocol monitor and validate config
    schema = protocol_monitor.config_schema()
    ConfigValidator.validate_schema(schema, config)
  end

  defp start_monitor_components(config, protocol_monitor) do
    monitor_id = config.id

    # Create protocol monitor config
    protocol_config = config  # BaseMonitor will inject base_monitor_pid

    # Start the BaseMonitor with protocol config
    case BaseMonitor.start_link(monitor_id, protocol_monitor, protocol_config) do
      {:ok, base_pid} -> {:ok, base_pid}
      error -> error
    end
  end


  defp report_error(config, reason) do
    error_report = %{
      timestamp: DateTime.utc_now(),
      monitor_id: config[:id],
      type: config[:type],
      error: %{
        type: :initialization,
        message: "Failed to start monitor",
        details: %{
          reason: reason,
          config: config
        }
      }
    }

    # Log the error
    Logger.error("[MonitorSupervisor] Monitor initialization failed: #{inspect(error_report)}")
  end
end
