# M02: bhyve Execution Progress

## Objective

Turn the VM lane into a real engineering loop:

1. stage a FreeBSD 15 guest image without polluting this repo;
2. install the custom `TWQDEBUG` kernel safely;
3. boot the guest under `bhyve`;
4. run the raw `twq_kernreturn` probe inside the guest automatically;
5. capture the serial log for regression testing.

## Current Result

This milestone is now proven end-to-end.

The guest boots the custom kernel, runs the probe from `rc`, and powers off
cleanly. The observed transition is the exact one the scaffold should produce:

1. stock host kernel: syscall `468` traps with `SIGSYS`;
2. guest `TWQDEBUG` kernel: known `TWQ_OP_INIT` returns `ENOTSUP`;
3. guest `TWQDEBUG` kernel: invalid op returns `EINVAL`.

That confirms the VM path is executing the custom kernel and not silently
falling back to the stock host behavior.

## Scripts and Harness

The important pieces now in this repo are:

1. `scripts/bhyve/stage-guest.sh`
2. `scripts/bhyve/run-guest.sh`
3. `zig/src/twq_probe_stub.zig`
4. `elixir/lib/twq_test/vm.ex`
5. `elixir/test/twq_test/vm_integration_test.exs`

The Elixir harness can now drive the real guest path through
`TwqTest.VM.probe_guest/1`.

## Key Decisions

### 1. Alternate kernel slot, not in-place `/boot/kernel` replacement

The initial `installkernel` path failed because it tried to install a full
module set from an objdir that only had the linked kernel.

The correct FreeBSD-native fix was:

1. use `INSTKERNNAME=TWQDEBUG`;
2. use `NO_MODULES=yes`;
3. boot with `kernel="TWQDEBUG"`;
4. preserve module loading with
   `module_path="/boot/kernel;/boot/modules;/boot/TWQDEBUG"`.

This keeps the stock image recoverable and avoids unnecessary module churn.

### 2. Guest mountpoint normalization

The staging cleanup initially leaked mounted `md` devices because the script
compared the literal `TWQ_GUEST_ROOT` path, which could contain `../`, against
the canonical mount path reported by `mount(8)`.

The fix was to normalize `guest_root` after creation so unmount and
`mdconfig -d` target the real mounted path.

### 3. Serial log capture as a first-class output

`run-guest.sh` now supports a real `TWQ_SERIAL_LOG` capture path instead of
only printing to the terminal. That makes the VM lane usable from ExUnit.

## Observed Guest Output

The important guest-side probe lines are:

```json
{"kind":"zig-probe","status":"syscall_error","data":{"syscall":468,"op":1,"arg3":0,"arg4":0,"rc":-1,"errno":45,"errno_name":"ENOTSUP"},"meta":{"component":"zig","binary":"twq-probe-stub"}}
{"kind":"zig-probe","status":"syscall_error","data":{"syscall":468,"op":9999,"arg3":0,"arg4":0,"rc":-1,"errno":22,"errno_name":"EINVAL"},"meta":{"component":"zig","binary":"twq-probe-stub"}}
```

The boot log also confirms the guest is running:

1. `FreeBSD 15.0-STABLE TWQDEBUG amd64`

## Validation Performed

1. manual guest staging and serial boot;
2. normal Elixir suite:
   `make test`
3. gated VM integration test:
   `TWQ_RUN_VM_INTEGRATION=1 mix test test/twq_test/vm_integration_test.exs`

The gated integration test passed locally and completed the full stage, boot,
probe, capture, and shutdown cycle.

## What This Unlocks

With M02 proven, later kernel milestones can be tested without host rebooting:

1. syscall ABI extensions;
2. real per-process and per-thread state;
3. scheduler feedback hooks;
4. guest-side regression checks from Elixir.

## Next Step

The next highest-value work is M05 into M06:

1. replace no-op lifecycle anchors with real `twq_proc` and `twq_thread`
   allocation and teardown;
2. define the first real kernel-private `TWQ_OP_*` state layout;
3. keep using the VM probe lane to validate each step before touching
   `libthr`.
