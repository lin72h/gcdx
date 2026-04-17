# CHANGELOG

## 2026-04-17

### Pressure observer smoke is now repo-owned above the aggregate adapter view

The pressure-only boundary now has a first consumer-side proof lane: a
policyless observer summary above the aggregate adapter surface and below any
real SPI or integration claim.

What changed:

1. [twq_pressure_provider_observer.h](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_observer.h),
   [twq_pressure_provider_observer.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_observer.c),
   and
   [twq_pressure_provider_observer_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_observer_probe.c)
   now define and emit a versioned observer summary above
   `aggregate_view_v1`;
2. [extract-m15-pressure-provider-observer.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/extract-m15-pressure-provider-observer.py),
   [compare-m15-pressure-provider-observer-smoke.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/compare-m15-pressure-provider-observer-smoke.py),
   and
   [run-m15-pressure-provider-observer-smoke.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/run-m15-pressure-provider-observer-smoke.sh)
   now provide the repo-owned observer smoke lane;
3. the first checked-in observer baseline now lives at
   [m15-pressure-provider-observer-smoke-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json);
4. [m15-pressure-provider-observer-smoke.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-pressure-provider-observer-smoke.md)
   now records the observer boundary explicitly, and the lane is visible to
   ExUnit through `TwqTest.PressureProviderObserver` plus
   `TwqTest.VM.run_m15_pressure_provider_observer_smoke/1`.

What this work proved:

1. the aggregate adapter view is sufficient for a consumer-side summary
   without promoting per-bucket diagnostics;
2. quiescence can be tracked honestly at the consumer edge through
   `total_workers_current == 0 && nonidle_workers_current == 0` while
   `final_pressure_visible` remains independent;
3. a fresh full guest observer run passes against the checked-in baseline with
   `verdict=ok`.

### Aggregate adapter pressure-provider smoke is now repo-owned and contract-checked

The pressure-only boundary now has a fourth repo-owned artifact family: a
versioned aggregate adapter view above the raw preview snapshot and below any
real SPI claim.

What changed:

1. [twq_pressure_provider_adapter.h](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_adapter.h),
   [twq_pressure_provider_adapter.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_adapter.c),
   and
   [twq_pressure_provider_adapter_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_adapter_probe.c)
   now define and emit the repo-local aggregate view v1;
2. [twq_pressure_provider_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_probe.c)
   now reuses that adapter builder for its aggregate mapping instead of
   carrying a second copy of the same logic;
3. [extract-m15-pressure-provider-adapter.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/extract-m15-pressure-provider-adapter.py),
   [compare-m15-pressure-provider-adapter-smoke.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/compare-m15-pressure-provider-adapter-smoke.py),
   and
   [run-m15-pressure-provider-adapter-smoke.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/run-m15-pressure-provider-adapter-smoke.sh)
   now provide the repo-owned adapter smoke lane;
4. [m15-pressure-provider-adapter-smoke-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json)
   is the first checked-in adapter baseline;
5. the machine-readable contract and contract-check lane now cover the
   derived, live, adapter, and preview families instead of only the earlier
   three;
6. [m15-pressure-provider-adapter-smoke.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-pressure-provider-adapter-smoke.md)
   records the adapter boundary explicitly, and the same lane is visible to
   ExUnit through `TwqTest.PressureProviderAdapter` and
   `TwqTest.VM.run_m15_pressure_provider_adapter_smoke/1`.

What this work proved:

1. a fresh guest bootstrap run produced a stable adapter artifact for both
   `dispatch.pressure` and `dispatch.sustained`;
2. the checked-in adapter baseline self-compares cleanly with `verdict=ok`;
3. the contract lane now validates all four current artifact families with
   `verdict=ok`.

### Raw preview pressure-provider smoke is now repo-owned and contract-checked

The pressure-only boundary now has a third artifact family below the earlier
derived and live views: a raw preview smoke lane built around a versioned C
snapshot shape.

What changed:

1. [twq_pressure_provider_preview.h](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_preview.h)
   and
   [twq_pressure_provider_preview.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_preview.c)
   now define the repo-local raw snapshot v1 shape for current pressure data;
2. [twq_pressure_provider_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_probe.c)
   now reuses that shared snapshot reader instead of carrying its own
   duplicated sysctl parsing path;
3. [twq_pressure_provider_preview_probe.c](/Users/me/wip-gcd-tbb-fx/wip-codex54x/csrc/twq_pressure_provider_preview_probe.c),
   [extract-m15-pressure-provider-preview.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/extract-m15-pressure-provider-preview.py),
   [compare-m15-pressure-provider-preview-smoke.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/compare-m15-pressure-provider-preview-smoke.py),
   and
   [run-m15-pressure-provider-preview-smoke.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/run-m15-pressure-provider-preview-smoke.sh)
   now provide the repo-owned raw preview smoke lane;
4. the first checked-in raw preview baseline now lives at
   [m15-pressure-provider-preview-smoke-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json);
5. the machine-readable contract and contract-check lane now cover the
   derived, live, and preview artifact families instead of only the earlier
   two;
6. [m15-pressure-provider-preview-smoke.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-pressure-provider-preview-smoke.md)
   now records the preview boundary explicitly, and the same lane is visible
   to ExUnit through `TwqTest.PressureProviderPreview` and
   `TwqTest.VM.run_m15_pressure_provider_preview_smoke/1`.

What this work proved:

1. a fresh full guest run now passes against the checked-in preview baseline
   with `verdict=ok`;
2. the preview shape stays pressure-only while carrying real generation,
   real monotonic time, and versioned raw snapshot structure;
3. the repo now has a contract-checked raw boundary below the higher-level
   pressure projections without prematurely claiming a callable SPI.

### Pressure-provider contract v1 is now machine-readable and repo-owned

The pressure-provider boundary is no longer defined only by docs plus two
comparators. The repo now has a checked-in machine-readable contract for that
surface.

What changed:

1. the checked-in contract now lives at
   [m15-pressure-provider-contract-v1.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/contracts/m15-pressure-provider-contract-v1.json);
2. both `extract-m15-pressure-provider.py` and
   `extract-m15-live-pressure-provider.py` now stamp a shared top-level
   `contract` object into their artifacts;
3. the live extractor now also normalizes missing
   `aggregate.nonidle_workers_current` and
   `diagnostics.per_bucket.nonidle_workers_current` fields when regenerating
   from older serial logs, so raw snapshots and summary fields no longer drift
   apart;
4. `validate-m15-pressure-provider-contract.py` and
   `run-m15-pressure-provider-contract-check.sh` now provide the repo-owned
   contract-validation lane for both the derived and live baselines;
5. `TwqTest.PressureProviderContract` now exposes the same contract check to
   ExUnit.

What this work found and fixed:

1. the first contract validator was too strict: it treated every per-bucket
   field as unconditional whenever diagnostics existed;
2. that was wrong for the derived artifact, where per-bucket content is
   conditional on the feedback flags for the mode;
3. the contract now encodes per-bucket requirements by flag:
   admission, block, and live-current fields are only required when the
   corresponding feedback flag is true.

What the new lane proved:

1. the checked-in derived provider baseline conforms to the same contract as
   the live smoke baseline;
2. the live baseline now carries `nonidle_workers_current` consistently both
   in summary fields and in per-snapshot aggregates/diagnostics;
3. the repo now has a stable machine-readable boundary for future consumers
   without claiming a system SPI.

### Pressure-provider boundary now uses non-idle current as the live signal

The pressure-provider lanes no longer treat raw `active_workers_current` as the
main current-pressure signal.

What changed:

1. both `extract-m15-pressure-provider.py` and
   `csrc/twq_pressure_provider_probe.c` now expose
   `nonidle_workers_current = total_workers_current - idle_workers_current`
   as the effective current-pressure field;
2. both the derived and live baselines were regenerated so that
   `nonidle_workers_current` is now part of the checked-in pressure-only
   boundary;
3. the live smoke comparator and Elixir wrappers now gate quiescence on
   `final_total_workers_current` and `final_nonidle_workers_current` instead
   of pretending that raw `active_workers_current` alone is the decisive
   signal;
4. raw `active_workers_current` is still emitted and compared, but now only as
   supporting detail for continuity with the earlier `kern.twq.*` view.

What this work found:

1. the earlier live smoke captures already showed a real mismatch in signal
   strength:
   `total_workers_current > 0` with `idle_workers_current = 0` while raw
   `active_workers_current` often remained `0`;
2. that meant the older boundary was too weak for current-pressure semantics
   even though the guest was clearly carrying non-idle workers;
3. promoting `nonidle_workers_current` fixes that honesty gap without claiming
   any new SPI or widening the boundary into queue semantics.

What the updated lanes proved:

1. the derived pressure-provider lane still re-derives and compares cleanly
   against the checked-in crossover artifact with `verdict=ok`;
2. the fresh guest live smoke rerun now passes cleanly against the updated
   live baseline with `verdict=ok`;
3. the repo now has a stronger current-pressure boundary while still staying
   pressure-only and probe-scoped.

### Live pressure-provider smoke is now a repo-owned lane

The project now has a guest-side live pressure-provider smoke lane instead of
only the earlier derived pressure-only prep artifact.

What changed:

1. `csrc/twq_pressure_provider_probe.c` now emits live pressure snapshots in
   the guest with real generation numbers and real monotonic timestamps;
2. `scripts/bhyve/stage-guest.sh` now stages the optional live
   pressure-provider probe and wraps the existing `dispatch.pressure` and
   `dispatch.sustained` modes with capture start/wait helpers;
3. `extract-m15-live-pressure-provider.py`,
   `compare-m15-live-pressure-provider-smoke.py`, and
   `run-m15-live-pressure-provider-smoke.sh` now provide the repo-owned
   extract/compare/run lane for this live artifact;
4. the first checked-in live baseline now lives at
   [m15-live-pressure-provider-smoke-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json);
