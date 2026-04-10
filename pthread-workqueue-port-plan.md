# GCDX `pthread_workqueue` Port Plan for FreeBSD 15

## Status

This document is a strategy and implementation plan, not an implementation.
It is written for the local trees currently available under `../nx/`.
The concrete target FreeBSD tree is now confirmed at `/usr/src`, and the local
ports tree is confirmed at `/usr/ports`.

Project name:

1. this implementation effort is now named `GCDX`.

## Objective

Port the kernel backed `pthread_workqueue` capability needed by modern Apple
`libdispatch` and Swift concurrency onto a current FreeBSD 15 codebase, while
keeping the scope intentionally narrow:

1. Bring in only the thread workqueue facility and the minimum userland bridge
   required for "real" `libdispatch`.
2. Avoid unrelated Darwin compatibility layers such as Mach IPC, launchd,
   workloops, event manager machinery, and general macOS emulation.
3. Build a workflow that uses `bhyve` VMs for fast iteration, crash capture,
   and repeatable testing instead of rebooting the host into experimental
   kernels.

## Clarified Project Intent

The intended outcome is not "libdispatch works on FreeBSD somehow". FreeBSD
already has a compatibility path for that. The intended outcome is to make this
system feel like the strongest non-macOS platform for real `libdispatch`
semantics backed by a kernel workqueue facility.

Practical interpretation:

1. semantic compatibility with macOS `libdispatch` behavior matters more than
   ABI compatibility with stock FreeBSD;
2. upstream-quality engineering is the quality bar, even if upstream FreeBSD
   acceptance is not assumed;
3. the implementation should still feel native to FreeBSD and should not fight
   the kernel's overall design, especially the scheduler;
4. exact macOS feature parity is not required when a feature would be unnatural
   or invasive on FreeBSD;
5. first iterations should prioritize correct semantics and a meaningful kernel
   feedback loop before chasing macOS-level performance.

## Hard Constraints

1. The current directory is the strategy repo and should only contain durable,
   reviewable information.
2. Build products, object directories, VM images, crash dumps, and cloned
   source trees should live outside this directory.
3. The implementation must target current FreeBSD 15, not the older FreeBSD
   base used by `NextBSD`.
4. The end goal is not the Linux style shim path for `libdispatch`. The end
   goal is the workqueue backed path used by Apple's own stack.

## Design Bias

When there is a tradeoff, bias toward:

1. the most natural FreeBSD implementation that preserves the important
   `libdispatch` semantics;
2. gradual integration that can become cleaner and deeper over time;
3. semantic compatibility over ABI conservatism;
4. avoiding features that compete with or distort established FreeBSD kernel
   mechanisms;
5. being smarter than blindly copying Darwin internals.

## Local Reference Trees

Use the local checkouts and system trees for all analysis and future
implementation work:

| Path | Role | How to use it |
| --- | --- | --- |
| `/usr/src` | Primary target tree | Current FreeBSD 15 `stable/15` source tree to receive the port and serve as the authoritative rebase target |
| `/usr/ports` | Ports and packaging reference | Use for later userland packaging, dependency builds, and testing integration; not as a kernel donor |
| `../nx/NextBSD-NextBSD-CURRENT` | Primary kernel donor | Source of the FreeBSD native workqueue scheduler logic and kernel hook set |
| `../nx/apple-opensource-xnu` | Behavior reference only | Source of the modern workqueue op model and the direct interface expected by newer Apple userland |
| `../nx/apple-opensource-libdispatch` | End target userland reference | Source of the modern `libdispatch` workqueue initialization and narrowing behavior |
| `../nx/ravynos-darwin` | ABI and test reference | Source of `libsystem_pthread` private headers and useful `wq_*` tests |
| `../nx/swift-corelibs-libdispatch` | Practical portability and test reference | Source of a more portable libdispatch tree plus a useful regression suite |

## What Each Tree Is Good For

### 1. `/usr/src` is the actual rebase target

This tree is the one that matters most operationally.

Current local evidence:

1. `/usr/src/sys/conf/newvers.sh` reports `REVISION="15.0"` and
   `BRANCH="STABLE"`.
2. `/usr/src/UPDATING` is the `stable/15` update log.

Use `/usr/src` for:

1. the real donor-to-target hook audit;
2. all later kernel and `libthr` edits;
3. build integration and bhyve guest image generation;
4. long-term rebases as `stable/15` moves toward FreeBSD 15.1.

Because `stable/15` is a moving branch, record the exact commit or branch
state used for each milestone before starting implementation work.

### 2. `NextBSD` is the kernel algorithm donor

The useful local files are:

- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_thrworkq.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/sys/thrworkq.h`
- `../nx/NextBSD-NextBSD-CURRENT/sys/conf/files`
- `../nx/NextBSD-NextBSD-CURRENT/sys/conf/options`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/syscalls.master`
- `../nx/NextBSD-NextBSD-CURRENT/sys/sys/proc.h`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_proc.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_mutex.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_synch.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_thr.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_exec.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_exit.c`
- `../nx/NextBSD-NextBSD-CURRENT/sys/kern/p1003_1b.c`
- `../nx/NextBSD-NextBSD-CURRENT/lib/libthr/thread/thr_workq.c`

This tree already contains the FreeBSD native ideas that matter:

1. Per-process workqueue state.
2. Worker thread parking and reuse.
3. New-thread creation through FreeBSD thread creation paths.
4. Scheduler feedback hooks when a worker blocks or yields.
5. Cleanup on `exec` and process exit.

This is the correct donor for kernel structure, locking shape, and hook points.

### 3. Apple `xnu` is the modern interface reference

The useful local files are:

- `../nx/apple-opensource-xnu/bsd/pthread/workqueue_syscalls.h`
- `../nx/apple-opensource-xnu/bsd/pthread/pthread_workqueue.c`

This tree should not be ported wholesale. It is tightly coupled to:

1. Mach thread and port machinery.
2. `bsdthread` registration semantics.
3. turnstiles and XNU scheduling policy internals.
4. direct kevent delivery and workloops.
5. event manager behavior and other Darwin-specific features.

Use it for op names, lifecycle semantics, and the modern separation between
"request worker threads" and "queue user work".

### 4. Apple `libdispatch` defines the user visible target behavior

The useful local files are:

- `../nx/apple-opensource-libdispatch/src/internal.h`
- `../nx/apple-opensource-libdispatch/src/shims.h`
- `../nx/apple-opensource-libdispatch/src/queue.c`

These files establish three critical points:

1. Modern `libdispatch` can use `_pthread_workqueue_init` without requiring
   direct kevent workqueue delivery, as long as `KEVENT_FLAG_WORKQ` is not
   advertised.
2. Modern `libdispatch` asks for additional workers with
   `_pthread_workqueue_addthreads()`.
3. Modern `libdispatch` asks whether a worker should stop draining and return
   through `_pthread_workqueue_should_narrow()`.

### 5. `ravynOS` is the best local ABI shape reference

The useful local files are:

- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/private/workqueue_private.h`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/pthread.c`
- `../nx/ravynos-darwin/BSD/include/pthread_workqueue.h`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/tests/wq_limits.c`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/tests/wq_block_handoff.c`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/tests/wq_kevent.c`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/tests/wq_kevent_stress.c`
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/tests/wq_event_manager.c`

This local checkout does not contain a matching FreeBSD `sys/kern/kern_thrworkq.c`
tree, so it is not the kernel donor here. Its value is in:

1. private header definitions such as `PTHREAD_WORKQUEUE_SPI_VERSION`.
2. the modern userland SPI surface.
3. the `__workq_kernreturn` style control flow.
4. userland tests that can be reused later.

### 6. `swift-corelibs-libdispatch` is the practical regression harness

The useful local files are:

- `../nx/swift-corelibs-libdispatch/src/internal.h`
- `../nx/swift-corelibs-libdispatch/src/queue.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_concur.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_overcommit.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_apply.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_group.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_timer.c`
- `../nx/swift-corelibs-libdispatch/tests/dispatch_io.c`

This tree is useful because it is already structured for non-Darwin bring-up
and offers an easier early validation loop than trying to jump directly into a
fully Apple-flavored environment on day one.

## Core Design Decision

Use `NextBSD` as the kernel logic donor, but do **not** preserve its original
userland contract as the end state.

That distinction is the most important design choice in the whole effort.

### Why

`NextBSD` exposes an older interface where userland submits individual work
items into the kernel through commands like `WQOPS_QUEUE_ADD` and
`WQOPS_QUEUE_REMOVE`.

Modern Apple `libdispatch` does not work that way. It does not hand its queued
jobs to the kernel. Instead, it:

1. registers worker callbacks;
2. asks the kernel for more worker threads when it needs concurrency;
3. lets a worker return to the kernel when it should park;
4. asks whether a worker should narrow its draining behavior.

So the right plan is:

1. Keep the `NextBSD` kernel scheduling and worker lifecycle ideas.
2. Replace or extend the old syscall contract so the userland bridge can
   present the modern Apple-style behavior expected by `libdispatch`.
3. Treat the old `NextBSD` public `pthread_workqueue.h` API as legacy donor
   material, not as the final FreeBSD userland contract.

## Recommended Architecture

### Layer 1: FreeBSD kernel workqueue core

Responsibilities:

1. Maintain per-process workqueue state.
2. Create, park, wake, and retire worker threads.
3. Track active, scheduled, and idle worker counts.
4. React to blocking and yielding to decide when more concurrency is needed.
5. Answer "should narrow" queries from userland.

### Layer 2: FreeBSD `libthr` / `libpthread` bridge

Responsibilities:

1. Export the modern workqueue SPI needed by Apple `libdispatch`.
2. Translate `pthread_priority_t` and feature bits into a FreeBSD private
   internal representation.
3. Register the worker callback.
4. Issue request-thread, thread-return, and should-narrow operations to the
   kernel.
5. Keep unsupported Apple-only features stubbed or unadvertised.

### Layer 3: Official Apple `libdispatch`

Responsibilities:

1. Use `_pthread_workqueue_init` or the modern setup path to register worker
   entrypoints.
2. Use `_pthread_workqueue_addthreads()` for demand signaling.
3. Use `_pthread_workqueue_should_narrow()` for backpressure.

### Layer 4: Swift concurrency

Responsibilities:

1. Ride on top of the real workqueue-backed dispatch behavior.
2. Benefit from more macOS-like thread pressure behavior without importing the
   rest of the Darwin kernel model.

## Explicit Non-Goals for Phase 1

Do not implement these in the first useful port:

1. Mach IPC.
2. launchd integration.
3. XNU `bsdthread` ABI compatibility as a goal in itself.
4. direct kevent workqueue delivery.
5. workloops.
6. event manager priority paths.
7. the full XNU QoS override stack.
8. any system-wide macOS compatibility layer unrelated to worker creation and
   feedback.

## Suggested Directory Layout Outside This Repo

To keep this directory clean, use a layout like this in the parent area:

