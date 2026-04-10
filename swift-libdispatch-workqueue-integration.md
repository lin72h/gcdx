# GCDX Swift, `libdispatch`, and `pthread_workqueue`

## Purpose

This note documents the architecture boundary between Swift concurrency,
`libdispatch`, and the kernel workqueue layer in `GCDX`.

It exists to answer a recurring question:

> If Swift concurrency on macOS uses a "cooperative pool", does that reduce the
> importance of `libdispatch` and kernel workqueue integration?

The answer is no.

On macOS, Swift's cooperative execution model still depends heavily on
`libdispatch`, and `libdispatch` in turn depends heavily on XNU workqueue
support.

## Short Answer

The clean mental model is:

1. Swift owns jobs, tasks, continuations, and executor semantics.
2. `libdispatch` owns the queueing surface and the bridge between Swift jobs and
   worker threads.
3. the kernel workqueue owns worker-thread admission, QoS-aware concurrency
   limits, and thread provisioning.

So the "cooperative pool" is not an independent replacement for `libdispatch`.
It is a specialized execution mode implemented through `libdispatch` and backed
by kernel workqueue support.

## Why This Matters To This Project

`GCDX` is not trying to improve only the C library layer in isolation.

The actual value proposition is:

1. provide real kernel-backed `pthread_workqueue` semantics on a FreeBSD-based
   system;
2. make `libdispatch` behave like a native system service rather than a
   compatibility library;
3. let higher-level consumers, especially Swift, inherit those semantics.

That means Swift is both:

1. a major product target;
2. one of the best integration tests for whether the lower C stack is behaving
   like a real platform.

## The Layering On macOS

### Swift runtime layer

Swift concurrency understands:

1. tasks;
2. task groups;
3. continuations;
4. priorities;
5. cooperative yielding;
6. executor selection.

But Swift does not create a separate kernel scheduler for these jobs.

On dispatch-backed platforms, the Swift runtime routes global-executor work into
`libdispatch`.

Useful local reference:

- `../nx/apple-opensource-libdispatch/private/queue_private.h`
- `/Users/me/wip-rnx/nx-/swift-source-vx-modified/workspace/swift/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp`

### `libdispatch` layer

`libdispatch` is where Swift jobs become queue work associated with real worker
threads.

This layer is responsible for:

1. enqueueing Swift jobs onto dispatch-managed queues;
2. associating those queues with particular worker-pool behavior;
3. asking the workqueue subsystem for more worker threads when needed;
4. handling timer and delayed execution paths that Swift async code also relies
   on.

In Apple's source, the key interface is `dispatch_async_swift_job`.

The comments and call sites make it clear that Swift jobs are expected to run on
cooperative queues, not on some wholly separate Swift-only scheduler detached
from dispatch.

Useful local references:

- `../nx/apple-opensource-libdispatch/private/queue_private.h`
- `../nx/apple-opensource-libdispatch/src/queue.c`

### Kernel workqueue layer

The kernel does not schedule Swift jobs directly. It schedules threads.

The workqueue layer is the piece that gives `libdispatch` a dynamic worker pool
with policy:

1. how many workers may run;
2. which QoS bucket they belong to;
3. when more workers should be admitted;
4. when pressure at one priority should constrain another;
5. how cooperative worker classes differ from constrained and overcommit ones.

On Apple platforms, the cooperative pool is a first-class concept in the kernel
workqueue implementation, not just a user-space convention.

Useful local references:

- `../nx/apple-opensource-xnu/bsd/pthread/pthread_workqueue.c`
- `../nx/apple-opensource-xnu/bsd/pthread/workqueue_syscalls.h`

## What "Cooperative Pool" Actually Means

The word "cooperative" can be misleading.

It does not mean:

1. Swift bypasses `libdispatch`;
2. the kernel stops mattering;
3. Swift manages all worker threads by itself.

It does mean:

1. Swift jobs are expected to cooperate with the executor model by yielding when
   appropriate;
2. `libdispatch` uses a special cooperative queue mode for those jobs;
3. the kernel workqueue layer applies a distinct worker/admission policy for
   those cooperative threads.

So "cooperative" changes the policy and execution style, but it does not remove
the dispatch/workqueue stack underneath it.

## Evidence From The Local Source Trees

### Swift runtime uses dispatch entry points

In the local Swift runtime source:

- `/Users/me/wip-rnx/nx-/swift-source-vx-modified/workspace/swift/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp`

the global executor code:

1. uses `dispatch_async_swift_job` when available;
2. creates or selects cooperative dispatch queues;
3. uses dispatch timer APIs such as `dispatch_source_create` and
   `dispatch_after_f` for delayed scheduling paths.

This is direct evidence that Swift's dispatch-backed executor path is still
rooted in `libdispatch`.

### Apple `libdispatch` has explicit cooperative queue support

In:

