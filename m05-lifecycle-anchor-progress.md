# M05 Lifecycle Hook Progress

## Scope

This note records the point where lifecycle wiring stopped being placeholder
anchors and became real ownership and cleanup logic.

The goal of M05 was to make process-scoped and thread-scoped workqueue state
survive normal kernel lifecycle edges without dragging the port back toward the
old donor model.

## Kernel State Anchors

### Process state

Added to `struct proc`:

1. `struct twq_proc *p_twq`

Important correction:

1. `p_twq` does **not** live in the proc zeroed-on-creation region anymore;
2. an earlier placement there tripped FreeBSD 15 KBI offset assertions in
   `kern_thread.c`;
3. it was moved to the tail of `struct proc`;
4. zero-initialization now comes from the `process_init` eventhandler, not
   from field placement.

### Thread state

Added to `struct thread`:

1. `struct twq_thread *td_twq`

This still follows the intended direction:

1. it is a dedicated thread-scoped anchor;
2. it avoids reviving donor fields such as `td_threadlist` or
   `td_reuse_stack`;
3. it gives the new implementation a clean place to attach worker metadata.

## Lifecycle Hooks Now Wired

### Initialization

`kern_thrworkq.c` registers:

1. `process_init` to set `p->p_twq = NULL`;
2. `thread_init` to set `td->td_twq = NULL`.

### Cleanup edges

The hooks are wired into:

1. `pre_execve()` via `twq_proc_exec(p)`;
2. `exit1()` via `twq_proc_exit(p)`;
3. `kern_thr_exit()` via `twq_thread_exit(td)`.

Current cleanup behavior is real, not placeholder:

1. `twq_thread_exit()` now calls `twq_thread_release(td)`;
2. `twq_proc_exec()` releases all thread-attached TWQ state for the process and
   then frees the proc-scoped `twq_proc`;
3. `twq_proc_exit()` does the same on process teardown;
4. the per-thread free path clears `td->td_twq`, removes idle accounting, and
   decrements the per-bucket thread totals when needed.

## Why This Matters

This milestone closes two early design risks:

1. the kernel no longer relies on a fake lifecycle story where pointers were
   present but never actually released;
2. cleanup is now aligned with the new proc-owned / thread-owned split instead
   of depending on donor-era stack and threadlist assumptions.

It also resolved a real FreeBSD 15 integration lesson:

1. `struct proc` layout changes are constrained by KBI assertions even for a
   private fork;
2. the safe early pattern is to keep new pointers near the tail and let
   explicit init hooks establish invariants.

## Validation

Validation now includes both build and execution:

1. the `TWQDEBUG` kernel relinked successfully after the `struct proc` move;
2. the guest boot path in `bhyve` remained clean after the lifecycle changes;
3. the VM integration test still passed after cleanup was made real.

## Relationship To M06

M05 is effectively complete enough to stop treating lifecycle work as a
separate blocker.

What remains belongs to M06 and later:

1. richer worker state transitions beyond idle bookkeeping;
2. scheduler-facing feedback;
3. stronger observability for leak and lifetime debugging under load.
