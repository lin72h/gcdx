# M07 and M08 Feedback / Observability Progress

## Scope

This note records the first scheduler-facing and observability-heavy pass after
the stateful ABI milestone, including the follow-up pass that made active
workers visible before they return.

The goal of this round was not to finish admission control. The goal was to
land the smallest FreeBSD-native scheduler hook that is worth keeping, and to
make that hook visible in the guest harness through stable `kern.twq.*`
signals.

## Kernel Changes

### 1. TWQ-specific switch hook in `mi_switch()`

The switch path now calls `twq_thread_switch()` from `mi_switch()` in
`/usr/src/sys/kern/kern_synch.c`:

1. before `sched_switch()` as `TWQ_SWCB_BLOCK`;
2. after `sched_switch()` as `TWQ_SWCB_UNBLOCK`.

Important design choice:

1. this is not a new generic scheduler callback framework;
2. it is a TWQ-specific hook keyed off `td->td_twq`;
3. that keeps the edit surface minimal while the feature is still private to
   this port.

### 2. Atomic-only switch-path behavior

`twq_thread_switch()` in `/usr/src/sys/kern/kern_thrworkq.c` only performs:

1. blocking-reason filtering from the `mi_switch()` flags;
2. flag updates on the current thread's TWQ state;
3. atomic global counter increments;
4. atomic timestamp publication to per-proc blocked-time state.

It does **not** take sleeping locks on the switch path.

The follow-up pass also tightened the hook so idle returned workers are ignored
on the switch path. A parked worker sleeping in userspace no longer looks like
real scheduler pressure.

### 3. Kernel observability under `kern.twq.*`

The kernel now exports cumulative stats through sysctls:

1. op counts:
   `init_count`, `thread_enter_count`, `setup_dispatch_count`,
   `reqthreads_count`,
   `thread_return_count`, `should_narrow_count`,
   `should_narrow_true_count`;
2. lifetime counts:
   `proc_alloc_count`, `proc_free_count`,
   `thread_state_alloc_count`, `thread_state_free_count`;
3. switch-path counts:
   `switch_block_count`, `switch_unblock_count`;
4. cumulative bucket totals:
   `bucket_thread_enter_total`,
   `bucket_req_total`, `bucket_admit_total`,
   `bucket_thread_return_total`,
   `bucket_switch_block_total`,
   `bucket_switch_unblock_total`.
5. live bucket state:
   `bucket_total_current`, `bucket_idle_current`, `bucket_active_current`.

These are cumulative by design so they remain useful after the probe process
has exited and released its proc-owned TWQ state.

### 4. First pressure-aware admission rule

`TWQ_OP_REQTHREADS` and `TWQ_OP_SHOULD_NARROW` no longer use only the raw
stored `scheduled_count`.

They now recompute the bucket target from:

1. the requested worker count for the bucket;
2. the bucket's parallelism limit;
3. recent higher-priority pressure from buckets above it;
4. recent blocked-worker timestamps within a configurable busy window.

This is still simpler than the donor/XNU model, but it is the first real
step beyond static per-bucket caps.

The important correction from the second pass is that "busy" now keys off
non-idle counted workers rather than the earlier request-target proxy. That
lets the kernel distinguish an actually entered worker that blocked from a
thread that has already returned idle.

## Harness Changes

### Same-process probe still retained

The Zig probe keeps the same-process sequence runner from M06.

### Blocking syscall retained

The `basic` sequence now performs a short `usleep()` after
`TWQ_OP_THREAD_RETURN`.

After the worker-entry pass, that sleep still helps exercise lifecycle cleanup,
but it no longer contributes worker-pressure signal because the thread is idle.

### Pressure split into idle and entered cases

The Zig probe now now uses two different pressure shapes:

1. `pressure`:
   initialize a workqueue process, request one user-interactive worker,
   return it idle, block briefly, then request four default workers;
2. `entered-pressure`:
   initialize a workqueue process, start a real helper thread that calls
   `TWQ_OP_THREAD_ENTER`, blocks briefly while still active, then request
   four default workers from the main thread.

With a widened test-time busy window, these two shapes now diverge in the VM:

1. the idle returned worker no longer constrains default work;
2. the actually entered and blocked worker does.

### Guest staging prints kernel TWQ stats

`stage-guest.sh` now dumps the relevant `kern.twq.*` sysctls after the probe
sequence and before shutdown.

The VM integration test now asserts on both:

1. the structured syscall results;
2. the exported kernel stats.

## Guest Validation

Observed in the guest serial log:

1. the stateful TWQ syscall sequence still passed;
2. the new stats matched the probe exactly:
   - `init_count: 1`
   - `setup_dispatch_count: 1`
   - `reqthreads_count: 2`
   - `thread_return_count: 1`
   - `should_narrow_count: 3`
   - `should_narrow_true_count: 1`
   - `switch_block_count: 1`
   - `switch_unblock_count: 1`
   - `bucket_req_total: 0,0,0,2,0,0`
   - `bucket_admit_total: 0,0,0,2,0,0`
   - `bucket_thread_return_total: 0,0,0,1,0,0`
   - `bucket_switch_block_total: 0,0,0,1,0,0`
   - `bucket_switch_unblock_total: 0,0,0,1,0,0`

That proves the switch hook is not merely compiled in. It is live in the VM
and visible through the harness.

After the worker-entry work landed, the guest lane proved the more honest
split:

1. `kern.twq.busy_window_usecs` can be widened for deterministic guest tests;
2. the idle-return path produced:
   - user-interactive `REQTHREADS(1) -> 1`
   - default `REQTHREADS(4) -> 4`
3. the entered-worker path produced:
   - user-interactive `THREAD_ENTER -> 0`
   - default `REQTHREADS(4) -> 3`
4. the cumulative kernel stats matched the three-sequence run:
   - `init_count: 3`
   - `thread_enter_count: 1`
   - `setup_dispatch_count: 3`
   - `reqthreads_count: 5`
   - `thread_return_count: 2`
   - `switch_block_count: 1`
   - `switch_unblock_count: 1`
   - `bucket_thread_enter_total: 0,0,0,0,0,1`
   - `bucket_req_total: 0,0,0,10,0,1`
   - `bucket_admit_total: 0,0,0,9,0,1`
   - `bucket_thread_return_total: 0,0,0,1,0,1`
   - `bucket_switch_block_total: 0,0,0,0,0,1`
   - `bucket_switch_unblock_total: 0,0,0,0,0,1`
   - `bucket_total_current: 0,0,0,0,0,0`
   - `bucket_idle_current: 0,0,0,0,0,0`
   - `bucket_active_current: 0,0,0,0,0,0`

## What This Does Not Claim Yet

This is not the final admission model:

1. `should_narrow` still does not use the final busy/blocked-window logic;
2. active-worker accounting is now real for entered workers, but the final
   `libthr` bridge still needs to drive it;
3. there is still no yield-driven expansion path;
4. there is still no scheduler priority mapping work against ULE.

## Why This Matters

This milestone changes the project in two important ways:

1. there is now a real scheduler-facing edge in the FreeBSD 15 kernel;
2. the feature is now inspectable after guest execution without manual kernel
   printf debugging.

That is enough to move toward the first honest userland bridge without
pretending that idle returned threads are the same thing as blocked workers.
