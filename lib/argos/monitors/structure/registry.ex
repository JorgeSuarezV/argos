defmodule Argos.Monitors.Registry do
  @moduledoc """
  Registry for monitor protocols and implementations.
  Handles monitor discovery, registration, and lookup.
  """

  @doc """
  Returns all modules that implement the MonitorProtocol.
  This function scans all loaded modules and finds those that implement
  the protocol, regardless of their location or application.
  """
  def discover_monitors do
    for {app, _, _} <- Application.loaded_applications(),
        {:ok, modules} <- [:application.get_key(app, :modules)],
        module <- List.wrap(modules),
        implements_protocol?(module),
        type = monitor_type(module),
        not is_nil(type) do
      {type, module}
    end
  end

  @doc """
  Gets a monitor module by its type.
  """
  def get_monitor(type) when is_atom(type) do
    case Enum.find(discover_monitors(), fn {t, _} -> t == type end) do
      {^type, module} -> {:ok, module}
      nil -> {:error, "Monitor type #{type} not found"}
    end
  end

  @doc """
  Validates that a module implements the MonitorProtocol correctly.
  """
  def implements_protocol?(module) do
    try do
      loaded = Code.ensure_loaded?(module)
      is_elixir = function_exported?(module, :__info__, 1)
      has_type = function_exported?(module, :__monitor_type__, 0)
      has_behaviour = if is_elixir, do: module.__info__(:attributes)[:behaviour], else: nil
      implements = has_behaviour && Argos.Monitors.MonitorProtocol in (has_behaviour || [])

      loaded && is_elixir && has_type && implements
    rescue
      _ -> false
    end
  end

  @doc """
  Gets the monitor type from a module.
  """
  def monitor_type(module) do
    try do
      module.__monitor_type__()
    rescue
      _ -> nil
    end
  end
end
