# M12 Swift `TaskGroup` Suspension Boundary Progress

Superseded in part by
[m12-swift-runtime-matrix-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-runtime-matrix-progress.md):
the later runtime-matrix work showed that `dispatchmain-taskgroup-yield`
recovered and that the remaining boundary is narrower than generic
`TaskGroup` child suspension.

This pass tightened the remaining staged guest Swift boundary from
"`dispatchMain()` plus `TaskGroup` plus `Task.sleep`" to the narrower and more
useful "`TaskGroup` child suspension under the staged guest runtime."

## What Changed

Four new focused `dispatchMain()` probes were added:

1. [twq_swift_dispatchmain_spawned_yield.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_spawned_yield.swift)
2. [twq_swift_dispatchmain_spawned_sleep.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_spawned_sleep.swift)
3. [twq_swift_dispatchmain_taskgroup_onesleep.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_taskgroup_onesleep.swift)
4. [twq_swift_dispatchmain_taskgroup_sleep_next.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_taskgroup_sleep_next.swift)

One more probe then confirmed the broader suspension case:

5. [twq_swift_dispatchmain_taskgroup_yield.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_taskgroup_yield.swift)

The Swift build/staging scripts were extended so those binaries are built,
installed into the guest, and runnable through `TWQ_SWIFT_PROBE_FILTER`:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)

## Host Controls

All five new probes complete on the canonical installed Swift 6.3 toolchain.
That keeps the failure surface anchored to the staged guest stack rather than
generic FreeBSD Swift 6.3.

## Guest Results

Focused guest run with:

`dispatchmain-spawned-yield,dispatchmain-spawned-sleep,dispatchmain-taskgroup-onesleep,dispatchmain-taskgroup-sleep,dispatchmain-taskgroup-sleep-next`

Result matrix:

1. `dispatchmain-spawned-yield`: `ok`
2. `dispatchmain-spawned-sleep`: `ok`
3. `dispatchmain-taskgroup-onesleep`: `timeout`
4. `dispatchmain-taskgroup-sleep`: `timeout`
5. `dispatchmain-taskgroup-sleep-next`: `timeout`

Second focused guest run with:

`dispatchmain-taskgroup-yield`

Result:

1. `dispatchmain-taskgroup-yield`: `timeout`

## What This Means

The new boundary is:

1. spawned child suspension under `dispatchMain()` is fine;
2. `TaskGroup` collection API choice is not the root cause:
   `for await` and `group.next()` both fail once child suspension is present;
3. "all children suspend" is not required:
   one sleeping child is enough to stall the group;
4. the issue is not specific to `Task.sleep`:
   `Task.yield()` inside `TaskGroup` children fails too.

That is a materially better diagnosis than the earlier
`dispatchmain-taskgroup-sleep` label. The remaining staged guest Swift problem
is now best described as:

`TaskGroup` child suspension/resume is broken on the staged guest stack.

## Evidence Shape

The most useful guest evidence was:

1. spawned child probes showed both pre-suspend and post-suspend progress and
   emitted final `ok`;
2. `dispatchmain-taskgroup-yield` showed child progress both before and after
   `Task.yield()` for the first two children, then still timed out before
   `child-after-group` / `after-await`;
3. `dispatchmain-taskgroup-onesleep` timed out even though only one child had a
   suspension point.

That combination rules out a generic `dispatchMain()` failure and strongly
points at `TaskGroup`-specific child suspension handling.

## Next Step

The next useful cut is not broader Swift workload expansion. It is one more
small-step runtime isolation pass around `TaskGroup` child resumption:

1. compare `TaskGroup` child continuation-resume against `TaskGroup` child
   `yield`;
2. compare `TaskGroup` child suspension under `async main` against the current
   `dispatchMain()` lane with the same probe shape;
3. keep the current stable Swift validation profile unchanged while this stays
   diagnostic.
