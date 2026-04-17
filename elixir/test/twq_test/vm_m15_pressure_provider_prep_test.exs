defmodule TwqTest.VMM15PressureProviderPrepTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @pressure_baseline Path.join(
                       @repo_root,
                       "benchmarks/baselines/m15-pressure-provider-20260417.json"
                     )

  @crossover_baseline Path.join(
                        @repo_root,
                        "benchmarks/baselines/m13-crossover-full-20260417.json"
                      )

  test "runs the repo-owned M15 pressure-provider prep lane against the checked-in crossover baseline" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m15-pressure-provider-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    comparison_json = Path.join(out_dir, "comparison.json")
    candidate_json = Path.join(out_dir, "candidate.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m15_pressure_provider_prep(
        m15_pressure_baseline: @pressure_baseline,
        m15_pressure_source_artifact: @crossover_baseline,
        m15_pressure_candidate_json: candidate_json,
        m15_pressure_out_dir: out_dir,
        m15_pressure_comparison_json: comparison_json,
        m15_pressure_summary_md: summary_md,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=ok"
    assert File.exists?(summary_md)
    assert File.exists?(comparison_json)
    assert File.exists?(candidate_json)
  end
end
