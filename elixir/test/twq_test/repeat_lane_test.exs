defmodule TwqTest.RepeatLaneTest do
  use ExUnit.Case, async: true

  alias TwqTest.RepeatLane

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json"
            )

  test "accepts the checked-in repeat baseline against itself" do
    comparison = RepeatLane.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert comparison.modes["dispatch.main-executor-resume-repeat"].status == "ok"
    assert comparison.modes["swift.dispatchmain-taskhandles-after-repeat"].status == "ok"
  end

  test "fails when the C control seam gains default.overcommit traffic" do
    candidate =
      @baseline
      |> RepeatLane.load()
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_root_push_mainq_default_overcommit_delta"
        ],
        List.duplicate(1, 64)
      )

    comparison = RepeatLane.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(
               &1,
               "dispatch.main-executor-resume-repeat: root_push_mainq_default_overcommit_per_round"
             )
           )
  end

  test "fails when the Swift repeat lane regresses beyond the steady-state limit" do
    candidate =
      @baseline
      |> RepeatLane.load()
      |> put_in(
        [
          "benchmarks",
          "swift.dispatchmain-taskhandles-after-repeat",
          "round_metrics",
          "round_ok_reqthreads_delta"
        ],
        List.duplicate(40, 64)
      )

    comparison = RepeatLane.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(
               &1,
               "swift.dispatchmain-taskhandles-after-repeat: reqthreads_per_round"
             )
           )
  end

  test "accepts sparse dispatch snapshot deltas when the common steady-state rounds stay within limits" do
    baseline = RepeatLane.load(@baseline)

    dispatch_metrics =
      get_in(baseline, [
        "benchmarks",
        "dispatch.main-executor-resume-repeat",
        "round_metrics"
      ])

    dropped_rounds = MapSet.new([11, 35])

    delta_rounds =
      dispatch_metrics["libdispatch_round_ok_delta_rounds"] ||
        dispatch_metrics["libdispatch_round_ok_rounds"]

    keep_indexes =
      delta_rounds
      |> Enum.with_index()
      |> Enum.reject(fn {round_number, _index} ->
        MapSet.member?(dropped_rounds, round_number)
      end)
      |> Enum.map(&elem(&1, 1))

    pick = fn values -> Enum.map(keep_indexes, &Enum.at(values, &1)) end

    candidate =
      baseline
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_delta_rounds"
        ],
        pick.(delta_rounds)
      )
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_root_push_mainq_default_overcommit_delta"
        ],
        pick.(dispatch_metrics["libdispatch_round_ok_root_push_mainq_default_overcommit_delta"])
      )
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_root_poke_slow_default_overcommit_delta"
        ],
        pick.(dispatch_metrics["libdispatch_round_ok_root_poke_slow_default_overcommit_delta"])
      )
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_root_push_empty_default_delta"
        ],
        pick.(dispatch_metrics["libdispatch_round_ok_root_push_empty_default_delta"])
      )
      |> put_in(
        [
          "benchmarks",
          "dispatch.main-executor-resume-repeat",
          "round_metrics",
          "libdispatch_round_ok_root_poke_slow_default_delta"
        ],
        pick.(dispatch_metrics["libdispatch_round_ok_root_poke_slow_default_delta"])
      )

    comparison = RepeatLane.compare(@baseline, candidate)

    assert comparison.ok?
    assert comparison.failures == []
  end
end