```text
/usr/src                       target FreeBSD 15 source tree
/usr/ports                     local ports tree
../build/obj/freebsd15-wq/     objdir for world/kernel builds
../build/stage/freebsd15-wq/   DESTDIR or image staging root
../vm/base/                    clean VM images
../vm/runs/                    per-branch VM clones
../artifacts/kdump/            crash dumps and kernel.debug copies
../artifacts/logs/             serial logs, test logs, benchmark logs
```

Reasons:

1. source stays separate from generated files;
2. VM artifacts do not pollute the strategy repo;
3. crash dumps and logs remain durable enough for regression review;
4. it becomes easy to destroy and recreate objdirs without touching the plan
   repo.

## Phase 0: Preconditions

### 0.1 Lock the actual FreeBSD 15 target tree

The target tree is `/usr/src`.

Current local indicators:

1. `/usr/src/sys/conf/newvers.sh` shows `REVISION="15.0"` and `BRANCH="STABLE"`.
2. `/usr/src/UPDATING` is maintained for `stable/15`.

Reason:

This removes the biggest planning ambiguity. The port should now be audited and
implemented directly against `/usr/src`, not against a hypothetical future
checkout.

### 0.2 Record the exact `/usr/src` revision used for each milestone

Before each real implementation phase, capture the exact branch and commit
state of `/usr/src`.

Reason:

`stable/15` is not static. If the branch moves underneath the port while the
hook audit is in progress, it becomes difficult to explain regressions and
review deltas cleanly.

### 0.3 Pick a first target architecture

Start with `amd64` only.

Reason:

1. it is the simplest path for bhyve;
2. Apple `libdispatch` and Swift validation will already be meaningful there;
3. cross-architecture bring-up would dilute the porting effort too early.

### 0.4 Create a bring-up kernel option gate

Carry the feature behind a dedicated kernel option such as `THRWORKQ` during
bring-up.

Reason:

1. it keeps the patch reviewable;
2. it provides an easy fallback build path;
3. it limits risk while the hook set is still being stabilized.

### 0.5 Decide the host build policy

Build on the host, boot in the guest.

Reason:

1. guest-side kernel builds are slower and harder to automate;
2. host-side object reuse makes iteration faster;
3. guest images can be treated as throwaway runtime targets.

Operational note:

Use `doas` when installing into root-owned paths such as `/usr/src`, mounted VM
images, or system staging locations, but keep objdirs, logs, dumps, and test
artifacts out of this strategy repo.

## Phase 1: Donor Extraction and Gap Audit

### 1.1 Build a precise diff inventory from `NextBSD`

Record every file that participates in the donor feature:

1. new subsystem file: `sys/kern/kern_thrworkq.c`
2. new internal header: `sys/sys/thrworkq.h`
3. build wiring: `sys/conf/files`, `sys/conf/options`
4. syscall wiring: `sys/kern/syscalls.master`
5. proc and thread structure changes: `sys/sys/proc.h`
6. process init/teardown hooks: `kern_proc.c`, `kern_mutex.c`, `kern_exec.c`,
   `kern_exit.c`
7. thread creation and stack reuse hooks: `kern_thr.c`
8. scheduler callback hooks: `kern_synch.c`
9. yield feedback hook: `p1003_1b.c`

Reason:

The donor is not just one file. Missing any of the hook points will produce a
kernel that compiles but does not behave correctly.

### 1.2 Compare each donor hook against FreeBSD 15 semantics

For each donor touchpoint, verify:

1. whether the type signatures still match;
2. whether the surrounding locking has changed;
3. whether the lifecycle point still exists under the same name;
4. whether equivalent functionality moved elsewhere in FreeBSD 15.
5. whether `/usr/src` already contains any adjacent scheduler or `libthr`
   changes that make the old donor assumptions invalid.

Reason:

The risky part is not copying `kern_thrworkq.c`. The risky part is assuming the
old hook points still mean the same thing.

### 1.3 Audit what can be reused unchanged and what cannot

Expect three categories:

1. likely reusable with minor edits:
   `kern_thrworkq.c`, `thrworkq.h`, build option wiring.
2. likely requiring mechanical rebase work:
   `proc.h`, `kern_proc.c`, `kern_exec.c`, `kern_exit.c`, `kern_thr.c`,
   `kern_synch.c`, `p1003_1b.c`.
3. likely requiring semantic redesign:
   the userland contract and any priority/QoS handling.

Reason:

This avoids wasting time trying to preserve donor interfaces that are already
known to be obsolete.

## Phase 2: Kernel Bring-Up on FreeBSD 15

### 2.1 Add the subsystem in an isolated way

Import the core implementation and header first:

1. `sys/kern/kern_thrworkq.c`
2. `sys/sys/thrworkq.h`
3. `sys/conf/files`
4. `sys/conf/options`

Reason:

This establishes a compile target and a build-time feature flag before touching
the harder lifecycle hooks.

### 2.2 Rebase the proc and thread structure additions

Carry over the minimum fields needed for workqueue state and worker tracking.
From the donor, this includes workqueue state on `struct proc` and callback or
reuse related fields on `struct thread`.

Reason:

The subsystem is built around per-process ownership and per-thread parking
metadata. Faking this elsewhere would create a worse port than adapting the
real kernel structs.

### 2.3 Rebase lifecycle hooks

Reapply the donor behavior for:

1. process creation initialization;
2. process exit cleanup;
3. `exec` cleanup;
4. thread creation upcall setup;
5. thread stack reuse notification;
6. block/unblock callback notifications;
7. voluntary yield notifications.

Reason:

The value of kernel-backed workqueues is feedback. If the kernel is not told
when workers block, yield, exit, or reuse stacks, the backpressure model is
broken.

