defmodule TwqTest.PressureProviderAdapterTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderAdapter

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json"
            )

  test "loads the checked-in adapter baseline" do
    payload = PressureProviderAdapter.load(@baseline)

    assert payload["adapter_kind"] == "aggregate_view_v1"
    assert get_in(payload, ["contract", "current_signal_field"]) == "nonidle_workers_current"
  end

  test "accepts the checked-in adapter baseline against itself" do
    comparison = PressureProviderAdapter.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when adapter struct size drifts" do
    candidate =
      @baseline
      |> PressureProviderAdapter.load()
      |> put_in(["captures", "dispatch.pressure", "struct_size"], 0)

    comparison = PressureProviderAdapter.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "struct_size differs")
           )
  end
end
