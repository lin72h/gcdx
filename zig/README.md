# Zig Scaffold

This directory is the low-level and performance test layer for the
`pthread_workqueue` project.

Current scope:

1. syscall probe binaries;
2. ABI and constant validation;
3. guest-run hot-path syscall benchmarks.

Current host status:

1. the scaffold is present in-repo;
2. the scaffold has been verified locally with Zig `0.15.2`;
3. `twq-probe-stub` is now a real raw syscall probe for local syscall slot
   `468`;
4. `twq-bench-syscall` now emits real JSON benchmark output for
   `should-narrow`, `reqthreads`, `reqthreads-overcommit`, `thread-enter`,
   `thread-return`, and `thread-transfer` in the guest lane.

Probe usage:

```sh
zig build
./zig-out/bin/twq-probe-stub --op 1
./zig-out/bin/twq-probe-stub --op 512
./zig-out/bin/twq-probe-stub --op 9999
```

Benchmark usage:

```sh
zig build bench-syscall
./zig-out/bin/twq-bench-syscall --mode should-narrow --samples 1024 --warmup 128
```

Real benchmark runs should use the guest wrapper so the binary executes against
the staged `TWQDEBUG` kernel instead of the stock host kernel:

```sh
TWQ_VM_IMAGE=../vm/runs/twq-dev.img \
TWQ_GUEST_ROOT=../vm/runs/twq-dev.root \
TWQ_ZIG_BENCH_MODE=reqthreads \
sh scripts/benchmarks/run-zig-hotpath-bench.sh
```

The default six-mode guest suite runs all current hot-path modes in one guest
boot and emits one structured JSON artifact:

```sh
TWQ_VM_IMAGE=../vm/runs/twq-dev.img \
TWQ_GUEST_ROOT=../vm/runs/twq-dev.root \
sh scripts/benchmarks/run-zig-hotpath-suite.sh
```

Compare a suite or single-mode artifact against the checked-in initial
baseline:

```sh
scripts/benchmarks/compare-zig-hotpath-baseline.py \
  benchmarks/baselines/m13-zig-hotpath-suite-20260416.json \
  ../artifacts/benchmarks/zig-hotpath-suite-YYYYMMDDTHHMMSSZ.json
```

The normal one-command gate is:

```sh
TWQ_VM_IMAGE=../vm/runs/twq-dev.img \
TWQ_GUEST_ROOT=../vm/runs/twq-dev.root \
sh scripts/benchmarks/run-zig-hotpath-gate.sh
```

The gate is deliberately strict on `kern.twq.*` counter deltas and coarse on
nanosecond latency drift. The default latency policy is `3.0x` plus `1000ns`
absolute slack because this lane runs inside a WITNESS-enabled bhyve guest; use
`TWQ_ZIG_HOTPATH_COMPARE_ARGS` to tighten it for quieter bare-metal runs.

Expected early outcomes:

1. stock kernels may terminate the child with `SIGSYS`, which the probe now
   reports explicitly;
2. kernels with the syscall slot but without `THRWORKQ` enabled should return
   `ENOSYS`;
3. `TWQDEBUG` kernels with the current scaffold should return `ENOTSUP` for
   known ops;
4. unknown ops should return `EINVAL`.

Intended next steps:

1. keep expanding the benchmark set beyond the first lifecycle subset into
   wakeup, stack reuse, and future ISA-assisted pre-park experiments;
2. check in and compare guest benchmark baselines by kernel revision;
3. keep the Elixir harness and CLI comparator aligned on the same regression
   policy.
