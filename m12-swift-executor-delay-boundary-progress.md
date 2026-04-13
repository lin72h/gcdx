# M12 Swift Executor Delay Boundary Progress

## Closeout

This document now serves as the narrowing history for a boundary that has been
closed.

Final outcome:

1. the old staged Swift delayed-child failure was not ultimately a staged
   `libdispatch` queue-redrive root cause;
2. the real root cause was kernel-side `TWQ` accounting that collapsed
   constrained and overcommit workers into the same QoS bucket;
3. internal accounting is now split by lane
   (`QoS x {constrained, overcommit}`) in
   `/usr/src/sys/kern/kern_thrworkq.c`, while the public
   `kern.twq.bucket_*` sysctls remain bucket-aggregated;
4. the previously failing staged probe,
   `dispatchmain-taskhandles-after-repeat-hooks`, now completes all `64`
   rounds successfully:
   `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-swiftonly-lanesplit.serial.log`;
5. the broader staged Swift `full` profile now completes end-to-end too:
   `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-swift-full-post-lanesplit.serial.log`;
6. the earlier staged `libdispatch` redrive / invoke-finish suspicion was a
   useful symptom boundary, but not the final fault.

The history below remains valuable because it shows how the false boundary was
isolated and why the eventual fix had to land lower in the stack.

## Historical Narrowing State

This pass started with the earlier "`executor queue width-setup`" suspicion and
ended by ruling that theory out as a complete explanation.

The historical boundary at that stage was:

1. delayed resume is not generically broken on the full staged TWQ lane;
2. `dispatchmain-spawnwait-after` succeeds on the full staged TWQ lane;
3. `dispatchmain-taskgroup-after` remains capable of timing out on the full
   staged TWQ lane;
4. `dispatchmain-taskhandles-after` also times out on the full staged TWQ
   lane;
5. the same `dispatchmain-taskhandles-after` binary succeeds on both
   stock-dispatch guest controls:
   stock `libthr` and custom `libthr`;
6. the same `dispatchmain-taskgroup-after` binary succeeds on both
   stock-dispatch guest controls:
   stock `libthr` and custom `libthr`;
7. on the failing staged `dispatchmain-taskhandles-after` path, all delayed
   children now visibly reach `child-after-await-*`, but the parent stalls
   after `parent-awaiting-1`;
8. the Swift 6.3 non-Apple global executor really does create per-priority
   concurrent queues and immediately call
   `dispatch_queue_set_width(queue, DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS)`;
9. all four pure-C delayed-dispatch queue shapes now pass in the guest:
   - `executor-after`
   - `executor-after-settled`
   - `executor-after-default-width`
   - `executor-after-sync-width`
10. the remaining staged Swift boundary is therefore not custom `libthr`, not
    generic timers, not `Task.sleep` specifically, not the bare queue-width
    narrowing shape by itself, and not generic Swift future completion by
    itself.
11. the repeated `dispatchmain-taskhandles-after-repeat` stress probe still
    times out on the full staged TWQ lane;
12. the exact same repeated stress probe completes all `64` rounds on the
    stock-dispatch plus custom-`libthr` guest control;
13. on the failing staged repeat lane, late child resumptions visibly reach:
    - Swift `enqueueGlobal`
    - `dispatch_async_f`
    - staged `libdispatch` `continuation_async`
14. those same late child resumptions then stop before the staged
    `libdispatch` callout/invoke path runs them on the Swift global
    concurrent queue;
15. a new stricter pure-C delayed-resume stress mode,
    `main-executor-resume-repeat`, now also passes on the full staged TWQ
    lane, even though it uses the same timer-queue to executor-queue hop that
    the failing Swift probe relies on;
16. staged `libdispatch` lane tracing on the failing Swift lane now shows the
    real `Swift global concurrent queue` entering `lane-invoke2` and
    `lane-drain` once for the first delayed-resume wave;
