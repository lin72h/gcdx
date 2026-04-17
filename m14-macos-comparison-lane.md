# M14 macOS Comparison Lane

## Purpose

`M14` is now a matched-behavior comparison lane, not another speculative
FreeBSD-side tuning pass.

The current question is narrow:

1. does the native macOS Swift `dispatchMain()` repeat shape drive the same
   main-queue to `default.overcommit` handoff seam that FreeBSD now exposes;
2. if so, is the steady-state rate close enough that FreeBSD should stop
   tuning this seam;
3. or is macOS materially lower, which would justify more coalescing work on
   the FreeBSD side.

## Primary Workload

The primary workload is the Swift `dispatchMain()` repeat shape equivalent to
`dispatchmain-taskhandles-after-repeat`:

1. `64` rounds
2. `8` delayed child completions per round
3. `20ms` delay
4. parent awaiting on the main-thread lane

The pure-C `main-executor-resume-repeat` lane remains a secondary control, not
the deciding seam.

## Current FreeBSD Readiness

The FreeBSD side now has:

1. per-round TWQ counters in the repeat lanes;
2. per-round libdispatch root snapshot counters for the Swift repeat lane and
   the C repeat lane;
3. a durable schema-`3` extractor in
   [extract-m13-baseline.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/extract-m13-baseline.py);
4. a comparison script in
   [compare-m14-steady-state.py](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/benchmarks/compare-m14-steady-state.py).

The current checked-in FreeBSD reference artifact is:

[m14-freebsd-round-snapshots-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json)

Its current steady-state (`8-63`) FreeBSD reference is:

1. `root_push_mainq_default_overcommit ~= 3.21 / round`
2. `root_poke_slow_default_overcommit ~= 3.21 / round`
3. `kern.twq.reqthreads_count ~= 18.36 / round`

## macOS Intake Shape

Use the template:

[m14-macos-template.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/m14-macos-template.json)

The current normalized macOS result is:

[m14-macos-stock-introspection-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-macos-stock-introspection-20260416.json)

The required steady-state metrics are:

1. `root_push_mainq_default_overcommit`
2. `root_poke_slow_default_overcommit`
3. `pthread_workqueue_addthreads_requested_threads`

Supporting metrics:

1. `pthread_workqueue_addthreads_calls`
2. `root_push_empty_default`
3. `root_poke_slow_default`
4. `root_push_source_default`

The comparison window is rounds `8-63`.

If raw per-round arrays are unavailable, the report may still carry
`steady_state_per_round` metrics. The comparison tool treats those as the
authoritative steady-state rates.

## Comparison Command

```sh
sh scripts/benchmarks/run-m14-comparison.sh
```

To compare against the checked-in FreeBSD reference without booting a guest:

```sh
TWQ_M14_FREEBSD_JSON=benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json \
  sh scripts/benchmarks/run-m14-comparison.sh
```

The low-level comparator itself remains directly usable:

```sh
python3 scripts/benchmarks/compare-m14-steady-state.py \
  benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json \
  benchmarks/baselines/m14-macos-stock-introspection-20260416.json
```

## Current Result

The first stock-macOS comparison result is now in hand.

Primary steady-state (`8-63`) comparison:

1. FreeBSD `root_push_mainq_default_overcommit ~= 3.21 / round`
   vs macOS `~= 2.04 / round`
2. FreeBSD `root_poke_slow_default_overcommit ~= 3.21 / round`
   vs macOS `~= 2.04 / round`
3. FreeBSD `pthread_workqueue` requested threads `~= 18.36 / round`
   vs macOS `~= 11.21 / round`

The qualitative split matches:

1. the Swift lane carries main-queue handoff traffic into
   `default.overcommit` on both systems;
2. the non-overcommit default root carries source traffic on both systems;
3. the C control lane stays clean on this seam.

Current verdict:

1. stop tuning this seam on FreeBSD;
2. the macOS rates are lower, but only by about `1.58x` on the primary seam,
   not by anything close to the stronger `2x` concern boundary.

## Decision Rule

Stop tuning this seam if:

1. macOS shows the same qualitative split:
   timer/source traffic on `default`,
   main-queue handoff traffic on `default.overcommit`;
2. the primary steady-state rates are within about `1.5x`.
   A modest borderline result between that heuristic and the stronger `2x`
   concern boundary should still be treated as a stop if the qualitative seam
   matches cleanly.

Keep tuning this seam if:

1. macOS matches the workload shape and classification;
2. FreeBSD remains about `2x` higher on
   `root_push_mainq_default_overcommit` or
   `root_poke_slow_default_overcommit`.

Otherwise treat the result as `review`, not as an automatic tuning order.
