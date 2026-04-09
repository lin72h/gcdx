# pthread_workqueue Testing Strategy

## Status

This document defines the testing architecture for the FreeBSD 15
`pthread_workqueue` effort.

It is intentionally separate from the main implementation plan because testing
is not a side concern here. The quality of this port depends on having a test
stack that is less fragile than the traditional FreeBSD shell-based approach
and honest enough to catch both semantic regressions and performance drift.

## Core Decision

The primary testing stack should be:

1. Elixir for most feature, integration, system, and comparison testing.
2. Zig for low-level, C-facing, ABI-sensitive, and performance-sensitive tests.
3. Shell only as a thin transport and orchestration layer when unavoidable.

This means the project should **not** treat `atf-sh` style shell tests as the
main test framework for this feature.

## Clarified Testing Intent

The test stack exists to keep the port honest while pushing it toward strong
macOS-like `libdispatch` semantics in a way that still feels natural on
FreeBSD.

That means:

1. phase 1 should prioritize semantic correctness and real kernel workqueue
   behavior over exact macOS performance;
2. the framework should clearly prove that the system is doing something more
   real than a compatibility-library story;
3. macOS comparison is a reference lane, not a mandatory gate for every run;
4. performance expectations should tighten gradually as the implementation
   matures.

## Why This Direction

### Why not shell-first testing

Shell-based testing is fragile for this project because:

1. it encourages text scraping instead of structured assertions;
2. process control, retries, timing windows, and multi-step orchestration become
   hard to reason about;
3. kernel-feature testing already has enough nondeterminism without adding more
   parser and quoting failure modes;
4. cross-host comparison between FreeBSD and macOS becomes unpleasant when the
   harness is mostly shell.

Shell still has a role, but only as glue:

1. launching `bhyve`;
2. mounting or updating VM images;
3. invoking `doas` where needed;
4. performing one-shot setup that higher-level code can call.

Pass/fail logic should not live in shell.

### Why Elixir for most tests

Elixir is a good fit because it gives us:

1. a strong test framework in `ExUnit`;
2. good concurrency primitives for orchestration;
3. practical process supervision when dealing with VMs, SSH sessions, serial
   capture, and external helper programs;
4. a clean path to property-based and state-machine testing;
5. easy structured data handling for logs, metrics, and result comparison;
6. a single harness that can run on FreeBSD and on the Apple Silicon macOS
   reference host.

For this project, Elixir should be the default answer to:

1. "How do we test this feature end to end?"
2. "How do we coordinate the VM and assert on behavior?"
3. "How do we compare FreeBSD against canonical macOS behavior?"

It is also the right default for the long-term shape of the project:

1. most tests should live in a durable, structured, readable language;
2. the harness should remain maintainable as the feature set grows.

### Why Zig for low-level and performance tests

Zig is a good fit because it gives us:

1. first-class C interop through `@cImport`;
2. direct control over low-level timing and memory behavior;
3. easy production of small helper binaries;
4. a practical test runner via `zig test`;
5. a clean way to write benchmarks without committing to a large framework.

For this project, Zig should be the default answer to:

1. syscall ABI probes;
2. struct layout and constant validation against C headers;
3. microbenchmarks for thread request, return, narrow, and stack reuse paths;
4. performance-focused tests where Elixir would add too much harness overhead.

This matches the explicit requirement to use Zig for the C-facing and
performance-sensitive parts of the project.

## Requirements Captured for This Project

These requirements are now explicit:

1. most tests should be written in Elixir;
2. the project should avoid relying on FreeBSD's traditional shell-based test
   style for primary coverage;
3. Zig should be used for the most performance-sensitive and C-facing tests;
4. the test framework must be ready early enough to make performance and
   regression claims credible;
5. the same repo will later be cloned onto the Apple M5-based macOS 26.4 host,
   and that machine should act as the canonical `libdispatch` behavior
   reference.

## Testing Principles

### 1. Structured outputs only

Tests and helpers should emit structured data, not ad hoc human-oriented text.

Preferred formats:

1. JSON lines for streaming events;
2. JSON summaries for final results;
3. machine-readable counters and histograms where possible.

Reason:

If a test needs `grep | sed | awk` to understand its result, the design is
already too fragile.