17. later child resumptions still enqueue successfully onto that same queue,
    but no second `lane-invoke2` / `lane-drain` entry appears for it before
    timeout;
18. a follow-up invoke-finish trace pass showed no matching
    `invoke-finish-*` events for that failing queue.

The current best description is:

the remaining staged failure is still inside staged `libdispatch`, but it is
now narrowed past generic timer-hop and past the simple enqueue boundary. Late
Swift child resumptions still reach staged `libdispatch`
`continuation_async` on the shared `Swift global concurrent queue`, yet that
queue does not get redriven a second time before timeout. The live seam is now
the queue redrive / invoke-finish / reenqueue path on that shared concurrent
queue, rather than the Swift future / waiter layer above it, kernel `TWQ`
worker supply, or the `libthr` bridge.

## What Changed

Two new Swift probes were added:

1. [twq_swift_dispatchmain_spawnwait_after.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_spawnwait_after.swift)
2. [twq_swift_dispatchmain_taskgroup_after.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_taskgroup_after.swift)

They use `DispatchQueue.global(...).asyncAfter(...)` to resume suspended work
instead of `Task.sleep`.

The Swift staging and guest scripts were extended accordingly:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)

Two extra C dispatch diagnostics were added:

3. `executor-after-default-width` and `executor-after-sync-width` in
   [twq_dispatch_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_dispatch_probe.c)
4. `executor-after-settled` in
   [twq_dispatch_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_dispatch_probe.c)
5. `main-executor-resume-repeat` in
   [twq_dispatch_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_dispatch_probe.c)

These modes split the queue setup into:

1. Swift-style async logical-width narrowing (`executor-after`);
2. no explicit width narrowing (`executor-after-default-width`);
3. synchronous positive-width narrowing (`executor-after-sync-width`);
4. Swift-style async narrowing plus a forced settle barrier
   (`executor-after-settled`).

The point of the split is to distinguish:

1. delayed work on a fresh custom concurrent queue in general;
2. the specific `dispatch_queue_set_width(..., -3)` path Swift uses on
   non-Apple platforms;
3. the possibility that the width-adjustment transition itself is the bug.

The local Swift runtime source confirms that the non-Apple global executor
really does use that queue shape:

1. `/Users/me/wip-rnx/nx-/swift-source-vx-modified/workspace/swift/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp`

Important details from that file:

1. `getGlobalQueue()` creates a concurrent queue per priority;
2. it then calls `dispatch_queue_set_width(newQueue, -3)`;
3. delayed jobs use `dispatch_after_f()` on `getTimerQueue(priority)`, which
   routes back to those same global executor queues on this lane.

## Host Controls

Both new Swift probes complete on the canonical installed Swift 6.3 toolchain:

1. `twq-swift-dispatchmain-spawnwait-after`
2. `twq-swift-dispatchmain-taskgroup-after`

That keeps the new failure surface anchored to the staged guest stack rather
than the local Swift 6.3 toolchain itself.

## Guest Results

Relevant serial logs:

