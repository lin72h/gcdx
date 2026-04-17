defmodule TwqTest.M14Comparison do
  @moduledoc """
  Elixir-side helpers for the repo-owned M14 steady-state comparison lane.

  This compares a FreeBSD schema-3 repeat-lane artifact against the checked-in
  macOS normalized report and answers the narrow question M14 is meant to
  settle: whether the `mainq -> default.overcommit` seam should still be tuned
  on FreeBSD.
  """

  alias TwqTest.JSON

  @primary_metrics ~w(
    root_push_mainq_default_overcommit
    root_poke_slow_default_overcommit
  )

  @secondary_metrics ~w(
    pthread_workqueue_addthreads_requested_threads
    root_push_empty_default
    root_poke_slow_default
  )

  @type metric_result :: %{
          name: String.t(),
          role: :primary | :secondary,
          status: :ok | :missing,
          freebsd_source: String.t(),
          macos_source: String.t(),
          freebsd_avg: float() | nil,
          macos_avg: float() | nil,
          symmetric_ratio: float() | nil,
          freebsd_over_macos: float() | nil
        }

  @type comparison :: %{
          stop?: boolean(),
          verdict: String.t(),
          note: String.t(),
          workload: %{
            freebsd: map(),
            macos: map(),
            mismatches: [String.t()]
          },
          classification: %{
            default_receives_source_traffic: term(),
            default_overcommit_receives_mainq_traffic: term(),
            default_overcommit_continuation_dominant: term(),
            ok: boolean()
          },
          metrics: %{String.t() => metric_result()},
          failures: [String.t()]
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  @spec compare(String.t() | map(), String.t() | map(), keyword()) :: comparison()
  def compare(freebsd_path_or_map, macos_path_or_map, opts \\ []) do
    freebsd =
      if is_binary(freebsd_path_or_map), do: load(freebsd_path_or_map), else: freebsd_path_or_map

    macos =
      if is_binary(macos_path_or_map), do: load(macos_path_or_map), else: macos_path_or_map

    mode = Keyword.get(opts, :mode, "swift.dispatchmain-taskhandles-after-repeat")
    steady_start = Keyword.get(opts, :steady_start, 8)
    steady_end = Keyword.get(opts, :steady_end, 63)
    stop_ratio = Keyword.get(opts, :stop_ratio, 1.5)
    tune_ratio = Keyword.get(opts, :tune_ratio, 2.0)

    benchmark = get_in(freebsd, ["benchmarks", mode]) || %{}
    freebsd_workload = freebsd_workload(benchmark)
    macos_workload = Map.get(macos, "workload", %{})
    workload_mismatches = ensure_matching_tuple(freebsd_workload, macos_workload)
    classification = classification(macos)

    metrics =
      (@primary_metrics ++ @secondary_metrics)
      |> Enum.map(fn metric ->
        role = if metric in @primary_metrics, do: :primary, else: :secondary
        {metric, evaluate_metric(metric, role, benchmark, macos, steady_start, steady_end)}
      end)
      |> Map.new()

    primary_results =
      @primary_metrics
      |> Enum.map(&Map.fetch!(metrics, &1))
      |> Enum.filter(&(&1.status == :ok))

    {verdict, note} =
      decide_verdict(
        workload_mismatches,
        classification.ok,
        primary_results,
        stop_ratio,
        tune_ratio
      )

    failures =
      []
      |> add_failure_list(Enum.map(workload_mismatches, &("workload mismatch: " <> &1)))
      |> add_failure_if(
        not classification.ok,
        "classification does not show the expected default/default.overcommit split"
      )
      |> add_failure_if(
        map_size(metrics) == 0 or length(primary_results) != length(@primary_metrics),
        "missing primary steady-state metrics"
      )
      |> add_failure_if(
        verdict == "keep_tuning_this_seam",
        "primary seam remains above the keep-tuning threshold"
      )
      |> add_failure_if(
        verdict == "review",
        "comparison verdict is review"
      )
      |> Enum.reverse()

    %{
      stop?: verdict == "stop_tuning_this_seam",
      verdict: verdict,
      note: note,
      workload: %{
        freebsd: freebsd_workload,
        macos: macos_workload,
        mismatches: workload_mismatches
      },
      classification: classification,
      metrics: metrics,
      failures: failures
    }
  end

  @spec assert_stop!(comparison()) :: comparison()
  def assert_stop!(%{stop?: true} = comparison), do: comparison

  def assert_stop!(%{failures: failures, verdict: verdict}) do
    raise "M14 comparison did not stop at this seam (#{verdict}):\n" <> Enum.join(failures, "\n")
  end

  defp add_failure_list(failures, additions), do: Enum.reverse(additions) ++ failures

  defp add_failure_if(failures, true, message), do: [message | failures]
  defp add_failure_if(failures, false, _message), do: failures

  defp freebsd_workload(benchmark) when is_map(benchmark) do
    probe = Map.get(benchmark, "probe", %{})

    %{
      "domain" => Map.get(benchmark, "domain"),
      "mode" => Map.get(benchmark, "mode"),
      "rounds" => Map.get(probe, "rounds"),
      "tasks" => Map.get(probe, "tasks"),
      "delay_ms" => Map.get(probe, "delay_ms")
    }
  end

  defp fallback_series(total, rounds)
       when is_number(total) and is_integer(rounds) and rounds > 0 do
    Enum.map(1..rounds, fn _ -> total * 1.0 / rounds end)
  end

  defp constant_series(value, rounds)
       when is_number(value) and is_integer(rounds) and rounds > 0 do
    Enum.map(1..rounds, fn _ -> value * 1.0 end)
  end

  defp freebsd_metric_series(benchmark, "pthread_workqueue_addthreads_requested_threads") do
    round_metrics = Map.get(benchmark, "round_metrics", %{})
    probe = Map.get(benchmark, "probe", %{})
    rounds = Map.get(probe, "rounds")

    cond do
      is_list(Map.get(round_metrics, "round_ok_reqthreads_delta")) and
          Map.get(round_metrics, "round_ok_reqthreads_delta") != [] ->
        {
          Enum.map(Map.get(round_metrics, "round_ok_reqthreads_delta"), &(&1 * 1.0)),
          "freebsd.round_ok_reqthreads_delta"
        }

      is_number(get_in(benchmark, ["twq_delta", "kern.twq.reqthreads_count"])) and
          is_integer(rounds) ->
        {
          fallback_series(get_in(benchmark, ["twq_delta", "kern.twq.reqthreads_count"]), rounds),
          "freebsd.twq_delta.reqthreads_count/fallback"
        }

      true ->
        {nil, "-"}
    end
  end

  defp freebsd_metric_series(benchmark, metric) do
    round_metrics = Map.get(benchmark, "round_metrics", %{})
    counters = benchmark |> Map.get("libdispatch_counters", [%{}]) |> List.last()
    rounds = benchmark |> Map.get("probe", %{}) |> Map.get("rounds")
    round_key = "libdispatch_round_ok_#{metric}_delta"

    cond do
      is_list(Map.get(round_metrics, round_key)) and Map.get(round_metrics, round_key) != [] ->
        {Enum.map(Map.get(round_metrics, round_key), &(&1 * 1.0)), "freebsd.#{round_key}"}

      is_number(Map.get(counters, metric)) and is_integer(rounds) ->
        {fallback_series(Map.get(counters, metric), rounds),
         "freebsd.libdispatch_counters.#{metric}/fallback"}

      true ->
        {nil, "-"}
    end
  end

  defp macos_metric_series(report, metric) do
    metrics = Map.get(report, "metrics", %{})
    per_round = Map.get(metrics, "per_round", %{})
    steady = Map.get(metrics, "steady_state_per_round", %{})
    full_run = Map.get(metrics, "full_run", %{})
    rounds = report |> Map.get("workload", %{}) |> Map.get("rounds")

    cond do
      is_list(Map.get(per_round, metric)) and Map.get(per_round, metric) != [] ->
        {Enum.map(Map.get(per_round, metric), &(&1 * 1.0)), "macos.metrics.per_round.#{metric}"}

      is_number(Map.get(steady, metric)) and is_integer(rounds) ->
        {constant_series(Map.get(steady, metric), rounds),
         "macos.metrics.steady_state_per_round.#{metric}"}

      is_number(Map.get(full_run, metric)) and is_integer(rounds) ->
        {fallback_series(Map.get(full_run, metric), rounds),
         "macos.metrics.full_run.#{metric}/fallback"}

      true ->
        {nil, "-"}
    end
  end

  defp evaluate_metric(metric, role, benchmark, macos, steady_start, steady_end) do
    {freebsd_series, freebsd_source} = freebsd_metric_series(benchmark, metric)
    {macos_series, macos_source} = macos_metric_series(macos, metric)

    base = %{
      name: metric,
      role: role,
      status: :ok,
      freebsd_source: freebsd_source,
      macos_source: macos_source,
      freebsd_avg: nil,
      macos_avg: nil,
      symmetric_ratio: nil,
      freebsd_over_macos: nil
    }

    cond do
      is_nil(freebsd_series) or is_nil(macos_series) ->
        %{base | status: :missing}

      true ->
        freebsd_avg = freebsd_series |> inclusive_window(steady_start, steady_end) |> avg()
        macos_avg = macos_series |> inclusive_window(steady_start, steady_end) |> avg()

        %{
          base
          | freebsd_avg: freebsd_avg,
            macos_avg: macos_avg,
            symmetric_ratio: symmetric_ratio(freebsd_avg, macos_avg),
            freebsd_over_macos: if(macos_avg == 0.0, do: :infinity, else: freebsd_avg / macos_avg)
        }
    end
  end

  defp classification(report) do
    source = get_in(report, ["classification", "default_receives_source_traffic"])
    mainq = get_in(report, ["classification", "default_overcommit_receives_mainq_traffic"])
    continuation = get_in(report, ["classification", "default_overcommit_continuation_dominant"])

    %{
      default_receives_source_traffic: source,
      default_overcommit_receives_mainq_traffic: mainq,
      default_overcommit_continuation_dominant: continuation,
      ok: !!(source and mainq)
    }
  end

  defp ensure_matching_tuple(freebsd, macos) do
    Enum.reduce(~w(rounds tasks delay_ms), [], fn key, acc ->
      case {Map.get(freebsd, key), Map.get(macos, key)} do
        {lhs, rhs} when is_nil(lhs) or is_nil(rhs) ->
          acc

        {lhs, rhs} when lhs == rhs ->
          acc

        {lhs, rhs} ->
          ["#{key}: freebsd=#{lhs} macos=#{rhs}" | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp decide_verdict(
         workload_mismatches,
         classification_ok,
         primary_results,
         stop_ratio,
         tune_ratio
       ) do
    cond do
      workload_mismatches != [] or not classification_ok or
          length(primary_results) != length(@primary_metrics) ->
        {"review", ""}

      Enum.any?(primary_results, fn result ->
        result.freebsd_over_macos == :infinity or result.freebsd_over_macos >= tune_ratio
      end) ->
        {"keep_tuning_this_seam", ""}

      Enum.all?(primary_results, &(&1.symmetric_ratio <= stop_ratio)) ->
        {"stop_tuning_this_seam", ""}

      true ->
        {"stop_tuning_this_seam",
         "borderline_stop_between_stop_ratio_and_tune_ratio;same qualitative seam and less than tune threshold"}
    end
  end

  defp inclusive_window(values, start_round, end_round) do
    length = length(values)

    cond do
      start_round < 0 or end_round < start_round ->
        raise ArgumentError, "invalid round window #{start_round}-#{end_round}"

      length <= end_round ->
        raise ArgumentError,
              "round window #{start_round}-#{end_round} exceeds series length #{length}"

      true ->
        Enum.slice(values, start_round, end_round - start_round + 1)
    end
  end

  defp avg(values), do: Enum.sum(values) / length(values)

  defp symmetric_ratio(lhs, rhs) when lhs == 0.0 and rhs == 0.0, do: 1.0
  defp symmetric_ratio(lhs, _rhs) when lhs == 0.0, do: :infinity
  defp symmetric_ratio(_lhs, rhs) when rhs == 0.0, do: :infinity
  defp symmetric_ratio(lhs, rhs), do: max(lhs, rhs) / min(lhs, rhs)
end
