defmodule TwqTest.VMRepeatGateTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json"
            )

  test "runs the repo-owned repeat gate against the checked-in baseline" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-repeat-gate-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    comparison_json = Path.join(out_dir, "comparison.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m13_repeat_gate(
        m13_repeat_baseline: @baseline,
        m13_repeat_candidate_json: @baseline,
        m13_repeat_out_dir: out_dir,
        m13_repeat_summary_md: summary_md,
        m13_repeat_comparison_json: comparison_json,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=ok"
    assert File.exists?(summary_md)
    assert File.exists?(comparison_json)
  end
end
