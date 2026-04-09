# FreeBSD 15 Donor Hook Map

## Purpose

This document closes milestone `M01`.

It turns the donor story into an implementation map against the real target
tree at `/usr/src`. The goal is not to restate the architecture plan. The goal
is to answer these concrete questions:

1. which donor files are actually useful;
2. where the matching hook points live in current FreeBSD 15 `stable/15`;
3. which parts can be ported mechanically;
4. which parts must be redesigned;
5. which old donor behaviors should be dropped on purpose.

The result is meant to be implementation-facing. If this document is followed,
the next phase should be actual kernel edits, not more architecture discovery.

## Local Source Roles

These are the local trees used for the audit:

- `/usr/src`
  - real target tree for the FreeBSD 15 based operating system;
  - local snapshot, not a Git checkout.
- `../nx/NextBSD-NextBSD-CURRENT`
  - primary kernel donor because it already solved the FreeBSD-side shape of a
    workqueue subsystem once;
  - still old and still carrying obsolete queue-item assumptions.
- `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread`
  - best userland SPI reference for the modern `_pthread_workqueue_*` surface.
- `../nx/apple-opensource-xnu/bsd/pthread`
  - canonical kernel semantics reference for QoS buckets, `workq_kernreturn`
    shape, admission, and `should_narrow`.
- `../nx/apple-opensource-libdispatch`
  - canonical dispatch consumer behavior reference.
- `../nx/swift-corelibs-libdispatch`
  - FreeBSD-relevant dispatch consumer and early bring-up target.

## Audit Summary

The donor is still the right starting point, but only for the kernel core.

The useful pieces are:

1. `NextBSD`'s kernel worker lifecycle model;
2. its FreeBSD-native thread creation and user-stack provisioning approach;
3. its workqueue timer and idle or blocked worker accounting shape;
4. its process `exec` and exit cleanup intent.

The pieces that should not survive into the target design are:

1. the old queue-item syscall ABI;
2. the old public `pthread_workqueue_np` item queue model;
3. the 3-priority internal model;
4. the `p_twqlock` and `td_reuse_stack` donor fields;
5. the donor's direct edits to `kern_proc.c`, `kern_mutex.c`, and
   `p1003_1b.c`.

The kernel port is therefore viable, but it is not a straight cherry-pick.

## Important Conclusions

### 1. `NextBSD` is the structural donor, not the ABI donor

`NextBSD` exports `WQOPS_INIT`, `WQOPS_QUEUE_ADD`, `WQOPS_QUEUE_REMOVE`,
`WQOPS_THREAD_RETURN`, and `WQOPS_THREAD_SETCONC` in
`sys/sys/thrworkq.h`. That is useful only as bootstrap history.

The target system should not keep the queue-item API because real modern
`libdispatch` expects:

1. worker setup;
2. thread requests by priority;
3. worker return to kernel;
4. `should_narrow`;
5. feature discovery.

That is much closer to Darwin's `workq_kernreturn` shape than to the donor's
item queue API.

### 2. The real FreeBSD 15 hook points still exist

The important lifecycle entry points are all still present in `/usr/src`:

- `process_init` eventhandler in `sys/kern/kern_proc.c`;
- `thread_init` and `thread_dtor` eventhandlers in `sys/kern/kern_thread.c`;
- `pre_execve()` in `sys/kern/kern_exec.c`;
- `exit1()` in `sys/kern/kern_exit.c`;
- `mi_switch()` in `sys/kern/kern_synch.c`;
- syscall generation from `sys/kern/syscalls.master` with
  `make -C /usr/src/sys/kern sysent`.

This is good news because it means the port can lean on current FreeBSD
extension points instead of copying old donor glue mechanically.

### 3. The biggest unavoidable rebase is the scheduler callback path

`NextBSD` added:

1. `mi_switchcb_t`;
2. `td_cswitchcb`;
3. `td_threadlist`;
4. pre-block and post-unblock callbacks inside `mi_switch()`.

Current `stable/15` does not have this callback path. That is the main kernel
surface that must be reintroduced deliberately.

However, the donor changed `mi_switch()` more than is necessary. The current
tree can keep its existing signature and just add a minimal callback branch
around `sched_switch(td, flags)`.

### 4. `stable/15` has a cleaner extension path than the donor used

Current FreeBSD already invokes:

1. `EVENTHANDLER_DIRECT_INVOKE(process_init, p)` for ordinary processes;
2. `EVENTHANDLER_DIRECT_INVOKE(process_init, p)` for `proc0` in
   `init_main.c`;
