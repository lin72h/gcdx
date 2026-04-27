defmodule TwqTest.VMM15PressureProviderStackGateTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @repo_root Path.expand("../../..", __DIR__)

  @contract Path.join(
              @repo_root,
              "benchmarks/contracts/m15-pressure-provider-contract-v1.json"
            )

  @crossover_source Path.join(
                      @repo_root,
                      "benchmarks/baselines/m13-crossover-full-20260417.json"
                    )

  @derived_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-20260417.json"
                    )

  @live_baseline Path.join(
                   @repo_root,
                   "benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json"
                 )

  @preview_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json"
                    )

  @adapter_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json"
                    )

  @session_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json"
                    )

  @observer_baseline Path.join(
                       @repo_root,
                       "benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json"
                     )

  @tracker_baseline Path.join(
                      @repo_root,
                      "benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json"
                    )

  @bundle_baseline Path.join(
                     @repo_root,
                     "benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json"
                   )

  test "runs the repo-owned pressure-provider stack gate against checked-in artifacts" do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "gcdx-m15-pressure-provider-stack-#{System.unique_integer([:positive])}"
      )

    summary_md = Path.join(out_dir, "summary.md")
    stack_json = Path.join(out_dir, "stack.json")

    on_exit(fn -> File.rm_rf(out_dir) end)

    result =
      VM.run_m15_pressure_provider_stack_gate(
        m15_stack_out_dir: out_dir,
        m15_stack_summary_md: summary_md,
        m15_stack_json: stack_json,
        m15_stack_contract_json: @contract,
        m15_stack_crossover_source: @crossover_source,
        m15_stack_derived_baseline: @derived_baseline,
        m15_stack_live_baseline: @live_baseline,
        m15_stack_preview_baseline: @preview_baseline,
        m15_stack_adapter_baseline: @adapter_baseline,
        m15_stack_session_baseline: @session_baseline,
        m15_stack_observer_baseline: @observer_baseline,
        m15_stack_tracker_baseline: @tracker_baseline,
        m15_stack_bundle_baseline: @bundle_baseline,
        m15_stack_live_candidate_json: @live_baseline,
        m15_stack_preview_candidate_json: @preview_baseline,
        m15_stack_adapter_candidate_json: @adapter_baseline,
        m15_stack_session_candidate_json: @session_baseline,
        m15_stack_observer_candidate_json: @observer_baseline,
        m15_stack_tracker_candidate_json: @tracker_baseline,
        m15_stack_bundle_candidate_json: @bundle_baseline,
        m15_stack_observer_replay_session_artifact: @session_baseline,
        m15_stack_tracker_replay_session_artifact: @session_baseline,
        m15_stack_bundle_replay_session_artifact: @session_baseline,
        gate_timeout_ms: 120_000
      )

    assert result.exit_status == 0
    assert result.timed_out? == false
    assert result.output =~ "verdict=pressure_stack_ready"
    assert File.exists?(summary_md)
    assert File.exists?(stack_json)
  end
end
