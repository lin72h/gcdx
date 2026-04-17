# M15 Pressure Provider Observer Smoke

## Purpose

This lane validates a policyless observer summary that sits above the aggregate
adapter view and below any real consumer integration.

It does not claim a provider SPI, a consumer ABI, or a scheduler policy.

Its job is narrower:

1. prove that the aggregate pressure-only view is sufficient for a consumer to
   track pressure state over time;
2. keep that consumer-side proof free of queue semantics, permit vocabulary,
   or bucket promotion;
3. make future consumer work start from a tested observer summary instead of
   jumping straight from provider artifacts to runtime integration.

## Observer Surface

The observer probe emits `pressure_observer_v1` summaries for:

1. `dispatch.pressure`
2. `dispatch.sustained`

Each summary carries:

1. versioned observer metadata: `struct_size` and `version`
2. source aggregate-view metadata:
   `source_view_struct_size` and `source_view_version`
3. sequencing checks:
   `sample_count`, `generation_first`, `generation_last`,
   `generation_contiguous`, `monotonic_increasing`
4. pressure-state sample counts:
   `pressure_visible_samples`, `nonidle_samples`,
   `request_backlog_samples`, `block_backlog_samples`,
   `narrow_feedback_samples`, and `quiescent_samples`
5. maxima for the frozen current-pressure and backlog signals:
   `max_nonidle_workers_current`, `max_request_backlog_total`,
   and `max_block_backlog_total`
6. final-state checks:
   `final_total_workers_current`, `final_idle_workers_current`,
   `final_nonidle_workers_current`, `final_active_workers_current`,
   `final_pressure_visible`, and `final_quiescent`

The current-pressure rule stays unchanged:

1. `nonidle_workers_current` is the main live current-pressure signal
2. raw `active_workers_current` remains diagnostic-only

## Why This Exists

The derived lane proved the pressure-only boundary could be projected from the
checked-in crossover artifact.

The live lane proved the same boundary could be emitted in-guest with real
generation and monotonic time.

The raw preview lane proved there is a stable struct-shaped snapshot below the
higher-level projections.

The aggregate adapter lane proved there is also a stable versioned C view above
that raw snapshot.

This observer lane closes the next gap:

1. it proves a consumer can summarize pressure behavior from the aggregate-only
   view without any bucket promotion;
2. it keeps that consumer proof pressure-only and policyless;
3. it still stops short of a real consumer/runtime integration.

## Exit Rule

This lane is green only if:

1. a fresh guest run matches the checked-in observer baseline with
   `verdict=ok`
2. generation stays contiguous and monotonic time stays increasing
3. the observer struct metadata stays stable and still records the aggregate
   view as its source surface
4. both `dispatch.pressure` and `dispatch.sustained` preserve the expected
   pressure floor and backlog visibility
5. final quiescence returns `total_workers_current` and
   `nonidle_workers_current` to zero without requiring `final_pressure_visible`
   itself to become false
