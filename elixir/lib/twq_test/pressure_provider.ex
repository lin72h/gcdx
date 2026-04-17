defmodule TwqTest.PressureProvider do
  @moduledoc """
  Elixir-side helpers for the derived M15 pressure-provider prep artifact.

  This lane does not claim a live SPI yet. It validates the repo-owned
  pressure-only view derived from the checked-in crossover artifact so future
  upper-layer consumers can depend on a stable shape without leaking TCM or
  scheduler vocabulary back down into GCDX.
  """

  alias TwqTest.JSON

  @aggregate_limits %{
    "request_events_total" => %{max_ratio: 1.5, slack: 8.0},
    "worker_entries_total" => %{max_ratio: 1.5, slack: 8.0},
    "worker_returns_total" => %{max_ratio: 1.5, slack: 8.0},
    "requested_workers_total" => %{max_ratio: 1.5, slack: 16.0},
    "admitted_workers_total" => %{max_ratio: 1.5, slack: 8.0},
    "blocked_events_total" => %{max_ratio: 1.5, slack: 16.0},
    "unblocked_events_total" => %{max_ratio: 1.5, slack: 16.0},
    "blocked_workers_total" => %{max_ratio: 1.5, slack: 32.0},
    "unblocked_workers_total" => %{max_ratio: 1.5, slack: 32.0},
    "total_workers_current" => %{max_ratio: 1.0, slack: 0.0},
    "idle_workers_current" => %{max_ratio: 1.0, slack: 0.0},
    "nonidle_workers_current" => %{max_ratio: 1.0, slack: 0.0},
    "active_workers_current" => %{max_ratio: 1.0, slack: 0.0},
    "should_narrow_true_total" => %{max_ratio: 1.5, slack: 2.0},
    "request_backlog_total" => %{max_ratio: 1.5, slack: 16.0},
    "block_backlog_total" => %{max_ratio: 1.5, slack: 16.0}
  }

  @flag_fields ~w(
    has_per_bucket_diagnostics
    has_admission_feedback
    has_block_feedback
    has_live_current_counts
    has_narrow_feedback
    pressure_visible
  )

  @top_level_paths [
    ["schema_version"],
    ["provider_scope"],
    ["contract", "name"],
    ["contract", "version"],
    ["contract", "current_signal_field"],
    ["contract", "current_signal_kind"],
    ["contract", "quiescence_kind"],
    ["contract", "per_bucket_scope"],
    ["contract", "diagnostic_fields"],
    ["source_schema_version"],
    ["metadata", "generation_kind"],
    ["metadata", "monotonic_time_kind"],
    ["metadata", "snapshot_count"]
  ]

  @snapshot_equal_fields ~w(status generation timestamp_kind monotonic_time_ns)
  @workload_fields ~w(domain mode rounds tasks delay_ms)

  @type comparison :: %{
          ok?: boolean(),
          failures: [String.t()],
          top_level: [map()],
          snapshots: %{String.t() => map()}
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
    |> normalize_nulls()
  end

  @spec compare(String.t() | map(), String.t() | map()) :: comparison()
  def compare(baseline_path_or_map, candidate_path_or_map) do
    baseline =
      if is_binary(baseline_path_or_map),
        do: load(baseline_path_or_map),
        else: normalize_nulls(baseline_path_or_map)

    candidate =
      if is_binary(candidate_path_or_map),
        do: load(candidate_path_or_map),
        else: normalize_nulls(candidate_path_or_map)

    {top_level, top_level_failures} =
      Enum.map_reduce(@top_level_paths, [], fn path, failures ->
        lhs = get_in(baseline, path)
        rhs = get_in(candidate, path)
        status = if lhs == rhs, do: "ok", else: "fail"

        failure =
          if lhs == rhs,
            do: nil,
            else:
              "#{Enum.join(path, ".")} differs (baseline #{inspect(lhs)}, candidate #{inspect(rhs)})"

        entry = %{
          path: path,
          baseline_value: lhs,
          candidate_value: rhs,
          status: status,
          failure: failure
        }

        next_failures = if is_nil(failure), do: failures, else: [failure | failures]
        {entry, next_failures}
      end)

    baseline_snapshots = Map.get(baseline, "snapshots", %{})
    candidate_snapshots = Map.get(candidate, "snapshots", %{})

    modes =
      (Map.keys(baseline_snapshots) ++ Map.keys(candidate_snapshots))
      |> Enum.uniq()
      |> Enum.sort()

    {snapshots, snapshot_failures} =
      Enum.map_reduce(
        modes,
        top_level_failures,
        fn mode, failures ->
          {result, mode_failures} =
            compare_snapshot(
              mode,
              Map.get(baseline_snapshots, mode),
              Map.get(candidate_snapshots, mode)
            )

          {{mode, result}, Enum.reverse(mode_failures) ++ failures}
        end
      )

    failures = Enum.reverse(snapshot_failures)

    %{
      ok?: failures == [],
      failures: failures,
      top_level: top_level,
      snapshots: Map.new(snapshots)
    }
  end

  @spec assert_ok!(comparison()) :: comparison()
  def assert_ok!(%{ok?: true} = comparison), do: comparison

  def assert_ok!(%{failures: failures}) do
    raise "pressure-provider comparison failed:\n" <> Enum.join(failures, "\n")
  end

  defp compare_snapshot(mode, nil, _candidate) do
    result = %{status: "missing-baseline", checks: [], failures: ["missing from baseline"]}
    {result, ["#{mode}: missing from baseline"]}
  end

  defp compare_snapshot(mode, _baseline, nil) do
    result = %{status: "missing-candidate", checks: [], failures: ["missing from candidate"]}
    {result, ["#{mode}: missing from candidate"]}
  end

  defp compare_snapshot(mode, baseline, candidate) do
    {checks, failures} =
      {[], []}
      |> compare_equal_fields(mode, baseline, candidate, @snapshot_equal_fields, fn field ->
        {field, [field]}
      end)
      |> compare_equal_fields(mode, baseline, candidate, @workload_fields, fn field ->
        {"workload.#{field}", ["workload", field]}
      end)
      |> compare_equal_fields(mode, baseline, candidate, @flag_fields, fn field ->
        {"flags.#{field}", ["flags", field]}
      end)
      |> compare_aggregate_limits(mode, baseline, candidate)

    result = %{
      status: if(failures == [], do: "ok", else: "fail"),
      checks: checks,
      failures: Enum.reverse(failures)
    }

    {result, failures}
  end

  defp compare_equal_fields({checks, failures}, mode, baseline, candidate, fields, path_fun) do
    Enum.map_reduce(fields, failures, fn field, failures ->
      {label, path} = path_fun.(field)
      lhs = get_in(baseline, path)
      rhs = get_in(candidate, path)
      status = if lhs == rhs, do: "ok", else: "fail"

      failure =
        if lhs == rhs,
          do: nil,
          else: "#{mode}: #{label} differs (baseline #{inspect(lhs)}, candidate #{inspect(rhs)})"

      check = %{
        kind: "equal",
        field: label,
        baseline_value: lhs,
        candidate_value: rhs,
        status: status,
        failure: failure
      }

      next_failures = if is_nil(failure), do: failures, else: [failure | failures]
      {check, next_failures}
    end)
    |> then(fn {new_checks, failures} -> {checks ++ new_checks, failures} end)
  end

  defp compare_aggregate_limits({checks, failures}, mode, baseline, candidate) do
    Enum.map_reduce(@aggregate_limits, failures, fn {field, limit}, failures ->
      lhs = get_in(baseline, ["aggregate", field])
      rhs = get_in(candidate, ["aggregate", field])

      {status, threshold, failure} =
        cond do
          is_nil(lhs) ->
            {"not_applicable", nil, nil}

          is_nil(rhs) ->
            {"missing", nil, "#{mode}: aggregate #{field} missing from candidate"}

          true ->
            allowed = allowed_value(lhs * 1.0, limit.max_ratio, limit.slack)

            if rhs * 1.0 > allowed do
              {"fail", allowed,
               "#{mode}: aggregate #{field} #{rhs} exceeds #{format_float(allowed)} (baseline #{lhs})"}
            else
              {"ok", allowed, nil}
            end
        end

      check = %{
        kind: "aggregate_limit",
        field: field,
        baseline_value: lhs,
        candidate_value: rhs,
        limit: threshold,
        status: status,
        failure: failure
      }

      next_failures = if is_nil(failure), do: failures, else: [failure | failures]
      {check, next_failures}
    end)
    |> then(fn {new_checks, failures} -> {checks ++ new_checks, failures} end)
  end

  defp allowed_value(baseline, max_ratio, slack) do
    max(baseline * max_ratio, baseline + slack)
  end

  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact])
  defp format_float(value), do: to_string(value)

  defp normalize_nulls(:null), do: nil

  defp normalize_nulls(list) when is_list(list) do
    Enum.map(list, &normalize_nulls/1)
  end

  defp normalize_nulls(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, normalize_nulls(value)} end)
  end

  defp normalize_nulls(value), do: value
end