### 2.4 Do not preserve the old `NextBSD` syscall contract unchanged

This is a planned redesign point.

`NextBSD` currently uses commands such as:

1. `WQOPS_INIT`
2. `WQOPS_QUEUE_ADD`
3. `WQOPS_QUEUE_REMOVE`
4. `WQOPS_THREAD_RETURN`
5. `WQOPS_THREAD_SETCONC`

That old contract assumes the kernel sees every queued work item.

Modern Apple userland expects something much closer to:

1. worker registration / setup
2. request additional threads
3. worker thread return
4. query should-narrow
5. optional future kevent/workloop extensions

Reason:

If the port keeps the old "queue work item into kernel" model, it will not
cleanly support modern `libdispatch` without an awkward compatibility layer
that becomes its own long-term maintenance problem.

### 2.5 Preferred syscall strategy

Keep a single FreeBSD-private syscall entrypoint, but evolve its command set to
support the modern control flow.

Recommended kernel-private operations:

1. init/setup callback registration
2. request worker threads for a priority bucket
3. thread return / park
4. should narrow query
5. optional future dispatch setup metadata

Reason:

1. this avoids importing XNU syscall names purely for cosmetics;
2. `libthr` can present Apple-compatible SPI to `libdispatch`;
3. the kernel ABI can stay FreeBSD-private and easier to maintain;
4. because this project is willing to change ABI if needed, the kernel
   interface should optimize for clarity and long-term design quality rather
   than strict compatibility with old FreeBSD experiments.

### 2.5.1 Concrete kernel-private op set

The first practical ABI should be explicitly defined, not left implicit.

Recommended initial command set:

1. `TWQ_OP_INIT` for worker callback registration and basic process setup;
2. `TWQ_OP_REQTHREADS` for "I need N workers at this priority";
3. `TWQ_OP_THREAD_RETURN` for worker park / immediate reassignment;
4. `TWQ_OP_SHOULD_NARROW` for the backpressure query;
5. `TWQ_OP_SET_CONCURRENCY` only if a temporary compatibility hint is useful;
6. `TWQ_OP_SETUP_DISPATCH` reserved early for dispatch metadata offsets.

Reason:

This is the smallest coherent control surface that matches modern
`libdispatch` behavior. It replaces the donor's work-item ABI with a
thread-lifecycle ABI.

### 2.5.2 Command argument strategy

Each command should use its own size-validated argument structure rather than a
single overloaded payload union.

Minimum useful command-specific structures:

1. init args:
   worker callback, new-thread callback, exit callback, stack size, guard size;
2. request-thread args:
   requested thread count plus `pthread_priority_t`;
3. should-narrow args:
   `pthread_priority_t` only;
4. dispatch-setup args:
   serial number offset and queue label offset.

Reason:

The command multiplexer is fine, but per-command struct validation prevents ABI
drift from turning into hard-to-debug copyin bugs.

### 2.5.3 Internal bucket and category model

Do not keep `NextBSD`'s 3-priority model internally.

Recommended initial kernel model:

1. six QoS buckets ordered low to high:
   background or maintenance, utility, default, initiated, interactive, and
   an above-interactive or internal high bucket reserved for parity with the
   Apple stack;
2. two thread categories:
   constrained and overcommit.

Reason:

Modern Apple userland reasons about multiple QoS classes, not just three
priority bands. Compressing to three buckets too early makes admission and
narrowing decisions lossy and turns `pthread_priority_t` translation into a
dead end. This also better matches the project's stated preference for macOS
semantic compatibility where that remains natural on FreeBSD.

### 2.5.4 Per-process workqueue state shape

The FreeBSD kernel state should be designed around thread requests, not queued
user work items.

The first concrete state design should include:

1. per-process callback registration and stack sizing;
2. pending request counts indexed by category and QoS bucket;
3. atomic active-worker counters by QoS bucket;
4. atomic last-blocked timestamps by QoS bucket;
5. max parallelism by QoS bucket;
6. running and idle worker lists;
7. stack recycling pool;
8. instrumentation counters for creation, reuse, return, narrow, and timer
   actions.

Reason:

This captures the actual state the kernel must own in the Apple model. The
donor's `struct workitem` arrays are the wrong abstraction for the final port.

### 2.5.5 Scheduler-hook lock discipline

Any hook placed in `mi_switch()` or its FreeBSD 15 equivalent must use
atomics only and must not acquire sleeping locks.

Safe switch-path work:

1. increment or decrement atomic active counters;
2. update atomic last-blocked timestamps;
3. set deferred flags or counters consumed later by the timer or syscall path.

Unsafe switch-path work:

1. taking `p_twqlock`;
2. sleeping or waiting;
3. walking complex lists under non-atomic synchronization.

Reason:

This is a deadlock boundary, not an optimization detail. The scheduler hook is
the most failure-prone integration point in the whole port.

### 2.5.6 Admission and narrowing algorithm

The first real admission policy should follow the XNU constrained-allowance
idea instead of a simple "active threads < ncpu" check.

For constrained threads, the kernel should compare:

1. active threads at the requested QoS and above;
2. plus recently blocked threads at the requested QoS and above;
3. against max parallelism for that QoS bucket.

The "recently blocked" window should start with the XNU-style short stall
window, on the order of `200` microseconds, and be exposed as a tunable.

Reason:

This is what prevents short lock stalls from triggering thread explosions. It
is also the core logic behind a meaningful `should_narrow` answer.

### 2.6 Add instrumentation before tuning

Add counters and sysctls for:

