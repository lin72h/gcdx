defmodule TwqTest.ZigHotpath do
  @moduledoc """
  Elixir-side helpers for Zig TWQ syscall hot-path benchmark artifacts.

  The shell/Python helpers remain useful for direct CLI work. This module makes
  the same artifact shape visible to ExUnit so M13 gates can live in the primary
  harness.
  """

  alias TwqTest.JSON

  @default_latency_metrics ~w(median_ns p95_ns p99_ns)
  @default_counter_metrics ~w(reqthreads_count thread_enter_count thread_return_count thread_transfer_count)
  @default_config_fields ~w(samples request_count requested_features settle_ms)

  @type mode_key :: String.t()
  @type comparison :: %{
          ok?: boolean(),
          failures: [String.t()],
          modes: [map()]
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  @spec normalize(String.t() | map()) :: %{mode_key() => map()}
  def normalize(path) when is_binary(path), do: path |> load() |> normalize()

  def normalize(%{} = artifact) do
    %{}
    |> merge_modes(Map.get(artifact, "modes", %{}))
    |> merge_benchmarks(Map.get(artifact, "benchmarks", %{}))
    |> merge_single_benchmark(Map.get(artifact, "benchmark"))
    |> ensure_not_empty!()
  end

  @spec compare(String.t() | map(), String.t() | map(), keyword()) :: comparison()
  def compare(baseline_path_or_map, candidate_path_or_map, opts \\ []) do
    baseline = normalize(baseline_path_or_map)
    candidate = normalize(candidate_path_or_map)
    latency_metrics = Keyword.get(opts, :latency_metrics, @default_latency_metrics)
    counter_metrics = Keyword.get(opts, :counter_metrics, @default_counter_metrics)
    latency_ratio = Keyword.get(opts, :max_latency_ratio, 3.0)
    latency_slack_ns = Keyword.get(opts, :latency_slack_ns, 1000)
    counter_ratio = Keyword.get(opts, :max_counter_ratio, 1.0)
    counter_slack = Keyword.get(opts, :counter_slack, 0)
    allow_config_mismatch? = Keyword.get(opts, :allow_config_mismatch?, false)

    mode_keys =
      opts
      |> Keyword.get(:modes, Map.keys(baseline) -- (Map.keys(baseline) -- Map.keys(candidate)))
      |> Enum.map(&normalize_mode_key/1)
      |> Enum.sort()

    {modes, failures} =
      Enum.map_reduce(mode_keys, [], fn mode, failures ->
        compare_mode(mode, baseline, candidate, %{
          latency_metrics: latency_metrics,
          counter_metrics: counter_metrics,
          latency_ratio: latency_ratio,
          latency_slack_ns: latency_slack_ns,
          counter_ratio: counter_ratio,
          counter_slack: counter_slack,
          allow_config_mismatch?: allow_config_mismatch?
        })
        |> append_mode_failures(failures)
      end)

    %{ok?: failures == [], failures: Enum.reverse(failures), modes: modes}
  end

  @spec assert_ok!(comparison()) :: comparison()
  def assert_ok!(%{ok?: true} = comparison), do: comparison

  def assert_ok!(%{failures: failures}) do
    raise "Zig hot-path comparison failed:\n" <> Enum.join(failures, "\n")
  end

  defp append_mode_failures({mode_result, mode_failures}, failures) do
    {mode_result, Enum.reverse(mode_failures) ++ failures}
  end

  defp compare_mode(mode, baseline, candidate, policy) do
    b = Map.get(baseline, mode)
    c = Map.get(candidate, mode)

    cond do
      is_nil(b) ->
        {%{mode: mode, status: "missing-baseline", checks: []},
         ["#{mode}: missing from baseline"]}

      is_nil(c) ->
        {%{mode: mode, status: "missing-candidate", checks: []},
         ["#{mode}: missing from candidate"]}

      true ->
        checks =
          []
          |> add_status_check(mode, b, c)
          |> add_sample_error_check(mode, b, c)
          |> add_config_checks(mode, b, c, policy.allow_config_mismatch?)
          |> add_metric_checks(
            mode,
            b,
            c,
            policy.latency_metrics,
            policy.latency_ratio,
            policy.latency_slack_ns
          )
          |> add_metric_checks(
            mode,
            b,
            c,
            policy.counter_metrics,
            policy.counter_ratio,
            policy.counter_slack
          )
          |> Enum.reverse()

        failures =
          checks
          |> Enum.filter(&(&1.status == :fail))
          |> Enum.map(& &1.failure)

        {%{mode: mode, status: if(failures == [], do: "ok", else: "fail"), checks: checks},
         failures}
    end
  end

  defp add_status_check(checks, mode, b, c) do
    b_status = status_for(b)
    c_status = status_for(c)
    failed? = b_status == "ok" and c_status != "ok"

    [
      %{
        kind: "status",
        metric: "status",
        baseline: b_status,
        candidate: c_status,
        status: status_atom(failed?),
        failure: "#{mode}: status regressed #{inspect(b_status)}->#{inspect(c_status)}"
      }
      | checks
    ]
  end

  defp add_sample_error_check(checks, mode, b, c) do
    b_errors = numeric(b, "sample_errors")
    c_errors = numeric(c, "sample_errors")
    failed? = b_errors == 0 and c_errors not in [0, nil]

    [
      %{
        kind: "sample_errors",
        metric: "sample_errors",
        baseline: b_errors,
        candidate: c_errors,
        status: status_atom(failed?),
        failure: "#{mode}: sample_errors regressed 0->#{c_errors}"
      }
      | checks
    ]
  end

  defp add_config_checks(checks, _mode, _b, _c, true), do: checks

  defp add_config_checks(checks, mode, b, c, false) do
    Enum.reduce(@default_config_fields, checks, fn field, acc ->
      b_value = Map.get(b, field)
      c_value = Map.get(c, field)

      if is_nil(b_value) or is_nil(c_value) do
        acc
      else
        failed? = b_value != c_value

        [
          %{
            kind: "config",
            metric: field,
            baseline: b_value,
            candidate: c_value,
            status: status_atom(failed?),
            failure: "#{mode}: #{field} differs #{inspect(b_value)}->#{inspect(c_value)}"
          }
          | acc
        ]
      end
    end)
  end

  defp add_metric_checks(checks, mode, b, c, metrics, ratio, slack) do
    Enum.reduce(metrics, checks, fn metric, acc ->
      b_value = numeric(b, metric)
      c_value = numeric(c, metric)

      if is_nil(b_value) or is_nil(c_value) do
        acc
      else
        limit = allowed_value(b_value, ratio, slack)
        failed? = c_value > limit

        [
          %{
            kind: "metric",
            metric: metric,
            baseline: b_value,
            candidate: c_value,
            limit: limit,
            status: status_atom(failed?),
            failure: "#{mode}: #{metric} #{c_value} exceeds #{limit} (baseline #{b_value})"
          }
          | acc
        ]
      end
    end)
  end

  defp status_atom(true), do: :fail
  defp status_atom(false), do: :ok

  defp allowed_value(baseline, ratio, slack) do
    max(trunc(baseline * ratio), baseline + slack)
  end

  defp numeric(record, metric) do
    cond do
      is_integer(Map.get(record, metric)) ->
        Map.get(record, metric)

      is_map(Map.get(record, "counter_delta")) and
          is_integer(get_in(record, ["counter_delta", metric])) ->
        get_in(record, ["counter_delta", metric])

      is_map(Map.get(record, "counter_delta")) and
          is_integer(get_in(record, ["counter_delta", "kern.twq.#{metric}"])) ->
        get_in(record, ["counter_delta", "kern.twq.#{metric}"])

      true ->
        nil
    end
  end

  defp status_for(record) do
    cond do
      is_binary(Map.get(record, "status")) -> Map.get(record, "status")
      Map.get(record, "sample_errors") == 0 -> "ok"
      true -> "unknown"
    end
  end

  defp merge_modes(acc, modes) when is_map(modes) do
    Enum.reduce(modes, acc, fn {key, value}, acc ->
      if is_map(value) do
        {mode, flat} = flatten_benchmark(value, key)
        Map.put(acc, mode, flat)
      else
        acc
      end
    end)
  end

  defp merge_modes(acc, _), do: acc

  defp merge_benchmarks(acc, benchmarks), do: merge_modes(acc, benchmarks)

  defp merge_single_benchmark(acc, benchmark) when is_map(benchmark) do
    {mode, flat} = flatten_benchmark(benchmark, nil)
    Map.put(acc, mode, flat)
  end

  defp merge_single_benchmark(acc, _), do: acc

  defp flatten_benchmark(%{"data" => data} = benchmark, fallback_key) when is_map(data) do
    mode =
      data
      |> Map.get("mode", fallback_key)
      |> normalize_mode_key()

    flat =
      data
      |> Map.put("status", Map.get(benchmark, "status", status_for(data)))
      |> Map.put("meta", Map.get(benchmark, "meta", %{}))

    {mode, flat}
  end

  defp flatten_benchmark(benchmark, fallback_key) when is_map(benchmark) do
    mode =
      benchmark
      |> Map.get("mode", fallback_key)
      |> normalize_mode_key()

    {mode, Map.put(benchmark, "status", status_for(benchmark))}
  end

  defp normalize_mode_key(value) when is_binary(value), do: String.replace(value, "-", "_")
  defp normalize_mode_key(nil), do: raise(ArgumentError, "benchmark mode is missing")
  defp normalize_mode_key(value), do: value |> to_string() |> normalize_mode_key()

  defp ensure_not_empty!(map) when map_size(map) > 0, do: map
  defp ensure_not_empty!(_), do: raise(ArgumentError, "no Zig hot-path benchmarks found")
end
