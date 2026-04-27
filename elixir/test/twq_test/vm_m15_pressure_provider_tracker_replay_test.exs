defmodule TwqTest.VMM15PressureProviderTrackerReplayTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json"
            )

  @session_artifact Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json"
                    )

  test "replays the checked-in session artifact into the tracker baseline" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m15-pressure-provider-tracker-replay-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    comparison_json = Path.join(out_dir, "comparison.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m15_pressure_provider_tracker_replay(
        m15_tracker_replay_baseline: @baseline,
        m15_tracker_replay_session_artifact: @session_artifact,
        m15_tracker_replay_out_dir: out_dir,
        m15_tracker_replay_comparison_json: comparison_json,
        m15_tracker_replay_summary_md: summary_md,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=ok"
    assert File.exists?(summary_md)
    assert File.exists?(comparison_json)
  end
end
