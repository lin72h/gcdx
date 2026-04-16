# M14 macOS Comparison Kit

This directory holds the native macOS comparison kit for the M13 -> M14 seam
decision.

Primary lane:

1. `swift.dispatchmain-taskhandles-after-repeat`

Secondary control lane:

1. `dispatch.main-executor-resume-repeat`

## What This Kit Does

The repo now has two macOS measurement paths.

Stock-first path:

1. checks which seams are actually visible on shipping macOS;
2. records DTrace and `xctrace` reality on the current host;
3. normalizes raw workload logs into one JSON artifact.

Introspection path:

1. runs the same workloads under `/usr/lib/system/introspection`;
2. installs libdispatch queue-item enqueue and runtime worker-request hooks;
3. emits per-round root-push and worker-request counters for the M14 seam;
4. produces one comparison-ready JSON report with a stop-versus-tune read.

The introspection path artifact directory contains:

1. the exact native Swift repeat workload log;
2. one C control-lane log with the same `64 x 8 x 20ms` default tuple;
3. stock symbol visibility and runtime-resolvability for the key seams;
4. raw host metadata;
5. one normalized JSON file;
6. one M14 comparison report JSON.

That answers the first M14 question quickly:

1. what is exported or resolvable on stock macOS;
2. what is blocked by SIP or DTrace privileges;
3. whether a stock-binary run can plausibly attribute
   `main_q -> default.overcommit`;
4. whether to bail out immediately to a custom-build counter lane.

## Stock-First Usage

Build the native macOS workloads:

```sh
sh scripts/macos/prepare-m14.sh
```

Run the default stock pass:

```sh
sh scripts/macos/run-m14-stock.sh
```

Override the tuple if needed:

```sh
TWQ_REPEAT_ROUNDS=64 \
TWQ_REPEAT_TASKS=8 \
TWQ_REPEAT_DELAY_MS=20 \
sh scripts/macos/run-m14-stock.sh
```

Inspect only stock symbol visibility and tool availability:

```sh
python3 scripts/macos/check-m14-symbols.py
```

## Introspection Usage

Run the full stock-binary introspection pass:

```sh
sh scripts/macos/run-m14-introspection.sh
```

Override the tuple if needed:

```sh
TWQ_REPEAT_ROUNDS=64 \
TWQ_REPEAT_TASKS=8 \
TWQ_REPEAT_DELAY_MS=20 \
sh scripts/macos/run-m14-introspection.sh
```

That path uses:

```sh
DYLD_LIBRARY_PATH=/usr/lib/system/introspection
```

and writes both:

1. `m14-run.json`
2. `m14-report.json`

## Current Stock Expectation

The stock inspection is expected to split the seams into two groups.

Likely stock candidates:

1. `_pthread_workqueue_addthreads`

Likely source-only seams, not useful stock symbol assumptions:

1. `_dispatch_root_queue_push`
2. `_dispatch_root_queue_poke_slow`
3. `_dispatch_queue_cleanup2`
4. `_dispatch_lane_barrier_complete`

That is because Apple source still gives the right call chain, but modern macOS
does not necessarily export those internal dispatch functions as live symbols.

## Fallback Custom-Build Plan

If either:

1. the root-queue seam is not exported or runtime-resolvable; or
2. DTrace is blocked by SIP or missing privileges;

the next step is no longer immediately “custom build.” First try the
introspection path, because it can still recover queue-item and worker-request
counts on stock binaries.

Move to the custom-build path only if the introspection lane cannot classify
the seam you need.

The fallback should add explicit counters or USDT-style probes at:

1. `_dispatch_queue_cleanup2`
2. `_dispatch_lane_barrier_complete`
3. `_dispatch_root_queue_push`
4. `_dispatch_root_queue_poke_slow`
5. `_pthread_workqueue_addthreads`

The decision rule remains the same:

1. same qualitative seam and same order of magnitude means stop tuning the
   FreeBSD cleanup handoff seam;
2. materially lower macOS steady-state push or poke rate means FreeBSD likely
   still has a coalescing gap.

## Instruments

`xctrace` support is recorded in the stock symbol JSON.

Treat Instruments as supporting evidence only:

1. useful for wakeups, runloop activity, Swift task timing, and signpost
   alignment;
2. not decision-grade proof of `main_q -> default.overcommit` root pushes.
