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

  @spec probe_guest(keyword()) :: Result.t()
  def probe_guest(opts \\ []) do
    env = build_env(opts)
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
            serial_ok? = validation_failures == []
            exit_ok? = run_result.exit_status in @normal_bhyve_exit_statuses and not run_result.timed_out?

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
      {"zig init rc", probe_line?(probe_lines, "\"mode\":\"init\"", "\"rc\":19", "\"errno_name\":\"OK\"")},
      {"zig setup-dispatch rc",
       probe_line?(probe_lines, "\"mode\":\"setup-dispatch\"", "\"rc\":0", "\"errno_name\":\"OK\"")},
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
      {"sysctl busy_window_usecs", String.contains?(serial_log, "kern.twq.busy_window_usecs: 50000")},
      {"sysctl init_count", String.contains?(serial_log, "kern.twq.init_count: 3")},
      {"sysctl thread_enter_count", String.contains?(serial_log, "kern.twq.thread_enter_count: 1")},
      {"sysctl setup_dispatch_count", String.contains?(serial_log, "kern.twq.setup_dispatch_count: 3")},
      {"sysctl reqthreads_count", String.contains?(serial_log, "kern.twq.reqthreads_count: 5")},
      {"sysctl thread_return_count", String.contains?(serial_log, "kern.twq.thread_return_count: 2")},
      {"sysctl should_narrow_count", String.contains?(serial_log, "kern.twq.should_narrow_count: 3")},
      {"sysctl should_narrow_true_count",
       String.contains?(serial_log, "kern.twq.should_narrow_true_count: 1")},
      {"sysctl switch_block_count", String.contains?(serial_log, "kern.twq.switch_block_count: 1")},
      {"sysctl switch_unblock_count", String.contains?(serial_log, "kern.twq.switch_unblock_count: 1")},
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
       workqueue_probe_line?(workqueue_probe_lines, "\"mode\":\"supported\"", "\"status\":\"ok\"", "\"features\":19")},
      {"workqueue init",
       workqueue_probe_line?(workqueue_probe_lines, "\"mode\":\"init\"", "\"status\":\"ok\"", "\"rc\":0")},
      {"workqueue addthreads",
       workqueue_probe_line?(workqueue_probe_lines, "\"mode\":\"addthreads\"", "\"status\":\"ok\"", "\"rc\":0")},
      {"workqueue callbacks observed",
       workqueue_probe_line?(workqueue_probe_lines, "\"mode\":\"callbacks\"", "\"status\":\"ok\"", "\"observed\":2")},
      {"workqueue callbacks priority",
       workqueue_probe_line?(workqueue_probe_lines, "\"mode\":\"callbacks\"", "\"timed_out\":false", "\"priority\":5376")},
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
       dispatch_probe_line?(dispatch_probe_lines, "\"mode\":\"supported\"", "\"status\":\"ok\"", "\"features\":19")},
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
       bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_req_total", 3) > 0},
      {"dispatch pressure bucket admit delta",
       bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_admit_total", 3) > 0},
      {"dispatch pressure req exceeds admit",
       bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_req_total", 3) >
         bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_admit_total", 3)},
      {"dispatch pressure bucket switch_block delta",
       bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_switch_block_total", 3) > 0},
      {"dispatch pressure bucket switch_unblock delta",
       bucket_delta(dispatch_pressure_before, dispatch_pressure_after, "kern.twq.bucket_switch_unblock_total", 3) > 0},
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
       section_array_value(dispatch_burst_after, "kern.twq.bucket_total_current") == [0, 0, 0, 0, 0, 0]},
      {"dispatch burst after bucket idle zero",
       section_array_value(dispatch_burst_after, "kern.twq.bucket_idle_current") == [0, 0, 0, 0, 0, 0]},
      {"dispatch burst after bucket active zero",
       section_array_value(dispatch_burst_after, "kern.twq.bucket_active_current") == [0, 0, 0, 0, 0, 0]},
      {"dispatch timeout-gap status", String.contains?(dispatch_timeout_gap_line, "\"status\":\"ok\"")},
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
      {"dispatch sustained status", String.contains?(dispatch_sustained_line, "\"status\":\"ok\"")},
      {"dispatch sustained timed_out", String.contains?(dispatch_sustained_line, "\"timed_out\":false")},
      {"dispatch sustained main thread callbacks",
       String.contains?(dispatch_sustained_line, "\"main_thread_callbacks\":0")},
      {"dispatch sustained high ready", String.contains?(dispatch_sustained_line, "\"high_ready\":true")},
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
       bucket_delta(dispatch_sustained_before, dispatch_sustained_after, "kern.twq.bucket_req_total", 3) > 0},
      {"dispatch sustained bucket admit delta",
       bucket_delta(dispatch_sustained_before, dispatch_sustained_after, "kern.twq.bucket_admit_total", 3) > 0},
      {"dispatch sustained after bucket total zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_total_current") == [0, 0, 0, 0, 0, 0]},
      {"dispatch sustained after bucket idle zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_idle_current") == [0, 0, 0, 0, 0, 0]},
      {"dispatch sustained after bucket active zero",
       section_array_value(dispatch_sustained_after, "kern.twq.bucket_active_current") == [0, 0, 0, 0, 0, 0]},
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
      {"swift mainqueue-resume value", String.contains?(swift_mainqueue_resume_line, "\"value\":42")},
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
