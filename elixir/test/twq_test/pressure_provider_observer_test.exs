defmodule TwqTest.PressureProviderObserverTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderObserver

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json"
            )

  test "loads the checked-in observer baseline" do
    payload = PressureProviderObserver.load(@baseline)

    assert payload["observer_kind"] == "pressure_observer_v1"
    assert payload["source_session_kind"] == "callable_session_v1"
    assert payload["source_view_kind"] == "aggregate_view_v1"
    assert get_in(payload, ["contract", "current_signal_field"]) == "nonidle_workers_current"
  end

  test "accepts the checked-in observer baseline against itself" do
    comparison = PressureProviderObserver.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when the observer source session version drifts" do
    candidate =
      @baseline
      |> PressureProviderObserver.load()
      |> put_in(["captures", "dispatch.pressure", "source_session_version"], 0)

    comparison = PressureProviderObserver.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "source_session_version differs")
           )
  end
end
