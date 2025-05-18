defmodule Argos.Monitors.MonitorDiscovery do
  @moduledoc """
  This module handles the discovery of monitor implementations in the system.
  It uses module attributes to find all modules that implement the MonitorProtocol.
  """

  @doc """
  Returns a list of all available monitor modules and their types.
  """
  def available_monitors do
    :code.all_loaded()
    |> Enum.filter(&monitor_module?/1)
    |> Enum.map(fn {module, _} -> {module, get_monitor_type(module)} end)
    |> Enum.filter(fn {_module, type} -> type != nil end)
    |> Map.new()
  end

  @doc """
  Gets a monitor module for a specific type.
  """
  def get_monitor_module(type) when is_atom(type) do
    case Enum.find(available_monitors(), fn {_module, t} -> t == type end) do
      {module, _type} -> {:ok, module}
      nil -> {:error, :unknown_monitor_type}
    end
  end

  @doc """
  Returns true if the given type has a monitor implementation.
  """
  def monitor_type_exists?(type) when is_atom(type) do
    match?({:ok, _}, get_monitor_module(type))
  end

  # Private helpers

  defp monitor_module?({module, _}) do
    Code.ensure_loaded?(module) and has_monitor_attribute?(module)
  end

  defp has_monitor_attribute?(module) do
    attributes = module.__info__(:attributes)
    Keyword.has_key?(attributes, :monitor)
  end

  defp get_monitor_type(module) do
    case module.__info__(:attributes) do
      attributes when is_list(attributes) ->
        case Keyword.get(attributes, :monitor) do
          [type: type] -> type
          _ -> nil
        end
      _ -> nil
    end
  end
end
