defmodule Argos.Monitors.StateManager do
  @moduledoc """
  StateManager is responsible for managing the state of all monitors in the Argos system.
  It handles state persistence, versioning, consistency validation, and access control.

  ## Responsibilities:
  - Monitor state persistence
  - State versioning and history
  - State consistency validation
  - State access control
  - Historical data management
  - Error history tracking
  - Connection state synchronization
  """

  use GenServer
  alias Argos.Types
  require Logger

  @type monitor_id :: String.t()
  @type state_version :: integer()
  @type state_history :: %{required(state_version()) => Types.monitor_state()}

  @type init_config :: %{
    monitor_id: String.t(),
    retry_policy: Types.retry_policy(),
    base_monitor_pid: pid()
  }

  @type error_history :: [Types.error_info()]

  @type state :: %{
    required(monitor_id()) => %{
      retry_policy: Types.retry_policy(),
      base_monitor_pid: pid(),
      current: Types.monitor_state() | nil,
      history: state_history(),
      error_history: error_history(),
      version: state_version(),
      connection_metadata: %{
        status: Types.connection_status(),
        last_updated: DateTime.t()
      }
    }
  }

  # Client API

  @doc """
  Starts the StateManager process.

  ## Options
  - `:name` - The name to register the process under. Defaults to __MODULE__
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Initializes state for a new monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  - `init_params` - Initial monitor parameters including retry policy, and base monitor pid
  """
  @spec init_state(GenServer.server(), monitor_id(), init_config()) :: :ok | {:error, term()}
  def init_state(pid, monitor_id, init_params) do
    GenServer.call(pid, {:init_state, monitor_id, init_params})
  end

  @doc """
  Updates the state for an existing monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  - `new_state` - New monitor state following the normalize format
  """
  @spec update_state(GenServer.server(), monitor_id(), Types.normalized_data()) :: :ok | {:error, term()}
  def update_state(pid, monitor_id, new_state) do
    GenServer.call(pid, {:update_state, monitor_id, new_state})
  end

  @doc """
  Retrieves the current state of a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  """
  @spec get_state(GenServer.server(), monitor_id()) :: {:ok, Types.monitor_state()} | {:error, :not_found}
  def get_state(pid, monitor_id) do
    GenServer.call(pid, {:get_state, monitor_id})
  end

  @doc """
  Retrieves a specific version of a monitor's state.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  - `version` - The version number to retrieve
  """
  @spec get_state_version(GenServer.server(), monitor_id(), state_version()) ::
    {:ok, Types.monitor_state()} | {:error, :not_found | :version_not_found}
  def get_state_version(pid, monitor_id, version) do
    GenServer.call(pid, {:get_state_version, monitor_id, version})
  end

  @doc """
  Updates the error history for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  - `error` - Error information to add to history
  """
  @spec add_error(GenServer.server(), monitor_id(), Types.error_info()) :: :ok | {:error, term()}
  def add_error(pid, monitor_id, error) do
    GenServer.cast(pid, {:add_error, monitor_id, error})
  end

  @doc """
  Updates the connection status for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  - `status` - New connection status
  """
  @spec update_connection_status(GenServer.server(), monitor_id(), Types.connection_status()) :: :ok | {:error, term()}
  def update_connection_status(pid, monitor_id, status) do
    GenServer.cast(pid, {:update_connection_status, monitor_id, status})
  end

  @doc """
  Gets the connection metadata for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor
  """
  @spec get_connection_metadata(GenServer.server(), monitor_id()) ::
    {:ok, %{status: Types.connection_status(), last_updated: DateTime.t()}} | {:error, :not_found}
  def get_connection_metadata(pid, monitor_id) do
    GenServer.call(pid, {:get_connection_metadata, monitor_id})
  end

  @doc """
  Gets the initialization configuration for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor

  ## Returns
  - `{:ok, init_config}` - The monitor's complete initialization configuration including:
    - retry_policy: The retry policy
    - base_monitor_pid: PID of the base monitor process
  - `{:error, :not_found}` - If the monitor doesn't exist
  """
  @spec get_init_config(GenServer.server(), monitor_id()) :: {:ok, init_config()} | {:error, :not_found}
  def get_init_config(pid, monitor_id) do
    GenServer.call(pid, {:get_init_config, monitor_id})
  end

  @doc """
  Removes all state for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor to clean up
  """
  @spec cleanup_state(GenServer.server(), monitor_id()) :: :ok
  def cleanup_state(pid, monitor_id) do
    GenServer.call(pid, {:cleanup_state, monitor_id})
  end

  @doc """
  Gets the error history for a monitor.

  ## Parameters
  - `pid` - The StateManager process pid
  - `monitor_id` - Unique identifier for the monitor

  ## Returns
  - `{:ok, error_history}` - List of errors for the monitor
  - `{:error, :not_found}` - If the monitor doesn't exist
  """
  @spec get_error_history(GenServer.server(), monitor_id()) :: {:ok, error_history()} | {:error, :not_found}
  def get_error_history(pid, monitor_id) do
    GenServer.call(pid, {:get_error_history, monitor_id})
  end

  # Server Callbacks

  @impl true
  def init(state) do
    Logger.info("[StateManager] Initializing state manager with initial state: #{inspect(state)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:init_state, monitor_id, %{
    retry_policy: retry_policy,
    base_monitor_pid: base_monitor_pid
  }}, _from, state) do
    Logger.debug("[StateManager] Initializing state for monitor #{monitor_id}")
    Logger.debug("[StateManager] Retry policy: #{inspect(retry_policy)}")
    Logger.debug("[StateManager] Base monitor PID: #{inspect(base_monitor_pid)}")

    if Map.has_key?(state, monitor_id) do
      Logger.warning("[StateManager] Monitor #{monitor_id} already exists with state: #{inspect(Map.get(state, monitor_id))}")
      {:reply, {:error, :already_exists}, state}
    else
      new_monitor_state = %{
        retry_policy: retry_policy,
        base_monitor_pid: base_monitor_pid,
        current: nil,
        history: %{},
        version: 1,
        error_history: [],
        connection_metadata: %{
          status: :disconnected,
          last_updated: DateTime.utc_now()
        }
      }
      Logger.info("[StateManager] Successfully initialized state for monitor #{monitor_id} with state: #{inspect(new_monitor_state)}")
      {:reply, :ok, Map.put(state, monitor_id, new_monitor_state)}
    end
  end

  @impl true
  def handle_call({:update_state, monitor_id, normalized_data}, _from, state) do
    Logger.debug("[StateManager] Updating state for monitor #{monitor_id}")
    Logger.debug("[StateManager] Normalized data: #{inspect(normalized_data)}")

    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found for state update")
        {:reply, {:error, :not_found}, state}
      monitor_state ->
        next_version = monitor_state.version + 1
        Logger.debug("[StateManager] Current state for #{monitor_id}: #{inspect(monitor_state)}")
        Logger.debug("[StateManager] Incrementing version to #{next_version} for monitor #{monitor_id}")

        # Create new state preserving config and retry policy
        updated_monitor = %{
          monitor_state |
          current: normalized_data,
          history: Map.put(monitor_state.history, next_version, normalized_data),
          version: next_version,
          connection_metadata: normalized_data.meta,
          error_history: []
        }

        Logger.info("[StateManager] Successfully updated state for monitor #{monitor_id}")
        Logger.debug("[StateManager] New state: #{inspect(updated_monitor)}")
        {:reply, :ok, Map.put(state, monitor_id, updated_monitor)}
    end
  end

  @impl true
  def handle_call({:get_state, monitor_id}, _from, state) do
    Logger.debug("[StateManager] Getting current state for monitor #{monitor_id}")
    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found")
        {:reply, {:error, :not_found}, state}
      monitor_state ->
        Logger.debug("[StateManager] Retrieved state for monitor #{monitor_id}: #{inspect(monitor_state.current)}")
        {:reply, {:ok, monitor_state.current}, state}
    end
  end

  @impl true
  def handle_call({:get_state_version, monitor_id, version}, _from, state) do
    with {:ok, monitor_state} <- Map.fetch(state, monitor_id),
         {:ok, versioned_state} <- Map.fetch(monitor_state.history, version) do
      {:reply, {:ok, versioned_state}, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      _ -> {:reply, {:error, :version_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_error_history, monitor_id}, _from, state) do
    Logger.debug("[StateManager] Getting error history for monitor #{monitor_id}")
    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found when getting error history")
        {:reply, {:error, :not_found}, state}
      monitor_state ->
        history_size = length(monitor_state.error_history)
        Logger.debug("[StateManager] Retrieved error history for monitor #{monitor_id}")
        Logger.debug("[StateManager] Error history size: #{history_size}")
        Logger.debug("[StateManager] Error history: #{inspect(monitor_state.error_history)}")
        {:reply, {:ok, monitor_state.error_history}, state}
    end
  end

  @impl true
  def handle_cast({:add_error, monitor_id, error}, state) when not is_nil(error) do
    Logger.debug("[StateManager] Adding error for monitor #{monitor_id}")
    Logger.debug("[StateManager] Error details: #{inspect(error)}")

    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found when adding error")
        {:noreply, state}
      monitor_state ->
        next_version = monitor_state.version + 1
        updated_errors = [error | monitor_state.error_history]
        Logger.debug("[StateManager] Current error history: #{inspect(monitor_state.error_history)}")
        Logger.debug("[StateManager] Updated error history size: #{length(updated_errors)}")

        # Update current state with error
        updated_current = %{monitor_state.current |
          error: error,
          data: nil,
          status: :error
        }
        Logger.debug("[StateManager] Updated current state: #{inspect(updated_current)}")

        # Update monitor state with new error history and metadata
        updated_monitor = %{monitor_state |
          error_history: updated_errors,
          current: updated_current,
          version: next_version,
          connection_metadata: %{
            status: :error,
            last_updated: DateTime.utc_now()
          }
        }

        Logger.info("[StateManager] Successfully added error for monitor #{monitor_id}")
        Logger.debug("[StateManager] Final state after error: #{inspect(updated_monitor)}")
        {:noreply, Map.put(state, monitor_id, updated_monitor)}
    end
  end

  def handle_cast({:add_error, monitor_id, nil}, state) do
    Logger.warning("[StateManager] Attempted to add nil error for monitor #{monitor_id}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_init_config, monitor_id}, _from, state) do
    Logger.debug("[StateManager] Getting init config for monitor #{monitor_id}")
    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found when getting init config")
        {:reply, {:error, :not_found}, state}
      monitor_state ->
        init_config = %{
          retry_policy: monitor_state.retry_policy,
          base_monitor_pid: monitor_state.base_monitor_pid
        }
        Logger.debug("[StateManager] Retrieved init config for monitor #{monitor_id}: #{inspect(init_config)}")
        {:reply, {:ok, init_config}, state}
    end
  end

  @impl true
  def handle_call({:cleanup_state, monitor_id}, _from, state) do
    Logger.info("[StateManager] Cleaning up state for monitor #{monitor_id}")
    case Map.get(state, monitor_id) do
      nil ->
        Logger.warning("[StateManager] Monitor #{monitor_id} not found during cleanup")
      monitor_state ->
        Logger.debug("[StateManager] Cleaning up state: #{inspect(monitor_state)}")
    end
    {:reply, :ok, Map.delete(state, monitor_id)}
  end
end
