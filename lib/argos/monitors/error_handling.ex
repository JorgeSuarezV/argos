defmodule Argos.Monitors.ErrorHandling do
  alias Argos.Monitors.Types

  @spec handle_error(Types.retry_policy(), pos_integer()) ::
          {:ok, Types.error_response_type()}
  def handle_error(retry_policy, retry_count) do
    if retry_count >= retry_policy.max_retries do
      {:ok, :stop}
    else
      delay =
        calculate_delay(retry_policy.backoff_strategy, retry_policy.retry_timeout, retry_count)

      Process.sleep(delay)
      {:ok, :retry}
    end
  end

  defp calculate_delay(backoff_strategy, retry_timeout, retry_count) do
    case backoff_strategy do
      :fixed -> retry_timeout
      :linear -> retry_timeout * retry_count
      :exponential -> retry_timeout * :math.pow(2, retry_count)
    end
  end
end