5. `TwqTest.LivePressureProvider` and
   `TwqTest.VM.run_m15_live_pressure_provider_smoke/1` now expose the same
   live lane to ExUnit and the host harness;
6. [m15-live-pressure-provider-smoke.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-live-pressure-provider-smoke.md)
   now records the live boundary explicitly:
   pressure-only, probe-scoped, real generation and monotonic time, still no
   SPI claim.

What this work found and fixed:

1. the first live guest bootstrap failed immediately with `EPROTO` at the
   base snapshot stage because the new probe was incorrectly treating numeric
   `sysctlbyname()` results as text;
2. the fix was to use typed numeric reads for scalar `kern.twq.*` counters
   and keep text parsing only for the comma-delimited bucket arrays, matching
   the already-working probe pattern elsewhere in the repo;
3. the live comparator also had an incorrect zero-baseline rule:
   zero-valued minimum-ratio metrics were being forced to `1.0`, which made a
   self-compare fail for legitimate `active_workers_current = 0` captures;
4. that policy is now corrected, so zero-baseline live metrics remain
   representable without false failures.

What the live lane proved:

1. the guest now emits real live pressure snapshots for both
   `dispatch.pressure` and `dispatch.sustained`;
2. the checked-in live baseline captures contiguous generation sequences,
   increasing monotonic timestamps, pressure visibility, and eventual return
   to zero current-worker counts;
3. the repo-owned live smoke lane can now validate that shape in reuse mode
   and in full guest mode without pretending that the project already has a
   final provider SPI.

### Post-M13 pressure-provider prep is now a repo-owned lane

The project now has a repo-owned derived pressure-provider lane for future
upper-layer consumers instead of only a design note about what should sit
above `GCDX`.

What changed:

1. `scripts/benchmarks/extract-m15-pressure-provider.py` now derives a
   pressure-only provider artifact from the checked-in schema-3 crossover
   baseline instead of inventing a new guest probe;
2. `scripts/benchmarks/compare-m15-pressure-provider-baseline.py` now checks
   both aggregate pressure values and the boundary shape itself:
   `schema_version`, `provider_scope`, synthetic generation semantics, and the
   explicit absence of live monotonic timestamps;
3. `scripts/benchmarks/run-m15-pressure-provider-prep.sh` now provides the
   repo-owned shell lane:
   reuse an existing crossover artifact or generate one, derive the provider
   view, compare it against the checked-in baseline, and emit
   `comparison.json`, `comparison.log`, and `summary.md`;
4. the first checked-in pressure-only baseline now lives at
   [m15-pressure-provider-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m15-pressure-provider-20260417.json);
5. `TwqTest.PressureProvider` and
   `TwqTest.VM.run_m15_pressure_provider_prep/1` now expose the same derived
   boundary to ExUnit and the host harness;
6. [m15-pressure-provider-prep.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m15-pressure-provider-prep.md)
   now records the boundary explicitly:
   pressure upward, mechanism downward, per-bucket detail diagnostic only, no
   fake live timestamps, and no TCM vocabulary leaking into `TWQ`.

What the lane proved:

1. the checked-in crossover baseline now deterministically reproduces the
   checked-in pressure-only provider baseline in reuse mode;
2. the repo-owned shell lane completes cleanly with `verdict=ok`;
3. the project now has a stable pressure-only prep surface for future
   consumers without claiming that a live provider SPI already exists.

Current consequence:

1. `M13` no longer ends at "the current floor is green";
2. the post-`M13` state now has a concrete upward-facing prep boundary for
   future pressure consumers;
3. future integration work can start from this pressure-only surface instead
   of reaching directly into raw `TWQ` or staged `libdispatch` internals.

### M13 formal closeout is now a repo-owned top-level lane

The project now has a single repo-owned command for deciding whether `M13` is
actually closeable.

What changed:

1. `scripts/benchmarks/run-m13-closeout.sh` now runs the three current
   closeout conditions together:
   the low-level one-boot gate, the focused repeat-lane gate, and the
   `M13.5` full-matrix crossover assessment;
2. the low-level gate is now composable in the same way as the repeat and
   crossover lanes:
   `run-m13-lowlevel-gate.sh` accepts an existing candidate JSON, emits a
   structured `comparison.json`, and writes a fuller markdown summary;
3. `compare-m13-lowlevel-baseline.py` now supports `--json-out` and emits a
   durable verdict payload instead of only a process exit code;
4. `TwqTest.VM.run_m13_closeout/1` and
   `TwqTest.VMM13CloseoutTest` now expose the same top-level closeout lane to
   ExUnit without forcing a guest boot.

What the new lane proved:

1. the low-level gate now passes cleanly in reuse mode with the checked-in
   combined suite baseline as both baseline and candidate;
2. the full `M13` closeout wrapper now completes in reuse mode with all three
   child lanes green and emits `verdict=close_m13`;
3. the closeout manifest is now written at
   `/tmp/gcdx-m13-closeout/closeout.json` with child-lane status and summary
   paths.

Current consequence:

1. there is now one repo-owned answer to the question "is M13 actually
   closeable?";
2. the project no longer needs to treat low-level, repeat, and crossover as
   three unrelated green boxes;
3. future work can assume the current `M13` floor only after the closeout
   lane remains green.

### M13.5 full-matrix crossover assessment is now a real repo-owned lane

The project now has a repo-owned closeout lane for the post-M13 state rather
than only the low-level floor, the focused repeat gate, and the M14 stop
result.

What changed:

1. `scripts/benchmarks/compare-m13-crossover-baseline.py` now compares the
   full current dispatch and Swift matrix against a checked-in crossover
   baseline;
2. `scripts/benchmarks/run-m13-crossover-assessment.sh` now provides the
   repo-owned `M13.5` lane:
   reuse an existing full-matrix artifact or generate a fresh guest run, then
   emit `comparison.json`, `comparison.log`, and `summary.md`;
3. the current full-matrix reference is now checked in as
   [m13-crossover-full-20260417.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-crossover-full-20260417.json);
4. `TwqTest.VM.run_m13_crossover_assessment/1` and
   `TwqTest.VMM13CrossoverAssessmentTest` now expose the same lane through the
   host harness;
5. `m13-5-crossover-boundary.md` now records what is stable, what is frozen,
   and what is explicitly deferred after the M13 and M14 work.

What the crossover work discovered:

1. the first broad rerun did not just show benchmark drift; it exposed a real
   staged-`libdispatch` correctness bug on the `dispatch.basic` lane;
2. the root cause was unsafe root-item classification on the default root
   queue:
   some root items are raw continuations, not vtable-backed dispatch objects,
   so hot-path code that reached `dx_metatype()` / `dx_type()` through those
   items could fault;
3. the current local staged `swift-corelibs-libdispatch` checkout now guards
   those root-item inspections before touching vtable-derived type metadata,
   and the full nine-mode matrix runs cleanly again.

What the repo-owned lane proved:

1. the new full baseline completes cleanly across:
   `dispatch.basic`, `dispatch.pressure`, `dispatch.burst-reuse`,
   `dispatch.timeout-gap`, `dispatch.sustained`,
   `dispatch.main-executor-resume-repeat`,
   `swift.dispatch-control`, `swift.mainqueue-resume`, and
   `swift.dispatchmain-taskhandles-after-repeat`;
