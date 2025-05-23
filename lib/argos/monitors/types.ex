defmodule Argos.Monitors.Types do
  @moduledoc """
  Types for the monitor system.

  """

  @type backoff_strategy :: :fixed | :linear | :exponential

  @type config_schema :: [config_field()]

  @type error_response_type :: :retry | :stop

  @type error_response :: %{
          type: error_response_type(),
          delay: pos_integer()
        }

  @typedoc """
  Configuration field definition
  """
  @type config_field :: %{
          required(:name) => atom(),
          required(:type) => config_field_type(),
          optional(:required) => boolean(),
          optional(:default) => term(),
          optional(:description) => String.t(),
          optional(:validation) => validation_rules()
        }

  @type monitor_config :: %{
          id: String.t(),
          base_monitor_pid: pid(),
          config: config_schema()
        }

  @type base_monitor_config :: %{
          monitor_id: String.t(),
          monitor_type: atom(),
          monitor_module: atom(),
          retry_policy: retry_policy(),
          inform_to: [String.t()],
          monitor_config: monitor_config()
        }

  @typedoc """
  Supported configuration field types
  """
  @type config_field_type ::
          :string
          | :integer
          | :float
          | :boolean
          | :map
          | {:list, config_field_type()}
          | {:enum, [atom() | String.t() | number()]}

  @typedoc """
  Validation rules for configuration fields
  """
  @type validation_rules :: %{
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:pattern) => String.t(),
          optional(:custom) => (term() -> :ok | {:error, String.t()})
        }

  @type retry_policy :: %{
          max_retries: pos_integer(),
          backoff_strategy: backoff_strategy(),
          retry_timeout: pos_integer()
        }

  @type monitor_response :: monitor_success_response() | monitor_error_response()

  @type monitor_success_response :: %{
          timestamp: DateTime.t(),
          monitor_id: String.t(),
          base_monitor_pid: pid(),
          data: Map.t()
        }

  @type monitor_error_response :: %{
          timestamp: DateTime.t(),
          monitor_id: String.t(),
          base_monitor_pid: pid(),
          error: Map.t()
        }
end

defmodule Argos.Monitors.SuccessResponse do
  @moduledoc "Struct for a successful monitor response"
  defstruct [:timestamp, :monitor_id, :base_monitor_pid, :data]
end

defmodule Argos.Monitors.ErrorResponse do
  @moduledoc "Struct for an error monitor response"
  defstruct [:timestamp, :monitor_id, :base_monitor_pid, :error]
end

defmodule Argos.Monitors.Types.Backoff do
  @type backoff_strategy :: :fixed | :linear | :exponential

  @spec parse_strategy(String.t()) :: backoff_strategy()
  def parse_strategy("fixed"), do: :fixed
  def parse_strategy("linear"), do: :linear
  def parse_strategy("exponential"), do: :exponential

  def parse_strategy(other) do
    raise ArgumentError, "unknown backoff strategy #{inspect(other)}"
  end
end
