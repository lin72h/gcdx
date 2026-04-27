# M15 Pressure Provider Session Smoke

## Purpose

This lane validates a repo-local callable session surface that sits above the
aggregate adapter view and below any real provider SPI or ABI claim.

It does not choose where a future system SPI should live.

Its job is narrower:

1. prove that a pressure-only caller can own baseline snapshot state and
   generation sequencing inside the guest;
2. keep that callable surface aligned with the same aggregate-only pressure
   view already validated by the adapter lane;
3. make future SPI work start from a tested callable shape instead of jumping
   straight from docs or comparators to placement decisions.

## Session Surface

The session probe emits `callable_session_v1` captures for:

1. `dispatch.pressure`
2. `dispatch.sustained`

Each sample carries:

1. versioned session metadata:
   `struct_size`, `version`, `source_snapshot_struct_size`,
   `source_snapshot_version`, `bucket_count`, `next_generation`, and `primed`
2. versioned aggregate-view metadata:
   `view.struct_size` and `view.version`
3. real `CLOCK_MONOTONIC` nanoseconds
4. the frozen aggregate pressure fields through `view.aggregate`:
   `request_events_total`, `worker_entries_total`,
   `worker_returns_total`, `requested_workers_total`,
   `admitted_workers_total`, `blocked_events_total`,
   `unblocked_events_total`, `blocked_workers_total`,
   `unblocked_workers_total`, `total_workers_current`,
   `idle_workers_current`, `nonidle_workers_current`,
   `active_workers_current`, `should_narrow_true_total`,
   `request_backlog_total`, and `block_backlog_total`
5. the same pressure-only flag set through `view.flags`

The current-pressure rule stays unchanged:

1. `nonidle_workers_current` is the main live current-pressure signal
2. raw `active_workers_current` remains diagnostic-only

## Why This Exists

The derived lane proved that a pressure-only boundary could be projected from
the checked-in crossover artifact.

The live lane proved that the same boundary could be emitted in-guest with
real generation and monotonic time.

The raw preview lane proved there is a stable versioned snapshot below those
projections.

The aggregate adapter lane proved there is also a stable aggregate-only C view
above that raw snapshot.

This session lane closes the next gap:

1. it proves there is also a callable pressure-only surface above the adapter
   view;
2. it lets the caller own baseline state and generation sequencing without
   promoting bucket details or queue semantics;
3. it still stops short of any real SPI placement claim.

## Exit Rule

This lane is green only if:

1. a fresh guest run matches the checked-in session baseline with
   `verdict=ok`
2. generation stays contiguous and monotonic time stays increasing
3. session and view struct metadata stay stable
4. all samples remain primed and `next_generation` stays consistent with the
   emitted view sequence
5. quiescence returns both `total_workers_current` and
   `nonidle_workers_current` to zero
