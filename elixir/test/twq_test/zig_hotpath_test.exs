defmodule TwqTest.ZigHotpathTest do
  use ExUnit.Case, async: true

  alias TwqTest.{JSON, ZigHotpath}

  @repo_root Path.expand("../../..", __DIR__)
  @baseline Path.join(@repo_root, "benchmarks/baselines/m13-zig-hotpath-suite-20260416.json")

  test "normalizes the checked-in M13 Zig hot-path baseline" do
    normalized = ZigHotpath.normalize(@baseline)

    assert Map.keys(normalized) |> Enum.sort() == [
             "reqthreads",
             "reqthreads_overcommit",
             "should_narrow",
             "thread_enter",
             "thread_return",
             "thread_transfer"
           ]

    assert get_in(normalized, ["should_narrow", "counter_delta", "reqthreads_count"]) == 0
    assert get_in(normalized, ["reqthreads", "counter_delta", "reqthreads_count"]) == 256

    assert get_in(normalized, ["reqthreads_overcommit", "counter_delta", "reqthreads_count"]) ==
             256

    assert get_in(normalized, ["thread_enter", "counter_delta", "thread_enter_count"]) == 256
    assert get_in(normalized, ["thread_enter", "counter_delta", "thread_return_count"]) == 256
    assert get_in(normalized, ["thread_return", "counter_delta", "thread_enter_count"]) == 256
    assert get_in(normalized, ["thread_return", "counter_delta", "thread_return_count"]) == 256

    assert get_in(normalized, ["thread_transfer", "counter_delta", "thread_transfer_count"]) ==
             256
  end

  test "accepts the baseline against itself" do
    comparison = ZigHotpath.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
    assert Enum.all?(comparison.modes, &(&1.status == "ok"))
  end

  test "reports latency regressions" do
    candidate =
      @baseline
      |> ZigHotpath.load()
      |> put_in(["modes", "should_narrow", "p95_ns"], 10_000_000)

    path =
      Path.join(
        System.tmp_dir!(),
        "gcdx-zig-hotpath-candidate-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, JSON.encode!(candidate))

    comparison = ZigHotpath.compare(@baseline, path)

    refute comparison.ok?
    assert Enum.any?(comparison.failures, &String.contains?(&1, "should_narrow: p95_ns"))
  end
end
