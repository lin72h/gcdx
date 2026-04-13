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
5. target the next reduction on cross-lane request generation, because the
   worker-recycling path is now proven across both same-lane and cross-lane
   handoff cases and is no longer the dominant unknown.