2. a second fresh candidate now compares cleanly against that baseline through
   the repo-owned lane at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-crossover-assessment-20260417/summary.md`;
3. the shared-absence case for `thread_return_count` on
   `dispatch.basic` and `dispatch.pressure` is now treated as
   `not_applicable` instead of a false failure in the crossover comparator.

Current consequence:

1. `M13` now has a real closeout lane above the low-level floor and the
   focused repeat gate;
2. the project can judge future changes against the full current matrix rather
   than only against the repeat seam;
3. the next milestone can be chosen from a real external need instead of
   continuing blind repeat-lane tuning.

## 2026-04-16

### M14 compare tooling now produces repo-native decisions

The repo-side M14 comparison is no longer just a pair of ad hoc commands.

What changed:

1. `scripts/benchmarks/extract-m14-benchmark.py` now normalizes current macOS
   reports, current FreeBSD benchmark JSON, and raw FreeBSD serial logs into a
   single benchmark-first schema;
2. the same extractor now accepts richer FreeBSD inputs that already carry
   `full_run`, `steady_state`, or `per_round.rows` data, instead of assuming
   only the older M13 baseline shape;
3. `scripts/benchmarks/compare-m14-benchmarks.py` now distinguishes strict
   `1.50x` reporting from the intended “about `1.5x`” stop-tuning policy,
   defaulting that softer decision band to `1.65x`;
4. the compare CLI can now write one machine-readable JSON decision file with
   the same classification and ratio details it prints to stdout;
5. `scripts/benchmarks/run-m14-compare.sh` now runs the whole normalization +
   comparison lane into one artifact directory with normalized FreeBSD/macOS
   JSON plus a saved summary;
6. `fixtures/benchmarks/m14-*.json` and
   `scripts/benchmarks/verify-m14-tooling.py` now provide a fixture-backed
   verification lane for the `stop`, `tune`, and `inconclusive` outcomes;
7. `extract-m14-benchmark.py` and `run-m14-compare.sh` now treat FreeBSD
   round-snapshot artifacts as a first-class source kind instead of assuming
   only the older `benchmarks{}` JSON layout;
8. `discover-m14-artifacts.py` and `summarize-m14-compare.py` now provide
   input discovery plus a reviewable compare report, and the runner can use
   `TWQ_M14_FREEBSD_SOURCE=auto` / `TWQ_M14_MACOS_REPORT=auto`;
9. `compare-m14-benchmarks.py` now treats workload-match and metric-coverage
   validation as part of the decision itself, instead of letting superficially
   similar rates produce a confident result on a mismatched tuple;
10. `validate-m14-artifacts.py` and `m14_validation.py` now validate both raw
    and normalized M14 inputs, `discover-m14-artifacts.py` prefers
    comparison-ready candidates, and `run-m14-compare.sh` saves validation
    artifacts while rejecting malformed inputs before comparison;
11. `discover-m14-artifacts.py` now emits a pair-aware `pairs.best` selection,
    and `run-m14-compare.sh` uses that matched pair when both sides are
    `auto`, instead of picking the two sides independently;
12. `audit-m14-artifact-schema.py` and `m14_audit.py` now audit raw M14
    artifacts for unmapped workload, classification, full-run, steady-state,
    and per-round fields; validation surfaces that audit as warnings, discovery
    prefers lower-drift candidates, and the runner saves input audit artifacts.

What this fixes:

1. the earlier compare CLI would have judged the current
   `3.21 / round` FreeBSD vs `2.04 / round` macOS seam as merely
   `inconclusive`, even though the project’s own M14 note and native macOS
   report already treat that pair as within the intended “about `1.5x`”
   stop boundary;
2. the repo now has one repeatable lane for consuming an incoming FreeBSD M14
   artifact instead of relying on hand-entered command sequences;
3. the repo can now regression-check M14 tooling without depending on the
   presence of one specific local macOS or FreeBSD artifact tree;
4. the repo is now materially closer to accepting the expected
   `m14-round-snapshots-*.json` family directly, including shell-runner
   auto-detection for that filename pattern;
5. the repo can now discover likely M14 inputs and emit both a terse machine
   decision and a human-readable report artifact for review;
6. the repo will now keep a mismatched workload pair `inconclusive`, even if
   the per-round seam rates happen to sit inside the intended stop band;
7. the repo will now refuse malformed raw artifacts early, instead of
   normalizing and comparing them far enough to make debugging ambiguous;
8. the auto lane can now avoid a false “best artifact” pick when a newer local
   FreeBSD candidate is valid in isolation but mismatched against the macOS
   comparison tuple;
9. the first real FreeBSD M14 artifact can now arrive with new fields without
   forcing blind trust or immediate extractor surgery, because the lane will
   preserve a usable compare result while telling us exactly what it dropped.

### M14 macOS comparison lane landed

The repo now has a native macOS comparison lane for the M13 -> M14 decision,
instead of relying on one-off local notes.

What changed:

1. `swiftsrc/twq_swift_dispatchmain_taskhandles_after_repeat.swift` now builds
   on both FreeBSD and macOS, while keeping the same repeated delayed-child
   `dispatchMain()` workload shape;
2. a new native C calibration lane was added at
   `csrc/twq_macos_dispatch_resume_repeat.c` for the same
   `main-executor-resume-repeat` tuple on stock macOS;
3. `csrc/twq_macos_dispatch_introspection.c` and
   `csrc/twq_macos_dispatch_introspection.h` add a stock-binary
   introspection-backed counter shim for root-queue enqueue classification and
   worker-request counting on macOS;
4. `scripts/macos/prepare-m14.sh` now builds both macOS binaries plus the
   shared introspection shim with the Xcode-default toolchain;
5. `scripts/macos/check-m14-symbols.py` records stock symbol visibility,
   runtime `dlsym()` reachability, DTrace accessibility, and relevant
   `xctrace` support;
6. `scripts/macos/run-m14-stock.sh` now produces one artifact directory with
   raw logs, host metadata, normalized JSON, and a short summary;
7. `scripts/macos/run-m14-introspection.sh` now runs both workloads under
   `/usr/lib/system/introspection` and writes a comparison-ready report JSON;
8. `scripts/macos/extract-m14-run.py`,
   `scripts/macos/extract-m14-introspection-report.py`, and
   `scripts/macos/summarize-m14-run.py` preserve the steady-state
   `rounds 8-63` view instead of only totals;
9. `scripts/macos/README.md` now documents the stock-first path, the
   introspection path, and the fallback custom-build plan.

What the local macOS runs proved:

1. the native Swift repeat lane completes all `64` rounds with the matched
   `8` tasks and `20ms` delay tuple on macOS;
2. the native C control lane completes the same tuple too;
3. on this host, the stock SDK and runtime do not expose
   `_dispatch_root_queue_push`, `_dispatch_root_queue_poke_slow`,
   `_dispatch_queue_cleanup2`, or `_dispatch_lane_barrier_complete` as usable
   live symbols;
4. `_pthread_workqueue_addthreads` is still runtime-resolvable on the same
   host;
5. stock `dtrace` is blocked here by SIP / privilege limits, while `xctrace`
   is available only as a supporting tool.
6. the stock introspection runtime is sufficient on this host to classify
   default-root source traffic, default-overcommit main-queue handoff traffic,
   and worker-request rates for the M14 seam;
7. the local matched `64 x 8 x 20ms` run lands the Swift steady-state
   `mainq -> default.overcommit` rate at about `2.04 / round` on macOS,
   versus the FreeBSD reference `3.21 / round`, while the C control lane
   stays at `0 / round`.

Current consequence:

1. the repo now has both a stock-symbol reality lane and a stock-binary
   introspection lane for matched M14 comparison runs;
2. this host can answer the seam question without a custom libdispatch build:
   the Swift main-queue cleanup handoff shape is native on macOS too;
3. the remaining FreeBSD/macOS delta is closer to “about 1.5x” than to a
   “2x lower” macOS result, so this seam should not get more FreeBSD-side
   tuning by default;
4. a custom-build counter path remains the fallback only if some later M14
   question needs deeper attribution than stock introspection can provide.
### M13 repeat-lane gate is now a real repo-owned regression lane

The checked-in FreeBSD schema-3 repeat reference is no longer just a file plus
ad hoc comparison commands. The repo now has a first-class repeat-lane gate
that can generate a focused guest artifact, compare it against the checked-in
baseline, and expose the same policy to ExUnit.

What changed:

1. `scripts/benchmarks/run-m13-repeat-gate.sh` now provides the focused
   FreeBSD repeat-lane gate for
   `dispatch.main-executor-resume-repeat` and
   `swift.dispatchmain-taskhandles-after-repeat`;
2. `scripts/benchmarks/compare-m13-repeat-baseline.py` now compares those
   focused artifacts against the checked-in schema-3 baseline using the steady
   state window `8-63`;
3. `TwqTest.RepeatLane` and `TwqTest.VM.run_m13_repeat_gate/1` now expose the
   same repeat-lane policy to ExUnit and the host harness;
4. the guest wrapper bug that had prevented libdispatch round snapshots from
   appearing in focused repeat runs is now fixed:
   the outer benchmark wrappers set `TWQ_LIBDISPATCH_COUNTERS=1`, which is the
   staging-script input that becomes guest-side
   `LIBDISPATCH_TWQ_COUNTERS=1`;
5. `extract-m13-baseline.py` and the repeat comparators now align libdispatch
   per-round deltas by round number instead of requiring a perfect one-to-one
   snapshot list, so sparse-but-valid control-lane snapshot series no longer
   cause false gate failures.

What the end-to-end proof run showed:

1. the fresh guest gate artifact at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-repeat-gate-20260416T-final/m13-repeat-candidate.json`
   now carries non-empty libdispatch round snapshots for both repeat modes;
2. the fresh gate summary at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-repeat-gate-20260416T-final/summary.md`
   completes with `verdict=ok`;
3. the C control lane now compares cleanly again at steady state:
   `reqthreads_per_round=4.13`,
   `root_push_mainq_default_overcommit_per_round=0.00`, and
   `root_poke_slow_default_overcommit_per_round=0.00`;
4. the Swift repeat lane still stays within the checked-in band at steady
   state:
   `reqthreads_per_round=16.27`,
   `root_push_mainq_default_overcommit_per_round=2.98`, and
   `root_poke_slow_default_overcommit_per_round=2.98`.

Current consequence:

1. the schema-3 FreeBSD repeat reference is now protected by a repo-owned
   gate, not just by a checked-in JSON artifact;
2. the M14 stop result is now backed by a durable FreeBSD-side repeat guard as
   well as the repo-owned macOS comparison lane;
3. future work can move on from the closed main-queue to
   `default.overcommit` seam without losing the ability to catch repeat-lane
   regressions.

### M14 steady-state comparison is now a repo-owned runnable lane

The first stock-macOS stop result is no longer just a note plus ad hoc
artifacts. The repo now carries the FreeBSD reference, the macOS report, the
comparison command, and harness-visible checks as one durable lane.

What changed:

1. the current FreeBSD M14 repeat reference is now checked in as
   [m14-freebsd-round-snapshots-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json)
   instead of living only under the local artifacts directory;
2. `scripts/benchmarks/compare-m14-steady-state.py` now writes a structured
   comparison JSON in addition to the human-readable verdict summary;
3. `scripts/benchmarks/run-m14-comparison.sh` now provides the repo-owned
   M14 lane: reuse an existing FreeBSD repeat artifact or generate a focused
   one, compare it against the checked-in macOS report, and emit
   `comparison.json`, `comparison.log`, and `summary.md`;
4. `TwqTest.M14Comparison` now exposes the same stop/tune decision to ExUnit,
   while `TwqTest.Swift.run_m14_comparison/1` wraps the shell lane through the
   primary harness.

What the repo-owned lane proved:

1. comparing
   [m14-freebsd-round-snapshots-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json)
   against
   [m14-macos-stock-introspection-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-macos-stock-introspection-20260416.json)
   still produces `verdict=stop_tuning_this_seam`;
2. the primary steady-state rates remain the same checked-in stop result:
   about `3.21` vs `2.04` main-queue pushes per round and
   about `3.21` vs `2.04` `default.overcommit poke_slow` per round;
3. the shell lane now reproduces that verdict end to end at
   `/tmp/gcdx-m14-script/summary.md` without requiring any manual reconstruction.

Current consequence:

1. M14 is now a durable repo-owned comparison lane, not just a one-off MX
   coordination result;
2. the `mainq -> default.overcommit` seam remains closed as a tuning target;
3. future performance work can assume that decision and move on to other gaps.

### M13 now has a real workqueue wake benchmark gate

The project now has a guest-run benchmark for the warmed idle worker wakeup
path rather than only raw `TWQ` syscall timing.

What changed:

1. `csrc/twq_workqueue_wake_bench.c` now measures request-to-callback-start
   latency for a warmed idle worker under both constrained and overcommit
   priorities;
2. `scripts/bhyve/stage-guest.sh` now stages and runs the optional benchmark
   through `TWQ_WORKQUEUE_WAKE_BENCH_BIN`,
   `TWQ_WORKQUEUE_WAKE_BENCH_ARGS`, and
   `TWQ_WORKQUEUE_WAKE_BENCH_PLAN`;
3. `scripts/benchmarks/run-workqueue-wake-bench.sh`,
   `run-workqueue-wake-suite.sh`, and
   `run-workqueue-wake-gate.sh` now provide the same one-command guest lane
   shape as the Zig syscall suite;
4. `scripts/benchmarks/run-m13-lowlevel-gate.sh` now reruns both the Zig
   syscall gate and the workqueue wake gate under one repo-owned command and
   writes a run summary manifest;
5. `scripts/benchmarks/extract-workqueue-wake-bench.py` and
   `compare-workqueue-wake-baseline.py` now extract and gate structured wake
   artifacts against a checked-in baseline;
6. `TwqTest.Workqueue` now exposes host-side build and guest-suite wrappers
   for the wake benchmark, while `TwqTest.WorkqueueWake` and its ExUnit
   coverage normalize and compare the resulting artifacts through the existing
   harness policy.

What the first full gate proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/workqueue-wake-gate-20260416T095730Z.json`
   completed with both `wake-default` and `wake-overcommit` at `status=ok`;
