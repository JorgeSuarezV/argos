defmodule Argos.Monitors.Protocol.HTTPMonitor do
  @moduledoc """
  HTTP protocol implementation for the monitor system.
  Periodically makes HTTP requests to configured endpoints and sends the results
  to the system for processing.
  """

  use Argos.Monitors.MonitorProtocol, type: :http

  @type http_config :: %{
    base_monitor_pid: pid(),
    type: :http,
    url: String.t(),
    method: String.t(),
    headers: %{optional(String.t()) => String.t()},
    interval: pos_integer(),
    timeout: pos_integer(),
    follow_redirect: boolean(),
    verify_ssl: boolean(),
    request_body: String.t() | map() | nil
  }

  @impl Argos.Monitors.MonitorProtocol
  def config_schema do
    [
      %{
        name: :url,
        type: :string,
        required: true,
        description: "The URL to fetch data from",
        validation: %{pattern: ~r/^https?:\/\/.+/}
      },
      %{
        name: :method,
        type: :string,
        required: false,
        default: "GET",
        description: "HTTP method to use"
      },
      %{
        name: :headers,
        type: :map,
        required: false,
        default: %{},
        description: "HTTP headers to send with the request"
      },
      %{
        name: :interval,
        type: :integer,
        required: true,
        description: "Time between requests in milliseconds",
        validation: %{min: 1000, max: 3_600_000}
      },
      %{
        name: :timeout,
        type: :integer,
        required: false,
        default: 5000,
        description: "Request timeout in milliseconds",
        validation: %{min: 100, max: 30_000}
      },
      %{
        name: :follow_redirect,
        type: :boolean,
        required: false,
        default: true,
        description: "Whether to follow HTTP redirects"
      },
      %{
        name: :verify_ssl,
        type: :boolean,
        required: false,
        default: false,
        description: "Whether to verify SSL certificates"
      },
      %{
        name: :request_body,
        type: :map,
        required: false,
        default: nil,
        description: "Body to send with POST/PUT requests"
      }
    ]
  end

  @impl GenServer
  @spec init(any()) ::
          {:ok, %{client: HTTPoison, config: any(), last_request: nil, timer_ref: reference()}}
          | {:stop, <<_::64, _::_*8>>}
  def init(config) do
    # Initialize the HTTP client
    case HTTPoison.start() do
      {:ok, _} ->
        state = %{
          config: config,
          client: HTTPoison,
          last_request: nil,
          timer_ref: schedule_next_request(0)
        }
        {:ok, state}
      {:error, reason} ->
        {:stop, "Failed to initialize HTTP client: #{inspect(reason)}"}
    end
  end

  @impl GenServer
  def handle_info(:fetch_data, state) do
    # Make the HTTP request
    response = make_request(state)

    # Normalize the response
    normalized = case response do
      %{error: true} = error ->
        Argos.Monitors.Normalize.output(
          monitor_id: state.config.id,
          status: :error,
          error: %{
            type: :network,
            message: "HTTP request failed",
            details: %{reason: error.reason},
            timestamp: DateTime.utc_now(),
            stacktrace: nil
          },
          meta: %{
            status: :error,
            last_success: nil
          }
        )
      response ->
        Argos.Monitors.Normalize.output(
          monitor_id: state.config.id,
          status: :ok,
          data: response,
          meta: %{
            status: :connected,
            last_success: DateTime.utc_now()
          }
        )
    end

    # Schedule next request only if no error
    timer_ref = case normalized do
      %{error: error} when not is_nil(error) ->
        Argos.Monitors.BaseMonitor.handle_error(state.config.base_monitor_pid, normalized)
        nil
      _ ->
        Argos.Monitors.BaseMonitor.handle_data(state.config.base_monitor_pid, normalized)
        schedule_next_request(state.config.interval)
    end

    {:noreply, %{state | last_request: DateTime.utc_now(), timer_ref: timer_ref}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Cancel any pending timer
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    # Let the process terminate normally
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_cast({:recover, %{command: :shutdown}}, state) do
    # Cancel any pending timer
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    # Let the process terminate normally
    {:stop, :normal, state}
  end

  def handle_cast({:recover, %{command: :retry, delay: delay}}, state) when not is_nil(delay) do
    # Cancel any existing timer
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    # Schedule next request after delay
    timer_ref = schedule_next_request(delay)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @spec recover(%{:command => :shutdown, optional(any()) => any()}) :: :ok
  def recover(%{command: :shutdown}) do
    # Cancel any pending timers
    if Process.get(:timer_ref), do: Process.cancel_timer(Process.get(:timer_ref))

    # Let the process terminate normally
    Process.exit(self(), :normal)
    :ok
  end

  # Private Functions

  defp make_request(state) do
    %{config: config} = state

    options = [
      follow_redirect: config.follow_redirect,
      ssl: [verify: if(config.verify_ssl, do: :verify_peer, else: :verify_none)],
      timeout: config.timeout,
      recv_timeout: config.timeout
    ]

    case state.client.request(
      config.method,
      config.url,
      config.request_body || "",
      config.headers,
      options
    ) do
      {:ok, %HTTPoison.MaybeRedirect{redirect_url: redirect_url, status_code: status_code}} ->
        # We get MaybeRedirect when:
        # 1. follow_redirect is true but method/status combination isn't auto-followed
        # 2. follow_redirect is false and we got a redirect
        %{
          error: true,
          reason: "HTTP #{status_code} redirect to #{redirect_url} not followed"
        }

      {:ok, response} ->
        if response.status_code >= 200 and response.status_code < 300 do
          # Only 2xx is guaranteed success
          %{
            status_code: response.status_code,
            body: response.body,
            headers: Map.new(response.headers)
          }
        else
          # If we got a response that's not 2xx and not a MaybeRedirect,
          # it must be 4xx or 5xx since 3xx would have been MaybeRedirect
          %{
            error: true,
            reason: "HTTP #{response.status_code}: #{response.body}"
          }
        end

      {:error, reason} ->
        %{
          error: true,
          reason: inspect(reason)
        }
    end
  end

  defp schedule_next_request(interval) do
    IO.puts("Scheduling next request in #{interval} milliseconds #{System.system_time(:millisecond)}")
    Process.send_after(self(), :fetch_data, interval)
  end
end
