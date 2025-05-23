defmodule Argos.Monitors.MonitorSupervisor do
  use Supervisor

  alias Argos.Monitors.MonitorTypeRegistry
  alias Argos.Monitors.ConfigValidator

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config)
  end

  @impl Supervisor
  @spec init(Map.t()) :: any()
  def init(config) do
    module_map = MonitorTypeRegistry.discover_monitors_list()
    # create a map of type -> schema from the module_map (type -> module)
    config_schemas =
      Enum.map(module_map, fn {type, module} -> {type, module.config_schema()} end)
      |> Enum.into(%{})

    validation_result = ConfigValidator.validate_config(config, config_schemas)

    case validation_result do
      {:ok, validated_config} ->
        children =
          Enum.map(validated_config, fn monitor_config ->
            monitor_config =
              Map.put(monitor_config, :monitor_module, module_map[monitor_config.monitor_type])

            %{
              id: "base_monitor_#{monitor_config.monitor_id}",
              start: {Argos.Monitors.BaseMonitor, :start_link, [monitor_config]},
              restart: :transient,
              type: :worker
            }
          end)

        Supervisor.init(children, strategy: :one_for_one)

      {:error, reason_list} ->
        {:error, reason_list}
    end
  end
end
