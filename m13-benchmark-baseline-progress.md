# M13 Benchmark Baseline Progress

## Summary

`M13` is now active instead of aspirational.

The repo now has a reproducible host-side benchmark lane that rebuilds the
staged userland pieces, stages the bhyve guest, runs a compact benchmark
profile, and extracts a structured JSON baseline.

Files added for this step:

1. `scripts/libthr/prepare-headers.sh`
2. `scripts/benchmarks/run-m13-baseline.sh`
3. `scripts/benchmarks/extract-m13-baseline.py`
4. `benchmarks/baselines/m13-initial.json`

Host-side artifacts from the first run:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T120024Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T120024Z.json`

Focused repeat-lane artifacts with round-level counter telemetry:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T123532Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T123532Z.json`
3. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125519Z.json`
4. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125820Z.serial.log`
5. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125820Z.json`
6. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T130005Z.json`

## Benchmark Set

The first compact M13 lane intentionally favors stable structured signals over
exhaustive coverage.

Dispatch modes:

1. `basic`
2. `pressure`
3. `burst-reuse`
4. `timeout-gap`
5. `sustained`
6. `main-executor-resume-repeat`

Swift modes:

1. `dispatch-control`
2. `mainqueue-resume`
3. `dispatchmain-taskhandles-after-repeat`

All selected modes completed with `ok` status in the first recorded baseline.

A second verification run kept the same `9/9` success result and the same
qualitative hotspots, but the heavy repeat lanes drifted modestly:

1. `dispatch.main-executor-resume-repeat`
   moved from `reqthreads +564 / enter +189 / return +186`
   to `reqthreads +522 / enter +175 / return +172`
2. `swift.dispatchmain-taskhandles-after-repeat`
   moved from `reqthreads +2799 / enter +934 / return +931`
   to `reqthreads +2640 / enter +881 / return +878`

That is good enough to confirm the direction of the next optimization work, but
not yet good enough for a hard regression gate.

The next two runs changed the M13 story in an important way:

1. the first apparent post-fix benchmark win turned out to be partly masked by
   a staging bug: `scripts/libthr/prepare-stage.sh` was refreshing from a stale
   `libthr` objdir and not the newest build products;
2. after fixing that staging path, the first real post-fix repeat-only run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125519Z.json`
   dropped the C repeat lane to
   `reqthreads +379 / enter +172 / return +169`
   and the Swift repeat lane to
   `reqthreads +1630 / enter +780 / return +777`;
3. a second clean repeat-only confirmation run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T130005Z.json`
   kept the same direction on the C lane at
   `reqthreads +320 / enter +150 / return +147`
   and kept the Swift lane materially below the pre-fix request level at
   `reqthreads +1863 / enter +884 / return +881`;
