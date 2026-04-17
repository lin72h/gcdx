# M15 Pressure Provider Adapter Smoke

## Purpose

This lane validates a repo-local aggregate adapter view that sits above the raw
preview snapshot and below any real provider SPI or ABI.

It does not claim a system integration surface.

Its job is narrower:

1. prove that the raw snapshot can be converted into a stable aggregate-only C
   view inside the guest;
2. keep that aggregate view pressure-only and consumer-shaped;
3. make future SPI work start from a tested adapter surface instead of jumping
   straight from markdown to ABI.

## Adapter Surface

The adapter probe emits `aggregate_view_v1` captures for:

1. `dispatch.pressure`
2. `dispatch.sustained`

Each sample carries:

1. versioned `struct_size` and `version`
2. real `CLOCK_MONOTONIC` nanoseconds
3. the frozen aggregate pressure fields:
   `request_events_total`, `worker_entries_total`,
   `worker_returns_total`, `requested_workers_total`,
   `admitted_workers_total`, `blocked_events_total`,
   `unblocked_events_total`, `blocked_workers_total`,
   `unblocked_workers_total`, `total_workers_current`,
   `idle_workers_current`, `nonidle_workers_current`,
   `active_workers_current`, `should_narrow_true_total`,
   `request_backlog_total`, and `block_backlog_total`
4. flag fields with `has_per_bucket_diagnostics = false`

The current-pressure rule stays the same:

1. `nonidle_workers_current = total_workers_current - idle_workers_current`
   is the main current-pressure signal
2. raw `active_workers_current` remains diagnostic-only

## Why This Exists

The derived lane proved that a pressure-only boundary can be projected from the
checked-in crossover artifact.

The live lane proved that a guest probe can emit that boundary with real
generation and real monotonic time.

The raw preview lane proved that there is a stable versioned snapshot below
those projections.

This adapter lane closes the next gap:

1. it proves there is also a versioned aggregate-only C view above the raw
   snapshot;
2. it strips per-bucket details out of the consumer-shaped surface while
   keeping the pressure-only contract intact;
3. it still stops short of a real SPI claim.

## Exit Rule

This lane is green only if:

1. a fresh guest run matches the checked-in adapter baseline with `verdict=ok`
2. generation stays contiguous and monotonic time stays increasing
3. the adapter struct metadata stays stable
4. `dispatch.pressure` and `dispatch.sustained` both preserve the expected
   pressure floor
5. quiescence returns both `total_workers_current` and
   `nonidle_workers_current` to zero
