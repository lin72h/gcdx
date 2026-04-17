defmodule TwqTest.VMIntegrationTest do
  use ExUnit.Case, async: false

  alias TwqTest.VM

  @run_vm_integration? System.get_env("TWQ_RUN_VM_INTEGRATION") == "1"
  @moduletag timeout: 360_000
  @moduletag skip: not @run_vm_integration?

  test "probe_guest stages the image, boots TWQDEBUG, and captures probe output" do
    repo_root = Path.expand("../../..", __DIR__)
    temp_root = System.tmp_dir!()
    vm_name = "twq-dev"
    vm_image = Path.expand("../vm/runs/#{vm_name}.img", repo_root)
    serial_log = Path.join(temp_root, "#{vm_name}.integration.serial.log")
    guest_root = Path.join(temp_root, "#{vm_name}.integration.root")

    result =
      VM.probe_guest(
        vm_name: vm_name,
        vm_image: vm_image,
        serial_log: serial_log,
        guest_root: guest_root,
        command_timeout_ms: 300_000
      )

    probe_lines =
      result.data[:serial_log]
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "\"kind\":\"zig-probe\""))

    workqueue_probe_lines =
      result.data[:serial_log]
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "\"kind\":\"zig-workq-probe\""))

    dispatch_probe_lines =
      result.data[:serial_log]
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "\"kind\":\"dispatch-probe\""))

    swift_probe_lines =
      result.data[:serial_log]
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "\"kind\":\"swift-probe\""))

    dispatch_basic_line = dispatch_line_for_mode(dispatch_probe_lines, "\"mode\":\"basic\"")
    dispatch_pressure_line = dispatch_line_for_mode(dispatch_probe_lines, "\"mode\":\"pressure\"")

    workqueue_timeout_line =
      dispatch_line_for_mode(workqueue_probe_lines, "\"mode\":\"idle-timeout\"")

    swift_async_smoke_line = dispatch_line_for_mode(swift_probe_lines, "\"mode\":\"async-smoke\"")

    swift_dispatch_line =
      dispatch_line_for_mode(swift_probe_lines, "\"mode\":\"dispatch-control\"")

    swift_mainqueue_resume_line =
      dispatch_line_for_mode(swift_probe_lines, "\"mode\":\"mainqueue-resume\"")

    swift_dispatch_before =
      section_between(
        result.data[:serial_log],
        "=== twq swift dispatch stats before ===",
        "=== twq swift dispatch stats before end ==="
      )

    swift_dispatch_after =
      section_between(
        result.data[:serial_log],
        "=== twq swift dispatch stats after ===",
        "=== twq swift dispatch stats after end ==="
      )

    swift_mainqueue_resume_before =
      section_between(
        result.data[:serial_log],
        "=== twq swift mainqueue resume stats before ===",
        "=== twq swift mainqueue resume stats before end ==="
      )

    swift_mainqueue_resume_after =
      section_between(
        result.data[:serial_log],
        "=== twq swift mainqueue resume stats after ===",
        "=== twq swift mainqueue resume stats after end ==="
      )

    assert result.status == :ok
    assert result.data[:validation_failures] == []
    assert result.data[:swift_probe_profile] == "validation"
    assert is_list(result.data[:swift_timeout_modes])
    assert String.contains?(result.data[:serial_log], "FreeBSD 15.0-STABLE TWQDEBUG amd64")
    assert String.contains?(result.data[:serial_log], "=== twq swift profile ===")

    assert Enum.any?(
             probe_lines,
             &line_has?(&1, "\"mode\":\"init\"", "\"rc\":19", "\"errno_name\":\"OK\"")
           )

    assert Enum.any?(
             probe_lines,
             &line_has?(&1, "\"mode\":\"raw\"", "\"op\":9999", "\"errno_name\":\"EINVAL\"")
           )

    assert String.contains?(workqueue_timeout_line, "\"status\":\"ok\"")

    assert line_int_value(workqueue_timeout_line, "settled_total") ==
             line_int_value(workqueue_timeout_line, "warm_floor")

    assert String.contains?(dispatch_basic_line, "\"status\":\"ok\"")
    assert String.contains?(dispatch_basic_line, "\"completed\":8")
    assert String.contains?(dispatch_pressure_line, "\"status\":\"ok\"")

    assert line_int_value(dispatch_basic_line, "max_inflight") >
             line_int_value(dispatch_pressure_line, "default_max_inflight")

    assert String.contains?(swift_async_smoke_line, "\"status\":\"ok\"")
    assert String.contains?(swift_dispatch_line, "\"status\":\"ok\"")
    assert line_int_value(swift_dispatch_line, "completed") == 8
    assert line_int_value(swift_dispatch_line, "sum") == 28
    assert String.contains?(swift_mainqueue_resume_line, "\"status\":\"ok\"")
    assert String.contains?(swift_mainqueue_resume_line, "\"value\":42")

    assert section_value(swift_dispatch_after, "kern.twq.init_count") >
             section_value(swift_dispatch_before, "kern.twq.init_count")

    assert section_value(swift_dispatch_after, "kern.twq.setup_dispatch_count") >
             section_value(swift_dispatch_before, "kern.twq.setup_dispatch_count")

    assert section_value(swift_dispatch_after, "kern.twq.reqthreads_count") >
             section_value(swift_dispatch_before, "kern.twq.reqthreads_count")

    assert section_value(swift_dispatch_after, "kern.twq.thread_enter_count") >
             section_value(swift_dispatch_before, "kern.twq.thread_enter_count")

    assert section_value(swift_mainqueue_resume_after, "kern.twq.reqthreads_count") >
             section_value(swift_mainqueue_resume_before, "kern.twq.reqthreads_count")

    assert section_value(swift_mainqueue_resume_after, "kern.twq.thread_enter_count") >
             section_value(swift_mainqueue_resume_before, "kern.twq.thread_enter_count")
  end

  test "stock toolchain dispatch plus custom libthr completes delayed taskgroup child completion without TWQ activity" do
    repo_root = Path.expand("../../..", __DIR__)
    temp_root = System.tmp_dir!()
    vm_name = "twq-dev"
    vm_image = Path.expand("../vm/runs/#{vm_name}.img", repo_root)
    serial_log = Path.join(temp_root, "#{vm_name}.integration.serial.log")
    guest_root = Path.join(temp_root, "#{vm_name}.integration.root")
    custom_dispatch = Path.expand("../artifacts/libdispatch-stage/libdispatch.so", repo_root)

    stock_dispatch =
      Path.expand("../artifacts/swift-stock-dispatch-stage/libdispatch.so", repo_root)

    custom_symbols = dispatch_dynamic_symbols(custom_dispatch)
    stock_symbols = dispatch_dynamic_symbols(stock_dispatch)

    result =
      VM.probe_guest(
        vm_name: vm_name,
        vm_image: vm_image,
        serial_log: serial_log,
        guest_root: guest_root,
        command_timeout_ms: 300_000,
        swift_probe_profile: "full",
        swift_probe_filter: "dispatchmain-taskgroup-after-stockdispatch-customthr",
        validate_serial: false
      )

    assert custom_symbols =~ "_pthread_workqueue_init"
    assert custom_symbols =~ "_pthread_workqueue_addthreads"
    refute stock_symbols =~ "_pthread_workqueue_init"
    refute stock_symbols =~ "_pthread_workqueue_addthreads"

    swift_probe_lines =
      result.data[:serial_log]
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.contains?(&1, "\"kind\":\"swift-probe\""))

    taskgroup_after_line =
      dispatch_line_for_mode(swift_probe_lines, "\"mode\":\"dispatchmain-taskgroup-after\"")

    taskgroup_before =
      section_between(
        result.data[:serial_log],
        "=== twq swift dispatchmain taskgroup after stockdispatch customthr stats before ===",
        "=== twq swift dispatchmain taskgroup after stockdispatch customthr stats before end ==="
      )

    taskgroup_after =
      section_between(
        result.data[:serial_log],
        "=== twq swift dispatchmain taskgroup after stockdispatch customthr stats after ===",
        "=== twq swift dispatchmain taskgroup after stockdispatch customthr stats after end ==="
      )

    assert result.status == :ok
    assert String.contains?(taskgroup_after_line, "\"status\":\"ok\"")
    assert String.contains?(taskgroup_after_line, "\"completed\":8")
    assert String.contains?(taskgroup_after_line, "\"sum\":28")

    assert section_value(taskgroup_after, "kern.twq.reqthreads_count") ==
             section_value(taskgroup_before, "kern.twq.reqthreads_count")

    assert section_value(taskgroup_after, "kern.twq.thread_enter_count") ==
             section_value(taskgroup_before, "kern.twq.thread_enter_count")
  end

  defp line_has?(line, fragment1, fragment2, fragment3) do
    String.contains?(line, fragment1) and
      String.contains?(line, fragment2) and
      String.contains?(line, fragment3)
  end

  defp section_between(serial_log, start_marker, end_marker) do
    case String.split(serial_log, start_marker, parts: 2) do
      [_prefix, rest] ->
        case String.split(rest, end_marker, parts: 2) do
          [section, _suffix] -> section
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp section_value(section, key) do
    case Regex.run(~r/#{Regex.escape(key)}: (\d+)/, section) do
      [_, value] -> String.to_integer(value)
      _ -> -1
    end
  end

  defp dispatch_line_for_mode(probe_lines, mode_fragment) do
    probe_lines
    |> Enum.filter(&String.contains?(&1, mode_fragment))
    |> List.last()
    |> Kernel.||("")
  end

  defp line_int_value(line, key) do
    case Regex.run(~r/"#{Regex.escape(key)}":(\d+)/, line) do
      [_, value] -> String.to_integer(value)
      _ -> -1
    end
  end

  defp dispatch_dynamic_symbols(path) do
    {output, 0} = System.cmd("nm", ["-D", path], stderr_to_stdout: true)
    output
  end
end
