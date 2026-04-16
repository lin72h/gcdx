# ADL 12900K UINTR Experiment Plan

Date: `2026-04-15`

## Purpose

This document defines a concrete experiment plan for an Alder Lake
`Core i9-12900K` system.

The plan is intentionally not optimistic.

It is designed to answer the hard gate first:

1. does this actual `12900K` system expose `UINTR` at runtime;
2. if not, can the same machine still be used as a high-value `WAITPKG`
   experiment box;
3. if yes, is `UINTR` still blocked by missing FreeBSD kernel/runtime support.

The plan must distinguish:

1. compiler support;
2. microarchitecture model assumptions;
3. actual CPUID exposure on this retail CPU;
4. actual OS enablement on this FreeBSD system.

## Why This Needs A Dedicated ADL Plan

The local corpus already shows the key ambiguity:

1. the Clang/LLVM toolchain exposes `uintr` intrinsics and `waitpkg`
   intrinsics;
2. Linux mainline material in the corpus shows `WAITPKG` support and no
   obvious mainline `UINTR` kernel lane;
3. the local QEMU snapshot shows `waitpkg` and `fred`, but no obvious
   `uintr` feature;
4. the local LLVM target parser does **not** place `FeatureUINTR` in
   `FeaturesAlderlake`, but it does place `FeatureWAITPKG` there.

That last point matters.

In the local source at
`/usr/src/contrib/llvm-project/llvm/lib/TargetParser/X86TargetParser.cpp`,
`FeaturesAlderlake` includes:

1. `FeatureWAITPKG`

but it does **not** include:

1. `FeatureUINTR`

while later feature sets do add `FeatureUINTR`.

So the compiler model already points away from `ADL` being a natural `UINTR`
platform.

That makes the correct first step a falsification plan, not an implementation
plan.

## Executive Verdict

The most likely useful outcomes on a `12900K` are:

1. prove that `UINTR` is absent at the CPUID level and stop there;
2. or prove that `UINTR` is present in CPUID but unusable under current
   FreeBSD because the kernel/runtime contract is missing;
3. in either case, reuse the same box as a stronger `WAITPKG` experiment lane.

The honest current expectation is that `UINTR` is blocked unless a new kernel
contract appears. The plan exists to prove that cleanly, not to assume that
ADL is a hidden shortcut to deployable `UINTR`.

The least likely outcome is:

1. "ADL gives us a practical production UINTR path for GCDX right now."

This plan therefore uses early stop gates and a clean fallback path.

## Questions The Plan Must Answer

1. Does the actual `12900K` expose `waitpkg` in `CPUID.(EAX=7,ECX=0):ECX[5]`?
2. Does the actual `12900K` expose `uintr` in `CPUID.(EAX=7,ECX=0):EDX[5]`?
3. Are those bits identical across all logical CPUs, or do P-cores and E-cores
   differ?
4. What does `IA32_UMWAIT_CONTROL` (`MSR 0xE1`) contain on this FreeBSD host?
5. If `uintr` is exposed, what is the actual user-space failure mode under
   current FreeBSD:
   `SIGILL`, `SIGSEGV`, or some other trap path?
6. Can the same machine be used for a bounded `WAITPKG` pre-park experiment
   even if `UINTR` is unavailable?

## Non-Goals

This plan does **not** attempt to:

1. add full FreeBSD kernel `UINTR` support;
2. retrofit `GCDX` to depend on `UINTR`;
3. move worker idle semantics out of `TWQ` visibility;
4. treat `WAITPKG` as a replacement for kernel-visible parking;
5. branch the product roadmap around speculative ISA work.

## Decision Gates

## Gate 0: Hardware Truth

This gate decides whether `ADL UINTR` is even real on the target box.

Pass criteria:

1. collect `CPUID` data from the actual `12900K`;
2. determine whether `uintr` is present or absent;
3. determine whether `waitpkg` is present or absent.

Stop conditions:

1. if `uintr` is absent on the real CPU, stop the `UINTR` lane immediately;
2. continue only with the `WAITPKG` side lane on the same host.

## Gate 1: OS Enablement Truth

This gate only runs if Gate 0 says `uintr` is present.

Pass criteria:

1. determine whether any `UINTR` instruction can execute meaningfully under the
   current FreeBSD kernel;
2. characterize the exact failure mode if it cannot.

Stop conditions:

1. if `UINTR` instructions trap because the kernel has not enabled the required
   state, stop the `UINTR` lane there and record the result as
   "hardware maybe present, OS path blocked."

## Gate 2: WAITPKG Reuse Lane

This gate is independent of `UINTR` success.

Pass criteria:

1. confirm `waitpkg` availability;
2. read and record `IA32_UMWAIT_CONTROL`;
3. run a bounded microbenchmark for short pre-park waits.

This is the high-probability productive output from the `12900K` box.

