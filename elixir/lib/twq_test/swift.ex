defmodule TwqTest.Swift do
  @moduledoc """
  Thin Elixir wrappers around the repo's local Swift pre-check staging.
  """

  alias TwqTest.{Command, Env}

  @spec prepare(keyword()) :: Command.Result.t()
  def prepare(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/swift/prepare-stage.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env),
      timeout: env.command_timeout_ms
    )
  end

  @spec run_m14_comparison(keyword()) :: Command.Result.t()
  def run_m14_comparison(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/benchmarks/run-m14-comparison.sh")

    Command.run(script, [],
      cd: env.repo_root,
      env: Env.script_env(env) |> m14_env(opts),
      timeout: Keyword.get(opts, :comparison_timeout_ms, env.command_timeout_ms)
    )
  end

  defp build_env(opts) do
    opts
    |> Enum.into(%{})
    |> Env.load()
  end

  defp m14_env(script_env, opts) do
    option_env = %{
      m14_freebsd_json: "TWQ_M14_FREEBSD_JSON",
      m14_macos_report: "TWQ_M14_MACOS_REPORT",
      m14_out_dir: "TWQ_M14_OUT_DIR",
      m14_comparison_json: "TWQ_M14_COMPARISON_JSON",
      m14_comparison_log: "TWQ_M14_COMPARISON_LOG",
      m14_summary_md: "TWQ_M14_SUMMARY_MD",
      m14_serial_log: "TWQ_M14_SERIAL_LOG",
      m14_swift_profile: "TWQ_M14_SWIFT_PROFILE",
      m14_steady_start: "TWQ_M14_STEADY_START",
      m14_steady_end: "TWQ_M14_STEADY_END",
      m14_stop_ratio: "TWQ_M14_STOP_RATIO",
      m14_tune_ratio: "TWQ_M14_TUNE_RATIO"
    }

    Enum.reduce(option_env, script_env, fn {option, env_key}, acc ->
      case Keyword.get(opts, option) do
        nil -> acc
        value -> Map.put(acc, env_key, to_string(value))
      end
    end)
  end
end