3. `EVENTHANDLER_DIRECT_INVOKE(thread_init, td)` for ordinary threads;
4. `EVENTHANDLER_DIRECT_INVOKE(thread_init, td)` for `thread0` in
   `init_main.c`.

This means the port does not need direct donor-style init patches in
`kern_proc.c` or `kern_mutex.c` just to initialize workqueue fields.

### 5. The first real kernel implementation does not need `sched_yield()` hooks

`NextBSD` patched `sys_sched_yield()` in `p1003_1b.c`.

That made sense for its older heuristic path, but it is not part of the modern
Darwin contract that matters for `libdispatch`. The first real port should
derive its behavior from:

1. thread requests;
2. return-to-kernel;
3. blocked-thread accounting;
4. `should_narrow`.

So the `sched_yield()` hook is explicitly dropped in phase 1.

### 6. The first real kernel implementation does not need `td_reuse_stack`

`NextBSD` added `td_reuse_stack` and patched `sys_thr_exit()` to recycle a
user stack back into the workqueue pool.

That is not the right shape for the modern design.

In the target design, a workqueue worker should normally return to kernel by
`TWQ_OP_THREAD_RETURN`, not by exiting through `thr_exit()`. If the kernel
chooses to permanently retire a worker, it already owns the worker metadata and
the user stack address, so stack cleanup or reuse can happen inside
`kern_thrworkq.c` without reviving a special `td_reuse_stack` field.

The recommended first cut therefore does not patch `kern_thr.c`.

### 7. Six internal QoS buckets should be used from day one

`NextBSD` uses `WORKQ_OS_NUMPRIOS == 3`.

That is not enough for modern dispatch behavior. The target should carry six
internal buckets aligned with Darwin semantics:

1. maintenance;
2. background;
3. utility;
4. default or legacy;
5. user initiated;
6. user interactive.

This does not require Mach scheduling semantics. It only means the kernel state
and admission model must not collapse these buckets into three from the start.

### 8. Local syscall slot 468 is acceptable for the forked OS

Current `/usr/src/sys/kern/syscalls.master` reserves `467-470` for local use,
and generated tables mark `468` as reserved local use.

For a forked FreeBSD-based operating system, using slot `468` for the initial
`twq_kernreturn` syscall is acceptable and minimizes early churn.

This is not an upstreaming promise. It is a practical local choice.

## Donor Inventory

| Source | Role | Keep | Rewrite | Drop |
| --- | --- | --- | --- | --- |
| `../nx/NextBSD-NextBSD-CURRENT/sys/kern/kern_thrworkq.c` | Primary kernel donor | worker lifecycle, stack provisioning pattern, timer logic, idle or blocked accounting intent | syscall decoder, state layout, QoS model, scheduler hook path, stack teardown path | old queue-item contract |
| `../nx/NextBSD-NextBSD-CURRENT/sys/sys/thrworkq.h` | Historical kernel header | names and rough command history only | new kernel-private ABI and structs | public queue-item ABI |
| `../nx/NextBSD-NextBSD-CURRENT/lib/libthr/thread/thr_workq.c` | Historical userland bridge | bootstrap shape for worker callbacks and stack sizing | modern `_pthread_workqueue_*` bridge | item queue logic |
| `../nx/ravynos-darwin/Libraries/Libsystem/libsystem_pthread/private/workqueue_private.h` | Modern userland SPI target | yes | only where FreeBSD naming needs isolation | nothing in phase 1 |
| `../nx/apple-opensource-xnu/bsd/pthread/workqueue_syscalls.h` | Canonical syscall shape reference | opcode philosophy and 4-arg multiplexer shape | FreeBSD-private names and packing | kevent or workloop ops in phase 1 |
| `../nx/apple-opensource-xnu/bsd/pthread/pthread_workqueue.c` | Canonical semantics reference | constrained allowance, busy-thread window, `should_narrow` shape | ULE mapping and non-Mach implementation | Mach, workloops, direct kevent delivery, override machinery |

## Target File Map Against `/usr/src`

This is the actual first kernel edit set.

