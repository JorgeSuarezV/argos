defmodule Argos.Monitors.Normalize do





  @moduledoc """
  Helper for normalizing monitor outputs in Argos.

  All monitor outputs should use this module to ensure a consistent, extensible format.

  ## Output Format

      %{
        monitor_id: String.t(),         # Required, unique per monitor instance
        timestamp: DateTime.t(),        # Always present, UTC ISO8601
        status: atom(),                 # Required, e.g. :ok, :error, :timeout, etc.
        data: map() | nil,              # Normalized, protocol-agnostic result
        error: map() | nil,             # Normalized error info, if any
        connection_metadata: map()                     # Open for extension: connection_status, last_updated, custom fields, etc.
      }

  - No protocol field or closed enums.
  - All fields are always present (with `nil` if not applicable).
  - `connection_metadata` is always a map, defaulting to `%{}`.
  """

  alias Argos.Types

  @type normalized_success :: %{
    monitor_id: String.t(),
    timestamp: DateTime.t(),
    status: :ok,
    data: map(),
    meta: %{
      status: Types.connection_status(),
      last_success: DateTime.t()
    }
  }

  @type normalized_error :: %{
    monitor_id: String.t(),
    timestamp: DateTime.t(),
    status: :error,
    error: Types.error_info(),
    meta: %{
      status: :error,
      last_success: DateTime.t() | nil
    }
  }

  @type normalized_output :: normalized_success() | normalized_error()

  @doc """
  Normalizes monitor output for reporting, logging, and rule/action processing.

  ## Options
    - :monitor_id (required, string)
    - :status (required, :ok | :error)
    - :data (map, required for success case)
    - :error (map, required for error case)
    - :meta (map, required with appropriate fields for each case)

  Returns a normalized output map with all required fields and a UTC ISO8601 timestamp.
  """
  @spec output(Keyword.t() | map()) :: Types.normalized_data()
  def output(opts) when is_list(opts), do: output(Map.new(opts))
  def output(%{monitor_id: monitor_id, status: :ok, data: data, meta: meta}) when is_map(data) and is_map(meta) do
    %{
      monitor_id: monitor_id,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: :ok,
      data: data,
      meta: validate_success_meta(meta)
    }
  end
  def output(%{monitor_id: monitor_id, status: :error, error: error, meta: meta}) when is_map(error) and is_map(meta) do
    %{
      monitor_id: monitor_id,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: :error,
      error: error,
      meta: validate_error_meta(meta)
    }
  end
  def output(_), do: raise(ArgumentError, "invalid normalized output format")

  # Private Functions

  defp validate_success_meta(%{status: status, last_success: last_success} = meta)
       when (status == :connected or status == :disconnected or status == :error) and
            (is_struct(last_success, DateTime) or is_nil(last_success)) do
    meta
  end
  defp validate_success_meta(_), do: raise(ArgumentError, "invalid success metadata format")

  defp validate_error_meta(%{status: :error, last_success: last_success} = meta)
       when is_struct(last_success, DateTime) or is_nil(last_success) do
    meta
  end
  defp validate_error_meta(_), do: raise(ArgumentError, "invalid error metadata format")
end
