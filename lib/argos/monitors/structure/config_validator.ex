defmodule Argos.Monitors.ConfigValidator do
  @moduledoc """
  Validates monitor configurations against their defined schemas.
  This module ensures that all configurations meet their protocol's requirements
  before being used in the system.
  """

  alias Argos.Config.SchemaTypes

  @retry_policy_schema %{
    type: :retry_policy,
    description: "Retry policy configuration",
    fields: [
      %{
        name: :max_retries,
        type: :integer,
        required: true,
        description: "Maximum number of retry attempts",
        validation: %{min: 0}
      },
      %{
        name: :backoff_strategy,
        type: :atom,
        required: true,
        description: "Strategy for calculating retry delays",
        validation: %{values: [:exponential, :linear, :fixed]}
      },
      %{
        name: :retry_timeout,
        type: :integer,
        required: true,
        description: "Base timeout in milliseconds",
        validation: %{min: 100}
      }
    ]
  }

  @doc """
  Validates a configuration against a schema.

  ## Parameters
    - schema: The schema to validate against (as defined in SchemaTypes)
    - config: The configuration to validate

  ## Returns
    - {:ok, validated_config} - Configuration is valid
    - {:error, reason} - Configuration is invalid with reason
  """
  @spec validate_schema([SchemaTypes.config_field()], map()) :: {:ok, map()} | {:error, String.t()}
  def validate_schema(schema, config) when is_list(schema) and is_map(config) do
    with :ok <- validate_required_fields(schema, config),
         {:ok, validated_fields} <- validate_fields(schema, config) do
      {:ok, Map.merge(config, validated_fields)}
    end
  end

  @doc """
  Validates a retry policy configuration.

  ## Parameters
    - retry_policy: The retry policy configuration to validate

  ## Returns
    - {:ok, validated_retry_policy} - Retry policy is valid
    - {:error, reason} - Retry policy is invalid with reason
  """
  @spec validate_retry_policy(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_retry_policy(retry_policy) when is_map(retry_policy) do
    case validate_fields(@retry_policy_schema.fields, retry_policy) do
      {:ok, validated_policy} -> {:ok, validated_policy}
      {:error, reason} -> {:error, "Invalid retry policy: #{reason}"}
    end
  end
  def validate_retry_policy(_), do: {:error, "Retry policy must be a map"}

  # Private Functions

  defp validate_required_fields(_schema, config) do
    required_fields = [:id, :type]
    case Enum.all?(required_fields, &Map.has_key?(config, &1)) do
      true -> :ok
      false ->
        missing = Enum.reject(required_fields, &Map.has_key?(config, &1))
        {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end

  defp validate_fields(fields, config) when is_list(fields) do
    fields
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
      case validate_field(field, config) do
        {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_field(%{name: name, type: type, required: true} = field, config) do
    case Map.get(config, name) do
      nil -> {:error, "Required field #{name} is missing"}
      value -> validate_field_type(type, value, field)
    end
  end

  defp validate_field(%{name: name, type: type} = field, config) do
    value = Map.get(config, name)
    cond do
      is_nil(value) and not is_nil(field[:default]) ->
        {:ok, {name, field.default}}
      is_nil(value) ->
        {:ok, {name, nil}}
      true ->
        validate_field_type(type, value, field)
    end
  end

  defp validate_field_type(:string, value, field) when is_binary(value) do
    validate_string_field(value, field)
  end

  defp validate_field_type(:integer, value, field) when is_integer(value) do
    validate_number_field(value, field)
  end

  defp validate_field_type(:float, value, field) when is_float(value) do
    validate_number_field(value, field)
  end

  defp validate_field_type(:boolean, value, field) when is_boolean(value) do
    {:ok, {field.name, value}}
  end

  defp validate_field_type(:map, value, field) when is_map(value) do
    {:ok, {field.name, value}}
  end

  defp validate_field_type(:atom, value, field) when is_atom(value) do
    validate_atom_field(value, field)
  end

  defp validate_field_type({:list, item_type}, value, field) when is_list(value) do
    case Enum.all?(value, &valid_type?(&1, item_type)) do
      true -> {:ok, {field.name, value}}
      false -> {:error, "Invalid list items for field #{field.name}"}
    end
  end

  defp validate_field_type(type, value, field) do
    {:error, "Invalid type #{inspect(type)} for field #{field.name}, got #{inspect(value)}"}
  end

  defp validate_string_field(value, %{name: name, validation: %{pattern: pattern}}) do
    case Regex.match?(pattern, value) do
      true -> {:ok, {name, value}}
      false -> {:error, "Field #{name} does not match pattern #{inspect(pattern)}"}
    end
  end
  defp validate_string_field(value, field), do: {:ok, {field.name, value}}

  defp validate_number_field(value, %{name: name, validation: validation}) do
    cond do
      is_number(validation[:min]) and value < validation.min ->
        {:error, "Field #{name} is below minimum #{validation.min}"}
      is_number(validation[:max]) and value > validation.max ->
        {:error, "Field #{name} is above maximum #{validation.max}"}
      true ->
        {:ok, {name, value}}
    end
  end
  defp validate_number_field(value, field), do: {:ok, {field.name, value}}

  defp validate_atom_field(value, %{name: name, validation: %{values: allowed_values}}) do
    if value in allowed_values do
      {:ok, {name, value}}
    else
      {:error, "Field #{name} must be one of: #{inspect(allowed_values)}"}
    end
  end
  defp validate_atom_field(value, field), do: {:ok, {field.name, value}}

  defp valid_type?(value, :string), do: is_binary(value)
  defp valid_type?(value, :integer), do: is_integer(value)
  defp valid_type?(value, :float), do: is_float(value)
  defp valid_type?(value, :boolean), do: is_boolean(value)
  defp valid_type?(value, :map), do: is_map(value)
  defp valid_type?(value, :atom), do: is_atom(value)
  defp valid_type?(value, {:list, type}), do: is_list(value) and Enum.all?(value, &valid_type?(&1, type))
  defp valid_type?(_, _), do: false
end