### 2. Orchestration and assertion are different concerns

It is acceptable to use shell to boot a VM.
It is not acceptable to let shell decide whether a complex workqueue test
passed.

Reason:

This keeps the control path thin and the assertion logic readable.

### 3. FreeBSD and macOS play different roles

FreeBSD-in-`bhyve` is the main engineering target.
Apple Silicon macOS is the canonical behavior reference.

Reason:

The FreeBSD side is where kernel iteration, crashes, and instrumentation live.
The macOS side is where canonical `libdispatch` behavior lives.

### 4. Performance claims require a dedicated test lane

No claim about thread pressure, narrowing, or workqueue quality should rest
only on functional tests.

Reason:

A port can be semantically correct and still regress badly in thread growth,
latency, or worker reuse.

### 5. Comparability is the goal, not total compatibility

macOS should be used as the oracle for natural `libdispatch` behavior.
It should not be used as a demand for bit-for-bit Darwin behavior in every
corner.

Reason:

This project is for FreeBSD, not a full Darwin reimplementation.

### 6. Early performance goals should be realistic

The first iterations do not need to match macOS performance.

The framework should initially answer:

1. are the semantics correct;
2. is the real kernel-backed path active;
3. is behavior clearly stronger than the fallback or compatibility path;
4. are there obvious failures such as thread explosion, useless narrowing, or
   poor reuse.

Reason:

This matches the project direction: semantics first, then gradual performance
improvement toward macOS where that remains natural.

## Recommended Repo Layout

When code work begins, the repo should grow toward a layout like this:

```text
docs/
  pthread-workqueue-port-plan.md
  pthread-workqueue-testing-strategy.md

elixir/
  mix.exs
  mix.lock
  config/
  lib/
  test/
  test/support/
  priv/

zig/
  build.zig
  build.zig.zon
  src/
  test/
  bench/
  c/

scripts/
  bhyve/
  image/
  capture/

fixtures/
  configs/
  workloads/
  baselines/
```

Role of each area:

1. `docs/` holds stable design documents;
2. `elixir/` holds the main harness and most tests;
3. `zig/` holds low-level helpers, ABI probes, and benchmarks;
4. `scripts/` holds thin wrappers only;
5. `fixtures/` holds non-generated inputs and expected baselines.

Generated logs, dumps, and heavy artifacts should remain outside the repo or in
ignored paths.

## Tooling Baseline

The local ports tree already contains:

1. `/usr/ports/lang/elixir`
2. `/usr/ports/lang/zig`

Current local ports snapshot shows:

1. Elixir `1.17.3`
2. Zig `0.15.2`

These versions should be treated as the current starting point, not as a
forever pin.

## Test Stack Overview

The project should have three test layers, not one:

### Layer A: Elixir orchestration and feature tests

This is the default test layer.

It should cover:

1. syscall semantics from the outside;
2. process lifecycle behavior;
3. `libthr` bridge behavior;
4. `libdispatch` behavior;
5. Swift concurrency scenarios;
6. FreeBSD versus macOS comparison runs;
7. orchestration of guests, traces, logs, and metrics.

### Layer B: Zig low-level tests and benchmarks

This is the precision layer.

It should cover:

1. syscall ABI layouts;
2. header and constant validation;
3. C interop checks against FreeBSD headers;
4. microbenchmarks for hot paths;
5. minimal helper binaries for guest-side probing.

### Layer C: Thin shell wrappers

This is the utility layer.

It should cover only:

1. `bhyve` launch;
2. image preparation and kernel replacement;
3. dump capture helpers;
4. convenience commands for developers.

It should not contain core assertions.

## Elixir as the Primary Harness

### Recommended project shape

The Elixir side should be a normal `Mix` project.

Suggested internal modules:

1. `TwqTest.Env`
2. `TwqTest.VM`
3. `TwqTest.Image`
4. `TwqTest.Guest`
5. `TwqTest.SSH`
6. `TwqTest.Serial`
7. `TwqTest.Sysctl`
8. `TwqTest.Trace`
9. `TwqTest.Results`
10. `TwqTest.MacRef`
11. `TwqTest.Workloads`
12. `TwqTest.Assert`

Suggested responsibilities:

