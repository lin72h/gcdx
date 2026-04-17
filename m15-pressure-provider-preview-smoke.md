# M15 Pressure Provider Preview Smoke

## Purpose

This lane validates the repo-local raw snapshot preview surface that now sits
below the derived and live pressure-only artifacts.

It does not claim a provider SPI or ABI.

Its job is narrower:

1. prove that a versioned C snapshot shape can be read directly in the guest;
2. prove that the snapshot shape stays pressure-only even when it is closer to
   raw `kern.twq.*` state;
3. keep that raw preview shape repo-owned and comparable before any private
   SPI preview is proposed.

## Preview Surface

The preview probe emits `raw_snapshot_v1` captures for:

1. `dispatch.pressure`
2. `dispatch.sustained`

Each raw snapshot includes:

1. a versioned `struct_size` and `version`
2. `bucket_count`
3. real `CLOCK_MONOTONIC` nanoseconds
4. cumulative request/admit/block/unblock lifecycle counters
5. current worker totals:
   `total_workers_current`, `idle_workers_current`,
   `nonidle_workers_current`, `active_workers_current`
6. per-bucket arrays for those same counter/current categories

The current-pressure rule stays the same as the higher-level artifacts:

1. `nonidle_workers_current = total_workers_current - idle_workers_current`
   is the frozen current-pressure signal
2. raw `active_workers_current` remains diagnostic-only

## Why This Exists

The derived lane proved that a pressure-only boundary can be projected from the
checked-in crossover artifact.

The live lane proved that a guest-side probe can emit the same pressure-only
boundary with real sequencing and real monotonic time.

This preview lane closes the remaining gap before any SPI discussion:

1. it proves there is a stable raw versioned snapshot shape underneath those
   projections;
2. it keeps that shape explicitly below any real consumer contract;
3. it prevents future SPI work from jumping straight from markdown to ABI.

## Exit Rule

This lane is green only if:

1. the checked-in preview baseline and a fresh candidate agree on the raw
   preview boundary shape;
2. generation stays contiguous and monotonic time stays increasing;
3. cumulative counters stay non-decreasing;
4. pressure signals stay above the minimum live floor for both capture modes;
5. the final quiescence rule returns both `total_workers_current` and
   `nonidle_workers_current` to zero.
