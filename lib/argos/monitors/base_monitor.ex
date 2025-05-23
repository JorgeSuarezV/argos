defmodule Argos.Monitors.BaseMonitor do
  @moduledoc """
  Base module for all monitors.
  """

  use GenServer
  require Logger

  alias Argos.Monitors.Types
  alias Argos.Monitors.ErrorHandling

  @registry :argos_rules_registry

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl GenServer
  @spec init(Types.base_monitor_config()) ::
          {:ok,
           %{
             inform_to: any(),
             monitor_id: any(),
             monitor_module: any(),
             monitor_pid: pid(),
             monitor_type: any(),
             retry_count: 0,
             retry_policy: any()
           }}
  def init(config) do
    # config is Types.base_monitor_config()
    # save monitor_id and retry_policy
    # save monitor_type and monitor_module
    Logger.info("BaseMonitor init #{inspect(self())}")
    monitor_config = Map.put(%{}, :id, config.monitor_id)
    monitor_config = Map.put(monitor_config, :base_monitor_pid, self())
    monitor_config = Map.put(monitor_config, :config, config.monitor_config)

    children = [
      %{
        id: config.monitor_id,
        start: {config.monitor_module, :start_link, [monitor_config]},
        restart: :transient,
        type: :worker
      }
    ]

    # monitor supervisor start and supervise the monitor
    {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)

    [{_, child_pid, :worker, _modules}] = Supervisor.which_children(sup_pid)

    {:ok,
     %{
       monitor_id: config.monitor_id,
       monitor_type: config.monitor_type,
       monitor_module: config.monitor_module,
       retry_policy: config.retry_policy,
       monitor_pid: child_pid,
       inform_to: config.inform_to,
       retry_count: 0
     }}
  end

  def handle_data(data) do
    GenServer.cast(self(), {:handle_data, data})
  end

  def handle_error(error) do
    GenServer.cast(self(), {:handle_error, error})
  end

  @impl GenServer
  def handle_info(message, state) do
    GenServer.cast(self(), {:handle_info, message})
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("BaseMonitor terminate #{inspect(self())}")
    Logger.info("BaseMonitor terminate reason: #{inspect(reason)}")
    # terminate the monitor
    Process.exit(state.monitor_pid, :normal)
    # terminate the supervisor
    Process.exit(self(), :normal)
    :ok
  end

  @impl GenServer
  def handle_cast({:handle_data, data}, state) do
    # send data to inform_to via registry
    inform_to_registry(state.inform_to, :monitor_data, data)

    Logger.info("Received data from monitor #{state.monitor_id}: #{inspect(data)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:handle_error, error}, state) do
    inform_to_registry(state.inform_to, :monitor_error, error)

    {:ok, error_response_type} =
      ErrorHandling.handle_error(state.retry_policy, state.retry_count)

    case error_response_type do
      :retry ->
        GenServer.cast(state.monitor_pid, {:recover, error_response_type})
        {:noreply, %{state | retry_count: state.retry_count + 1}}

      :stop ->
        terminate("max_retries_reached", state)
        {:stop, :normal, state}
    end
  end

  @impl GenServer
  def handle_cast({:handle_info, message}, state) do
    Logger.info("Received message in monitor #{state.monitor_id}: #{inspect(message)}")
    {:noreply, state}
  end


  defp inform_to_registry(rule_ids, message_type, data) do
    for rule_id <- rule_ids do
      Registry.dispatch(@registry, rule_id, fn entries ->
        for {pid, _} <- entries do
          send(pid, {message_type, data})
        end
      end)
    end
  end
end
