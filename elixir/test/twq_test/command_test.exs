defmodule TwqTest.CommandTest do
  use ExUnit.Case, async: true

  alias TwqTest.Command

  test "captures output and exit status for a successful command" do
    result = Command.run("/usr/bin/printf", ["twq-ok"], timeout: 1_000)

    assert Command.Result.ok?(result)
    assert result.output == "twq-ok"
    assert result.exit_status == 0
    assert result.timed_out? == false
  end

  test "marks a timed out command clearly" do
    result = Command.run("/bin/sh", ["-c", "sleep 1"], timeout: 10)

    refute Command.Result.ok?(result)
    assert result.exit_status == 124
    assert result.timed_out? == true
  end
end
