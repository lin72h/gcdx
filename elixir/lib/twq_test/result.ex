defmodule TwqTest.Result do
  @moduledoc """
  Shared structured result schema for the harness and low-level helpers.
  """

  alias TwqTest.JSON

  @enforce_keys [:kind, :status, :data, :meta, :recorded_at]
  defstruct @enforce_keys

  @type status :: :ok | :error
  @type t :: %__MODULE__{
          kind: atom() | String.t(),
          status: status(),
          data: map(),
          meta: map(),
          recorded_at: String.t()
        }

  @spec ok(atom() | String.t(), map(), map()) :: t()
  def ok(kind, data, meta \\ %{}) when is_map(data) and is_map(meta) do
    new(:ok, kind, data, meta)
  end

  @spec error(atom() | String.t(), map(), map()) :: t()
  def error(kind, data, meta \\ %{}) when is_map(data) and is_map(meta) do
    new(:error, kind, data, meta)
  end

  @spec validate(map() | t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = result) do
    validate(Map.from_struct(result))
  end

  def validate(%{} = result) do
    with :ok <- required_key(result, :kind),
         :ok <- required_key(result, :status),
         :ok <- required_key(result, :data),
         :ok <- required_key(result, :meta),
         :ok <- required_key(result, :recorded_at),
         :ok <- validate_status(result[:status] || result["status"]),
         :ok <- validate_map_field(result, :data),
         :ok <- validate_map_field(result, :meta) do
      :ok
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    Map.from_struct(result)
  end

  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = result) do
    result
    |> to_map()
    |> JSON.encode!()
  end

  defp new(status, kind, data, meta) do
    %__MODULE__{
      kind: kind,
      status: status,
      data: data,
      meta: meta,
      recorded_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp required_key(map, key) do
    if Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key)) do
      :ok
    else
      {:error, {:missing_key, key}}
    end
  end

  defp validate_status(:ok), do: :ok
  defp validate_status(:error), do: :ok
  defp validate_status("ok"), do: :ok
  defp validate_status("error"), do: :ok
  defp validate_status(other), do: {:error, {:invalid_status, other}}

  defp validate_map_field(map, key) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      field when is_map(field) -> :ok
      other -> {:error, {:expected_map, key, other}}
    end
  end
end
