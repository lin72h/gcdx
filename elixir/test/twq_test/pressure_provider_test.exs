defmodule TwqTest.PressureProviderTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProvider

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-20260417.json"
            )

  test "loads the checked-in pressure-provider baseline shape" do
    artifact = PressureProvider.load(@baseline)

    assert artifact["provider_scope"] == "pressure_only"
    assert artifact["schema_version"] == 1
    assert get_in(artifact, ["contract", "name"]) == "twq_pressure_provider"
    assert get_in(artifact, ["contract", "current_signal_field"]) == "nonidle_workers_current"
    assert get_in(artifact, ["metadata", "generation_kind"]) == "synthetic_sequence"
    assert get_in(artifact, ["metadata", "monotonic_time_kind"]) == "unavailable_in_derived_view"
    assert map_size(artifact["snapshots"]) == 9

    assert get_in(artifact, [
             "snapshots",
             "dispatch.pressure",
             "aggregate",
             "nonidle_workers_current"
           ]) == nil

    assert is_integer(
             get_in(artifact, [
               "snapshots",
               "dispatch.sustained",
               "aggregate",
               "nonidle_workers_current"
             ])
           )
  end

  test "accepts the checked-in pressure-provider baseline against itself" do
    comparison = PressureProvider.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert comparison.snapshots["dispatch.pressure"].status == "ok"
    assert comparison.snapshots["swift.dispatchmain-taskhandles-after-repeat"].status == "ok"
  end

  test "fails when the pressure-visible lane loses its pressure signal" do
    candidate =
      @baseline
      |> PressureProvider.load()
      |> put_in(["snapshots", "dispatch.pressure", "flags", "pressure_visible"], false)

    comparison = PressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.pressure: flags.pressure_visible differs")
           )
  end

  test "fails when a pressure aggregate exceeds the baseline limit" do
    candidate =
      @baseline
      |> PressureProvider.load()
      |> put_in(["snapshots", "dispatch.pressure", "aggregate", "request_events_total"], 100)

    comparison = PressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.pressure: aggregate request_events_total")
           )
  end

  test "fails when the nonidle current signal drifts above the baseline limit" do
    candidate =
      @baseline
      |> PressureProvider.load()
      |> put_in(["snapshots", "dispatch.sustained", "aggregate", "nonidle_workers_current"], 999)

    comparison = PressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.sustained: aggregate nonidle_workers_current")
           )
  end
end
