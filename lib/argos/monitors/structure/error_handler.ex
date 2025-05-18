defmodule Argos.Monitors.ErrorHandler do
  @moduledoc """
  ErrorHandler is responsible for centralized error handling across the Argos monitoring system.
  It manages error classification, recovery strategies, and retry policies.

  This is a stateless service that relies on StateManager for all state management.

  ## Responsibilities:
  - Error classification and categorization
  - Error recovery strategy execution
  - Error logging and monitoring
  - Retry policy enforcement
  """

  use GenServer
  require Logger
  alias Argos.Types
  alias Argos.Monitors.StateManager

  # Client API

  @doc """
  Starts the ErrorHandler process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    Logger.info("[ErrorHandler] Starting error handler process...")
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc """
  Handles an error from a monitor and determines the appropriate recovery action.
  """
  @spec handle_error(GenServer.server(), Types.normalized_data()) ::
    {:ok, Types.recovery_action()} | {:error, term()}
  def handle_error(server, normalized_data) do
    Logger.debug("[ErrorHandler] Handling error for monitor #{normalized_data.monitor_id}")
    GenServer.call(server, {:handle_error, normalized_data})
  end

  # Server Callbacks

  @impl true
  def init([]) do
    Logger.info("[ErrorHandler] Initialized with empty state")
    {:ok, []}
  end

  @impl true
  def handle_call({:handle_error, %{monitor_id: monitor_id, error: error} = normalized_data}, _from, state) when not is_nil(error) do
    Logger.debug("[ErrorHandler] Processing error for monitor #{monitor_id}: #{inspect(error)}")

    # Get current monitor state and retry policy from state manager
    case StateManager.get_init_config(StateManager, monitor_id) do
      {:ok, %{retry_policy: retry_policy}} ->
        Logger.debug("[ErrorHandler] Retrieved retry policy for #{monitor_id}: #{inspect(retry_policy)}")

        # Get current retry count from error history
        retry_count = case StateManager.get_error_history(StateManager, monitor_id) do
          {:ok, error_history} ->
            count = length(error_history)
            Logger.debug("[ErrorHandler] Current retry count for #{monitor_id}: #{count}")
            count
          {:error, :not_found} ->
            Logger.debug("[ErrorHandler] No error history found for #{monitor_id}")
            0
        end

        # Always log the error
        log_error(error, monitor_id)

        # Update error in state manager and connection status
        Logger.debug("[ErrorHandler] Adding error to state manager for #{monitor_id}")
        :ok = StateManager.add_error(StateManager, monitor_id, error)

        # Determine recovery action
        recovery_action = determine_recovery_action(error, retry_count, retry_policy, monitor_id)
        Logger.info("[ErrorHandler] Determined recovery action for #{monitor_id}: #{inspect(recovery_action)}")

        # Log critical error if shutting down
        if recovery_action.command == :shutdown do
          Logger.critical("[ErrorHandler] Monitor #{monitor_id} shutting down after #{retry_count} retries")
          # Clean up state if shutting down
          Logger.debug("[ErrorHandler] Cleaning up state for #{monitor_id}")
          :ok = StateManager.cleanup_state(StateManager, monitor_id)
        end

        {:reply, {:ok, recovery_action}, state}

      {:error, :not_found} ->
        Logger.error("[ErrorHandler] Monitor #{monitor_id} not found in state manager")
        {:reply, {:error, "Monitor #{monitor_id} not found"}, state}
    end
  end
  def handle_call({:handle_error, normalized_data}, _from, state) do
    Logger.error("[ErrorHandler] Invalid normalized data format: #{inspect(normalized_data)}")
    {:reply, {:error, "Invalid normalized data format: #{inspect(normalized_data)}"}, state}
  end

  # Private Functions

  defp log_error(error, monitor_id) do
    Logger.warning(
      "[ErrorHandler] Monitor error: #{inspect(error)} | Monitor ID: #{monitor_id}"
    )
  end

  defp determine_recovery_action(_error, retry_count, retry_policy, monitor_id) do
    max_retries = Map.get(retry_policy, :max_retries, 3)
    backoff_strategy = Map.get(retry_policy, :backoff_strategy, "exponential")
    base_timeout = Map.get(retry_policy, :retry_timeout, 1000)

    Logger.debug("[ErrorHandler] Calculating recovery action with retry_count: #{retry_count}, max_retries: #{max_retries} for monitor #{monitor_id}")

    if retry_count < max_retries do
      delay = calculate_backoff(backoff_strategy, base_timeout, retry_count + 1, monitor_id)
      Logger.debug("[ErrorHandler] Calculated retry delay: #{delay}ms using #{backoff_strategy} strategy for monitor #{monitor_id}")
      %{
        command: :retry,
        delay: delay
      }
    else
      Logger.debug("[ErrorHandler] Max retries reached, initiating shutdown for monitor #{monitor_id}")
      %{command: :shutdown, delay: nil}
    end
  end

  defp calculate_backoff(strategy, base, attempt, monitor_id) do
    delay = case strategy do
      :fixed -> base
      :linear -> base * attempt
      :exponential -> base * :math.pow(2, attempt - 1) |> round
    end
    Logger.debug("[ErrorHandler] Calculated backoff delay: #{delay}ms for attempt #{attempt} using #{strategy} strategy for monitor #{monitor_id}")
    delay
  end
end
