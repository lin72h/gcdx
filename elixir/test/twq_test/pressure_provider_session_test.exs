defmodule TwqTest.PressureProviderSessionTest do
  use ExUnit.Case, async: true

  alias TwqTest.PressureProviderSession

  @repo_root Path.expand("../../..", __DIR__)

  @baseline Path.join(
              @repo_root,
              "benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json"
            )

  test "loads the checked-in session baseline" do
    payload = PressureProviderSession.load(@baseline)

    assert payload["session_kind"] == "callable_session_v1"
    assert payload["view_kind"] == "aggregate_view_v1"
    assert get_in(payload, ["contract", "current_signal_field"]) == "nonidle_workers_current"
  end

  test "accepts the checked-in session baseline against itself" do
    comparison = PressureProviderSession.compare(@baseline, @baseline)

    assert comparison.ok?
    assert comparison.failures == []
  end

  test "fails when session struct size drifts" do
    candidate =
      @baseline
      |> PressureProviderSession.load()
      |> put_in(["captures", "dispatch.pressure", "session_struct_size"], 0)

    comparison = PressureProviderSession.compare(@baseline, candidate)

    refute comparison.ok?

    assert Enum.any?(
             comparison.failures,
             &String.contains?(&1, "session_struct_size differs")
           )
  end
end
