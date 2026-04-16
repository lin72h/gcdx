# CHANGELOG

## 2026-04-16

### M13 DTrace lane now identifies default-overcommit traffic safely

The root-push classifier boundary has been made usable instead of just
documented.

What changed:

1. `scripts/bhyve/stage-guest.sh` now runs DTrace against the actual Swift or
   C probe binary instead of tracing `/usr/bin/env`;
2. staged `libdispatch` now has a safe pre-publish counter for one narrow
   case: pushed object pointer equals `_dispatch_main_q`;
3. that counter deliberately avoids `dx_metatype()` / `dx_type()` and therefore
   does not reintroduce the post-publish crash class;
4. `scripts/benchmarks/extract-m13-baseline.py` now preserves
   `[libdispatch-twq-counters]` dumps in schema version `2`;
5. `scripts/benchmarks/summarize-m13-baseline.py` gives a compact summary of
   `kern.twq.*` deltas plus the high-value libdispatch root counters;
6. `scripts/benchmarks/compare-m13-baselines.py` provides the first coarse
   drift-tolerant regression gate for common benchmark modes.

What the guest runs proved:

1. the full Swift repeat lane completed with counters enabled at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.serial.log`;
2. the extracted baseline
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json`
   reports `reqthreads +1058 / enter +343 / return +340`;
3. the counter dump shows
   `root_push_empty_default_overcommit=186` and
   `root_push_mainq_default_overcommit=186`;
4. the fresh DTrace sample
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-dtrace-push-vtable-20260416T042209Z.serial.log`
   maps default-overcommit pushes primarily to
   `__OS_dispatch_queue_main_vtable`.

Current consequence:

1. the remaining default-overcommit pressure is main-queue handoff traffic;
2. that is compatible with the macOS-source model, so it should not be
   suppressed blindly;
3. the next decision needs rate/coalescing evidence, ideally from the M14
   macOS comparison lane.

### M13 push-path classification moved to DTrace after unsafe hot-path attempt

The next `M13` diagnostic pass confirmed an important instrumentation boundary:
root-push object classification must not dereference the pushed object after it
has been published to the MPSC root queue.

What changed:

1. the unsafe in-process overcommit push-kind classifier was reverted from
   staged `libdispatch`;
2. the retained M13 behavior changes remain intact:
   one-shot `dispatch_after` source repoke suppression and same-target
   `ASYNC_REDIRECT` suppression for `used_width >= 3`;
3. `scripts/dtrace/` now contains focused FreeBSD DTrace scripts for root
   push/poke/drain tracing, vtable-pointer classification at function entry,
   and root queue aggregate summaries;
4. `scripts/bhyve/stage-guest.sh` now stages those diagnostics into the guest
   under `/root/twq-dtrace`, controlled by `TWQ_DTRACE_SCRIPT_DIR`.

What the guest run proved:

1. the crash was isolated to the unsafe classifier, not to the retained M13
   behavior changes;
2. the focused Swift repeat run
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260416T024756Z.json`
   completed all `64` rounds after the revert;
3. that same run landed at
   `swift.dispatchmain-taskhandles-after-repeat = +969 / +317 / +314`;
4. its counter dump still shows the remaining seam as overcommit
   `empty->poke-slow` ingress:
   `root_push_empty_default_overcommit=164`,
   `root_poke_slow_default_overcommit=165`,
   and only
   `root_repoke_default_overcommit=1`.

Current consequence:

1. further push-population classification should use DTrace at
   `_dispatch_root_queue_push:entry`, before `os_mpsc_push_list()` publishes
   the object;
2. permanent in-process counters may be reintroduced only if they classify
   before publish or on the drain side where ownership is clear;
3. `hwpmc` remains a later cost-attribution tool, not the tool for pointer
   safety or queue-semantics debugging.

### M13 `dispatch_after` source suppression becomes the first durable root-redrive win

The next real `M13` movement stayed inside staged `libdispatch`, but it
stopped trying to tune root redrive in the abstract.

What changed:

1. `_dispatch_root_queue_drain_one()` now skips the pre-invoke
   `drain-one-repoke` only when the current head item is a one-shot
   `dispatch_after` timer source on the non-overcommit default root;
2. the earlier generic “queue-ish head” suppression experiment was removed;
   it never fired in the guest and was the wrong seam.

What the guest runs proved:

1. the first clean proof run,
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.json`,
   kept both repeat lanes correct while improving
   `dispatch.main-executor-resume-repeat` from
   `+402 / +177 / +174` to
   `+324 / +153 / +150`;
2. that same run improved
   `swift.dispatchmain-taskhandles-after-repeat` from
   `+1323 / +422 / +419` to
   `+1234 / +408 / +405`;
3. the Swift counter dump from
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.serial.log`
   shows the mechanism directly:
   `root_repoke_default=0`,
   `root_repoke_drain_one_default=0`,
   and
   `root_repoke_suppressed_after_source_default=363`.

