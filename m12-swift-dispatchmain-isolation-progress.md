# M12 Swift `dispatchMain` Isolation Progress

Later follow-up work tightened this further in
[m12-swift-taskgroup-suspension-boundary-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-taskgroup-suspension-boundary-progress.md):
the surviving staged guest boundary is now specifically `TaskGroup` child
suspension, not generic `dispatchMain()`.

## Summary

This pass took the remaining Swift guest flakiness and reduced it to a much
smaller boundary.

The important result is:

1. the repo now has a focused Swift probe filter mechanism for guest runs;
2. three new `dispatchMain()` isolation probes now exist:
   - `dispatchmain-spawn`
   - `dispatchmain-yield`
   - `dispatchmain-continuation`
3. two consecutive filtered guest runs show the same result:
   - `dispatchmain-spawn`: `ok`
   - `dispatchmain-yield`: `ok`
   - `dispatchmain-continuation`: `ok`
   - `dispatchmain-sleep`: `ok`
   - `dispatchmain-taskgroup`: `ok`
   - `dispatchmain-taskgroup-sleep`: `timeout`

That means the remaining guest Swift problem is no longer "something about
`dispatchMain()`." It is much narrower: the persistent failure in this lane is
the combination of `TaskGroup` child execution plus `Task.sleep`.

## What Changed

### New Swift probes

Added:

1. [twq_swift_dispatchmain_spawn.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_spawn.swift)
2. [twq_swift_dispatchmain_yield.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_yield.swift)
3. [twq_swift_dispatchmain_continuation.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_continuation.swift)

These isolate three different behaviors under the same synchronous `main` +
`dispatchMain()` entry shape:

1. child-task join without suspension;
2. direct task suspension via `Task.yield()`;
3. continuation suspension/resume via `DispatchQueue.global()`.

### Staging and guest control

Updated:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
3. [env.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/env.ex)
4. [config.exs](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/config/config.exs)

The guest lane now supports:

1. `TWQ_SWIFT_PROBE_FILTER`
   - optional comma-separated Swift probe mode list
2. logged profile and filter sections in the guest serial log
3. filtered focused runs without widening the required validation lane

The filter is designed for isolation work, not for the normal stable gate.

## Host Result

Using the canonical installed Swift 6.3 toolchain, all three new probes pass on
the host:

1. `dispatchmain-spawn`
2. `dispatchmain-yield`
3. `dispatchmain-continuation`

That keeps the host as a clean control case.

## Guest Result

Focused guest runs used:

1. `TWQ_SWIFT_PROBE_PROFILE=full`
2. `TWQ_SWIFT_PROBE_FILTER=dispatchmain-spawn,dispatchmain-yield,dispatchmain-continuation,dispatchmain-sleep,dispatchmain-taskgroup,dispatchmain-taskgroup-sleep`

Serial logs:

1. `/tmp/twq-swiftdiag.serial.log`
2. `/tmp/twq-swiftdiag-repeat.serial.log`

Both runs produced the same terminal matrix:

1. `dispatchmain-spawn`: `ok`
2. `dispatchmain-yield`: `ok`
3. `dispatchmain-continuation`: `ok`
4. `dispatchmain-sleep`: `ok`
5. `dispatchmain-taskgroup`: `ok`
6. `dispatchmain-taskgroup-sleep`: `timeout`

That repeat matters. This is no longer a one-run curiosity.

## Interpretation

The new read is:

1. `dispatchMain()` itself is not the blocker;
2. awaited child-task join under `dispatchMain()` is not the blocker;
3. direct suspension via `Task.yield()` under `dispatchMain()` is not the
   blocker;
4. continuation suspend/resume under `dispatchMain()` is not the blocker;
5. plain `Task.sleep()` under `dispatchMain()` is not the blocker;
6. plain `TaskGroup` collection under `dispatchMain()` is not the blocker;
7. the persistent failure in this lane is the combination of `TaskGroup` child
   work and `Task.sleep()` inside those child tasks.

That is a much more defensible problem statement than the older "Swift guest
runtime is context-sensitive" description.

## Practical Consequence

The next Swift diagnostic step should not be another broad matrix.

It should stay narrow:

1. compare `dispatchmain-taskgroup` against `dispatchmain-taskgroup-sleep`
   directly;
2. split the sleep case further:
   - one sleeping child
   - all sleeping children
   - `Task.yield()` in children instead of `Task.sleep()`
   - `group.next()` versus `for await`
3. only after that widen back out to the async-main and inherited-context
   variants.

## Verification

Completed in this pass:

1. `zsh -n` on
   [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
2. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
3. host runs of the three new Swift probes
4. two focused guest runs with the same filtered probe set

## Next Step

Keep the stable Swift validation lane unchanged.

The next useful move is to create one more level of split inside the
`dispatchmain-taskgroup-sleep` family, not to widen the required gate.
