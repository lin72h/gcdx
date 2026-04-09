# M06 Stateful ABI Progress

## Scope

This note records the first point where the port stopped being a stub ABI and
started behaving like a stateful per-process workqueue subsystem.

The goal of this pass was not to implement the full Darwin scheduler model.
The goal was to prove that FreeBSD 15 can host a kernel-private `TWQ_OP_*`
contract with real proc/thread state and that the VM test lane is exercising
that state correctly.

## Kernel ABI and State Added

### Kernel-private ABI

`/usr/src/sys/sys/thrworkq.h` now carries:

1. six internal buckets:
   `MAINTENANCE`, `BACKGROUND`, `UTILITY`, `DEFAULT`,
   `USER_INITIATED`, `USER_INTERACTIVE`;
2. Darwin-shaped priority flag and QoS bit definitions;
3. typed ABI payloads for:
   `TWQ_OP_INIT`, `TWQ_OP_REQTHREADS`, `TWQ_OP_SHOULD_NARROW`,
   and dispatch setup;
4. version and supported-flags constants for the typed commands.

### Kernel state

`/usr/src/sys/kern/kern_thrworkq.c` now has real internal state:

1. `struct twq_proc` with:
   process config, dispatch config, request counts, scheduled counts,
   total counts, idle counts, and thread lists;
2. `struct twq_thread` with:
   owning thread, owning proc, bucket, and lifecycle flags.

### First real opcode behavior

The syscall path now implements:

1. `TWQ_OP_INIT`
   - validates typed init args;
   - creates proc state lazily;
   - stores SPI/config inputs;
   - returns the granted feature mask;
2. `TWQ_OP_SETUP_DISPATCH`
   - validates and stores dispatch offsets and config version;
3. `TWQ_OP_REQTHREADS`
   - validates typed args;
   - maps priority to bucket;
   - computes a simple parallelism limit from `mp_ncpus`;
   - returns the number of additional workers the kernel would admit;
4. `TWQ_OP_THREAD_RETURN`
   - creates per-thread state lazily;
   - attaches the current thread to a bucket;
   - moves it to the idle list and updates counts;
5. `TWQ_OP_SHOULD_NARROW`
   - returns true when total workers in a bucket exceed the currently
     scheduled target for that bucket.

## Important Testing Lesson

The first guest validation revealed a real harness bug:

1. the probe script launched each syscall in a separate process;
2. that meant only `TWQ_OP_INIT` saw configured proc state;
3. later ops returned `EINVAL`, which was technically correct but not useful;
4. the earlier VM assertions were therefore too weak and allowed a false pass.

That bug is now fixed.

### Probe redesign

The Zig probe now supports a same-process sequence runner:

1. `--sequence basic`

That sequence runs:

1. `INIT`
2. `SETUP_DISPATCH`
3. `REQTHREADS(count=2)`
4. `SHOULD_NARROW`
5. `THREAD_RETURN`
6. `SHOULD_NARROW`
7. `REQTHREADS(count=0)`
8. `SHOULD_NARROW`
9. invalid op `9999`

all inside one process, which is the minimum correct shape for testing
proc-owned workqueue state.

## Guest Validation

The `bhyve` integration test now boots `TWQDEBUG`, runs the same-process
sequence in the guest, and verifies the expected results.

Observed sequence in the guest:

1. `INIT` returned `17`
   - granted features `DISPATCHFUNC | MAINTENANCE`;
2. `SETUP_DISPATCH` returned `0`;
3. `REQTHREADS(count=2)` returned `2`;
4. first `SHOULD_NARROW` returned `0`;
5. `THREAD_RETURN` returned `0`;
6. second `SHOULD_NARROW` returned `0`;
7. `REQTHREADS(count=0)` returned `0`;
8. final `SHOULD_NARROW` returned `1`;
9. invalid op `9999` returned `EINVAL`.

That guest trace proves three important things:

1. proc-scoped state persists across calls in one process;
2. thread-return accounting mutates bucket state;
3. narrowing decisions are now connected to earlier request state instead of
   being inert stubs.

## Current Limits

This is still early M06, not M07:

1. admission is based on a simple `mp_ncpus` limit, not the final
   XNU-inspired busy/blocked model;
2. there is no `mi_switch()` feedback path yet;
3. there is no real scheduler priority translation into ULE yet;
4. worker lists are still minimal and mostly used for accounting.

## Why This Matters

This is the first milestone where the port demonstrates the core semantic
shape of the feature:

1. userland negotiates a kernel-private ABI;
2. the kernel owns proc-level worker state;
3. userland requests and returns threads through one control entry point;
4. narrowing decisions depend on kernel-maintained state.

That is enough to justify continuing toward scheduler feedback and a real
`libpthread` bridge without revisiting the donor ABI direction again.
