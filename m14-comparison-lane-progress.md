# M14 Comparison Lane Progress

## Summary

The repo now has a platform-neutral M14 comparison layer in `scripts/benchmarks`.

This milestone does not pretend that macOS and FreeBSD expose identical telemetry
today. It does something more useful:

1. it normalizes the current macOS introspection report into a benchmark-first
   schema;
2. it normalizes current FreeBSD benchmark artifacts into the same schema;
3. it carries missing-data reality forward instead of fabricating per-round seam
   counters on the FreeBSD side;
4. it adds one compare CLI that prints the stop-versus-tune decision using the
   M14 policy instead of the older M13 drift policy.

Files added in this step:

1. `scripts/benchmarks/extract-m14-benchmark.py`
2. `scripts/benchmarks/compare-m14-benchmarks.py`
3. `scripts/benchmarks/run-m14-compare.sh`
4. `scripts/benchmarks/verify-m14-tooling.py`
5. `scripts/benchmarks/discover-m14-artifacts.py`
6. `scripts/benchmarks/summarize-m14-compare.py`
7. `scripts/benchmarks/validate-m14-artifacts.py`
8. `scripts/benchmarks/m14_validation.py`
9. `scripts/benchmarks/audit-m14-artifact-schema.py`
10. `scripts/benchmarks/m14_audit.py`
11. `fixtures/benchmarks/m14-*.json`

## What The New Extractor Does

`scripts/benchmarks/extract-m14-benchmark.py` accepts three source forms:

1. `--macos-report`
   for the native macOS report already produced by
   `scripts/macos/extract-m14-introspection-report.py`;
2. `--freebsd-benchmark-json`
   for the structured guest artifact already produced by
   `scripts/benchmarks/extract-m13-baseline.py`;
3. `--freebsd-round-snapshots-json`
   for the newer FreeBSD M14 round-snapshot lane carrying per-round seam rows
   directly;
4. `--freebsd-serial-log`
   for direct guest serial logs, using `extract-m13-baseline.py` as the first
   normalization pass under the hood.

The common output schema focuses on the two M14 lanes:

1. `swift.dispatchmain-taskhandles-after-repeat`
2. `dispatch.main-executor-resume-repeat`

Per benchmark it stores:

1. workload tuple;
2. normalized full-run metrics;
3. normalized per-round rows when available;
4. steady-state summaries from `round >= 8` by default;
5. seam classification booleans;
6. capability flags showing whether dispatch-seam and worker metrics are
   available at full-run and per-round granularity.

The FreeBSD path no longer assumes only one top-level artifact shape.

It can now recover the two M14 benchmarks from:

1. `benchmarks{}` dictionaries;
2. `lanes[]`, `runs[]`, or `modes[]` arrays with `mode` fields;
3. direct round-row containers such as `round_snapshots[]` or `rows[]`;
4. explicit `steady_state` / `steadyState` summaries when present.

## Canonical Metrics

The extractor maps platform-specific names into canonical M14 names so the
comparison rule can stay simple:

1. `pthread_workqueue_addthreads_requested_threads`
   and FreeBSD `reqthreads_*`
   become `worker_requested_threads`;
2. `pthread_workqueue_addthreads_calls`
   becomes `worker_addthreads_calls`;
3. `thread_enter_*`
   becomes `worker_thread_enter`;
4. `thread_return_*`
   becomes `worker_thread_return`;
5. `root_*`
   becomes `dispatch_root_*`.

That means the compare step can reason about one worker-request series and one
dispatch-root seam series without hard-coding platform-specific spellings.

## What The Compare CLI Does

`scripts/benchmarks/compare-m14-benchmarks.py` consumes one normalized FreeBSD
artifact and one normalized macOS artifact.

It computes:

1. primary-lane steady-state ratios for
   `dispatch_root_push_mainq_default_overcommit`,
   `dispatch_root_poke_slow_default_overcommit`, and
   `worker_requested_threads`;
2. control-lane zero-ness for the two main seam metrics;
3. same-qualitative-split validation from the classification booleans.

The outcome matches the M14 decision language:

1. `stop_tuning_this_seam`
2. `freebsd_likely_still_has_coalescing_gap`
3. `inconclusive`

The compare policy now distinguishes two bands:

1. a strict `1.50x` band that is still reported per metric;
2. an “about `1.5x`” decision band, defaulting to `1.65x`, which matches the
   earlier M14 note and the existing macOS-report decision logic.

That matters because the current reference pair,
`3.21 / round` on FreeBSD vs about `2.04 / round` on macOS, is slightly above
strict `1.50x` but still fits the intended “about `1.5x`” stop boundary.

The compare CLI can also write one machine-readable decision file with
`--json-out`.

## Compare Runner

`scripts/benchmarks/run-m14-compare.sh` turns the normalization and compare
steps into one repeatable lane.

It accepts:

1. a FreeBSD source path via `TWQ_M14_FREEBSD_SOURCE`, or `auto` to use
   discovery;
2. `benchmark-json`, `round-snapshots`, `serial-log`, or already `normalized`
   FreeBSD input;
