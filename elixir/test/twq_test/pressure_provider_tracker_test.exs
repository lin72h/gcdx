defmodule TwqTest.PressureProviderTrackerTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderTracker

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json"
            )

  test "loads the checked-in tracker baseline" do
    payload = PressureProviderTracker.load(@baseline)

    assert payload["tracker_kind"] == "pressure_transition_tracker_v1"
    assert payload["source_session_kind"] == "callable_session_v1"
    assert payload["source_view_kind"] == "aggregate_view_v1"
    assert get_in(payload, ["contract", "current_signal_field"]) == "nonidle_workers_current"
  end

  test "accepts the checked-in tracker baseline against itself" do
    comparison = PressureProviderTracker.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when tracker source session version drifts" do
    candidate =
      @baseline
      |> PressureProviderTracker.load()
      |> put_in(["captures", "dispatch.pressure", "source_session_version"], 0)

    comparison = PressureProviderTracker.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "source_session_version differs")
           )
  end
end