1. total worker threads created;
2. total threads reused;
3. total thread return operations;
4. current active workers by priority bucket;
5. current idle workers by priority bucket;
6. total "need more threads" decisions;
7. total "should narrow" true decisions;
8. queue request counts by priority;
9. failed thread creation or wakeup counts;
10. yield-triggered expansion events.

Reason:

Without visibility, the port will degenerate into panic-chasing and timing
guesswork.

### 2.7 Keep kevent and workloop code out of the kernel in phase 1

Do not implement:

1. `THREAD_KEVENT_RETURN`
2. `THREAD_WORKLOOP_RETURN`
3. workloop IDs
4. bound workloop threads
5. direct event delivery buffers

Reason:

Those features explode the complexity of the port and are not required for the
first useful `libdispatch` plus Swift outcome.

## Phase 3: Userland Bridge in `libthr` / `libpthread`

### 3.1 Treat this as a real porting layer, not a shim

The userland bridge must expose the expected workqueue SPI and own the mapping
between Apple-flavored priorities and FreeBSD private kernel commands.

Reason:

This keeps Apple-specific surface area in userland while the kernel remains a
cleaner FreeBSD-native implementation. It also matches the project's intent to
avoid "compatibility library only" status and move toward a real operating
system feature.

### 3.2 Minimal modern SPI to implement first

Implement these first:

1. `_pthread_workqueue_init()`
2. `_pthread_workqueue_supported()`
3. `_pthread_workqueue_addthreads()`
4. `_pthread_workqueue_should_narrow()`
5. worker thread return path in the worker trampoline

Highly recommended shortly after:

1. `pthread_workqueue_setup()`
2. `pthread_workqueue_addthreads_np()`
3. `pthread_workqueue_setdispatch_np()`
4. `_pthread_workqueue_init_with_kevent()` stub or controlled `ENOTSUP`
5. `_pthread_workqueue_init_with_workloop()` stub or controlled `ENOTSUP`

Reason:

This is the smallest surface area that gets modern `libdispatch` onto the real
worker-thread path without forcing kevent/workloop support early.

### 3.2.1 SPI version floor

The private header version must be chosen carefully.

Minimum safe guidance:

1. if the goal is real QoS workqueue support only, the version must still be
   high enough for `libdispatch` to call a real `_pthread_workqueue_should_narrow()`;
2. `PTHREAD_WORKQUEUE_SPI_VERSION` below `20160427` is not acceptable for this
   project because `libdispatch` compiles in a local stub that always returns
   false;
3. if `pthread_workqueue_setup()` is adopted, prefer matching the newer Darwin
   shape such as `20170201`.

Reason:

The wrong version macro can make the port appear to work while quietly removing
kernel-backed narrowing from the build.

### 3.3 Feature bit policy

Initially advertise only what is truly implemented.

Recommended early feature set:

1. base workqueue support;
2. `WORKQ_FEATURE_MAINTENANCE`, because current `libdispatch` requires it at
   initialization time;
3. possibly `WORKQ_FEATURE_DISPATCHFUNC` if the compatibility path is provided.

Recommended to leave disabled initially:

1. `WORKQ_FEATURE_KEVENT`
2. `WORKQ_FEATURE_WORKLOOP`
3. `WORKQ_FEATURE_FINEPRIO` unless fine-grained kernel QoS mapping really
   exists

Reason:

`libdispatch` already has compile and runtime branching based on these bits.
The maintenance bit is the one exception: current Apple and swift-corelibs
`libdispatch` will crash during root-queue initialization if it is absent.
Everything else should remain off until it is genuinely implemented.

### 3.4 Priority mapping policy

Do not bake `NextBSD`'s current 3-priority model into either the external ABI
or the internal scheduler model.

Recommended staged approach:

1. accept `pthread_priority_t` at the userland boundary immediately;
2. decode the QoS class bits and the overcommit flag in `libthr`, not in
   `libdispatch`;
3. map the request into a 6-bucket kernel model from the start;
4. treat maintenance plus background as the same bucket initially if needed,
   but do not collapse utility/default/initiated/interactive into a 3-band
   model;
5. reserve any above-interactive bucket as internal-only if userland does not
   need to request it directly;
6. only advertise `WORKQ_FEATURE_FINEPRIO` when the kernel behavior has a real
   scheduling effect and is not just label-preserving bookkeeping.

Reason:

This preserves Apple-like semantics where they matter most, while still giving
the implementation room to stage scheduler fidelity over time.

### 3.4.1 Priority extraction requirements

The translation layer should explicitly handle at least:

1. the QoS class field embedded in `pthread_priority_t`;
2. the overcommit flag;
3. undefined or malformed values by mapping them to a safe default bucket.

Reason:

This is the real ABI boundary. If it is vague in the plan, it will become
inconsistent across `libthr`, tests, and kernel admission logic.

### 3.5 Narrowing should be a real kernel query

Implement `_pthread_workqueue_should_narrow()` as a genuine kernel-backed
decision, not a pure userland heuristic.

A direct query command is acceptable for phase 1 because `libdispatch` already
throttles how often it asks.

Reason:

The whole point of this feature is kernel feedback. If narrowing becomes a
userland guess, the port loses the behavior it was meant to provide.

The answer should reuse the same constrained-admission logic as
`REQTHREADS`, not a separate heuristic. That keeps "admit more workers" and
"should this worker park" mathematically consistent.

### 3.6 Dispatch setup metadata can start simple

If `pthread_workqueue_setup()` is implemented, the first version can treat the
dispatch metadata fields as accepted configuration with minimal kernel use.

Reason:

This keeps the ABI shape future-friendly without forcing dispatch queue
introspection into the kernel before it is actually useful.