3. a macOS source that is either a raw M14 report, already normalized, or
   `auto`;
4. `TWQ_M14_DISCOVER_ROOTS` as a colon-separated discovery search path;
5. the same steady-state and ratio knobs used by the compare CLI.

The runner writes:

1. `freebsd.normalized.json`
2. `macos.normalized.json`
3. `comparison.json`
4. `summary.txt`
5. `report.txt`
6. `freebsd.input-validation.json`
7. `macos.input-validation.json`
8. `freebsd.normalized-validation.json`
9. `macos.normalized-validation.json`
10. `freebsd.input-audit.json`
11. `macos.input-audit.json`
12. `discovery.json` when discovery is used

inside one timestamped artifact directory under `../artifacts/benchmarks`.

## Discovery And Reporting

`scripts/benchmarks/discover-m14-artifacts.py` scans one or more roots for:

1. FreeBSD `round-snapshots`, `benchmark-json`, or normalized candidates;
2. macOS M14 reports or normalized candidates;
3. a preferred “best” candidate for each side plus the full candidate list;
4. a pair-aware `pairs.best` selection that scores FreeBSD/macOS pairs on
   workload tuple match, steady-state window match, and individual
   comparison-readiness.

`scripts/benchmarks/summarize-m14-compare.py` turns `comparison.json` plus the
normalized inputs into a more reviewable decision artifact with:

1. workload tuple lines for both primary and control lanes;
2. classification and control-specificity status;
3. primary metric ratios and band results;
4. warnings when the comparison is missing key ingredients.

## Artifact Validation

The lane now validates both raw inputs and normalized outputs before treating an
artifact as comparison-ready.

`scripts/benchmarks/validate-m14-artifacts.py` accepts:

1. raw macOS reports;
2. raw FreeBSD benchmark JSON;
3. raw FreeBSD round-snapshot JSON;
4. raw FreeBSD serial logs;
5. already normalized M14 artifacts.

It normalizes raw inputs through `extract-m14-benchmark.py` in a temporary
staging path, then checks one consistent readiness contract:

1. primary benchmark exists and `status=ok`;
2. workload tuple is complete;
3. steady-state summary is present and non-empty;
4. primary classification booleans are complete;
5. primary decision metrics are present;
6. control-lane data exists when the artifact claims stop-decision readiness.

Discovery now carries that validation state per candidate and prefers
comparison-ready artifacts over merely newer ones. The shell runner now saves
validation artifacts and fails fast on malformed inputs before comparison.

## Schema Audit

The lane now has a raw-artifact schema audit pass in
`scripts/benchmarks/audit-m14-artifact-schema.py`.

This solves a different problem from validation.

Validation answers:

1. is the artifact comparison-ready?
2. is it fair enough to support a stop/tune decision?

Schema audit answers:

1. which raw workload fields are present but not mapped?
2. which raw classification keys are present but not recognized?
3. which full-run, steady-state, or per-round metric keys are being dropped?
4. whether the artifact is still usable despite that drift.

The validator now includes a compact schema-audit summary in its output and adds
warnings, not blockers, when a raw artifact is comparison-ready but still
contains unmapped fields.

That means the first real FreeBSD M14 artifact can now succeed with explicit
drift evidence instead of silently losing new fields.

Discovery is also pair-aware now.

When multiple individually valid artifacts exist, the lane no longer assumes
that the newest FreeBSD artifact and the newest macOS artifact form the best
comparison. `pairs.best` preserves the best matched pair, and
`run-m14-compare.sh` now uses that pair directly when both sides are `auto`.

Discovery is now also drift-aware.

When two artifacts are equally valid and equally well matched, the lane prefers
the one with fewer unmapped raw fields. That keeps a clean known-good artifact
ahead of a newer but driftier one until the extractor learns the new schema.

## Decision Integrity

The compare lane now treats fairness checks as part of the decision, not just
as report decoration.

`scripts/benchmarks/compare-m14-benchmarks.py` now validates:

1. primary workload tuple match on `rounds`, `tasks`, and `delay_ms`;
2. control workload tuple match for stop-decision specificity;
3. primary benchmark status equals `ok` on both sides;
4. steady-state start-round match;
5. presence of the primary seam metrics needed for a decision;
6. completeness of the primary classification booleans.

The output now carries:

1. `validation.blockers`
2. `validation.stop_blockers`
3. `validation.warnings`
4. `validation.decision_ready`
5. `validation.stop_ready`

That means a superficially similar rate pair no longer produces a confident
decision when the underlying workload match is not fair.

## Fixture Verification

The repo now has version-controlled M14 fixtures instead of relying only on
live local artifacts:

1. `fixtures/benchmarks/m14-macos-report-minimal.json`
2. `fixtures/benchmarks/m14-freebsd-reference.json`
3. `fixtures/benchmarks/m14-freebsd-gap.json`
4. `fixtures/benchmarks/m14-freebsd-worker-only-legacy.json`
5. `fixtures/benchmarks/m14-round-snapshots-fixture.json`
6. `fixtures/benchmarks/m14-freebsd-workload-mismatch.json`
7. `fixtures/benchmarks/m14-round-snapshots-invalid.json`
8. `fixtures/benchmarks/invalid-m14-report.json`
9. `fixtures/benchmarks/m14-freebsd-reference-drift.json`
10. `fixtures/benchmarks/m14-macos-report-drift.json`

