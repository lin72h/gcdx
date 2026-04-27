# M15 Pressure Provider Tracker Smoke

## Purpose

This document records the repo-owned tracker smoke lane above the callable
session surface.

It does not claim a provider SPI or consumer integration.

Its job is narrower:

1. validate a versioned transition-tracker summary above callable session v1;
2. keep the pressure-only boundary expressed in edge counts instead of policy;
3. prove that the session artifact is rich enough to support a second
   consumer-side summary family besides the observer summary.

## Lane Command

The checked-in tracker smoke lane lives at:

1. `scripts/benchmarks/run-m15-pressure-provider-tracker-smoke.sh`

The corresponding ExUnit wrapper is:

1. `TwqTest.VM.run_m15_pressure_provider_tracker_smoke/1`

## What It Captures

For each tracked label, the tracker summary records:

1. source session and source view version/size;
2. sample count and generation/monotonic continuity;
3. initial and final state for:
   `pressure_visible`,
   `nonidle`,
   `request_backlog`,
   `block_backlog`,
   `narrow_feedback`,
   `quiescent`;
4. rise/fall counts for the same state set.

This keeps the lane pressure-only and policyless. It does not promote
per-bucket details or queue semantics.

## Exit Rule

This lane stays healthy only if:

1. the tracker summary remains session-backed and aggregate-view-backed;
2. the current-pressure contract still freezes on
   `nonidle_workers_current`, not raw `active_workers_current`;
3. the checked-in baseline and the fresh guest smoke both preserve the same
   transition shape for `dispatch.pressure` and `dispatch.sustained`.
