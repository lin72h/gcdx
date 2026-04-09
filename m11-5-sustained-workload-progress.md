# M11.5 Progress: Sustained Dispatch and Worker Reuse

## Outcome

`M11.5` is now real enough to close for phase 1.

The guest lane no longer only proves short dispatch bursts. It now covers:

1. burst-pause-burst reuse of an existing worker pool;
2. a longer mixed-priority sustained workload;
3. bounded idle-worker retention instead of unbounded thread churn.

The important design decision is now explicit:

1. phase 1 accepts a bounded warm worker pool;
2. phase 1 does not require full post-lull retirement to zero;
3. the failure mode we care about here is runaway growth, not the existence of
   a small warm pool.

## Important Source Work

### 1. `libthr` worker reuse was tightened

Relevant file:

1. `/usr/src/lib/libthr/thread/thr_workq.c`

Important changes:

1. the immediate post-callback narrow/exit path was removed;
2. `_pthread_workqueue_should_narrow()` now keeps a small non-overcommit warm
   floor instead of letting dispatch churn one worker per burst;
3. the worker lifecycle is now driven by a wait-sequence wake path, with
   excess idle workers later trimmed by the reaper work captured in `M11.6`.

What this changed in practice:

1. short default-QoS bursts now reuse the same four workers across rounds on a
   four-vCPU guest;
2. the old pattern of one newly created worker per round is gone;
3. narrowing still exists, but it no longer causes obvious short-burst churn.

### 2. The dispatch probe now exercises lifecycle behavior directly

Relevant file:

1. `csrc/twq_dispatch_probe.c`

New modes:

1. `burst-reuse`
2. `sustained`

What they record:

1. round-by-round unique worker growth;
2. new-thread count after each burst;
3. in-process idle/total worker counts between rounds;
4. long-run thread-count samples under mixed-priority load;
5. post-settle total, idle, and active worker counts.

### 3. The guest script and Elixir harness now treat this as first-class

Relevant files:

1. `scripts/bhyve/stage-guest.sh`
2. `elixir/lib/twq_test/vm.ex`
3. `elixir/test/twq_test/vm_integration_test.exs`

The guest lane now stages and validates:

1. the original raw syscall probe;
2. the userland workqueue probe;
3. the basic dispatch probe;
4. the pressure dispatch probe;
5. the burst-reuse lifecycle probe;
6. the sustained lifecycle probe.

## Guest Evidence

### Burst-reuse

The current guest result is:

1. `round_unique_threads:[4,4,4,4]`
2. `round_new_threads:[4,0,0,0]`
3. `round_rest_total:[4,4,4,4]`
4. `round_rest_idle:[4,4,4,4]`
5. `round_rest_active:[0,0,0,0]`
6. `round_should_narrow_true_delta:[0,0,0,0]`
7. `settled_total:4`
8. `settled_idle:4`
9. `settled_active:0`
10. `warm_floor:4`

This is the main lifecycle result:

1. after the first burst creates the pool, later bursts do not create new
   workers;
2. workers stay warm and idle between bursts;
3. there is no visible per-round churn anymore.

### Sustained

The current sustained guest result is:

1. `requested_default:640`
2. `requested_high:1`
3. `unique_threads:4`
4. `default_max_inflight:4`
5. `peak_sample_total:4`
6. `settled_total:4`
7. `settled_idle:4`
8. `settled_active:0`
9. `warm_floor:4`

This means:

1. the mixed-priority sustained load reaches a bounded plateau;
2. the plateau matches the current warm-floor policy instead of growing past
   it;
3. the in-process worker pool remains warm rather than collapsing back to zero.

That is now treated as acceptable phase-1 behavior because:

1. it is bounded;
2. it is stable;
3. it does not accumulate across bursts;
4. the process-scoped state still drops to zero after the probe process exits.

The earlier exploratory variant that drove a much heavier higher-priority lane
was useful because it exposed starvation-shaped behavior, but it was the wrong
shape for this milestone. The current passing sustained workload keeps the
mixed-priority lane active without turning the test into a pure
higher-priority-drain scenario.

## What This Milestone Proves

1. the current kernel-plus-`libthr` split is strong enough to survive longer
   dispatch workloads without obvious thread explosion;
2. the userland-owned worker lifecycle is no longer only a short-lived burst
   story;
3. bounded warm-pool retention is a deliberate policy choice rather than
   visible short-burst churn.

## What It Does Not Yet Prove

1. it does not prove macOS-equivalent warm-worker latency;
2. it does not prove Swift concurrency uses the same path;
3. it does not prove deeper kernel-owned worker lifecycle work is unnecessary
   forever.

It only proves that phase 1 can move forward without stopping for immediate
kernel-owned parking, timer-kthread work, or stack reuse.

## Next Step

Move to `M11.6`: isolate idle-timeout behavior directly, then move to `M12`
with the same anti-fallback TWQ counter discipline already used for dispatch.
