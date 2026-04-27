# M15 Pressure Provider Stack Gate

## Purpose

This document records the repo-owned top-level gate for the current
pressure-only boundary stack.

It does not claim a provider SPI or ABI.

Its job is narrower:

1. compose the current derived, live, preview, adapter, session, observer,
   tracker, bundle, replay, and contract lanes into one machine-readable
   verdict;
2. keep the pressure boundary legible as one stack instead of a growing list of
   independent smoke lanes;
3. prove that the same checked-in contract still describes every artifact
   family used by the stack.

## Gate Command

The checked-in stack gate lives at:

1. `scripts/benchmarks/run-m15-pressure-provider-stack-gate.sh`

The corresponding ExUnit wrapper is:

1. `TwqTest.VM.run_m15_pressure_provider_stack_gate/1`

## What The Gate Runs

The current stack gate runs these child lanes:

1. derived pressure-provider prep
2. live pressure-provider smoke
3. raw preview pressure-provider smoke
4. aggregate adapter pressure-provider smoke
5. callable session pressure-provider smoke
6. observer pressure-provider smoke
7. tracker pressure-provider smoke
8. bundle pressure-provider smoke
9. observer replay from the checked-in session artifact
10. tracker replay from the checked-in session artifact
11. bundle replay from the checked-in session artifact
12. shared contract-check over the actual artifact paths used above

## Default Operating Mode

The top-level gate defaults to reuse mode for the live families.

That means:

1. the derived lane still re-derives from the checked-in crossover artifact;
2. the replay lane still reconstructs the observer summary from the checked-in
   session artifact;
3. the live, preview, adapter, session, observer, tracker, and bundle smoke lanes
   reuse their checked-in baselines unless explicit candidate overrides are
   supplied.

This keeps the top-level gate practical while the individual smoke lanes remain
the place to demand fresh guest runs.

## Exit Rule

The stack is ready only when:

1. every child lane is green;
2. the contract lane still accepts every artifact family used by the gate;
3. the observer replay lane still proves the session artifact is sufficient for
   the consumer-side summary;
4. the tracker replay lane still proves the session artifact is sufficient for
   the transition-summary family;
5. the bundle replay lane still proves the session artifact is sufficient for
   the combined observer/tracker summary family;
6. the stack stays pressure-only and does not silently widen into topology,
   permits, or a claimed system SPI.

If any new layer needs fields that the current contract cannot describe
honestly, that is a contract version change or a design fork, not a quiet
extension to the current gate.