1. `/tmp/twq-dev.m12o.serial.log`
2. `/tmp/twq-dev.m12p.serial.log`
3. `/tmp/twq-dev.m12q.serial.log`
4. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-controls.serial.log`
5. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-libdispatch-async.serial.log`
6. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-stockdispatch-customthr.serial.log`
7. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-customdispatch-stockthr.serial.log`
8. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-main-executor-resume-repeat.serial.log`
9. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-libdispatch-lanedrain.serial.log`
10. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-invokefinish.serial.log`

### Full TWQ lane

Observed:

1. `dispatchmain-spawnwait-after`: `ok`
2. `dispatchmain-taskhandles-after`: `timeout`
3. `dispatchmain-taskgroup-after`: still capable of timing out on the staged
   lane

Important shape:

1. in the staged `dispatchmain-taskhandles-after` run, every child now reaches
   both `child-after-delay-*` and `child-after-await-*`;
2. the parent reaches `parent-after-await-0` and then stalls at
   `parent-awaiting-1`;
3. timeout diagnostics still show the same waiter topology:
   `nanslp`, `kqread`, `sigsusp`, and `uwait`.

That means this is not a simple "timers never fire" failure and not a child
completion failure.

### Repeated delayed-child stress

Observed:

1. `dispatchmain-taskhandles-after-repeat-hooks`: `timeout` on the full staged
   TWQ lane;
2. `dispatchmain-taskhandles-after-repeat-stockdispatch-customthr`: `ok`,
   completing all `64` rounds on the same guest and kernel;
3. `dispatchmain-taskhandles-after-repeat-customdispatch-stockthr` is not a
   valid runtime lane because staged `libdispatch` expects custom-`libthr`
   symbols such as `qos_class_main`.

Important shape from the hook and `libdispatch` trace run:

1. the repeated failure does not stop at Swift `enqueueGlobal`;
2. late child jobs also reach `dispatch_async_f` and staged
   `libdispatch`'s `continuation_async` on the `Swift global concurrent queue`;
3. after `parent-awaiting` advances to task `2`, multiple later child
   resumptions still enqueue successfully, but none of those queued jobs
   reach the staged `libdispatch` callout/invoke path;
4. the first two awaited handles can complete, so the queue is not uniformly
   dead from the beginning;
5. the failure is therefore in staged `libdispatch` after enqueue, during
   queue drain / wake / root-redrive, not in the Swift continuation-resume
   request itself;
6. lane tracing on the real `Swift global concurrent queue` tightens that
   further:
   - the first delayed-resume wave reaches `lane-invoke2-entry`,
     `lane-drain-entry`, `lane-drain-exit`, and normal callouts;
   - later child resumptions still hit `continuation_async` on the same
     queue;
   - no second `lane-invoke2-entry` / `lane-drain-entry` appears for that
     queue before timeout;
7. a follow-up invoke-finish trace run then showed no `invoke-finish-*`
   events for the failing queue at all, even though control queues such as
   `twq.swift.executor` still produced those traces.

### Stock-dispatch guest controls

Observed in the same guest:

1. `dispatchmain-taskhandles-after-stockdispatch`: `ok`
2. `dispatchmain-taskhandles-after-stockdispatch-customthr`: `ok`
3. `dispatchmain-taskgroup-after-stockdispatch`: `ok`
4. `dispatchmain-taskgroup-after-stockdispatch-customthr`: `ok`
5. `dispatchmain-taskhandles-after-repeat-stockdispatch-customthr`: `ok`

This keeps the blame off custom `libthr` and off the generic Swift runtime
future-wait path. The same binary and the same guest complete once the
dispatch runtime is swapped back to stock.

## C Dispatch Controls

The C dispatch probe now provides useful surrounding controls for delayed
dispatch:

1. `after`: passes
2. `main-after`: passes
3. `executor-after`: passes in the latest full guest diagnostic run
4. `executor-after-settled`: passes there too
5. `executor-after-default-width`: passes
6. `executor-after-sync-width`: passes
7. `main-executor-after-repeat`: passes
8. `main-executor-resume-repeat`: passes

The new result matters more than the older intermittent `executor-after`
observation:

1. the Swift-style async width-narrowing queue shape is real;
2. but raw delayed C dispatch on that shape is currently healthy in the guest;
3. removing the width change or making it synchronous does not change the C
   outcome;
4. therefore the queue-width transition is not, by itself, a sufficient
   explanation for the remaining staged Swift timeout;
5. even a repeated timer callback that re-enqueues a distinct continuation
   onto the executor queue for each child can complete all `64` rounds on the
   staged TWQ lane in plain C.

## Interpretation

The old boundary is now too broad:

1. it is not accurate anymore to say the remaining problem is just
   `Task.sleep` on the TWQ path;
2. delayed dispatch wakeups can succeed on the full staged TWQ lane;
3. the failing shape is narrower and more structured:
   delayed Swift child completion with a parent still awaiting on the staged
   custom `libdispatch` lane.

That moves the likely fault line back downward into staged `libdispatch`.

The remaining suspect area is now closer to:

1. the shared concurrent-lane redrive path after the first successful
   `lane-drain-exit`;
2. the handoff between `lane-invoke2` return and
   `_dispatch_queue_invoke_finish()` for this queue class;
3. queue state transitions that should re-enqueue or re-wake
   `Swift global concurrent queue` after later `continuation_async` events;
4. root-queue to lane redrive only insofar as the root queue successfully
   pokes workers but the target lane is not re-entered;
5. staged `dispatchMain()` only indirectly, because the strongest visible gap
   is on the shared concurrent queue, not on the main queue itself.

It is no longer honest to treat plain executor-queue width setup or the Swift
future/waiter layer as the strongest implementation lead.

## Verification

Completed in this pass:

1. `zsh -n` on
   [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. `zsh -n` on
   [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
3. `./scripts/swift/prepare-stage.sh`
4. host runs of:
   - `twq-swift-dispatchmain-spawnwait-after`
   - `twq-swift-dispatchmain-taskgroup-after`
5. repeated filtered guest runs covering:
   - `dispatchmain-spawnwait-after`
   - `dispatchmain-taskhandles-after`
   - `dispatchmain-taskhandles-after-stockdispatch`
   - `dispatchmain-taskhandles-after-stockdispatch-customthr`
   - `dispatchmain-taskgroup-after`
   - `dispatchmain-taskgroup-after-stockdispatch`
   - `dispatchmain-taskgroup-after-stockdispatch-customthr`
   - `main-executor-resume-repeat`
6. local Swift runtime source inspection in:
   - `/Users/me/wip-rnx/nx-/swift-source-vx-modified/workspace/swift/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp`
7. custom dispatch-probe rebuild after adding:
   - `executor-after-default-width`
   - `executor-after-sync-width`
   - `executor-after-settled`
8. a full-profile guest run capturing all four executor-after queue shapes in
   `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev.serial.log`
9. a preloadable Swift concurrency hook library in
   [twq_swift_concurrency_hooks.cpp](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_swift_concurrency_hooks.cpp)
   that traces Swift enqueue hooks and `dispatch_async_f` handoff
10. staged `libdispatch` tracing at:
   - `continuation_async`
   - Swift global queue callout
11. a focused failing guest run captured in:
   `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-libdispatch-async.serial.log`
12. a new repeated-stress guest control mode:
   `dispatchmain-taskhandles-after-repeat-stockdispatch-customthr`
13. a matching guest control run showing that stock dispatch plus custom
   `libthr` completes all `64` rounds in:
   `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-stockdispatch-customthr.serial.log`
14. staged `libdispatch` rebuild after adding lane-drain tracepoints in
    `swift-corelibs-libdispatch/src/queue.c`
15. a focused failing guest run captured in:
    `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-libdispatch-lanedrain.serial.log`
16. staged `libdispatch` rebuild after adding invoke-finish tracepoints in
    `swift-corelibs-libdispatch/src/queue.c`
17. a second focused failing guest run captured in:
    `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-invokefinish.serial.log`
18. `make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)

## Next Step

The next useful local step is not another broad Swift matrix.

The focus should now move down one layer into staged `libdispatch` queue
redrive:

1. instrument the handoff below `lane-invoke2`, especially the path that
   should flow into `_dispatch_queue_invoke_finish()` or an equivalent finish
   path for the shared concurrent queue;
2. determine whether the failing `Swift global concurrent queue`:
   - returns normally from `lane_invoke2` but skips finish / reenqueue;
   - reaches finish but decides not to reenqueue;
   - or bypasses the expected finish path entirely;
3. compare that failing shared queue against the healthy control queue
   `twq.swift.executor`, which still produces normal finish traces;
4. only return to broader Swift-runtime theory if staged `libdispatch`
   evidence stops moving.