2. both modes preserved a single warmed worker across the measured window:
   `before_total=1`, `after_total=1`, and `thread_mismatch_count=0`;
3. both modes produced exact lifecycle counter deltas:
   `reqthreads_count=512`, `thread_enter_count=256`,
   `thread_return_count=256`, `thread_transfer_count=0`;
4. the checked-in suite baseline is now
   [m13-workqueue-wake-suite-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-workqueue-wake-suite-20260416.json).
5. the combined low-level gate now passes end-to-end at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-lowlevel-gate-20260416T100353Z/summary.md`.

Important measurement note:

1. the wake benchmark currently observes `reqthreads_count=2 x samples`
   because each measured wake request is paired with a return-side request in
   the current `libthr` flow;
2. that is intentional baseline behavior right now and should not be treated
   as a harness bug without a real `libthr` change.

Current consequence:

1. M13 now covers both raw syscall hot paths and the warmed idle worker wake
   path;
2. the repo can now rerun that whole low-level floor with one command via
   `scripts/benchmarks/run-m13-lowlevel-gate.sh`;
3. the project has a lower-level regression boundary for future wakeup-policy,
   pre-park, and stack-reuse work that sits below dispatch-level workloads.

### M13 low-level floor is now a one-boot suite-native gate

The top-level M13 low-level regression command no longer stitches two separate
guest boots together. It now runs the whole low-level floor in one staged boot
and compares against a suite-native combined baseline.

What changed:

1. `scripts/benchmarks/run-m13-lowlevel-suite.sh` now stages both the Zig
   syscall suite and the workqueue wake suite into one guest boot;
2. `scripts/benchmarks/extract-m13-lowlevel-bench.py` now emits one combined
   artifact with child suites under `suites.zig_hotpath` and
   `suites.workqueue_wake`;
3. `scripts/benchmarks/compare-m13-lowlevel-baseline.py` now compares that
   combined artifact against a combined baseline while reusing the proven
   child-suite comparators;
4. `scripts/benchmarks/run-m13-lowlevel-gate.sh` now drives the one-boot
   suite and compares it against a suite-native combined baseline instead of
   rerunning two independent gate scripts;
5. `TwqTest.LowlevelBench` now exposes the same combined artifact shape to
   ExUnit, and the baseline is covered by unit tests.

What the first one-boot run proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-lowlevel-suite-20260416T101547Z/m13-lowlevel.json`
   completed with both child suites present under one serial log;
2. the checked-in combined baseline is now
   [m13-lowlevel-suite-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-lowlevel-suite-20260416.json);
3. the one-command gate now passes end-to-end at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-lowlevel-gate-20260416T101704Z/summary.md`.

Current consequence:

1. the project’s low-level M13 floor is now suite-native rather than
   assembled from separate boots;
2. future low-level kernel and `libthr` work can be judged against the exact
   one-boot composition that developers will actually rerun.

### M13 Zig hot-path gate now covers worker lifecycle syscalls

The Zig hot-path suite now measures the worker lifecycle paths that sit below
the higher-level dispatch and Swift repeat lanes.

What changed:

1. `zig/bench/syscall_hotpath.zig` now supports `thread-enter`,
   `thread-return`, and `thread-transfer` benchmark modes in addition to the
   existing `should-narrow` and `reqthreads` modes;
2. lifecycle modes keep kernel state balanced by pairing measured `enter`,
   `return`, or `transfer` operations with unmeasured setup/cleanup calls;
3. the benchmark JSON now includes `thread_transfer_count` alongside the
   existing `init`, `reqthreads`, `thread_enter`, and `thread_return`
   counter deltas;
4. `scripts/benchmarks/run-zig-hotpath-suite.sh` now runs a default six-mode
   plan in one guest boot;
5. the CLI comparator and `TwqTest.ZigHotpath` both gate
   `thread_transfer_count` by default;
6. ExUnit now checks the lifecycle counter invariants in the checked-in
   baseline.

What the full lifecycle run proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-lifecycle-suite-20260416T215000Z.json`
   completed with all six modes at `status=ok`;
2. `thread-enter` recorded `thread_enter_count=256` and
   `thread_return_count=256`, proving the measured enter path can be
   balanced cleanly;
3. `thread-return` recorded the same balanced enter/return deltas while
   timing the return syscall itself;
4. `thread-transfer` recorded `thread_transfer_count=256` with balanced
   enter/return cleanup around the transfer path;
5. the checked-in suite baseline now reflects this six-mode lifecycle gate.

Important implementation note:

1. the first lifecycle smoke exposed a benchmark-harness bug when the
   overcommit priority bit was cast through a signed syscall argument;
2. the fix preserves the raw `u32` priority bits via a bit-cast before
   passing them through the `i32` syscall slot.

Current consequence:

1. M13 now has a low-level regression gate for the main TWQ query, request,
   worker enter, worker return, and cross-lane transfer syscalls;
2. the gate remains strict on `kern.twq.*` counter deltas but intentionally
   coarse on nanosecond latency drift (`3.0x` plus `1000ns` slack by default)
   because the normal lane runs in a WITNESS-enabled bhyve guest;
3. this is the right boundary for future wakeup, stack reuse, `WAITPKG`, and
   other ISA-assisted experiments.

### M13 Zig hot-path baselines now have repeatable suite and comparison tooling

The new Zig benchmark lane is now usable as a regression lane instead of only a
one-off measurement path.

What changed:

1. `scripts/bhyve/stage-guest.sh` now accepts
   `TWQ_ZIG_HOTPATH_BENCH_PLAN`, a newline-separated benchmark argument plan;
2. `scripts/benchmarks/run-zig-hotpath-bench.sh` can now run either a single
   mode or a plan-backed suite;
3. `scripts/benchmarks/run-zig-hotpath-suite.sh` now runs the default
   `should-narrow`, `reqthreads`, and `reqthreads-overcommit` suite in one
   guest boot;
4. `scripts/benchmarks/extract-zig-hotpath-bench.py` now supports `--all`,
   producing a suite artifact keyed by benchmark mode;
5. `scripts/benchmarks/compare-zig-hotpath-baseline.py` now compares single
   or suite artifacts against the checked-in baseline with latency and counter
   drift gates;
6. `scripts/benchmarks/run-zig-hotpath-gate.sh` now runs the one-boot suite
   and immediately compares it against the suite-native baseline;
7. the Elixir harness now has `TwqTest.ZigHotpath`, so ExUnit can normalize
   and compare Zig hot-path artifacts directly;
8. `TwqTest.Zig.run_hotpath_suite/1` now exposes the guest suite through the
   primary harness wrapper layer.

What the first full-suite run proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-suite-default-20260416T201000Z.json`
   completed with all three benchmark modes at `status=ok`;
2. the suite-native checked-in baseline is now
   [m13-zig-hotpath-suite-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-zig-hotpath-suite-20260416.json);
3. comparing the full-suite artifact against that suite-native baseline
   passes the new latency and counter gates.

Important measurement note:

1. the earlier
   [m13-zig-hotpath-initial-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-zig-hotpath-initial-20260416.json)
   remains useful as historical first data, but it was assembled from three
   separate guest boots;
2. its `reqthreads-overcommit` median is lower than the one-boot suite result
   while p95/p99 and counters remain stable, so the suite-native baseline is
   the correct gate for future one-boot suite runs.

Current consequence:

1. M13 can now gate low-level `TWQ` syscall latency and counter deltas without
   rerunning three separate guest boots;
2. the gate is intentionally strict on raw counter deltas and tolerant on
   nanosecond latency drift;
3. a reduced-sample guest smoke produced
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-suite-smoke-20260416T200000Z.json`
   with all three benchmark modes present and `status=ok`;
4. the Elixir unit suite now validates the baseline shape and catches synthetic
   latency regressions without booting a VM;
5. this gives future syscall-path and ISA experiments a stable benchmark
   boundary before any new tuning is accepted.

### M13 now has a real Zig hot-path benchmark lane

The placeholder Zig benchmark is gone. The repo now has a guest-run benchmark
lane that measures real `TWQ` syscall hot paths and archives structured JSON.

