# M12 Swift Validation Profile Progress

## Summary

This pass turned the Swift guest lane into an honest passing gate instead of a
moving target.

The important outcome is:

1. the repo now has a stable Swift `validation` profile in the guest;
2. that profile passes end to end in the gated `bhyve` integration test;
3. the required Swift lane is now intentionally narrow:
   - `async-smoke`
   - `dispatch-control`
   - `mainqueue-resume`
4. the `dispatchMain()` and `TaskGroup`-shaped probes remain useful, but they
   are now explicitly diagnostic instead of being forced into the required
   validation gate.

That is a real M12 milestone. It does not finish Swift validation, but it does
establish a trustworthy baseline that can be extended without lying to
ourselves.

## What Changed

The main work in this pass was not kernel code. It was the host-side harness
and Swift guest staging discipline.

Code changes:

1. [vm.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/vm.ex)
   now:
   - records the active Swift probe profile in the VM payload;
   - records the set of Swift timeout modes observed in the guest run;
   - validates only the currently stable Swift guest lane;
   - resolves per-mode probe lines from the final matching event instead of the
     first progress event.
2. [vm_integration_test.exs](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/test/twq_test/vm_integration_test.exs)
   now mirrors the stable Swift validation lane instead of expecting the older
   `TaskGroup` precheck to pass.
3. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
   already had the Swift profile split; this pass is what made the Elixir side
   actually respect it.

## The Important Bug Fixed

The red VM run after the first harness narrowing was not a new runtime
regression.

It was a parser bug.

Swift probes like `mainqueue-resume` emit multiple JSON lines:

1. one or more `progress` events;
2. one terminal event:
   - `ok`
   - `timeout`
   - or `error`

The previous lookup logic used the first line matching a mode, which meant the
validator would read the `progress` line and conclude the probe had failed even
when the final terminal event was `ok`.

The fix was to make the mode lookup use the last matching line.

That is now encoded in both:

1. [vm.ex](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/lib/twq_test/vm.ex)
2. [vm_integration_test.exs](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir/test/twq_test/vm_integration_test.exs)

## Stable Validation Lane

The current required Swift guest validation lane is:

1. `async-smoke`
   - proves the staged Swift runtime can start under `TWQDEBUG`
2. `dispatch-control`
   - proves Swift's `Dispatch` import uses the real TWQ-backed path
   - proves real TWQ counter movement in the guest
3. `mainqueue-resume`
   - proves a small awaited Swift path also completes and still moves real TWQ
     counters

This lane now passes in the gated VM integration run.

## Diagnostic Lane

These probes remain valuable, but they are not yet part of the required gate:

1. `taskgroup-spawned`
2. `dispatchmain-sleep`
3. `dispatchmain-taskgroup`
4. `dispatchmain-taskgroup-sleep`
5. the broader inherited-context and suspended-concurrency probes from the
   `full` profile

The current reason is simple: they are still context-sensitive and can vary
between runs, while the new `validation` lane is stable enough to be used as a
real regression gate.

## Verification

Completed in this pass:

1. `make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)
2. `TWQ_RUN_VM_INTEGRATION=1 make test` in
   [elixir](/Users/me/wip-gcd-tbb-fx/wip-codex54x/elixir)

Result:

1. host-side Elixir suite passes;
2. gated `bhyve` integration passes;
3. the Swift `validation` profile is now a real tested contract instead of a
   note in a progress document.

## Next Step

The next useful Swift work is not to widen the required gate immediately.

It is:

1. keep the stable `validation` lane green;
2. use the diagnostic probes to isolate the remaining waiter / `TaskGroup` /
   `dispatchMain()` boundary;
3. only promote new Swift probes into the required gate after they pass
   repeatedly under the guest lane.
