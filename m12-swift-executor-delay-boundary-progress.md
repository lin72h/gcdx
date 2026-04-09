# M12 Swift Executor Delay Boundary Progress

## Summary

This pass replaced the earlier "`Task.sleep`-driven resumption" diagnosis with
a more precise boundary:

1. delayed resume is not generically broken on the full staged TWQ lane;
2. `dispatchmain-spawnwait-after` succeeds on the full staged TWQ lane;
3. `dispatchmain-taskgroup-after` still times out on the full staged TWQ lane;
4. the same `dispatchmain-taskgroup-after` binary succeeds on both
   stock-dispatch guest controls:
   stock `libthr` and custom `libthr`;
5. the remaining staged Swift boundary is therefore not custom `libthr`, not
   generic timers, and not `Task.sleep` specifically.

The current best description is:

custom `libdispatch` handling of delayed child completion inside
`TaskGroup`-style executor work on the full TWQ lane

## What Changed

Two new Swift probes were added:

1. [twq_swift_dispatchmain_spawnwait_after.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_spawnwait_after.swift)
2. [twq_swift_dispatchmain_taskgroup_after.swift](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swiftsrc/twq_swift_dispatchmain_taskgroup_after.swift)

They use `DispatchQueue.global(...).asyncAfter(...)` to resume suspended work
instead of `Task.sleep`.

The Swift staging and guest scripts were extended accordingly:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
2. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)

One extra C dispatch diagnostic was also added:

3. `executor-after-settled` in
   [twq_dispatch_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_dispatch_probe.c)

That mode creates the same executor-style queue as `executor-after`, but
forces the queue's width-setup work to drain before scheduling delayed
callbacks.

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

### Full TWQ lane

Observed:

1. `dispatchmain-spawnwait-after`: `ok`
2. `dispatchmain-taskgroup-after`: `timeout`

Important shape:

1. some child delay callbacks do fire before the timeout;
2. the group never reaches `child-after-group`;
3. timeout diagnostics still show the same waiter topology:
   `nanslp`, `kqread`, `sigsusp`, and `uwait`.

That means this is not a simple "timers never fire" failure.

### Stock-dispatch guest controls

Observed in the same guest:

1. `dispatchmain-taskgroup-after-stockdispatch`: `ok`
2. `dispatchmain-taskgroup-after-stockdispatch-customthr`: `ok`

This keeps the blame off custom `libthr`. The same binary and the same guest
complete once the dispatch runtime is swapped back to stock.

## C Dispatch Controls

The C dispatch probe now provides useful surrounding controls for delayed
dispatch:

1. `after`: passes
2. `main-after`: passes
3. `executor-after`: passed in `/tmp/twq-dev.m12o.serial.log`, timed out once
   in `/tmp/twq-dev.m12p.serial.log`, then passed again in
   `/tmp/twq-dev.m12q.serial.log`
4. `executor-after-settled`: passes in `/tmp/twq-dev.m12q.serial.log`

That does not prove the queue-settling theory yet, but it does identify a real
implementation lead: delayed work on custom executor-style queues is the only C
surface that has shown instability, and the settled variant is currently
healthy.

## Interpretation

The old boundary is now too broad:

1. it is not accurate anymore to say the remaining problem is just
   `Task.sleep` on the TWQ path;
2. delayed dispatch wakeups can succeed on the full staged TWQ lane;
3. the failing shape is narrower and more structured:
   `TaskGroup` child completion after delayed resume on the staged custom
   `libdispatch`.

The C `executor-after` behavior is not stable enough yet to call it the
definitive root cause, but it is now the strongest non-Swift implementation
lead.

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
   - `dispatchmain-taskgroup-after`
   - `dispatchmain-taskgroup-after-stockdispatch`
   - `dispatchmain-taskgroup-after-stockdispatch-customthr`
6. custom dispatch-probe rebuild after adding `executor-after-settled`
7. `make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)

## Next Step

The next useful local step is no longer another broad Swift matrix.

It is a targeted custom-`libdispatch` investigation around delayed work on
executor-style queues:

1. inspect the queue-width setup path for executor queues;
2. inspect after-source targeting for custom concurrent queues;
3. compare plain `executor-after` against the settled variant until the
   instability story is either confirmed or disproved;
4. only then return to broader Swift workload expansion.