What changed:

1. `zig/bench/syscall_hotpath.zig` now emits real benchmark JSON for
   `should-narrow`, `reqthreads`, and `reqthreads-overcommit`;
2. `zig/build.zig` now builds that binary as `twq-bench-syscall` via the
   `bench-syscall` target;
3. `scripts/bhyve/stage-guest.sh` can now stage and run the optional Zig
   hot-path benchmark in the guest through `TWQ_ZIG_HOTPATH_BENCH_BIN` and
   `TWQ_ZIG_HOTPATH_BENCH_ARGS`;
4. `scripts/benchmarks/run-zig-hotpath-bench.sh` now drives the full guest
   lane for the benchmark and writes a parsed JSON artifact;
5. `scripts/benchmarks/extract-zig-hotpath-bench.py` now extracts the final
   `zig-bench` JSON object from the guest serial log;
6. the first repo-owned baseline is now checked in at
   [m13-zig-hotpath-initial-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-zig-hotpath-initial-20260416.json).

What the first guest runs proved:

1. the `should-narrow` guest run now completes cleanly and records
   `mean_ns=1035`, `median_ns=1012`, `p95_ns=1032`, `p99_ns=1079`, with zero
   `reqthreads` / `thread_enter` / `thread_return` churn across the measured
   sample window;
2. the constrained `reqthreads` guest run records `mean_ns=1151`,
   `median_ns=1130`, `p95_ns=1196`, `p99_ns=1219`, with
   `counter_delta.reqthreads_count=256`;
3. the overcommit `reqthreads` guest run records `mean_ns=524`,
   `median_ns=402`, `p95_ns=1099`, `p99_ns=1113`, with the same
   `counter_delta.reqthreads_count=256`;
4. all three runs report kernel metadata directly in the benchmark JSON:
   `kernel_ident=TWQDEBUG`, `kernel_osrelease=15.0-STABLE`, and
   `kernel_bootfile=/boot/TWQDEBUG/kernel`.

Current consequence:

1. `M13` no longer depends on a fake Zig benchmark placeholder;
2. the project now has a real low-level benchmark subset for the kernel query
   and request paths;
3. the next Zig benchmark work can build from a working guest lane instead of
   scaffolding from scratch.

### M14 now has a stock-macOS stop result for the mainq -> default.overcommit seam

The first native macOS comparison result is now integrated into the repo.

What changed:

1. the MX-side stock-macOS result was normalized into
   [m14-macos-stock-introspection-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-macos-stock-introspection-20260416.json);
2. the repo-owned M14 comparison flow now accepts either raw `per_round`
   arrays or `steady_state_per_round` aggregates;
3. [m14-macos-comparison-lane.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m14-macos-comparison-lane.md)
   now records the actual first comparison result instead of only the plan.

What the comparison proved:

1. native macOS shows the same qualitative seam on the Swift repeat lane:
   main-queue handoff traffic reaches `default.overcommit`;
2. the default root still carries source traffic on macOS;
3. the C control lane stays clean on this seam on macOS too;
4. macOS is lower on the primary steady-state rates, but only by about
   `1.58x`, not by anything close to the stronger `2x` concern boundary.

Current consequence:

1. the main-queue to `default.overcommit` seam is no longer an active
   FreeBSD-side tuning target;
2. the correct decision for this seam is now to stop tuning it on FreeBSD;
3. future performance work should focus on other gaps, not on suppressing this
   native-shaped handoff path.

### FreeBSD now has round-boundary libdispatch snapshots for M14

The FreeBSD side no longer stops at full-run libdispatch root counters.

What changed:

1. staged `libdispatch` now exports a narrow
   `_dispatch_twq_counter_emit_snapshot()` helper that emits structured
   round-boundary root counter snapshots;
2. the primary Swift repeat lane and the secondary C repeat lane now emit
   those snapshots at both `round-start-counters` and `round-ok-counters`;
3. `scripts/benchmarks/extract-m13-baseline.py` now parses those snapshot
   lines into schema version `3`, including per-round libdispatch deltas;
4. `scripts/benchmarks/summarize-m13-baseline.py` now summarizes both full-run
   and steady-state round averages;
5. `scripts/benchmarks/compare-m14-steady-state.py`,
   `benchmarks/m14-macos-template.json`, and
   `m14-macos-comparison-lane.md` now define the repo-owned M14 intake path.

What the focused guest run proved:

1. the focused repeat-only benchmark run completed successfully and produced
   [m14-round-snapshots-20260416T000000Z.json](/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m14-round-snapshots-20260416T000000Z.json);
2. that artifact is the first schema-`3` benchmark JSON with per-round
   libdispatch deltas;
3. in the primary Swift repeat lane, the steady-state `8-63` window now reads
   about
   `3.21 mainq pushes / round`,
   `3.21 default-overcommit poke_slow / round`,
   and
   `18.36 reqthreads / round`;
4. the secondary C repeat lane stays clean on this seam:
   `0.00 mainq pushes / round` and
   `0.00 default-overcommit poke_slow / round`.

Current consequence:

1. the FreeBSD side now has the exact per-round primary metrics M14 needs;
2. MX/macOS data can now be compared against a steady-state FreeBSD reference
   without reconstructing rates from full-run totals;
3. the next decision remains M14 comparison, not more speculative seam
   suppression.

### M14 is now a Swift-first matched-behavior comparison lane

The macOS comparison lane is no longer described abstractly.

The current MX-side reading sharpens the next step:

1. the primary native macOS workload should be the Swift
   `dispatchMain()` repeat shape equivalent to
   `dispatchmain-taskhandles-after-repeat`;
2. the pure-C `main-executor-resume-repeat` lane should remain a secondary
   calibration/control lane, not the deciding seam;
3. the main comparison window should be steady-state rounds `8-63`, not the
   startup-heavy early rounds;
4. the primary comparison metrics should be
   main-queue pushes into `default.overcommit`,
   `default.overcommit poke_slow`,
   and `_pthread_workqueue_addthreads` request rate per round;
5. the current decision boundary is now explicit:
   if macOS shows the same qualitative split and roughly the same order of
   magnitude for those steady-state handoff/poke rates, stop tuning this seam
   on FreeBSD;
   if macOS is materially lower, especially around `2x` lower on the same
   `64 x 8 x 20ms` Swift workload, keep tuning.

Current consequence:

1. the current FreeBSD line should not suppress more main-queue to
   `default.overcommit` traffic before that macOS comparison exists;
2. the next milestone is not another speculative M13 suppression pass;
3. the next milestone is a matched M14 behavior comparison with a concrete
   stop/tune rule.

### Project-state update: M13 is healthy and M14 is now the next decision point

The current project state is better described as "comparison-bound" than
"blocked."

What changed in the project reading:

1. the current staged stack has no major correctness blocker;
2. the kernel `TWQ` path, staged `libthr`, staged `libdispatch`, and staged
   Swift validation lane are all functioning together;
3. the remaining high-visibility repeat-lane traffic on FreeBSD is now
   identified more narrowly as main-queue handoff into the default-overcommit
   root;
4. that seam appears plausibly native-shaped from both Apple open-source
   reading and current FreeBSD DTrace evidence.

Current consequence:

1. `M13` remains active for baseline discipline and local regression tooling;
2. `M14` is now the next milestone in practice, because the project needs
   native macOS comparison data before suppressing another root-queue traffic
   class;
3. the current uncertainty is rate/coalescing versus macOS, not whether the
   FreeBSD stack fundamentally works.

### M13 DTrace lane now identifies default-overcommit traffic safely

The root-push classifier boundary has been made usable instead of just
documented.

What changed:

1. `scripts/bhyve/stage-guest.sh` now runs DTrace against the actual Swift or
   C probe binary instead of tracing `/usr/bin/env`;
2. staged `libdispatch` now has a safe pre-publish counter for one narrow
   case: pushed object pointer equals `_dispatch_main_q`;
3. that counter deliberately avoids `dx_metatype()` / `dx_type()` and therefore
   does not reintroduce the post-publish crash class;
4. `scripts/benchmarks/extract-m13-baseline.py` now preserves
   `[libdispatch-twq-counters]` dumps in schema version `2`;
5. `scripts/benchmarks/summarize-m13-baseline.py` gives a compact summary of
   `kern.twq.*` deltas plus the high-value libdispatch root counters;
6. `scripts/benchmarks/compare-m13-baselines.py` provides the first coarse
   drift-tolerant regression gate for common benchmark modes.

What the guest runs proved:

1. the full Swift repeat lane completed with counters enabled at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.serial.log`;
2. the extracted baseline
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json`
   reports `reqthreads +1058 / enter +343 / return +340`;
3. the counter dump shows
   `root_push_empty_default_overcommit=186` and
   `root_push_mainq_default_overcommit=186`;
4. the fresh DTrace sample
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-dtrace-push-vtable-20260416T042209Z.serial.log`
   maps default-overcommit pushes primarily to
   `__OS_dispatch_queue_main_vtable`.

Current consequence:

1. the remaining default-overcommit pressure is main-queue handoff traffic;
2. that is compatible with the macOS-source model, so it should not be
   suppressed blindly;
3. the next decision needs rate/coalescing evidence, ideally from the M14
   macOS comparison lane.

### M13 push-path classification moved to DTrace after unsafe hot-path attempt

The next `M13` diagnostic pass confirmed an important instrumentation boundary:
root-push object classification must not dereference the pushed object after it
has been published to the MPSC root queue.

What changed:

1. the unsafe in-process overcommit push-kind classifier was reverted from
   staged `libdispatch`;
2. the retained M13 behavior changes remain intact:
   one-shot `dispatch_after` source repoke suppression and same-target
   `ASYNC_REDIRECT` suppression for `used_width >= 3`;
3. `scripts/dtrace/` now contains focused FreeBSD DTrace scripts for root
   push/poke/drain tracing, vtable-pointer classification at function entry,
   and root queue aggregate summaries;
4. `scripts/bhyve/stage-guest.sh` now stages those diagnostics into the guest
   under `/root/twq-dtrace`, controlled by `TWQ_DTRACE_SCRIPT_DIR`.

What the guest run proved:

1. the crash was isolated to the unsafe classifier, not to the retained M13
   behavior changes;
2. the focused Swift repeat run
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260416T024756Z.json`
   completed all `64` rounds after the revert;
