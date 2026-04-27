defmodule TwqTest.VMM15TbbxN0GcdOnlyBaselineTest do
  use ExUnit.Case, async: false

  alias TwqTest.{Command, VM}

  @repo_root Path.expand("../../..", __DIR__)
  @bundle_baseline Path.join(
                     @repo_root,
                     "benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json"
                   )

  test "runs the repo-owned TBBX N0 GCD-only baseline lane in reuse mode" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m15-tbbx-n0-gcd-only-#{System.unique_integer([:positive])}"
      )

    result =
      VM.run_m15_tbbx_n0_gcd_only_baseline(
        m15_tbbx_n0_gcd_out_dir: out_dir,
        m15_tbbx_n0_gcd_candidate_json: @bundle_baseline
      )

    assert Command.Result.ok?(result), result.output
    assert String.contains?(result.output, "verdict=ok")
    assert File.exists?(Path.join(out_dir, "summary.md"))
  end
end
