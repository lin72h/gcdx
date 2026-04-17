# M15 Pressure-Provider Prep

## Purpose

This document defines the post-`M13` pressure-provider prep boundary.

It does not introduce a live SPI yet.

It records the first repo-owned pressure-only view that future upper-layer
consumers can rely on while the mechanism layer remains free of TCM, permit,
or scheduler-policy vocabulary.

The machine-readable contract for that boundary now lives at:

1. `benchmarks/contracts/m15-pressure-provider-contract-v1.json`

## What This Lane Is

The current lane is:

1. a derived artifact view built from the checked-in full-matrix crossover
   artifact;
2. pressure-only by design;
3. stable enough to compare across runs;
4. explicit about what data is real, what data is synthetic, and what is still
   unavailable.

The current lane is not:

1. a live ABI or SPI commitment;
2. a promise that a user-space consumer can query this structure directly;
3. a license to leak queue semantics or permit vocabulary into `TWQ`,
   `libthr`, or staged `libdispatch`.

## What The Derived View Exposes

Each snapshot is scoped to one existing benchmark mode and exposes only the
pressure-facing surface that is already observable from the crossover
artifact:

1. aggregate request counts;
2. aggregate worker entry and return counts;
3. aggregate admitted-versus-requested worker counts when that information is
   available;
4. aggregate block and unblock counts when that information is available;
5. current worker totals, idle totals, and effective non-idle totals when the
   underlying mode records them;
6. narrowing feedback through `should_narrow_true_total`;
7. derived backlog totals:
   `request_backlog_total` and `block_backlog_total`;
8. raw `active_workers_current` only as supporting continuity detail when it
   is present;
9. per-bucket arrays only as diagnostics.

## What This Lane Explicitly Does Not Expose

The current derived view must not expose:

1. raw queue internals;
2. staged `libdispatch` queue-object or continuation semantics;
3. scheduler hooks;
4. run-queue state;
5. TCM permit vocabulary;
6. any fake monotonic timestamp or fake live generation source.

If a future provider needs those, it is a new design question, not an
extension of this derived lane.

## Synthetic Versus Real Fields

The current pressure-provider artifact is deliberately honest about what it can
and cannot claim.

### Real

These fields come from the current schema-3 crossover artifact:

1. per-mode workload tuple;
2. `status`;
3. all aggregate `kern.twq.*`-derived counts;
4. per-bucket diagnostics when present.

### Synthetic

These fields are generated only to provide stable ordering inside the derived
artifact:

1. `generation` is a synthetic sequence number based on a fixed mode order;
2. `metadata.generation_kind` is therefore `synthetic_sequence`.

### Unavailable In The Derived View

These fields are intentionally left unavailable:

1. `monotonic_time_ns` is `null`;
2. `metadata.monotonic_time_kind` is
   `unavailable_in_derived_view`.

The current lane must not invent live timestamps just to make the shape look
more complete than it is.

## Design Rule

The design rule for this prep lane is:

1. expose pressure upward;
2. keep mechanism downward;
3. keep diagnostic detail optional;
4. do not let future consumer vocabulary contaminate the mechanism layer.

In practical terms:

1. aggregate pressure signals are the contract;
2. `nonidle_workers_current = total_workers_current - idle_workers_current` is
   the effective current-pressure signal for this boundary;
3. per-bucket detail is diagnostic only;
4. queue semantics remain internal;
5. any future live SPI should start from this boundary, not from raw internal
   structures.

That same rule is now carried in the artifact's top-level `contract` object,
not only in this document.

## Exit Rule

This prep lane is healthy only if:

1. the checked-in derived baseline remains reproducible from the checked-in
   crossover artifact;
2. the repo-owned comparison lane stays green;
3. the top-level shape remains pressure-only and explicitly derived;
4. no future patch widens the lane into queue or permit semantics without a
   separate design decision.
