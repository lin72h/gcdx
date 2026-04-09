# Zig Scaffold

This directory is the low-level and performance test layer for the
`pthread_workqueue` project.

Current scope:

1. syscall probe binaries;
2. ABI and constant validation;
3. microbenchmark stubs for hot paths.

Current host status:

1. the scaffold is present in-repo;
2. the scaffold has been verified locally with Zig `0.15.2`;
3. `twq-probe-stub` is now a real raw syscall probe for local syscall slot
   `468`.

Probe usage:

```sh
zig build
./zig-out/bin/twq-probe-stub --op 1
./zig-out/bin/twq-probe-stub --op 512
./zig-out/bin/twq-probe-stub --op 9999
```

Expected early outcomes:

1. stock kernels may terminate the child with `SIGSYS`, which the probe now
   reports explicitly;
2. kernels with the syscall slot but without `THRWORKQ` enabled should return
   `ENOSYS`;
3. `TWQDEBUG` kernels with the current scaffold should return `ENOTSUP` for
   known ops;
4. unknown ops should return `EINVAL`.

Intended next steps:

1. teach the probe to pass real `TWQ_OP_INIT` and dispatch config payloads;
2. expand the benchmark set beyond the initial placeholder;
3. make the Elixir harness consume richer structured output from the helpers.
