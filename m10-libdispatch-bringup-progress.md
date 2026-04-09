# M10 Progress: `libdispatch` Bring-Up

## Outcome

`libdispatch` now builds locally against the staged custom `libthr` and runs in
the `bhyve` guest through both a basic dispatch probe and a pressured dispatch
probe.

This is no longer just a source-level or link-level milestone. The guest now
proves both real dispatch execution on top of the TWQ path and real pressure
feedback affecting default worker concurrency.

## Important Source Work

### 1. Minimal pthread QoS/private surface added in `/usr/src`

The staged `libthr` surface was extended so `libdispatch` can enter its real
pthread workqueue path without dragging in unrelated Darwin subsystems.

Important additions:

1. `/usr/src/include/pthread/qos.h`
2. `/usr/src/include/pthread/qos_private.h`
3. `/usr/src/include/pthread/workqueue_private.h`
4. `/usr/src/lib/libthr/thread/thr_workq.c`
5. `/usr/src/lib/libthr/pthread.map`

What was added:

1. `_pthread_qos_class_encode()`
2. `_pthread_qos_class_decode()`
3. `_pthread_qos_class_encode_workqueue()`
4. `_pthread_set_properties_self()`
5. `pthread_qos_max_parallelism()`
6. `pthread_time_constraint_max_parallelism()`
7. `qos_class_main()`
8. `qos_class_self()`
9. `pthread_set_qos_class_self_np()`
10. direct override entry points used by dispatch, currently as controlled
    stubs

This keeps the userland contract dispatch expects while still avoiding Mach,
launchd, workloops, or direct kevent workqueue delivery.

### 2. Local `swift-corelibs-libdispatch` tree needed two real fixes

The local dispatch checkout under `../nx/swift-corelibs-libdispatch` had two
build issues for this use case:

1. `cmake/config.h.in` emitted valueless `HAVE_*` macros for:
   `HAVE__PTHREAD_WORKQUEUE_INIT`, `HAVE_PTHREAD_WORKQUEUE_H`,
   `HAVE_PTHREAD_WORKQUEUE_PRIVATE_H`, and `HAVE_PTHREAD_QOS_H`
2. `src/voucher_internal.h` lacked a no-voucher
   `_voucher_release_no_dispose()` stub in the disabled-mach-voucher path

Those were fixed locally so the dispatch tree can be rebuilt reproducibly
against the staged custom pthread surface.

### 3. Dispatch build and staging are now scripted

New script:

1. `scripts/libdispatch/prepare-stage.sh`

This script now:

1. configures the local `swift-corelibs-libdispatch` tree with external
   pthread workqueues enabled
2. points the build at the staged custom `libthr`
3. uses the staged pthread private headers
4. builds `libdispatch.so`
5. stages `libdispatch.so` and `libBlocksRuntime.so` into
   `../artifacts/libdispatch-stage`

## New Probe and Harness Work

New probe:

1. `csrc/twq_dispatch_probe.c`

What it does:

1. exposes a `basic` mode:
   - loads `dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)`
   - submits a burst of default-QoS async tasks
   - waits with a timeout
   - reports requested tasks, started tasks, completed tasks, unique worker
     threads, peak concurrency, main-thread callback count, and
     `_pthread_workqueue_supported()` feature bits
2. exposes a `pressure` mode:
   - starts a user-interactive worker that blocks long enough to overlap lower
     QoS work
   - submits a matching default-QoS burst while that higher-priority worker is
     active
   - reports default-task completion, high-priority-task completion, unique
     worker threads, and peak default concurrency under pressure

New harness pieces:

1. `scripts/bhyve/stage-guest.sh`
2. `elixir/lib/twq_test/zig.ex`
3. `elixir/lib/twq_test/vm.ex`
4. `elixir/test/twq_test/vm_integration_test.exs`

What changed:

1. the host now stages `libdispatch.so`, `libBlocksRuntime.so`, and the new
   dispatch probe into the guest
2. the guest runs the dispatch probe with:
   `LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib`
3. the guest now captures separate TWQ snapshots around both:
   - the basic dispatch workload
   - the pressured dispatch workload
4. ExUnit now asserts all of the following:
   - successful basic dispatch execution
   - successful pressured dispatch execution
   - counter deltas proving the real TWQ path was exercised
   - peak default concurrency is lower under pressure than in the basic case
   - the default bucket requests more work than the kernel admits under the
     pressured workload

## Validation

### Local

Passed:

1. `scripts/libdispatch/prepare-stage.sh`
2. manual build of `../artifacts/zig/prefix/bin/twq-dispatch-probe`
3. `cd elixir && make test`

### Guest

Passed:

1. `cd elixir && env PATH="/usr/local/lib/erlang28/bin:$PATH" TWQ_RUN_VM_INTEGRATION=1 mix test test/twq_test/vm_integration_test.exs`

### Guest Evidence

The guest serial log showed:

1. basic dispatch probe output:
   - `_pthread_workqueue_supported()` reported `19`
   - requested `8` tasks
   - started `8`
   - completed `8`
   - used `4` unique worker threads
   - peak in-flight default concurrency was `4`
   - main-thread callbacks stayed at `0`
2. basic dispatch TWQ deltas:
   - `kern.twq.init_count: 4 -> 5`
   - `kern.twq.setup_dispatch_count: 4 -> 5`
   - `kern.twq.reqthreads_count: 8 -> 23`
   - `kern.twq.thread_enter_count: 3 -> 8`
3. pressured dispatch probe output:
   - requested default work `8`
   - requested high-priority blockers `1`
   - completed default work `8`
   - completed high-priority blockers `1`
   - used `4` unique worker threads
   - peak default concurrency dropped to `3`
   - main-thread callbacks stayed at `0`
4. pressured dispatch TWQ deltas:
   - `kern.twq.init_count: 5 -> 6`
   - `kern.twq.setup_dispatch_count: 5 -> 6`
   - `kern.twq.reqthreads_count: 23 -> 38`
   - `kern.twq.thread_enter_count: 8 -> 13`
   - `kern.twq.switch_block_count: 12 -> 21`
   - `kern.twq.switch_unblock_count: 12 -> 21`
   - the default bucket in `bucket_req_total` grew more than the default
     bucket in `bucket_admit_total`

Those deltas are the important proof:

1. dispatch initialized the real workqueue path
2. dispatch requested additional workers through TWQ
3. worker threads actually entered the kernel-tracked path
4. the pressured workload exercised real TWQ pressure accounting rather than a
   blind pthread-pool fallback
5. this was not a silent fallback to the generic pthread pool

## Milestone Reading

This milestone is now complete enough for its intended purpose.

What is now true:

1. `libdispatch` builds and runs in the guest against the staged custom
   `libthr`
2. the guest proves real TWQ activity under both basic and pressured dispatch
   workloads
3. silent fallback is actively checked and ruled out for these workloads
4. TWQ pressure now has visible behavioral effect on default dispatch
   concurrency in the guest

## Next Step

The next high-value step is M11: validate against the local Apple tree and use
the macOS lane for canonical behavior comparison when needed.