Current consequence:

1. the dominant Swift repeat seam is no longer generic default-root repoke;
2. the new retained optimization is source-specific and evidence-backed;
3. the next `M13` question becomes “what remains after source repokes are
   gone?” not “should we still suppress source repokes?”

### M13 remaining C repeat churn is now pinned to default-root `ASYNC_REDIRECT`

The follow-up pass after source suppression was measurement-only:
split the remaining default-root continuation tail by subtype.

What changed:

1. staged `libdispatch` root counters now distinguish continuation repokes by
   subtype, including plain user continuations versus `ASYNC_REDIRECT`.

What the guest run proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.json`
   kept the new source suppression result:
   `dispatch.main-executor-resume-repeat` held at
   `+329 / +153 / +150`,
   while
   `swift.dispatchmain-taskhandles-after-repeat` improved again to
   `+1137 / +386 / +383`;
2. the C counter dump from
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.serial.log`
   now shows the remaining default-root repoke makeup exactly:
   `root_repoke_suppressed_after_source_default=512`,
   `root_repoke_drain_one_kind_default_continuation=443`,
   `root_repoke_drain_one_kind_default_continuation_async_redirect=443`,
   and
   `root_repoke_drain_one_kind_default_lane=55`;
3. the Swift lane in the same run still shows
   `root_repoke_default=0` with
   `root_repoke_suppressed_after_source_default=372`,
   so the retained source suppression still behaves as intended.

Current consequence:

1. the next honest `M13` target is the default-root `ASYNC_REDIRECT`
   continuation path on the C repeat lane;
2. generic continuation suppression would be the wrong next move, because the
   remaining continuation tail is already specific enough to target directly.

### M13 root-counter instrumentation isolates the live repeat seam

The next `M13` step stayed diagnostic, but it materially changed the
optimization target.

What changed:

1. staged `libdispatch` now has low-overhead per-process counters for the
   repeat-lane investigation, covering both the suspected concurrent-lane
   redirect path and the root queue redrive path;
2. `scripts/bhyve/stage-guest.sh` already stages
   `LIBDISPATCH_TWQ_COUNTERS`, so the guest benchmark lane can run those
   counters without enabling the heavier `dprintf` trace surfaces.

What the guest runs proved:

1. the queue-focused counter run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T130059Z.serial.log`
   showed
   `concurrent_push_redirect=0`,
   `concurrent_push_fallback=0`,
   `async_redirect_invoke_entry=0`,
   `async_redirect_invoke_exit=0`,
   `lane_push_wakeup=0`, and
   `lane_push_no_wake=0`,
   so the remaining repeat churn is not flowing through the suspected
   concurrent-lane redirect seam;
2. the root-counter run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T131214Z.serial.log`
   isolated the real hot path instead:
   the C repeat lane completed at
   `reqthreads +385 / enter +170 / return +167`
   with
   `root_push_append_default=973` and
   `root_repoke_drain_one_default=973`,
   while the Swift repeat lane completed at
   `reqthreads +1401 / enter +463 / return +460`
   with
   `root_push_append_default=381` and
   `root_repoke_drain_one_default=381`;
3. both runs showed zero `contended-wait` and `worker-timeout` repokes, which
   means the redrive is coming from the default-root next-visible path in
   `_dispatch_root_queue_drain_one()`, not from broader pool contention or idle
   timeout recycling;
4. Swift still adds a separate one-shot default-overcommit ingress
   (`root_push_empty_default_overcommit=208` in the clean run), but not an
   overcommit repoke loop.

Current consequence:

1. the active `M13` target is now root `drain-one-repoke` coalescing or
   equivalent next-visible handoff on the default root;
2. concurrent-lane redirect tuning is demoted from “active suspect” to
   “ruled out for this repeat lane”;
3. the earlier `cleanup2 -> overcommit root` handoff remains a reference seam,
   but it is no longer the best first place to optimize.

## 2026-04-15

### M13 `libthr`-only trace confirms the remaining churn is wake-dominant

The next useful `M13` refinement was diagnostic again, but this time it
changed the layer we should optimize next.

Key result:

1. `scripts/bhyve/stage-guest.sh` now supports split guest trace controls:
   `TWQ_LIBPTHREAD_TRACE`,
   `TWQ_LIBDISPATCH_MAINQUEUE_TRACE`, and
   `TWQ_LIBDISPATCH_ROOT_TRACE`;
2. the older `TWQ_SWIFT_RUNTIME_TRACE` compatibility path still works, but it
   is no longer the only way to enable `LIBPTHREAD_TWQ_TRACE`;
3. a new repeat-only guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.serial.log`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.json`
   completed successfully under `libthr`-only tracing, avoiding the
   `rc=139` failures seen with the broader bundled trace path.

Important findings:

1. the traced C repeat lane still completed with
   `reqthreads +230 / enter +110 / return +107`
   and round-level `reqthreads_delta` mean `3.484`;
