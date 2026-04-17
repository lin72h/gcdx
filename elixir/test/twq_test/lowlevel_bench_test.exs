defmodule TwqTest.LowlevelBenchTest do
  use ExUnit.Case, async: true

  alias TwqTest.{JSON, LowlevelBench}

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m13-lowlevel-suite-20260416.json"
            )

  test "normalizes the checked-in combined M13 low-level baseline" do
    normalized = LowlevelBench.normalize(@baseline)

    assert Map.keys(normalized) |> Enum.sort() == ["workqueue_wake", "zig_hotpath"]

    assert Map.keys(normalized["zig_hotpath"]) |> Enum.sort() == [
             "reqthreads",
             "reqthreads_overcommit",
             "should_narrow",
             "thread_enter",
             "thread_return",
             "thread_transfer"
           ]

    assert Map.keys(normalized["workqueue_wake"]) |> Enum.sort() == [
             "wake_default",
             "wake_overcommit"
           ]
  end

  test "accepts the combined baseline against itself" do
    comparison = LowlevelBench.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert comparison.suites["zig_hotpath"].ok?
    assert comparison.suites["workqueue_wake"].ok?
  end

  test "reports child-suite regressions" do
    candidate =
      @baseline
      |> LowlevelBench.load()
      |> put_in(
        [
          "suites",
          "workqueue_wake",
          "benchmarks",
          "wake_default",
          "data",
          "thread_mismatch_count"
        ],
        1
      )

    path =
      Path.join(
        System.tmp_dir!(),
        "gcdx-lowlevel-candidate-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, JSON.encode!(candidate))

    comparison = LowlevelBench.compare(@baseline, path)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "workqueue_wake: wake_default: thread_mismatch_count")
           )
  end

  test "fails when a child suite is missing" do
    candidate =
      @baseline
      |> LowlevelBench.load()
      |> update_in(["suites"], &Map.delete(&1, "zig_hotpath"))

    comparison = LowlevelBench.compare(@baseline, candidate)

    refute comparison.ok?
    assert "zig_hotpath: missing from candidate" in comparison.failures
  end
end
