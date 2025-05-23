defmodule Argos.Monitors.HttpMonitor do
  @moduledoc """
  HTTP Monitor that periodically makes HTTP requests to configured endpoints.
  This monitor conforms to the Argos.Monitors.Behavior.
  """

  use Argos.Monitors.Behavior, type: :http

  alias HTTPoison
  require Logger

  alias Argos.Monitors.SuccessResponse
  alias Argos.Monitors.ErrorResponse

  # Old Argos.Types is aliased in Behavior for the recover callback, not needed directly here unless specified otherwise.

  @default_http_settings %{
    method: "GET",
    # Default app-level headers, can be overridden by headers
    headers: %{},
    timeout: 5000,
    # User's previous update
    interval: 1000,
    follow_redirect: true,
    verify_ssl: false,
    request_body: "",
    # User's previous update
    request_params: %{}
  }

  @impl Argos.Monitors.Behavior
  def config_schema do
    [
      %{
        name: :url,
        type: :string,
        required: true,
        description: "The URL to fetch data from",
        validation: %{pattern: ~r{^http?://.+}}
      },
      %{
        name: :method,
        type: :string,
        required: false,
        default: "GET",
        description: "HTTP method to use"
      },
      %{
        # General headers, might be deprecated in favor of headers
        name: :headers,
        type: :map,
        required: false,
        default: %{},
        description: "HTTP headers to send with the request (consider using headers)"
      },
      %{
        name: :interval,
        type: :integer,
        required: true,
        # Default added for clarity, though schema default is king
        default: 1000,
        description: "Time between requests in milliseconds",
        # User's previous update
        validation: %{min: 100, max: 3_600_000}
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
        type: :string,
        required: false,
        default: "",
        description: "String body to send with POST/PUT/PATCH requests"
      },
      %{
        name: :request_params,
        type: :map,
        required: false,
        default: %{},
        description: "URL parameters to send with GET/HEAD requests"
      },
      %{
        name: :headers,
        type: :map,
        required: false,
        default: %{},
        description: "Additional specific headers for the request"
      }
    ]
  end

  @impl GenServer
  def init(args) do
    # args is Argos.Monitors.Types.monitor_config()
    # %{id: String.t(), base_monitor_pid: pid(), config: monitor_specific_key_value_map}
    case HTTPoison.start() do
      {:ok, _client_pid} ->
        # Ensure config is a map, even if not provided in args
        monitor_specific_config = Map.get(args, :config, %{})

        # Merge defaults with the monitor-specific config from the database/args
        http_settings = Map.merge(@default_http_settings, monitor_specific_config)

        unless Map.get(http_settings, :url) do
          Logger.error(
            "[#{__MODULE__}] Missing required configuration: :url for monitor ID #{args.id}"
          )

          {:stop, {:missing_required_config, [:url]}}
        end

        interval = Map.get(http_settings, :interval, @default_http_settings.interval)

        state = %{
          monitor_id: args.id,
          base_monitor_pid: args.base_monitor_pid,
          http_config: http_settings,
          client_module: HTTPoison,
          # Schedule immediately
          timer_ref: schedule_next_request(interval, 0)
        }

        Logger.debug(
          "[#{__MODULE__}] Initialized for monitor ID #{args.id} with config: #{inspect(http_settings)}"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "[#{__MODULE__}] Failed to initialize HTTP client: #{inspect(reason)} for monitor ID #{args.id}"
        )

        {:stop, {:http_client_init_failed, reason}}
    end
  end

  @impl GenServer
  def handle_info(:fetch_data, state) do
    Logger.debug(
      "[#{__MODULE__}] Fetching data for monitor ID #{state.monitor_id}, URL: #{state.http_config.url}"
    )

    response_tuple = make_request(state.http_config, state.client_module)
    now = DateTime.utc_now()

    case response_tuple do
      {:ok, response_data} ->
        success_response = %SuccessResponse{
          timestamp: now,
          monitor_id: state.monitor_id,
          # For completeness, though base_monitor knows its pid
          base_monitor_pid: state.base_monitor_pid,
          # This is %{status_code, body, headers}
          data: %{response_data | body: Jason.decode!(response_data.body)}
        }

        GenServer.cast(state.base_monitor_pid, {:handle_data, success_response})
        new_timer_ref = schedule_next_request(state.http_config.interval)
        {:noreply, %{state | timer_ref: new_timer_ref}}

      {:error, error_details} ->
        error_response = %ErrorResponse{
          timestamp: now,
          monitor_id: state.monitor_id,
          base_monitor_pid: state.base_monitor_pid,
          # This is %{type, message, details}
          error: format_error_details(error_details)
        }

        GenServer.cast(state.base_monitor_pid, {:handle_error, error_response})
    end

    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info(
      "[#{__MODULE__}] Terminating monitor ID #{state.monitor_id}, reason: #{inspect(reason)}"
    )

    if Map.get(state, :timer_ref), do: Process.cancel_timer(state.timer_ref)

    Process.exit(self(), :normal)
    :ok
  end

  @impl Argos.Monitors.Behavior
  def recover(error_response_type) do
    GenServer.cast(self(), {:recover, error_response_type})
  end

  @impl GenServer
  def handle_cast({:recover, error_response_type}, state) do
    case error_response_type do
      :stop ->
        GenServer.stop(self())

      :retry ->
        timer_ref = schedule_next_request(0)
        {:noreply, %{state | timer_ref: timer_ref}}
    end
  end

  # --- Private Helper Functions ---

  defp schedule_next_request(interval_ms, initial_delay_ms \\ nil) do
    delay = initial_delay_ms || interval_ms
    Logger.debug("[#{__MODULE__}] Scheduling next fetch in #{delay}ms.")
    Process.send_after(self(), :fetch_data, delay)
  end

  # Format error details and decode JSON body if present
  defp format_error_details(error_details) do
    if Map.has_key?(error_details, :details) and
       Map.has_key?(error_details.details, :body) and
       is_binary(error_details.details.body) do
      try do
        decoded_body = Jason.decode!(error_details.details.body)
        %{error_details | details: %{error_details.details | body: decoded_body}}
      rescue
        _ ->
          # If JSON parsing fails, return the original error details
          error_details
      end
    else
      error_details
    end
  end

  defp make_request(http_config, client_module) do
    method_str = String.upcase(to_string(http_config.method || "GET"))

    base_url = http_config.url
    params = http_config.request_params || %{}

    url =
      if Enum.member?(["GET", "HEAD"], method_str) && map_size(params) > 0 do
        uri = URI.parse(base_url)
        query = URI.encode_query(Map.merge(URI.decode_query(uri.query || ""), params))
        %{uri | query: query} |> URI.to_string()
      else
        base_url
      end

    # Merge general headers with specific headers, headers take precedence
    final_headers = Map.merge(http_config.headers || %{}, http_config.headers || %{})

    options = [
      follow_redirect: http_config.follow_redirect,
      ssl: [verify: if(http_config.verify_ssl, do: :verify_peer, else: :verify_none)],
      timeout: http_config.timeout,
      recv_timeout: http_config.timeout
    ]

    body =
      if Enum.member?(["POST", "PUT", "PATCH"], method_str),
        do: http_config.request_body || "",
        else: ""

    Logger.debug(
      "[#{__MODULE__}] Making HTTP #{method_str} request to #{url} with timeout #{http_config.timeout}ms. Body: #{if body == "", do: "(empty)", else: "(present)"}"
    )

    try do
      case client_module.request(method_str, url, body, final_headers, options) do
        {:ok,
         %HTTPoison.Response{status_code: status_code, body: resp_body, headers: resp_headers}}
        when status_code >= 200 and status_code < 300 ->
          parsed_headers = Map.new(resp_headers)
          {:ok, %{status_code: status_code, body: resp_body, headers: parsed_headers}}

        {:ok, %HTTPoison.Response{status_code: status_code, body: resp_body}} ->
          Logger.warning("[#{__MODULE__}] HTTP Error for #{url}: #{status_code} - #{resp_body}")

          {:error,
           %{
             type: :http_error,
             message: "HTTP " <> to_string(status_code),
             details: %{status_code: status_code, body: resp_body}
           }}

        {:ok, %HTTPoison.MaybeRedirect{status_code: status_code, redirect_url: redirect_url}} ->
          Logger.warning(
            "[#{__MODULE__}] HTTP Redirect not followed for #{url}: #{status_code} to #{redirect_url}"
          )

          {:error,
           %{
             type: :redirect_error,
             message: "HTTP #{status_code} redirect to #{redirect_url} not followed",
             details: %{status_code: status_code, redirect_url: redirect_url}
           }}

        {:error, %HTTPoison.Error{reason: reason_val}} ->
          Logger.error("[#{__MODULE__}] HTTP Client Error for #{url}: #{inspect(reason_val)}")

          {:error,
           %{
             type: :client_error,
             message: "HTTP client error: " <> inspect(reason_val),
             details: %{reason: reason_val}
           }}
      end
    catch
      kind, error_val ->
        stacktrace = __STACKTRACE__

        Logger.error("""
        [#{__MODULE__}] HTTP request failed unexpectedly.
        Kind: #{inspect(kind)}
        Error: #{inspect(error_val)}
        URL: #{url}
        Method: #{method_str}
        Options: #{inspect(options)}
        Stacktrace: #{inspect(stacktrace)}
        """)

        {:error,
         %{
           type: :exception,
           message: "Exception during HTTP request: #{kind}",
           details: %{kind: kind, error: error_val, stacktrace: stacktrace}
         }}
    end
  end
end