The reason this lane is worth keeping even if `UINTR` fails is that current
`M13` behavior already shows the right shape for a bounded `WAITPKG` check:
rapid empty-to-non-empty oscillations where workers can pay false-idle
transition cost before they really need a kernel-visible sleep.

## Experiment Sequence

## Phase A: Host Capability Audit

Use the actual ADL host, not a VM, for this phase.

Recommended commands:

```sh
doas kldload cpuctl || true
doas cpucontrol -i 0x7,0x0 /dev/cpuctl0
doas cpucontrol -m 0xe1 /dev/cpuctl0
```

Repeat the `CPUID` check across multiple logical CPUs, not just CPU 0.

Minimum capture set:

1. one logical CPU believed to be on a P-core;
2. one logical CPU believed to be on an E-core;
3. ideally all logical CPUs, because ADL is hybrid and feature asymmetry would
   matter more than a single-sample result.

Recommended audit script shape:

```sh
for dev in /dev/cpuctl*; do
  echo "== $dev =="
  doas cpucontrol -i 0x7,0x0 "$dev"
done
```

What to record:

1. `%ecx` from leaf `0x7,0x0`
2. `%edx` from leaf `0x7,0x0`
3. whether `ECX[5]` (`waitpkg`) is set
4. whether `EDX[5]` (`uintr`) is set

Expected interpretation:

1. `waitpkg` present, `uintr` absent:
   this is the most plausible useful ADL result;
2. both absent:
   the ADL box is not useful for either ISA lane;
3. both present:
   surprising and worth continuing to Gate 1;
4. `uintr` present on some CPUs and absent on others:
   this is effectively a blocker for any serious process-wide experiment.

## Phase B: Hybrid-Core Classification

Because the `12900K` is hybrid, do not assume all logical CPUs are equivalent.

Objectives:

1. map logical CPU ids to the two core classes well enough for experiment
   control;
2. pin later tests to a specific CPU set instead of allowing migration.

FreeBSD tooling to use:

1. `cpuset(1)` for process pinning
2. `/dev/cpuctlN` for per-CPU `CPUID` and `MSR` reads

Recommended rule:

1. if the capability bits differ between core classes, terminate the `UINTR`
   plan as a product-relevance lane;
2. continue only as a curiosity experiment if desired.

## Phase C: WAITPKG Control-State Audit

This phase runs if `waitpkg` is present.

Read:

```sh
doas cpucontrol -m 0xe1 /dev/cpuctl0
```

`0xe1` is `IA32_UMWAIT_CONTROL`.

This phase exists because the Linux corpus includes a real `umwait.c` path that
manages this MSR globally, while the current FreeBSD and local `GCDX` search
did not show an equivalent management path in the areas we care about.

Questions to answer:

1. what value did firmware leave in `IA32_UMWAIT_CONTROL`;
2. is the value identical across logical CPUs;
3. is there any reason to believe the value is unsuitable for bounded
   user-space experiments.

Stop conditions:

1. if the MSR cannot be read consistently or looks obviously unsuitable for
   bounded experiments, stop before writing any `WAITPKG` benchmark;
2. if later production use is considered, treat a minimal FreeBSD-side MSR
   initialization path as a prerequisite.

## Phase C.5: Optional bhyve WAITPKG Visibility Check

This phase is optional and only matters if the bare-metal `WAITPKG` lane looks
promising.

It exists to answer one practical question:

1. can the current guest environment even expose `waitpkg` honestly enough for
   a guest-side microbenchmark.

Checks:

1. verify `waitpkg` exposure inside the guest with a CPUID read or an explicit
   guest-visible record such as `/var/run/dmesg.boot`;
2. if the bit is not exposed in the guest, stop the guest-side `WAITPKG` lane
   immediately;
3. if the bit is exposed, treat guest timing as secondary evidence only, not as
   the canonical measurement source.

Reason:

1. virtual timer delivery can distort very short `_umwait` windows;
2. so the guest lane is useful for compatibility checks, but bare metal remains
   the authoritative measurement lane.

## Phase D: Compiler And Encoding Sanity

This phase proves what the compiler can emit on the ADL host.

Write two tiny programs:

1. `adl_waitpkg_probe.c`
2. `adl_uintr_probe.c`

Compile with explicit flags:

```sh
cc -O2 -mwaitpkg adl_waitpkg_probe.c -o adl_waitpkg_probe
cc -O2 -muintr adl_uintr_probe.c -o adl_uintr_probe
```

Disassemble:

```sh
objdump -d adl_waitpkg_probe | less
objdump -d adl_uintr_probe | less
```

Success criteria:

1. `WAITPKG` binary contains `umonitor` / `umwait` / `tpause` as intended;
2. `UINTR` binary contains `clui` / `stui` / `testui` / `senduipi` as
   intended.

This phase proves encoding, not runtime viability.

## Phase E: Guarded UINTR Runtime Probe

This phase runs only if Gate 0 shows `uintr` present.

The purpose is not to "make UINTR work."