2. the traced Swift repeat lane also completed with
   `reqthreads +657 / enter +189 / return +186`
   and round-level `reqthreads_delta` mean `10.156`;
3. the more important signal is the wake/spawn mix from
   `addthreads-ready` events:
   dispatch showed `118` wake-only events versus `5` spawn-only events,
   while Swift showed `456` wake-only events versus `7` spawn-only events;
4. that means the new `libthr` planning path is doing the intended job:
   most remaining repeat-lane requests are now waking already-idle workers,
   not manufacturing new workers;
5. the honest next target therefore moves back up the stack:
   reduce upstream request generation and weak coalescing in staged
   `libdispatch`, while keeping the new low-noise `libthr` trace lane as a
   guard against regressing wake-first behavior.

### M13 wake-first `libthr` ready planning verified

The next real `M13` win did not come from another root-queue heuristic.
It came from making `libthr` stop treating every newly admitted worker as a
fresh spawn.

Key result:

1. `/usr/src/lib/libthr/thread/thr_workq.c` now tracks per-lane idle worker
   counts (`tbr_idle`) instead of only a process-wide idle total;
2. the old spawn-biased `admitted -> spawn_needed` assumption is now replaced
   by a wake-first planning step:
   same-lane idle workers are used first for already-counted pending work,
   then transferable idle workers from other lanes are used, and only the
   remainder is spawned;
3. the new planning path is used both in `addthreads` and in reaper-driven
   redrive, so the staged guest runtime now makes the same wake/spawn decision
   on both the hot path and the idle-trim redrive path;
4. two clean repeat-only runs at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T110916Z.json`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111107Z.json`
   confirm the effect in the guest.

Important findings:

1. the C repeat lane,
   `dispatch.main-executor-resume-repeat`,
   stayed stable and slightly improved versus the prior post-transfer band:
   from `+380 / +169 / +166` and `+354 / +163 / +160`
   to `+361 / +164 / +161` and `+343 / +158 / +155`;
2. the Swift repeat lane,
   `swift.dispatchmain-taskhandles-after-repeat`,
   improved materially versus the same post-transfer band:
   from `+1371 / +460 / +457` and `+1500 / +506 / +503`
   to `+1350 / +429 / +426` and `+1279 / +394 / +391`;
3. the Swift round-level request mean also improved from
   `21.297` and `23.312` to `20.984` and `19.891`;
4. this is the first current-branch result that improves the repeat-heavy
   Swift lane again without trying to fight a donor-shaped
   `cleanup2 -> overcommit root` handoff in staged `libdispatch`;
5. the honest next question is therefore narrower:
   measure the new wake/spawn mix directly under trace, then decide whether
   the next dominant hotspot is still staged-`libdispatch` redrive/coalescing
   or the remaining cross-lane wake planning inside `libthr`.

### M13 root-only trace isolates `cleanup2` main-queue handoff

The next useful `M13` narrowing step was diagnostic, not behavioral.

Key result:

1. `../nx/swift-corelibs-libdispatch/src/queue.c` now supports a dedicated
   `LIBDISPATCH_TWQ_TRACE_ROOT` switch, so root-queue diagnostics no longer
   require the broader mainqueue/lane trace;
2. `scripts/bhyve/stage-guest.sh` now stages and forwards a matching
   `TWQ_LIBDISPATCH_ROOT_TRACE` control into the guest benchmark lane;
3. the new root-only trace in
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T095603Z.serial.log`
   shows that the first repeat-lane overcommit request is not delayed child
   work directly;
4. it first appears when `_dispatch_queue_cleanup2()` has cleared the main
   queue's thread-bound state and `com.apple.main-thread` is pushed onto
   `com.apple.root.default-qos.overcommit` as an `empty->poke` root item.

Important findings:

1. the traced main queue is already ordinary at that point:
   `head_thread_bound=0`, `head_enqueued=1`, `head_dirty=0`,
   `head_drain_locked=0`, `head_in_barrier=0`;
2. the queue already contains one internal item at the moment it is pushed to
   the overcommit root (`head_head=head_tail=0xdb287e1a040` in the recorded
   trace);
3. the root-only traced repeat lane still ends in `rc=139`, so this remains a
   diagnostic lane, not a stable regression benchmark;
4. donor-side comparison against the local Apple `libdispatch` tree now says
   this seam is probably native-shaped:
   `_dispatch_main_q` targets `_dispatch_get_default_queue(true)`, and
   `_dispatch_queue_cleanup2()` clears thread-bound state before handing off
   through `_dispatch_lane_barrier_complete()`;
5. the next honest target is therefore narrower than “generic root redrive”
   and more specific than “the cleanup handoff exists”:
   investigate excess overcommit push/poke rate and weak coalescing after the
   first `cleanup2 -> barrier_complete -> main queue overcommit push`
   transition.

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
