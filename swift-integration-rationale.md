# Swift Integration Rationale

## Purpose

This note explains why recent work in this repo spends meaningful time on Swift,
even though the core porting target is the C layer:

- kernel `TWQ` / `pthread_workqueue`-style support
- `libthr` bridge
- `libdispatch`

The short answer is:

> Swift is both a first-class product target of this project and the best
> high-value test vehicle for the C stack underneath it.

## Core Position

Swift work in this repo is **not** a side project and **not** a shift away from
`libdispatch` or `pthread_workqueue`.

It serves two purposes at once:

1. **Feature goal**
   Swift concurrency is one of the main reasons to do this port at all. A
   FreeBSD-based system with real kernel-backed `libdispatch` semantics is much
   more valuable if Swift can benefit from it directly.

2. **Diagnostic lane**
   Swift is an excellent way to exercise the real integrated behavior of:
   - `/usr/src/sys/kern/kern_thrworkq.c`
   - `/usr/src/lib/libthr/thread/thr_workq.c`
   - the staged custom `libdispatch`

## What The C Layer Already Proved

Before the recent Swift-focused work, the project already proved the basic C
stack was real:

- the kernel `TWQ` subsystem exists and boots in the guest
- the `bhyve` lane is real and automated
- the custom `libthr` bridge works
- staged `libdispatch` runs on the `TWQ` path
- pressure, admission, narrowing, and lifecycle behavior are observable

That earlier work is captured in:

- [m10-libdispatch-bringup-progress.md](./m10-libdispatch-bringup-progress.md)
- [m11-5-sustained-workload-progress.md](./m11-5-sustained-workload-progress.md)
- [m11-6-timeout-isolation-progress.md](./m11-6-timeout-isolation-progress.md)

At that point, adding more narrow C-only smoke tests would have had diminishing
returns.

## Why Swift Became The Right Next Layer

Swift workloads exercise integration surfaces that the simpler C probes only
touch partially or not at all:

- delayed resumption
- `TaskGroup` fan-out and completion
- suspension and resume ordering
- executor-style queue behavior
- interaction between dispatch-managed work and Swift-managed task structure

Those are exactly the places where a `pthread_workqueue`-powered dispatch stack
either feels real or still behaves like a compatibility path.

So the Swift lane is not replacing C validation. It is forcing the C stack to
behave correctly under realistic higher-level use.

## Why This Still Counts As C-Layer Debugging

Even when the symptom appears in Swift, the debugging target usually stays in
the lower stack.

The current workflow is:

1. reproduce a realistic failure with a small Swift probe
2. compare behavior across staged/runtime combinations
3. use those controls to identify which C layer is actually responsible

This matters because a Swift failure does **not** automatically mean “Swift is
broken.”

Often it means one of these is wrong:

- custom `libdispatch`
- custom `libthr`
- kernel `TWQ` accounting or admission
- an interaction boundary between Swift concurrency and dispatch

## What Swift Already Helped Narrow

The Swift lane has already produced more precise results than generic C stress
tests alone.

### First Narrowing

Earlier, a suspended `TaskGroup` workload timed out in the guest. That looked
like a broad Swift-concurrency problem.

Further isolation showed that was too broad:

- `Task.yield` worked in some paths
- continuation-resume paths worked
- several `dispatchMain()`-rooted Swift probes worked

That moved the problem away from “Swift generally” and toward a narrower staged
runtime boundary.

### Second Narrowing

The strongest result came from the runtime matrix documented in:

- [m12-swift-runtime-matrix-progress.md](./m12-swift-runtime-matrix-progress.md)
- [m12-swift-executor-delay-boundary-progress.md](./m12-swift-executor-delay-boundary-progress.md)

The same Swift binaries were run against three guest lanes:

1. stock `libdispatch` + stock `libthr`
2. stock `libdispatch` + custom `libthr`
3. custom staged `libdispatch` + custom `libthr` on the `TWQ` path

That showed:

- stock-dispatch + custom `libthr` succeeds
- full staged `libdispatch` + custom `libthr` fails only on a narrower delayed
  child-completion case

So Swift testing helped narrow blame **away** from:

- the FreeBSD kernel in general
- custom `libthr` in general
- “Swift concurrency” as a broad category

and **toward**:

- custom `libdispatch` delayed work / child completion on the `TWQ` path

That is exactly the kind of diagnosis we want.

## Working Rule For Future Work

When deciding whether to use Swift as part of the porting effort, follow this
rule:

1. Use C probes to prove basic mechanics.
2. Use Swift probes to expose realistic integrated behavior.
3. Use guest runtime matrices to decide which lower layer is actually at fault.

In other words:

> Swift is not the replacement for the C-layer port. It is the best realistic
> pressure test for whether the C-layer port is actually good enough.

## What This Means Operationally

For this repo, Swift work currently has three roles:

1. **Toolchain lane**
   The local Swift 6.3 setup and staging process are documented in
   [freebsd-swift63-toolchain-reference.md](./freebsd-swift63-toolchain-reference.md).

2. **Validation lane**
   A stable Swift guest validation profile exists and should stay green while
   new diagnostics are added.

3. **Diagnostic lane**
   Small targeted Swift probes are used to isolate failures that simple C
   workload generators do not explain clearly enough.

## Practical Interpretation

If future work appears “too Swift-focused,” the right question is not:

> Why are we leaving the C layer?

The right question is:

> Which lower C layer is this Swift workload helping us distinguish?

If the answer is clear, the Swift work is justified.

If the answer is not clear, the Swift probe should be simplified or replaced
with a better control.
