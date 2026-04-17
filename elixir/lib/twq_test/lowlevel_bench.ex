defmodule TwqTest.LowlevelBench do
  @moduledoc """
  Elixir-side helpers for the combined M13 low-level benchmark artifact.

  This artifact groups the Zig syscall hot-path suite and the warmed-worker
  workqueue wake suite under one repo-owned schema so the full low-level floor
  can be validated together.
  """

  alias TwqTest.{JSON, WorkqueueWake, ZigHotpath}

  @type comparison :: %{
          ok?: boolean(),
          failures: [String.t()],
          suites: %{String.t() => map()}
        }

  @spec load(String.t()) :: map()
  def load(path) when is_binary(path) do
    path
    |> File.read!()
    |> JSON.decode!()
  end

  @spec normalize(String.t() | map()) :: %{String.t() => %{String.t() => map()}}
  def normalize(path) when is_binary(path), do: path |> load() |> normalize()

  def normalize(%{} = artifact) do
    suites = Map.get(artifact, "suites", %{})

    %{
      "zig_hotpath" => suites |> Map.get("zig_hotpath", %{}) |> ZigHotpath.normalize(),
      "workqueue_wake" => suites |> Map.get("workqueue_wake", %{}) |> WorkqueueWake.normalize()
    }
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

    baseline_suites = Map.get(baseline, "suites", %{})
    candidate_suites = Map.get(candidate, "suites", %{})

    {zig, zig_failures} =
      compare_suite(
        "zig_hotpath",
        &ZigHotpath.compare/3,
        baseline_suites,
        candidate_suites,
        opts
      )

    {wake, wake_failures} =
      compare_suite(
        "workqueue_wake",
        &WorkqueueWake.compare/3,
        baseline_suites,
        candidate_suites,
        opts
      )

    failures = zig_failures ++ wake_failures

    %{
      ok?: failures == [],
      failures: failures,
      suites: %{"zig_hotpath" => zig, "workqueue_wake" => wake}
    }
  end

  @spec assert_ok!(comparison()) :: comparison()
  def assert_ok!(%{ok?: true} = comparison), do: comparison

  def assert_ok!(%{failures: failures}) do
    raise "M13 low-level comparison failed:\n" <> Enum.join(failures, "\n")
  end

  defp compare_suite(name, comparator, baseline_suites, candidate_suites, opts) do
    cond do
      not Map.has_key?(baseline_suites, name) ->
        {%{ok?: false, failures: ["missing from baseline"], modes: []},
         ["#{name}: missing from baseline"]}

      not Map.has_key?(candidate_suites, name) ->
        {%{ok?: false, failures: ["missing from candidate"], modes: []},
         ["#{name}: missing from candidate"]}

      true ->
        result =
          comparator.(Map.fetch!(baseline_suites, name), Map.fetch!(candidate_suites, name), opts)

        {result, Enum.map(result.failures, &("#{name}: " <> &1))}
    end
  end
end