Those fixtures cover:

1. raw macOS-report normalization;
2. a FreeBSD reference case that should stop tuning the seam;
3. a FreeBSD gap case that should still recommend tuning;
4. a worker-only legacy case that must remain inconclusive;
5. a direct FreeBSD round-snapshot case that should normalize and compare
   without first being rewritten into the older benchmark-json shape;
6. discovery of the best available FreeBSD/macOS inputs from mixed roots;
7. auto-runner mode using that discovery output;
8. raw-artifact validation and fail-fast runner rejection on malformed inputs;
9. pair-aware discovery, where the auto-runner must choose an older matched
   FreeBSD artifact over a newer mismatched one;
10. a workload-mismatch case that must remain `inconclusive` even when the
   rates themselves would otherwise look close enough;
11. schema-drift cases that remain comparison-ready but surface explicit audit
   warnings and influence discovery preference.

`scripts/benchmarks/verify-m14-tooling.py` runs the fixture lane end to end and
checks all three decision outcomes plus the shell runner output.

Run it with:

```sh
python3 scripts/benchmarks/verify-m14-tooling.py
```

## Verification

The local verification pass now covers three important cases:

1. normalizing the existing macOS report at
   `../artifacts/macos/m14-introspection-final/m14-report.json`;
2. comparing that normalized macOS artifact against a synthetic FreeBSD
   reference carrying the published steady-state
   `3.21 / 3.21 / 18.36` rates and the expected classification booleans;
3. comparing the same macOS artifact against the older worker-only
   `benchmarks/baselines/m13-initial.json` input.

Those checks prove:

1. the compare CLI now returns `stop_tuning_this_seam` for the intended
   “about `1.5x`” reference case, while still reporting that the strict
   `1.50x` band is exceeded;
2. `scripts/benchmarks/run-m14-compare.sh` produces the same stop result and
   saves the decision to `comparison.json`;
3. older FreeBSD inputs that lack dispatch-seam steady-state metrics remain
   `inconclusive` rather than being over-interpreted.
4. fixture-backed verification now covers the `stop`, `tune`, and
   `inconclusive` branches under version-controlled inputs.
5. the direct `round-snapshots` source kind and filename auto-detection path
   both normalize correctly into the common schema.
6. discovery now finds the best available FreeBSD/macOS candidates and the
   runner can operate from `auto` sources.
7. a workload mismatch on `tasks` now blocks the decision and is surfaced
   explicitly in both `comparison.json` and `report.txt`.

## Honest Limitation

The repo-side FreeBSD extractor can summarize per-round worker-request deltas
today, but per-round dispatch seam counters are only present if the source
artifact actually contains them.

So this milestone is intentionally honest:

1. if the FreeBSD input only has full-run libdispatch counters, the normalized
   output shows that;
2. if the FreeBSD input has newer round snapshots, the extractor will carry the
   recognized per-round worker metrics through automatically;
3. dispatch-seam per-round gaps remain visible as capability flags instead of
   being silently invented.

## Intended Workflow

Normalize macOS:

```sh
python3 scripts/benchmarks/extract-m14-benchmark.py \
  --macos-report /path/to/m14-report.json \
  --out /tmp/macos-m14.json
```

Normalize FreeBSD from structured JSON:

```sh
python3 scripts/benchmarks/extract-m14-benchmark.py \
  --freebsd-benchmark-json /path/to/freebsd-benchmark.json \
  --out /tmp/freebsd-m14.json
```

Normalize FreeBSD from a round-snapshot artifact:

```sh
python3 scripts/benchmarks/extract-m14-benchmark.py \
  --freebsd-round-snapshots-json /path/to/m14-round-snapshots.json \
  --out /tmp/freebsd-m14.json
```

Normalize FreeBSD directly from a serial log:

```sh
python3 scripts/benchmarks/extract-m14-benchmark.py \
  --freebsd-serial-log /path/to/guest.serial.log \
  --out /tmp/freebsd-m14.json
```

Compare the two normalized artifacts:

```sh
python3 scripts/benchmarks/compare-m14-benchmarks.py \
  /tmp/freebsd-m14.json \
  /tmp/macos-m14.json
```

Run the whole lane end to end:

```sh
TWQ_M14_FREEBSD_SOURCE=/path/to/freebsd-m14.json \
sh scripts/benchmarks/run-m14-compare.sh
```

If the filename already matches `*round-snapshots*.json`, the runner will
auto-detect that source kind.

Discover the latest likely inputs:

```sh
python3 scripts/benchmarks/discover-m14-artifacts.py
```

Run the whole lane from discovery:

```sh
TWQ_M14_FREEBSD_SOURCE=auto \
TWQ_M14_MACOS_REPORT=auto \
sh scripts/benchmarks/run-m14-compare.sh
```
