defmodule TwqTest.PressureProviderPreviewTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderPreview

  @repo_root Path.expand("../../..", __DIR__)
  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json"
            )

  test "accepts the checked-in preview baseline" do
    comparison = PressureProviderPreview.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when preview top-level contract metadata drifts" do
    candidate =
      @baseline
      |> PressureProviderPreview.load()
      |> put_in(["contract", "current_signal_field"], "active_workers_current")

    comparison = PressureProviderPreview.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "contract.current_signal_field differs")
           )
  end

  test "fails when preview capture monotonicity drifts" do
    candidate =
      @baseline
      |> PressureProviderPreview.load()
      |> put_in(["captures", "dispatch.pressure", "generation_contiguous"], false)

    comparison = PressureProviderPreview.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "generation_contiguous is not true")
           )
  end
end