1. `Env` resolves host role, paths, and configuration;
2. `VM` controls `bhyve` lifecycle;
3. `Image` updates kernels and guest roots;
4. `Guest` executes commands in the guest in a structured way;
5. `SSH` handles remote transport when SSH is used;
6. `Serial` captures console and panic output;
7. `Sysctl` reads kernel counters and tunables;
8. `Trace` wraps `truss`, `ktrace`, `kdump`, or future tracing helpers;
9. `Results` writes machine-readable summaries;
10. `MacRef` runs the same workloads on macOS and aligns result schemas;
11. `Workloads` defines reusable dispatch and Swift scenarios;
12. `Assert` centralizes interpretation of metrics and pass/fail policy.

### ExUnit should be the top-level driver

Use `ExUnit` as the main test entrypoint.

Advantages:

1. standard tagging and filtering;
2. clean setup and teardown hooks;
3. async tests where safe;
4. deterministic reporting;
5. easy integration with helper processes.

Suggested tags:

1. `:unit`
2. `:guest`
3. `:kernel`
4. `:dispatch`
5. `:swift`
6. `:macos_ref`
7. `:bench`
8. `:slow`
9. `:destructive`

### Property and state-machine testing

Elixir should also host model-based testing for the workqueue contract.

Recommended uses:

1. random sequences of `INIT`, `REQTHREADS`, `THREAD_RETURN`, and
   `SHOULD_NARROW` requests against a reference model;
2. lifecycle checks around `exec`, exit, duplicate init, and reuse behavior;
3. invariants such as "active count never negative", "narrow never true when
   the system is clearly underutilized", and "thread request totals converge
   back to zero".

Use `StreamData` or a comparable property-testing library on the Elixir side.

Reason:

This gives the project a high-level correctness model that is much easier to
evolve than a pile of shell scripts.

### Elixir test categories

The Elixir suite should be organized around the following categories.

#### 1. Pure harness and model tests

Run without a VM.

Examples:

1. result schema validation;
2. parsing and normalization of trace output;
3. state-machine model tests for request and narrow behavior;
4. threshold comparison logic.

#### 2. Guest control tests

Verify the harness itself.

Examples:

1. VM boots;
2. serial capture works;
3. guest command execution works;
4. kernel replacement helper works;
5. dump capture helpers work.

#### 3. Kernel feature tests

These are simple behavioral tests but still use structured Elixir assertions.

Examples:

1. workqueue init succeeds once;
2. duplicate init is rejected;
3. requesting constrained threads updates stats as expected;
4. overcommit requests bypass constrained limits;
5. worker return parks or reassigns a thread correctly;
6. `should_narrow` answers change with load;
7. `exec` and exit clean up per-process workqueue state.

#### 4. `libthr` and `libdispatch` tests

Examples:

1. `_pthread_workqueue_init()` path is used;
2. thread requests are visible in kernel counters;
3. fallback is not silently used;
4. dispatch workloads show bounded growth and recovery.

#### 5. Swift concurrency tests

Examples:

1. task groups under CPU load;
2. mixed blocking and compute workloads;
3. detached tasks;
4. fan-out and fan-in stress;
5. priority-sensitive task mixes.

#### 6. Comparison tests against macOS

Examples:

1. identical workload definitions run on both FreeBSD and macOS;
2. resulting worker growth, narrowing, and completion timing are collected into
   a common schema;
3. the harness flags meaningful divergence for review.

## Zig as the Low-Level and Performance Layer

### Recommended Zig project shape

The Zig side should be a normal `zig build` project.

Suggested targets:

1. `zig build test-abi`
2. `zig build test-syscall`
3. `zig build test-c-interop`
4. `zig build bench-syscall`
5. `zig build bench-thread-create`
6. `zig build bench-thread-return`
7. `zig build bench-narrow`
8. `zig build bench-stack-reuse`

### What Zig should test

#### 1. ABI layout validation

Zig should `@cImport` the project headers and validate:

1. command constants;
2. struct sizes;
3. struct alignment;
4. field offsets where relevant;
5. flag encodings.

Reason:

This is the kind of low-level validation that is awkward in Elixir and too
important to leave implicit.

#### 2. Syscall probe binaries

Small Zig programs should directly exercise:

