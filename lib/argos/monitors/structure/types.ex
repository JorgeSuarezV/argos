defmodule Argos.Types do
  @moduledoc """
  This module defines all the common types used across the Argos system.
  These types are used for specs and documentation purposes.
  """

  alias Argos.Config.SchemaTypes

  @typedoc """
  Represents the normalized data format for successful monitor outputs.
  """
  @type normalized_data_success :: %{
    monitor_id: String.t(),
    timestamp: DateTime.t(),
    status: :ok,
    data: map(),
    meta: %{
      status: connection_status(),
      latency: non_neg_integer(),
      last_success: DateTime.t()
    }
  }

  @typedoc """
  Represents the normalized data format for error monitor outputs.
  """
  @type normalized_data_error :: %{
    monitor_id: String.t(),
    timestamp: DateTime.t(),
    status: :error,
    error: error_info(),
    meta: %{
      status: :error,
      last_success: DateTime.t() | nil
    }
  }

  @typedoc """
  Union type for all possible normalized data formats.
  """
  @type normalized_data :: normalized_data_success() | normalized_data_error()

  @typedoc """
  Represents the command of recovery of a monitor
  """
  @type recovery_command :: :retry | :shutdown

  @typedoc """
  Represents the action of recovery of a monitor
  """
  @type recovery_action :: %{
    command: recovery_command(),
    delay: pos_integer() | nil
  }

  @typedoc """
  Possible connection states for a monitor
  """
  @type connection_status :: :connected | :disconnected | :connecting | :error

  @typedoc """
  Error information structure
  """
  @type error_info :: %{
    type: error_type(),
    message: String.t(),
    details: map(),
    timestamp: DateTime.t(),
    stacktrace: list() | nil
  }

  @typedoc """
  Classification of different types of errors that can occur
  """
  @type error_type :: :network | :protocol | :authentication | :timeout | :parse | :unknown

  @typedoc """
  Represents the complete state of a monitor
  """
  @type monitor_state :: %{
    monitor_id: String.t(),
    type: atom(),
    config: map(),
    current_data: normalized_data() | nil,
    error_history: [error_info()],
    connection_status: connection_status(),
    last_update: DateTime.t(),
    retry_policy: SchemaTypes.retry_policy(),
    meta: map()
  }


end
