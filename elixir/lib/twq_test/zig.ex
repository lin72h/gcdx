defmodule TwqTest.Zig do
  @moduledoc """
  Thin Elixir wrappers around the repo's Zig scaffold.

  This is enough for the harness to prove that ExUnit can drive low-level
  helper builds and assert on their output.
  """

  alias TwqTest.{Command, Env}

  @spec abi(keyword()) :: Command.Result.t()
  def abi(opts \\ []) do
    env = build_env(opts)

    Command.run("zig", zig_args(env, ["test-abi"]),
      cd: zig_root(env),
      timeout: env.command_timeout_ms
    )
  end

  @spec build(keyword()) :: Command.Result.t()
  def build(opts \\ []) do
    env = build_env(opts)
    Command.run("zig", zig_args(env, []), cd: zig_root(env), timeout: env.command_timeout_ms)
  end

  @spec build_hotpath_bench(keyword()) :: Command.Result.t()
  def build_hotpath_bench(opts \\ []) do
    env = build_env(opts)

    Command.run("zig", zig_args(env, ["bench-syscall"]),
      cd: zig_root(env),
      timeout: env.command_timeout_ms
    )
  end

  @spec run_hotpath_suite(keyword()) :: Command.Result.t()
  def run_hotpath_suite(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-zig-hotpath-suite.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> hotpath_suite_env(opts),
      timeout: Keyword.get(opts, :suite_timeout_ms, env.command_timeout_ms)
    )
  end

  @spec build_workqueue_probe(keyword()) :: Command.Result.t()
  def build_workqueue_probe(opts \\ []) do
    env = build_env(opts)
    stage_result = prepare_pthread_stage(env)
    source = Path.join(env.repo_root, "csrc/twq_workqueue_probe.c")

    if Command.Result.ok?(stage_result) do
      File.mkdir_p!(Path.dirname(env.workqueue_probe_bin))

      Command.run(
        "cc",
        [
          "-I",
          env.pthread_include_dir,
          source,
          "-L",
          env.pthread_stage_dir,
          "-Wl,-rpath,#{env.pthread_stage_dir}",
          "-lthr",
          "-lc",
          "-o",
          env.workqueue_probe_bin
        ],
        cd: zig_root(env),
        timeout: env.command_timeout_ms
      )
    else
      stage_result
    end
  end

  @spec build_dispatch_probe(keyword()) :: Command.Result.t()
  def build_dispatch_probe(opts \\ []) do
    env = build_env(opts)
    pthread_stage_result = prepare_pthread_stage(env)
    dispatch_stage_result = prepare_dispatch_stage(env)
    source = Path.join(env.repo_root, "csrc/twq_dispatch_probe.c")
    dispatch_probe_bin = Path.join(env.zig_prefix, "bin/twq-dispatch-probe")
    dispatch_build_dir = Path.join(env.artifacts_root, "libdispatch-build")
    dispatch_stage_dir = Path.join(env.artifacts_root, "libdispatch-stage")
    pthread_headers_dir = Path.join(env.artifacts_root, "pthread-headers")
    dispatch_src_dir = Path.join(env.repo_root, "../nx/swift-corelibs-libdispatch")

    cond do
      not Command.Result.ok?(pthread_stage_result) ->
        pthread_stage_result

      not Command.Result.ok?(dispatch_stage_result) ->
        dispatch_stage_result

      true ->
        File.mkdir_p!(Path.dirname(dispatch_probe_bin))

        Command.run(
          "cc",
          [
            "-I",
            dispatch_src_dir,
            "-I",
            dispatch_build_dir,
            "-I",
            pthread_headers_dir,
            source,
            "-L",
            dispatch_stage_dir,
            "-L",
            env.pthread_stage_dir,
            "-Wl,-rpath,#{dispatch_stage_dir}",
            "-Wl,-rpath,#{env.pthread_stage_dir}",
            "-ldispatch",
            "-lthr",
            "-lc",
            "-o",
            dispatch_probe_bin
          ],
          cd: env.repo_root,
          timeout: env.command_timeout_ms
        )
    end
  end

  @spec run_probe(keyword()) :: Command.Result.t()
  def run_probe(opts \\ []) do
    env = build_env(opts)
    build_result = build(opts)
    probe_args = Keyword.get(opts, :probe_args, [])

    if Command.Result.ok?(build_result) do
      probe = env.probe_bin
      Command.run(probe, probe_args, cd: env.repo_root, timeout: env.command_timeout_ms)
    else
      build_result
    end
  end

  defp build_env(opts) do
    opts
    |> Enum.into(%{})
    |> Env.load()
  end

  defp zig_root(%Env{} = env) do
    Path.join(env.repo_root, "zig")
  end

  defp prepare_pthread_stage(%Env{} = env) do
    script = Path.join(env.repo_root, "scripts/libthr/prepare-stage.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  defp prepare_dispatch_stage(%Env{} = env) do
    script = Path.join(env.repo_root, "scripts/libdispatch/prepare-stage.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  defp zig_args(%Env{} = env, steps) do
    [
      "build",
      "--prefix",
      env.zig_prefix,
      "--cache-dir",
      env.zig_cache_dir,
      "--global-cache-dir",
      env.zig_global_cache_dir
      | steps
    ]
  end

  defp hotpath_suite_env(script_env, opts) do
    option_env = %{
      benchmark_json: "TWQ_BENCHMARK_JSON",
      benchmark_label: "TWQ_BENCHMARK_LABEL",
      serial_log: "TWQ_SERIAL_LOG",
      should_narrow_samples: "TWQ_ZIG_BENCH_SHOULD_NARROW_SAMPLES",
      should_narrow_warmup: "TWQ_ZIG_BENCH_SHOULD_NARROW_WARMUP",
      reqthreads_samples: "TWQ_ZIG_BENCH_REQTHREADS_SAMPLES",
      reqthreads_warmup: "TWQ_ZIG_BENCH_REQTHREADS_WARMUP",
      overcommit_samples: "TWQ_ZIG_BENCH_OVERCOMMIT_SAMPLES",
      overcommit_warmup: "TWQ_ZIG_BENCH_OVERCOMMIT_WARMUP",
      thread_enter_samples: "TWQ_ZIG_BENCH_THREAD_ENTER_SAMPLES",
      thread_enter_warmup: "TWQ_ZIG_BENCH_THREAD_ENTER_WARMUP",
      thread_return_samples: "TWQ_ZIG_BENCH_THREAD_RETURN_SAMPLES",
      thread_return_warmup: "TWQ_ZIG_BENCH_THREAD_RETURN_WARMUP",
      thread_transfer_samples: "TWQ_ZIG_BENCH_THREAD_TRANSFER_SAMPLES",
      thread_transfer_warmup: "TWQ_ZIG_BENCH_THREAD_TRANSFER_WARMUP",
      request_count: "TWQ_ZIG_BENCH_REQUEST_COUNT",
      requested_features: "TWQ_ZIG_BENCH_REQUESTED_FEATURES",
      settle_ms: "TWQ_ZIG_BENCH_SETTLE_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end
end
