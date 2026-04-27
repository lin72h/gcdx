# M15 Pressure Provider Observer Replay

## Purpose

This lane validates that the checked-in session artifact is sufficient to
reconstruct the checked-in observer summary without booting a guest again.

It does not add a new provider surface.

Its job is narrower:

1. prove that the session artifact carries enough information to recreate the
   policyless observer summary offline;
2. keep that sufficiency proof above the session surface and below any real
   consumer/runtime integration;
3. give future consumer work a host-side replay lane instead of forcing every
   change through a new guest boot.

## Replay Surface

The replay lane reads:

1. `benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json`

and derives an observer artifact with the same pressure-only shape as the
checked-in observer baseline:

1. `observer_kind = pressure_observer_v1`
2. `source_session_kind = callable_session_v1`
3. `source_view_kind = aggregate_view_v1`

The derived summary keeps the same sequencing, backlog, pressure, and
quiescence semantics as the guest-side observer lane.

## Why This Exists

The guest-side observer lane proves that the live stack can emit a valid
observer summary.

This replay lane closes a different gap:

1. it proves the session artifact itself is sufficient input for that summary;
2. it makes observer validation cheaper and more reusable on the host;
3. it avoids promoting the observer into a real integration surface just to
   get repeatable consumer-side checks.

## Exit Rule

This lane is green only if:

1. the checked-in observer baseline and the session-derived replay candidate
   compare with `verdict=ok`
2. both labels remain present:
   `dispatch.pressure` and `dispatch.sustained`
3. session provenance remains explicit through `source_session_kind`,
   `source_session_struct_size`, and `source_session_version`
4. final quiescence returns `total_workers_current` and
   `nonidle_workers_current` to zero