## Phase 4: `libdispatch` Bring-Up Strategy

### 4.1 First target the worker-thread path, not kevent workqueue delivery

The initial goal is:

1. `_pthread_workqueue_init()` works;
2. `_pthread_workqueue_addthreads()` works;
3. `_pthread_workqueue_should_narrow()` works;
4. `KEVENT_FLAG_WORKQ` is **not** advertised.

Reason:

With that feature profile, Apple `libdispatch` can use real workqueue-backed
worker creation without requiring direct kevent delivery or workloops.

### 4.1.1 Success criteria for early bring-up

The first meaningful success target is semantic quality, not total Darwin
coverage.

For early iterations, "good enough" means:

1. the real workqueue-backed path is active;
2. the semantics are clearly beyond the Linux-style compatibility story;
3. the system behaves well enough to be compelling relative to other
   non-macOS environments;
4. the design leaves a path to move gradually closer to native macOS behavior.

Reason:

This matches the project's stated priority: make the system second only to
native macOS for `libdispatch` support, without pretending phase 1 must
instantly equal Apple's performance envelope.

### 4.2 Use Apple `libdispatch` as the end target, but not as the only test bed

Recommended order:

1. prove the bridge with focused unit and syscall tests;
2. prove concurrency behavior with `swift-corelibs-libdispatch`;
3. then validate against `apple-opensource-libdispatch`.

Reason:

This de-risks the port. It is easier to debug kernel feedback problems in the
more portable tree first, then confirm that the official Apple tree follows the
same intended path.

Because the choice between the two trees is not itself a project goal, use
whichever path is most productive at a given stage. `swift-corelibs-libdispatch`
is acceptable for bring-up as long as the implementation continues converging
toward the official Apple semantics.

### 4.3 Do not allow fallback to hide failures

When testing the real path, make sure `libdispatch` is actually taking the
workqueue-backed route and not silently falling back to a generic pthread pool.

Concrete checks should include:

1. runtime tracing of `thr_workq` or the final workqueue syscall path with
   `truss`, `ktrace`, `kdump`, `dtrace`, or an equivalent mechanism;
2. kernel stats showing non-zero thread requests, thread creations, and narrow
   decisions after running dispatch workloads;
3. build and symbol inspection sufficient to confirm that the workqueue-backed
   initialization path is present and the generic fallback path is not the only
   route being exercised.

Reason:

A silent fallback would produce passing smoke tests while proving nothing about
the actual feature being developed.

## Phase 5: `bhyve` Development Methodology

### 5.1 Use a clean base image plus disposable clones

Workflow:

1. build a clean guest image once;
2. keep it immutable as the baseline;
3. clone it per branch or milestone;
4. throw away broken clones freely.

Reason:

Kernel workqueue bugs are exactly the kind of bugs that can leave a guest image
in a confused state after repeated crash cycles.

### 5.2 Build artifacts should stay outside the plan repo

Use objdirs, install roots, VM disks, logs, and dumps in sibling directories.

Reason:

This keeps the repo reviewable and avoids accidental commits of giant binaries.

### 5.3 Run a debug kernel configuration first

Recommended early kernel settings:

1. `DEBUG=-g`
2. `DDB`
3. `INVARIANTS`
4. `INVARIANT_SUPPORT`
5. `WITNESS` for the earliest locking bring-up

Reason:

Thread lifecycle and lock ordering bugs should fail loudly and early.

### 5.4 Use serial-first boot and logging

Capture:

1. boot logs;
2. panic traces;
3. `DDB` output;
4. test harness logs;
5. kernel debug symbols matching each VM image.

Reason:

If the guest wedges in the workqueue path, serial logging is often the only
useful post-mortem evidence.

### 5.5 Prefer host-side image updates over guest-side rebuilds

Recommended iteration loop:

1. build kernel on host;
2. install into a staged guest root or mounted VM image;
3. boot or reboot the guest;
4. run tests;
5. collect logs and dumps.

Reason:

This keeps turnaround tight and makes it easier to reproduce a known kernel
image from host-side artifacts.

### 5.6 Keep one slow path and one fast path

Slow path:

1. full clean image rebuild for milestone checkpoints.

Fast path:

1. kernel-only replacement into an existing disposable guest for rapid testing.

Reason:

The slow path preserves a known-good reset point. The fast path preserves
developer velocity.

### 5.7 Keep the VM workflow scripted

Before implementation begins in earnest, define a small helper-script set for:

1. building or refreshing a clean base image;
2. cloning a run image for a specific milestone or branch;
3. updating just the kernel into an existing run image;
4. launching the guest with serial logging;
5. collecting crash dumps and matching `kernel.debug` artifacts after failure.

Reason:

The workflow is part of the engineering strategy. If it remains manual, the
cost of kernel iteration and crash recovery will dominate the project.

### 5.8 Add a canonical macOS reference lane

After this directory is initialized as the project Git repository and mirrored
to an upstream remote, clone the same repo onto the Apple M5-based macOS 26.4
system and treat that machine as the canonical behavior reference for
`libdispatch`.

Use that macOS host for:

1. running the same userland and workload tests against Apple's native
   implementation;
2. capturing baseline behavior for thread growth, narrowing, blocking, and
   queue-drain patterns;
3. checking whether a proposed FreeBSD-visible behavior is comparable to the
   natural Darwin behavior before spending time on compatibility work;
4. regression comparison when FreeBSD behavior changes during tuning.

Do not use that host as a requirement for bit-for-bit compatibility.

Reason:

The Apple machine is the best oracle for "what good looks like" for
`libdispatch` behavior, but the port should still be judged by whether the
feature is technically sound and natural on FreeBSD, not by whether every
Darwin quirk is reproduced.

