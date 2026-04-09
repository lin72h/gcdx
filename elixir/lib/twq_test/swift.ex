defmodule TwqTest.Swift do
  @moduledoc """
  Thin Elixir wrappers around the repo's local Swift pre-check staging.
  """

  alias TwqTest.{Command, Env}

  @spec prepare(keyword()) :: Command.Result.t()
  def prepare(opts \\ []) do
    env = build_env(opts)
    script = Path.join(env.repo_root, "scripts/swift/prepare-stage.sh")
    Command.run(script, [], cd: env.repo_root, env: Env.script_env(env), timeout: env.command_timeout_ms)
  end

  defp build_env(opts) do
    opts
    |> Enum.into(%{})
    |> Env.load()
  end
end
