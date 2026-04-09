defmodule TwqTest.VMTest do
  use ExUnit.Case, async: true

  alias TwqTest.VM

  test "stage_guest dry-run emits a staging plan" do
    result =
      VM.stage_guest(
        dry_run: true,
        vm_image: "/tmp/twq-stage.img",
        guest_root: "/tmp/twq-stage-root"
      )

    assert result.exit_status == 0
    assert String.contains?(result.output, "attach image with mdconfig")
    assert String.contains?(result.output, "/tmp/twq-stage-root")
  end

  test "run_guest dry-run emits a bhyve command line" do
    result =
      VM.run_guest(
        dry_run: true,
        vm_name: "twq-dry-run",
        vm_image: "/tmp/twq-dry-run.img",
        vcpus: 2,
        memory: "4G"
      )

    assert result.exit_status == 0
    assert String.contains?(result.output, "bhyve")
    assert String.contains?(result.output, "twq-dry-run")
    assert String.contains?(result.output, "/tmp/twq-dry-run.img")
  end

  test "update_kernel dry-run emits a copy plan" do
    result =
      VM.update_kernel(
        "/tmp/kernel-WORKQUEUE",
        dry_run: true,
        guest_root: "/tmp/guest-root"
      )

    assert result.exit_status == 0
    assert String.contains?(result.output, "copy kernel")
    assert String.contains?(result.output, "/tmp/kernel-WORKQUEUE")
    assert String.contains?(result.output, "/tmp/guest-root")
  end

  test "collect_crash dry-run emits a collection plan" do
    result =
      VM.collect_crash(
        "/tmp/savecore",
        "/tmp/out",
        dry_run: true
      )

    assert result.exit_status == 0
    assert String.contains?(result.output, "collect crash")
    assert String.contains?(result.output, "/tmp/savecore")
    assert String.contains?(result.output, "/tmp/out")
  end
end
