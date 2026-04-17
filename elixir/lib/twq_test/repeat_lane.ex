defmodule TwqTest.RepeatLane do
  @moduledoc """
  Elixir-side helpers for the focused FreeBSD repeat-lane regression gate.

  This keeps the schema-3 repeat baseline durable on the FreeBSD side after
  M14 closed the mainq -> default.overcommit seam as native-shaped rather than
  a live tuning target.
  """

  alias TwqTest.JSON

  @mode_policies %{
    "dispatch.main-executor-resume-repeat" => %{
      label: "dispatch repeat control",
      checks: [
        %{
          metric: "round_ok_reqthreads_delta",
          label: "reqthreads_per_round",
          max_ratio: 1.5,
          slack: 1.0
        },
        %{
          metric: "libdispatch_round_ok_root_push_mainq_default_overcommit_delta",
          label: "root_push_mainq_default_overcommit_per_round",
          max_ratio: 1.0,
          slack: 0.0
        },
        %{
          metric: "libdispatch_round_ok_root_poke_slow_default_overcommit_delta",
          label: "root_poke_slow_default_overcommit_per_round",
          max_ratio: 1.0,
          slack: 0.0
        },
        %{
          metric: "libdispatch_round_ok_root_push_empty_default_delta",
          label: "root_push_empty_default_per_round",
          max_ratio: 1.5,
          slack: 1.0
        },
        %{
          metric: "libdispatch_round_ok_root_poke_slow_default_delta",
          label: "root_poke_slow_default_per_round",
          max_ratio: 1.5,
          slack: 1.0
        }
      ]
    },
    "swift.dispatchmain-taskhandles-after-repeat" => %{
      label: "swift dispatchMain repeat",
      checks: [
        %{
          metric: "round_ok_reqthreads_delta",
          label: "reqthreads_per_round",
          max_ratio: 1.5,
          slack: 4.0
        },
        %{
          metric: "libdispatch_round_ok_root_push_mainq_default_overcommit_delta",
          label: "root_push_mainq_default_overcommit_per_round",
          max_ratio: 1.5,
          slack: 1.0
        },
        %{
          metric: "libdispatch_round_ok_root_poke_slow_default_overcommit_delta",
          label: "root_poke_slow_default_overcommit_per_round",
          max_ratio: 1.5,
          slack: 1.0
        },
        %{
          metric: "libdispatch_round_ok_root_push_empty_default_delta",
          label: "root_push_empty_default_per_round",
          max_ratio: 2.0,
          slack: 2.0
        },
        %{
          metric: "libdispatch_round_ok_root_poke_slow_default_delta",
          label: "root_poke_slow_default_per_round",
          max_ratio: 2.0,
          slack: 2.0
        }
      ]
    }
  }

  @type comparison :: %{
          ok?: boolean(),
          failures: [String.t()],
          modes: %{String.t() => map()}
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  @spec compare(String.t() | map(), String.t() | map(), keyword()) :: comparison()
  def compare(baseline_path_or_map, candidate_path_or_map, opts \\ []) do
    baseline =
      if is_binary(baseline_path_or_map),
        do: load(baseline_path_or_map),
        else: baseline_path_or_map

    candidate =
      if is_binary(candidate_path_or_map),
        do: load(candidate_path_or_map),
        else: candidate_path_or_map

    steady_start = Keyword.get(opts, :steady_start, 8)
    steady_end = Keyword.get(opts, :steady_end, 63)

    {modes, failures} =
      Enum.map_reduce(@mode_policies, [], fn {mode, policy}, failures ->
        {result, mode_failures} =
          compare_mode(
            mode,
            policy,
            get_in(baseline, ["benchmarks", mode]),
            get_in(candidate, ["benchmarks", mode]),
            steady_start,
            steady_end
          )

        {{mode, result}, Enum.reverse(mode_failures) ++ failures}
      end)

    %{ok?: failures == [], failures: Enum.reverse(failures), modes: Map.new(modes)}
  end

  @spec assert_ok!(comparison()) :: comparison()
  def assert_ok!(%{ok?: true} = comparison), do: comparison

  def assert_ok!(%{failures: failures}) do
    raise "repeat-lane comparison failed:\n" <> Enum.join(failures, "\n")
  end

  defp compare_mode(mode, policy, nil, _candidate, _steady_start, _steady_end) do
    result = %{
      label: policy.label,
      status: "missing-baseline",
      workload: %{},
      checks: [],
      failures: ["missing from baseline"]
    }

    {result, ["#{mode}: missing from baseline"]}
  end

  defp compare_mode(mode, policy, _baseline, nil, _steady_start, _steady_end) do
    result = %{
      label: policy.label,
      status: "missing-candidate",
      workload: %{},
      checks: [],
      failures: ["missing from candidate"]
    }

    {result, ["#{mode}: missing from candidate"]}
  end

  defp compare_mode(mode, policy, baseline, candidate, steady_start, steady_end) do
    baseline_workload = workload_tuple(baseline)
    candidate_workload = workload_tuple(candidate)
    mismatches = workload_mismatches(baseline_workload, candidate_workload)

    failures =
      []
      |> add_failure_if(
        Map.get(baseline, "status") == "ok" and Map.get(candidate, "status") != "ok",
        "#{mode}: status regressed #{inspect(Map.get(baseline, "status"))}->#{inspect(Map.get(candidate, "status"))}"
      )
      |> add_failure_list(Enum.map(mismatches, &("#{mode}: workload mismatch " <> &1)))

    {checks, failures} =
      Enum.map_reduce(policy.checks, failures, fn check, failures ->
        {baseline_avg, candidate_avg, common_rounds} =
          steady_avg_pair(baseline, candidate, check.metric, steady_start, steady_end)

        {status, limit, failures} =
          cond do
            is_nil(baseline_avg) or is_nil(candidate_avg) ->
              {:missing, nil, ["#{mode}: missing metric #{check.metric}" | failures]}

            true ->
              limit = allowed_value(baseline_avg, check.max_ratio, check.slack)

              if candidate_avg > limit do
                {:fail, limit,
                 [
                   "#{mode}: #{check.label} #{format_float(candidate_avg)} exceeds #{format_float(limit)} (baseline #{format_float(baseline_avg)})"
                   | failures
                 ]}
              else
                {:ok, limit, failures}
              end
          end

        check_result = %{
          metric: check.metric,
          label: check.label,
          baseline_avg: baseline_avg,
          candidate_avg: candidate_avg,
          limit: limit,
          rounds_compared: common_rounds,
          status: status
        }

        {check_result, failures}
      end)

    result = %{
      label: policy.label,
      status: if(failures == [], do: "ok", else: "fail"),
      workload: %{
        baseline: baseline_workload,
        candidate: candidate_workload,
        mismatches: mismatches
      },
      checks: checks,
      failures: Enum.reverse(failures)
    }

    {result, failures}
  end

  defp add_failure_if(failures, true, message), do: [message | failures]
  defp add_failure_if(failures, false, _message), do: failures
  defp add_failure_list(failures, additions), do: Enum.reverse(additions) ++ failures

  defp workload_tuple(benchmark) do
    probe = Map.get(benchmark, "probe", %{})

    %{
      "domain" => Map.get(benchmark, "domain"),
      "mode" => Map.get(benchmark, "mode"),
      "rounds" => Map.get(probe, "rounds"),
      "tasks" => Map.get(probe, "tasks"),
      "delay_ms" => Map.get(probe, "delay_ms")
    }
  end

  defp workload_mismatches(baseline, candidate) do
    Enum.reduce(~w(rounds tasks delay_ms), [], fn key, acc ->
      case {Map.get(baseline, key), Map.get(candidate, key)} do
        {lhs, rhs} when is_nil(lhs) or is_nil(rhs) -> acc
        {lhs, rhs} when lhs == rhs -> acc
        {lhs, rhs} -> ["#{key}: baseline=#{lhs} candidate=#{rhs}" | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp steady_avg_pair(baseline, candidate, metric, steady_start, steady_end) do
    baseline_map = metric_round_map(baseline, metric, steady_start, steady_end)
    candidate_map = metric_round_map(candidate, metric, steady_start, steady_end)

    cond do
      is_nil(baseline_map) or is_nil(candidate_map) ->
        {nil, nil, []}

      true ->
        common_rounds =
          baseline_map
          |> Map.keys()
          |> MapSet.new()
          |> MapSet.intersection(MapSet.new(Map.keys(candidate_map)))
          |> Enum.sort()

        if common_rounds == [] do
          {nil, nil, []}
        else
          baseline_avg =
            common_rounds
            |> Enum.map(&Map.fetch!(baseline_map, &1))
            |> avg()

          candidate_avg =
            common_rounds
            |> Enum.map(&Map.fetch!(candidate_map, &1))
            |> avg()

          {baseline_avg, candidate_avg, common_rounds}
        end
    end
  end

  defp metric_round_map(benchmark, metric, steady_start, steady_end) do
    round_metrics = Map.get(benchmark, "round_metrics", %{})
    values = Map.get(round_metrics, metric)

    cond do
      not is_list(values) or values == [] ->
        nil

      true ->
        round_key = metric_round_key(round_metrics, metric, length(values))

        rounds =
          case round_key do
            nil -> Enum.to_list(0..(length(values) - 1))
            key -> Map.get(round_metrics, key, [])
          end

        if length(rounds) != length(values) do
          nil
        else
          rounds
          |> Enum.zip(values)
          |> Enum.reduce(%{}, fn
            {round_number, value}, acc when is_integer(round_number) ->
              if round_number >= steady_start and round_number <= steady_end do
                Map.put(acc, round_number, value * 1.0)
              else
                acc
              end

            _, acc ->
              acc
          end)
        end
    end
  end

  defp metric_round_key(round_metrics, metric, series_length) do
    candidates =
      cond do
        String.starts_with?(metric, "libdispatch_round_ok_") and
            String.ends_with?(metric, "_delta") ->
          ["libdispatch_round_ok_delta_rounds", "libdispatch_round_ok_rounds"]

        String.starts_with?(metric, "libdispatch_round_ok_") ->
          ["libdispatch_round_ok_rounds"]

        String.starts_with?(metric, "libdispatch_round_start_") ->
          ["libdispatch_round_start_rounds"]

        String.starts_with?(metric, "round_ok_") ->
          ["round_ok_rounds"]

        String.starts_with?(metric, "round_start_") ->
          ["round_start_rounds"]

        true ->
          []
      end

    Enum.find(candidates, fn key ->
      case Map.get(round_metrics, key) do
        rounds when is_list(rounds) -> length(rounds) == series_length
        _ -> false
      end
    end)
  end

  defp avg(values), do: Enum.sum(values) / length(values)

  defp allowed_value(baseline, max_ratio, slack), do: max(baseline * max_ratio, baseline + slack)

  defp format_float(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end
end