- `../nx/apple-opensource-libdispatch/private/queue_private.h`
- `../nx/apple-opensource-libdispatch/src/queue.c`

the Apple tree exposes:

1. `dispatch_async_swift_job`;
2. cooperative queue handling;
3. cooperative root-queue logic;
4. cooperative worker-thread requests via
   `_pthread_workqueue_add_cooperativethreads(...)`.

That is strong evidence that the cooperative executor path is a dispatch path,
not a dispatch alternative.

### XNU has cooperative workqueue support in the kernel

In:

- `../nx/apple-opensource-xnu/bsd/pthread/workqueue_syscalls.h`
- `../nx/apple-opensource-xnu/bsd/pthread/pthread_workqueue.c`

the XNU side defines:

1. `WQ_FLAG_THREAD_COOPERATIVE`;
2. cooperative queue scheduling counters;
3. cooperative allowance logic;
4. cooperative request selection and admission.

That is the kernel half of the same design.

## What This Means For Our FreeBSD Port

Our project does not need to clone every Apple-specific runtime feature to be
valuable.

But it does need to preserve the important architecture truth:

1. higher-level async runtimes should not sit on an oblivious generic thread
   pool if the platform can provide better feedback;
2. `libdispatch` should be able to request worker threads using a real platform
   mechanism;
3. the kernel should be able to apply pressure, QoS-aware limits, and admission
   policy;
4. Swift should benefit from that through the dispatch layer.

This is why the current project sequence has been:

1. build the kernel `TWQ` substrate;
2. build the `libthr` bridge;
3. bring up a real `libdispatch` TWQ path;
4. use Swift workloads to validate integrated behavior.

## What We Have Already Proved

At this point, the project has already demonstrated the following on the
FreeBSD-side execution lane:

1. the kernel `TWQ` subsystem exists and boots in the guest;
2. `libthr` can speak the workqueue-oriented ABI;
3. staged `libdispatch` uses the real workqueue path;
4. backpressure and admission effects are observable from guest probes.

That means the core statement:

> kernel feedback can shape dispatch behavior on this platform

is already proven.

The remaining work is about how completely and naturally that benefit reaches
higher-level runtimes like Swift.

## What Swift Is Good For In This Repo

Swift work here should be understood in three different roles.

### 1. Product target

Swift is one of the main reasons to care about making `libdispatch` feel native
on this platform.

If Swift only sees a compatibility-thread-pool behavior, the platform remains
second-class compared with macOS.

### 2. Integration validator

Swift exercises behaviors that simple C probes only partially cover:

1. delayed child completion;
2. task-group suspension and resume;
3. executor-driven fan-out;
4. timer and continuation interactions.

These are high-value integration tests for the lower C stack.

### 3. Diagnostic control lane

Swift is useful even when it exposes a lower-layer problem.

A Swift failure can help distinguish:

1. kernel/TWQ bugs;
2. `libthr` bridge bugs;
3. staged `libdispatch` bugs;
4. runtime-boundary mismatches between Swift and dispatch.

That is why the Swift probes in this repo are small and targeted instead of
trying to prove everything at once.

## Important Current Boundary

There is one operational rule that must stay explicit:

The stock local Swift 6.3 `libdispatch` lane is not the same thing as the staged
TWQ-backed dispatch lane.

The stock Swift toolchain is still useful as:

1. a runtime comparison lane;
2. a control for "does this Swift workload work at all on FreeBSD Swift?"

But it is not proof that the workload used our real workqueue integration.

That distinction is documented in:

- `./m12-swift63-stockdispatch-boundary-progress.md`

For any Swift workload that is meant to validate this port, TWQ counters must
move. Otherwise the workload may only be exercising the stock dispatch runtime.

## Practical Porting Rule

When evaluating Swift-related work in this repo, use this decision rule:

1. if the question is "does the basic workqueue machinery function?", start
   with C probes;
2. if the question is "does higher-level asynchronous behavior inherit the
   right semantics?", use Swift probes;
3. if the question is "which layer is wrong?", compare stock and staged runtime
   lanes and require TWQ counter deltas before drawing conclusions.

## Bottom Line

Swift's cooperative executor on macOS is not evidence that `libdispatch` and
kernel workqueue features are less important.

It is evidence that Apple built a tighter integration stack:

1. Swift defines the async work model;
2. `libdispatch` defines the queueing and worker-request model;
3. the kernel workqueue defines the actual worker-pool policy.

That is exactly why this project's `pthread_workqueue` and `libdispatch` work
matters so much for Swift on a FreeBSD-based system.

## Related Notes

- `./swift-integration-rationale.md`
- `./freebsd-swift63-toolchain-reference.md`
- `./m10-libdispatch-bringup-progress.md`
- `./m11-5-sustained-workload-progress.md`
- `./m11-apple-libdispatch-exploration.md`
- `./m12-swift-runtime-matrix-progress.md`
- `./m12-swift63-stockdispatch-boundary-progress.md`
