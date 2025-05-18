defmodule Argos.Monitors.BaseMonitor do
  @moduledoc """
  Base monitor behavior that coordinates between protocol monitors, error handling,
  and state management. This module is stateless and acts as a coordinator between
  different components of the monitoring system.
  """

  use GenServer
  require Logger
  alias Argos.Monitors.{StateManager, ErrorHandler}
  alias Argos.Types

  @type monitor_id :: String.t()
  @type protocol_monitor :: module()
  @type normalized_data :: Types.normalized_data()
  @type recovery_action :: Types.recovery_action()

  # Client API
  @doc """
  Starts a base monitor coordinator and initializes its protocol monitor.
  """
  def start_link(monitor_id, protocol_monitor, protocol_config) do
    Logger.info("[BaseMonitor] Starting base monitor for #{monitor_id} with protocol #{protocol_monitor}")
    GenServer.start_link(__MODULE__, {monitor_id, protocol_monitor, protocol_config})
  end

  @doc """
  Handles incoming data from protocol monitors.
  """
  def handle_data(pid, data) do
    Logger.debug("[BaseMonitor] Received data request for pid #{inspect(pid)}")
    GenServer.cast(pid, {:handle_data, data})
  end

  @doc """
  Handles error reports from protocol monitors.
  """
  @spec handle_error(atom() | pid() | {atom(), any()} | {:via, atom(), any()}, any()) :: :ok
  def handle_error(pid, error) do
    Logger.debug("[BaseMonitor] Received error request for pid #{inspect(pid)}")
    GenServer.cast(pid, {:handle_error, error})
  end

  # Server Callbacks

  @impl true
  def init({monitor_id, protocol_monitor, protocol_config}) do
    Logger.debug("[BaseMonitor] Initializing monitor #{monitor_id}")
    # First initialize state in StateManager with empty current state
    init_params = %{
      monitor_id: monitor_id,
      retry_policy: protocol_config.retry_policy,
      base_monitor_pid: self()
    }

    case StateManager.init_state(StateManager, monitor_id, init_params) do
      :ok ->
        Logger.debug("[BaseMonitor] State initialized for #{monitor_id}, starting protocol monitor")
        # Now start protocol monitor with updated config including base_monitor_pid
        protocol_config = Map.put(protocol_config, :base_monitor_pid, self())

        case protocol_monitor.start_link(protocol_config) do
          {:ok, protocol_pid} ->
            Logger.debug("[BaseMonitor] Protocol monitor started successfully for #{monitor_id}")
            # Initialize empty state in StateManager
            initial_state = %{
              monitor_id: monitor_id,
              status: :ok,
              data: nil,
              error: nil,
              meta: %{
                status: :initialized,
                last_success: nil
              }
            }
            :ok = StateManager.update_state(StateManager, monitor_id, initial_state)

            state = %{
              monitor_id: monitor_id,
              protocol_monitor: protocol_monitor,
              protocol_pid: protocol_pid
            }
            Logger.info("[BaseMonitor] Monitor #{monitor_id} initialized successfully")
            {:ok, state}

          {:error, reason} = error ->
            Logger.error("[BaseMonitor] Failed to start protocol monitor for #{monitor_id}: #{inspect(reason)}")
            # Clean up any initialized state
            :ok = StateManager.cleanup_state(StateManager, monitor_id)
            {:stop, error}
        end

      {:error, reason} = error ->
        Logger.error("[BaseMonitor] Failed to initialize state for #{monitor_id}: #{inspect(reason)}")
        {:stop, error}
    end
  end

  @impl true
  def handle_cast({:handle_data, %{data: data, monitor_id: monitor_id} = normalized_data}, state) when not is_nil(data) do
    Logger.debug("[BaseMonitor] Processing data message for #{monitor_id}: #{inspect(normalized_data)}")
    # Update state in StateManager for success case
    :ok = StateManager.update_state(StateManager, monitor_id, normalized_data)
    Logger.info("[BaseMonitor] Successfully processed data for monitor #{monitor_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:handle_data, %{error: error, monitor_id: monitor_id} = normalized_data}, state) when not is_nil(error) do
    Logger.debug("[BaseMonitor] Processing error in data message for #{monitor_id}: #{inspect(normalized_data)}")
    # Forward to error handler
    handle_error_with_recovery(normalized_data, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:handle_error, error}, state) do
    Logger.debug("[BaseMonitor] Processing error message for #{state.monitor_id}: #{inspect(error)}")
    handle_error_with_recovery(error, state)
    {:noreply, state}
  end

  # Private Functions

  defp handle_error_with_recovery(normalized_data, state) do
    Logger.debug("[BaseMonitor] Starting error recovery for #{state.monitor_id}")
    case ErrorHandler.handle_error(ErrorHandler, normalized_data) do
      {:ok, %{command: :retry} = recovery_action} ->
        Logger.info("[BaseMonitor] Executing retry recovery for #{state.monitor_id} with action: #{inspect(recovery_action)}")
        # Send recovery action to protocol monitor via cast
        GenServer.cast(state.protocol_pid, {:recover, recovery_action})
        {:noreply, state}

      {:ok, %{command: :shutdown}} ->
        Logger.info("[BaseMonitor] Executing shutdown recovery for #{state.monitor_id}")
        # Send shutdown to protocol monitor and wait for it to terminate
        ref = Process.monitor(state.protocol_pid)
        GenServer.cast(state.protocol_pid, {:recover, %{command: :shutdown}})

        receive do
          {:DOWN, ^ref, :process, _pid, _reason} ->
            Logger.debug("[BaseMonitor] Protocol monitor terminated gracefully for #{state.monitor_id}")
            # Protocol monitor terminated, clean up state and stop ourselves
            :ok = StateManager.cleanup_state(StateManager, state.monitor_id)
            {:stop, :normal, state}
        after
          5000 ->
            Logger.warning("[BaseMonitor] Protocol monitor failed to terminate gracefully for #{state.monitor_id}, forcing shutdown")
            # Force terminate protocol monitor if it doesn't shut down gracefully
            Process.exit(state.protocol_pid, :kill)
            :ok = StateManager.cleanup_state(StateManager, state.monitor_id)
            {:stop, :normal, state}
        end

      {:error, reason} ->
        Logger.error("[BaseMonitor] Error handling failed for monitor #{state.monitor_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[BaseMonitor] Terminating monitor #{state.monitor_id} with reason: #{inspect(reason)}")
    if state.protocol_pid && Process.alive?(state.protocol_pid) do
      Logger.debug("[BaseMonitor] Terminating protocol monitor process for #{state.monitor_id}")
      Process.exit(state.protocol_pid, :normal)
    end
    :ok
  end
end
