defmodule Argos.Rules.MockRule do
  @moduledoc """
  A mock rule process for testing monitor→rule dispatch.
  It registers under a hard-coded `rule_id` and logs all incoming data.
  """

  use GenServer
  require Logger

  @registry :argos_rules_registry
  @rule_id "mock_rule"

  ## Public API

  @doc """
  Start the mock rule process and register under the mock rule ID.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Returns the rule ID this process registered under.
  """
  def rule_id, do: @rule_id

  ## GenServer callbacks

  @impl true
  def init(_) do
    # Register this process under the mock rule ID
    case Registry.register(@registry, @rule_id, nil) do
      {:ok, _pid} ->
        Logger.info("[MockRule] Registered under rule_id=#{inspect(@rule_id)}")
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("[MockRule] Failed to register: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:monitor_data, data}, state) do
    Logger.info("[MockRule] Received monitor data: #{inspect(data)}")
    new_state = Map.put(state, :data, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:monitor_error, error}, state) do
    state = Map.put(state, :error, error)
    {:noreply, state}
  end

  def get_data(state) do
    GenServer.call(__MODULE__, {:get_data, nil})
  end

  @impl true
  def handle_call({:get_data, _}, _from, state) do
    {:reply, state, state}
  end
end