1. init;
2. request threads;
3. thread return;
4. should narrow;
5. invalid argument cases.

These programs should emit structured JSON summaries so the Elixir harness can
consume them directly.

Reason:

This keeps the probe binaries small and honest while leaving orchestration and
assertion in Elixir.

#### 3. C-facing integration checks

Zig should validate the C-facing parts that matter to this port:

1. header inclusion;
2. calling convention assumptions;
3. `pthread_priority_t` translation helpers;
4. syscall parameter marshalling;
5. interop with test helper C code where needed.

Reason:

Zig is especially good at sitting next to C APIs without forcing a large
separate framework.

#### 4. Microbenchmarks

Zig should host the serious microbenchmarks.

Initial benchmark candidates:

1. request-thread syscall overhead;
2. should-narrow query overhead;
3. thread create latency;
4. thread return and park latency;
5. wakeup latency for reused workers;
6. stack reuse benefit versus fresh stack allocation;
7. constrained versus overcommit throughput under synthetic load.

Reason:

These are exactly the areas where a high-level runtime would distort the
measurement too much.

### Benchmark output rules

Every Zig benchmark should emit:

1. test name;
2. kernel build identifier;
3. workload parameters;
4. sample count;
5. mean;
6. median;
7. p95;
8. p99 where useful;
9. standard deviation or equivalent spread metric.

Prefer JSON output.

Reason:

That allows the Elixir layer to archive, compare, and gate regressions without
parsing free-form text.

## Division of Responsibility Between Elixir and Zig

### Elixir should own

1. orchestration;
2. system setup and teardown;
3. guest management;
4. high-level feature assertions;
5. comparison testing against macOS;
6. result collation and reporting;
7. property and state-machine testing.

### Zig should own

1. ABI and layout validation;
2. direct syscall helper programs;
3. C interop checks;
4. hot-path microbenchmarks;
5. low-overhead probes used by Elixir.

### Shell should own only

1. bootstrapping;
2. VM launch and stop wrappers;
3. image and dump utilities;
4. very small helpers that are not worth reimplementing elsewhere.

## FreeBSD Guest Test Strategy

### Guest-side software stack

The FreeBSD guest should eventually contain enough tooling to run:

1. guest-side Zig helper binaries;
2. guest-side userland test programs;
3. optional Elixir workloads if that becomes practical.

Preferred model:

1. the main harness runs on the host in Elixir;
2. the host drives guest programs through SSH or serial;
3. guest programs emit structured results;
4. the host owns pass/fail interpretation.

Reason:

This avoids overloading the guest while still keeping test logic out of shell.

### Elixir in the guest versus Elixir on the host

Default assumption:

1. Elixir runs on the host as the main controller.

Optional later expansion:

1. some guest-side test runners may also use Elixir if it becomes convenient
   and the guest image budget allows it.

Reason:

Running Elixir on the host is enough to get the main benefits immediately.
Guest-side Elixir is optional, not required for the architecture to work.

## macOS Reference Lane

### Purpose

The Apple M5-based macOS 26.4 machine is the canonical behavior reference for
native `libdispatch`.

It should be used to answer questions like:

1. how aggressively does canonical `libdispatch` request workers here?
2. when does the native implementation narrow?
3. how does blocked-worker expansion behave?
4. how different is FreeBSD under the same workload?

### What the macOS lane should run

The macOS clone of this repo should run:

1. the Elixir harness;
2. the same userland workload definitions where possible;
3. comparison-only tests that make sense on a Darwin host;
4. optionally Zig microbenchmarks when they are userland-only and portable.

The macOS lane should not be expected to run FreeBSD kernel probes.

### Comparison policy

When the same workload runs on FreeBSD and macOS, classify the result as:

1. comparable;
2. acceptable divergence;
3. concerning divergence.

Use the following interpretation:

1. comparable means behavior is directionally aligned and feature quality looks
   healthy;
2. acceptable divergence means FreeBSD differs, but the difference is natural
   and not obviously harmful;
3. concerning divergence means FreeBSD behavior suggests a missing feature,
   unstable policy, or poor regression.

Reason:

This keeps the project aligned with canonical behavior without turning the
comparison into a rigid compatibility trap.

Operational note:

