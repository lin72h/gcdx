defmodule TwqTest.VM do
  @moduledoc """
  Thin host-side wrappers around the repo's bhyve helper scripts.

  Assertions belong in ExUnit. These functions only prepare commands and
  execute the wrappers with structured results.
  """

  alias TwqTest.{Command, Env, Result, Swift, Zig}

  @normal_bhyve_exit_statuses [0, 1, 2]

  @spec stage_guest(keyword()) :: Command.Result.t()
  def stage_guest(opts \\ []) do
    env = build_env(opts)
    args = dry_run_args(opts)
    script = Path.join(env.scripts_dir, "stage-guest.sh")

    Command.run(script, args,
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  @spec run_guest(keyword()) :: Command.Result.t()
  def run_guest(opts \\ []) do
    env = build_env(opts)
    args = dry_run_args(opts)
    script = Path.join(env.scripts_dir, "run-guest.sh")

    Command.run(script, args,
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  @spec run_m13_repeat_gate(keyword()) :: Command.Result.t()
  def run_m13_repeat_gate(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-m13-repeat-gate.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> repeat_gate_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m13_crossover_assessment(keyword()) :: Command.Result.t()
  def run_m13_crossover_assessment(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-m13-crossover-assessment.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> crossover_assessment_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m13_closeout(keyword()) :: Command.Result.t()
  def run_m13_closeout(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-m13-closeout.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> closeout_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_prep(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_prep(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-prep.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_live_pressure_provider_smoke(keyword()) :: Command.Result.t()
  def run_m15_live_pressure_provider_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-live-pressure-provider-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> live_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_preview_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_preview_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-preview-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> preview_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_adapter_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_adapter_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-adapter-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> adapter_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_session_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_session_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-session-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> session_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_observer_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_observer_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-observer-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> observer_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_observer_replay(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_observer_replay(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-observer-replay.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> observer_replay_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_tracker_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_tracker_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-tracker-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> tracker_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_tracker_replay(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_tracker_replay(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-tracker-replay.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> tracker_replay_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_bundle_smoke(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_bundle_smoke(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-bundle-smoke.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> bundle_pressure_provider_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_bundle_replay(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_bundle_replay(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-bundle-replay.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> bundle_replay_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_tbbx_n0_gcd_only_baseline(keyword()) :: Command.Result.t()
  def run_m15_tbbx_n0_gcd_only_baseline(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-tbbx-n0-gcd-only-baseline.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> tbbx_n0_gcd_only_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec run_m15_pressure_provider_stack_gate(keyword()) :: Command.Result.t()
  def run_m15_pressure_provider_stack_gate(opts \\ []) do
    env = build_env(opts)

    script =
      Path.join(env.repo_root, "scripts/benchmarks/run-m15-pressure-provider-stack-gate.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> pressure_provider_stack_env(opts),
      timeout: Keyword.get(opts, :gate_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec probe_guest(keyword()) :: Result.t()
  def probe_guest(opts \\ []) do
    env = build_env(opts)
    validate_serial? = Keyword.get(opts, :validate_serial, true)
    File.rm(env.serial_log)
    build_result = Zig.build(opts)
    workqueue_build_result = Zig.build_workqueue_probe(opts)
    dispatch_build_result = Zig.build_dispatch_probe(opts)
    swift_prepare_result = Swift.prepare(opts)

    cond do
      not Command.Result.ok?(build_result) ->
        Result.error(
          :vm_probe,
          %{
            phase: "build",
            build: command_to_map(build_result),
            workqueue_build: command_to_map(workqueue_build_result),
            dispatch_build: command_to_map(dispatch_build_result),
            swift_prepare: command_to_map(swift_prepare_result),
            serial_log_path: env.serial_log,
            serial_log: read_serial_log(env)
          },
          probe_meta(env)
        )

      not Command.Result.ok?(workqueue_build_result) ->
        Result.error(
          :vm_probe,
          %{
            phase: "workqueue-build",
            build: command_to_map(build_result),
            workqueue_build: command_to_map(workqueue_build_result),
            dispatch_build: command_to_map(dispatch_build_result),
            swift_prepare: command_to_map(swift_prepare_result),
            serial_log_path: env.serial_log,
            serial_log: read_serial_log(env)
          },
          probe_meta(env)
        )

      not Command.Result.ok?(dispatch_build_result) ->
        Result.error(
          :vm_probe,
          %{
            phase: "dispatch-build",
            build: command_to_map(build_result),
            workqueue_build: command_to_map(workqueue_build_result),
            dispatch_build: command_to_map(dispatch_build_result),
            swift_prepare: command_to_map(swift_prepare_result),
            serial_log_path: env.serial_log,
            serial_log: read_serial_log(env)
          },
          probe_meta(env)
        )

      not Command.Result.ok?(swift_prepare_result) ->
        Result.error(
          :vm_probe,
          %{
            phase: "swift-prepare",
            build: command_to_map(build_result),
            workqueue_build: command_to_map(workqueue_build_result),
            dispatch_build: command_to_map(dispatch_build_result),
            swift_prepare: command_to_map(swift_prepare_result),
            serial_log_path: env.serial_log,
            serial_log: read_serial_log(env)
          },
          probe_meta(env)
        )

      true ->
        stage_result = stage_guest(opts)

        cond do
          not Command.Result.ok?(stage_result) ->
            Result.error(
              :vm_probe,
              %{
                phase: "stage",
                build: command_to_map(build_result),
                workqueue_build: command_to_map(workqueue_build_result),
                dispatch_build: command_to_map(dispatch_build_result),
                swift_prepare: command_to_map(swift_prepare_result),
                stage: command_to_map(stage_result),
                serial_log_path: env.serial_log,
                serial_log: read_serial_log(env)
              },
              probe_meta(env)
            )

          true ->
            run_result = run_guest(opts)
            serial_log = read_serial_log(env)
            swift_probe_profile = swift_probe_profile(serial_log)
            swift_timeout_modes = swift_timeout_modes(serial_log)
            validation_failures = probe_validation_failures(serial_log)
            serial_ok? = not validate_serial? or validation_failures == []

            exit_ok? =
              run_result.exit_status in @normal_bhyve_exit_statuses and not run_result.timed_out?

            payload = %{
              phase: "run",
              build: command_to_map(build_result),
              workqueue_build: command_to_map(workqueue_build_result),
              dispatch_build: command_to_map(dispatch_build_result),
              swift_prepare: command_to_map(swift_prepare_result),
              stage: command_to_map(stage_result),
              run: command_to_map(run_result),
              serial_log_path: env.serial_log,
              serial_log: serial_log,
              swift_probe_profile: swift_probe_profile,
              swift_timeout_modes: swift_timeout_modes,
              validation_failures: validation_failures
            }

            if exit_ok? and serial_ok? do
              Result.ok(:vm_probe, payload, probe_meta(env))
            else
              Result.error(:vm_probe, payload, probe_meta(env))
            end
        end
    end
  end

  @spec update_kernel(String.t(), keyword()) :: Command.Result.t()
  def update_kernel(kernel_dir, opts \\ []) do
    env = build_env(opts)
    args = dry_run_args(opts)
    script = Path.join(env.scripts_dir, "update-kernel.sh")
    script_env = Env.script_env(env) |> Map.put("TWQ_KERNEL_DIR", Path.expand(kernel_dir))
    Command.run(script, args, cd: env.repo_root, env: script_env, timeout: env.command_timeout_ms)
  end

  @spec collect_crash(String.t(), String.t(), keyword()) :: Command.Result.t()
  def collect_crash(crash_source, crash_dest, opts \\ []) do
    env = build_env(opts)
    args = dry_run_args(opts)
    script = Path.join(env.scripts_dir, "collect-crash.sh")

    script_env =
      Env.script_env(env)
      |> Map.put("TWQ_CRASH_SOURCE", Path.expand(crash_source))
      |> Map.put("TWQ_CRASH_DEST", Path.expand(crash_dest))

    Command.run(script, args, cd: env.repo_root, env: script_env, timeout: env.command_timeout_ms)
  end

  defp build_env(opts) do
    opts
    |> Keyword.drop([:dry_run])
    |> Enum.into(%{})
    |> Env.load()
  end

  defp dry_run_args(opts) do
    if Keyword.get(opts, :dry_run, false), do: ["--dry-run"], else: []
  end

  defp repeat_gate_env(script_env, opts) do
    option_env = %{
      m13_repeat_baseline: "TWQ_M13_REPEAT_BASELINE",
      m13_repeat_candidate_json: "TWQ_M13_REPEAT_CANDIDATE_JSON",
      m13_repeat_out_dir: "TWQ_M13_REPEAT_OUT_DIR",
      m13_repeat_comparison_json: "TWQ_M13_REPEAT_COMPARISON_JSON",
      m13_repeat_comparison_log: "TWQ_M13_REPEAT_COMPARISON_LOG",
      m13_repeat_summary_md: "TWQ_M13_REPEAT_SUMMARY_MD",
      m13_repeat_serial_log: "TWQ_M13_REPEAT_SERIAL_LOG",
      m13_repeat_steady_start: "TWQ_M13_REPEAT_STEADY_START",
      m13_repeat_steady_end: "TWQ_M13_REPEAT_STEADY_END",
      m13_repeat_swift_profile: "TWQ_M13_REPEAT_SWIFT_PROFILE"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp crossover_assessment_env(script_env, opts) do
    option_env = %{
      m13_crossover_baseline: "TWQ_M13_CROSSOVER_BASELINE",
      m13_crossover_candidate_json: "TWQ_M13_CROSSOVER_CANDIDATE_JSON",
      m13_crossover_out_dir: "TWQ_M13_CROSSOVER_OUT_DIR",
      m13_crossover_comparison_json: "TWQ_M13_CROSSOVER_COMPARISON_JSON",
      m13_crossover_comparison_log: "TWQ_M13_CROSSOVER_COMPARISON_LOG",
      m13_crossover_summary_md: "TWQ_M13_CROSSOVER_SUMMARY_MD",
      m13_crossover_serial_log: "TWQ_M13_CROSSOVER_SERIAL_LOG",
      m13_crossover_baseline_log: "TWQ_M13_CROSSOVER_BASELINE_LOG",
      m13_crossover_steady_start: "TWQ_M13_CROSSOVER_STEADY_START",
      m13_crossover_steady_end: "TWQ_M13_CROSSOVER_STEADY_END"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp closeout_env(script_env, opts) do
    option_env = %{
      m13_closeout_out_dir: "TWQ_M13_CLOSEOUT_OUT_DIR",
      m13_closeout_summary_md: "TWQ_M13_CLOSEOUT_SUMMARY_MD",
      m13_closeout_json: "TWQ_M13_CLOSEOUT_JSON",
      m13_closeout_lowlevel_baseline: "TWQ_M13_CLOSEOUT_LOWLEVEL_BASELINE",
      m13_closeout_lowlevel_candidate_json: "TWQ_M13_CLOSEOUT_LOWLEVEL_CANDIDATE_JSON",
      m13_closeout_repeat_baseline: "TWQ_M13_CLOSEOUT_REPEAT_BASELINE",
      m13_closeout_repeat_candidate_json: "TWQ_M13_CLOSEOUT_REPEAT_CANDIDATE_JSON",
      m13_closeout_crossover_baseline: "TWQ_M13_CLOSEOUT_CROSSOVER_BASELINE",
      m13_closeout_crossover_candidate_json: "TWQ_M13_CLOSEOUT_CROSSOVER_CANDIDATE_JSON"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_pressure_baseline: "TWQ_M15_PRESSURE_BASELINE",
      m15_pressure_source_artifact: "TWQ_M15_PRESSURE_SOURCE_ARTIFACT",
      m15_pressure_candidate_json: "TWQ_M15_PRESSURE_CANDIDATE_JSON",
      m15_pressure_out_dir: "TWQ_M15_PRESSURE_OUT_DIR",
      m15_pressure_comparison_json: "TWQ_M15_PRESSURE_COMPARISON_JSON",
      m15_pressure_comparison_log: "TWQ_M15_PRESSURE_COMPARISON_LOG",
      m15_pressure_summary_md: "TWQ_M15_PRESSURE_SUMMARY_MD"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp live_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_live_pressure_baseline: "TWQ_M15_LIVE_PRESSURE_BASELINE",
      m15_live_pressure_candidate_json: "TWQ_M15_LIVE_PRESSURE_CANDIDATE_JSON",
      m15_live_pressure_out_dir: "TWQ_M15_LIVE_PRESSURE_OUT_DIR",
      m15_live_pressure_serial_log: "TWQ_M15_LIVE_PRESSURE_SERIAL_LOG",
      m15_live_pressure_comparison_json: "TWQ_M15_LIVE_PRESSURE_COMPARISON_JSON",
      m15_live_pressure_comparison_log: "TWQ_M15_LIVE_PRESSURE_COMPARISON_LOG",
      m15_live_pressure_summary_md: "TWQ_M15_LIVE_PRESSURE_SUMMARY_MD",
      m15_live_pressure_label: "TWQ_M15_LIVE_PRESSURE_LABEL",
      m15_live_pressure_capture_modes: "TWQ_M15_LIVE_PRESSURE_CAPTURE_MODES",
      m15_live_pressure_interval_ms: "TWQ_M15_LIVE_PRESSURE_INTERVAL_MS",
      m15_live_pressure_pressure_ms: "TWQ_M15_LIVE_PRESSURE_PRESSURE_MS",
      m15_live_pressure_sustained_ms: "TWQ_M15_LIVE_PRESSURE_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp preview_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_preview_baseline: "TWQ_M15_PREVIEW_BASELINE",
      m15_preview_candidate_json: "TWQ_M15_PREVIEW_CANDIDATE_JSON",
      m15_preview_out_dir: "TWQ_M15_PREVIEW_OUT_DIR",
      m15_preview_serial_log: "TWQ_M15_PREVIEW_SERIAL_LOG",
      m15_preview_comparison_json: "TWQ_M15_PREVIEW_COMPARISON_JSON",
      m15_preview_comparison_log: "TWQ_M15_PREVIEW_COMPARISON_LOG",
      m15_preview_summary_md: "TWQ_M15_PREVIEW_SUMMARY_MD",
      m15_preview_label: "TWQ_M15_PREVIEW_LABEL",
      m15_preview_capture_modes: "TWQ_M15_PREVIEW_CAPTURE_MODES",
      m15_preview_interval_ms: "TWQ_M15_PREVIEW_INTERVAL_MS",
      m15_preview_pressure_ms: "TWQ_M15_PREVIEW_PRESSURE_MS",
      m15_preview_sustained_ms: "TWQ_M15_PREVIEW_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp adapter_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_adapter_baseline: "TWQ_M15_ADAPTER_BASELINE",
      m15_adapter_candidate_json: "TWQ_M15_ADAPTER_CANDIDATE_JSON",
      m15_adapter_out_dir: "TWQ_M15_ADAPTER_OUT_DIR",
      m15_adapter_serial_log: "TWQ_M15_ADAPTER_SERIAL_LOG",
      m15_adapter_comparison_json: "TWQ_M15_ADAPTER_COMPARISON_JSON",
      m15_adapter_comparison_log: "TWQ_M15_ADAPTER_COMPARISON_LOG",
      m15_adapter_summary_md: "TWQ_M15_ADAPTER_SUMMARY_MD",
      m15_adapter_label: "TWQ_M15_ADAPTER_LABEL",
      m15_adapter_capture_modes: "TWQ_M15_ADAPTER_CAPTURE_MODES",
      m15_adapter_interval_ms: "TWQ_M15_ADAPTER_INTERVAL_MS",
      m15_adapter_pressure_ms: "TWQ_M15_ADAPTER_PRESSURE_MS",
      m15_adapter_sustained_ms: "TWQ_M15_ADAPTER_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp session_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_session_baseline: "TWQ_M15_SESSION_BASELINE",
      m15_session_candidate_json: "TWQ_M15_SESSION_CANDIDATE_JSON",
      m15_session_out_dir: "TWQ_M15_SESSION_OUT_DIR",
      m15_session_serial_log: "TWQ_M15_SESSION_SERIAL_LOG",
      m15_session_comparison_json: "TWQ_M15_SESSION_COMPARISON_JSON",
      m15_session_comparison_log: "TWQ_M15_SESSION_COMPARISON_LOG",
      m15_session_summary_md: "TWQ_M15_SESSION_SUMMARY_MD",
      m15_session_label: "TWQ_M15_SESSION_LABEL",
      m15_session_capture_modes: "TWQ_M15_SESSION_CAPTURE_MODES",
      m15_session_interval_ms: "TWQ_M15_SESSION_INTERVAL_MS",
      m15_session_pressure_ms: "TWQ_M15_SESSION_PRESSURE_MS",
      m15_session_sustained_ms: "TWQ_M15_SESSION_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp observer_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_observer_baseline: "TWQ_M15_OBSERVER_BASELINE",
      m15_observer_candidate_json: "TWQ_M15_OBSERVER_CANDIDATE_JSON",
      m15_observer_out_dir: "TWQ_M15_OBSERVER_OUT_DIR",
      m15_observer_serial_log: "TWQ_M15_OBSERVER_SERIAL_LOG",
      m15_observer_comparison_json: "TWQ_M15_OBSERVER_COMPARISON_JSON",
      m15_observer_comparison_log: "TWQ_M15_OBSERVER_COMPARISON_LOG",
      m15_observer_summary_md: "TWQ_M15_OBSERVER_SUMMARY_MD",
      m15_observer_label: "TWQ_M15_OBSERVER_LABEL",
      m15_observer_capture_modes: "TWQ_M15_OBSERVER_CAPTURE_MODES",
      m15_observer_interval_ms: "TWQ_M15_OBSERVER_INTERVAL_MS",
      m15_observer_pressure_ms: "TWQ_M15_OBSERVER_PRESSURE_MS",
      m15_observer_sustained_ms: "TWQ_M15_OBSERVER_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp observer_replay_env(script_env, opts) do
    option_env = %{
      m15_observer_replay_baseline: "TWQ_M15_OBSERVER_REPLAY_BASELINE",
      m15_observer_replay_session_artifact: "TWQ_M15_OBSERVER_REPLAY_SESSION_ARTIFACT",
      m15_observer_replay_candidate_json: "TWQ_M15_OBSERVER_REPLAY_CANDIDATE_JSON",
      m15_observer_replay_out_dir: "TWQ_M15_OBSERVER_REPLAY_OUT_DIR",
      m15_observer_replay_comparison_json: "TWQ_M15_OBSERVER_REPLAY_COMPARISON_JSON",
      m15_observer_replay_comparison_log: "TWQ_M15_OBSERVER_REPLAY_COMPARISON_LOG",
      m15_observer_replay_summary_md: "TWQ_M15_OBSERVER_REPLAY_SUMMARY_MD",
      m15_observer_replay_label: "TWQ_M15_OBSERVER_REPLAY_LABEL"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp tracker_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_tracker_baseline: "TWQ_M15_TRACKER_BASELINE",
      m15_tracker_candidate_json: "TWQ_M15_TRACKER_CANDIDATE_JSON",
      m15_tracker_out_dir: "TWQ_M15_TRACKER_OUT_DIR",
      m15_tracker_serial_log: "TWQ_M15_TRACKER_SERIAL_LOG",
      m15_tracker_comparison_json: "TWQ_M15_TRACKER_COMPARISON_JSON",
      m15_tracker_comparison_log: "TWQ_M15_TRACKER_COMPARISON_LOG",
      m15_tracker_summary_md: "TWQ_M15_TRACKER_SUMMARY_MD",
      m15_tracker_label: "TWQ_M15_TRACKER_LABEL",
      m15_tracker_capture_modes: "TWQ_M15_TRACKER_CAPTURE_MODES",
      m15_tracker_interval_ms: "TWQ_M15_TRACKER_INTERVAL_MS",
      m15_tracker_pressure_ms: "TWQ_M15_TRACKER_PRESSURE_MS",
      m15_tracker_sustained_ms: "TWQ_M15_TRACKER_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp tracker_replay_env(script_env, opts) do
    option_env = %{
      m15_tracker_replay_baseline: "TWQ_M15_TRACKER_REPLAY_BASELINE",
      m15_tracker_replay_session_artifact: "TWQ_M15_TRACKER_REPLAY_SESSION_ARTIFACT",
      m15_tracker_replay_candidate_json: "TWQ_M15_TRACKER_REPLAY_CANDIDATE_JSON",
      m15_tracker_replay_out_dir: "TWQ_M15_TRACKER_REPLAY_OUT_DIR",
      m15_tracker_replay_comparison_json: "TWQ_M15_TRACKER_REPLAY_COMPARISON_JSON",
      m15_tracker_replay_comparison_log: "TWQ_M15_TRACKER_REPLAY_COMPARISON_LOG",
      m15_tracker_replay_summary_md: "TWQ_M15_TRACKER_REPLAY_SUMMARY_MD",
      m15_tracker_replay_label: "TWQ_M15_TRACKER_REPLAY_LABEL"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp bundle_pressure_provider_env(script_env, opts) do
    option_env = %{
      m15_bundle_baseline: "TWQ_M15_BUNDLE_BASELINE",
      m15_bundle_candidate_json: "TWQ_M15_BUNDLE_CANDIDATE_JSON",
      m15_bundle_out_dir: "TWQ_M15_BUNDLE_OUT_DIR",
      m15_bundle_serial_log: "TWQ_M15_BUNDLE_SERIAL_LOG",
      m15_bundle_comparison_json: "TWQ_M15_BUNDLE_COMPARISON_JSON",
      m15_bundle_comparison_log: "TWQ_M15_BUNDLE_COMPARISON_LOG",
      m15_bundle_summary_md: "TWQ_M15_BUNDLE_SUMMARY_MD",
      m15_bundle_label: "TWQ_M15_BUNDLE_LABEL",
      m15_bundle_capture_modes: "TWQ_M15_BUNDLE_CAPTURE_MODES",
      m15_bundle_interval_ms: "TWQ_M15_BUNDLE_INTERVAL_MS",
      m15_bundle_pressure_ms: "TWQ_M15_BUNDLE_PRESSURE_MS",
      m15_bundle_sustained_ms: "TWQ_M15_BUNDLE_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp bundle_replay_env(script_env, opts) do
    option_env = %{
      m15_bundle_replay_baseline: "TWQ_M15_BUNDLE_REPLAY_BASELINE",
      m15_bundle_replay_session_artifact: "TWQ_M15_BUNDLE_REPLAY_SESSION_ARTIFACT",
      m15_bundle_replay_candidate_json: "TWQ_M15_BUNDLE_REPLAY_CANDIDATE_JSON",
      m15_bundle_replay_out_dir: "TWQ_M15_BUNDLE_REPLAY_OUT_DIR",
      m15_bundle_replay_comparison_json: "TWQ_M15_BUNDLE_REPLAY_COMPARISON_JSON",
      m15_bundle_replay_comparison_log: "TWQ_M15_BUNDLE_REPLAY_COMPARISON_LOG",
      m15_bundle_replay_summary_md: "TWQ_M15_BUNDLE_REPLAY_SUMMARY_MD",
      m15_bundle_replay_label: "TWQ_M15_BUNDLE_REPLAY_LABEL"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp tbbx_n0_gcd_only_env(script_env, opts) do
    option_env = %{
      m15_tbbx_n0_gcd_out_dir: "TWQ_M15_TBBX_N0_GCD_OUT_DIR",
      m15_tbbx_n0_gcd_candidate_json: "TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON",
      m15_tbbx_n0_gcd_serial_log: "TWQ_M15_TBBX_N0_GCD_SERIAL_LOG",
      m15_tbbx_n0_gcd_summary_md: "TWQ_M15_TBBX_N0_GCD_SUMMARY_MD",
      m15_tbbx_n0_gcd_interval_ms: "TWQ_M15_TBBX_N0_GCD_INTERVAL_MS",
      m15_tbbx_n0_gcd_pressure_ms: "TWQ_M15_TBBX_N0_GCD_PRESSURE_MS",
      m15_tbbx_n0_gcd_sustained_ms: "TWQ_M15_TBBX_N0_GCD_SUSTAINED_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp pressure_provider_stack_env(script_env, opts) do
    option_env = %{
      m15_stack_out_dir: "TWQ_M15_STACK_OUT_DIR",
      m15_stack_summary_md: "TWQ_M15_STACK_SUMMARY_MD",
      m15_stack_json: "TWQ_M15_STACK_JSON",
      m15_stack_contract_json: "TWQ_M15_STACK_CONTRACT_JSON",
      m15_stack_crossover_source: "TWQ_M15_STACK_CROSSOVER_SOURCE",
      m15_stack_derived_baseline: "TWQ_M15_STACK_DERIVED_BASELINE",
      m15_stack_live_baseline: "TWQ_M15_STACK_LIVE_BASELINE",
      m15_stack_preview_baseline: "TWQ_M15_STACK_PREVIEW_BASELINE",
      m15_stack_adapter_baseline: "TWQ_M15_STACK_ADAPTER_BASELINE",
      m15_stack_session_baseline: "TWQ_M15_STACK_SESSION_BASELINE",
      m15_stack_observer_baseline: "TWQ_M15_STACK_OBSERVER_BASELINE",
      m15_stack_tracker_baseline: "TWQ_M15_STACK_TRACKER_BASELINE",
      m15_stack_bundle_baseline: "TWQ_M15_STACK_BUNDLE_BASELINE",
      m15_stack_derived_candidate_json: "TWQ_M15_STACK_DERIVED_CANDIDATE_JSON",
      m15_stack_live_candidate_json: "TWQ_M15_STACK_LIVE_CANDIDATE_JSON",
      m15_stack_preview_candidate_json: "TWQ_M15_STACK_PREVIEW_CANDIDATE_JSON",
      m15_stack_adapter_candidate_json: "TWQ_M15_STACK_ADAPTER_CANDIDATE_JSON",
      m15_stack_session_candidate_json: "TWQ_M15_STACK_SESSION_CANDIDATE_JSON",
      m15_stack_observer_candidate_json: "TWQ_M15_STACK_OBSERVER_CANDIDATE_JSON",
      m15_stack_tracker_candidate_json: "TWQ_M15_STACK_TRACKER_CANDIDATE_JSON",
      m15_stack_bundle_candidate_json: "TWQ_M15_STACK_BUNDLE_CANDIDATE_JSON",
      m15_stack_observer_replay_session_artifact:
        "TWQ_M15_STACK_OBSERVER_REPLAY_SESSION_ARTIFACT",
      m15_stack_tracker_replay_session_artifact: "TWQ_M15_STACK_TRACKER_REPLAY_SESSION_ARTIFACT",
      m15_stack_bundle_replay_session_artifact: "TWQ_M15_STACK_BUNDLE_REPLAY_SESSION_ARTIFACT"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end

  defp command_to_map(%Command.Result{} = result) do
    %{
      command: result.command,
      args: result.args,
      cwd: result.cwd,
      env: result.env,
      output: result.output,
      exit_status: result.exit_status,
      duration_ms: result.duration_ms,
      timed_out?: result.timed_out?
    }
  end

  defp probe_validation_failures(serial_log) do
    probe_lines = zig_probe_lines(serial_log)
    workqueue_probe_lines = zig_workqueue_probe_lines(serial_log)
    dispatch_probe_lines = dispatch_probe_lines(serial_log)
    swift_probe_lines = swift_probe_lines(serial_log)
    dispatch_basic_line = dispatch_probe_line_for_mode(dispatch_probe_lines, "\"mode\":\"basic\"")

    dispatch_pressure_line =
      dispatch_probe_line_for_mode(dispatch_probe_lines, "\"mode\":\"pressure\"")

    dispatch_burst_line =
      dispatch_probe_line_for_mode(dispatch_probe_lines, "\"mode\":\"burst-reuse\"")

    workqueue_timeout_line =
      dispatch_probe_line_for_mode(workqueue_probe_lines, "\"mode\":\"idle-timeout\"")

    dispatch_timeout_gap_line =
      dispatch_probe_line_for_mode(dispatch_probe_lines, "\"mode\":\"timeout-gap\"")

    dispatch_sustained_line =
      dispatch_probe_line_for_mode(dispatch_probe_lines, "\"mode\":\"sustained\"")

    dispatch_resume_repeat_line =
      dispatch_probe_line_for_mode(
        dispatch_probe_lines,
        "\"mode\":\"main-executor-resume-repeat\""
      )

    swift_async_smoke_line =
      dispatch_probe_line_for_mode(swift_probe_lines, "\"mode\":\"async-smoke\"")

    swift_dispatch_line =
      dispatch_probe_line_for_mode(swift_probe_lines, "\"mode\":\"dispatch-control\"")

    swift_mainqueue_resume_line =
      dispatch_probe_line_for_mode(swift_probe_lines, "\"mode\":\"mainqueue-resume\"")

    dispatch_basic_before =
      extract_section(
        serial_log,
        "=== twq dispatch basic stats before ===",
        "=== twq dispatch basic stats before end ==="
      )

    dispatch_basic_after =
      extract_section(
        serial_log,
        "=== twq dispatch basic stats after ===",
        "=== twq dispatch basic stats after end ==="
      )

    dispatch_pressure_before =
      extract_section(
        serial_log,
        "=== twq dispatch pressure stats before ===",
        "=== twq dispatch pressure stats before end ==="
      )

    dispatch_pressure_after =
      extract_section(
        serial_log,
        "=== twq dispatch pressure stats after ===",
        "=== twq dispatch pressure stats after end ==="
      )

    dispatch_burst_before =
      extract_section(
        serial_log,
        "=== twq dispatch burst stats before ===",
        "=== twq dispatch burst stats before end ==="
      )

    dispatch_burst_after =
      extract_section(
        serial_log,
        "=== twq dispatch burst stats after ===",
        "=== twq dispatch burst stats after end ==="
      )

    workqueue_timeout_before =
      extract_section(
        serial_log,
        "=== twq workqueue timeout stats before ===",
        "=== twq workqueue timeout stats before end ==="
      )

    workqueue_timeout_after =
      extract_section(
        serial_log,
        "=== twq workqueue timeout stats after ===",
        "=== twq workqueue timeout stats after end ==="
      )

    dispatch_timeout_gap_before =
      extract_section(
        serial_log,
        "=== twq dispatch timeout-gap stats before ===",
        "=== twq dispatch timeout-gap stats before end ==="
      )

    dispatch_timeout_gap_after =
      extract_section(
        serial_log,
        "=== twq dispatch timeout-gap stats after ===",
        "=== twq dispatch timeout-gap stats after end ==="
      )

    dispatch_sustained_before =
      extract_section(
        serial_log,
        "=== twq dispatch sustained stats before ===",
        "=== twq dispatch sustained stats before end ==="
      )

    dispatch_sustained_after =
      extract_section(
        serial_log,
        "=== twq dispatch sustained stats after ===",
        "=== twq dispatch sustained stats after end ==="
      )

    dispatch_resume_repeat_before =
      extract_section(
        serial_log,
        "=== twq dispatch main-executor-resume-repeat stats before ===",
        "=== twq dispatch main-executor-resume-repeat stats before end ==="
      )

    dispatch_resume_repeat_after =
      extract_section(
        serial_log,
        "=== twq dispatch main-executor-resume-repeat stats after ===",
        "=== twq dispatch main-executor-resume-repeat stats after end ==="
      )

    swift_dispatch_before =
      extract_section(
        serial_log,
        "=== twq swift dispatch stats before ===",
        "=== twq swift dispatch stats before end ==="
      )

    swift_dispatch_after =
      extract_section(
        serial_log,
        "=== twq swift dispatch stats after ===",
        "=== twq swift dispatch stats after end ==="
      )

    swift_mainqueue_resume_before =
      extract_section(
        serial_log,
        "=== twq swift mainqueue resume stats before ===",
        "=== twq swift mainqueue resume stats before end ==="
      )

    swift_mainqueue_resume_after =
      extract_section(
        serial_log,
        "=== twq swift mainqueue resume stats after ===",
        "=== twq swift mainqueue resume stats after end ==="
      )

    [
      {"zig init rc",
       probe_line?(probe_lines, "\"mode\":\"init\"", "\"rc\":19", "\"errno_name\":\"OK\"")},
      {"zig setup-dispatch rc",
       probe_line?(
         probe_lines,
         "\"mode\":\"setup-dispatch\"",
         "\"rc\":0",
         "\"errno_name\":\"OK\""
       )},
      {"zig reqthreads rc=2",
       probe_line?(probe_lines, "\"mode\":\"reqthreads\"", "\"rc\":2", "\"errno_name\":\"OK\"")},
      {"zig reqthreads rc=4",
       probe_line?(probe_lines, "\"mode\":\"reqthreads\"", "\"rc\":4", "\"errno_name\":\"OK\"")},
      {"zig reqthreads rc=3",
       probe_line?(probe_lines, "\"mode\":\"reqthreads\"", "\"rc\":3", "\"errno_name\":\"OK\"")},
      {"zig thread-enter rc",
       probe_line?(probe_lines, "\"mode\":\"thread-enter\"", "\"rc\":0", "\"errno_name\":\"OK\"")},
      {"zig thread-return rc",
       probe_line?(probe_lines, "\"mode\":\"thread-return\"", "\"rc\":0", "\"errno_name\":\"OK\"")},
      {"zig should-narrow false rc",
       probe_line?(probe_lines, "\"mode\":\"should-narrow\"", "\"rc\":0", "\"errno_name\":\"OK\"")},
      {"zig should-narrow true rc",
       probe_line?(probe_lines, "\"mode\":\"should-narrow\"", "\"rc\":1", "\"errno_name\":\"OK\"")},
      {"zig invalid op EINVAL",
       probe_line?(probe_lines, "\"mode\":\"raw\"", "\"op\":9999", "\"errno_name\":\"EINVAL\"")},
      {"sysctl busy_window_usecs",
       String.contains?(serial_log, "kern.twq.busy_window_usecs: 50000")},
      {"sysctl init_count", String.contains?(serial_log, "kern.twq.init_count: 3")},
      {"sysctl thread_enter_count",
       String.contains?(serial_log, "kern.twq.thread_enter_count: 1")},
      {"sysctl setup_dispatch_count",
       String.contains?(serial_log, "kern.twq.setup_dispatch_count: 3")},
      {"sysctl reqthreads_count", String.contains?(serial_log, "kern.twq.reqthreads_count: 5")},
      {"sysctl thread_return_count",
       String.contains?(serial_log, "kern.twq.thread_return_count: 2")},
      {"sysctl should_narrow_count",
       String.contains?(serial_log, "kern.twq.should_narrow_count: 3")},
      {"sysctl should_narrow_true_count",
       String.contains?(serial_log, "kern.twq.should_narrow_true_count: 1")},
      {"sysctl switch_block_count",
       String.contains?(serial_log, "kern.twq.switch_block_count: 1")},
      {"sysctl switch_unblock_count",
       String.contains?(serial_log, "kern.twq.switch_unblock_count: 1")},
      {"sysctl bucket_thread_enter_total",
       String.contains?(serial_log, "kern.twq.bucket_thread_enter_total: 0,0,0,0,0,1")},
      {"sysctl bucket_req_total",
       String.contains?(serial_log, "kern.twq.bucket_req_total: 0,0,0,10,0,1")},
      {"sysctl bucket_admit_total",
       String.contains?(serial_log, "kern.twq.bucket_admit_total: 0,0,0,9,0,1")},
      {"sysctl bucket_thread_return_total",
       String.contains?(serial_log, "kern.twq.bucket_thread_return_total: 0,0,0,1,0,1")},
      {"sysctl bucket_switch_block_total",
       String.contains?(serial_log, "kern.twq.bucket_switch_block_total: 0,0,0,0,0,1")},
      {"sysctl bucket_switch_unblock_total",
       String.contains?(serial_log, "kern.twq.bucket_switch_unblock_total: 0,0,0,0,0,1")},
      {"sysctl bucket_total_current zero",
       String.contains?(serial_log, "kern.twq.bucket_total_current: 0,0,0,0,0,0")},
      {"sysctl bucket_idle_current zero",
       String.contains?(serial_log, "kern.twq.bucket_idle_current: 0,0,0,0,0,0")},
      {"sysctl bucket_active_current zero",
       String.contains?(serial_log, "kern.twq.bucket_active_current: 0,0,0,0,0,0")},
      {"workqueue supported features",
       workqueue_probe_line?(
         workqueue_probe_lines,
         "\"mode\":\"supported\"",
         "\"status\":\"ok\"",
         "\"features\":19"
       )},
      {"workqueue init",
       workqueue_probe_line?(
         workqueue_probe_lines,
         "\"mode\":\"init\"",
         "\"status\":\"ok\"",
         "\"rc\":0"
       )},
      {"workqueue addthreads",
       workqueue_probe_line?(
         workqueue_probe_lines,
         "\"mode\":\"addthreads\"",
         "\"status\":\"ok\"",
         "\"rc\":0"
       )},
      {"workqueue callbacks observed",
       workqueue_probe_line?(
         workqueue_probe_lines,
         "\"mode\":\"callbacks\"",
         "\"status\":\"ok\"",
         "\"observed\":2"
       )},
      {"workqueue callbacks priority",
       workqueue_probe_line?(
         workqueue_probe_lines,
         "\"mode\":\"callbacks\"",
         "\"timed_out\":false",
         "\"priority\":5376"
       )},
      {"workqueue timeout status", String.contains?(workqueue_timeout_line, "\"status\":\"ok\"")},
      {"workqueue timeout before exceeds warm floor",
       line_int_value(workqueue_timeout_line, "before_total") >
         line_int_value(workqueue_timeout_line, "warm_floor")},
      {"workqueue timeout settled idle matches total",
       line_int_value(workqueue_timeout_line, "settled_idle") ==
         line_int_value(workqueue_timeout_line, "settled_total")},
      {"workqueue timeout settled active zero",
       line_int_value(workqueue_timeout_line, "settled_active") == 0},
      {"workqueue timeout settles to warm floor",
       line_int_value(workqueue_timeout_line, "settled_total") ==
         line_int_value(workqueue_timeout_line, "warm_floor")},
      {"workqueue timeout reqthreads_count delta",
       section_value(workqueue_timeout_after, "kern.twq.reqthreads_count") >
         section_value(workqueue_timeout_before, "kern.twq.reqthreads_count")},
      {"workqueue timeout thread_enter_count delta",
       section_value(workqueue_timeout_after, "kern.twq.thread_enter_count") >
         section_value(workqueue_timeout_before, "kern.twq.thread_enter_count")},
      {"workqueue timeout thread_return_count delta",
       section_value(workqueue_timeout_after, "kern.twq.thread_return_count") >
         section_value(workqueue_timeout_before, "kern.twq.thread_return_count")},
      {"workqueue timeout after bucket total zero",
       section_array_value(workqueue_timeout_after, "kern.twq.bucket_total_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"workqueue timeout after bucket idle zero",
       section_array_value(workqueue_timeout_after, "kern.twq.bucket_idle_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"workqueue timeout after bucket active zero",
       section_array_value(workqueue_timeout_after, "kern.twq.bucket_active_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"dispatch supported features",
       dispatch_probe_line?(
         dispatch_probe_lines,
         "\"mode\":\"supported\"",
         "\"status\":\"ok\"",
         "\"features\":19"
       )},
      {"dispatch basic status", String.contains?(dispatch_basic_line, "\"status\":\"ok\"")},
      {"dispatch basic requested", String.contains?(dispatch_basic_line, "\"requested\":8")},
      {"dispatch basic completed", String.contains?(dispatch_basic_line, "\"completed\":8")},
      {"dispatch basic timed_out", String.contains?(dispatch_basic_line, "\"timed_out\":false")},
      {"dispatch basic main thread callbacks",
       String.contains?(dispatch_basic_line, "\"main_thread_callbacks\":0")},
      {"dispatch pressure status", String.contains?(dispatch_pressure_line, "\"status\":\"ok\"")},
      {"dispatch pressure requested default",
       String.contains?(dispatch_pressure_line, "\"requested_default\":8")},
      {"dispatch pressure requested high",
       String.contains?(dispatch_pressure_line, "\"requested_high\":1")},
      {"dispatch pressure completed default",
       String.contains?(dispatch_pressure_line, "\"completed_default\":8")},
      {"dispatch pressure completed high",
       String.contains?(dispatch_pressure_line, "\"completed_high\":1")},
      {"dispatch pressure timed_out",
       String.contains?(dispatch_pressure_line, "\"timed_out\":false")},
      {"dispatch pressure main thread callbacks",
       String.contains?(dispatch_pressure_line, "\"main_thread_callbacks\":0")},
      {"dispatch pressure reduces default max inflight",
       line_int_value(dispatch_basic_line, "max_inflight") >
         line_int_value(dispatch_pressure_line, "default_max_inflight")},
      {"dispatch basic init_count delta",
       section_value(dispatch_basic_after, "kern.twq.init_count") >
         section_value(dispatch_basic_before, "kern.twq.init_count")},
      {"dispatch basic setup_dispatch_count delta",
       section_value(dispatch_basic_after, "kern.twq.setup_dispatch_count") >
         section_value(dispatch_basic_before, "kern.twq.setup_dispatch_count")},
      {"dispatch basic reqthreads_count delta",
       section_value(dispatch_basic_after, "kern.twq.reqthreads_count") >
         section_value(dispatch_basic_before, "kern.twq.reqthreads_count")},
      {"dispatch basic thread_enter_count delta",
       section_value(dispatch_basic_after, "kern.twq.thread_enter_count") >
         section_value(dispatch_basic_before, "kern.twq.thread_enter_count")},
      {"dispatch pressure init_count delta",
       section_value(dispatch_pressure_after, "kern.twq.init_count") >
         section_value(dispatch_pressure_before, "kern.twq.init_count")},
      {"dispatch pressure setup_dispatch_count delta",
       section_value(dispatch_pressure_after, "kern.twq.setup_dispatch_count") >
         section_value(dispatch_pressure_before, "kern.twq.setup_dispatch_count")},
      {"dispatch pressure reqthreads_count delta",
       section_value(dispatch_pressure_after, "kern.twq.reqthreads_count") >
         section_value(dispatch_pressure_before, "kern.twq.reqthreads_count")},
      {"dispatch pressure thread_enter_count delta",
       section_value(dispatch_pressure_after, "kern.twq.thread_enter_count") >
         section_value(dispatch_pressure_before, "kern.twq.thread_enter_count")},
      {"dispatch pressure switch_block_count delta",
       section_value(dispatch_pressure_after, "kern.twq.switch_block_count") >
         section_value(dispatch_pressure_before, "kern.twq.switch_block_count")},
      {"dispatch pressure switch_unblock_count delta",
       section_value(dispatch_pressure_after, "kern.twq.switch_unblock_count") >
         section_value(dispatch_pressure_before, "kern.twq.switch_unblock_count")},
      {"dispatch pressure bucket req delta",
       bucket_delta(
         dispatch_pressure_before,
         dispatch_pressure_after,
         "kern.twq.bucket_req_total",
         3
       ) > 0},
      {"dispatch pressure bucket admit delta",
       bucket_delta(
         dispatch_pressure_before,
         dispatch_pressure_after,
         "kern.twq.bucket_admit_total",
         3
       ) > 0},
      {"dispatch pressure req exceeds admit",
       bucket_delta(
         dispatch_pressure_before,
         dispatch_pressure_after,
         "kern.twq.bucket_req_total",
         3
       ) >
         bucket_delta(
           dispatch_pressure_before,
           dispatch_pressure_after,
           "kern.twq.bucket_admit_total",
           3
         )},
      {"dispatch pressure bucket switch_block delta",
       bucket_delta(
         dispatch_pressure_before,
         dispatch_pressure_after,
         "kern.twq.bucket_switch_block_total",
         3
       ) > 0},
      {"dispatch pressure bucket switch_unblock delta",
       bucket_delta(
         dispatch_pressure_before,
         dispatch_pressure_after,
         "kern.twq.bucket_switch_unblock_total",
         3
       ) > 0},
      {"dispatch burst status", String.contains?(dispatch_burst_line, "\"status\":\"ok\"")},
      {"dispatch burst timed_out", String.contains?(dispatch_burst_line, "\"timed_out\":false")},
      {"dispatch burst main thread callbacks",
       String.contains?(dispatch_burst_line, "\"main_thread_callbacks\":0")},
      {"dispatch burst no new threads after first round",
       dispatch_burst_line
       |> line_array_values("round_new_threads")
       |> Enum.drop(1)
       |> Enum.all?(&(&1 == 0))},
      {"dispatch burst no narrow churn",
       dispatch_burst_line
       |> line_array_values("round_should_narrow_true_delta")
       |> Enum.all?(&(&1 == 0))},
      {"dispatch burst rest totals bounded",
       dispatch_burst_line
       |> line_array_values("round_rest_total")
       |> Enum.max(fn -> 0 end) <= line_int_value(dispatch_burst_line, "warm_floor")},
      {"dispatch burst rest active zero",
       dispatch_burst_line
       |> line_array_values("round_rest_active")
       |> Enum.all?(&(&1 == 0))},
      {"dispatch burst settled idle matches total",
       line_int_value(dispatch_burst_line, "settled_idle") ==
         line_int_value(dispatch_burst_line, "settled_total")},
      {"dispatch burst settled active zero",
       line_int_value(dispatch_burst_line, "settled_active") == 0},
      {"dispatch burst settled within warm floor",
       line_int_value(dispatch_burst_line, "settled_total") <=
         line_int_value(dispatch_burst_line, "warm_floor")},
      {"dispatch burst reqthreads_count delta",
       section_value(dispatch_burst_after, "kern.twq.reqthreads_count") >
         section_value(dispatch_burst_before, "kern.twq.reqthreads_count")},
      {"dispatch burst thread_enter_count delta",
       section_value(dispatch_burst_after, "kern.twq.thread_enter_count") >
         section_value(dispatch_burst_before, "kern.twq.thread_enter_count")},
      {"dispatch burst after bucket total zero",
       section_array_value(dispatch_burst_after, "kern.twq.bucket_total_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch burst after bucket idle zero",
       section_array_value(dispatch_burst_after, "kern.twq.bucket_idle_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch burst after bucket active zero",
       section_array_value(dispatch_burst_after, "kern.twq.bucket_active_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch timeout-gap status",
       String.contains?(dispatch_timeout_gap_line, "\"status\":\"ok\"")},
      {"dispatch timeout-gap timed_out",
       String.contains?(dispatch_timeout_gap_line, "\"timed_out\":false")},
      {"dispatch timeout-gap main thread callbacks",
       String.contains?(dispatch_timeout_gap_line, "\"main_thread_callbacks\":0")},
      {"dispatch timeout-gap no new threads after first round",
       dispatch_timeout_gap_line
       |> line_array_values("round_new_threads")
       |> Enum.drop(1)
       |> Enum.all?(&(&1 == 0))},
      {"dispatch timeout-gap rest totals bounded",
       dispatch_timeout_gap_line
       |> line_array_values("round_rest_total")
       |> Enum.max(fn -> 0 end) <= line_int_value(dispatch_timeout_gap_line, "warm_floor")},
      {"dispatch timeout-gap settled idle matches total",
       line_int_value(dispatch_timeout_gap_line, "settled_idle") ==
         line_int_value(dispatch_timeout_gap_line, "settled_total")},
      {"dispatch timeout-gap settled active zero",
       line_int_value(dispatch_timeout_gap_line, "settled_active") == 0},
      {"dispatch timeout-gap settled within warm floor",
       line_int_value(dispatch_timeout_gap_line, "settled_total") <=
         line_int_value(dispatch_timeout_gap_line, "warm_floor")},
      {"dispatch timeout-gap reqthreads_count delta",
       section_value(dispatch_timeout_gap_after, "kern.twq.reqthreads_count") >
         section_value(dispatch_timeout_gap_before, "kern.twq.reqthreads_count")},
      {"dispatch timeout-gap thread_enter_count delta",
       section_value(dispatch_timeout_gap_after, "kern.twq.thread_enter_count") >
         section_value(dispatch_timeout_gap_before, "kern.twq.thread_enter_count")},
      {"dispatch timeout-gap after bucket total zero",
       section_array_value(dispatch_timeout_gap_after, "kern.twq.bucket_total_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"dispatch timeout-gap after bucket idle zero",
       section_array_value(dispatch_timeout_gap_after, "kern.twq.bucket_idle_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"dispatch timeout-gap after bucket active zero",
       section_array_value(dispatch_timeout_gap_after, "kern.twq.bucket_active_current") ==
         [0, 0, 0, 0, 0, 0]},
      {"dispatch sustained status",
       String.contains?(dispatch_sustained_line, "\"status\":\"ok\"")},
      {"dispatch sustained timed_out",
       String.contains?(dispatch_sustained_line, "\"timed_out\":false")},
      {"dispatch sustained main thread callbacks",
       String.contains?(dispatch_sustained_line, "\"main_thread_callbacks\":0")},
      {"dispatch sustained high ready",
       String.contains?(dispatch_sustained_line, "\"high_ready\":true")},
      {"dispatch sustained settled idle matches total",
       line_int_value(dispatch_sustained_line, "settled_idle") ==
         line_int_value(dispatch_sustained_line, "settled_total")},
      {"dispatch sustained settled active zero",
       line_int_value(dispatch_sustained_line, "settled_active") == 0},
      {"dispatch sustained settled within bounded warm pool",
       line_int_value(dispatch_sustained_line, "settled_total") <=
         line_int_value(dispatch_sustained_line, "warm_floor") + 1},
      {"dispatch sustained peak within bounded warm pool",
       line_int_value(dispatch_sustained_line, "peak_sample_total") <=
         line_int_value(dispatch_sustained_line, "warm_floor") + 1},
      {"dispatch sustained sample count",
       line_int_value(dispatch_sustained_line, "sample_count") >= 4},
      {"dispatch sustained reqthreads_count delta",
       section_value(dispatch_sustained_after, "kern.twq.reqthreads_count") >
         section_value(dispatch_sustained_before, "kern.twq.reqthreads_count")},
      {"dispatch sustained thread_enter_count delta",
       section_value(dispatch_sustained_after, "kern.twq.thread_enter_count") >
         section_value(dispatch_sustained_before, "kern.twq.thread_enter_count")},
      {"dispatch sustained switch_block_count delta",
       section_value(dispatch_sustained_after, "kern.twq.switch_block_count") >
         section_value(dispatch_sustained_before, "kern.twq.switch_block_count")},
      {"dispatch sustained switch_unblock_count delta",
       section_value(dispatch_sustained_after, "kern.twq.switch_unblock_count") >
         section_value(dispatch_sustained_before, "kern.twq.switch_unblock_count")},
      {"dispatch sustained bucket req delta",
       bucket_delta(
         dispatch_sustained_before,
         dispatch_sustained_after,
         "kern.twq.bucket_req_total",
         3
       ) > 0},
      {"dispatch sustained bucket admit delta",
       bucket_delta(
         dispatch_sustained_before,
         dispatch_sustained_after,
         "kern.twq.bucket_admit_total",
         3
       ) > 0},
      {"dispatch sustained after bucket total zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_total_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch sustained after bucket idle zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_idle_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch sustained after bucket active zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_active_current") == [
         0,
         0,
         0,
         0,
         0,
         0
       ]},
      {"dispatch resume-repeat status",
       dispatch_resume_repeat_line == "" or
         String.contains?(dispatch_resume_repeat_line, "\"status\":\"ok\"")},
      {"dispatch resume-repeat timed_out",
       dispatch_resume_repeat_line == "" or
         String.contains?(dispatch_resume_repeat_line, "\"timed_out\":false")},
      {"dispatch resume-repeat rounds complete",
       dispatch_resume_repeat_line == "" or
         line_int_value(dispatch_resume_repeat_line, "completed_rounds") ==
           line_int_value(dispatch_resume_repeat_line, "rounds")},
      {"dispatch resume-repeat expected total",
       dispatch_resume_repeat_line == "" or
         line_int_value(dispatch_resume_repeat_line, "total_sum") ==
           line_int_value(dispatch_resume_repeat_line, "expected_total_sum")},
      {"dispatch resume-repeat main thread callbacks",
       dispatch_resume_repeat_line == "" or
         String.contains?(dispatch_resume_repeat_line, "\"main_thread_callbacks\":0")},
      {"dispatch resume-repeat reqthreads_count delta",
       dispatch_resume_repeat_line == "" or
         section_value(dispatch_resume_repeat_after, "kern.twq.reqthreads_count") >
           section_value(dispatch_resume_repeat_before, "kern.twq.reqthreads_count")},
      {"dispatch resume-repeat thread_enter_count delta",
       dispatch_resume_repeat_line == "" or
         section_value(dispatch_resume_repeat_after, "kern.twq.thread_enter_count") >
           section_value(dispatch_resume_repeat_before, "kern.twq.thread_enter_count")},
      {"dispatch resume-repeat after bucket total zero",
       dispatch_resume_repeat_line == "" or
         section_array_value(dispatch_resume_repeat_after, "kern.twq.bucket_total_current") ==
           [0, 0, 0, 0, 0, 0]},
      {"dispatch resume-repeat after bucket idle zero",
       dispatch_resume_repeat_line == "" or
         section_array_value(dispatch_resume_repeat_after, "kern.twq.bucket_idle_current") ==
           [0, 0, 0, 0, 0, 0]},
      {"dispatch resume-repeat after bucket active zero",
       dispatch_resume_repeat_line == "" or
         section_array_value(dispatch_resume_repeat_after, "kern.twq.bucket_active_current") ==
           [0, 0, 0, 0, 0, 0]},
      {"swift async smoke status", String.contains?(swift_async_smoke_line, "\"status\":\"ok\"")},
      {"swift dispatch status", String.contains?(swift_dispatch_line, "\"status\":\"ok\"")},
      {"swift dispatch completed", line_int_value(swift_dispatch_line, "completed") == 8},
      {"swift dispatch sum", line_int_value(swift_dispatch_line, "sum") == 28},
      {"swift dispatch timed_out false",
       String.contains?(swift_dispatch_line, "\"timed_out\":false")},
      {"swift dispatch init_count delta",
       section_value(swift_dispatch_after, "kern.twq.init_count") >
         section_value(swift_dispatch_before, "kern.twq.init_count")},
      {"swift dispatch setup_dispatch_count delta",
       section_value(swift_dispatch_after, "kern.twq.setup_dispatch_count") >
         section_value(swift_dispatch_before, "kern.twq.setup_dispatch_count")},
      {"swift dispatch reqthreads_count delta",
       section_value(swift_dispatch_after, "kern.twq.reqthreads_count") >
         section_value(swift_dispatch_before, "kern.twq.reqthreads_count")},
      {"swift dispatch thread_enter_count delta",
       section_value(swift_dispatch_after, "kern.twq.thread_enter_count") >
         section_value(swift_dispatch_before, "kern.twq.thread_enter_count")},
      {"swift mainqueue-resume status",
       String.contains?(swift_mainqueue_resume_line, "\"status\":\"ok\"")},
      {"swift mainqueue-resume value",
       String.contains?(swift_mainqueue_resume_line, "\"value\":42")},
      {"swift mainqueue-resume reqthreads_count delta",
       section_value(swift_mainqueue_resume_after, "kern.twq.reqthreads_count") >
         section_value(swift_mainqueue_resume_before, "kern.twq.reqthreads_count")},
      {"swift mainqueue-resume thread_enter_count delta",
       section_value(swift_mainqueue_resume_after, "kern.twq.thread_enter_count") >
         section_value(swift_mainqueue_resume_before, "kern.twq.thread_enter_count")}
    ]
    |> Enum.reject(fn {_name, ok?} -> ok? end)
    |> Enum.map(&elem(&1, 0))
  end

  defp probe_meta(%Env{} = env) do
    %{
      vm_name: env.vm_name,
      vm_image: env.vm_image,
      serial_log: env.serial_log
    }
  end

  defp read_serial_log(%Env{} = env) do
    case File.read(env.serial_log) do
      {:ok, data} -> data
      {:error, _reason} -> ""
    end
  end

  defp zig_probe_lines(serial_log) do
    serial_log
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, "\"kind\":\"zig-probe\""))
  end

  defp zig_workqueue_probe_lines(serial_log) do
    serial_log
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, "\"kind\":\"zig-workq-probe\""))
  end

  defp dispatch_probe_lines(serial_log) do
    serial_log
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, "\"kind\":\"dispatch-probe\""))
  end

  defp swift_probe_lines(serial_log) do
    serial_log
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, "\"kind\":\"swift-probe\""))
  end

  defp swift_probe_profile(serial_log) do
    serial_log
    |> extract_section("=== twq swift profile ===", "=== twq swift profile end ===")
    |> String.trim()
  end

  defp swift_timeout_modes(serial_log) do
    serial_log
    |> swift_probe_lines()
    |> Enum.filter(&String.contains?(&1, "\"status\":\"timeout\""))
    |> Enum.map(fn line ->
      case Regex.run(~r/"mode":"([^"]+)"/, line) do
        [_, mode] -> mode
        _ -> "unknown"
      end
    end)
  end

  defp probe_line?(probe_lines, mode_fragment, result_fragment, errno_fragment) do
    Enum.any?(probe_lines, fn line ->
      String.contains?(line, mode_fragment) and
        String.contains?(line, result_fragment) and
        String.contains?(line, errno_fragment)
    end)
  end

  defp workqueue_probe_line?(probe_lines, fragment1, fragment2, fragment3) do
    Enum.any?(probe_lines, fn line ->
      String.contains?(line, fragment1) and
        String.contains?(line, fragment2) and
        String.contains?(line, fragment3)
    end)
  end

  defp dispatch_probe_line?(probe_lines, fragment1, fragment2, fragment3) do
    workqueue_probe_line?(probe_lines, fragment1, fragment2, fragment3)
  end

  defp dispatch_probe_line_for_mode(probe_lines, mode_fragment) do
    probe_lines
    |> Enum.filter(&String.contains?(&1, mode_fragment))
    |> List.last()
    |> Kernel.||("")
  end

  defp extract_section(serial_log, start_marker, end_marker) do
    case String.split(serial_log, start_marker, parts: 2) do
      [_prefix, rest] ->
        case String.split(rest, end_marker, parts: 2) do
          [section, _suffix] -> section
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp section_value(section, key) do
    case Regex.run(~r/#{Regex.escape(key)}: (\d+)/, section) do
      [_, value] -> String.to_integer(value)
      _ -> -1
    end
  end

  defp section_array_value(section, key) do
    case Regex.run(~r/#{Regex.escape(key)}: ([0-9,]+)/, section) do
      [_, value] ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_integer/1)

      _ ->
        []
    end
  end

  defp bucket_delta(before_section, after_section, key, index) do
    before_values = section_array_value(before_section, key)
    after_values = section_array_value(after_section, key)
    Enum.at(after_values, index, -1) - Enum.at(before_values, index, -1)
  end

  defp line_int_value(line, key) do
    case Regex.run(~r/"#{Regex.escape(key)}":(\d+)/, line) do
      [_, value] -> String.to_integer(value)
      _ -> -1
    end
  end

  defp line_array_values(line, key) do
    case Regex.run(~r/"#{Regex.escape(key)}":\[([0-9,]*)\]/, line) do
      [_, ""] ->
        []

      [_, value] ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_integer/1)

      _ ->
        []
    end
  end
end
