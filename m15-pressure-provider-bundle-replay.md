# M15 Pressure Provider Bundle Replay

## Purpose

This document records the host-side replay lane for the callable pressure
bundle.

It reconstructs a bundle artifact from the checked-in callable session artifact
without booting a guest. The purpose is to prove that the session artifact is
sufficient to reproduce the combined observer and tracker summary that the
bundle emits.

## Command

The replay lane lives at:

1. `scripts/benchmarks/run-m15-pressure-provider-bundle-replay.sh`

The corresponding ExUnit wrapper is:

1. `TwqTest.VM.run_m15_pressure_provider_bundle_replay/1`

## Replay Source

The default replay source is:

1. `benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json`

The default comparison baseline is:

1. `benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json`

## Exit Rule

The replay lane is healthy only if:

1. the replayed bundle artifact matches the checked-in bundle baseline;
2. the replayed struct sizes and source provenance remain stable;
3. observer summary fields and tracker transition fields remain reproducible
   from the session snapshots alone.

This keeps the bundle as a callable projection of session data rather than a
separate source of pressure truth.
