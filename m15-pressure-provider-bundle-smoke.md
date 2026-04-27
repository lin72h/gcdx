# M15 Pressure Provider Bundle Smoke

## Purpose

This document records the repo-owned smoke lane for the callable pressure
bundle.

It does not introduce a live SPI or ABI.

The bundle is a preview consumer surface above the callable session:

1. prime one pressure-provider session;
2. poll the session once per sample;
3. update the observer summary from that same view;
4. update the transition tracker from that same view;
5. emit one combined summary per workload label.

This gives TBBX / TCM integration work a stable aggregate polling artifact
without putting TCM vocabulary or permit policy below the provider line.

## Command

The checked-in smoke lane lives at:

1. `scripts/benchmarks/run-m15-pressure-provider-bundle-smoke.sh`

The corresponding ExUnit wrapper is:

1. `TwqTest.VM.run_m15_pressure_provider_bundle_smoke/1`

The checked-in baseline lives at:

1. `benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json`

## Boundary

The bundle remains pressure-only.

It records:

1. session, view, observer, and tracker struct provenance;
2. sample continuity and monotonic time continuity;
3. final aggregate pressure view fields;
4. observer sample and max values;
5. tracker transition counts.

`observer_quiescent_samples` is intentionally treated as a timing-tolerant
sample count.  The stable quiescence contract is the final quiescent state plus
the tracker quiescent rise/fall transitions.

It does not record:

1. TCM permit states;
2. TCM grant counts;
3. TCM callbacks;
4. topology or CPU capacity;
5. per-QoS policy decisions.

## Exit Rule

The bundle smoke lane is healthy only if:

1. generation and monotonic time remain ordered;
2. the final state is quiescent;
3. embedded observer and tracker provenance is stable;
4. observer and tracker summaries continue to show the expected pressure
   transitions for `dispatch.pressure` and `dispatch.sustained`;
5. the artifact remains accepted by the shared pressure-provider contract.
