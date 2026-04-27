defmodule TwqTest.PressureProviderObserver do
  @moduledoc """
  Elixir-side helpers for the M15 pressure-provider observer smoke artifact.

  This lane validates a policyless observer summary built above the aggregate
  pressure adapter view and below any real consumer integration.
  """

  alias TwqTest.JSON

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
    ["observer_kind"],
    ["source_session_kind"],
    ["source_view_kind"],
    ["metadata", "generation_kind"],
    ["metadata", "monotonic_time_kind"],
    ["metadata", "label_count"]
  ]

  @capture_equal_fields ~w(
    label
    interval_ms
    duration_ms
    struct_version
    struct_size
    source_session_version
    source_session_struct_size
    source_view_version
    source_view_struct_size
    final_pressure_visible
    final_quiescent
  )

  @required_true_fields ~w(generation_contiguous monotonic_increasing final_quiescent)

  @minimum_ratio_fields %{
    "sample_count" => 0.50,
    "pressure_visible_samples" => 0.25,
    "nonidle_samples" => 0.25,
    "request_backlog_samples" => 0.25,
    "block_backlog_samples" => 0.25,
    "narrow_feedback_samples" => 0.25,
    "quiescent_samples" => 0.25,
    "max_nonidle_workers_current" => 0.50,
    "max_request_backlog_total" => 0.50,
    "max_block_backlog_total" => 0.50
  }

  @upper_limit_fields ~w(final_total_workers_current final_nonidle_workers_current)

  @type comparison :: %{
          ok?: boolean(),
          failures: [String.t()],
          top_level: [map()],
          captures: %{String.t() => map()}
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

    baseline_captures = Map.get(baseline, "captures", %{})
    candidate_captures = Map.get(candidate, "captures", %{})

    labels =
      (Map.keys(baseline_captures) ++ Map.keys(candidate_captures))
      |> Enum.uniq()
      |> Enum.sort()

    {captures, capture_failures} =
      Enum.map_reduce(labels, top_level_failures, fn label, failures ->
        {result, label_failures} =
          compare_capture(
            label,
            Map.get(baseline_captures, label),
            Map.get(candidate_captures, label)
          )

        {{label, result}, Enum.reverse(label_failures) ++ failures}
      end)

    failures = Enum.reverse(capture_failures)

    %{
      ok?: failures == [],
      failures: failures,
      top_level: top_level,
      captures: Map.new(captures)
    }
  end

  @spec assert_ok!(comparison()) :: comparison()
  def assert_ok!(%{ok?: true} = comparison), do: comparison

  def assert_ok!(%{failures: failures}) do
    raise "pressure-provider observer comparison failed:\n" <> Enum.join(failures, "\n")
  end

  defp compare_capture(label, nil, _candidate) do
    result = %{status: "missing-baseline", checks: [], failures: ["missing from baseline"]}
    {result, ["#{label}: missing from baseline"]}
  end

  defp compare_capture(label, _baseline, nil) do
    result = %{status: "missing-candidate", checks: [], failures: ["missing from candidate"]}
    {result, ["#{label}: missing from candidate"]}
  end

  defp compare_capture(label, baseline, candidate) do
    {checks, failures} =
      {[], []}
      |> compare_required_true(label, candidate)
      |> compare_equal_fields(label, baseline, candidate)
      |> compare_minimum_ratios(label, baseline, candidate)
      |> compare_upper_limits(label, baseline, candidate)

    result = %{
      status: if(failures == [], do: "ok", else: "fail"),
      checks: checks,
      failures: Enum.reverse(failures)
    }

    {result, failures}
  end

  defp compare_required_true({checks, failures}, label, candidate) do
    Enum.map_reduce(@required_true_fields, failures, fn field, failures ->
      value = Map.get(candidate, field)
      status = if value == true, do: "ok", else: "fail"
      failure = if value == true, do: nil, else: "#{label}: #{field} is not true"

      check = %{
        kind: "boolean_required",
        field: field,
        candidate_value: value,
        status: status,
        failure: failure
      }

      next_failures = if is_nil(failure), do: failures, else: [failure | failures]
      {check, next_failures}
    end)
    |> then(fn {new_checks, failures} -> {checks ++ new_checks, failures} end)
  end

  defp compare_equal_fields({checks, failures}, label, baseline, candidate) do
    Enum.map_reduce(@capture_equal_fields, failures, fn field, failures ->
      lhs = Map.get(baseline, field)
      rhs = Map.get(candidate, field)
      status = if lhs == rhs, do: "ok", else: "fail"

      failure =
        if lhs == rhs,
          do: nil,
          else: "#{label}: #{field} differs (baseline #{inspect(lhs)}, candidate #{inspect(rhs)})"

      check = %{
        kind: "equal",
        field: field,
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

  defp compare_minimum_ratios({checks, failures}, label, baseline, candidate) do
    Enum.map_reduce(@minimum_ratio_fields, failures, fn {field, ratio}, failures ->
      lhs = Map.get(baseline, field)
      rhs = Map.get(candidate, field)

      {status, minimum, failure} =
        cond do
          is_nil(lhs) ->
            {"not_applicable", nil, nil}

          is_nil(rhs) ->
            {"missing", nil, "#{label}: #{field} missing from candidate"}

          true ->
            minimum = minimum_value(lhs, ratio)

            if rhs * 1.0 < minimum do
              {"fail", minimum,
               "#{label}: #{field} #{rhs} is below #{format_float(minimum)} (baseline #{lhs})"}
            else
              {"ok", minimum, nil}
            end
        end

      check = %{
        kind: "minimum_ratio",
        field: field,
        baseline_value: lhs,
        candidate_value: rhs,
        minimum: minimum,
        status: status,
        failure: failure
      }

      next_failures = if is_nil(failure), do: failures, else: [failure | failures]
      {check, next_failures}
    end)
    |> then(fn {new_checks, failures} -> {checks ++ new_checks, failures} end)
  end

  defp compare_upper_limits({checks, failures}, label, baseline, candidate) do
    Enum.map_reduce(@upper_limit_fields, failures, fn field, failures ->
      lhs = Map.get(baseline, field)
      rhs = Map.get(candidate, field)

      {status, limit, failure} =
        cond do
          is_nil(lhs) ->
            {"not_applicable", nil, nil}

          is_nil(rhs) ->
            {"missing", lhs, "#{label}: #{field} missing from candidate"}

          rhs > lhs ->
            {"fail", lhs, "#{label}: #{field} #{rhs} exceeds #{lhs}"}

          true ->
            {"ok", lhs, nil}
        end

      check = %{
        kind: "upper_limit",
        field: field,
        baseline_value: lhs,
        candidate_value: rhs,
        limit: limit,
        status: status,
        failure: failure
      }

      next_failures = if is_nil(failure), do: failures, else: [failure | failures]
      {check, next_failures}
    end)
    |> then(fn {new_checks, failures} -> {checks ++ new_checks, failures} end)
  end

  defp minimum_value(baseline_value, _ratio) when baseline_value <= 1, do: baseline_value * 1.0
  defp minimum_value(baseline_value, ratio), do: baseline_value * ratio

  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)

  defp normalize_nulls(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {key, normalize_nulls(inner)} end)
    |> Map.new()
  end

  defp normalize_nulls(value) when is_list(value), do: Enum.map(value, &normalize_nulls/1)
  defp normalize_nulls(:null), do: nil
  defp normalize_nulls(value), do: value
end
