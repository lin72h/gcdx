defmodule TwqTest.PressureProviderContractTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderContract

  @repo_root Path.expand("../../..", __DIR__)
  @contract Path.join(@repo_root, "benchmarks/contracts/m15-pressure-provider-contract-v1.json")
  @derived_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-20260417.json"
                    )
  @live_baseline Path.join(
                   @repo_root,
                   "benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json"
                 )
  @adapter_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json"
                    )
  @session_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json"
                    )
  @observer_baseline Path.join(
                       @repo_root,
                       "benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json"
                     )
  @tracker_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json"
                    )
  @bundle_baseline Path.join(
                     @repo_root,
                     "benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json"
                   )
  @preview_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json"
                    )

  test "loads the checked-in pressure-provider contract" do
    contract = PressureProviderContract.load(@contract)

    assert contract["name"] == "twq_pressure_provider"
    assert contract["version"] == 1
    assert contract["current_signal_field"] == "nonidle_workers_current"
    assert contract["quiescence_kind"] == "total_and_nonidle_zero"
  end

  test "accepts the checked-in derived baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @derived_baseline, :derived)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in live baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @live_baseline, :live)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in adapter baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @adapter_baseline, :adapter)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in session baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @session_baseline, :session)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in preview baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @preview_baseline, :preview)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in observer baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @observer_baseline, :observer)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in tracker baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @tracker_baseline, :tracker)

    assert validation.ok?
    assert validation.failures == []
  end

  test "accepts the checked-in bundle baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @bundle_baseline, :bundle)

    assert validation.ok?
    assert validation.failures == []
  end

  test "fails when derived contract metadata drifts" do
    candidate =
      @derived_baseline
      |> PressureProviderContract.load()
      |> put_in(["contract", "current_signal_field"], "active_workers_current")

    validation = PressureProviderContract.validate(@contract, candidate, :derived)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(&1, "contract differs")
           )
  end

  test "fails when live snapshot per-bucket nonidle detail is missing" do
    candidate =
      @live_baseline
      |> PressureProviderContract.load()
      |> update_in(["captures", "dispatch.pressure", "snapshots"], fn [first | rest] ->
        [
          update_in(
            first,
            ["diagnostics", "per_bucket"],
            &Map.delete(&1, "nonidle_workers_current")
          )
          | rest
        ]
      end)

    validation = PressureProviderContract.validate(@contract, candidate, :live)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(&1, "per-bucket field nonidle_workers_current missing")
           )
  end

  test "fails when preview raw snapshot nonidle detail is missing" do
    candidate =
      @preview_baseline
      |> PressureProviderContract.load()
      |> update_in(["captures", "dispatch.pressure", "snapshots"], fn [first | rest] ->
        [
          update_in(first, ["snapshot"], &Map.delete(&1, "bucket_nonidle_current"))
          | rest
        ]
      end)

    validation = PressureProviderContract.validate(@contract, candidate, :preview)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(&1, "raw field bucket_nonidle_current missing")
           )
  end

  test "fails when adapter view metadata is missing" do
    candidate =
      @adapter_baseline
      |> PressureProviderContract.load()
      |> update_in(
        ["captures", "dispatch.pressure", "snapshots"],
        fn [first | rest] ->
          [update_in(first, ["view"], &Map.delete(&1, "version")) | rest]
        end
      )

    validation = PressureProviderContract.validate(@contract, candidate, :adapter)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(&1, "view field version missing")
           )
  end

  test "fails when session metadata is missing" do
    candidate =
      @session_baseline
      |> PressureProviderContract.load()
      |> update_in(
        ["captures", "dispatch.pressure", "snapshots"],
        fn [first | rest] ->
          [update_in(first, ["session"], &Map.delete(&1, "next_generation")) | rest]
        end
      )

    validation = PressureProviderContract.validate(@contract, candidate, :session)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(&1, "session field next_generation missing")
           )
  end

  test "fails when observer source-session metadata is missing" do
    candidate =
      @observer_baseline
      |> PressureProviderContract.load()
      |> update_in(["captures", "dispatch.pressure"], &Map.delete(&1, "source_session_version"))

    validation = PressureProviderContract.validate(@contract, candidate, :observer)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(
               &1,
               "captures.dispatch.pressure: field source_session_version missing"
             )
           )
  end

  test "fails when tracker source-session metadata is missing" do
    candidate =
      @tracker_baseline
      |> PressureProviderContract.load()
      |> update_in(["captures", "dispatch.pressure"], &Map.delete(&1, "source_session_version"))

    validation = PressureProviderContract.validate(@contract, candidate, :tracker)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(
               &1,
               "captures.dispatch.pressure: field source_session_version missing"
             )
           )
  end

  test "fails when bundle source-observer metadata is missing" do
    candidate =
      @bundle_baseline
      |> PressureProviderContract.load()
      |> update_in(["captures", "dispatch.pressure"], &Map.delete(&1, "source_observer_version"))

    validation = PressureProviderContract.validate(@contract, candidate, :bundle)

    refute validation.ok?

    assert Enum.any?(
             validation.failures,
             &String.contains?(
               &1,
               "captures.dispatch.pressure: field source_observer_version missing"
             )
           )
  end
end
