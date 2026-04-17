defmodule TwqTest.VMM13CloseoutTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @lowlevel_baseline Path.join(
                       @repo_root,
                       "benchmarks/baselines/m13-lowlevel-suite-20260416.json"
                     )

  @repeat_baseline Path.join(
                     @repo_root,
                     "benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json"
                   )

  @crossover_baseline Path.join(
                        @repo_root,
                        "benchmarks/baselines/m13-crossover-full-20260417.json"
                      )

  test "runs the repo-owned M13 closeout lane against checked-in baselines" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m13-closeout-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    closeout_json = Path.join(out_dir, "closeout.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m13_closeout(
        m13_closeout_out_dir: out_dir,
        m13_closeout_summary_md: summary_md,
        m13_closeout_json: closeout_json,
        m13_closeout_lowlevel_baseline: @lowlevel_baseline,
        m13_closeout_lowlevel_candidate_json: @lowlevel_baseline,
        m13_closeout_repeat_baseline: @repeat_baseline,
        m13_closeout_repeat_candidate_json: @repeat_baseline,
        m13_closeout_crossover_baseline: @crossover_baseline,
        m13_closeout_crossover_candidate_json: @crossover_baseline,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=close_m13"
    assert File.exists?(summary_md)
    assert File.exists?(closeout_json)
  end
end