3. that same run landed at
   `swift.dispatchmain-taskhandles-after-repeat = +969 / +317 / +314`;
4. its counter dump still shows the remaining seam as overcommit
   `empty->poke-slow` ingress:
   `root_push_empty_default_overcommit=164`,
   `root_poke_slow_default_overcommit=165`,
   and only
   `root_repoke_default_overcommit=1`.

Current consequence:

1. further push-population classification should use DTrace at
   `_dispatch_root_queue_push:entry`, before `os_mpsc_push_list()` publishes
   the object;
2. permanent in-process counters may be reintroduced only if they classify
   before publish or on the drain side where ownership is clear;
3. `hwpmc` remains a later cost-attribution tool, not the tool for pointer
   safety or queue-semantics debugging.

### M13 `dispatch_after` source suppression becomes the first durable root-redrive win

The next real `M13` movement stayed inside staged `libdispatch`, but it
stopped trying to tune root redrive in the abstract.

What changed:

1. `_dispatch_root_queue_drain_one()` now skips the pre-invoke
   `drain-one-repoke` only when the current head item is a one-shot
   `dispatch_after` timer source on the non-overcommit default root;
2. the earlier generic “queue-ish head” suppression experiment was removed;
   it never fired in the guest and was the wrong seam.

What the guest runs proved:

1. the first clean proof run,
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.json`,
   kept both repeat lanes correct while improving
   `dispatch.main-executor-resume-repeat` from
   `+402 / +177 / +174` to
   `+324 / +153 / +150`;
2. that same run improved
   `swift.dispatchmain-taskhandles-after-repeat` from
   `+1323 / +422 / +419` to
   `+1234 / +408 / +405`;
3. the Swift counter dump from
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.serial.log`
   shows the mechanism directly:
   `root_repoke_default=0`,
   `root_repoke_drain_one_default=0`,
   and
   `root_repoke_suppressed_after_source_default=363`.

Current consequence:

1. the dominant Swift repeat seam is no longer generic default-root repoke;
2. the new retained optimization is source-specific and evidence-backed;
3. the next `M13` question becomes “what remains after source repokes are
   gone?” not “should we still suppress source repokes?”

### M13 remaining C repeat churn is now pinned to default-root `ASYNC_REDIRECT`

The follow-up pass after source suppression was measurement-only:
split the remaining default-root continuation tail by subtype.

What changed:

1. staged `libdispatch` root counters now distinguish continuation repokes by
   subtype, including plain user continuations versus `ASYNC_REDIRECT`.

What the guest run proved:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.json`
   kept the new source suppression result:
   `dispatch.main-executor-resume-repeat` held at
   `+329 / +153 / +150`,
   while
   `swift.dispatchmain-taskhandles-after-repeat` improved again to
   `+1137 / +386 / +383`;
2. the C counter dump from
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.serial.log`
   now shows the remaining default-root repoke makeup exactly:
   `root_repoke_suppressed_after_source_default=512`,
   `root_repoke_drain_one_kind_default_continuation=443`,
   `root_repoke_drain_one_kind_default_continuation_async_redirect=443`,
   and
   `root_repoke_drain_one_kind_default_lane=55`;
3. the Swift lane in the same run still shows
   `root_repoke_default=0` with
   `root_repoke_suppressed_after_source_default=372`,
   so the retained source suppression still behaves as intended.

Current consequence:

1. the next honest `M13` target is the default-root `ASYNC_REDIRECT`
   continuation path on the C repeat lane;
2. generic continuation suppression would be the wrong next move, because the
   remaining continuation tail is already specific enough to target directly.

### M13 root-counter instrumentation isolates the live repeat seam

The next `M13` step stayed diagnostic, but it materially changed the
optimization target.

What changed:

1. staged `libdispatch` now has low-overhead per-process counters for the
   repeat-lane investigation, covering both the suspected concurrent-lane
   redirect path and the root queue redrive path;
2. `scripts/bhyve/stage-guest.sh` already stages
   `LIBDISPATCH_TWQ_COUNTERS`, so the guest benchmark lane can run those
   counters without enabling the heavier `dprintf` trace surfaces.

What the guest runs proved:

1. the queue-focused counter run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T130059Z.serial.log`
   showed
   `concurrent_push_redirect=0`,
   `concurrent_push_fallback=0`,
   `async_redirect_invoke_entry=0`,
   `async_redirect_invoke_exit=0`,
   `lane_push_wakeup=0`, and
   `lane_push_no_wake=0`,
   so the remaining repeat churn is not flowing through the suspected
   concurrent-lane redirect seam;
2. the root-counter run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T131214Z.serial.log`
   isolated the real hot path instead:
   the C repeat lane completed at
   `reqthreads +385 / enter +170 / return +167`
   with
   `root_push_append_default=973` and
   `root_repoke_drain_one_default=973`,
   while the Swift repeat lane completed at
   `reqthreads +1401 / enter +463 / return +460`
   with
   `root_push_append_default=381` and
   `root_repoke_drain_one_default=381`;
3. both runs showed zero `contended-wait` and `worker-timeout` repokes, which
   means the redrive is coming from the default-root next-visible path in
   `_dispatch_root_queue_drain_one()`, not from broader pool contention or idle
   timeout recycling;
4. Swift still adds a separate one-shot default-overcommit ingress
   (`root_push_empty_default_overcommit=208` in the clean run), but not an
   overcommit repoke loop.

Current consequence:

1. the active `M13` target is now root `drain-one-repoke` coalescing or
   equivalent next-visible handoff on the default root;
2. concurrent-lane redirect tuning is demoted from “active suspect” to
   “ruled out for this repeat lane”;
3. the earlier `cleanup2 -> overcommit root` handoff remains a reference seam,
   but it is no longer the best first place to optimize.

## 2026-04-15

### M13 `libthr`-only trace confirms the remaining churn is wake-dominant

The next useful `M13` refinement was diagnostic again, but this time it
changed the layer we should optimize next.

Key result:

1. `scripts/bhyve/stage-guest.sh` now supports split guest trace controls:
   `TWQ_LIBPTHREAD_TRACE`,
   `TWQ_LIBDISPATCH_MAINQUEUE_TRACE`, and
   `TWQ_LIBDISPATCH_ROOT_TRACE`;
2. the older `TWQ_SWIFT_RUNTIME_TRACE` compatibility path still works, but it
   is no longer the only way to enable `LIBPTHREAD_TWQ_TRACE`;
3. a new repeat-only guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.serial.log`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.json`
   completed successfully under `libthr`-only tracing, avoiding the
   `rc=139` failures seen with the broader bundled trace path.

Important findings:

1. the traced C repeat lane still completed with
   `reqthreads +230 / enter +110 / return +107`
   and round-level `reqthreads_delta` mean `3.484`;
2. the traced Swift repeat lane also completed with
   `reqthreads +657 / enter +189 / return +186`
   and round-level `reqthreads_delta` mean `10.156`;
3. the more important signal is the wake/spawn mix from
   `addthreads-ready` events:
   dispatch showed `118` wake-only events versus `5` spawn-only events,
   while Swift showed `456` wake-only events versus `7` spawn-only events;
4. that means the new `libthr` planning path is doing the intended job:
   most remaining repeat-lane requests are now waking already-idle workers,
   not manufacturing new workers;
5. the honest next target therefore moves back up the stack:
   reduce upstream request generation and weak coalescing in staged
   `libdispatch`, while keeping the new low-noise `libthr` trace lane as a
   guard against regressing wake-first behavior.

### M13 wake-first `libthr` ready planning verified

The next real `M13` win did not come from another root-queue heuristic.
It came from making `libthr` stop treating every newly admitted worker as a
fresh spawn.

Key result:

1. `/usr/src/lib/libthr/thread/thr_workq.c` now tracks per-lane idle worker
   counts (`tbr_idle`) instead of only a process-wide idle total;
2. the old spawn-biased `admitted -> spawn_needed` assumption is now replaced
   by a wake-first planning step:
   same-lane idle workers are used first for already-counted pending work,
   then transferable idle workers from other lanes are used, and only the
   remainder is spawned;
3. the new planning path is used both in `addthreads` and in reaper-driven
   redrive, so the staged guest runtime now makes the same wake/spawn decision
   on both the hot path and the idle-trim redrive path;
4. two clean repeat-only runs at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T110916Z.json`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111107Z.json`
   confirm the effect in the guest.

Important findings:

1. the C repeat lane,
   `dispatch.main-executor-resume-repeat`,
   stayed stable and slightly improved versus the prior post-transfer band:
   from `+380 / +169 / +166` and `+354 / +163 / +160`
   to `+361 / +164 / +161` and `+343 / +158 / +155`;
2. the Swift repeat lane,
   `swift.dispatchmain-taskhandles-after-repeat`,
   improved materially versus the same post-transfer band:
   from `+1371 / +460 / +457` and `+1500 / +506 / +503`
   to `+1350 / +429 / +426` and `+1279 / +394 / +391`;
3. the Swift round-level request mean also improved from
   `21.297` and `23.312` to `20.984` and `19.891`;
4. this is the first current-branch result that improves the repeat-heavy
   Swift lane again without trying to fight a donor-shaped
   `cleanup2 -> overcommit root` handoff in staged `libdispatch`;
5. the honest next question is therefore narrower:
   measure the new wake/spawn mix directly under trace, then decide whether
   the next dominant hotspot is still staged-`libdispatch` redrive/coalescing
   or the remaining cross-lane wake planning inside `libthr`.

