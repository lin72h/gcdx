# M12 Swift Runtime Boundary Progress

## Summary

This pass moved `M12` from "Swift reaches the TWQ path" to a more precise
answer:

1. the stock local FreeBSD Swift 6.3 toolchain passes all current probe entry
   shapes on the host;
2. the staged guest stack under `TWQDEBUG` is context-sensitive instead of
   uniformly broken;
3. the remaining failures are therefore not generic Swift failures and not
   generic TWQ path-selection failures;
4. the later stable guest validation profile is narrower than that first
   reading and is now recorded in
   [m12-swift-validation-profile-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-validation-profile-progress.md);
5. the later focused `dispatchMain()` isolation work is recorded in
   [m12-swift-dispatchmain-isolation-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-dispatchmain-isolation-progress.md).

That is enough to stop treating the whole Swift lane as one unknown blob.

## Host Result

Using the canonical installed toolchain from
[freebsd-swift63-toolchain-reference.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/freebsd-swift63-toolchain-reference.md),
the host passed all of these probe shapes:

1. `async-sleep`
2. `taskgroup`
3. `spawned-sleep`
4. `spawned-yield`
5. `mainactor-sleep`
6. `mainactor-taskgroup`
7. `dispatchmain-sleep`
8. `dispatchmain-taskgroup`
9. `detached-sleep`
10. `detached-taskgroup`

That makes the host-side Swift 6.3 toolchain a useful control case instead of a
suspected root cause.

## Guest Result

The latest staged guest run (`/tmp/twq-dev.m12e.serial.log`) produced this
matrix:

Passing guest probes:

1. `taskgroup-spawned`
2. `dispatch-control`
3. `mainqueue-resume`
4. `mainactor-sleep`
5. `dispatchmain-sleep`
6. `dispatchmain-taskgroup`

Failing guest probes:

1. `async-yield`
2. `taskgroup-immediate`
3. `taskgroup-yield`
4. `async-sleep`
5. `mainactor-taskgroup`
6. `detached-sleep`
7. `detached-taskgroup`
8. `spawned-yield`
9. `spawned-sleep`
10. `taskgroup`

Common traits of the failing shapes:

1. they are not failing at path selection;
2. they still increase `kern.twq.init_count`, `kern.twq.setup_dispatch_count`,
   `kern.twq.reqthreads_count`, and `kern.twq.thread_enter_count`;
3. many of them reach late progress markers, which means the child work often
   finishes and the stall happens during waiter wake, inherited-context
   handling, or final completion propagation.

## Interpretation

The best current reading is:

1. the kernel TWQ path is not the blocker;
2. staged Swift plus staged `libdispatch` plus staged `libthr` has a
   context-sensitive runtime bug in the guest;
3. the bug is not reproduced by the stock local Swift 6.3 toolchain on the
   host;
4. the safest current workload-entry lane for further Swift validation is
   `dispatchMain()`-rooted work, because both `dispatchmain-sleep` and
   `dispatchmain-taskgroup` completed in the latest guest run.

This is still not enough to call `M12` finished, but it is enough to stop
debugging the wrong layer.

## Practical Consequence

The Swift lane should now be split into two categories.

The later stable passing guest gate is recorded separately in
[m12-swift-validation-profile-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-validation-profile-progress.md).

Required validation lane:

1. guest Swift workloads that complete through the TWQ-backed path and move
   `kern.twq.*` counters;
2. at the time of this document, the strongest candidates were the
   `dispatchMain()`-rooted probes;
3. the later stable required gate was tightened further to:
   - `async-smoke`
   - `dispatch-control`
   - `mainqueue-resume`

Diagnostic lane:

1. context-sensitive probe shapes that still fail under the staged guest stack;
2. these remain useful because they describe the current FreeBSD staged-stack
   quality boundary, but they should not be mistaken for proof that Swift never
   works on the TWQ path.

## Next Step

The next high-value move is not another wide probe explosion.

It is:

1. promote the `dispatchMain()`-rooted Swift probes into the main validation
   lane;
2. keep the failing inherited-context probes as diagnostics;
3. only then expand from the `dispatchMain()` lane into broader Swift workload
   coverage.
