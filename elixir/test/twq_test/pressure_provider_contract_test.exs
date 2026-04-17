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

  test "accepts the checked-in preview baseline against the contract" do
    validation = PressureProviderContract.validate(@contract, @preview_baseline, :preview)

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
end
