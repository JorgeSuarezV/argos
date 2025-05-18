defmodule Argos.Config.SchemaTypes do
  @moduledoc """
  This module defines the types used for configuration schemas.
  These types are used by monitor protocols to define their configuration requirements.
  """

  @typedoc """
  Protocol specific configuration schema.
  Each monitor protocol must define its configuration schema.
  This is used for validation and JSON parsing.
  """
  @type config_schema :: %{
    required(:id) => String.t(),
    required(:type) => atom(),
    required(:retry_policy) => retry_policy(),
    required(:fields) => [config_field()],
    optional(:description) => String.t()
  }


  @typedoc """
  Retry policy configuration
  """
  @type retry_policy :: %{
    max_retries: pos_integer(),
    backoff_strategy: backoff_strategy(),
    retry_timeout: pos_integer()
  }

  @typedoc """
  Available backoff strategies for retries.
  """
  @type backoff_strategy :: :fixed | :linear | :exponential 


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

  @typedoc """
  Supported configuration field types
  """
  @type config_field_type ::
    :string |
    :integer |
    :float |
    :boolean |
    :map |
    {:list, config_field_type()} |
    {:enum, [atom() | String.t() | number()]}

  @typedoc """
  Validation rules for configuration fields
  """
  @type validation_rules :: %{
    optional(:min) => number(),
    optional(:max) => number(),
    optional(:pattern) => String.t(),
    optional(:custom) => (term() -> :ok | {:error, String.t()})
  }
end
