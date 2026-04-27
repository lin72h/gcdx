defmodule TwqTest.PressureProviderBundleTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderBundle

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json"
            )

  test "loads the checked-in bundle baseline" do
    payload = PressureProviderBundle.load(@baseline)

    assert payload["bundle_kind"] == "pressure_bundle_v1"
    assert payload["source_session_kind"] == "callable_session_v1"
    assert payload["source_observer_kind"] == "pressure_observer_v1"
    assert payload["source_tracker_kind"] == "pressure_transition_tracker_v1"
    assert get_in(payload, ["contract", "current_signal_field"]) == "nonidle_workers_current"
  end

  test "accepts the checked-in bundle baseline against itself" do
    comparison = PressureProviderBundle.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when bundle source tracker version drifts" do
    candidate =
      @baseline
      |> PressureProviderBundle.load()
      |> put_in(["captures", "dispatch.pressure", "source_tracker_version"], 0)

    comparison = PressureProviderBundle.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "source_tracker_version differs")
           )
  end
end
