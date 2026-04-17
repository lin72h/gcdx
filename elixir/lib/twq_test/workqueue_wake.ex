defmodule TwqTest.WorkqueueWake do
  @moduledoc """
  Elixir-side helpers for workqueue wake benchmark artifacts.

  This benchmark lane measures request-to-callback latency once a worker is
  already warm and idle. It reuses the generic suite comparison logic while
  adding the thread-reuse guard that matters for this benchmark.
  """

  alias TwqTest.ZigHotpath

  @default_counter_metrics ~w(
    reqthreads_count
    thread_enter_count
    thread_return_count
    thread_transfer_count
    thread_mismatch_count
  )

  @spec load(String.t()) :: map()
  defdelegate load(path), to: ZigHotpath

  @spec normalize(String.t() | map()) :: %{String.t() => map()}
  defdelegate normalize(path_or_map), to: ZigHotpath

  @spec compare(String.t(), String.t(), keyword()) :: map()
  def compare(baseline_path, candidate_path, opts \\ []) do
    ZigHotpath.compare(
      baseline_path,
      candidate_path,
      Keyword.put_new(opts, :counter_metrics, @default_counter_metrics)
    )
  end

  @spec assert_ok!(map()) :: map()
  defdelegate assert_ok!(comparison), to: ZigHotpath
end
