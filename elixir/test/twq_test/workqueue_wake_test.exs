defmodule TwqTest.WorkqueueWakeTest do
  use ExUnit.Case, async: true

  alias TwqTest.{JSON, WorkqueueWake}

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m13-workqueue-wake-suite-20260416.json"
            )

  test "normalizes the checked-in workqueue wake baseline" do
    normalized = WorkqueueWake.normalize(@baseline)

    assert Map.keys(normalized) |> Enum.sort() == [
             "wake_default",
             "wake_overcommit"
           ]

    assert get_in(normalized, ["wake_default", "counter_delta", "reqthreads_count"]) == 512
    assert get_in(normalized, ["wake_default", "counter_delta", "thread_enter_count"]) == 256
    assert get_in(normalized, ["wake_default", "counter_delta", "thread_return_count"]) == 256
    assert get_in(normalized, ["wake_default", "thread_mismatch_count"]) == 0

    assert get_in(normalized, ["wake_overcommit", "counter_delta", "reqthreads_count"]) == 512
    assert get_in(normalized, ["wake_overcommit", "thread_mismatch_count"]) == 0
  end

  test "accepts the baseline against itself" do
    comparison = WorkqueueWake.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert Enum.all?(comparison.modes, &(&1.status == "ok"))
  end

  test "reports thread reuse regressions" do
    candidate =
      @baseline
      |> WorkqueueWake.load()
      |> put_in(["modes", "wake_default", "thread_mismatch_count"], 1)

    path =
      Path.join(
        System.tmp_dir!(),
        "gcdx-workqueue-wake-candidate-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, JSON.encode!(candidate))

    comparison = WorkqueueWake.compare(@baseline, path)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "wake_default: thread_mismatch_count")
           )
  end
end
