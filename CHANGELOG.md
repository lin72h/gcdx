# CHANGELOG

## 2026-04-13

### M13 `ready`-coverage fast path rejected

A targeted `libthr` experiment tried to skip kernel `REQTHREADS` when a lane
already had enough `tbr_ready` workers to cover its current `tbr_pending`
count.

Result:

1. the first clean repeat-only run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115402Z.json`
   improved the C repeat lane to
   `dispatch.main-executor-resume-repeat = +345 / +157 / +154`,
   but moved the Swift repeat lane to
   `swift.dispatchmain-taskhandles-after-repeat = +1533 / +532 / +529`;
2. the traced run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115538Z.serial.log`
   showed the new path only `4` times:
   `addthreads-covered: 4` versus
   `addthreads-begin: 952` and
   `root-queue-poke-slow: 952`;
3. the second clean run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115743Z.json`
   landed at `+316 / +149 / +146` for the C repeat lane and
   `+1424 / +491 / +488` for the Swift repeat lane.

Important finding:

1. this is not the dominant hotspot;
2. the trace proves the fast path barely fires in the real continuation-heavy
   workload shape;
3. the patch was reverted and the staged `libthr` was refreshed back to the
   reverted state;
4. the remaining honest target stays higher in the stack:
   repeated root-queue request generation and cross-queue wake behavior.

### M13 cross-lane transfer handoff verified

The next real M13 churn reduction is now proven in the staged guest, and the
result is more specific than the earlier same-lane win.

Key result:

1. `/usr/src/sys/sys/thrworkq.h`,
   `/usr/src/lib/libthr/thread/thr_workq_kern.h`,
   `/usr/src/sys/kern/kern_thrworkq.c`, and
   `/usr/src/lib/libthr/thread/thr_workq.c` now implement
   `TWQ_OP_THREAD_TRANSFER`, letting a worker move directly from one kernel
   `TWQ` lane to another on cross-lane handoff instead of always paying a full
   `THREAD_RETURN -> THREAD_ENTER` cycle;
2. the first current-branch transfer runs were misleading because the guest was
   not actually exercising the new code at first:
   the kernel had to be rebuilt, and then the staged `libthr` had to be
   refreshed from newly rebuilt `/tmp/twqlibobj/.../*.pico` objects;
3. the decisive traced run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112356Z.serial.log`
   proves the transfer path is live:
   `worker-handoff-transfer` fired `183` times,
   `worker-handoff-enter` fell to `0`, and
   `worker-handoff-fastpath` still fired `85` times for same-lane claims;
4. two clean repeat-only runs at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112557Z.json`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112757Z.json`
   confirm the qualitative result without tracing overhead.

Important findings:

1. the clean post-transfer C repeat lane,
   `dispatch.main-executor-resume-repeat`,
   now sits at `reqthreads +380 / enter +169 / return +166` and
   `+354 / +163 / +160`, which is still roughly the same band as the earlier
   same-lane-only M13 result;
2. the clean post-transfer Swift repeat lane,
   `swift.dispatchmain-taskhandles-after-repeat`,
   moved to `reqthreads +1371 / enter +460 / return +457` and
   `+1500 / +506 / +503`;
3. compared with the earlier same-lane-only M13 result
   (`+1630 / +780 / +777` and `+1863 / +884 / +881`),
   that is a real Swift-side reduction in both worker requests and
   enter/return churn;
4. the current-branch debugging lesson is important enough to keep:
   `scripts/libthr/prepare-stage.sh` relinks from objdir products, so changing
   `/usr/src/lib/libthr/thread/thr_workq.c` alone does not put new behavior
   into the guest until the corresponding `.pico` objects are rebuilt;
5. the honest next M13 target is no longer worker recycling within `libthr`.
   The transfer path closes that question enough to move on. The remaining
   hotspot is request generation across root queues and staged `libdispatch`
   wake policy.

## 2026-04-11

### M13 same-lane handoff fast path verified

The first real post-M12 churn reduction is now proven instead of inferred.

Key result:

1. `scripts/libthr/prepare-stage.sh` now refreshes the staged `libthr` from
   the freshest objdir instead of a stale default path;
2. `/usr/src/lib/libthr/thread/thr_workq.c` now has a same-lane handoff fast
   path that skips a redundant `THREAD_RETURN -> THREAD_ENTER` cycle when a
   worker immediately claims more work in the same kernel bucket;
3. a traced guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125820Z.serial.log`
   proves `worker-handoff-fastpath` is live in the staged guest runtime;
4. two clean repeat-only runs now show materially lower churn than the
   pre-fix baseline on the same workloads.

Important findings:

1. the pre-fix repeat-only mean for
   `dispatch.main-executor-resume-repeat` was
   `reqthreads +546 / enter +183 / return +180`;
2. the first two real post-fix runs moved that C lane to
   `+379 / +172 / +169` and `+320 / +150 / +147`;
3. the pre-fix repeat-only mean for
   `swift.dispatchmain-taskhandles-after-repeat` was
   `reqthreads +2659.5 / enter +887.5 / return +884.5`;
4. the first two real post-fix runs moved that Swift lane to
   `+1630 / +780 / +777` and `+1863 / +884 / +881`;
5. the traced run shows why the Swift win is partial rather than final:
   `worker-handoff-fastpath` fired `30/30` same-lane claims in the C section,
   but only `63` times in the Swift section where `153` more handoffs still
   crossed lanes and required the slower re-enter path.

## 2026-04-10

### M13 repeat-lane telemetry added

The repeat-heavy M13 hotspots now expose round-by-round `TWQ` counter series
instead of only whole-run before/after deltas.

Key result:

1. `csrc/twq_dispatch_probe.c` now emits `round-start-counters` and
   `round-ok-counters` for the C repeat lanes;
2. `swiftsrc/twq_swift_dispatchmain_taskhandles_after_repeat.swift` now emits
   matching round counter events for the staged Swift repeat lane;
3. `scripts/benchmarks/extract-m13-baseline.py` now preserves those series
   under `round_metrics` in the extracted benchmark JSON;
4. a focused guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T123532Z.json`
   shows the repeat hotspot is steady-state churn, not just startup noise.

Important findings:

1. `dispatch.main-executor-resume-repeat` keeps a stable per-round request
   pattern with `reqthreads_delta` mean `7.55`, first-half mean `7.66`,
   second-half mean `7.44`;
2. the same C lane keeps `bucket_total` pinned at `5`, so worker-pool
   formation is already complete while the requests continue;
3. `swift.dispatchmain-taskhandles-after-repeat` remains much hotter with
   `reqthreads_delta` mean `41.73`, first-half mean `44.91`,
   second-half mean `38.56`;
4. this makes the next honest optimization target clearer:
   staged `libdispatch` request generation should be tuned before kernel
   admission or `libthr` warm-pool policy.

### M13 baseline lane started

The repo now has a real post-M12 performance baseline instead of a vague
benchmark intention.

Key result:

1. added a reproducible host-side benchmark runner in
   `scripts/benchmarks/run-m13-baseline.sh`;
2. added a structured serial-log extractor in
   `scripts/benchmarks/extract-m13-baseline.py`;
3. added staged pthread header refresh support in
   `scripts/libthr/prepare-headers.sh`;
4. captured the first compact baseline in
   `benchmarks/baselines/m13-initial.json`;
5. confirmed all `6` selected dispatch modes and all `3` selected Swift modes
   completed with `ok` status in the first baseline run.

Important findings:

1. the warm-pool reuse lanes are stable:
   `dispatch.burst-reuse` and `dispatch.timeout-gap` both settle at `4` idle
   workers with no post-round active workers;
2. pressure behavior is still visible:
   `dispatch.pressure` holds `default_max_inflight` to `3`, and
   `dispatch.sustained` records `641` block/unblock observations;
3. the next honest optimization target is worker-request churn:
   `dispatch.main-executor-resume-repeat` still drives
   `reqthreads_count +564`, while
   `swift.dispatchmain-taskhandles-after-repeat` drives
   `reqthreads_count +2799`.

This moves `M13` from `next` to `in_progress`. The project now has a concrete
baseline artifact it can optimize against instead of relying on intuition.

### M12 closed by kernel TWQ lane split

The repo now records the actual fix for the strongest staged Swift correctness
gap.

Key result:

1. the old repeated delayed-child Swift failure was not ultimately a staged
   `libdispatch` queue-redrive bug;
2. the real root cause was kernel-side `TWQ` accounting that collapsed
   constrained and overcommit workers into the same QoS bucket;
3. internal `TWQ` accounting is now split by lane
   (`QoS x {constrained, overcommit}`) in
   `/usr/src/sys/kern/kern_thrworkq.c`, while the public sysctl surface
   remains bucket-aggregated;
4. the previously failing staged probe,
   `dispatchmain-taskhandles-after-repeat-hooks`, now completes all `64`
   rounds on the full staged lane;
5. the broader staged Swift `full` profile now completes end-to-end in the
   guest with no timeout results, aside from the already-known invalid
   `customdispatch + stock libthr` control lanes.

Important evidence:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-swiftonly-lanesplit.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-swift-full-post-lanesplit.serial.log`

This changes the honest M12 story. Earlier staged-`libdispatch` tracing was
useful narrowing work, but it described the symptom boundary rather than the
root cause. The Tier 1 Swift delayed-resume correctness gap is now closed for
the current validation matrix.

### Staged libdispatch lane-redrive boundary corrected

The repo now records a more accurate M12 boundary after adding staged
`libdispatch` lane-drain and invoke-finish tracing on the failing Swift lane.

Key result:

1. the failing queue is the real `Swift global concurrent queue`, not just the
   earlier pure-C `twq.swift.executor` control;
2. on that queue, the first delayed-resume wave reaches:
   - `lane-invoke2-entry`
   - `lane-drain-entry`
   - `lane-drain-exit`
   - normal callouts for the first resumed jobs;
3. later child resumptions still reach staged `libdispatch`
   `continuation_async` on the same queue;
4. after those later enqueues, the queue no longer shows a second
   `lane-invoke2-entry` / `lane-drain-entry` before timeout;
5. a follow-up pass also showed no matching `invoke-finish-*` traces for that
   failing queue.

That moves the honest live boundary back downward. The remaining staged M12
failure is not best described as a Swift future/waiter bug above raw C
dispatch. It is more accurately a staged `libdispatch` queue redrive /
invoke-finish / reenqueue failure on the shared `Swift global concurrent
queue` under the delayed-child Swift workload.

### Plain-C timer-hop repeat boundary tightened

The repo now records a stricter C-side control for the remaining M12 bug:

1. a new `main-executor-resume-repeat` dispatch mode was added;
2. it drives `64` rounds of delayed timer callbacks that each re-enqueue a
   distinct continuation onto the executor queue;
3. that new mode completes successfully on the full staged TWQ lane with
   `512/512` resumed continuations.

That means the remaining staged failure is no longer honestly describable as
"timer queue callback re-enqueues work onto the executor queue and custom
libdispatch drops it" in generic C. That rules out the simple timer-hop theory,
but later lane tracing showed the remaining live boundary is still inside
staged `libdispatch`, not above it in Swift future/waiter logic.

### Repeated delayed-child control matrix tightened again

The repo now records the strongest M12 isolation result so far:

1. the repeated `dispatchmain-taskhandles-after-repeat` stress probe still
   times out on the full staged TWQ lane;
2. the exact same repeated stress probe completes all `64` rounds on the
   `stock libdispatch + custom libthr` guest control;
3. the `custom libdispatch + stock libthr` lane is not a valid runtime
   comparison because staged `libdispatch` expects custom-`libthr` symbols
   such as `qos_class_main`.

That moves the honest critical-path blame off kernel `TWQ` worker supply and
off the `libthr` bridge for this bug class. The remaining divergence is now
firmly in the staged `libdispatch` lane.

### Staged repeat failure narrowed past enqueue

The repo now records a tighter staged M12 failure boundary:

1. in the failing repeated-stress run, late child resumptions still reach
   Swift `enqueueGlobal`;
2. they still pass through `dispatch_async_f`;
3. they still enter staged `libdispatch` `continuation_async` on the
   `Swift global concurrent queue`;
4. they stop before the staged `libdispatch` callout / invoke path runs them.

That means the live fault line is no longer "Swift did not request resume"
and no longer "the queue-shape hypothesis". It is now staged `libdispatch`
queue drain / wakeup after enqueue on the full TWQ lane.

### Swift executor queue-shape hypothesis narrowed

The repo now records a more precise M12 result:

1. Swift 6.3's non-Apple `DispatchGlobalExecutor.cpp` really does create
   per-priority concurrent queues and immediately call
   `dispatch_queue_set_width(queue, -3)`;
2. the C dispatch probe now splits that queue shape into four variants:
   `executor-after`, `executor-after-settled`,
   `executor-after-default-width`, and `executor-after-sync-width`;
3. a new full-profile guest run showed all four variants completing
   successfully on the staged TWQ lane.

That means the simple "fresh queue width-narrowing race" theory is no longer a
sufficient explanation for the remaining Swift delayed-child timeout.

The next M12 focus therefore shifts upward to the staged Swift/dispatch
boundary:

1. delayed Swift job re-enqueue;
2. `dispatch_async_swift_job` or its fallback path;
3. parent-await / child-resume behavior after enqueue.

### Swift delayed-child control matrix tightened

The repo now records a stronger M12 isolation result:

1. the staged `dispatchmain-taskhandles-after` probe still times out on the
   TWQ-backed custom-`libdispatch` lane;
2. the same probe completes on both stock-dispatch guest controls:
   stock `libthr` and custom `libthr`;
3. on the failing staged lane, every delayed child still reaches
   `child-after-await-*`, but the parent stalls after `parent-awaiting-1`.

That moves the remaining delayed-child bug away from generic Swift future
completion and away from the custom `libthr` bridge. The honest live boundary
is now staged workqueue-enabled `libdispatch`, most likely in the redrive path
that should resume the waiting parent task after delayed child completion.

### GLM review response captured

The repo now records the immediate execution response to the external GLM
architecture review.

The main change is a shift in the next-step judgment:

1. the remaining staged delayed-child boundary is now treated primarily as a
   Layer B staged-`libdispatch` correctness problem;
2. the next milestone is no longer "more Swift narrowing";
3. the next milestone is now a C-level staged-`libdispatch` executor-after /
   delayed-child fix, while the current Swift probe set is held steady as a
   validation and regression lane.

### Project naming standardized

The repo now treats `GCDX` as the explicit project name for the current
FreeBSD-based kernel-integrated dispatch effort.

The terminology map is now:

1. `libdispatch` = portable Tier 0 baseline;
2. `GCDX` = this project, the kernel-integrated Tier 1 lane;
3. `GCD` = the platform-complete macOS reference lane.

### Swift 6.3 stock-dispatch boundary corrected

The repo now records an important Swift validation correction:

1. the stock Swift 6.3 toolchain `libdispatch.so` does not reference
   `_pthread_workqueue_*` symbols at all;
2. the staged custom `libdispatch.so` does;
3. the stock-dispatch plus custom-`libthr` guest control completes a delayed
   child-completion probe successfully, but shows zero TWQ counter deltas
   during that probe window.

This means the stock Swift 6.3 dispatch lane is a useful runtime control, but
it is not a TWQ-backed control lane. Real Swift/TWQ validation still depends
on the staged custom `libdispatch` lane.

### Swift delayed-child boundary narrowed again

The repo now has a stronger staged Swift diagnosis:

1. a new pure-C `worker-after-group` dispatch mode succeeds on the staged TWQ
   lane;
2. a new Swift `dispatchmain-taskhandles-after` probe still times out there,
   while passing on the stock host Swift 6.3 lane.

This means the remaining problem is no longer best described as a
`TaskGroup`-only bug. The tighter boundary is:

1. multiple delayed Swift child-task resumptions awaited by a parent async
   context on the staged custom-`libdispatch` lane.

### Current macOS-gap reading

The repo now carries an explicit estimate for how close the current port is to
native macOS `libdispatch` behavior:

1. roughly `70-80%` for the kernel-backed workqueue behavior that matters most
   to this project;
2. roughly `45-55%` for broader native-macOS `libdispatch` parity overall.

### Why the estimate is already meaningfully high

The following are already real and working:

1. kernel `TWQ` support in `/usr/src`;
2. real pressure-aware admission and narrowing;
3. real backpressure from the kernel workqueue path into staged
   `libdispatch`;
4. a real `libthr` pthread_workqueue bridge;
5. repeatable `bhyve` guest validation;
6. a stable Swift validation profile that proves the staged stack is not just
   a synthetic C-only demo.

### Why the estimate is not higher yet

The following important gaps remain:

1. no direct kevent-workqueue delivery;
2. no workloops;
3. no cooperative-pool semantics;
4. worker lifecycle is still not kernel-owned the way it is on macOS;
5. no turnstile-style priority inheritance for this path;
6. no structured macOS-side comparison lane has been run yet;
7. one staged custom-`libdispatch` bug is still open:
   delayed `TaskGroup` child completion on the TWQ lane.

### Current position

The project is already past the stage where it can be honestly called a shim or
compatibility-only dispatch story. It has crossed the boundary into a real
kernel-backed dispatch implementation on FreeBSD.

The remaining work is no longer "make pthread_workqueue exist at all." It is:

1. fix the remaining staged custom-`libdispatch` delayed child-completion bug;
2. expand Swift validation without lying about what is already stable;
3. build the macOS comparison lane;
4. decide later which deeper macOS features are worth adopting naturally on
   FreeBSD.
