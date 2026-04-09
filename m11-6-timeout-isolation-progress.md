# M11.6 Progress: Timeout Isolation and Stage Refresh

## Outcome

`M11.6` is now complete enough to close.

This pass resolved the main ambiguity left after `M11.5`:

1. idle retirement is now proven directly, without relying on dispatch
   housekeeping to keep workers warm;
2. long gaps larger than the idle timeout still preserve warm-worker reuse;
3. the staged custom `libthr` path now refreshes itself from newer objdir
   artifacts instead of silently serving stale binaries.

## Important Source Work

### 1. `libthr` lifecycle moved to a reaper-driven model

Relevant file:

1. `/usr/src/lib/libthr/thread/thr_workq.c`

Important changes:

1. workers now wait on a wait-sequence wake path rather than a timed
   condition-variable loop;
2. a background reaper trims excess idle workers back to the bounded warm
   floor after inactivity;
3. temporary debug prints used to validate the reaper path were removed once
   the behavior was proven.

What this changed in practice:

1. overcommit bursts can grow above the warm floor;
2. idle excess workers now retire back to the warm floor after the idle
   window expires;
3. the steady warm pool remains bounded and reusable.

### 2. Timeout behavior is now exercised in two separate ways

Relevant files:

1. `csrc/twq_workqueue_probe.c`
2. `csrc/twq_dispatch_probe.c`

New coverage:

1. a direct no-dispatch `idle-timeout` workqueue probe;
2. a dispatch `timeout-gap` probe with a pause longer than the idle timeout.

What they verify:

1. direct workqueue workers become genuinely idle before the timeout window
   starts;
2. idle overcommit workers retire from `8` down to the `4`-thread warm floor;
3. a long dispatch gap still shows reuse rather than recreation:
   `round_new_threads:[4,0]`.

### 3. The stage path no longer hides stale `libthr` artifacts

Relevant file:

1. `scripts/libthr/prepare-stage.sh`

Important changes:

1. the script now detects newer `*.pico` outputs and refreshes
   `libthr.so.3.full.manual` automatically;
2. the relink path no longer falsely depends on a sibling `libc` objdir
   existing;
3. the stage copy now tracks the actual rebuilt manual shared object.

## Guest Evidence

### Direct idle-timeout probe

The current guest result is:

1. `requested:8`
2. `before_total:8`
3. `before_idle:8`
4. `before_active:0`
5. `settled_total:4`
6. `settled_idle:4`
7. `settled_active:0`
8. `idle_wait_ms:8000`
9. `warm_floor:4`

This means:

1. the timeout window is now measured from a genuinely idle worker state;
2. excess overcommit workers retire cleanly;
3. the remaining warm pool is bounded exactly at the floor.

### Dispatch timeout-gap probe

The current guest result is:

1. `rounds:2`
2. `round_new_threads:[4,0]`
3. `round_rest_total:[4,4]`
4. `round_rest_idle:[4,4]`
5. `settled_total:4`
6. `settled_idle:4`
7. `settled_active:0`
8. `warm_floor:4`

This means:

1. a gap longer than the idle timeout does not recreate the warm worker set;
2. the bounded pool is reused across rounds;
3. the current phase-1 lifecycle split remains defensible.

## What This Milestone Proves

1. the warm-pool story is no longer just an inference from short bursts;
2. idle retirement and long-gap reuse are both real and reproducible;
3. future guest results are less likely to be polluted by stale staged
   `libthr` artifacts.

## What It Does Not Yet Prove

1. it does not prove Swift concurrency uses this path on FreeBSD;
2. it does not prove macOS-equivalent warm-worker latency;
3. it does not prove deeper kernel-owned worker lifecycle work is never
   needed.

## Next Step

Move to the Swift pre-check at `M12`: run the smallest guest Swift concurrency
workload possible and verify that `kern.twq.reqthreads_count` and
`kern.twq.thread_enter_count` actually move during task execution.
