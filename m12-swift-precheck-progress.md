# M12 Swift Pre-Check Progress

## Summary

This pass did not complete full Swift workload validation. It reached the first
real Swift boundary instead:

1. the staged Swift 6.3 runtime can start in the `TWQDEBUG` guest;
2. Swift's `Dispatch` import uses the real TWQ-backed path;
3. the first structured-concurrency `TaskGroup` workload also reaches the
   TWQ-backed path;
4. that same `TaskGroup` workload currently times out when it uses
   `Task.sleep`.

That is a useful result. The project is past the "is Swift even touching the
kernel-backed path?" question. The current problem is narrower: a suspended
structured-concurrency workload does not complete under the staged Swift +
`libdispatch` + `libthr` stack.

This document records the first boundary. The later host-vs-guest split and the
current `dispatchMain()`-rooted Swift validation lane are recorded in
[m12-swift-runtime-boundary-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-runtime-boundary-progress.md).

## Code Changes

The guest Swift lane was expanded so it can diagnose this boundary cleanly.

Repo-side changes:

1. [env.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/env.ex)
   now carries Swift staging paths for:
   - `twq-swift-async-smoke`
   - `twq-swift-taskgroup-precheck`
   - `twq-swift-dispatch-control`
2. [swift.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/swift.ex)
   remains the host-side wrapper around Swift staging.
3. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
   now:
   - extracts the local Swift 6.3 toolchain if needed;
   - stages the guest Swift runtime;
   - strips staged `libdispatch.so` and `libBlocksRuntime.so` from the Swift
     runtime tree so the guest prefers the custom staged dispatch;
   - builds all Swift guest probes with guest `RUNPATH`.
4. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
   now:
   - stages the Swift runtime and Swift probe binaries into the guest;
   - runs a dedicated async smoke probe;
   - runs the Swift Dispatch control probe with pre/post `kern.twq.*`
     snapshots;
   - runs the Swift `TaskGroup` probe under a shell timeout wrapper so the
     integration run finishes even when the probe stalls;
   - emits explicit JSON for Swift probe timeout/error cases.
5. [vm.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/vm.ex)
   and
   [vm_integration_test.exs](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/test/twq_test/vm_integration_test.exs)
   now parse the new Swift sections and gate on the Swift results.
6. Swift probes added or updated:
   - [twq_swift_async_smoke.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_async_smoke.swift)
   - [twq_swift_dispatch_control.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatch_control.swift)
   - [twq_swift_taskgroup_precheck.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_taskgroup_precheck.swift)

## Guest Results

The important guest observations from `/tmp/twq-dev.integration.serial.log`
were:

1. Swift async smoke:
   - status: `ok`
   - meaning: the staged Swift runtime can start an `async` entrypoint under
     the guest kernel/runtime stack.
2. Swift Dispatch control:
   - status: `ok`
   - workload completed: `8/8`
   - sum: `28`
   - counter deltas:
     - `init_count: 10 -> 11`
     - `setup_dispatch_count: 10 -> 11`
     - `reqthreads_count: 165 -> 180`
     - `thread_enter_count: 57 -> 62`
     - `thread_return_count: 58 -> 63`
   - meaning: Swift's `Dispatch` import is using the real TWQ-backed path.
3. Swift `TaskGroup` pre-check:
   - status: `timeout`
   - timeout window: `15s`
   - counter deltas:
     - `init_count: 11 -> 12`
     - `setup_dispatch_count: 11 -> 12`
     - `reqthreads_count: 180 -> 193`
     - `thread_enter_count: 62 -> 67`
     - `thread_return_count: 63 -> 66`
   - meaning: the structured-concurrency workload is also reaching the
     TWQ-backed path, but it is not completing.

## Interpretation

This is the first real Swift boundary:

1. path selection is no longer the issue;
2. the structured-concurrency runtime is making enough progress to initialize
   dispatch-backed workqueue state and run worker entries;
3. the first suspended `TaskGroup` workload still stalls.

That means the current blocker is not "Swift ignores TWQ on FreeBSD." The
blocker is closer to higher-level Swift concurrency behavior on top of the
TWQ-backed dispatch path.

The current host cannot reproduce the staged Swift binaries meaningfully,
because the staged `libdispatch` intentionally traps on syscall `468`, which
does not exist on the stock host kernel. Swift diagnosis for this lane must
therefore stay in the `TWQDEBUG` guest.

## Verification

Completed during this pass:

1. `scripts/swift/prepare-stage.sh`
2. `make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)
3. `TWQ_RUN_VM_INTEGRATION=1 make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)

Current test state:

1. the normal host-side Elixir suite passes;
2. the gated VM integration run now finishes and reports the Swift boundary
   instead of hanging indefinitely;
3. the gated VM integration test remains red because it still expects the
   `TaskGroup` probe to complete successfully.

## Next Step

Do not expand into a broad Swift workload matrix yet.

The next useful work is narrower:

1. isolate whether the failing piece is suspension (`Task.sleep`), general
   `TaskGroup` execution, or some other structured-concurrency primitive;
2. build the smallest additional Swift probes needed to split those cases;
3. only after that should broader M12 Swift workload coverage resume.
