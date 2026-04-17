defmodule TwqTest.SwiftTest do
  use ExUnit.Case, async: false

  alias TwqTest.Swift

  @repo_root Path.expand("../../..", __DIR__)

  @freebsd_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json"
                    )

  @macos_report Path.join(
                  @repo_root,
                  "benchmarks/baselines/m14-macos-stock-introspection-20260416.json"
                )

  test "runs the repo-owned M14 comparison lane against checked-in baselines" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m14-comparison-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    comparison_json = Path.join(out_dir, "comparison.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      Swift.run_m14_comparison(
        m14_freebsd_json: @freebsd_baseline,
        m14_macos_report: @macos_report,
        m14_out_dir: out_dir,
        m14_summary_md: summary_md,
        m14_comparison_json: comparison_json,
        comparison_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=stop_tuning_this_seam"
    assert File.exists?(summary_md)
    assert File.exists?(comparison_json)
  end
end
