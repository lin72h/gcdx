# M12 Swift Runtime Matrix Progress

Superseded in part by
[m12-swift-executor-delay-boundary-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-executor-delay-boundary-progress.md):
later `dispatch_after`-based probes showed that the remaining staged Swift
boundary is narrower than "`Task.sleep` on the TWQ path" and is now better
described as delayed `TaskGroup` child completion on the staged custom
`libdispatch` lane.

## Summary

This pass replaced the earlier "`TaskGroup` child suspension is broken"
diagnosis with a more precise runtime split:

1. `dispatchmain-taskgroup-yield` now completes in all three tested guest
   runtime combinations.
2. `dispatchmain-taskgroup-sleep` times out only on the full staged TWQ lane.
3. `dispatchmain-spawnwait-sleep` shows the same split:
   timeout on the full staged TWQ lane, success on stock-dispatch.
4. `dispatchmain-taskgroup-sleep` also completes with stock-dispatch plus the
   custom `libthr`, which means the current blocker is not custom `libthr`.

The remaining staged Swift boundary is therefore not generic `TaskGroup`
suspension. It is narrower:

custom `libdispatch` / TWQ handling of `Task.sleep`-driven resumption

## Runtime Combinations

The same Swift binaries were run in the guest with three different library
paths:

1. stock-dispatch plus stock `libthr`
   - `LD_LIBRARY_PATH=/root/twq-stock-dispatch:/root/twq-swift/usr/lib/swift/freebsd`
2. stock-dispatch plus custom `libthr`
   - `LD_LIBRARY_PATH=/root/twq-stock-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib`
3. full staged TWQ lane
   - `LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib`

That let the guest compare the same Swift runtime and the same binary against
different dispatch / thread-library stacks without changing the kernel or the
probe code.

## Yield Matrix

Serial log:

1. `/tmp/twq-dev.m12l.serial.log`

Result:

1. `dispatchmain-spawnwait-yield` on full staged TWQ lane: `ok`
2. `dispatchmain-spawnwait-yield` on stock-dispatch: `ok`
3. `dispatchmain-taskgroup-yield` on full staged TWQ lane: `ok`
4. `dispatchmain-taskgroup-yield` on stock-dispatch plus stock `libthr`: `ok`
5. `dispatchmain-taskgroup-yield` on stock-dispatch plus custom `libthr`: `ok`

Meaning:

1. the earlier "`TaskGroup` yield always wedges" result is no longer true;
2. the current guest problem is not generic suspended-child collection inside
   `TaskGroup`;
3. custom `libthr` is not enough by itself to break `TaskGroup` yield.

## Sleep Matrix

Serial logs:

1. `/tmp/twq-dev.m12m.serial.log`
2. `/tmp/twq-dev.m12n.serial.log`

Result:

1. `dispatchmain-spawnwait-sleep` on full staged TWQ lane: `timeout`
2. `dispatchmain-spawnwait-sleep` on stock-dispatch: `ok`
3. `dispatchmain-taskgroup-sleep` on full staged TWQ lane: `timeout`
4. `dispatchmain-taskgroup-sleep` on stock-dispatch plus stock `libthr`: `ok`
5. `dispatchmain-taskgroup-sleep` on stock-dispatch plus custom `libthr`: `ok`

Meaning:

1. the failure is not specific to `TaskGroup`;
2. the failure is tied to `Task.sleep`-driven resumption on the staged TWQ
   dispatch path;
3. because stock-dispatch plus custom `libthr` succeeds, the current boundary
   is not custom `libthr`;
4. the best current suspect is the staged custom `libdispatch` / TWQ worker
   path under sleep-driven Swift resumption.

## Timeout Shape

The timeout diagnostics from the failing TWQ runs are consistent across both
sleep-based probes:

1. one thread is blocked in `kern_clock_nanosleep`;
2. one thread is sleeping in `kqueue_scan` / `kevent`;
3. one thread is in `kern_sigsuspend`;
4. two threads are blocked in `__umtx_op_wait_uint_private`.

That does not prove the root cause yet, but it shows the failing state is a
real blocked/waiter topology, not a missing path-selection issue.

## What Changed

The guest staging path now carries a second Dispatch runtime source:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
   now copies the toolchain-shipped `libdispatch.so` and
   `libBlocksRuntime.so` into a dedicated stock-dispatch stage directory.
2. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
   now stages those libraries into `/root/twq-stock-dispatch` and exposes
   filtered diagnostic modes for stock-dispatch versus full-TWQ runs.

This is diagnostic-only plumbing. The required Swift validation gate stays
unchanged.

## Verification

Completed in this pass:

1. `zsh -n` on
   [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. `zsh -n` on
   [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
3. `./scripts/swift/prepare-stage.sh`
4. `make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)
5. `TWQ_RUN_VM_INTEGRATION=1 make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)

The normal `validation` profile remained green.

## Next Step

The next useful cut is no longer "`TaskGroup` vs non-`TaskGroup`."

It is sleep-driven resumption specifically on the staged TWQ dispatch path:

1. compare `Task.sleep` against continuation-resume and `dispatch_after` on the
   same queue shape;
2. inspect whether the TWQ-backed worker lane is starving or mis-accounting
   delayed wakeups after sleep;
3. keep the stable Swift validation profile narrow while this stays
   diagnostic.