The purpose is to measure the exact current failure mode under FreeBSD.

Safety rules:

1. run each probe in a short-lived child process;
2. install a `SIGILL` handler or at minimum inspect the child exit signal;
3. test one instruction at a time;
4. do **not** attempt kernel register patching or unsupported CR4 writes on the
   daily system.

Probe order:

1. `_testui()`
2. `_clui()`
3. `_stui()`
4. `_senduipi(0)`

Expected likely result:

1. trap path because the OS has not enabled the required machine state.

Useful outcomes:

1. `SIGILL` on every instruction:
   record as "hardware may expose bit, OS path blocked";
2. mixed behavior:
   record exactly, because that would be more interesting than expected.

Stop condition:

1. once the failure mode is characterized, stop the `UINTR` lane.

There is no value in forcing deeper product work until a real kernel setup path
exists.

## Phase F: WAITPKG Microbenchmark

This is the likely productive ADL lane.

The benchmark should model a bounded false-idle window, not a long sleep.

Candidate design:

1. producer and consumer share a cache-line-aligned generation word;
2. consumer spins briefly, then enters a bounded `_umonitor` / `_umwait`
   window;
3. producer writes the generation word at controlled offsets;
4. if the generation changes inside the short window, the consumer records a
   warm wake;
5. if not, the consumer falls through to the existing ordinary fallback path.

Compare:

1. pure spin plus fallback;
2. `_umwait` bounded pre-park plus same fallback;
3. existing baseline without ISA-specific wait.

Measure:

1. wake latency distribution;
2. CPU time burned by the waiter;
3. percentage of wakeups caught in the bounded pre-park window;
4. percentage of wakeups that still require the fallback path.

Critical constraint:

1. keep the `_umwait` window very short;
2. microseconds, not milliseconds;
3. this experiment is meant to reduce false-idle transition cost, not to hide
   real blocked time from the kernel;
4. if a later revision starts stretching `_umwait` toward real idle residency,
   that is the point where the experiment is competing with `TWQ` instead of
   accelerating it.

## Phase G: Optional GCDX-Specific Relevance Check

Only run this if the `WAITPKG` microbenchmark shows a real gain.

This phase is still not a product integration.

It is a relevance check against current `M13` behavior.

Question:

1. do the continuation-heavy lanes in `GCDX` spend enough time in short
   false-idle gaps that a bounded pre-park optimization could matter after the
   software churn is reduced?

This phase should use the current `M13` findings as the filter:

1. if `libdispatch` still generates too many transitions, fix that first;
2. only when the transition count is lower does it make sense to optimize the
   cost of each transition.

## Artifact Plan

Store all ADL experiment outputs outside the main repo tree if they are bulky.

Inside the repo, keep only:

1. the experiment plan
2. small probe sources
3. small scripts
4. summary results

Suggested artifact groups:

1. `cpuid/`
2. `msr/`
3. `disassembly/`
4. `uintr-runtime/`
5. `waitpkg-bench/`

Suggested file naming:

1. `adl12900k-cpuid-leaf7-allcpus.txt`
2. `adl12900k-umwait-msr.txt`
3. `adl12900k-uintr-runtime-probe.txt`
4. `adl12900k-waitpkg-benchmark.json`

## Success Criteria

This plan is successful if it produces one of these clean conclusions:

1. `ADL 12900K` does not expose `UINTR`; stop UINTR work and reuse the machine
   for `WAITPKG`;
2. `ADL 12900K` exposes `UINTR`, but current FreeBSD blocks practical use;
3. `ADL 12900K` exposes `WAITPKG`, the MSR state is understood, and a bounded
   microbenchmark can be run honestly;
4. the box is unsuitable for both lanes, and we stop cleanly without confusing
   compiler support with platform support.

## Failure Modes To Avoid

1. confusing `-muintr` compilation success with runtime availability;
2. trusting the compiler microarchitecture model instead of real CPUID on the
   actual retail CPU;
3. running long `_umwait` windows that compete with `TWQ` visibility;
4. ignoring hybrid-core asymmetry on `ADL`;
5. trying unsupported kernel-state hacks on the daily machine.

## Recommended Immediate First Commands

Run these first on the ADL host:

```sh
doas kldload cpuctl || true
for dev in /dev/cpuctl*; do
  echo "== $dev =="
  doas cpucontrol -i 0x7,0x0 "$dev"
done
doas cpucontrol -m 0xe1 /dev/cpuctl0
```

Interpret them before writing any runtime probe.

That keeps the plan honest:

1. hardware truth first;
2. OS truth second;
3. microbench only after both are understood.

## Bottom Line

On a `12900K`, the right ADL `UINTR` plan is mostly a decision plan:

1. prove whether `UINTR` is even there;
2. if it is not, stop immediately;
3. if it is there but FreeBSD blocks it, record that boundary precisely;
4. use the same machine to run the more realistic `WAITPKG` lane.

That is the highest-value path for this hardware and this project.