### M13 root-only trace isolates `cleanup2` main-queue handoff

The next useful `M13` narrowing step was diagnostic, not behavioral.

Key result:

1. `../nx/swift-corelibs-libdispatch/src/queue.c` now supports a dedicated
   `LIBDISPATCH_TWQ_TRACE_ROOT` switch, so root-queue diagnostics no longer
   require the broader mainqueue/lane trace;
2. `scripts/bhyve/stage-guest.sh` now stages and forwards a matching
   `TWQ_LIBDISPATCH_ROOT_TRACE` control into the guest benchmark lane;
3. the new root-only trace in
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T095603Z.serial.log`
   shows that the first repeat-lane overcommit request is not delayed child
   work directly;
4. it first appears when `_dispatch_queue_cleanup2()` has cleared the main
   queue's thread-bound state and `com.apple.main-thread` is pushed onto
   `com.apple.root.default-qos.overcommit` as an `empty->poke` root item.

Important findings:

1. the traced main queue is already ordinary at that point:
   `head_thread_bound=0`, `head_enqueued=1`, `head_dirty=0`,
   `head_drain_locked=0`, `head_in_barrier=0`;
2. the queue already contains one internal item at the moment it is pushed to
   the overcommit root (`head_head=head_tail=0xdb287e1a040` in the recorded
   trace);
3. the root-only traced repeat lane still ends in `rc=139`, so this remains a
   diagnostic lane, not a stable regression benchmark;
4. donor-side comparison against the local Apple `libdispatch` tree now says
   this seam is probably native-shaped:
   `_dispatch_main_q` targets `_dispatch_get_default_queue(true)`, and
   `_dispatch_queue_cleanup2()` clears thread-bound state before handing off
   through `_dispatch_lane_barrier_complete()`;
5. the next honest target is therefore narrower than “generic root redrive”
   and more specific than “the cleanup handoff exists”:
   investigate excess overcommit push/poke rate and weak coalescing after the
   first `cleanup2 -> barrier_complete -> main queue overcommit push`
   transition.

## 2026-04-13

### M13 `ready`-coverage fast path rejected

A targeted `libthr` experiment tried to skip kernel `REQTHREADS` when a lane
already had enough `tbr_ready` workers to cover its current `tbr_pending`
count.

Result:

1. the first clean repeat-only run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115402Z.json`
   improved the C repeat lane to
   `dispatch.main-executor-resume-repeat = +345 / +157 / +154`,
   but moved the Swift repeat lane to
   `swift.dispatchmain-taskhandles-after-repeat = +1533 / +532 / +529`;
2. the traced run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115538Z.serial.log`
   showed the new path only `4` times:
   `addthreads-covered: 4` versus
   `addthreads-begin: 952` and
   `root-queue-poke-slow: 952`;
3. the second clean run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115743Z.json`
   landed at `+316 / +149 / +146` for the C repeat lane and
   `+1424 / +491 / +488` for the Swift repeat lane.

Important finding:

1. this is not the dominant hotspot;
2. the trace proves the fast path barely fires in the real continuation-heavy
   workload shape;
3. the patch was reverted and the staged `libthr` was refreshed back to the
   reverted state;
4. the remaining honest target stays higher in the stack:
   repeated root-queue request generation and cross-queue wake behavior.

### M13 cross-lane transfer handoff verified

The next real M13 churn reduction is now proven in the staged guest, and the
result is more specific than the earlier same-lane win.

Key result:

1. `/usr/src/sys/sys/thrworkq.h`,
   `/usr/src/lib/libthr/thread/thr_workq_kern.h`,
   `/usr/src/sys/kern/kern_thrworkq.c`, and
   `/usr/src/lib/libthr/thread/thr_workq.c` now implement
   `TWQ_OP_THREAD_TRANSFER`, letting a worker move directly from one kernel
   `TWQ` lane to another on cross-lane handoff instead of always paying a full
   `THREAD_RETURN -> THREAD_ENTER` cycle;
2. the first current-branch transfer runs were misleading because the guest was
   not actually exercising the new code at first:
   the kernel had to be rebuilt, and then the staged `libthr` had to be
   refreshed from newly rebuilt `/tmp/twqlibobj/.../*.pico` objects;
3. the decisive traced run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112356Z.serial.log`
   proves the transfer path is live:
   `worker-handoff-transfer` fired `183` times,
   `worker-handoff-enter` fell to `0`, and
   `worker-handoff-fastpath` still fired `85` times for same-lane claims;
4. two clean repeat-only runs at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112557Z.json`
   and
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112757Z.json`
   confirm the qualitative result without tracing overhead.

Important findings:

1. the clean post-transfer C repeat lane,
   `dispatch.main-executor-resume-repeat`,
   now sits at `reqthreads +380 / enter +169 / return +166` and
   `+354 / +163 / +160`, which is still roughly the same band as the earlier
   same-lane-only M13 result;
2. the clean post-transfer Swift repeat lane,
   `swift.dispatchmain-taskhandles-after-repeat`,
   moved to `reqthreads +1371 / enter +460 / return +457` and
   `+1500 / +506 / +503`;
3. compared with the earlier same-lane-only M13 result
   (`+1630 / +780 / +777` and `+1863 / +884 / +881`),
   that is a real Swift-side reduction in both worker requests and
   enter/return churn;
4. the current-branch debugging lesson is important enough to keep:
   `scripts/libthr/prepare-stage.sh` relinks from objdir products, so changing
   `/usr/src/lib/libthr/thread/thr_workq.c` alone does not put new behavior
   into the guest until the corresponding `.pico` objects are rebuilt;
5. the honest next M13 target is no longer worker recycling within `libthr`.
   The transfer path closes that question enough to move on. The remaining
   hotspot is request generation across root queues and staged `libdispatch`
   wake policy.

## 2026-04-11

### M13 same-lane handoff fast path verified

The first real post-M12 churn reduction is now proven instead of inferred.

Key result:

1. `scripts/libthr/prepare-stage.sh` now refreshes the staged `libthr` from
   the freshest objdir instead of a stale default path;
2. `/usr/src/lib/libthr/thread/thr_workq.c` now has a same-lane handoff fast
   path that skips a redundant `THREAD_RETURN -> THREAD_ENTER` cycle when a
   worker immediately claims more work in the same kernel bucket;
3. a traced guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T125820Z.serial.log`
   proves `worker-handoff-fastpath` is live in the staged guest runtime;
4. two clean repeat-only runs now show materially lower churn than the
   pre-fix baseline on the same workloads.

Important findings:

1. the pre-fix repeat-only mean for
   `dispatch.main-executor-resume-repeat` was
   `reqthreads +546 / enter +183 / return +180`;
2. the first two real post-fix runs moved that C lane to
   `+379 / +172 / +169` and `+320 / +150 / +147`;
3. the pre-fix repeat-only mean for
   `swift.dispatchmain-taskhandles-after-repeat` was
   `reqthreads +2659.5 / enter +887.5 / return +884.5`;
4. the first two real post-fix runs moved that Swift lane to
   `+1630 / +780 / +777` and `+1863 / +884 / +881`;
5. the traced run shows why the Swift win is partial rather than final:
   `worker-handoff-fastpath` fired `30/30` same-lane claims in the C section,
   but only `63` times in the Swift section where `153` more handoffs still
   crossed lanes and required the slower re-enter path.

## 2026-04-10

### M13 repeat-lane telemetry added

The repeat-heavy M13 hotspots now expose round-by-round `TWQ` counter series
instead of only whole-run before/after deltas.

Key result:

1. `csrc/twq_dispatch_probe.c` now emits `round-start-counters` and
   `round-ok-counters` for the C repeat lanes;
2. `swiftsrc/twq_swift_dispatchmain_taskhandles_after_repeat.swift` now emits
   matching round counter events for the staged Swift repeat lane;
3. `scripts/benchmarks/extract-m13-baseline.py` now preserves those series
   under `round_metrics` in the extracted benchmark JSON;
4. a focused guest run at
   `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260410T123532Z.json`
   shows the repeat hotspot is steady-state churn, not just startup noise.

Important findings:

1. `dispatch.main-executor-resume-repeat` keeps a stable per-round request
   pattern with `reqthreads_delta` mean `7.55`, first-half mean `7.66`,
   second-half mean `7.44`;
2. the same C lane keeps `bucket_total` pinned at `5`, so worker-pool
   formation is already complete while the requests continue;
3. `swift.dispatchmain-taskhandles-after-repeat` remains much hotter with
   `reqthreads_delta` mean `41.73`, first-half mean `44.91`,
   second-half mean `38.56`;
4. this makes the next honest optimization target clearer:
   staged `libdispatch` request generation should be tuned before kernel
   admission or `libthr` warm-pool policy.

### M13 baseline lane started

The repo now has a real post-M12 performance baseline instead of a vague
benchmark intention.

Key result:

1. added a reproducible host-side benchmark runner in
   `scripts/benchmarks/run-m13-baseline.sh`;
2. added a structured serial-log extractor in
   `scripts/benchmarks/extract-m13-baseline.py`;
3. added staged pthread header refresh support in
   `scripts/libthr/prepare-headers.sh`;
4. captured the first compact baseline in
   `benchmarks/baselines/m13-initial.json`;
5. confirmed all `6` selected dispatch modes and all `3` selected Swift modes
   completed with `ok` status in the first baseline run.

Important findings:

1. the warm-pool reuse lanes are stable:
   `dispatch.burst-reuse` and `dispatch.timeout-gap` both settle at `4` idle
   workers with no post-round active workers;
2. pressure behavior is still visible:
   `dispatch.pressure` holds `default_max_inflight` to `3`, and
   `dispatch.sustained` records `641` block/unblock observations;