| Target | Action | Donor | Classification | Recommendation |
| --- | --- | --- | --- | --- |
| `sys/conf/files` | add `kern/kern_thrworkq.c` | `NextBSD sys/conf/files` | mechanical | safe direct edit |
| `sys/conf/options` | add `THRWORKQ opt_thrworkq.h` | `NextBSD sys/conf/options` | mechanical | safe direct edit |
| `sys/sys/proc.h` | add forward declaration and one proc pointer, plus minimal thread scheduler callback fields | donor `proc.h` | redesign | do not port `p_twqlock`, `td_threadlist`, or `td_reuse_stack` literally |
| `sys/kern/kern_synch.c` | add pre-block and post-switch callback branch in `mi_switch()` | donor `kern_synch.c` | redesign | keep current `mi_switch(int flags)` signature |
| `sys/kern/kern_exec.c` | call `twq_proc_exec(p)` in `pre_execve()` after thread-single succeeds | donor `kern_exec.c` | mechanical | safe small edit |
| `sys/kern/kern_exit.c` | call `twq_proc_exit(p)` in `exit1()` before later teardown | donor `kern_exit.c` | mechanical | safe small edit |
| `sys/kern/syscalls.master` | add local syscall entry for `twq_kernreturn` | donor `syscalls.master` and XNU shape | redesign | use local slot `468` |
| `sys/kern/Makefile` generated files | regenerate `init_sysent.c`, `syscalls.c`, `systrace_args.c`, `sysproto.h`, `syscall.mk` | n/a | generated | run `make -C /usr/src/sys/kern sysent` |
| `sys/kern/kern_thrworkq.c` | new implementation file | donor `kern_thrworkq.c` | redesign-heavy import | main implementation file |
| `sys/sys/thrworkq.h` or renamed equivalent | new kernel-private header | donor `thrworkq.h` plus XNU references | redesign | keep private until userland bridge solidifies |
| `sys/kern/kern_proc.c` | no direct edit required for init path | donor patched this | dropped | use `process_init` eventhandler instead |
| `sys/kern/kern_mutex.c` | no direct edit required | donor patched this | dropped | `proc0` gets `process_init` already |
| `sys/kern/kern_thr.c` | no phase-1 edit | donor patched this | dropped for phase 1 | handle worker teardown inside `kern_thrworkq.c` |
| `sys/kern/p1003_1b.c` | no phase-1 edit | donor patched this | dropped for phase 1 | no `sched_yield()` hook in first real design |

## Recommended Kernel Shapes

These are not final header files yet. They are the recommended shapes for the
first implementation pass.

### 1. Per-process state

Do not embed the workqueue lock directly in `struct proc`.

Instead:

1. add only `struct twq_proc *p_twq;` to `struct proc`;
2. allocate the real state lazily from `TWQ_OP_INIT`;
3. embed the workqueue lock inside `struct twq_proc`.

Recommended sketch:

```c
struct twq_proc {
	struct mtx		tqp_lock;
	struct proc		*tqp_proc;
	struct thread		*tqp_owner;
	uint32_t		tqp_flags;
	uint32_t		tqp_features;
	uint32_t		tqp_spi_version;
	void			*tqp_dispatch_func;
	size_t			tqp_stack_size;
	size_t			tqp_guard_size;
	uint16_t		tqp_req_count[6];
	uint16_t		tqp_active_count[6];
	uint16_t		tqp_scheduled_count[6];
	_Atomic uint64_t	tqp_last_blocked[6];
	uint16_t		tqp_total_threads;
	uint16_t		tqp_idle_threads;
	TAILQ_HEAD(, twq_thread) tqp_running;
	TAILQ_HEAD(, twq_thread) tqp_idle;
};
```

This keeps the lifetime and locking model explicit and avoids reviving the
donor's `p_twqlock`.

### 2. Per-thread state

Do not port the donor's `td_threadlist` and `td_reuse_stack` fields literally.

Use:

1. a minimal generic callback hook in `struct thread`;
2. a `struct twq_thread` object owned by `kern_thrworkq.c`;
3. thread OSD only for optional non-hot-path metadata if needed later.

Recommended sketch:

```c
typedef void (*td_sched_cb_t)(int event, struct thread *td, void *arg);

struct twq_thread {
	struct thread		*tqt_td;
	struct twq_proc		*tqt_proc;
	stack_t			 tqt_stack;
	uint8_t			 tqt_bucket;
	uint8_t			 tqt_flags;
	TAILQ_ENTRY(twq_thread) tqt_entry;
};
```

Recommended `struct thread` additions:

```c
td_sched_cb_t	td_sched_cb;
void		*td_sched_cb_arg;
```

This is the smallest stable/15-friendly way to support lock-free switch-path
accounting.

### 3. Syscall ABI

Use a Darwin-shaped multiplexer, but keep the names FreeBSD-private.

Recommended syscall:

```c
int twq_kernreturn(int op, void *arg2, int arg3, int arg4);
```

Recommended first opcode subset:

