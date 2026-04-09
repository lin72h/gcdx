# M12 Swift 6.3 Stock-Dispatch Boundary

## Purpose

This note records an important correction to the Swift validation story:
the local Swift 6.3 stock toolchain remains valuable, but its `libdispatch`
must not be treated as a TWQ-backed control lane.

## What Changed

Earlier guest results showed that some Swift workloads completed on:

1. stock-dispatch plus stock `libthr`;
2. stock-dispatch plus custom `libthr`;
3. the full staged custom-`libdispatch` plus custom-`libthr` TWQ lane.

That initially made the stock-dispatch plus custom-`libthr` lane look stronger
than it really was.

The new evidence says otherwise.

## Evidence

### 1. Symbol-level difference

The staged custom `libdispatch.so` has dynamic references to the workqueue
entry points:

1. `_pthread_workqueue_init`
2. `_pthread_workqueue_addthreads`
3. `_pthread_workqueue_supported`

The stock Swift 6.3 toolchain `libdispatch.so` does not reference those
symbols at all.

That means the stock toolchain dispatch runtime is not a hidden TWQ client.

### 2. Guest runtime control behavior

The targeted guest probe
`dispatchmain-taskgroup-after-stockdispatch-customthr` completed successfully
with:

1. `"status":"ok"`
2. `"completed":8`
3. `"sum":28`

But its before/after TWQ stats stayed flat across the probe window:

1. `kern.twq.reqthreads_count`
2. `kern.twq.thread_enter_count`

Both were unchanged.

## Correct Interpretation

The stock Swift 6.3 toolchain dispatch lane is still useful, but only as:

1. a control for "does this Swift behavior work at all on local FreeBSD Swift
   6.3?";
2. a comparison lane against the staged TWQ-backed dispatch lane.

It is not a control for:

1. "is this Swift behavior using the TWQ-backed dispatch path?"

The staged custom `libdispatch` lane remains the only meaningful Swift/TWQ
validation lane in this repo.

## Why It Matters

This prevents a specific false positive:

1. a Swift workload can succeed on stock-dispatch plus custom `libthr`;
2. that success does not imply the stock dispatch runtime is using the
   pthread_workqueue bridge;
3. therefore that success does not clear the staged custom `libdispatch` when
   the same workload fails on the real TWQ lane.

In practical terms, the remaining delayed-child-completion bug is still a
custom-`libdispatch` / TWQ problem until proven otherwise.

## Operational Rule

For the current project phase:

1. use stock Swift 6.3 dispatch as the Swift/runtime comparison lane;
2. use staged custom `libdispatch` plus custom `libthr` as the real TWQ lane;
3. require TWQ counter movement before calling any Swift workload
   "TWQ-backed".