The macOS lane does not need to be fully automated from day one. When
canonical comparison runs are needed, the repo can be moved or cloned onto the
Apple Silicon machine intentionally.

## No-Shell-Assertion Rule

The project should adopt a hard rule:

1. shell may launch things;
2. shell may collect raw files;
3. shell may not be the main place where correctness is decided.

Bad pattern:

1. launch workload;
2. `grep` log text;
3. infer pass/fail from a string.

Good pattern:

1. launch workload;
2. collect JSON counters, trace summaries, and benchmark results;
3. let Elixir or Zig assert on the structured data.

## Fallback Detection Requirements

Because silent fallback is such a large risk, the test framework must make it
easy to prove that the real workqueue path is in use.

The combined Elixir and Zig stack should support:

1. checking that the relevant symbols and initialization path are present;
2. tracing workqueue syscalls during workload execution;
3. reading kernel stats after the workload;
4. proving non-zero request and narrow activity where appropriate.

This should become a reusable assertion helper, not a one-off manual step.

## Performance Regression Policy

### Functional regressions

Functional regressions are hard failures.

Examples:

1. wrong error codes;
2. missing cleanup;
3. fallback path being used silently;
4. narrowing never triggering when it clearly should.

### Performance regressions

Performance regressions should be tracked in two ways:

1. FreeBSD versus its own previous baselines;
2. FreeBSD versus canonical macOS behavior for comparable workloads.

Policy:

1. FreeBSD self-regressions are hard failures once the baseline is stable;
2. macOS differences are review triggers, not automatic failures, unless the
   behavior clearly indicates a broken or missing feature.
3. early in the project, "beats the compatibility story and stays stable" is a
   sufficient performance bar;
4. later in the project, the baseline should be tightened with captured data.

Reason:

This is the right balance between honesty and practicality.

## Suggested Baseline Artifacts

The framework should be able to capture:

1. kernel identifier and `/usr/src` revision;
2. ports snapshot identifiers for Elixir and Zig if relevant;
3. VM image identifier;
4. workload definition identifier;
5. FreeBSD counters before and after the workload;
6. benchmark result sets;
7. macOS comparison results where available.

These should be written as structured artifacts in ignored output directories.

## Adoption Plan

### Stage 1: Framework skeleton

Build:

1. Elixir `Mix` project;
2. Zig `build.zig`;
3. shell wrappers for `bhyve` and image updates;
4. result schema.

Exit criteria:

1. the harness can boot a guest;
2. the harness can run a guest command;
3. a Zig helper binary can run and report JSON;
4. ExUnit can assert on the result.

### Stage 2: Kernel API feature coverage

Build:

1. Elixir feature tests for syscall semantics;
2. Zig syscall probe binaries;
3. structured stats capture.

Exit criteria:

1. init, request, return, and narrow are all testable through the framework;
2. fallback detection helpers exist;
3. the suite runs repeatably in the guest.

### Stage 3: Dispatch and Swift coverage

Build:

1. reusable workload definitions;
2. dispatch and Swift scenario runners;
3. comparison reporting.

Exit criteria:

1. FreeBSD guest runs the workload set;
2. macOS reference host runs the comparable workload set;
3. differences are surfaced as structured reports.

### Stage 4: Performance discipline

Build:

1. Zig microbench lane;
2. Elixir baseline comparison logic;
3. stable threshold policy.

Exit criteria:

1. thread and narrow regressions are visible immediately;
2. performance discussions can use captured data, not impressions.

## Immediate Recommendations

1. keep the main implementation plan and this testing plan separate;
2. make Elixir the first-class harness before kernel work gets too far ahead of
   observability;
3. create the Zig helper and benchmark layer early, not after the feature is
   "done";
4. never let shell become the place where important workqueue behavior is
   asserted;
5. wire the Apple Silicon macOS clone into the same workload definitions as
   soon as the repo remote exists.

## Bottom Line

The testing strategy should be opinionated:

1. Elixir is the primary framework.
2. Zig is the precision and performance layer.
3. Shell is only glue.
4. FreeBSD `bhyve` guests are the main engineering target.
5. Apple Silicon macOS is the canonical behavior reference.

If we do this early, the project will have a testing stack strong enough to
catch semantic breakage, prevent silent fallback, and keep performance claims
honest.
