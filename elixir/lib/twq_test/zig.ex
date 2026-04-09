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
    Command.run(script, [], cd: env.repo_root, env: Env.script_env(env), timeout: env.command_timeout_ms)
  end

  defp prepare_dispatch_stage(%Env{} = env) do
    script = Path.join(env.repo_root, "scripts/libdispatch/prepare-stage.sh")
    Command.run(script, [], cd: env.repo_root, env: Env.script_env(env), timeout: env.command_timeout_ms)
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
end
