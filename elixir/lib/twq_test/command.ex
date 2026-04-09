defmodule TwqTest.Command do
  @moduledoc """
  Minimal host-side command runner with timeout support and merged output.

  The result shape is intentionally simple and fully serializable.
  """

  defmodule Result do
    @enforce_keys [:command, :args, :output, :exit_status, :duration_ms, :timed_out?]
    defstruct @enforce_keys ++ [cwd: nil, env: %{}]

    @type t :: %__MODULE__{
            command: String.t(),
            args: [String.t()],
            cwd: String.t() | nil,
            env: map(),
            output: String.t(),
            exit_status: integer(),
            duration_ms: non_neg_integer(),
            timed_out?: boolean()
          }

    @spec ok?(t()) :: boolean()
    def ok?(%__MODULE__{exit_status: 0, timed_out?: false}), do: true
    def ok?(%__MODULE__{}), do: false
  end

  @spec run(String.t(), [String.t()], keyword()) :: Result.t()
  def run(command, args \\ [], opts \\ []) when is_binary(command) and is_list(args) do
    timeout = Keyword.get(opts, :timeout, Application.fetch_env!(:twq_test, :command_timeout_ms))
    cwd = Keyword.get(opts, :cd)
    env = Keyword.get(opts, :env, %{})
    executable = resolve_executable!(command)
    start_ms = System.monotonic_time(:millisecond)

    port =
      Port.open(
        {:spawn_executable, executable},
        port_options(args, cwd, env)
      )

    {output, exit_status, timed_out?} = collect(port, [], timeout)
    duration_ms = System.monotonic_time(:millisecond) - start_ms

    %Result{
      command: command,
      args: args,
      cwd: cwd,
      env: env,
      output: output,
      exit_status: exit_status,
      duration_ms: duration_ms,
      timed_out?: timed_out?
    }
  end

  defp resolve_executable!(command) do
    cond do
      String.starts_with?(command, "/") ->
        command

      String.contains?(command, "/") ->
        Path.expand(command)

      true ->
        case System.find_executable(command) do
          nil -> raise ArgumentError, "unable to resolve executable: #{command}"
          executable -> executable
        end
    end
  end

  defp port_options(args, cwd, env) do
    base = [
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      :stderr_to_stdout,
      {:args, args}
    ]

    base
    |> maybe_put_cd(cwd)
    |> maybe_put_env(env)
  end

  defp maybe_put_cd(opts, nil), do: opts
  defp maybe_put_cd(opts, cwd), do: [{:cd, String.to_charlist(cwd)} | opts]

  defp maybe_put_env(opts, env) when map_size(env) == 0, do: opts

  defp maybe_put_env(opts, env) do
    port_env =
      Enum.map(env, fn {key, value} ->
        {String.to_charlist(to_string(key)), String.to_charlist(to_string(value))}
      end)

    [{:env, port_env} | opts]
  end

  defp collect(port, chunks, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect(port, [chunks | data], timeout)

      {^port, {:exit_status, exit_status}} ->
        {IO.iodata_to_binary(chunks), exit_status, false}
    after
      timeout ->
        Port.close(port)
        {IO.iodata_to_binary(chunks), 124, true}
    end
  end
end