1. `TWQ_OP_INIT`
2. `TWQ_OP_REQTHREADS`
3. `TWQ_OP_THREAD_RETURN`
4. `TWQ_OP_SHOULD_NARROW`
5. `TWQ_OP_SETUP_DISPATCH`

Notes:

1. `TWQ_OP_INIT` is the practical bridge between old donor setup and modern
   dispatch setup;
2. `TWQ_OP_SETUP_DISPATCH` can alias or replace `TWQ_OP_INIT` once the userland
   bridge settles;
3. kevent and workloop return opcodes should stay reserved, not implemented, in
   phase 1.

### 4. QoS model

Use six internal request and worker buckets from day one:

1. maintenance;
2. background;
3. utility;
4. default or legacy;
5. user initiated;
6. user interactive.

Keep the mapping separate from ULE details. The kernel state should preserve
the six buckets even if the first scheduling translation is only approximate.

### 5. ULE-facing translation

Do not emulate Mach thread policy.

Use existing FreeBSD scheduler interfaces from `sys/sched.h`:

1. `sched_class()`
2. `sched_user_prio()`
3. `sched_prio()`
4. `sched_lend_prio()` only if strictly necessary later

The first pass should keep workqueue workers in the natural ULE model and map
QoS buckets into sane timeshare priorities rather than attempting a foreign
policy system.

## Exact Hook Decisions

### `sys/sys/proc.h`

Recommended:

1. add `struct twq_proc *p_twq;` near the tail of `struct proc`, after the
   copied and zeroed fork layout areas;
2. add a generic scheduler callback type and two thread fields;
3. do not add donor-only fields:
   - `p_twqlock`
   - `td_threadlist`
   - `td_reuse_stack`

Reason:

The current tree already has eventhandlers for init and teardown. It does not
need embedded donor state just to bootstrap.

### `sys/kern/kern_proc.c`

Recommended:

1. no direct initialization edit;
2. register a `process_init` handler from `kern_thrworkq.c` to set `p->p_twq`
   to `NULL`;
3. register a matching `process_fini` or rely on `twq_proc_exit()` lifetime
   rules where appropriate.

Reason:

Current FreeBSD already exposes a process init hook. Use it.

### `sys/kern/init_main.c`

Recommended:

1. no direct edit;
2. rely on the existing `process_init` and `thread_init` eventhandler
   invocations for `proc0` and `thread0`.

Reason:

This removes the donor need for `kern_mutex.c` proc0 special initialization.

### `sys/kern/kern_thread.c`

Recommended:

1. no direct edit for phase 1;
2. register `thread_init` and `thread_dtor` handlers from `kern_thrworkq.c` if
   per-thread callback fields or metadata need explicit nulling or cleanup;
3. use `osd_thread_register()` only for non-hot-path side data, not for the
   switch-path callback lookup.

Reason:

The existing thread eventhandler model is cleaner than reviving donor-specific
teardown edits.

### `sys/kern/kern_synch.c`

Recommended:

1. keep current `mi_switch(int flags)`;
2. add a branch before `sched_switch(td, flags)`:
   - if `td->td_sched_cb != NULL`, invoke `td->td_sched_cb(TWQ_SWCB_BLOCK, td,
     td->td_sched_cb_arg)`;
3. add a branch after `sched_switch(td, flags)` returns:
   - if the resumed thread has a callback, invoke
     `td->td_sched_cb(TWQ_SWCB_UNBLOCK, td, td->td_sched_cb_arg)`.

Reason:

This is the minimum kernel scheduler delta that preserves the donor's lock-free
blocked or active accounting concept without dragging in the old `mi_switch()`
signature change.

### `sys/kern/kern_exec.c`

Recommended:

1. call `twq_proc_exec(p)` from `pre_execve()` after thread-single succeeds and
   before the old vmspace is handed off.

Reason:

This preserves the donor cleanup intent while matching current FreeBSD 15 exec
flow.

### `sys/kern/kern_exit.c`

Recommended:

1. call `twq_proc_exit(p)` in `exit1()` after the `initproc` guard and before
   later cleanup steps.

Reason:

That remains the correct place to tear down the process-wide workqueue state
before the process falls deeper into exit.

### `sys/kern/kern_thr.c`

Recommended:

1. do not port the donor `sys_thr_exit()` hook in phase 1.

Reason:

The real worker lifecycle should be based on `TWQ_OP_THREAD_RETURN`, not on
repurposing `thr_exit()` as the normal worker park path.

### `sys/kern/p1003_1b.c`

Recommended:

1. do not port the donor `sys_sched_yield()` hook in phase 1.