4. the traced proof run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125820Z.serial.log`
   is noisier because tracing changes timing, but it proves the new
   `worker-handoff-fastpath` path is live in the guest.

## Key Findings

### 1. Warm-pool behavior is stable in the compact reuse lanes

The first baseline confirms the current phase-1 warm-pool behavior rather than
just the raw correctness path:

1. `dispatch.burst-reuse` created `4` new workers in round `1` and `0` in the
   remaining rounds;
2. `dispatch.timeout-gap` also stayed at `4` settled idle workers after the
   long gap;
3. both lanes settled at `4` idle workers with `0` active workers.

This is a good baseline for later lifecycle tuning because it shows reuse is
already happening, even if retirement policy is still conservative.

### 2. Pressure behavior is still visible after the M12 correctness fix

The first M13 baseline still shows useful pressure shaping:

1. `dispatch.pressure` held `default_max_inflight` to `3` while the higher
   priority work ran;
2. the same run produced `9` block and `9` unblock observations;
3. `dispatch.sustained` drove `641` block and `641` unblock observations while
   settling back to the `4`-worker warm floor.

So the new baseline does not just confirm success/failure. It also preserves
the backpressure signal we care about.

### 3. The next honest optimization target is request/enter churn

The largest remaining inefficiency in the compact benchmark set is repeated
worker request/enter churn on continuation-heavy lanes.

The two clearest hotspots in the first baseline are:

1. `dispatch.main-executor-resume-repeat`
   `reqthreads_count +564`, `thread_enter_count +189`,
   `thread_return_count +186`
2. `swift.dispatchmain-taskhandles-after-repeat`
   `reqthreads_count +2799`, `thread_enter_count +934`,
   `thread_return_count +931`

Those numbers are much larger than the simpler control lanes:

1. `dispatch.basic`
   `reqthreads_count +15`, `thread_enter_count +5`
2. `swift.dispatch-control`
   `reqthreads_count +15`, `thread_enter_count +5`
3. `swift.mainqueue-resume`
   `reqthreads_count +13`, `thread_enter_count +5`,
   `thread_return_count +3`

That makes the next M13 direction concrete: keep correctness fixed, then
reduce redrive churn on repeated delayed-resume workloads.

### 4. Round-level repeat telemetry now shows the churn shape directly

The repeat benchmarks no longer rely only on whole-run before/after counters.

The C repeat lane, `dispatch.main-executor-resume-repeat`, now emits and
extracts `round-start-counters` and `round-ok-counters` for every round. The
same is true for the Swift repeat lane,
`swift.dispatchmain-taskhandles-after-repeat`.

That focused run changes what can be said honestly about the hotspot:

1. the C repeat lane is not just paying a startup penalty and then flattening;
   its `reqthreads` deltas stay active across all `64` rounds with a first-half
   mean of `7.66` and a second-half mean of `7.44`;
2. the same C lane keeps `bucket_total` pinned at `5` through the run, which
   means the warm pool is already established while the requests continue;
3. the Swift repeat lane is also not startup-only:
   `reqthreads` deltas average `44.91` in the first half and `38.56` in the
   second half, still far above the C lane late in the run;
4. this shifts the next tuning target more clearly toward request generation in
   staged `libdispatch`, not toward kernel admission or warm-pool formation.

### 5. The first real M13 tuning pass is now proven in-guest

The first live M13 optimization is no longer hypothetical.

The change had two parts:

1. `scripts/libthr/prepare-stage.sh` now auto-selects the freshest staged
   `libthr` objdir instead of assuming the old `amd64.amd64` path;
2. `/usr/src/lib/libthr/thread/thr_workq.c` now has a same-lane handoff fast
   path that skips a redundant `THREAD_RETURN -> THREAD_ENTER` cycle when a
   worker immediately claims another item in the same kernel bucket.

Compared with the pre-fix repeat-only mean:

1. `dispatch.main-executor-resume-repeat`
   moved from `reqthreads +546 / enter +183 / return +180`
   to `+379 / +172 / +169` in the first clean post-fix run and
   `+320 / +150 / +147` in the second;
2. `swift.dispatchmain-taskhandles-after-repeat`
   moved from `reqthreads +2659.5 / enter +887.5 / return +884.5`
   to `+1630 / +780 / +777` in the first clean post-fix run and
   `+1863 / +884 / +881` in the second.

The traced proof run shows why the results are mixed:

1. in the C repeat section, `worker-handoff-fastpath` fired `30` times and
   matched all `30` same-lane handoff claims;
2. in the Swift repeat section, `worker-handoff-fastpath` fired `63` times,
   but there were `216` handoff claims total and `153` of them still crossed
   lanes and required a real re-enter path;
3. that explains why `reqthreads` improves clearly on Swift while
   `thread_enter` / `thread_return` remain much noisier than the C lane.

### 6. Cross-lane transfer handoff is now proven live

The next M13 step no longer relies on inference from same-lane recycling.

The kernel and `libthr` now have a real cross-lane handoff op,
`TWQ_OP_THREAD_TRANSFER`, so a worker that claims work from a different kernel
lane can move there directly instead of always returning to the kernel and
re-entering.

The first current-branch transfer runs were misleading for two separate
reasons:

1. the guest kernel initially had not been rebuilt, so the new syscall op was
   not actually present in the running image;
2. after that, the staged `libthr` still came from stale
   `/tmp/twqlibobj/.../*.pico` objects, so new source edits in
   `/usr/src/lib/libthr/thread/thr_workq.c` had still not reached the guest.

Once both were corrected, the traced proof run at
`/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112356Z.serial.log`
showed the new path directly:

1. `worker-handoff-transfer`: `183`
2. `worker-handoff-enter`: `0`
3. `worker-handoff-fastpath`: `85`
4. `worker-handoff-claim`: `268`

That run is timing-perturbed by tracing, so the clean repeat-only follow-up
runs are the more honest performance signal:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112557Z.json`
   moved `dispatch.main-executor-resume-repeat` to
   `reqthreads +380 / enter +169 / return +166`
   and `swift.dispatchmain-taskhandles-after-repeat` to
   `+1371 / +460 / +457`;
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112757Z.json`
   moved the same lanes to
   `+354 / +163 / +160` and
   `+1500 / +506 / +503`.

The result is deliberately narrower than a blanket “all repeat churn is fixed”:

1. the C repeat lane stays roughly in the same band as the earlier same-lane
   improvement;
2. the Swift repeat lane improves materially, especially on
   `thread_enter` / `thread_return`;
3. that is strong evidence that cross-lane recycling was a real missing piece
   for Swift-heavy continuation paths;
4. it is also strong evidence that the next honest target is no longer
   worker recycling, but request generation and wake policy further up the
   stack.

### 7. A root-queue active-worker cap was tested and rejected

The next libdispatch-side experiment was deliberately small:
use the otherwise-idle `dgq_thread_pool_size` field on the FreeBSD
`pthread_workqueue` path as a transient active-worker count, then suppress
drain-side repokes once a root queue already had enough active drainers.

That idea did not survive contact with the trace:

1. the focused clean run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T113935Z.json`
   stayed correct and produced
   `dispatch.main-executor-resume-repeat`
   `+321 / +152 / +149` and
   `swift.dispatchmain-taskhandles-after-repeat`
   `+1407 / +476 / +473`;
2. but the proof trace at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T114107Z.serial.log`
   showed `drain-one-skip-poke` only `2` times while
   `root-queue-poke-slow` still fired `988` times;
3. that means the apparent clean-run movement was not materially caused by the
   cap logic;
4. the patch was reverted immediately rather than leaving a weak heuristic in
   the staged dispatch tree.

This is still useful progress because it narrows the next honest seam:

1. the remaining churn is not going to be solved by a coarse
   “active workers already at target” guard;
2. the real hotspot is still the root-queue request policy itself,
   especially the repeated `root-queue-poke-slow` traffic on
   `com.apple.root.default-qos` and
   `com.apple.root.user-initiated-qos`.

### 8. A `ready`-coverage fast path was also tested and rejected

The next `libthr` experiment targeted a more concrete redundancy:
skip a fresh kernel `REQTHREADS` call when a lane already had enough
`tbr_ready` workers to cover its current `tbr_pending` count.

That looked promising in static trace samples, but the live repeat-only runs
did not support keeping it:

1. the first clean run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115402Z.json`
   moved `dispatch.main-executor-resume-repeat` to
   `+345 / +157 / +154`, but moved
   `swift.dispatchmain-taskhandles-after-repeat` to
   `+1533 / +532 / +529`;
2. the traced run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115538Z.json`
   landed at `+384 / +179 / +176` and `+1263 / +521 / +517`,
   but the trace showed `addthreads-covered` only `4` times against
   `addthreads-begin: 952` and `root-queue-poke-slow: 952`;
3. the second clean run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115743Z.json`
   moved the same lanes to `+316 / +149 / +146` and
   `+1424 / +491 / +488`.

That is not a stable win:

1. the C repeat lane improved on average versus the immediate pre-patch band;
2. the Swift repeat lane did not improve on average and remained noisier than
   the post-transfer baseline;
3. the traced proof run shows the new path barely fires, so it is not the
   dominant source of repeat-lane churn.

The patch was reverted and the staged `libthr` was refreshed back to the
reverted state. The result is useful because it closes another tempting but
weak branch:

1. the main hotspot is not “already-ready work on the same lane”;
2. the remaining cost is still dominated by repeated root-queue request
   generation and cross-queue wake behavior above this point in the stack.

### 9. Root-queue tracing now reaches the default roots, and a main-queue repoke guard was rejected

The next useful step was not a blind behavior tweak. It was a traceability
fix.

The staged `libdispatch` root-drain trace originally only matched
`com.apple.root.user-initiated-qos`, which meant the dominant
`com.apple.root.default-qos` repeat-lane traffic was invisible at the
root-drain level even though the higher-level root-poke traces already showed
it.

The trace surface was widened in `../nx/swift-corelibs-libdispatch/src/queue.c`
so that:

1. root-drain traces now include both default and user-initiated roots;
2. root-drain events now record the popped item kind and queue label when the
   item is itself a queue object;
3. explicit callsite markers now exist for `drain-one`, contended-wait, and
   worker-timeout repokes.

That immediately produced one concrete new finding in the first focused trace
run at
`/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T093244Z.serial.log`:

1. the early repeat-lane redrive is not only about `twq.swift.executor` on the
   default root;
2. the `com.apple.main-thread` item on
   `com.apple.root.default-qos.overcommit` also performs an immediate
   `drain-one-repoke` when another root item is visible;
3. that overcommit-main-queue repoke is therefore part of the same churn
   picture and deserved a direct falsification attempt.

The resulting bounded behavior branch was:

1. skip the preemptive `drain-one` repoke only when the current root item is
   `com.apple.main-thread` and the current root is overcommit.

That branch did not survive repeated clean runs.

Artifacts:

1. trace seed run:
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T093244Z.serial.log`
2. clean trial 1:
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T093604Z.json`
3. clean trial 2:
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T093749Z.json`
4. clean trial 3:
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T093913Z.json`

The three clean trials landed at:

1. dispatch repeat:
   `+336 / +153 / +150`,
   `+348 / +160 / +157`,
   `+340 / +153 / +150`
2. Swift repeat:
   `+1344 / +429 / +426`,
   `+1414 / +468 / +465`,
   `+1616 / +542 / +539`

That is not stable enough to keep:

1. the C lane stayed roughly in-band;
2. the Swift lane had one promising result, one neutral result, and one clear
   regression;
3. the behavior change was reverted immediately;
4. only the improved root-trace instrumentation remains.

This is still real progress because it narrows the next honest target again:

1. a coarse “skip main-queue overcommit repoke” heuristic is too
   timing-sensitive;
2. the useful retained result is the wider root-drain visibility on the
   default roots;
3. the next libdispatch-side change needs to distinguish more carefully between
   queue-object redrive that is actually productive and queue-object redrive
   that only manufactures extra worker requests.

### 10. Root-only tracing isolates the first overcommit request to `cleanup2` main-queue handoff

The next useful narrowing step was to stop tracing the whole executor path and
trace only the root-queue enqueue/drain path.

Two small infrastructure changes made that possible:

1. `../nx/swift-corelibs-libdispatch/src/queue.c` now has a dedicated
   `LIBDISPATCH_TWQ_TRACE_ROOT` control, instead of forcing root traces to ride
   on the broader `LIBDISPATCH_TWQ_TRACE_MAINQUEUE` switch;
2. `scripts/bhyve/stage-guest.sh` now stages and forwards a matching
   `TWQ_LIBDISPATCH_ROOT_TRACE` guest-side control so the benchmark lane can
   request root-only tracing without also enabling the noisier lane and
   main-queue traces.

That narrower trace produced a better boundary in
`/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T095603Z.serial.log`:

1. the first root activity in the repeat lane is expected:
   `twq.swift.executor` is pushed onto
   `com.apple.root.default-qos` as an `empty->poke` item;
2. after the executor callback returns to the main-queue side,
   the next overcommit request is not yet delayed child work;
3. instead, `com.apple.main-thread` itself is pushed onto
   `com.apple.root.default-qos.overcommit` as another `empty->poke` root item;
4. that pushed main queue is already no longer thread-bound at this point
   (`head_thread_bound=0`), is already marked enqueued, and already contains
   one queued item (`head_head=head_tail=0xdb287e1a040` in the traced run);
5. the traced repeat lane still crashes with `rc=139` immediately after that
   push, so this root-only trace remains diagnostic-only, not a stable
   regression workload.

That changes the next honest seam again:

1. the earliest repeat-lane overcommit request is now tied directly to
   `_dispatch_queue_cleanup2()` turning the main queue into an ordinary queue
   and handing it off to the overcommit default root;
2. the next libdispatch-side investigation should look at the
   `cleanup2 -> barrier_complete -> root push` transition itself, not only at
   later “next visible item” redrive;
3. the retained root-only trace control should stay, because it is a more
   targeted diagnostic lane than the earlier broad executor trace.

### 11. MX comparison says the `cleanup2 -> overcommit` seam is probably native-shaped

The next interpretation step was to compare that seam against Apple’s own
`libdispatch` structure, not just our local trace.

The useful donor-side facts are now explicit:

1. in `../nx/apple-opensource-libdispatch/src/queue.c`,
   `_dispatch_main_q` is initialized with
   `.do_targetq = _dispatch_get_default_queue(true)`, which points the main
   queue at the default overcommit root rather than the plain default root;
2. in `../nx/apple-opensource-libdispatch/src/inline_internal.h`,
   `_dispatch_get_default_queue(true)` resolves to the overcommit variant of
   the default root queue;
3. in `../nx/apple-opensource-libdispatch/src/queue.c`,
   `_dispatch_queue_cleanup2()` clears the thread-bound state and immediately
   hands off through `_dispatch_lane_barrier_complete(dq, 0, 0)`.

That does not prove our current repeat lane is efficient, but it changes the
burden of proof:

1. the mere existence of a
   `cleanup2 -> com.apple.main-thread -> com.apple.root.default-qos.overcommit`
   transition is now likely native behavior, not an immediate porting mistake;
2. the real question is rate and coalescing:
   are we generating materially more cleanup-triggered overcommit pushes/pokes
   per logical delayed-resume cycle than native macOS would;
3. the next honest target is therefore no longer “remove the cleanup handoff,”
   but “measure and reduce excess overcommit redrive after the first
   cleanup-triggered handoff.”

### 12. Per-lane idle accounting and wake-first planning reduce repeat-lane churn again

The next real `M13` movement did not come from another staged-`libdispatch`
requeue heuristic. It came from making `libthr` stop treating every admitted
worker as a fresh spawn.

The useful structural issue was in `/usr/src/lib/libthr/thread/thr_workq.c`:

1. `TWQ_OP_REQTHREADS` returns newly scheduled workers for a lane, not a pure
   “spawn this many brand-new threads” command;
2. the old userland planning path still treated `admitted` as
   `spawn_needed`, then only woke idle workers for the remainder;
3. that meant the runtime had no lane-aware way to prefer already-counted
   same-lane idle workers or transferable idle workers from other lanes before
   creating more workers.

The fix is now more explicit:

1. each lane runtime now tracks its own idle worker count via `tbr_idle`;
2. a new ready-planning step first wakes same-lane idle workers for
   already-counted pending work, then wakes transferable idle workers for the
   admitted remainder, and only then spawns the rest;
3. the same wake-first planning is used both in the direct `addthreads` path
   and in reaper-driven redrive, so the staged runtime no longer has one
   wake/spawn policy on the hot path and another in the idle-redrive path.

The first two clean repeat-only runs after rebuilding `/tmp/twqlibobj` and
refreshing the staged guest artifacts are:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T110916Z.json`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111107Z.json`

Compared with the earlier clean post-transfer band from
`/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112557Z.json`
and
`/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112757Z.json`,
the result is narrower but real:

1. `dispatch.main-executor-resume-repeat` stayed stable and slightly improved,
   moving from `+380 / +169 / +166` and `+354 / +163 / +160`
   to `+361 / +164 / +161` and `+343 / +158 / +155`;
2. `swift.dispatchmain-taskhandles-after-repeat` improved materially,
   moving from `+1371 / +460 / +457` and `+1500 / +506 / +503`
   to `+1350 / +429 / +426` and `+1279 / +394 / +391`;
3. the Swift round-level `reqthreads_delta` mean also moved in the right
   direction, from `21.297` and `23.312` to `20.984` and `19.891`.

That changes the next honest interpretation again:

1. the donor-shaped
   `cleanup2 -> com.apple.main-thread -> com.apple.root.default-qos.overcommit`
   seam may still exist exactly as before, but that seam was not the whole
   story;
2. userland worker planning inside `libthr` still had real churn to remove,
   because it was too eager to spawn instead of waking workers that were
   already counted or already idle;
3. this is the first current-branch result that improves the Swift repeat lane
   again without trying to suppress the cleanup-triggered overcommit handoff
   itself.

### 13. A low-noise `libthr` trace lane now shows the remaining requests are mostly wakes, not spawns

The next useful question after that wake-first improvement was simple:
did the benchmark win come from real wake-first behavior, or did the run just
land in a better timing band?

The original trace surface was not good enough to answer that honestly,
because enabling `TWQ_SWIFT_RUNTIME_TRACE` also turned on the broader
`libdispatch` lane and main-queue traces, and the repeat-only traced runs
under that full bundle were still crashing with `rc=139`.

That is now fixed at the harness layer:

1. `scripts/bhyve/stage-guest.sh` now stages and forwards split guest trace
   controls for `TWQ_LIBPTHREAD_TRACE`,
   `TWQ_LIBDISPATCH_MAINQUEUE_TRACE`, and
   `TWQ_LIBDISPATCH_ROOT_TRACE`;
2. the old compatibility path still exists, but `LIBPTHREAD_TWQ_TRACE` no
   longer requires the noisier `libdispatch` traces to be enabled at the same
   time.

The first repeat-only `libthr`-trace run is:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.json`

That run is timing-perturbed by tracing, so its absolute counters are not the
right baseline to compare against the clean band.

What it proves is narrower and more useful:

1. the C repeat lane still completed under trace with
   `reqthreads +230 / enter +110 / return +107`
   and round-level `reqthreads_delta` mean `3.484`;
2. the Swift repeat lane also completed under trace with
   `reqthreads +657 / enter +189 / return +186`
   and round-level `reqthreads_delta` mean `10.156`;
3. more importantly, the `addthreads-ready` mix in the traced serial log is
   overwhelmingly wake-dominant:
   dispatch showed `118` wake-only events versus `5` spawn-only events,
   while Swift showed `456` wake-only events versus `7` spawn-only events;
4. many of those wake-only decisions now happen with `admitted=0`, which is
   the exact signal we wanted:
   repeated upstream requests are being serviced by already-counted idle
   workers instead of being translated into more worker creation.

That changes the next honest target again:

1. the new `libthr` wake-first planning path is now directly proven in the
   guest, not just inferred from benchmark deltas;
2. the remaining repeat-lane cost is therefore less about “still spawning too
   many workers” and more about “still generating too many worker requests
   upstream”;
3. the next behavioral pass should go back to staged-`libdispatch` request
   generation and coalescing, while keeping the new low-noise `libthr` trace
   lane available as a regression guard.

### 14. Queue-only same-root root-poke deferral was tried and rejected

The next staged-`libdispatch` experiment after that trace result was a much
narrower version of the earlier rejected same-root poke suppression:
defer the root poke only when an empty root queue receives a single queue
object back onto the same root the current worker is already draining.

The hypothesis was specific:
this should coalesce the repeated timer-worker to executor-queue handoff
without suppressing unrelated continuation or override pushes.

The results were not stable enough to keep:

1. the first clean repeat-only run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T124521Z.json`
   looked promising:
   `dispatch.main-executor-resume-repeat` landed at
   `+343 / +155 / +152`
   and
   `swift.dispatchmain-taskhandles-after-repeat` dropped to
   `+1184 / +362 / +359`;
2. the required confirmation run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T124736Z.json`
   did not hold that win:
   dispatch regressed to
   `+432 / +187 / +184`
   and Swift regressed to
   `+1532 / +506 / +503`;
3. the round-level means told the same story:
   the first run moved Swift `reqthreads_delta` mean down to `18.328`,
   but the second run climbed back to `23.750`, which is materially worse than
   the earlier clean post-wake-first band.

That is enough to treat this as another rejected `M13` line:

1. the queue-only same-root root-poke deferral was reverted;
2. the first improved run is now treated as timing luck, not as a valid new
   baseline;
3. the next honest target remains upstream request generation in staged
   `libdispatch`, but not through same-root root-poke suppression.

## Immediate Next Step

The next implementation pass should focus on why repeated continuation-heavy
lanes still provoke so many worker requests and enter/return cycles even though
they now complete correctly.

That tuning work should stay disciplined:

1. measure against `benchmarks/baselines/m13-initial.json`;
2. optimize one layer at a time;
3. use the new round-level telemetry to distinguish startup effects from
   steady-state policy behavior;
4. verify that lower churn does not regress the M12 correctness floor;
5. treat the first `cleanup2 -> main queue -> overcommit root` handoff as
   likely legitimate and measure what happens after it;
6. treat the new `libthr` wake-first planning path as proven enough for the
   current phase:
   the low-noise trace now shows that most remaining repeat-lane requests are
   wakes, not spawns;
7. move the next behavioral reduction back to staged `libdispatch` request
   generation and coalescing above that wake path;
8. keep the split `libthr`-only trace lane as a guardrail so later
   `libdispatch` changes do not quietly regress the wake/spawn mix.

### 15. Counter-only staged-`libdispatch` runs move the M13 target to root `drain-one-repoke`

The next diagnostic pass replaced the noisy `dprintf` trace path with
low-overhead per-process counters inside staged `libdispatch`.

That changed the `M13` picture again, but this time more decisively:

1. the first queue-focused counter pass, at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T130059Z.serial.log`,
   completed cleanly and showed that the suspected concurrent-lane redirect
   seam was inactive for these repeat workloads:
   `concurrent_push_redirect=0`,
   `concurrent_push_fallback=0`,
   `async_redirect_invoke_entry=0`,
   `async_redirect_invoke_exit=0`,
   `lane_push_wakeup=0`, and
   `lane_push_no_wake=0`;
2. that ruled out `_dispatch_lane_concurrent_push()` and
   `_dispatch_async_redirect_invoke()` as the live source of the remaining
   repeat-lane churn;
3. the next counter pass moved down to the root queue path and the cleanest
   fully instrumented run is now
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T131214Z.serial.log`
   with structured output at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T131214Z.json`.

What that run proves for the C repeat lane:

1. `dispatch.main-executor-resume-repeat` completed at
   `reqthreads +385 / enter +170 / return +167`;
2. its staged-`libdispatch` counter dump ended with
   `root_push_append_default=973`,
   `root_repoke_default=973`, and
   `root_repoke_drain_one_default=973`;
3. the two other repoke sources stayed at zero:
   `root_repoke_contended_wait_default=0` and
   `root_repoke_worker_timeout_default=0`;
4. default-overcommit participation in that C lane stayed negligible:
   `root_push_empty_default_overcommit=1`,
   `root_poke_default_overcommit=2`, and
   `root_repoke_default_overcommit=1`.

What that run proves for the Swift repeat lane:

1. `swift.dispatchmain-taskhandles-after-repeat` completed at
   `reqthreads +1401 / enter +463 / return +460`;
2. the repeated redrive signature is still the same default-root pattern:
   `root_push_append_default=381`,
   `root_repoke_default=381`, and
   `root_repoke_drain_one_default=381`;
3. again, the repoke came entirely from the next-visible drain path:
   `root_repoke_contended_wait_default=0`,
   `root_repoke_worker_timeout_default=0`,
   `root_repoke_contended_wait_default_overcommit=0`, and
   `root_repoke_worker_timeout_default_overcommit=0`;
4. Swift adds one extra ingredient that the C repeat lane barely touches:
   a material one-shot default-overcommit ingress,
   `root_push_empty_default_overcommit=208` and
   `root_poke_slow_default_overcommit=208`,
   but not an overcommit repoke loop.

That is enough to freeze the next `M13` target more narrowly:

1. the active repeat bottleneck is no longer “staged `libdispatch` request
   generation in general”;
2. it is specifically the root queue next-visible redrive path,
   `_dispatch_root_queue_drain_one() -> _dispatch_root_queue_poke(dq, 1, 0)`;
3. the C repeat lane is almost a perfect proof:
   `root_push_append_default` and
   `root_repoke_drain_one_default` match exactly;
4. the Swift repeat lane keeps the same default-root repoke signature and then
   adds a separate one-shot default-overcommit ingress, which should be treated
   as a secondary follow-up seam rather than the first optimization target;
5. therefore the next behavioral pass should target root repoke coalescing or
   better next-visible handoff at the default root, not concurrent-lane
   redirect tuning and not another attempt to suppress the initial
   `cleanup2 -> overcommit root` handoff.

### 16. Targeted `dispatch_after` source suppression is the first root-redrive win that holds

The next `M13` pass stopped guessing about generic root policy and targeted the
dominant measured seam directly:
non-overcommit default-root `drain-one-repoke` was suppressed only when the
current head item was a one-shot `dispatch_after` timer source.

The first clean result is now:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.json`

What that run proves:

1. `dispatch.main-executor-resume-repeat` stayed correct and improved from the
   prior kind-classification baseline
   (`+402 / +177 / +174` at `...133950Z.json`)
   to `+324 / +153 / +150`;
2. `swift.dispatchmain-taskhandles-after-repeat` also stayed correct and moved
   from `+1323 / +422 / +419` to `+1234 / +408 / +405`;
3. the Swift counter dump shows the intended effect directly:
   `root_repoke_default=0`,
   `root_repoke_drain_one_default=0`, and
   `root_repoke_suppressed_after_source_default=363`;
4. the remaining Swift default-root traffic in that run is therefore no longer
   a repoke loop at all; it is reduced to ordinary root pushes and the same
   one-shot default-overcommit main-queue handoff we already treat as a
   secondary seam.

That is enough to keep this behavioral change:

1. the live repeat-lane bottleneck was not “all root repokes”;
2. it was specifically over-eager next-visible repoke on one-shot
   `dispatch_after` source items;
3. suppressing only that source class materially reduces churn without breaking
   the staged guest correctness floor.

### 17. The remaining C repeat tail is now pinned to default-root `ASYNC_REDIRECT`

Once the `dispatch_after` source repoke was suppressed, the next useful
question was what still remained on the C repeat lane.

The follow-up measurement run is now:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.json`

What that run proves:

1. the source suppression still holds:
   `dispatch.main-executor-resume-repeat` stayed in the same improved band at
   `+329 / +153 / +150`,
   while Swift improved again to
   `+1137 / +386 / +383`;
2. Swift still shows the same root-level outcome:
   `root_repoke_default=0` and
   `root_repoke_suppressed_after_source_default=372`;
3. the C repeat lane no longer repokes on source items either:
   `root_repoke_suppressed_after_source_default=512`,
   `root_repoke_drain_one_kind_default_source=0`;
4. the remaining C default-root repokes are now almost entirely
   `ASYNC_REDIRECT` continuations plus a small lane tail:
   `root_repoke_drain_one_kind_default_continuation=443`,
   `root_repoke_drain_one_kind_default_continuation_async_redirect=443`,
   and
   `root_repoke_drain_one_kind_default_lane=55`.

That freezes the next honest `M13` target again:

1. keep the new `dispatch_after` source suppression in staged `libdispatch`;
2. stop treating generic continuation traffic as the next fix target;
3. move the next pass to the default-root `ASYNC_REDIRECT` continuation path,
   because that is now the dominant remaining C repeat seam after source
   repokes were removed.

### 18. Unsafe push-path classification was rejected; DTrace is now the right seam

The next diagnostic attempt tried to classify objects pushed to
`com.apple.root.default-qos.overcommit` from inside staged `libdispatch`.
That was the correct question but the wrong implementation site.

The failed path:

1. root-push kind counters dereferenced the pushed `head` object after
   `_dispatch_root_queue_push_inline()` had already called `os_mpsc_push_list()`;
2. on the append path, that publish can race with an already-running drainer
   that pops, invokes, and recycles the continuation;
3. dereferencing `dx_metatype(head)` after that publish boundary produced
   immediate Swift repeat `rc=139` failures.

That patch was reverted. The two retained M13 behavior changes were kept:

1. non-overcommit default-root `drain-one-repoke` suppression for one-shot
   `dispatch_after` timer sources;
2. same-target `ASYNC_REDIRECT` suppression when the target lane already has
   `used_width >= 3`.

The focused stability run after the revert is:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260416T024756Z.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260416T024756Z.json`

What that run proves:

1. `swift.dispatchmain-taskhandles-after-repeat` completed all `64` rounds;
2. the TWQ delta was `reqthreads +969 / enter +317 / return +314`;
3. the remaining overcommit seam is still push volume, not repoke:
   `root_push_empty_default_overcommit=164`,
   `root_poke_slow_default_overcommit=165`,
   and
   `root_repoke_default_overcommit=1`.

The new instrumentation rule is now explicit:

1. classify push objects before publish, not after publish;
2. classify drain objects only while the drain loop owns them;
3. use DTrace for push-path classification until the object population is
   known well enough to justify a permanent in-process counter.

The repo now stages three FreeBSD DTrace helpers into bhyve guests under
`/root/twq-dtrace`:

1. `m13-push-poke-drain.d` for pointer-only event ordering;
2. `m13-push-vtable.d` for vtable-pointer classification at
   `_dispatch_root_queue_push:entry`;
3. `m13-root-summary.d` for low-volume root queue aggregate counts.

### 19. DTrace and a safe main-queue counter close the overcommit object question

The next pass fixed two diagnostic problems rather than changing dispatch
policy.

First, the DTrace runner now traces the real target process directly. The
initial no-event DTrace attempts used `dtrace -c "env ... probe"` which made
DTrace bind to `/usr/bin/env` before the final probe binary was executed. The
guest script now runs `env ... dtrace ... -c /root/probe`, so the `pid`
provider sees the staged Swift or C probe process itself.

Second, the only permanent push-path classifier retained in staged
`libdispatch` now uses pointer identity against `_dispatch_main_q`. It no
longer calls `dx_metatype()` or `dx_type()` on pushed objects. That keeps the
classification before the MPSC publish boundary and avoids decoding arbitrary
continuations.

Fresh current-binary DTrace evidence:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-dtrace-push-vtable-20260416T042209Z.serial.log`
   completed a `2 x 8` Swift repeat run under `push-vtable`;
2. `scripts/dtrace/analyze-m13-vtable.py` maps the pushed objects as:
   `default` root gets `16` `__OS_dispatch_source_vtable` pushes,
   `default.overcommit` gets `7` `__OS_dispatch_queue_main_vtable` pushes,
   and `user-initiated` gets `21` `_dispatch_continuation_vtables+0x38`
   pushes;
3. that matches the manual trace reading: timer sources land on the default
   root, Swift/global continuations land on user-initiated, and the
   default-overcommit root is primarily main-queue handoff traffic.

Fresh full-repeat counter evidence:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.serial.log`
   completed the full `64 x 8` Swift repeat run with counters enabled;
2. the extracted JSON at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json`
   reports `reqthreads +1058 / enter +343 / return +340`;
3. the round-level mean is `16.41` `reqthreads` per round, with a range of
   `9` to `40`;
4. the libdispatch counter dump shows
   `root_push_empty_default_overcommit=186`,
   `root_push_mainq_default_overcommit=186`,
   `root_poke_slow_default_overcommit=187`, and
   `root_repoke_default_overcommit=1`.

That closes the object-population question for this seam:

1. the default-overcommit pressure is not random continuation traffic;
2. it is almost exactly main-queue handoff traffic;
3. this agrees with the macOS-source expectation that
   `com.apple.main-thread` can target the default overcommit root;
4. the next question is therefore rate and coalescing compared with macOS, not
   whether the handoff exists.

The benchmark extractor now preserves `[libdispatch-twq-counters]` dumps in
the structured JSON, and `scripts/benchmarks/summarize-m13-baseline.py` gives
a compact CLI view of both `kern.twq.*` deltas and libdispatch root counters.

`scripts/benchmarks/compare-m13-baselines.py` is also available as the first
coarse regression gate. It compares common benchmark modes across two JSON
files, checks status regressions, and applies a drift-tolerant threshold to
`reqthreads_count`, `thread_enter_count`, and `thread_return_count`.

The current focused comparison against the checked-in initial baseline passes:

```sh
scripts/benchmarks/compare-m13-baselines.py \
  benchmarks/baselines/m13-initial.json \
  /Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json \
  --mode swift.dispatchmain-taskhandles-after-repeat
```

That reports the Swift repeat lane moving from
`2799 / 934 / 931` to `1058 / 343 / 340` for
`reqthreads / enter / return`.
