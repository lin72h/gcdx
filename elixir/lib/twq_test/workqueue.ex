defmodule TwqTest.Workqueue do
  @moduledoc """
  Thin Elixir wrappers around the repo's C workqueue probes and benchmarks.
  """

  alias TwqTest.{Command, Env}

  @spec build_wake_bench(keyword()) :: Command.Result.t()
  def build_wake_bench(opts \\ []) do
    env = build_env(opts)
    stage_result = prepare_pthread_stage(env)
    source = Path.join(env.repo_root, "csrc/twq_workqueue_wake_bench.c")

    if Command.Result.ok?(stage_result) do
      File.mkdir_p!(Path.dirname(env.workqueue_wake_bench_bin))

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
          "-lm",
          "-lc",
          "-o",
          env.workqueue_wake_bench_bin
        ],
        cd: env.repo_root,
        timeout: env.command_timeout_ms
      )
    else
      stage_result
    end
  end

  @spec run_wake_suite(keyword()) :: Command.Result.t()
  def run_wake_suite(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-workqueue-wake-suite.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> wake_suite_env(opts),
      timeout: Keyword.get(opts, :suite_timeout_ms, env.command_timeout_ms)
    )
  end

  defp build_env(opts) do
    opts
    |> Enum.into(%{})
    |> Env.load()
  end

  defp prepare_pthread_stage(%Env{} = env) do
    script = Path.join(env.repo_root, "scripts/libthr/prepare-stage.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  defp wake_suite_env(script_env, opts) do
    option_env = %{
      benchmark_json: "TWQ_BENCHMARK_JSON",
      benchmark_label: "TWQ_BENCHMARK_LABEL",
      serial_log: "TWQ_SERIAL_LOG",
      suite_plan: "TWQ_WORKQUEUE_WAKE_SUITE_PLAN",
      default_samples: "TWQ_WORKQUEUE_WAKE_DEFAULT_SAMPLES",
      default_warmup: "TWQ_WORKQUEUE_WAKE_DEFAULT_WARMUP",
      overcommit_samples: "TWQ_WORKQUEUE_WAKE_OVERCOMMIT_SAMPLES",
      overcommit_warmup: "TWQ_WORKQUEUE_WAKE_OVERCOMMIT_WARMUP",
      settle_ms: "TWQ_WORKQUEUE_WAKE_SETTLE_MS",
      prime_timeout_ms: "TWQ_WORKQUEUE_WAKE_PRIME_TIMEOUT_MS",
      callback_timeout_ms: "TWQ_WORKQUEUE_WAKE_CALLBACK_TIMEOUT_MS",
      quiescent_timeout_ms: "TWQ_WORKQUEUE_WAKE_QUIESCENT_TIMEOUT_MS"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end
end
