defmodule TwqTest.JSON do
  @moduledoc """
  Tiny deterministic JSON encoder for harness-owned data.

  This avoids taking a dependency before the framework skeleton is in place.
  """

  @spec encode!(term()) :: String.t()
  def encode!(term) do
    term
    |> encode()
    |> IO.iodata_to_binary()
  end

  @spec decode!(String.t()) :: term()
  def decode!(binary) when is_binary(binary) do
    :json.decode(binary)
  end

  defp encode(nil), do: "null"
  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(int) when is_integer(int), do: Integer.to_string(int)
  defp encode(float) when is_float(float), do: :erlang.float_to_binary(float, [:compact])
  defp encode(binary) when is_binary(binary), do: [?", escape(binary), ?"]
  defp encode(atom) when is_atom(atom), do: atom |> Atom.to_string() |> encode()
  defp encode(%DateTime{} = dt), do: dt |> DateTime.to_iso8601() |> encode()
  defp encode(%_{} = struct), do: struct |> Map.from_struct() |> encode()

  defp encode(list) when is_list(list) do
    inner =
      list
      |> Enum.map(&encode/1)
      |> Enum.intersperse(",")

    ["[", inner, "]"]
  end

  defp encode(map) when is_map(map) do
    inner =
      map
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, value} -> [encode(key), ":", encode(value)] end)
      |> Enum.intersperse(",")

    ["{", inner, "}"]
  end

  defp escape(binary) do
    binary
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
