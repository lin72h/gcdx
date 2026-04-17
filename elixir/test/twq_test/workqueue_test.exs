defmodule TwqTest.WorkqueueTest do
  use ExUnit.Case, async: false

  alias TwqTest.Workqueue

  test "builds the workqueue wake benchmark" do
    result = Workqueue.build_wake_bench()

    assert result.exit_status == 0
    assert result.timed_out? == false
  end
end
