defmodule TwqTest.ResultTest do
  use ExUnit.Case, async: true

  alias TwqTest.Result

  test "builds and validates ok results" do
    result =
      Result.ok(:probe, %{threads_created: 1}, %{kernel: "WORKQUEUE"})

    assert :ok = Result.validate(result)
    assert result.kind == :probe
    assert result.status == :ok
  end

  test "rejects malformed results" do
    assert {:error, {:missing_key, :meta}} =
             Result.validate(%{
               kind: :probe,
               status: :ok,
               data: %{},
               recorded_at: "2026-04-07T00:00:00Z"
             })
  end

  test "encodes deterministically as json" do
    result =
      Result.ok(:probe, %{narrow_true: 2, narrow_false: 1}, %{vm: "twq-dev"})

    json = Result.to_json(result)

    assert String.contains?(json, "\"kind\":\"probe\"")
    assert String.contains?(json, "\"status\":\"ok\"")
    assert String.contains?(json, "\"narrow_true\":2")
  end
end
