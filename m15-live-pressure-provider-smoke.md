# M15 Live Pressure Provider Smoke

## Purpose

This lane is the first guest-side live confirmation of the pressure-only
provider boundary prepared after `M13` closeout.

It does not claim a provider SPI or ABI.

It exists to prove three narrower things:

1. the guest can emit a pressure-only live view with real generation numbers;
2. the guest can emit real monotonic timestamps for that live view;
3. the boundary can stay pressure-only without exposing queue semantics or
   permit vocabulary.

## Scope

This lane is intentionally limited to:

1. `dispatch.pressure`
2. `dispatch.sustained`

Those two workloads are enough to exercise:

1. request/admit growth
2. block/unblock growth
3. current worker counts
4. backlog visibility
5. retirement back to quiescence

## Boundary Rules

The rules stay the same as the derived prep lane:

1. pressure upward, mechanism downward
2. no raw queue semantics in the artifact
3. no TCM or permit vocabulary
4. per-bucket detail is diagnostic only
5. no scheduler or run-queue hooks

What changes relative to the derived lane:

1. `capture_kind` is now `live_probe`
2. `generation_kind` is now `monotonic_sequence`
3. `monotonic_time_kind` is now `clock_monotonic`

What still does not change:

1. this is still not a live provider SPI
2. this is still not a stable ABI promise
3. this is still probe-scoped validation, not consumer integration

## Current-Pressure Rule

The live smoke boundary now treats:

1. `nonidle_workers_current = total_workers_current - idle_workers_current`
   as the effective live current-pressure signal;
2. raw `active_workers_current` only as supporting continuity detail;
3. `final_total_workers_current == 0` and
   `final_nonidle_workers_current == 0` as the quiescence rule for the live
   lane.

This keeps the pressure-only boundary honest. Earlier live captures already
showed cases where total workers were present, idle workers were zero, and raw
`active_workers_current` still stayed at zero. Treating raw active counts as
the main signal would therefore understate real in-flight pressure.

The machine-readable contract for that rule now lives at:

1. `benchmarks/contracts/m15-pressure-provider-contract-v1.json`

The live artifact now carries the same top-level `contract` object as the
derived artifact, so this rule is embedded in the data and not left only in
markdown.

## Artifact Shape

Top-level shape:

1. `schema_version`
2. `provider_scope = pressure_only`
3. `capture_kind = live_probe`
4. `metadata.generation_kind = monotonic_sequence`
5. `metadata.monotonic_time_kind = clock_monotonic`
6. `metadata.label_count`

Per-capture required fields:

1. `label`
2. `sample_count`
3. `generation_first`
4. `generation_last`
5. `generation_contiguous`
6. `monotonic_increasing`
7. `interval_ms`
8. `duration_ms`
9. pressure summary maxima
10. final current-count values

The maxima and final current-count values are now expected to include
`nonidle_workers_current` alongside the older raw active field.

## Current Exit Rule

This smoke lane is green only if:

1. generation stays contiguous for every capture
2. monotonic time stays increasing for every capture
3. the checked-in live baseline and a fresh candidate agree on the boundary
   shape
4. the fresh candidate stays above the minimum signal floor for pressure
   visibility and cumulative pressure metrics
5. the fresh candidate returns both total and non-idle current worker counts
   to zero by the end of the capture

## Why This Exists

The derived pressure-provider prep lane proved that the checked-in crossover
artifact already contains enough data to define the pressure-only boundary.

This live smoke lane proves the next narrower claim:

the guest can emit the same kind of boundary with real sequencing and real
monotonic time, without pretending that the project already has a final live
provider SPI.

The raw snapshot preview lane now sits one level below this live lane:

1. [m15-pressure-provider-preview-smoke.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-pressure-provider-preview-smoke.md)

That preview stays closer to versioned `kern.twq.*` state, while this live
lane remains the higher-level pressure-only projection.
