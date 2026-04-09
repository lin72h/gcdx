# M09 Progress: `libthr` Bridge

## Scope

This milestone was the first real userland bridge pass:

1. expose the modern pthread_workqueue SPI from `libthr`;
2. stage a custom `libthr` into the `bhyve` guest;
3. prove that guest userland can drive the kernel TWQ path through that
   bridge.

This is the point where the project stops being kernel-only.

## Important Outcome

The guest now runs a userland pthread_workqueue probe through the custom
`libthr` bridge, not just the raw syscall scaffold.

Observed in the guest serial log:

1. `supported` reports `19`;
2. `_pthread_workqueue_init()` returns `0`;
3. `pthread_workqueue_addthreads_np(..., 2)` returns `0`;
4. two callbacks execute successfully;
5. the observed callback priority is `5376`;
6. callback-side `_pthread_workqueue_should_narrow()` stayed false in both
   callbacks for this simple default-priority case.

The exact emitted lines were:

```text
{"kind":"zig-workq-probe","status":"ok","data":{"mode":"supported","rc":19,"requested":0,"observed":0,"timed_out":false,"features":19,"priority":0,"narrow_true":0,"narrow_false":0},"meta":{"component":"c","binary":"twq-workqueue-probe"}}
{"kind":"zig-workq-probe","status":"ok","data":{"mode":"init","rc":0,"requested":0,"observed":0,"timed_out":false,"features":19,"priority":0,"narrow_true":0,"narrow_false":0},"meta":{"component":"c","binary":"twq-workqueue-probe"}}
{"kind":"zig-workq-probe","status":"ok","data":{"mode":"addthreads","rc":0,"requested":2,"observed":0,"timed_out":false,"features":19,"priority":0,"narrow_true":0,"narrow_false":0},"meta":{"component":"c","binary":"twq-workqueue-probe"}}
{"kind":"zig-workq-probe","status":"ok","data":{"mode":"callbacks","rc":0,"requested":2,"observed":2,"timed_out":false,"features":19,"priority":5376,"narrow_true":0,"narrow_false":2},"meta":{"component":"c","binary":"twq-workqueue-probe"}}
```

That is the first proof that the `libthr` bridge is usable by real guest
userland.

## Kernel-Side State

The bridge is built on top of the kernel work already landed in `/usr/src`:

1. `TWQ_OP_INIT`
2. `TWQ_OP_SETUP_DISPATCH`
3. `TWQ_OP_REQTHREADS`
4. `TWQ_OP_THREAD_ENTER`
5. `TWQ_OP_THREAD_RETURN`
6. `TWQ_OP_SHOULD_NARROW`

Those paths were already stateful and guest-validated before this milestone.
What changed here is that `libthr` now drives them on behalf of userland.

## `libthr` Bridge Work

Important `/usr/src` changes:

1. `/usr/src/include/pthread/workqueue_private.h`
2. `/usr/src/include/pthread_workqueue.h`
3. `/usr/src/include/Makefile`
4. `/usr/src/include/pthread/Makefile`
5. `/usr/src/lib/libthr/thread/thr_workq.c`
6. `/usr/src/lib/libthr/thread/thr_workq_kern.h`
7. `/usr/src/lib/libthr/thread/Makefile.inc`
8. `/usr/src/lib/libthr/pthread.map`
9. `/usr/src/lib/libthr/thread/thr_syscalls.c`
10. `/usr/src/lib/libthr/Makefile`

Important behavior now present in `thr_workq.c`:

1. bridge-level runtime state for pending, active, idle, and live workers;
2. SPI entry points for initialization, feature reporting, addthreads, and
   narrowing;
3. worker creation through detached pthreads;
4. per-worker kernel notifications for enter and return;
5. request synchronization back to the kernel on queue growth and worker exit.

## Build and Staging Decisions

Two build-system problems showed up and had to be handled pragmatically.

### 1. Avoid the `libsys` stub dependency

The first bridge revision still depended on:

1. `__sys_twq_kernreturn`
2. `__sys_pdwait`

That made the custom `libthr` unusable with the stock guest `libsys.so.7`.

The fix was to stop depending on those generated stubs in the bridge path:

1. `thr_workq.c` now uses raw syscall `468` directly;
2. `thr_syscalls.c` now uses raw syscall `601` for `pdwait`.

### 2. Do not carry a custom `libsys.so.7`

The default `libthr` shared-library link path in the objdir still pulled in a
non-PIC `libsys.a` / `libsys_pie.a` combination and failed with relocation
errors.

That is not worth solving in this milestone. The stable staging artifact is:

1. build the `libthr` PIC objects in the objdir;
2. link `libthr.so.3` manually against the host `libsys.so.7`;
3. stage only that custom `libthr` into the guest.

This is implemented in:

1. `scripts/libthr/prepare-stage.sh`

The staged directory currently contains:

1. `libthr.so.3`
2. `libthr.so -> libthr.so.3`
3. `libpthread.so -> libthr.so.3`

## Harness Work

Important repo-side changes:

1. `scripts/libthr/prepare-stage.sh`
2. `scripts/bhyve/stage-guest.sh`
3. `csrc/twq_workqueue_probe.c`
4. `elixir/lib/twq_test/env.ex`
5. `elixir/lib/twq_test/zig.ex`
6. `elixir/lib/twq_test/vm.ex`
7. `elixir/test/twq_test/vm_integration_test.exs`

Important behavior now present in the harness:

1. host-side preparation of a staged custom `libthr`;
2. copy of that staged `libthr` into `/root/twq-lib` in the guest image;
3. execution of a guest-side userland pthread_workqueue probe with
   `LD_LIBRARY_PATH=/root/twq-lib`;
4. ExUnit assertions on both:
   the old raw syscall sequence and the new userland bridge probe.

## Zig Note

The raw syscall probe and benchmark lane remain Zig-based, which is still the
right direction for low-level ABI probing and performance work.

For this first userland bridge milestone, the dedicated workqueue probe is C,
not Zig, for a narrow reason:

1. the local Zig 0.15.2 driver special-cased pthread linkage in a way that did
   not honor the staged custom `libthr` path cleanly on this host;
2. `cc` linked the same probe against the staged `libthr` immediately and
   reliably.

That is a toolchain detail, not a project-direction problem. It can be revisited
later without changing the bridge or guest workflow.

## Validation

Validated in this order:

1. `make test` under `elixir/`
2. `TWQ_RUN_VM_INTEGRATION=1 mix test test/twq_test/vm_integration_test.exs`
3. guest serial-log inspection of both the raw syscall lines and the userland
   bridge lines

Current result:

1. 15 ExUnit tests pass, with 1 gated skip in the normal host run;
2. the dedicated VM integration test passes;
3. the guest proves both the raw ABI and the staged-`libthr` userland path.

## Remaining Gap

This milestone proves the bridge is usable by a dedicated guest probe.

It does not yet prove:

1. `libdispatch` uses it correctly;
2. there is no silent fallback inside dispatch;
3. the bridge shape is sufficient for real dispatch worker behavior.

That is the next milestone.