Reason:

It is not required for modern dispatch semantics, and it is easy to add noise
before the core admission logic is even correct.

### `sys/kern/syscalls.master`

Recommended:

1. use local slot `468`;
2. define `twq_kernreturn(int op, void *arg2, int arg3, int arg4)`;
3. regenerate tables with:

```sh
make -C /usr/src/sys/kern sysent
```

Reason:

This gives the forked OS a stable local syscall slot with low churn.

## What To Port Directly, What To Rewrite, What To Drop

### Port Directly

These donor ideas are still good enough to carry over with only normal rework:

1. kernel-owned worker list management;
2. worker parking and idle list management;
3. kernel-owned user stack allocation for new workers;
4. timer-based revisiting of stalled or idle worker state;
5. per-process workqueue object lifetime.

### Rewrite

These donor ideas are valid, but the actual code should be rewritten against
current FreeBSD 15:

1. syscall decoder and syscall ABI;
2. per-process state layout;
3. per-thread metadata storage;
4. scheduler hook integration;
5. QoS bucket accounting;
6. stack teardown or reuse path;
7. priority translation.

### Drop

These donor pieces should not survive into the target system:

1. queue-item add or remove operations as the core ABI;
2. `pthread_workqueue_np` item-queue semantics as the end state;
3. 3-bucket internal priority model;
4. explicit `sched_yield()` hook in phase 1;
5. `td_reuse_stack`;
6. `p_twqlock`;
7. any Mach or launchd-related behavior;
8. direct kevent delivery and workloops in phase 1.

## Userland-Relevant Constraints Discovered During Audit

These are important because they influence the kernel port immediately.

1. `libdispatch` now requires `WORKQ_FEATURE_MAINTENANCE`.
2. `PTHREAD_WORKQUEUE_SPI_VERSION` must be at least `20160427`, or
   `_pthread_workqueue_should_narrow()` is compiled away to a stub that always
   returns false.
3. The worker-thread path is enough for the first useful result; direct kevent
   or workloop delivery is not required for phase 1.

This means the kernel and `libthr` bridge should prioritize:

1. setup and feature discovery;
2. request threads;
3. return threads;
4. `should_narrow`;
5. six-bucket accounting.

## First Real Edit Sequence

This is the recommended order for the next implementation phase.

1. Add the new donor map file to the repo and freeze this milestone.
2. Add `THRWORKQ` build glue:
   - `sys/conf/files`
   - `sys/conf/options`
3. Add the minimal kernel-private header for `twq_kernreturn`.
4. Add the local syscall entry in `syscalls.master`.
5. Regenerate syscall outputs with `make -C /usr/src/sys/kern sysent`.
6. Add the smallest possible `struct proc` and `struct thread` additions:
   - `p_twq`
   - `td_sched_cb`
   - `td_sched_cb_arg`
7. Add callback branches to `mi_switch()` in `kern_synch.c`.
8. Add `twq_proc_exec()` and `twq_proc_exit()` call sites in
   `kern_exec.c` and `kern_exit.c`.
9. Land a stub `kern_thrworkq.c` that:
   - registers eventhandlers;
   - owns `struct twq_proc`;
   - returns `ENOTSUP` or `EINVAL` cleanly for unimplemented ops.
10. Boot that scaffold under `bhyve` before adding any admission logic.
11. Only after the scaffold boots:
   - add six-bucket accounting;
   - add request-thread logic;
   - add return-to-kernel;
   - add `should_narrow`.

This order keeps the first risky kernel phase bounded and observable.

## Implementation Stop Conditions

The port should stop and re-evaluate if any of these become true:

1. the `mi_switch()` callback branch cannot be added without fighting ULE or
   introducing unsafe lock contexts;
2. the six-bucket internal model proves impossible to map cleanly onto ULE even
   approximately;
3. worker return-to-kernel semantics force a `thr_exit()`-based design again;
4. the userland bridge cannot expose `WORKQ_FEATURE_MAINTENANCE`,
   `_pthread_workqueue_addthreads()`, and `should_narrow` without a design
   contradiction.

No such blocker was found in this audit.

## Bottom Line

The donor is still the right donor.

The correct next direction is:

1. keep `NextBSD` as the kernel structural reference;
2. use Darwin and ravynOS as the ABI and semantic references;
3. port only the workqueue subsystem;
4. lean on current FreeBSD 15 eventhandler hooks where possible;
5. reintroduce only one unavoidable scheduler-facing primitive:
   a minimal per-thread switch callback hook.

That is a good direction, not a feature mismatch.
