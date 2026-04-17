defmodule TwqTest.M14ComparisonTest do
  use ExUnit.Case, async: true

  alias TwqTest.M14Comparison

  @repo_root Path.expand("../../..", __DIR__)

  @freebsd_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json"
                    )

  @macos_report Path.join(
                  @repo_root,
                  "benchmarks/baselines/m14-macos-stock-introspection-20260416.json"
                )

  test "the checked-in M14 comparison stops tuning the seam" do
    comparison = M14Comparison.compare(@freebsd_baseline, @macos_report)

    assert comparison.stop?
    assert comparison.verdict == "stop_tuning_this_seam"
    assert comparison.workload.mismatches == []
    assert comparison.classification.ok

    assert_in_delta(
      comparison.metrics["root_push_mainq_default_overcommit"].freebsd_avg,
      3.21,
      0.01
    )

    assert_in_delta(
      comparison.metrics["root_push_mainq_default_overcommit"].macos_avg,
      2.04,
      0.01
    )

    assert_in_delta(
      comparison.metrics["root_push_mainq_default_overcommit"].symmetric_ratio,
      1.58,
      0.01
    )
  end

  test "classification mismatch downgrades the verdict to review" do
    macos_report =
      @macos_report
      |> M14Comparison.load()
      |> put_in(["classification", "default_overcommit_receives_mainq_traffic"], false)

    comparison = M14Comparison.compare(@freebsd_baseline, macos_report)

    refute comparison.stop?
    assert comparison.verdict == "review"

    assert "classification does not show the expected default/default.overcommit split" in comparison.failures
  end
end
