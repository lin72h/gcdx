# M15 Pressure Provider Tracker Replay

## Purpose

This document records the repo-owned host replay lane for the tracker family.

It does not boot a guest and does not claim a live provider SPI.

Its job is narrower:

1. rebuild a tracker candidate from the checked-in session artifact;
2. prove that the session artifact is sufficient for the tracker summary;
3. keep tracker sufficiency testable without requiring a fresh guest run.

## Lane Command

The checked-in replay lane lives at:

1. `scripts/benchmarks/run-m15-pressure-provider-tracker-replay.sh`

The corresponding ExUnit wrapper is:

1. `TwqTest.VM.run_m15_pressure_provider_tracker_replay/1`

## Exit Rule

This lane stays healthy only if:

1. the checked-in session artifact still contains enough aggregate session/view
   detail to reconstruct the tracker summary;
2. the replayed tracker candidate still compares cleanly against the checked-in
   tracker baseline;
3. tracker remains a repo-owned summary above session, not a new hidden source
   of truth.