## Phase 6: Test Plan

Detailed framework and tooling choices for testing live in
`pthread-workqueue-testing-strategy.md`.

### 6.1 Level 0: compile and boot integrity

Must prove:

1. kernel builds with `THRWORKQ` disabled;
2. kernel builds with `THRWORKQ` enabled;
3. guest boots cleanly in both cases;
4. exit, exec, and thread creation do not regress before `libdispatch` is even
   involved.

Reason:

This catches structural integration mistakes before concurrency semantics enter
the picture.

### 6.2 Level 1: kernel syscall smoke tests

Write focused tests for:

1. worker registration and duplicate-init rejection;
2. add-thread requests for constrained workers;
3. add-thread requests for overcommit workers;
4. worker return and immediate reassignment;
5. should-narrow query under low load;
6. should-narrow query under saturated load;
7. process exit cleanup;
8. `exec` cleanup;
9. repeated thread reuse;
10. admission behavior when all workers block briefly versus for a long time.

Reason:

These isolate kernel and `libthr` behavior from dispatch complexity.

### 6.3 Level 2: `libpthread` / workqueue API tests

Reuse or adapt the local `ravynOS` tests:

1. `wq_limits.c`
2. `wq_block_handoff.c`

Only later, if those features are implemented:

1. `wq_kevent.c`
2. `wq_kevent_stress.c`
3. `wq_event_manager.c`

Reason:

The early tests should match the implemented feature set, not the full Darwin
feature envelope.

### 6.4 Level 3: `libdispatch` regression tests

Run at least these:

1. `dispatch_concur.c`
2. `dispatch_overcommit.c`
3. `dispatch_apply.c`
4. `dispatch_group.c`
5. `dispatch_timer.c`
6. `dispatch_io.c`

Reason:

This is where real queue draining and backpressure behavior starts to get
exercised under representative workloads.

### 6.5 Level 4: custom narrowing and blocking tests

Add two purpose-built tests before Swift validation:

1. a narrowing test that starts significantly more runnable work than `ncpu`
   and verifies bounded thread growth plus non-zero narrow decisions;
2. a blocking test that parks one wave of workers on sleep or I/O, then starts
   a second wave of runnable work and verifies controlled expansion followed by
   contraction.

Reason:

The stock dispatch test suite exercises concurrency, but these tests prove the
exact kernel feedback behavior this project is intended to add.

### 6.6 Level 5: Swift concurrency stress tests

Once dispatch is stable, add Swift-side tests that stress:

1. task groups;
2. detached tasks;
3. priority changes;
4. blocking workloads mixed with compute workloads;
5. large fan-out and fan-in patterns.

Reason:

The user-facing purpose of the whole project is to make Swift concurrency
behave more like it does on macOS.

### 6.7 Level 6: soak and failure testing

Run:

1. long-lived mixed workloads;
2. repeated process start/exit loops;
3. forced signal and cancellation scenarios;
4. repeated VM reboot cycles;
5. crash-and-recover drills to confirm dump collection still works.

Reason:

Workqueue bugs often show up only after long churn, not in short happy-path
tests.

### 6.8 Canonical macOS comparison testing

Maintain a parallel test lane on the Apple M5 macOS 26.4 clone of this repo.

Use it to run:

1. the same dispatch microbenchmarks and stress programs used on FreeBSD where
   that makes sense;
2. custom narrowing and blocking tests with comparable task structure;
3. Swift concurrency stress programs that are expected to behave similarly on
   both systems.

Capture and compare:

1. worker-thread growth curves;
2. steady-state thread counts under CPU-bound work;
3. expansion under blocked-worker scenarios;
4. narrowing and recovery after pressure drops;
5. any user-visible semantic differences that matter to Swift or dispatch APIs.

Interpretation policy:

1. macOS is the reference behavior for canonical `libdispatch`;
2. FreeBSD does not need to match every implementation detail;
3. when behavior differs, first decide whether the difference is acceptable and
   natural on FreeBSD before treating it as a bug;
4. if the feature is cheap and natural to align, bias toward comparability with
   the macOS result.

Reason:

This creates a practical regression oracle without turning the project into a
full Darwin compatibility effort.

## Phase 7: Performance and Semantics Hardening

### 7.1 Validate worker creation pressure

Measure:

1. thread creation bursts;
2. idle worker retention;
3. wakeup latency;
4. return-to-kernel frequency;
5. oversubscription under blocking loads.

Reason:

A port that "works" but continuously overspawns threads misses the point of the
feature.

Performance priority guidance:

1. first iteration: semantics and stability first;
2. second iteration onward: remove obvious inefficiencies and beat the Linux
   compatibility story clearly;
3. later iterations: move as close to macOS behavior and performance as is
   natural on FreeBSD.

### 7.2 Revisit bucket fidelity only after correctness

If testing shows starvation or priority inversion, improve scheduler fidelity
and per-CPU refinement after the 6-bucket admission model is already stable.

Reason:

It is better to first establish correct feedback flow than to overfit the
low-level scheduler mapping while lifecycle bugs remain.

### 7.3 Decide whether direct kevent support is worth a separate project

Treat direct kevent delivery and workloops as a later, separate decision.

Reason:

They are not required for the first meaningful improvement to Swift and
dispatch behavior, and they would dominate the engineering effort if pulled in
too early.

## Specific Risks to Call Out Early

### 1. `stable/15` drift during implementation

The target tree is now known, but it is a moving branch.

### 2. `NextBSD`'s priority handling is incomplete

