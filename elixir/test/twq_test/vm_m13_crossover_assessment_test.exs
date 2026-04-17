defmodule TwqTest.VMM13CrossoverAssessmentTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m13-crossover-full-20260417.json"
            )

  test "runs the repo-owned M13.5 crossover assessment against the checked-in baseline" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m13-crossover-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    comparison_json = Path.join(out_dir, "comparison.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m13_crossover_assessment(
        m13_crossover_baseline: @baseline,
        m13_crossover_candidate_json: @baseline,
        m13_crossover_out_dir: out_dir,
        m13_crossover_summary_md: summary_md,
        m13_crossover_comparison_json: comparison_json,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=ok"
    assert File.exists?(summary_md)
    assert File.exists?(comparison_json)
  end
end
