defmodule TwqTest.LivePressureProviderTest do
  use ExUnit.Case, async: true

  alias TwqTest.LivePressureProvider

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json"
            )

  test "loads the checked-in live pressure-provider baseline shape" do
    artifact = LivePressureProvider.load(@baseline)

    assert artifact["provider_scope"] == "pressure_only"
    assert artifact["schema_version"] == 1
    assert get_in(artifact, ["contract", "name"]) == "twq_pressure_provider"
    assert get_in(artifact, ["contract", "current_signal_field"]) == "nonidle_workers_current"
    assert artifact["capture_kind"] == "live_probe"
    assert get_in(artifact, ["metadata", "generation_kind"]) == "monotonic_sequence"
    assert get_in(artifact, ["metadata", "monotonic_time_kind"]) == "clock_monotonic"
    assert get_in(artifact, ["metadata", "label_count"]) == 2

    assert artifact["captures"] |> Map.keys() |> Enum.sort() == [
             "dispatch.pressure",
             "dispatch.sustained"
           ]

    assert is_integer(
             get_in(artifact, ["captures", "dispatch.pressure", "max_nonidle_workers_current"])
           )

    assert is_integer(
             get_in(artifact, [
               "captures",
               "dispatch.pressure",
               "snapshots",
               Access.at(0),
               "aggregate",
               "nonidle_workers_current"
             ])
           )
  end

  test "accepts the checked-in live pressure-provider baseline against itself" do
    comparison = LivePressureProvider.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert comparison.captures["dispatch.pressure"].status == "ok"
    assert comparison.captures["dispatch.sustained"].status == "ok"
  end

  test "fails when a capture loses contiguous generation semantics" do
    candidate =
      @baseline
      |> LivePressureProvider.load()
      |> put_in(["captures", "dispatch.pressure", "generation_contiguous"], false)

    comparison = LivePressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.pressure: generation_contiguous is not true")
           )
  end

  test "fails when a capture drops below the live smoke sample floor" do
    candidate =
      @baseline
      |> LivePressureProvider.load()
      |> put_in(["captures", "dispatch.sustained", "sample_count"], 10)

    comparison = LivePressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.sustained: sample_count 10 is below")
           )
  end

  test "fails when a live capture does not return nonidle current to baseline quiescence" do
    candidate =
      @baseline
      |> LivePressureProvider.load()
      |> put_in(["captures", "dispatch.sustained", "final_nonidle_workers_current"], 2)

    comparison = LivePressureProvider.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "dispatch.sustained: final_nonidle_workers_current 2 exceeds")
           )
  end
end
