# M13 DTrace And hwpmc Notes

## Purpose

Use DTrace for GCDX control-flow diagnosis and hwpmc for later hardware-cost
attribution. They answer different questions.

## Why This Exists

The attempted in-process root-push classifier crashed the Swift repeat probe
with `rc=139`. The likely cause is a use-after-publish race: the root push item
can be published to the MPSC queue before the classifier dereferences it.

DTrace lets us observe an explicit `_dispatch_twq_dtrace_*` probe call before
that publish boundary. FreeBSD's `pid` provider did not reliably match
libdispatch's hidden/internal symbols, so the staged debug build exports
no-op probe shims that are only called when `LIBDISPATCH_TWQ_DTRACE_PROBES=1`.

## Guest Setup

`TWQDEBUG` includes `GENERIC-DEBUG`, which includes the FreeBSD `GENERIC`
settings for:

1. `WITH_CTF=1`
2. `KDTRACE_FRAME`
3. `KDTRACE_HOOKS`
4. `DDB_CTF`
5. `HWPMC_HOOKS`

Inside the guest, load DTrace modules before tracing:

```sh
kldload dtraceall
```

For later hardware profiling on bare metal, load hwpmc:

```sh
kldload hwpmc
```

## DTrace Scripts

`scripts/bhyve/stage-guest.sh` installs these files under `/root/twq-dtrace`
in the guest.

The easiest host-side path is the M13 runner in DTrace mode:

```sh
TWQ_VM_IMAGE=/Users/me/wip-gcd-tbb-fx/vm/runs/twq-dev.img \
TWQ_GUEST_ROOT=/Users/me/wip-gcd-tbb-fx/vm/runs/twq-dev.root \
TWQ_DTRACE_MODE=push-poke-drain \
TWQ_DTRACE_TARGET=swift-repeat \
./scripts/benchmarks/run-m13-baseline.sh
```

Supported modes:

1. `push-poke-drain`
2. `push-vtable`
3. `root-summary`

Supported targets:

1. `swift-repeat`
2. `c-repeat`

Implementation detail: the guest runner applies the target environment to the
`dtrace` command itself and passes the real probe binary to `dtrace -c`. Do not
wrap the target in `/usr/bin/env` inside `-c`, because the `pid` provider will
bind to `env` before the final probe executable is reached.

Manual guest commands are still useful when iterating inside a staged image.
Start with pointer-only tracing:

```sh
env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib \
  LIBDISPATCH_TWQ_DTRACE_PROBES=1 \
  TWQ_REPEAT_ROUNDS=64 TWQ_REPEAT_TASKS=8 TWQ_REPEAT_DELAY_MS=20 \
  TWQ_REPEAT_DEBUG_FIRST_ROUND=1 \
  dtrace -Z -x nolibs -x evaltime=main -s /root/twq-dtrace/m13-push-poke-drain.d \
  -c /root/twq-swift-dispatchmain-taskhandles-after-repeat
```

If that works, classify push and pop objects by vtable pointer:

```sh
env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib \
  LIBDISPATCH_TWQ_DTRACE_PROBES=1 \
  TWQ_REPEAT_ROUNDS=64 TWQ_REPEAT_TASKS=8 TWQ_REPEAT_DELAY_MS=20 \
  TWQ_REPEAT_DEBUG_FIRST_ROUND=1 \
  dtrace -Z -x nolibs -x evaltime=main -s /root/twq-dtrace/m13-push-vtable.d \
  -c /root/twq-swift-dispatchmain-taskhandles-after-repeat
```

For low-volume totals:

```sh
env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib \
  LIBDISPATCH_TWQ_DTRACE_PROBES=1 \
  TWQ_REPEAT_ROUNDS=64 TWQ_REPEAT_TASKS=8 TWQ_REPEAT_DELAY_MS=20 \
  TWQ_REPEAT_DEBUG_FIRST_ROUND=1 \
  dtrace -Z -x nolibs -x evaltime=main -s /root/twq-dtrace/m13-root-summary.d \
  -c /root/twq-swift-dispatchmain-taskhandles-after-repeat
```

## Symbol Check

The staged `libdispatch.so` exports DTrace probe shims for the seams we need:

```sh
nm -D /root/twq-dispatch/libdispatch.so | grep _dispatch_twq_dtrace
```

Expected useful symbols include:

1. `_dispatch_twq_dtrace_root_queue_push_probe`
2. `_dispatch_twq_dtrace_root_queue_poke_probe`
3. `_dispatch_twq_dtrace_continuation_pop_probe`
4. `_dispatch_twq_dtrace_queue_cleanup2_probe`
5. `_dispatch_twq_dtrace_async_redirect_probe`

## Post-Processing

Map vtable pointers from `m13-push-vtable.d` back to local symbols:

```sh
nm -a /root/twq-dispatch/libdispatch.so | sort > /tmp/libdispatch.nm
```

Then compare the vtable addresses emitted by DTrace against nearby `dispatch`
vtable symbols in `/tmp/libdispatch.nm`.

From the host, use the checked-in helper against a captured serial log:

```sh
scripts/dtrace/analyze-m13-vtable.py \
  /Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-dtrace-push-vtable-20260416T042209Z.serial.log
```

The current Swift repeat sample shows the important shape:

1. default root receives `__OS_dispatch_source_vtable` pushes;
2. default-overcommit receives `__OS_dispatch_queue_main_vtable` pushes;
3. user-initiated receives Swift/global continuation pushes.

For non-DTrace counter runs, the M13 extractor preserves
`[libdispatch-twq-counters]` dumps in the structured JSON:

```sh
scripts/benchmarks/summarize-m13-baseline.py \
  /Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json \
  --mode swift.dispatchmain-taskhandles-after-repeat
```

## hwpmc Role

Do not use hwpmc for the `rc=139` crash. That failure is a pointer-safety bug,
not a hardware-cost question.

Use hwpmc after DTrace has identified the remaining semantic hot path.

Useful starting commands on bare metal:

```sh
pmc list
pmcstat -S instructions -O /tmp/gcdx-instructions.pmc -- /path/to/repeat-probe
pmcstat -R /tmp/gcdx-instructions.pmc -g
```

Use hwpmc to answer:

1. where cycles are spent after the queue/root behavior is understood;
2. whether remaining churn is instruction-heavy, cache-miss-heavy, or branchy;
3. whether a GCDX change reduces actual CPU cost, not just TWQ request counts.

Prefer bare metal for hwpmc. `bhyve` is fine for DTrace control-flow tracing,
but virtual PMCs may be incomplete or distorted.
