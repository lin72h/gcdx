# M15 Pressure Provider Contract

## Purpose

This document records the repo-owned machine-readable contract for the current
pressure-only provider artifacts.

It does not introduce a live SPI or ABI.

Its job is narrower:

1. make the provider boundary self-describing inside the derived, live,
   adapter, session, observer, tracker, bundle, and preview artifacts;
2. give future consumers one checked-in contract file to build against;
3. stop the pressure-provider surface from drifting silently through docs,
   comparators, and baselines.

## Contract File

The checked-in contract lives at:

1. `benchmarks/contracts/m15-pressure-provider-contract-v1.json`

The contract version is now part of the artifacts themselves through the
top-level `contract` object.

## What The Contract Freezes

The current contract freezes these boundary decisions:

1. `provider_scope = pressure_only`
2. `current_signal_field = nonidle_workers_current`
3. `current_signal_kind = total_minus_idle`
4. `quiescence_kind = total_and_nonidle_zero`
5. `per_bucket_scope = diagnostic_only`
6. `diagnostic_fields = [active_workers_current]`

That means future work is not allowed to silently switch back to raw
`active_workers_current` as the main current-pressure signal.

## Conditional Per-Bucket Rule

Per-bucket diagnostics are still optional and flag-driven.

The contract now encodes that explicitly:

1. if `has_admission_feedback == true`, per-bucket diagnostics must carry
   `requested_workers` and `admitted_workers`
2. if `has_block_feedback == true`, per-bucket diagnostics must carry
   `blocked_workers` and `unblocked_workers`
3. if `has_live_current_counts == true`, per-bucket diagnostics must carry
   `total_workers_current`, `idle_workers_current`,
   `nonidle_workers_current`, and `active_workers_current`

This matters because the derived artifact does not record every category on
every mode. The contract must model that honestly instead of forcing fields
that the underlying mode never observed.

## Derived Versus Live Versus Adapter Versus Session Versus Observer Versus Tracker Versus Bundle Versus Preview

The same contract now applies to all current artifact families, but the timing
and rawness surfaces still differ:

1. derived artifact:
   synthetic generation, no monotonic timestamps
2. live artifact:
   monotonic generation sequence, real monotonic timestamps
3. adapter artifact:
   monotonic generation sequence, real monotonic timestamps, aggregate view v1
   above the raw snapshot and without per-bucket diagnostics
4. session artifact:
   monotonic generation sequence, real monotonic timestamps, callable
   session v1 owning the base snapshot and returning aggregate view v1
5. observer artifact:
   monotonic generation sequence, real monotonic timestamps, pressure observer
   v1 summary above callable session v1
6. tracker artifact:
   monotonic generation sequence, real monotonic timestamps, pressure
   transition tracker v1 summary above callable session v1
7. bundle artifact:
   monotonic generation sequence, real monotonic timestamps, callable bundle
   v1 combining one session poll with observer and tracker updates
8. preview artifact:
   monotonic generation sequence, real monotonic timestamps, raw snapshot v1
   capture below the higher-level projections

Those differences are part of the contract file too, so the artifacts stay
self-describing without pretending they are already a direct queryable SPI.

## Validation Surface

The repo now has a first-class contract check:

1. `scripts/benchmarks/validate-m15-pressure-provider-contract.py`
2. `scripts/benchmarks/run-m15-pressure-provider-contract-check.sh`
3. `TwqTest.PressureProviderContract`

The contract lane validates all checked-in artifact families:

1. the derived pressure-provider baseline
2. the live pressure-provider smoke baseline
3. the aggregate adapter pressure-provider smoke baseline
4. the callable session pressure-provider smoke baseline
5. the observer pressure-provider smoke baseline
6. the tracker pressure-provider smoke baseline
7. the bundle pressure-provider smoke baseline
8. the raw preview pressure-provider smoke baseline

## Exit Rule

This contract lane stays healthy only if:

1. all artifact families carry the same top-level `contract` object
2. all artifact families still satisfy the checked-in contract file
3. conditional per-bucket fields stay aligned with their feedback flags
4. session-only callable surface fields stay versioned and explicit instead of
   silently turning the prep lane into a placement decision
5. observer-only summary provenance stays versioned and explicit instead of
   silently bypassing the callable session surface
6. tracker-only transition summary provenance stays versioned and explicit
   instead of silently bypassing the callable session surface
7. bundle-only combined summary provenance stays versioned and explicit
   instead of silently becoming a TBBX or TCM policy object
8. preview-only raw snapshot fields stay versioned and explicit instead of
   leaking upward as accidental contract growth
9. any future widening of the surface becomes an explicit contract version
   change, not a silent shape drift
