defmodule TwqTest.ZigTest do
  use ExUnit.Case, async: false

  alias TwqTest.Zig

  test "runs zig abi scaffold step successfully" do
    result = Zig.abi()

    assert result.exit_status == 0
    assert result.timed_out? == false
  end

  test "builds the zig syscall hot-path benchmark" do
    result = Zig.build_hotpath_bench()

    assert result.exit_status == 0
    assert result.timed_out? == false
  end

  test "builds and runs the zig probe against the stock host baseline" do
    result = Zig.run_probe(probe_args: ["--op", "1"])

    assert result.exit_status == 0
    assert String.contains?(result.output, "\"kind\":\"zig-probe\"")
    assert String.contains?(result.output, "\"status\":\"signal\"")
    assert String.contains?(result.output, "\"signal_name\":\"SIGSYS\"")
  end
end