The donor kernel still contains a real `XXX Set thread priority` gap, so it is
not safe to assume its current priority behavior is the final answer.

### 3. FreeBSD 15 hook drift may be non-trivial

The thread creation, stack reuse, yield, and context switch callback sites may
have moved or changed semantics.

### 4. Userland ABI drift is guaranteed

The donor `pthread_workqueue` API shape is older than what current Apple
`libdispatch` expects.

### 5. Silent fallback is a real danger

Tests must confirm the actual workqueue path is active, not a generic pthread
fallback.

### 6. Scheduler-hook deadlocks are easy to introduce

If the switch-path callback takes sleeping locks or walks complex structures,
the port will fail in a way that is difficult to debug and easy to misattribute.

### 7. A bad SPI version can disable real narrowing at compile time

If the private header advertises too old a `PTHREAD_WORKQUEUE_SPI_VERSION`,
`libdispatch` will compile in a local `_pthread_workqueue_should_narrow()`
stub that always returns false.

## Milestone Plan

### Milestone A: Host and VM pipeline ready

Exit criteria:

1. `/usr/src` revision recorded;
2. base bhyve guest boots;
3. serial logging works;
4. crash-dump collection is verified.

### Milestone B: Rebase audit and ABI plan locked

Exit criteria:

1. every donor hook is mapped to `/usr/src`;
2. the FreeBSD-private `TWQ_OP_*` command set is finalized;
3. per-process and per-thread state layout is agreed;
4. feature-bit and SPI-version policy is frozen for phase 1.

### Milestone C: Kernel compiles and boots with feature gated

Exit criteria:

1. `THRWORKQ` option builds;
2. guest boots with and without the option;
3. no regressions in basic process and thread lifecycle paths;
4. basic instrumentation sysctls are visible.

### Milestone D: Core kernel workqueue operations function

Exit criteria:

1. init, request-threads, return, and should-narrow all work;
2. scheduler feedback is active and does not deadlock;
3. constrained versus overcommit behavior is distinguishable;
4. kernel smoke tests pass in the guest.

### Milestone E: `libthr` SPI is usable by dispatch

Exit criteria:

1. `_pthread_workqueue_init()` works;
2. `_pthread_workqueue_addthreads()` works;
3. worker return works;
4. `_pthread_workqueue_should_narrow()` reaches the kernel;
5. `WORKQ_FEATURE_MAINTENANCE` and the chosen SPI version are correct.

### Milestone F: `swift-corelibs-libdispatch` uses the real worker-thread path

Exit criteria:

1. no silent fallback;
2. `dispatch_apply`, `dispatch_group`, `dispatch_timer` pass;
3. `dispatch_concur` and `dispatch_overcommit` pass;
4. custom narrowing and blocking tests show kernel feedback working;
5. equivalent tests are defined well enough to run on the macOS reference host.

### Milestone G: Apple `libdispatch` uses the same path

Exit criteria:

1. the official Apple tree builds against the ported SPI surface;
2. it initializes without maintenance-feature crashes;
3. it exercises the same worker-thread path without silent fallback;
4. the same userland workload set is runnable on the macOS reference host for
   behavioral comparison.

### Milestone H: Swift concurrency and soak validation pass

Exit criteria:

1. representative Swift workloads run correctly;
2. blocking-heavy workloads do not explode thread counts;
3. long-running soak tests stay stable;
4. priority handling has a real scheduling effect, not just labels;
5. key workload behavior is documented as either comparable to macOS or
   intentionally divergent for FreeBSD-specific reasons.

## What Not To Do

1. Do not start from XNU's `pthread_workqueue.c` as the base implementation.
2. Do not import Mach and workloop infrastructure just to get a familiar file
   layout.
3. Do not freeze the old `NextBSD` queue-item API as the public contract.
4. Do not claim fine-grained QoS support until the kernel genuinely provides
   it.
5. Do not test only by rebooting the host into experimental kernels.
6. Do not allow fallback code paths to masquerade as a successful port.
7. Do not force a macOS feature into FreeBSD if it clearly competes with or
   distorts the native kernel model for little real benefit.

## Recommended Immediate Next Steps

1. Record the exact `/usr/src` revision that will anchor the first implementation pass.
2. Produce a file-by-file donor-to-`/usr/src` mapping with hook-by-hook notes.
3. Freeze the initial `TWQ_OP_*` ABI and command argument structures.
4. Sketch the actual `thrworkq` and per-thread state layout around requests,
   counters, lists, and timestamps.
5. Define the `libthr` private header with the correct SPI version and
   mandatory feature bits.
6. Initialize this directory as the project Git repository when you are ready
   to start implementation history.
7. Stand up the scripted host-build plus `bhyve` guest loop before touching kernel code.
8. After the upstream remote exists, clone the repo onto the Apple M5 macOS
   26.4 machine and wire the reference-test lane into the workflow.

## Bottom Line

The best path is not "port XNU workqueue to FreeBSD". The best path is:

1. transplant `NextBSD`'s FreeBSD-native worker lifecycle and feedback logic;
2. redesign the userland contract so it matches what modern Apple
   `libdispatch` actually expects;
3. keep kevent/workloop support out of scope until the worker-thread path is
   solid;
4. develop and validate the kernel side in disposable `bhyve` guests with
   strong instrumentation;
5. continuously compare userland-visible behavior against the Apple Silicon
   macOS reference host so the FreeBSD port stays meaningfully aligned with the
   canonical implementation where that alignment is natural.

That gives the smallest plausible implementation that still delivers the thing
you actually care about: real kernel-backed concurrency feedback for dispatch
and Swift on a current FreeBSD base.