3. the next honest optimization target is worker-request churn:
   `dispatch.main-executor-resume-repeat` still drives
   `reqthreads_count +564`, while
   `swift.dispatchmain-taskhandles-after-repeat` drives
   `reqthreads_count +2799`.

This moves `M13` from `next` to `in_progress`. The project now has a concrete
baseline artifact it can optimize against instead of relying on intuition.

### M12 closed by kernel TWQ lane split

The repo now records the actual fix for the strongest staged Swift correctness
gap.

Key result:

1. the old repeated delayed-child Swift failure was not ultimately a staged
   `libdispatch` queue-redrive bug;
2. the real root cause was kernel-side `TWQ` accounting that collapsed
   constrained and overcommit workers into the same QoS bucket;
3. internal `TWQ` accounting is now split by lane
   (`QoS x {constrained, overcommit}`) in
   `/usr/src/sys/kern/kern_thrworkq.c`, while the public sysctl surface
   remains bucket-aggregated;
4. the previously failing staged probe,
   `dispatchmain-taskhandles-after-repeat-hooks`, now completes all `64`
   rounds on the full staged lane;
5. the broader staged Swift `full` profile now completes end-to-end in the
   guest with no timeout results, aside from the already-known invalid
   `customdispatch + stock libthr` control lanes.

Important evidence:

1. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-swiftonly-lanesplit.serial.log`
2. `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-swift-full-post-lanesplit.serial.log`

This changes the honest M12 story. Earlier staged-`libdispatch` tracing was
useful narrowing work, but it described the symptom boundary rather than the
root cause. The Tier 1 Swift delayed-resume correctness gap is now closed for
the current validation matrix.

### Staged libdispatch lane-redrive boundary corrected

The repo now records a more accurate M12 boundary after adding staged
`libdispatch` lane-drain and invoke-finish tracing on the failing Swift lane.

Key result:

1. the failing queue is the real `Swift global concurrent queue`, not just the
   earlier pure-C `twq.swift.executor` control;
2. on that queue, the first delayed-resume wave reaches:
   - `lane-invoke2-entry`
   - `lane-drain-entry`
   - `lane-drain-exit`
   - normal callouts for the first resumed jobs;
3. later child resumptions still reach staged `libdispatch`
   `continuation_async` on the same queue;
4. after those later enqueues, the queue no longer shows a second
   `lane-invoke2-entry` / `lane-drain-entry` before timeout;
5. a follow-up pass also showed no matching `invoke-finish-*` traces for that
   failing queue.

That moves the honest live boundary back downward. The remaining staged M12
failure is not best described as a Swift future/waiter bug above raw C
dispatch. It is more accurately a staged `libdispatch` queue redrive /
invoke-finish / reenqueue failure on the shared `Swift global concurrent
queue` under the delayed-child Swift workload.

### Plain-C timer-hop repeat boundary tightened

The repo now records a stricter C-side control for the remaining M12 bug:

1. a new `main-executor-resume-repeat` dispatch mode was added;
2. it drives `64` rounds of delayed timer callbacks that each re-enqueue a
   distinct continuation onto the executor queue;
3. that new mode completes successfully on the full staged TWQ lane with
   `512/512` resumed continuations.

That means the remaining staged failure is no longer honestly describable as
"timer queue callback re-enqueues work onto the executor queue and custom
libdispatch drops it" in generic C. That rules out the simple timer-hop theory,
but later lane tracing showed the remaining live boundary is still inside
staged `libdispatch`, not above it in Swift future/waiter logic.

### Repeated delayed-child control matrix tightened again

The repo now records the strongest M12 isolation result so far:

1. the repeated `dispatchmain-taskhandles-after-repeat` stress probe still
   times out on the full staged TWQ lane;
2. the exact same repeated stress probe completes all `64` rounds on the
   `stock libdispatch + custom libthr` guest control;
3. the `custom libdispatch + stock libthr` lane is not a valid runtime
   comparison because staged `libdispatch` expects custom-`libthr` symbols
   such as `qos_class_main`.

That moves the honest critical-path blame off kernel `TWQ` worker supply and
off the `libthr` bridge for this bug class. The remaining divergence is now
firmly in the staged `libdispatch` lane.

### Staged repeat failure narrowed past enqueue

The repo now records a tighter staged M12 failure boundary:

1. in the failing repeated-stress run, late child resumptions still reach
   Swift `enqueueGlobal`;
2. they still pass through `dispatch_async_f`;
3. they still enter staged `libdispatch` `continuation_async` on the
   `Swift global concurrent queue`;
4. they stop before the staged `libdispatch` callout / invoke path runs them.

That means the live fault line is no longer "Swift did not request resume"
and no longer "the queue-shape hypothesis". It is now staged `libdispatch`
queue drain / wakeup after enqueue on the full TWQ lane.

### Swift executor queue-shape hypothesis narrowed

The repo now records a more precise M12 result:

1. Swift 6.3's non-Apple `DispatchGlobalExecutor.cpp` really does create
   per-priority concurrent queues and immediately call
   `dispatch_queue_set_width(queue, -3)`;
2. the C dispatch probe now splits that queue shape into four variants:
   `executor-after`, `executor-after-settled`,
   `executor-after-default-width`, and `executor-after-sync-width`;
3. a new full-profile guest run showed all four variants completing
   successfully on the staged TWQ lane.

That means the simple "fresh queue width-narrowing race" theory is no longer a
sufficient explanation for the remaining Swift delayed-child timeout.

The next M12 focus therefore shifts upward to the staged Swift/dispatch
boundary:

1. delayed Swift job re-enqueue;
2. `dispatch_async_swift_job` or its fallback path;
3. parent-await / child-resume behavior after enqueue.

### Swift delayed-child control matrix tightened

The repo now records a stronger M12 isolation result:

1. the staged `dispatchmain-taskhandles-after` probe still times out on the
   TWQ-backed custom-`libdispatch` lane;
2. the same probe completes on both stock-dispatch guest controls:
   stock `libthr` and custom `libthr`;
3. on the failing staged lane, every delayed child still reaches
   `child-after-await-*`, but the parent stalls after `parent-awaiting-1`.

That moves the remaining delayed-child bug away from generic Swift future
completion and away from the custom `libthr` bridge. The honest live boundary
is now staged workqueue-enabled `libdispatch`, most likely in the redrive path
that should resume the waiting parent task after delayed child completion.

### GLM review response captured

The repo now records the immediate execution response to the external GLM
architecture review.

The main change is a shift in the next-step judgment:

1. the remaining staged delayed-child boundary is now treated primarily as a
   Layer B staged-`libdispatch` correctness problem;
2. the next milestone is no longer "more Swift narrowing";
3. the next milestone is now a C-level staged-`libdispatch` executor-after /
   delayed-child fix, while the current Swift probe set is held steady as a
   validation and regression lane.

### Project naming standardized

The repo now treats `GCDX` as the explicit project name for the current
FreeBSD-based kernel-integrated dispatch effort.

The terminology map is now:

1. `libdispatch` = portable Tier 0 baseline;
2. `GCDX` = this project, the kernel-integrated Tier 1 lane;
3. `GCD` = the platform-complete macOS reference lane.

### Swift 6.3 stock-dispatch boundary corrected

The repo now records an important Swift validation correction:

1. the stock Swift 6.3 toolchain `libdispatch.so` does not reference
   `_pthread_workqueue_*` symbols at all;
2. the staged custom `libdispatch.so` does;
3. the stock-dispatch plus custom-`libthr` guest control completes a delayed
   child-completion probe successfully, but shows zero TWQ counter deltas
   during that probe window.

This means the stock Swift 6.3 dispatch lane is a useful runtime control, but
it is not a TWQ-backed control lane. Real Swift/TWQ validation still depends
on the staged custom `libdispatch` lane.

### Swift delayed-child boundary narrowed again

The repo now has a stronger staged Swift diagnosis:

1. a new pure-C `worker-after-group` dispatch mode succeeds on the staged TWQ
   lane;
2. a new Swift `dispatchmain-taskhandles-after` probe still times out there,
   while passing on the stock host Swift 6.3 lane.

This means the remaining problem is no longer best described as a
`TaskGroup`-only bug. The tighter boundary is:

1. multiple delayed Swift child-task resumptions awaited by a parent async
   context on the staged custom-`libdispatch` lane.

### Current macOS-gap reading

The repo now carries an explicit estimate for how close the current port is to
native macOS `libdispatch` behavior:

1. roughly `70-80%` for the kernel-backed workqueue behavior that matters most
   to this project;
2. roughly `45-55%` for broader native-macOS `libdispatch` parity overall.

### Why the estimate is already meaningfully high

The following are already real and working:

1. kernel `TWQ` support in `/usr/src`;
2. real pressure-aware admission and narrowing;
3. real backpressure from the kernel workqueue path into staged
   `libdispatch`;
4. a real `libthr` pthread_workqueue bridge;
5. repeatable `bhyve` guest validation;
6. a stable Swift validation profile that proves the staged stack is not just
   a synthetic C-only demo.

### Why the estimate is not higher yet

The following important gaps remain:

1. no direct kevent-workqueue delivery;
2. no workloops;
3. no cooperative-pool semantics;
4. worker lifecycle is still not kernel-owned the way it is on macOS;
5. no turnstile-style priority inheritance for this path;
6. no structured macOS-side comparison lane has been run yet;
7. one staged custom-`libdispatch` bug is still open:
   delayed `TaskGroup` child completion on the TWQ lane.

### Current position

The project is already past the stage where it can be honestly called a shim or
compatibility-only dispatch story. It has crossed the boundary into a real
kernel-backed dispatch implementation on FreeBSD.

The remaining work is no longer "make pthread_workqueue exist at all." It is:

1. fix the remaining staged custom-`libdispatch` delayed child-completion bug;
2. expand Swift validation without lying about what is already stable;
3. build the macOS comparison lane;
4. decide later which deeper macOS features are worth adopting naturally on
   FreeBSD.
