# M04 Kernel Scaffold Progress

## Scope

This note records the first real kernel-side `pthread_workqueue` scaffold
landed in `/usr/src` against FreeBSD 15 `stable/15`.

The goal of this pass was narrow:

1. reserve the syscall entry point;
2. add the minimum kernel header and source scaffold;
3. make the generated syscall surface update cleanly;
4. prove the new path compiles under a debug kernel config.

This pass did not attempt real behavior yet. The syscall still returns
`ENOTSUP` for known operations and `EINVAL` for unknown ones when `THRWORKQ`
is enabled, and `ENOSYS` when it is not.

## `/usr/src` Touch Set

Source and config files:

1. `/usr/src/sys/conf/options`
2. `/usr/src/sys/conf/files`
3. `/usr/src/sys/kern/syscalls.master`
4. `/usr/src/sys/sys/thrworkq.h`
5. `/usr/src/sys/kern/kern_thrworkq.c`
6. `/usr/src/sys/amd64/conf/TWQDEBUG`

Generated files updated through `make -C /usr/src/sys/kern sysent`:

1. `/usr/src/sys/kern/init_sysent.c`
2. `/usr/src/sys/kern/syscalls.c`
3. `/usr/src/sys/sys/syscall.h`
4. `/usr/src/sys/sys/syscall.mk`
5. `/usr/src/sys/sys/sysproto.h`
6. `/usr/src/lib/libsys/_libsys.h`
7. `/usr/src/lib/libsys/syscalls.map`

## What Was Added

### 1. New local syscall entry

Slot `468` is now wired as:

1. `twq_kernreturn(int op, void *arg2, int arg3, int arg4)`

This keeps the eventual kernel ABI shaped around a Darwin-style command
multiplexer rather than inheriting NextBSD's older work-item syscall model.

### 2. Kernel-private header

`/usr/src/sys/sys/thrworkq.h` now defines:

1. the first `TWQ_OP_*` command constants;
2. `TWQ_FEATURE_*` bits needed for later userland negotiation;
3. the first SPI version constants;
4. `struct twq_dispatch_config`;
5. kernel-side lifecycle hook prototypes for later milestones.

### 3. Stub kernel implementation

`/usr/src/sys/kern/kern_thrworkq.c` currently provides:

1. `sys_twq_kernreturn()`;
2. command validation for the known `TWQ_OP_*` set;
3. `twq_proc_exec()` and `twq_proc_exit()` stubs for later lifecycle work.

### 4. Debug kernel config

`/usr/src/sys/amd64/conf/TWQDEBUG` now exists as the dedicated kernel config
for this project's bring-up work.

## Important Implementation Lesson

`kern_thrworkq.c` currently has to be listed as `standard`, not
`optional thrworkq`.

Reason:

1. the syscall table is generated unconditionally from `syscalls.master`;
2. that means `sys_twq_kernreturn` must always exist at link time;
3. the option gate therefore has to live inside the implementation for now.

So the correct early pattern is:

1. always compile the file;
2. return `ENOSYS` when the option is not enabled;
3. keep the real behavior behind `#ifdef THRWORKQ`.

This is small, but it materially changes how the feature gate should be carried
through the early milestones.

## Validation Performed

### Syscall generation

Ran:

```sh
make -C /usr/src/sys/kern sysent
```

This completed successfully after making the generated output files writable.

### Focused compile validation

Configured kernel objdir:

1. `/tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG`

Successful targeted builds:

```sh
make -C /tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG kern_thrworkq.o
make -C /tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG init_sysent.o
make -C /tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG syscalls.o
```

Artifacts confirmed:

1. `kern_thrworkq.o`
2. `init_sysent.o`
3. `syscalls.o`

### Full kernel link validation

Successful objdir-driven kernel build:

```sh
env SRCTOP=/usr/src make -C /tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG kernel -j4
```

Important note:

1. the direct objdir invocation needs `SRCTOP=/usr/src`;
2. without that, parts of the kernel build may collapse `${SRCTOP}` into an
   empty path and fail on unrelated include directories such as `/sys/dev/ath`.

With `SRCTOP` set correctly, the `TWQDEBUG` kernel linked successfully and
produced:

1. `kernel.full`
2. `kernel.debug`
3. `kernel`

## What Was Learned

1. the `twq_kernreturn` syscall shape is acceptable to FreeBSD's syscall
   generator;
2. the generated kernel and libsys surfaces update cleanly;
3. the stub source compiles under the `TWQDEBUG` kernel environment with
   `-Werror`;
4. there is no immediate structural blocker in `/usr/src` for the first real
   scaffold.

## What Is Still Missing Before M04 Is Done

1. run a clean no-modules kernel build instead of the broad default
   `buildkernel` sweep;
2. install the resulting `TWQDEBUG` kernel into a guest image;
3. boot the guest and verify the new syscall path is inert but stable;
4. confirm non-`THRWORKQ` kernels still behave correctly.

## Why This Matters

This is the first point where the project stopped being only strategy and
became a real kernel port effort.

The scaffold is intentionally thin, but it already proves three critical
things:

1. the FreeBSD 15 tree can host the new syscall and header cleanly;
2. the project can carry a Darwin-shaped control entry point without dragging
   in the old donor ABI;
3. the next work can move into lifecycle hooks and real state management
   instead of revisiting the same bootstrap questions.
