# GCDX ROADMAP

## Purpose

This roadmap turns the strategy documents into an execution map.

Project name:

1. this repo's implementation effort is named `GCDX`.

It is intentionally milestone-heavy. The goal is to make progress legible,
stage work in a sane order, and keep the project honest about what is actually
done versus what is still conceptual.

This roadmap is guided by the current project intent:

1. deliver real kernel-backed `libdispatch` semantics, not just a compatibility
   story;
2. prefer the most natural FreeBSD design that preserves the important macOS
   semantics;
3. optimize for upstream-quality engineering even if upstream acceptance is not
   assumed;
4. prioritize semantics and stability first, then close the performance gap
   over time.

## Status Legend

- `done`: already completed in this repo
- `next`: highest-value upcoming work
- `planned`: should happen in normal sequence
- `later`: intentionally deferred

## Current State

- `done` Git repo initialized in this directory
- `done` main implementation plan exists
- `done` testing strategy exists
- `done` local FreeBSD 15 `stable/15` source tree identified at `/usr/src`
- `done` local ports tree identified at `/usr/ports`
- `done` local donor and reference trees identified under `../nx/`
- `done` Elixir harness skeleton verified with ExUnit
- `done` Zig scaffold verified locally and reachable from the Elixir harness
- `done` detailed donor hook map written against `/usr/src`
- `done` minimal `/usr/src` `THRWORKQ` scaffold landed and compile-validated in
  a `TWQDEBUG` kernel objdir
- `done` `TWQDEBUG` kernel linked successfully from the configured objdir
- `done` raw Zig syscall probe now distinguishes stock-kernel `SIGSYS`
- `done` first proc/thread lifecycle anchors for `pthread_workqueue` landed in
  `/usr/src`
- `done` scripted guest staging now installs `TWQDEBUG` into an alternate
  kernel slot and preserves the stock module tree
- `done` `bhyve` guest boot was validated end-to-end with the custom kernel
- `done` guest-side raw syscall probe now returns `ENOTSUP` for supported stub
  ops and `EINVAL` for invalid ops under `TWQDEBUG`
- `done` Elixir can stage, boot, capture serial output, and assert on the VM
  probe path through a gated integration test
- `done` custom `libthr.so.3` can now be linked outside this repo and staged
  into the guest without carrying a custom `libsys.so.7`
- `done` first guest-side userland pthread_workqueue probe now passes through
  the custom `libthr` bridge and observes real callbacks under `TWQDEBUG`
- `done` local `swift-corelibs-libdispatch` now builds against the staged
  custom `libthr`
- `done` a dedicated guest-side dispatch probe now runs through staged
  `libdispatch.so` and `libBlocksRuntime.so`
- `done` the VM harness now captures pre/post-dispatch `kern.twq.*` snapshots
  and asserts that dispatch increases real TWQ counters
- `done` the guest dispatch lane now covers both a basic workload and a
  pressure workload that reduces default concurrency under TWQ feedback
- `done` kernel and `libthr` feature-bit reporting now agree on
  `DISPATCHFUNC | FINEPRIO | MAINTENANCE` (`19`)
- `done` idle `libthr` TWQ workers now use a wait-sequence wake path with a
  background reaper to retire excess idle workers after inactivity
- `done` the VM harness now reports named validation failures instead of a
  single opaque pass/fail result
- `done` the local Apple `libdispatch` tree now configures against the staged
  pthread surface on FreeBSD
- `done` local Apple-tree exploration pushed past the first workgroup and Mach
  header failures
- `done` the current local Apple-tree build boundary is broader
  Darwin-private QoS, lock, voucher, and Swift-concurrency runtime surface,
  not `pthread_workqueue` semantics
- `done` phase-1 direction is now explicit: use the Apple tree as a source
  reference and native macOS as the future behavior lane, not as the immediate
  local build target on FreeBSD
- `done` sustained dispatch lifecycle probes now cover both burst-reuse and
  longer mixed-priority runs in the guest
- `done` short-burst worker churn is now eliminated by a bounded warm-worker
  policy in `libthr`
- `done` phase 1 now explicitly accepts a bounded warm pool instead of
  requiring full in-process retirement to zero after every lull
- `done` the VM harness now validates burst-reuse and sustained-lifecycle
  behavior in addition to the earlier basic and pressure probes
- `done` `libthr` now uses a background reaper plus a wait-sequence wake path
  to trim excess idle workers back to the warm floor after inactivity
- `done` the direct no-dispatch workqueue timeout probe now proves that an
  overcommit burst retires from `8` idle workers back to the `4`-thread warm
  floor after `8s`
- `done` the dispatch timeout-gap probe now proves that a gap longer than the
  idle timeout still reuses the same warm worker set instead of recreating it
- `done` `scripts/libthr/prepare-stage.sh` now auto-refreshes the manual
  `libthr` artifact when newer `libthr` objdir outputs are present
- `done` a guest-side Swift async smoke probe now proves that the staged
  Swift 6.3 runtime can start an `async` entrypoint under `TWQDEBUG`
- `done` a guest-side Swift Dispatch control probe now proves that Swift's
  `Dispatch` import drives real `kern.twq.*` deltas under the staged runtime
- `done` the first guest-side Swift `TaskGroup` probe now proves that
  structured Swift concurrency reaches the TWQ-backed path, because
  `init_count`, `setup_dispatch_count`, `reqthreads_count`, and
  `thread_enter_count` all increase during the attempt
- `done` the same `TaskGroup` probe currently times out under a suspended
  `Task.sleep` workload, which is now the concrete M12 boundary rather than a
  vague unknown
- `done` the staged Swift guest lane now emits explicit timeout/error JSON for
  Swift probes instead of hanging the whole integration run
- `done` the canonical local host Swift 6.3 toolchain is now documented in
  `freebsd-swift63-toolchain-reference.md`
- `done` host-side verification now shows that the stock local Swift 6.3
  toolchain completes all current probe entry shapes successfully
- `done` the current Swift guest boundary is now characterized as a
  context-sensitive staged-stack issue, not a generic Swift or generic TWQ
  failure
- `done` the VM harness now records the active Swift probe profile and the set
  of Swift timeout modes seen during a guest run
- `done` the guest lane now supports `TWQ_SWIFT_PROBE_FILTER` for focused
  Swift isolation runs without changing the stable validation gate
- `done` Swift probe parsing now resolves each mode from the final matching
  event instead of the first progress event
- `done` the guest now has a stable Swift `validation` profile with a passing
  gated VM integration lane:
  `async-smoke`, `dispatch-control`, and `mainqueue-resume`
- `done` `dispatchMain()` and `TaskGroup`-shaped Swift probes are now tracked
  as diagnostics instead of being overstated as required validation
- `done` focused guest isolation now shows that under `dispatchMain()` the
  following all complete repeatably:
  `dispatchmain-spawn`, `dispatchmain-yield`,
  `dispatchmain-continuation`, `dispatchmain-sleep`, and
  `dispatchmain-taskgroup`
- `done` spawned child suspension under `dispatchMain()` now has direct guest
  proof too: both `dispatchmain-spawned-yield` and
  `dispatchmain-spawned-sleep` complete on the staged stack
- `done` focused guest isolation now shows the remaining staged Swift failure
  is no longer generic `dispatchMain()` and no longer a generic
  `TaskGroup` suspension issue
- `done` runtime-matrix guest runs now show `dispatchmain-taskgroup-yield`
  completes in all three tested runtime combinations:
  stock-dispatch plus stock `libthr`, stock-dispatch plus custom `libthr`,
  and the full staged TWQ lane
- `done` `dispatchmain-taskgroup-sleep` times out on the full staged TWQ lane
  but completes on both stock-dispatch combinations, which rules out custom
  `libthr` as the current blocker
- `done` `dispatchmain-spawnwait-sleep` now shows the same split:
  timeout on the full staged TWQ lane, success on stock-dispatch
- `done` the current staged Swift boundary is therefore narrowed to custom
  `libdispatch` / TWQ handling of `Task.sleep`-driven resumption rather than
  generic Swift `TaskGroup` child suspension
- `done` later `dispatch_after`-based Swift controls now show
  `dispatchmain-spawnwait-after` succeeding on the full staged TWQ lane while
  `dispatchmain-taskgroup-after` still times out there
- `done` the same `dispatchmain-taskgroup-after` binary succeeds on both
  stock-dispatch guest controls, including stock-dispatch plus custom
  `libthr`, so the current blocker is still not custom `libthr`
- `done` the current staged Swift boundary is now narrower than
  `Task.sleep` specifically: it is delayed `TaskGroup` child completion on the
  staged custom `libdispatch` lane
- `done` the C dispatch lane now has an `executor-after-settled` control and
  one prior `executor-after` timeout has identified delayed work on
  executor-style queues as the strongest current non-Swift implementation lead
- `done` host-side symbol inspection now shows the stock Swift 6.3
  `libdispatch.so` does not reference `_pthread_workqueue_*` while the staged
  custom `libdispatch.so` does
- `done` the stock-dispatch plus custom-`libthr` delayed-child Swift control
  now has zero `kern.twq.reqthreads_count` and `kern.twq.thread_enter_count`
  deltas across the probe window, so it is a runtime control lane rather than
  a TWQ-backed control lane
- `done` real Swift/TWQ validation must therefore continue to use the staged
  custom `libdispatch` lane; the stock Swift 6.3 dispatch lane is only a
  comparison lane
- `done` a new pure-C `worker-after-group` dispatch probe now proves that a
  dispatch worker can schedule delayed children and wait for them
  successfully on the staged TWQ lane
- `done` a new Swift `dispatchmain-taskhandles-after` probe now shows the same
  timeout shape as `dispatchmain-taskgroup-after` on the staged TWQ lane while
  passing on the stock host Swift 6.3 lane
- `done` the remaining staged Swift boundary is therefore narrower than
  generic delayed dispatch callbacks and broader than `TaskGroup` alone: it is
  multiple delayed Swift child-task resumptions awaited by a parent async
  context on the staged custom-`libdispatch` lane
- `done` host-side reproduction confirmed that staged Swift binaries cannot be
  run meaningfully on the stock host kernel because the staged `libdispatch`
  intentionally traps on syscall `468`; Swift diagnosis must stay in the guest
  lane
- `done` the project now has an explicit parity estimate against native macOS
  `libdispatch`:
  roughly `70-80%` for the real kernel-backed workqueue behavior that matters
  most here, and roughly `45-55%` for broader native-macOS `libdispatch`
  parity overall
- `done` the real root cause of the staged delayed-child Swift failure is now
  identified as kernel-side `TWQ` accounting that collapsed constrained and
  overcommit workers into the same QoS bucket
- `done` internal kernel `TWQ` accounting is now split by lane
  (`QoS x {constrained, overcommit}`) while the public sysctl surface remains
  bucket-aggregated
- `done` `dispatchmain-taskhandles-after`,
  `dispatchmain-taskhandles-after-repeat-hooks`,
  `dispatchmain-taskgroup-after`, and `dispatchmain-taskgroup-sleep` now all
  complete on the full staged TWQ lane
- `done` the staged Swift `full` profile now completes end-to-end in the guest
  after the kernel lane split; only the already-known invalid
  `customdispatch + stock libthr` control lanes still emit `rc=1` errors
- `done` the focused repeat-only benchmark lane now emits round-boundary
  libdispatch root snapshots in addition to the earlier per-round `kern.twq.*`
  counters, and the structured benchmark JSON is now schema version `3`
- `done` the Zig hot-path lane now has a default one-boot suite runner and a
  drift-tolerant comparator against the checked-in M13 syscall baseline
- `done` ExUnit now normalizes and compares Zig hot-path artifacts through
  `TwqTest.ZigHotpath`, and the suite-native M13 baseline is checked in
- `done` the normal Zig hot-path regression command is now a single gate
  wrapper: run the suite, extract JSON, compare against baseline
- `done` the default Zig hot-path gate now covers six syscall modes:
  `should-narrow`, constrained `reqthreads`, overcommit `reqthreads`,
  `thread-enter`, `thread-return`, and `thread-transfer`
- `done` the lifecycle hot-path baseline proves balanced enter/return cleanup
  around measured worker enter, return, and cross-lane transfer syscalls
- `done` M13 now also has a one-boot workqueue wake benchmark gate for warmed
  idle workers in both constrained and overcommit modes, with a checked-in
  suite baseline and exact lifecycle counter gating
- `done` the warmed-worker wake lane is now exposed through a repo-owned
  Elixir wrapper (`TwqTest.Workqueue`) in addition to the shell benchmark
  scripts
- `done` the full M13 low-level performance floor can now be rerun under one
  top-level command via `scripts/benchmarks/run-m13-lowlevel-gate.sh`
- `done` the top-level M13 low-level gate is now a one-boot suite-native gate
  backed by a combined baseline artifact instead of two separate guest boots
- `done` the combined M13 low-level artifact is now visible to ExUnit through
  `TwqTest.LowlevelBench`
- `done` the M14 FreeBSD repeat reference is now checked into the repo as
  `benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json`
- `done` the FreeBSD schema-`3` repeat reference is now protected by a
  repo-owned focused gate via `scripts/benchmarks/run-m13-repeat-gate.sh`
- `done` M14 now has a repo-owned runnable steady-state comparison lane via
  `scripts/benchmarks/run-m14-comparison.sh`, with structured comparison JSON
  from `compare-m14-steady-state.py`
- `done` the checked-in M14 stop/tune decision is now visible to ExUnit
  through `TwqTest.M14Comparison`
- `done` focused repeat-lane guest runs now propagate libdispatch counter
  enablement correctly through `TWQ_LIBDISPATCH_COUNTERS`, so generated repeat
  artifacts carry libdispatch round snapshots instead of only TWQ deltas
- `done` the broad post-M13 rerun now has a checked-in full-matrix crossover
  baseline at `benchmarks/baselines/m13-crossover-full-20260417.json`
- `done` the broad post-M13 closeout lane is now repo-owned through
  `scripts/benchmarks/run-m13-crossover-assessment.sh` and is visible to
  ExUnit through `TwqTest.VM.run_m13_crossover_assessment/1`
- `done` the first `M13.5` full-matrix rerun exposed and cleared a real staged
  `libdispatch` correctness bug:
  unsafe root-item type inspection on raw continuations in the local staged
  `swift-corelibs-libdispatch` checkout
- `done` the current `M13.5` boundary is now explicit in
  `m13-5-crossover-boundary.md`:
  stable floor, frozen seams, deferred work, and the exit rule for closing
  `M13`
- `done` formal `M13` closeout is now a repo-owned top-level lane through
  `scripts/benchmarks/run-m13-closeout.sh`, which aggregates the low-level
  floor, the focused repeat gate, and the `M13.5` crossover assessment into
  one machine-readable verdict
- `done` the low-level gate is now composable in the same way as the repeat
  and crossover lanes:
  it accepts a prebuilt candidate JSON and emits structured comparison JSON
- `done` the top-level `M13` closeout decision is now visible to ExUnit
  through `TwqTest.VM.run_m13_closeout/1`
- `done` the post-`M13` pressure-provider prep lane is now repo-owned through
  `scripts/benchmarks/run-m15-pressure-provider-prep.sh`
- `done` the first checked-in pressure-only provider baseline is now derived
  from the checked-in full-matrix crossover artifact at
  `benchmarks/baselines/m15-pressure-provider-20260417.json`
- `done` the current derived pressure-provider boundary is now explicit in
  `m15-pressure-provider-prep.md` and visible to ExUnit through
  `TwqTest.PressureProvider` plus `TwqTest.VM.run_m15_pressure_provider_prep/1`
- `done` the first guest-side live pressure-provider smoke lane now exists
  through `scripts/benchmarks/run-m15-live-pressure-provider-smoke.sh`
- `done` the live pressure smoke lane now stages a dedicated in-guest probe for
  `dispatch.pressure` and `dispatch.sustained`, with real generation numbers
  and real monotonic timestamps
- `done` the first checked-in live pressure baseline now lives at
  `benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json`
- `done` the live pressure smoke boundary is now explicit in
  `m15-live-pressure-provider-smoke.md` and visible to ExUnit through
  `TwqTest.LivePressureProvider` plus
  `TwqTest.VM.run_m15_live_pressure_provider_smoke/1`
- `done` the pressure-only provider boundary now treats
  `nonidle_workers_current = total_workers_current - idle_workers_current` as
  the effective live current-pressure signal while retaining raw
  `active_workers_current` only as supporting detail
- `done` the pressure-only provider boundary is now also machine-readable
  through `benchmarks/contracts/m15-pressure-provider-contract-v1.json`, with
  repo-owned contract validation for the derived, live, adapter, and preview
  artifact families
- `done` an aggregate adapter smoke lane now exists through
  `scripts/benchmarks/run-m15-pressure-provider-adapter-smoke.sh`, with a
  checked-in aggregate adapter baseline at
  `benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json`
- `done` the aggregate adapter boundary is now explicit in
  `m15-pressure-provider-adapter-smoke.md` and visible to ExUnit through
  `TwqTest.PressureProviderAdapter` plus
  `TwqTest.VM.run_m15_pressure_provider_adapter_smoke/1`
- `done` a policyless observer smoke lane now exists through
  `scripts/benchmarks/run-m15-pressure-provider-observer-smoke.sh`, with a
  checked-in observer baseline at
  `benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json`
- `done` the observer boundary is now explicit in
  `m15-pressure-provider-observer-smoke.md` and visible to ExUnit through
  `TwqTest.PressureProviderObserver` plus
  `TwqTest.VM.run_m15_pressure_provider_observer_smoke/1`
- `done` a raw preview smoke lane now exists through
  `scripts/benchmarks/run-m15-pressure-provider-preview-smoke.sh`, with a
  checked-in raw snapshot baseline at
  `benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json`
- `done` the raw preview boundary is now explicit in
  `m15-pressure-provider-preview-smoke.md` and visible to ExUnit through
  `TwqTest.PressureProviderPreview` plus
  `TwqTest.VM.run_m15_pressure_provider_preview_smoke/1`

## Current Gap Versus Native macOS

Honest estimate:

1. For the part this project cares about most, real kernel-backed dispatch
   behavior under a `pthread_workqueue`-style path, the port is roughly
   `70-80%` of the way to native macOS.
2. For broader native-macOS `libdispatch` parity overall, the port is closer
   to `45-55%`.

Why the first number is already fairly high:

1. a real kernel `TWQ` path exists in `/usr/src`;
2. real backpressure from kernel workqueue state into dispatch is proven in
   the guest;
3. QoS-aware admission and narrowing exist;
4. the `libthr` workqueue bridge is real;
5. staged `libdispatch` runs on that path;
6. Swift is already a meaningful validation lane, not just a synthetic demo.

Important caveat:

1. that `70-80%` reading is a mechanism-coverage estimate for the
   kernel-backed workqueue path;
2. it is still not a claim that broader macOS parity is close, even though the
   current staged Swift validation matrix is now green.

Why the second number is still much lower:

1. no direct kevent-workqueue delivery exists yet;
2. no workloop support exists yet;
3. no cooperative-pool semantics exist yet;
4. worker lifecycle is not kernel-owned the way it is on macOS;
5. no turnstile-style priority inheritance exists for this path;
6. only one completed macOS-side comparison exists so far, and it covers the
   repeat-lane main-queue handoff seam rather than the full dispatch surface;
7. the current full staged Swift profile still drives high `reqthreads`,
   `thread_enter`, and `thread_return` churn, so efficiency work remains
   meaningfully behind macOS even though correctness is much better.

Current project-health reading:

1. there is no major correctness blocker at the moment;
2. there is no active kernel bring-up blocker at the moment;
3. the staged stack now has a completed macOS comparison result for the
   main-queue to default-overcommit repeat-lane seam;
4. that seam is now judged native-shaped enough to stop tuning on FreeBSD;
5. the remaining gaps are broader efficiency and platform gaps, not a live
   correctness or seam-interpretation blocker.

Working interpretation:

1. For "this is a real workqueue-backed dispatch system, not a shim", the
   project is already quite close.
2. For "this is broadly comparable to native macOS `libdispatch` as a whole",
   the project is not close enough yet and still has meaningful platform and
   semantic gaps to close.

## Milestone Index

| ID | Status | Milestone | Main Outcome |
| --- | --- | --- | --- |
| M00 | done | Repo and planning baseline | Working repo with core design docs |
| M01 | done | Source baseline and donor map | File-by-file map from donor trees into `/usr/src` |
| M02 | done | VM and image pipeline | Repeatable `bhyve` workflow with crash capture |
| M03 | done | Test harness skeleton | Elixir + Zig framework ready before deep kernel work |
| M04 | done | Kernel scaffold import | `THRWORKQ`-gated kernel builds and boots |
| M05 | done | Proc/thread hook rebase | Workqueue lifecycle hooks wired into FreeBSD 15 |
| M06 | done | New kernel ABI and state layout | FreeBSD-private `TWQ_OP_*` contract and core structs |
| M07 | done | Scheduler feedback and admission core | Real block/yield feedback and narrowing logic |
| M08 | done | Kernel observability and smoke tests | Counters, sysctls, and syscall validation |
| M09 | done | `libthr` / `libpthread` bridge | Modern SPI exposed to userland |
| M10 | done | FreeBSD dispatch bring-up | Real workqueue path active under dispatch |
| M11 | planned | Apple behavior reference lane | Apple `libdispatch` semantics compared against the port |
| M11.5 | done | Sustained workload validation | Worker lifecycle and bounded warm-pool behavior hold under longer-running dispatch loads |
| M11.6 | done | Timeout-isolation validation | Idle retirement and long-gap reuse are both proven independently of short-burst dispatch behavior |
| M12 | done | Swift delayed-resume correctness closure | Kernel lane-split accounting closes the staged delayed-child Swift boundary and the full staged Swift profile now completes |
| M13 | done | Performance and regression discipline | Benchmarks, DTrace tooling, safe counters, and comparison-ready baselines |
| M14 | done | Canonical macOS comparison lane | Structured FreeBSD-vs-macOS comparison now shows the repeat-lane handoff seam is close enough to native macOS to stop tuning it |
| M14.5 | done | Pressure-provider prep lanes | Derived, live-smoke, adapter-smoke, observer-smoke, and raw-preview pressure-only prep surfaces now exist without claiming a live SPI |
| M15 | later | Optional deep integration | Scheduler refinement and possible kevent/workloop decisions |

## Milestone Details

## M00: Repo and Planning Baseline

Status: `done`

Goal:

1. start from a clean repo;
2. write down the implementation and testing strategy;
3. avoid hidden assumptions before code work begins.

Completed outcomes:

1. Git repository initialized;
2. `.gitignore` created;
3. implementation plan written;
4. testing strategy written.

This milestone is complete enough to support real execution work.

## M01: Source Baseline and Donor Map

Status: `done`

Goal:

1. turn the high-level donor story into a precise file map against `/usr/src`;
2. identify every hook that must move, not just the obvious new files;
3. freeze the first real implementation target revision of `stable/15`.

Completed outcomes:

1. donor and reference trees were audited against the real `/usr/src` target;
2. the first kernel edit surface was mapped explicitly in
   `freebsd15-donor-hook-map.md`;
3. current FreeBSD 15 lifecycle hook anchors were confirmed in:
   `proc.h`, `kern_synch.c`, `kern_exec.c`, `kern_exit.c`,
   `syscalls.master`, `sys/conf/files`, and `sys/conf/options`;
4. donor assumptions that no longer hold were identified, including:
   - no existing `mi_switch()` callback hook;
   - no `td_reuse_stack`;
   - no need to keep the old queue-item ABI;
5. the main unavoidable scheduler-facing delta was isolated to a minimal
   callback branch around `mi_switch()`.

Exit criteria:

1. every donor touchpoint has a target location in `/usr/src`;
2. each touchpoint is classified as reusable, mechanical rebase, or redesign;
3. there is no remaining ambiguity about the first kernel edit set.

Why it matters:

If this milestone is weak, every later milestone becomes guesswork.

Result:

This milestone is now complete enough to start the first real kernel scaffold.

## M02: VM and Image Pipeline

Status: `done`

Goal:

1. make kernel iteration cheap and reproducible;
2. avoid host reboots entirely for development;
3. guarantee panic and dump capture before risky kernel work starts.

Work:

1. define base-image and run-image locations outside this repo;
2. create thin scripts for image refresh, kernel replacement, guest boot, and
   dump collection;
3. configure serial-first logging;
4. preserve matching `kernel.debug` artifacts;
5. verify that a panic or failed boot leaves usable evidence.

Exit criteria:

1. a clean `bhyve` guest boots from a scripted flow;
2. kernel-only replacement works on an existing run image;
3. crash output and dumps are collectable;
4. the workflow can be rerun without manual cleanup.

Why it matters:

Kernel workqueue bugs are exactly the kind of bugs that punish manual VM
workflows.

Completed outcomes:

1. a FreeBSD 15 raw image is staged outside the repo under `../vm/`;
2. `stage-guest.sh` installs the custom kernel into `/boot/TWQDEBUG` using
   `INSTKERNNAME=TWQDEBUG` and `NO_MODULES=yes`;
3. the guest keeps the stock `/boot/kernel` module tree, while loader is
   redirected with:
   `kernel="TWQDEBUG"` and
   `module_path="/boot/kernel;/boot/modules;/boot/TWQDEBUG"`;
4. `run-guest.sh` boots the image through `bhyveload` and `bhyve`;
5. serial output can be captured to a host log file;
6. the workflow was validated by booting the guest, running the probe inside
   the VM, and powering the guest off cleanly;
7. the staging cleanup path now normalizes the guest mountpoint and detaches
   the raw image cleanly after use.

## M03: Test Harness Skeleton

Status: `done`

Goal:

1. stand up the test architecture before implementation outruns observability;
2. make Elixir the default test harness;
3. make Zig the low-level and performance test layer.

Completed outcomes:

1. Elixir `Mix` project skeleton created under `elixir/`;
2. Zig scaffold created under `zig/`;
3. structured JSON result schema defined;
4. host-side Elixir modules added for command execution, VM wrapper calls, and
   Zig integration;
5. thin `bhyve` wrapper scripts added under `scripts/bhyve/`;
6. ExUnit and Zig scaffolds verified locally;
7. Elixir now has a gated `probe_guest` path that stages the guest, boots the
   VM, captures the serial log, and asserts on the guest-side probe result.

Exit criteria:

1. ExUnit can drive a guest command and assert on structured output;
2. a Zig helper can be built and run through the harness;
3. shell remains only a thin orchestration layer.

Why it matters:

This is the point where the project commits to "no shell-first testing".

## M04: Kernel Scaffold Import

Status: `done`

Goal:

1. land the minimum kernel scaffold behind `THRWORKQ`;
2. prove the build and boot path before deeper behavioral logic.

Work:

1. import `kern_thrworkq.c`;
2. import `thrworkq.h` or its renamed equivalent;
3. wire `sys/conf/files`;
4. wire `sys/conf/options`;
5. make the kernel build with and without the option.

Completed so far:

1. added `sys/sys/thrworkq.h`;
2. added `sys/kern/kern_thrworkq.c` as a stub implementation;
3. added local syscall slot `468` as `twq_kernreturn`;
4. regenerated syscall outputs including:
   `init_sysent.c`, `syscalls.c`, `syscall.h`, `sysproto.h`,
   `lib/libsys/_libsys.h`, and `lib/libsys/syscalls.map`;
5. added `sys/amd64/conf/TWQDEBUG`;
6. compile-validated:
   `kern_thrworkq.o`, `init_sysent.o`, and `syscalls.o`
   in `/tmp/twqobj/usr/src/amd64.amd64/sys/TWQDEBUG`.
7. linked a full `TWQDEBUG` kernel from the objdir;
8. installed the custom kernel into a guest image and booted it in `bhyve`;
9. validated guest behavior for the scaffold ABI:
   `TWQ_OP_INIT` returns `ENOTSUP` and an unknown op returns `EINVAL`.

Important design note:

1. `kern_thrworkq.c` must currently be `standard`, not `optional thrworkq`.
   The syscall table is generated unconditionally, so the kernel always needs a
   real `sys_twq_kernreturn` symbol. The option gate therefore lives inside the
   implementation for now, returning `ENOSYS` when `THRWORKQ` is not enabled.

Exit criteria:

1. `THRWORKQ` kernels build;
2. `GENERIC` behavior remains intact;
3. the guest boots with the feature gate enabled.

Why it matters:

This creates the safe build boundary for later work.

## M05: Proc and Thread Hook Rebase

Status: `done`

Goal:

1. connect workqueue state to real process and thread lifecycle points;
2. get the minimum kernel hooks in place without yet solving full semantics.

Work:

1. add per-process workqueue state fields;
2. add per-thread workqueue metadata fields;
3. wire process init, exit, and `exec` cleanup;
4. wire thread creation and stack reuse hooks;
5. identify the correct FreeBSD 15 switch and wakeup hook points.

Completed outcomes:

1. added `p_twq` and `td_twq` as dedicated proc and thread anchors;
2. moved `p_twq` to the tail of `struct proc` after an earlier placement
   tripped FreeBSD 15 KBI offset assertions;
3. added `process_init` and `thread_init` eventhandler initialization hooks in
   `kern_thrworkq.c`;
4. wired cleanup hooks into `pre_execve()`, `exit1()`, and `kern_thr_exit()`;
5. made cleanup real:
   `twq_thread_exit()` now releases thread state, and process cleanup frees all
   thread-owned TWQ state before freeing the proc-owned state;
6. relinked and re-booted the guest successfully after the lifecycle cleanup
   became real.

Exit criteria:

1. process and thread state survive ordinary lifecycle events correctly;
2. no obvious leaks or stale references remain across exit and `exec`;
3. the hook set is stable enough for real scheduling behavior work.

Why it matters:

Without this, the rest of the subsystem is just detached code.

## M06: New Kernel ABI and State Layout

Status: `done`

Goal:

1. replace the old work-item-centric donor ABI with a thread-lifecycle ABI;
2. define the long-lived internal state model around requests and workers.

Work:

1. define the FreeBSD-private `TWQ_OP_*` command set;
2. define size-validated per-command argument structures;
3. define the per-process `thrworkq` state around request counts, worker lists,
   timestamps, counters, and stack recycling;
4. define the per-thread metadata model;
5. freeze the first internal 6-bucket QoS model and constrained versus
   overcommit categories.

Completed so far:

1. `thrworkq.h` now defines the typed ABI payloads for:
   `TWQ_OP_INIT`, `TWQ_OP_REQTHREADS`, `TWQ_OP_SHOULD_NARROW`, and dispatch
   setup, and the internal op set now includes `TWQ_OP_THREAD_ENTER` for
   worker-start visibility;
2. the first internal 6-bucket QoS model is present in the kernel-private
   header and state code;
3. `kern_thrworkq.c` now has real `twq_proc` and `twq_thread` state with
   per-bucket request, scheduled, total, and idle counters;
4. `TWQ_OP_INIT`, `TWQ_OP_THREAD_ENTER`, `TWQ_OP_SETUP_DISPATCH`,
   `TWQ_OP_REQTHREADS`, `TWQ_OP_THREAD_RETURN`, and `TWQ_OP_SHOULD_NARROW`
   now have stateful kernel behavior;
5. the VM probe was redesigned to run the syscall sequence inside one process,
   which fixed an earlier false-positive guest test;
6. guest validation now shows the expected same-process sequence:
   `INIT -> SETUP_DISPATCH -> REQTHREADS -> SHOULD_NARROW -> THREAD_RETURN ->
   SHOULD_NARROW -> REQTHREADS(0) -> SHOULD_NARROW -> invalid op`.

Exit criteria:

1. the kernel ABI is concrete and implementation-ready;
2. the old donor queue-item model is fully retired from the target design;
3. the state layout is precise enough to code against directly.

Why it matters:

This is the main architecture boundary between donor code and the final port.

## M07: Scheduler Feedback and Admission Core

Status: `done`

Goal:

1. implement the real value of the feature: kernel feedback;
2. make block, yield, request, return, and narrow decisions coherent.

Work:

1. add atomic-only switch-path callbacks;
2. implement active-worker accounting by QoS bucket;
3. implement blocked-worker timestamp tracking;
4. implement constrained admission logic;
5. implement `should_narrow` using the same admission model;
6. integrate yield feedback without creating thread explosions.

Completed so far:

1. `mi_switch()` now calls a TWQ-specific `twq_thread_switch()` hook when
   `td->td_twq` is present;
2. the hook is intentionally narrow and FreeBSD-native:
   it does not introduce a generic callback framework yet;
3. the switch-path logic is atomic-only and tracks real blocking reasons only
   (`sleepq`, `turnstile`, `iwait`, `suspend`);
4. the hook now exports observable cumulative block/unblock counts and bucket
   totals through `kern.twq.*`;
5. the Zig probe now includes a short blocking syscall after
   `TWQ_OP_THREAD_RETURN`, and the guest run proves one tracked block/unblock
   pair in the default bucket.
6. `TWQ_OP_REQTHREADS` and `TWQ_OP_SHOULD_NARROW` now recompute the bucket
   target from requested count, parallelism limit, and recent higher-priority
   busy pressure;
7. `TWQ_OP_THREAD_ENTER` now makes a worker visible to the kernel before it
   returns, which is the first ABI needed for a future `libthr` bridge to
   present honest active-worker state;
8. busy pressure is now based on non-idle counted workers rather than the
   earlier request-target proxy;
9. the guest lane now distinguishes two different cases cleanly:
   - an idle returned user-interactive worker no longer constrains a later
     default `REQTHREADS(4)`, which now returns `4`;
   - an actually entered and blocked user-interactive worker constrains the
     same default `REQTHREADS(4)` to `3`;
10. the kernel now exports current bucket totals, idle counts, and active
    counts, and the guest run proves they return to all-zero after probe
    process teardown.

Exit criteria:

1. scheduler hook logic does not deadlock;
2. constrained and overcommit behavior are visibly different;
3. `should_narrow` answers are meaningful under load;
4. short blocking windows do not cause runaway worker growth.

Why it matters:

If this milestone is wrong, the port loses the entire point of
`pthread_workqueue`.

## M08: Kernel Observability and Smoke Tests

Status: `done`

Goal:

1. make kernel behavior inspectable;
2. prove the new ABI works before involving dispatch.

Work:

1. add sysctls and counters;
2. write Elixir-driven syscall smoke tests;
3. add Zig syscall probe binaries;
4. validate duplicate init rejection, request handling, return behavior,
   narrow behavior, and lifecycle cleanup.

Completed outcomes:

1. `kern.twq.*` now exports useful cumulative counters and bucket totals from
   the kernel;
2. the Zig probe exercises the stateful syscall sequence in one process;
3. the `bhyve` guest script now prints both probe results and the exported
   kernel stats;
4. the VM integration test asserts on the syscall sequence and on the kernel
   counters after guest execution;
5. repeated guest runs now prove:
   init, setup, request handling, thread return, narrow behavior,
   invalid-op rejection, lifecycle cleanup, and one real switch-hook
   block/unblock pair.

Exit criteria:

1. kernel counters are readable and useful;
2. init, request, return, and narrow are testable through the harness;
3. kernel smoke tests run repeatably in the guest.

Why it matters:

This milestone is the line between "kernel code exists" and "kernel code is
observable and testable".

## M09: `libthr` / `libpthread` Bridge

Status: `done`

Goal:

1. expose the modern userland SPI expected by dispatch;
2. keep the Apple-shaped interface in userland while the kernel stays
   FreeBSD-private.

Work:

1. define the private header surface;
2. choose the correct `PTHREAD_WORKQUEUE_SPI_VERSION`;
3. expose mandatory feature bits, including maintenance support;
4. implement `_pthread_workqueue_init()`;
5. implement `_pthread_workqueue_supported()`;
6. implement `_pthread_workqueue_addthreads()`;
7. implement `_pthread_workqueue_should_narrow()`;
8. add worker trampoline paths and controlled stubs for unsupported kevent or
   workloop APIs if needed.

Completed outcomes so far:

1. source-tree userland headers now exist for:
   `pthread/workqueue_private.h` and `pthread_workqueue.h`;
2. `libthr` now exports the first usable SPI surface:
   `_pthread_workqueue_init()`,
   `_pthread_workqueue_supported()`,
   `_pthread_workqueue_addthreads()`,
   `_pthread_workqueue_should_narrow()`,
   `pthread_workqueue_addthreads_np()`,
   and the related setup entry points;
3. the bridge now drives the kernel through real `TWQ_OP_*` calls for:
   init, dispatch setup, thread requests, thread entry, thread return, and
   narrowing;
4. the bridge maintains process-local worker state, pending counts, active
   counts, idle-worker wakeups, and detached worker creation;
5. `thr_syscalls.c` and `thr_workq.c` now avoid the earlier unresolved
   `libsys` stub path by using raw syscall numbers for the two problematic
   calls;
6. a manual `libthr.so.3` link against the host `libsys.so.7` is now the
   stable staging artifact, which avoids the non-PIC objdir `libsys.a`
   failure that blocked the default shared-link path;
7. the host harness now prepares a staged custom `libthr` directory outside
   this repo and copies it into the guest for execution;
8. the guest lane now runs a dedicated userland pthread_workqueue probe after
   the raw syscall sequences;
9. the guest serial log now proves the first real userland bridge behavior:
   - supported features report `19`;
   - `_pthread_workqueue_init()` returns `0`;
   - `pthread_workqueue_addthreads_np(..., 2)` returns `0`;
   - two callbacks execute under the custom `libthr` path;
   - the observed callback priority is `5376`, which is the expected default
     QoS encoding for this bridge;
10. the full VM integration test passes with the staged custom `libthr`.

Exit criteria:

1. a guest-side userland probe can initialize, request threads, and observe
   callbacks through the staged custom `libthr`;
2. the SPI version does not compile away real narrowing;
3. the feature-bit policy matches what is actually implemented;
4. unsupported kevent or workloop paths fail in a controlled way without
   pretending to exist.

Why it matters:

This is what turns a kernel feature into a usable system feature.

This milestone is now complete enough for its intended purpose.

The remaining behavioral questions are no longer bridge-bring-up questions.
They belong to M10 and later dispatch validation.

## M10: FreeBSD Dispatch Bring-Up

Status: `done`

Goal:

1. get dispatch onto the real workqueue path;
2. prove the port is no longer just a compatibility story.

Work:

1. bring up the worker-thread path first;
2. verify no silent fallback;
3. run basic dispatch tests and custom narrowing or blocking tests;
4. confirm bounded thread growth and meaningful return-to-kernel behavior.

Completed outcomes so far:

1. the local `swift-corelibs-libdispatch` tree now builds successfully against
   the staged custom `libthr`;
2. the project now carries a scripted libdispatch build and staging step in
   `scripts/libdispatch/prepare-stage.sh`;
3. a dedicated guest-side dispatch probe now builds from
   `csrc/twq_dispatch_probe.c`;
4. the guest stages `libdispatch.so`, `libBlocksRuntime.so`, and the dispatch
   probe into isolated runtime directories;
5. the guest now runs the dispatch probe with
   `LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib`;
6. the dispatch probe currently proves:
   - `_pthread_workqueue_supported()` reports `19`;
   - a basic default-QoS workload of `8` tasks starts and completes
     successfully;
   - a pressured workload of `1` user-interactive blocker plus `8` default
     tasks also starts and completes successfully;
   - work is executed on worker threads rather than the main thread;
   - observed peak default in-flight concurrency is `4` in the basic case and
     `3` in the pressured case;
7. the guest serial log now captures dispatch-specific before/after TWQ
   counter snapshots;
8. the basic dispatch snapshot currently shows real deltas under dispatch:
   - `init_count` increased from `4` to `5`;
   - `setup_dispatch_count` increased from `4` to `5`;
   - `reqthreads_count` increased from `8` to `23`;
   - `thread_enter_count` increased from `3` to `8`;
9. the pressured dispatch snapshot currently shows real TWQ pressure evidence:
   - `init_count` increased from `5` to `6`;
   - `setup_dispatch_count` increased from `5` to `6`;
   - `reqthreads_count` increased from `23` to `38`;
   - `thread_enter_count` increased from `8` to `13`;
   - `switch_block_count` increased from `12` to `21`;
   - `switch_unblock_count` increased from `12` to `21`;
   - `bucket_req_total` in the default bucket increased more than
     `bucket_admit_total`;
10. the VM integration test now passes with dispatch included in the staged
    guest workflow, including the pressure workload.

Exit criteria:

1. real workqueue-backed dispatch execution is active;
2. silent fallback is ruled out;
3. core dispatch workloads pass on FreeBSD.

Why it matters:

This is the first user-visible proof that the port changes the platform story.

Current reading:

This milestone is now complete enough for its purpose.

The important uncertainty is no longer "does dispatch use TWQ on FreeBSD?".
That is now proven.

The next uncertainty is M11.5:

1. whether the current kernel plus `libthr` split reuses workers cleanly
   across bursts and pauses;
2. whether narrowing has real lifecycle teeth once workloads run long enough
   to leave workers idle.

## M11: Apple Behavior Reference Lane

Status: `planned`

Goal:

1. validate against the canonical Apple behavior where it is useful;
2. confirm that the chosen semantics line up with the real target without
   turning phase 1 into a broader Darwin-runtime port.

Work:

1. keep the Apple open-source tree as a source and API reference;
2. use native macOS as the canonical behavior lane for matched workloads;
3. compare observable TWQ-relevant behavior once the FreeBSD workload set is
   stronger;
4. only revive local Apple-tree build work if a narrow workqueue-specific gap
   requires it.

Current reading:

The first local exploration on FreeBSD already established the important
boundary:

1. the Apple tree configures successfully against the staged pthread surface;
2. after pushing past the first workgroup and Mach-header failures, the local
   build now stalls on broader Darwin-private QoS, lock, voucher, and
   Swift-concurrency runtime assumptions.

This means local Apple-tree build completion is not the right next phase-1
objective. The right use of M11 is behavior comparison, not continued local
port forcing.

Exit criteria:

1. matched FreeBSD and macOS workloads exist for the behaviors we care about;
2. important divergences are understood rather than accidental;
3. Apple-tree source usage stays focused on semantics, not unrelated
   Darwin-runtime portability work.

Why it matters:

This keeps Apple semantics in view without letting the project drift into a
general Darwin userland port.

## M11.5: Sustained Workload Validation

Status: `done`

Goal:

1. validate worker reuse and narrowing under longer-running dispatch loads;
2. prove the current userland-owned worker lifecycle is good enough before
   Swift enters the picture.

Work:

1. added a sustained mixed-priority dispatch probe mode in
   `csrc/twq_dispatch_probe.c`;
2. added burst-pause-burst coverage with in-process `kern.twq.bucket_*_current`
   sampling;
3. tightened the `libthr` worker idle path around a bounded warm floor;
4. captured lifecycle signals in the guest harness and made them part of the
   gated VM test;
5. confirmed worker reuse through the idle wake path instead of repeated
   short-burst creation.

Exit criteria:

1. thread counts reach a stable bounded plateau under sustained load;
2. idle counts no longer accumulate across short bursts;
3. short-burst worker churn is gone, with later bursts reusing the existing
   pool instead of creating new workers;
4. the guest harness can explain lifecycle failures clearly enough to debug.

Why it matters:

This was the shortest path to proving whether deeper kernel-owned lifecycle
machinery was immediately necessary. The current answer is "not yet" for phase
1, because the guest now shows bounded warm-pool behavior rather than runaway
growth.

## M11.6: Timeout-Isolation Validation

Status: `done`

Goal:

1. prove that idle retirement works without dispatch housekeeping masking it;
2. prove that gaps longer than the idle timeout still preserve reuse of the
   bounded warm worker set;
3. eliminate stale staged `libthr` artifacts as a source of false positives.

Work:

1. added a direct no-dispatch idle-timeout mode to
   `csrc/twq_workqueue_probe.c`;
2. added a `timeout-gap` dispatch mode to `csrc/twq_dispatch_probe.c`;
3. replaced the earlier timed-wait worker cleanup with a `libthr` reaper that
   trims excess idle workers back to the warm floor;
4. taught the Elixir VM harness and gated integration test to assert the new
   timeout-isolation paths;
5. fixed `scripts/libthr/prepare-stage.sh` so newer `libthr` objdir outputs
   refresh the staged manual shared object automatically.

Exit criteria:

1. an overcommit workqueue burst retires from `8` idle workers down to the
   `4`-thread warm floor after the idle window expires;
2. a dispatch burst with a pause longer than the idle timeout still shows
   `round_new_threads:[4,0]` rather than recreating the pool;
3. the guest lane passes with no temporary reaper debug prints in serial
   output;
4. the staged `libthr` refresh path no longer depends on a manual relink step.

Why it matters:

This milestone closes the exact ambiguity Opus called out. The warm pool is no
longer just a plausible interpretation of short-burst behavior; idle
retirement and long-gap reuse are now proven separately and reproducibly.

## M12: Swift Delayed-Resume Correctness Closure

Status: `done`

Goal:

1. close the strongest remaining Tier 1 correctness gap in staged
   Swift/TWQ validation;
2. identify the lowest honest fix layer instead of overfitting to the first
   staged `libdispatch` symptom boundary;
3. re-run the real staged Swift matrix after the fix instead of claiming
   victory from a single targeted probe.

Completed outcomes:

1. the repo froze Swift workload expansion and used the existing staged Swift
   diagnostics as the discovery lane while pushing the fix downward;
2. pure-C delayed-dispatch queue-shape controls and the stricter
   `main-executor-resume-repeat` mode proved that raw timer-hop-to-executor
   behavior was healthy on the staged TWQ lane;
3. staged `libdispatch` tracing narrowed the old symptom boundary usefully,
   but the final root cause turned out to be lower: kernel `TWQ` accounting
   was collapsing constrained and overcommit occupancy inside the same QoS
   bucket;
4. internal kernel accounting is now split by lane in
   `/usr/src/sys/kern/kern_thrworkq.c`, while the public `kern.twq.bucket_*`
   sysctls remain bucket-aggregated;
5. after that kernel fix, the previously failing staged probe
   `dispatchmain-taskhandles-after-repeat-hooks` now completes all `64`
   rounds successfully;
6. the broader staged Swift `full` profile now completes end-to-end on the
   guest with no timeout results, aside from the already-known invalid
   `customdispatch + stock libthr` control lanes.

Boundary history and closeout evidence:

1. `twq-swift-async-smoke` succeeds in the guest.
2. `twq-swift-dispatch-control` succeeds in the guest and increases:
   `init_count`, `setup_dispatch_count`, `reqthreads_count`, and
   `thread_enter_count`.
3. `twq-swift-mainqueue-resume` also succeeds in the guest and increases real
   `reqthreads_count` and `thread_enter_count`.
4. the repo now has a stable Swift `validation` profile and the gated VM
   integration run passes on that profile.
5. the stock host Swift 6.3 toolchain completes every current probe entry
   shape successfully, including `async main`, `TaskGroup`, `@MainActor`,
   `dispatchMain()`, and detached-task variants.
6. the staged guest stack is therefore context-sensitive rather than uniformly
   broken.
7. the remaining Swift probes are split intentionally:
   - required validation:
     `async-smoke`, `dispatch-control`, `mainqueue-resume`
   - focused `dispatchMain()` diagnostics:
     `dispatchmain-spawn`, `dispatchmain-yield`,
     `dispatchmain-continuation`, `dispatchmain-sleep`,
     `dispatchmain-taskgroup`, `dispatchmain-spawned-yield`,
     `dispatchmain-spawned-sleep`, `dispatchmain-taskgroup-yield`,
     `dispatchmain-taskgroup-onesleep`,
     `dispatchmain-taskgroup-sleep`, `dispatchmain-taskgroup-sleep-next`
   - broader diagnostics:
     `taskgroup-spawned` and the inherited-context probes in the `full`
     profile
8. focused guest runs now show that spawned suspended children under
   `dispatchMain()` complete successfully, so plain spawned-child suspension is
   not the blocker.
9. a later runtime-matrix pass showed `dispatchmain-taskgroup-yield`
   completing in all three tested runtime combinations:
   stock-dispatch plus stock `libthr`, stock-dispatch plus custom `libthr`,
   and the full staged TWQ lane.
10. the same runtime-matrix pass showed `dispatchmain-taskgroup-sleep`
    timing out only on the full staged TWQ lane while both stock-dispatch
    combinations completed successfully.
11. `dispatchmain-spawnwait-sleep` now shows the same split:
    timeout on the full staged TWQ lane, success on stock-dispatch.
12. That older `Task.sleep` reading is now too broad.
13. newer `dispatch_after`-based controls show `dispatchmain-spawnwait-after`
    completing on the full staged TWQ lane while
    `dispatchmain-taskgroup-after` still times out there.
14. the same `dispatchmain-taskgroup-after` binary completes on both
    stock-dispatch guest controls, including stock-dispatch plus custom
    `libthr`.
15. local Swift 6.3 runtime source inspection now shows that the non-Apple
    global executor creates per-priority concurrent queues and immediately
    calls `dispatch_queue_set_width(queue, -3)` on them before using
    `dispatch_after_f()` for delayed jobs.
16. the C dispatch probe now has four executor-after queue-shape controls:
    `executor-after`, `executor-after-settled`,
    `executor-after-default-width`, and `executor-after-sync-width`.
17. the latest full guest diagnostic run shows all four of those pure-C
    delayed-dispatch queue shapes completing successfully on the staged TWQ
    lane.
18. that weakens the earlier queue-width hypothesis: the Swift-style async
    width-narrowing shape is real, but raw delayed C dispatch on that shape is
    healthy.
19. the current staged Swift boundary is therefore best described as delayed
    Swift child-task completion awaited by a parent async context on the
    staged custom `libdispatch` lane, beyond the raw C delayed-dispatch queue
    shape, not generic `TaskGroup` suspension, not custom `libthr`, and not
    `Task.sleep` alone.
20. host-side symbol inspection now shows the stock Swift 6.3
    `libdispatch.so` does not reference `_pthread_workqueue_init`,
    `_pthread_workqueue_addthreads`, or the other workqueue entry points,
    while the staged custom `libdispatch.so` does.
21. the guest-side stock-dispatch plus custom-`libthr` delayed-child control
    completes successfully, but its `kern.twq.reqthreads_count` and
    `kern.twq.thread_enter_count` values stay flat across the probe window.
22. that makes the stock-dispatch plus custom-`libthr` lane a useful
    Swift/runtime comparison lane, but not evidence that the stock Swift 6.3
    dispatch runtime is using TWQ.
23. a new pure-C `worker-after-group` dispatch mode completes successfully on
    the staged TWQ lane, so raw delayed callbacks plus parent waiting do work
    below Swift.
24. a new Swift `dispatchmain-taskhandles-after` probe times out on the staged
    TWQ lane while passing on the stock host Swift 6.3 lane, so the remaining
    boundary is not `TaskGroup` alone. It is the interaction between staged
    custom `libdispatch` and multiple delayed Swift child-task resumptions.
25. guest-side control runs now show `dispatchmain-taskhandles-after`
    completing on both stock-dispatch lanes:
    stock `libthr` and custom `libthr`.
26. in the failing staged `dispatchmain-taskhandles-after` run, every child
    still reaches `child-after-await-*`, while the parent stalls after
    `parent-awaiting-1`.
27. that moves the remaining blame off generic Swift future completion and
    off custom `libthr`; the strongest remaining fault line is staged
    workqueue-enabled `libdispatch`.
28. the most specific staged lead is now non-thread-bound `dispatchMain()`
    main-queue / executor redrive under the workqueue-backed lane.
29. a new repeated delayed-child stress control,
    `dispatchmain-taskhandles-after-repeat-stockdispatch-customthr`,
    completes all `64` rounds on the same guest while still using the custom
    `libthr` TWQ bridge.
30. the matching full staged repeat lane,
    `dispatchmain-taskhandles-after-repeat-hooks`, still times out.
31. focused hook and staged-`libdispatch` tracing now show that the failing
    late child resumptions still reach:
    - Swift `enqueueGlobal`
    - `dispatch_async_f`
    - staged `libdispatch` `continuation_async`
32. those same resumptions stop before the staged `libdispatch` callout /
    invoke path runs them on the `Swift global concurrent queue`.
33. that removes kernel `TWQ` worker supply and the custom `libthr` bridge
    from the critical-path suspect set for this failure class.
34. `customdispatch + stock libthr` is not a valid runtime control here,
    because staged `libdispatch` expects custom-`libthr` symbols such as
    `qos_class_main`.
35. a new pure-C `main-executor-resume-repeat` mode now completes all `64`
    rounds on the staged TWQ lane while using the same essential timer-queue
    to executor-queue hop as the failing Swift repeat probe.
36. that rules out the simple timer-hop theory, but does not clear staged
    `libdispatch` itself.
37. the decisive root-cause correction is now in place:
    internal kernel `TWQ` accounting distinguishes constrained and
    overcommit lanes per QoS bucket instead of collapsing them together.
38. the previously failing staged repeat run,
    `dispatchmain-taskhandles-after-repeat-hooks`, now completes all `64`
    rounds on the full TWQ lane:
    `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-taskhandles-repeat-hooks-swiftonly-lanesplit.serial.log`
39. the broader staged Swift `full` profile now completes cleanly too:
    `/Users/me/wip-gcd-tbb-fx/artifacts/twq-dev-swift-full-post-lanesplit.serial.log`
40. that full profile includes successful staged results for the earlier M12
    blockers:
    - `dispatchmain-spawnwait-sleep`
    - `dispatchmain-spawnwait-after`
    - `dispatchmain-taskhandles-after`
    - `dispatchmain-taskhandles-after-repeat`
    - `dispatchmain-taskgroup-after`
    - `dispatchmain-taskgroup-sleep`
    - `dispatchmain-taskgroup-sleep-next`
41. the only remaining non-`ok` Swift entries in the full profile are the
    already-known invalid `customdispatch + stock libthr` control lanes,
    which fail because staged `libdispatch` expects custom-`libthr` symbols
    such as `qos_class_main`.

Exit criteria:

1. the delayed-child Swift boundary is closed on the real staged TWQ lane;
2. the existing required Swift `validation` profile remains green;
3. the stronger staged delayed-child diagnostics are re-run after the fix and
   now complete;
4. the repo has a documented explanation for why the earlier staged
   `libdispatch` symptom boundary was incomplete;
5. the next milestone can shift from correctness isolation to performance and
   regression discipline.

Why it matters:

This closes the strongest remaining Tier 1 Swift correctness gap in the
current validation matrix. The important lesson is architectural: staged
`libdispatch` tracing was useful narrowing work, but the final bug sat lower
than that symptom boundary. The next honest step is no longer more delayed
resume isolation. It is performance discipline, efficiency tuning, and then
macOS comparison with the correctness floor in place.

## M13: Performance and Regression Discipline

Status: `in_progress`

Goal:

1. make performance claims real instead of anecdotal;
2. keep the project from regressing as semantics improve.

Work:

1. add Zig microbenchmarks for syscall overhead, thread create, return,
   narrow, wakeup, and stack reuse;
2. capture stable JSON benchmark output;
3. archive baselines by kernel revision;
4. start gating obvious regressions once the baseline is trustworthy.

Current progress:

1. the repo now has a reproducible host-side benchmark lane in
   `scripts/benchmarks/run-m13-baseline.sh`;
2. the guest serial output can now be normalized into a structured baseline via
   `scripts/benchmarks/extract-m13-baseline.py`;
3. the first compact baseline is checked in at
   `benchmarks/baselines/m13-initial.json`;
4. the first recorded baseline shows all `6` selected dispatch modes and all
   `3` selected Swift modes completing with `ok` status;
5. the next optimization target is clear from that baseline:
   repeated continuation-heavy lanes still generate high
   `reqthreads` / `thread_enter` / `thread_return` churn.
6. a second verification run preserved the same qualitative hotspot pattern but
   still showed enough numeric drift that hard regression gating would be
   premature before the noise floor is characterized.
7. focused repeat-only telemetry now shows that the remaining hotspot is not
   just cold-start noise:
   `dispatch.main-executor-resume-repeat` keeps a steady `reqthreads` mean of
   `7.55` per round with `bucket_total` pinned at `5`, while
   `swift.dispatchmain-taskhandles-after-repeat` still averages `41.73`
   `reqthreads` per round late in the run.
8. `scripts/libthr/prepare-stage.sh` now auto-selects the freshest `libthr`
   objdir, fixing a stale-stage bug that had masked the first live M13 tuning
   result.
9. `/usr/src/lib/libthr/thread/thr_workq.c` now has a same-lane handoff fast
   path that skips a redundant return/enter cycle when a worker immediately
   claims more work in the same kernel bucket.
10. the first two real post-fix repeat-only runs reduced
    `dispatch.main-executor-resume-repeat` from a pre-fix mean of
    `reqthreads +546 / enter +183 / return +180` to
    `+379 / +172 / +169` and `+320 / +150 / +147`.
11. the same tuning pass reduced
    `swift.dispatchmain-taskhandles-after-repeat` request churn from a
    pre-fix mean of `reqthreads +2659.5 / enter +887.5 / return +884.5` to
    `+1630 / +780 / +777` and `+1863 / +884 / +881`, but the traced proof run
    also shows that cross-lane handoffs still dominate the remaining cost.
12. `TWQ_OP_THREAD_TRANSFER` now exists in the kernel and `libthr`, so a worker
    that claims work from a different lane can move directly into that lane
    instead of always doing a full return/re-enter cycle.
13. the first current-branch transfer experiments were initially misleading
    because the guest did not yet contain the new code:
    the kernel had to be rebuilt first, and then the staged `libthr` had to be
    refreshed from newly rebuilt `/tmp/twqlibobj/.../*.pico` objects.
14. once both were real, the traced run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T112356Z.serial.log`
    showed `worker-handoff-transfer: 183`,
    `worker-handoff-enter: 0`, and
    `worker-handoff-fastpath: 85`, proving that the new cross-lane path was
    live in the guest.
15. the two clean post-transfer runs moved
    `dispatch.main-executor-resume-repeat` to
    `+380 / +169 / +166` and `+354 / +163 / +160`, which keeps the C lane in
    roughly the same band as the earlier same-lane-only tuning.
16. the repo no longer relies on a fake Zig microbenchmark stub:
    `zig/bench/syscall_hotpath.zig` plus
    `scripts/benchmarks/run-zig-hotpath-bench.sh` now provide a real guest-run
    benchmark lane for `should-narrow`, `reqthreads`, and
    `reqthreads-overcommit`.
17. the first three guest benchmark artifacts are now preserved outside the
    repo at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-should-narrow-20260416T191500Z.json`,
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-reqthreads-20260416T192000Z.json`,
    and
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-reqthreads-overcommit-20260416T192500Z.json`,
    and the compact repo baseline is checked in at
    `benchmarks/baselines/m13-zig-hotpath-initial-20260416.json`.
18. those first measurements put the current steady guest kernel in the
    following band:
    `should-narrow mean_ns=1035`,
    constrained `reqthreads mean_ns=1151`,
    and overcommit `reqthreads mean_ns=524`,
    which is enough to replace the earlier placeholder and start tracking drift
    across kernel revisions.
16. the same two clean runs moved
    `swift.dispatchmain-taskhandles-after-repeat` to
    `+1371 / +460 / +457` and `+1500 / +506 / +503`, which is materially below
    the earlier same-lane-only Swift result and closes cross-lane recycling as
    the leading unknown.
17. the next honest M13 target is now staged `libdispatch` request generation
    and wake policy across root queues, not another round of worker recycling
    changes inside `libthr`.
18. a follow-up staged-`libdispatch` experiment that tried to cap drain-side
    repokes with an active-worker counter was rejected and reverted:
    the proof trace only hit the new `drain-one-skip-poke` path `2` times
    while `root-queue-poke-slow` still fired `988` times, so that heuristic is
    not the real lever.
19. a second follow-up `libthr` experiment that tried to skip kernel
    `REQTHREADS` when a lane's `tbr_ready` count already covered
    `tbr_pending` was also rejected and reverted:
    the traced proof run only hit `addthreads-covered` `4` times against
    `addthreads-begin: 952`, and the repeat-only Swift lane did not show a
    stable improvement across
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115402Z.json`,
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115538Z.json`,
    and
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260413T115743Z.json`.
20. root-only tracing in
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T095603Z.serial.log`
    now shows that the earliest repeat-lane overcommit request is sourced by
    `_dispatch_queue_cleanup2()` re-enqueuing `com.apple.main-thread` onto
    `com.apple.root.default-qos.overcommit` as an `empty->poke` root item.
21. a donor-side comparison against
    `../nx/apple-opensource-libdispatch/src/queue.c` and
    `../nx/apple-opensource-libdispatch/src/inline_internal.h`
    now says that seam is probably native-shaped:
    Apple’s open `libdispatch` points `_dispatch_main_q` at
    `_dispatch_get_default_queue(true)`, and `_dispatch_queue_cleanup2()`
    immediately hands off through `_dispatch_lane_barrier_complete()`.
22. that changes the next M13 target again:
    the existence of the `cleanup2 -> overcommit root` handoff is no longer
    the main suspect; the honest target is now excess overcommit redrive rate
    and weak coalescing after the first cleanup-triggered handoff.
23. a follow-up `libthr` analysis found that the runtime was still too
    spawn-biased:
    lane admission was being translated into `spawn_needed` even when
    same-lane idle workers or transferable idle workers already existed.
24. `/usr/src/lib/libthr/thread/thr_workq.c` now tracks per-lane idle workers
    (`tbr_idle`) and uses a wake-first planning step in both the `addthreads`
    path and reaper-driven redrive:
    same-lane idle workers are used first, then transferable idle workers, and
    only the remainder is spawned.
25. two clean repeat-only runs at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T110916Z.json`
    and
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111107Z.json`
    kept the C repeat lane stable while improving the Swift repeat lane to
    `+1350 / +429 / +426` and `+1279 / +394 / +391`.
26. the next honest M13 question is now narrower than “optimize libdispatch”
    or “optimize libthr” in the abstract:
    a trace-enabled repeat lane should quantify the remaining wake/spawn mix
    before the next behavioral patch is chosen.
27. `scripts/bhyve/stage-guest.sh` now supports split trace controls for
    `TWQ_LIBPTHREAD_TRACE`,
    `TWQ_LIBDISPATCH_MAINQUEUE_TRACE`, and
    `TWQ_LIBDISPATCH_ROOT_TRACE`, so `libthr` tracing no longer requires the
    noisier bundled `TWQ_SWIFT_RUNTIME_TRACE` path.
28. the new `libthr`-only traced run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.serial.log`
    and
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T111903Z.json`
    completed successfully and showed the remaining repeat-lane requests are
    overwhelmingly wake-dominant:
    dispatch had `118` wake-only versus `5` spawn-only `addthreads-ready`
    events, and Swift had `456` wake-only versus `7` spawn-only.
29. that is the next real decision point:
    `libthr` wake-first planning is now proven enough that the next behavioral
    reduction should return to staged-`libdispatch` request generation and
    coalescing, with the new low-noise `libthr` trace lane kept as a
    regression guard.
30. a narrower staged-`libdispatch` follow-up then tried deferring the root
    poke only for single queue-object pushes back onto the same root worker.
31. that branch was rejected and reverted after two clean repeat-only runs:
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T124521Z.json`
    looked promising at
    `dispatch +343 / +155 / +152` and
    `swift +1184 / +362 / +359`,
    but the confirmation run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T124736Z.json`
    regressed to
    `dispatch +432 / +187 / +184` and
    `swift +1532 / +506 / +503`.
32. the first improved sample is now treated as timing luck, not as a valid
    new M13 baseline.
33. the next staged-`libdispatch` pass then stopped trying to coalesce all
    root redrive generically and instead suppressed
    `_dispatch_root_queue_drain_one() -> _dispatch_root_queue_poke(dq, 1, 0)`
    only for one-shot `dispatch_after` timer sources on the non-overcommit
    default root.
34. the first clean proof run,
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134322Z.json`,
    kept both repeat lanes correct while improving
    `dispatch.main-executor-resume-repeat` to
    `+324 / +153 / +150`
    and
    `swift.dispatchmain-taskhandles-after-repeat` to
    `+1234 / +408 / +405`.
35. the corresponding counter dump proves the source seam was real:
    Swift dropped to
    `root_repoke_default=0`,
    `root_repoke_drain_one_default=0`,
    with
    `root_repoke_suppressed_after_source_default=363`.
36. the follow-up classification run,
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260415T134625Z.json`,
    kept that source suppression result and improved Swift again to
    `+1137 / +386 / +383`,
    while holding the C lane in the same improved band at
    `+329 / +153 / +150`.
37. after source suppression, the remaining C default-root repoke tail is now
    explicit:
    `root_repoke_drain_one_kind_default_continuation=443`,
    `root_repoke_drain_one_kind_default_continuation_async_redirect=443`,
    and
    `root_repoke_drain_one_kind_default_lane=55`,
    so the next honest M13 target is the default-root `ASYNC_REDIRECT`
    continuation path, not generic root repoke policy.
38. an attempted in-process classifier for default-overcommit root-push object
    kinds was rejected after it produced Swift repeat `rc=139` failures:
    the classifier dereferenced the pushed object after `os_mpsc_push_list()`
    had published it to the root queue, so a concurrent drainer could recycle
    it before `dx_metatype()` read the vtable.
39. that unsafe classifier was reverted while keeping the proven source and
    `ASYNC_REDIRECT` suppression changes; the focused stability run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-baseline-20260416T024756Z.json`
    completed the Swift repeat lane at
    `reqthreads +969 / enter +317 / return +314`.
40. FreeBSD DTrace is now the preferred tool for the next diagnostic seam:
    scripts under `scripts/dtrace/` trace `_dispatch_root_queue_push:entry`,
    `_dispatch_root_queue_poke*`, `_dispatch_continuation_pop`,
    `_dispatch_queue_cleanup2`, and `_dispatch_async_redirect_invoke` without
    mutating the hot path.
41. `scripts/bhyve/stage-guest.sh` stages those scripts into the guest under
    `/root/twq-dtrace`, so future repeat-lane runs can classify push
    populations before the MPSC publish boundary.
42. `hwpmc` is recorded as a later M13/M14 performance attribution tool for
    bare-metal cost analysis after DTrace has identified the semantic hot path;
    it is not the right tool for pointer-safety or queue-ownership bugs.
43. the DTrace runner now targets the real probe process instead of
    `/usr/bin/env`, which makes the exported staged-`libdispatch`
    `_dispatch_twq_dtrace_*` shims reliable in bhyve runs.
44. a fresh `push-vtable` DTrace run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-dtrace-push-vtable-20260416T042209Z.serial.log`
    shows the default-overcommit root receiving main-queue objects, while the
    default root receives timer sources and the user-initiated root receives
    Swift/global continuation traffic.
45. staged `libdispatch` now keeps only a narrow safe push-path classifier:
    pointer equality against `_dispatch_main_q` before MPSC publication. It
    does not decode arbitrary pushed objects on the hot path.
46. the full Swift repeat counter run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-swift-repeat-counters-20260416T041819Z.json`
    completed at `reqthreads +1058 / enter +343 / return +340`, with
    `root_push_empty_default_overcommit=186` matching
    `root_push_mainq_default_overcommit=186`.
47. the current M13 conclusion is therefore narrower:
    default-overcommit pressure in the Swift repeat lane is main-queue handoff
    traffic and appears native-shaped. The next tuning decision should compare
    rate and coalescing against macOS before suppressing it.
48. `scripts/benchmarks/extract-m13-baseline.py` now emits schema version `2`
    and preserves libdispatch counter dumps alongside TWQ deltas.
49. `scripts/benchmarks/summarize-m13-baseline.py` and
    `scripts/benchmarks/compare-m13-baselines.py` are now the first practical
    CLI tools for quick M13 triage and drift-tolerant regression comparison.
50. the current project state is healthy rather than blocked:
    correctness is stable, the kernel path is stable, and the main remaining
    uncertainty is comparative behavior against macOS.
51. the current M13 exit path is now visible:
    freeze the proven FreeBSD-side behavior changes, keep the new benchmark and
    DTrace lane as the local regression guard, and use M14 to decide whether
    more suppression/coalescing work is justified.
52. M14 then returned a stop result for the main-queue to
    `default.overcommit` seam: native macOS shows the same qualitative Swift
    repeat-lane handoff shape, and FreeBSD is about `1.58x` higher rather than
    near the stronger `2x` tuning threshold.
53. the Zig hot-path lane has now expanded from three request/query modes to a
    six-mode lifecycle suite covering `should-narrow`, constrained
    `reqthreads`, overcommit `reqthreads`, `thread-enter`, `thread-return`,
    and `thread-transfer`.
54. the full lifecycle suite run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/zig-hotpath-lifecycle-suite-20260416T215000Z.json`
    completed all six modes with `status=ok` and balanced enter/return cleanup
    around all lifecycle modes.
55. the suite-native M13 baseline now gates `thread_transfer_count` as well as
    `reqthreads_count`, `thread_enter_count`, and `thread_return_count`, giving
    future kernel, `libthr`, and ISA experiments a lower-level regression
    boundary before they touch dispatch policy.
56. the Zig gate policy is intentionally split:
    counter deltas are exact by default, while latency drift is coarse
    (`3.0x` plus `1000ns`) to avoid false failures from WITNESS-enabled bhyve
    timing noise.
57. M13 now also has a real warmed-worker wake benchmark lane in
    `csrc/twq_workqueue_wake_bench.c`, measuring request-to-callback-start
    latency for both constrained and overcommit workqueue wakes.
58. the full wake suite run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/workqueue-wake-suite-20260416T095418Z.json`
    completed both modes with `status=ok`, `thread_mismatch_count=0`, and a
    stable single-worker settled state (`before_total=1`, `after_total=1`).
59. the checked-in wake baseline at
    [m13-workqueue-wake-suite-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-workqueue-wake-suite-20260416.json)
    now gates exact `reqthreads_count`, `thread_enter_count`,
    `thread_return_count`, `thread_transfer_count`, and
    `thread_mismatch_count` deltas for future `libthr` wake-path changes.
60. the normal wake-path regression command is now a one-command guest gate:
    `scripts/benchmarks/run-workqueue-wake-gate.sh`.
61. the warmed-worker wake lane is now also reachable through the Elixir
    harness via `TwqTest.Workqueue.build_wake_bench/1` and
    `TwqTest.Workqueue.run_wake_suite/1`, so the lane is no longer shell-only.
62. the full M13 low-level floor is now composed into one repo-owned command:
    `scripts/benchmarks/run-m13-lowlevel-gate.sh`.
63. that gate is now suite-native rather than sequential:
    `scripts/benchmarks/run-m13-lowlevel-suite.sh` stages both low-level
    suites into one guest boot and emits one combined artifact.
64. the first one-boot combined suite run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-lowlevel-suite-20260416T101547Z/m13-lowlevel.json`
    is now the suite-native reference artifact for the combined low-level
    floor.
65. the checked-in combined baseline is now
    [m13-lowlevel-suite-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m13-lowlevel-suite-20260416.json).
66. `scripts/benchmarks/compare-m13-lowlevel-baseline.py` now compares that
    combined artifact shape while delegating the child-suite policy to the
    proven Zig and workqueue wake comparators.
67. the first one-command suite-native gate run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-lowlevel-gate-20260416T101704Z/summary.md`
    proves that the full low-level floor can now be rerun in one guest boot
    and one compare step.
68. the same combined artifact is now visible to ExUnit through
    `TwqTest.LowlevelBench`, so the repo-owned low-level floor is not only a
    shell concept.
69. the checked-in FreeBSD schema-`3` repeat reference is now protected by a
    dedicated focused gate:
    `scripts/benchmarks/run-m13-repeat-gate.sh` generates or reuses a focused
    repeat artifact, compares it against
    [m14-freebsd-round-snapshots-20260416.json](/Users/me/wip-gcd-tbb-fx/wip-codex54x/benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json),
    and emits a structured comparison plus `summary.md`.
70. the guest staging seam for repeat-lane libdispatch counters is now fixed:
    the outer wrappers pass `TWQ_LIBDISPATCH_COUNTERS=1`, which
    `scripts/bhyve/stage-guest.sh` converts into guest-side
    `LIBDISPATCH_TWQ_COUNTERS=1`.
71. the repeat-lane extractor and comparators now align libdispatch deltas by
    actual round number, so sparse-but-valid control-lane snapshot series do
    not produce false regression failures.
72. the fresh end-to-end proof run at
    `/Users/me/wip-gcd-tbb-fx/artifacts/benchmarks/m13-repeat-gate-20260416T-final/summary.md`
    completed with `verdict=ok`, confirming that both repeat modes now carry
    usable libdispatch snapshot data under the normal focused guest gate.

Exit criteria:

1. key hot paths have benchmark coverage;
2. performance can be compared against earlier FreeBSD baselines;
3. the project can honestly say when it improves or regresses.

Why it matters:

Semantics-first is correct for phase 1, but performance discipline has to start
before the codebase gets large.

## M14: Canonical macOS Comparison Lane

Status: `done`

Goal:

1. compare behavior against native macOS `libdispatch`;
2. use the Apple Silicon machine as the canonical reference lane.

Work:

1. use the native Swift `dispatchMain()` repeat shape as the primary workload,
   because it is the workload that actually matches the current FreeBSD seam:
   repeated delayed child completion, non-main delayed source, and main-thread
   resumption;
2. keep the pure-C `main-executor-resume-repeat` lane as a secondary
   calibration/control workload, not the deciding seam;
3. capture per-round behavior after startup, not just whole-run totals;
4. use steady-state rounds `8-63` as the primary comparison window and keep
   startup rounds only as supporting context;
5. measure the exact seam that now dominates the FreeBSD reading:
   main-queue cleanup/handoff into the default-overcommit root;
6. compare the primary rates that matter for that seam:
   main-queue pushes into default-overcommit,
   default-overcommit `poke_slow`,
   and workqueue addthreads / requested-thread sum per round;
7. prefer a custom macOS `libdispatch` / `libpthread` build with explicit
   counters or USDT probes if stock symbol visibility is not good enough;
8. treat DTrace on those custom probes as the preferred macOS measurement
   lane, with Instruments / `xctrace` / signposts used only as supporting
   evidence;
9. land the macOS results into the repo-owned comparison shape now documented
   by `benchmarks/m14-macos-template.json` and
   `scripts/benchmarks/compare-m14-steady-state.py`;
10. classify divergence as comparable, acceptable, or concerning before making
   another staged-`libdispatch` suppression decision.

Exit criteria:

1. the same workload family can run on FreeBSD and macOS;
2. the comparison focuses on steady-state rounds, not startup noise;
3. results land in a common enough schema to compare root push, poke, and
   worker-request rates;
4. the project can say whether the current FreeBSD main-queue handoff rate is
   native-shaped or still a real coalescing gap.
5. the project has an explicit stop/tune decision boundary:
   if macOS shows the same qualitative traffic split and roughly the same
   order of magnitude for steady-state main-queue pushes and
   `default.overcommit poke_slow`, stop tuning this seam on FreeBSD;
   if macOS is materially lower, especially around `2x` lower in steady-state
   handoff/poke rate for the same `64 x 8 x 20ms` Swift workload, keep tuning.

Completed outcome:

1. the first stock-macOS result now lives in
   `benchmarks/baselines/m14-macos-stock-introspection-20260416.json`;
2. it shows the same qualitative Swift/main-queue seam as FreeBSD:
   source traffic on `default`, main-queue handoff traffic on
   `default.overcommit`, and a clean C control lane;
3. the primary steady-state rates are lower on macOS but only by about
   `1.58x`, which is below the stronger `2x` concern boundary;
4. the resulting decision is to stop tuning this seam on FreeBSD.

Why it matters:

This keeps the project aligned with canonical behavior without demanding total
Darwin replication.

## M14.5: Pressure-provider prep lane

Status: `done`

Goal:

1. prepare an upward-facing pressure boundary after `M13` without inventing a
   live SPI too early;
2. prove that the checked-in crossover artifact already contains enough
   mechanism data to derive a stable pressure-only view;
3. freeze the rule that future consumers get pressure signals, not raw queue
   semantics.

Completed outcomes:

1. `extract-m15-pressure-provider.py` now derives a pressure-only provider
   artifact from the checked-in schema-3 crossover baseline;
2. the first checked-in derived baseline now lives at
   `benchmarks/baselines/m15-pressure-provider-20260417.json`;
3. `compare-m15-pressure-provider-baseline.py` now checks both aggregate
   pressure values and the top-level boundary shape:
   `provider_scope`, synthetic generation semantics, and the explicit absence
   of live monotonic timestamps;
4. `run-m15-pressure-provider-prep.sh` now provides the repo-owned shell lane
   for re-deriving and re-checking the provider view;
5. the same derived boundary is now visible through
   `TwqTest.PressureProvider` and
   `TwqTest.VM.run_m15_pressure_provider_prep/1`;
6. `m15-pressure-provider-prep.md` now records the scope boundary:
   pressure upward, mechanism downward, per-bucket diagnostics optional, no
   raw queue semantics, no permit vocabulary;
7. `csrc/twq_pressure_provider_probe.c` now emits live guest-side snapshots for
   `dispatch.pressure` and `dispatch.sustained`;
8. the first checked-in live smoke baseline now lives at
   `benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json`;
9. `compare-m15-live-pressure-provider-smoke.py` and
   `run-m15-live-pressure-provider-smoke.sh` now provide the repo-owned live
   smoke lane;
10. the live smoke boundary is now recorded in
    `m15-live-pressure-provider-smoke.md` and is visible through
    `TwqTest.LivePressureProvider` plus
    `TwqTest.VM.run_m15_live_pressure_provider_smoke/1`;
11. both the derived and live pressure-only boundaries now treat
    `nonidle_workers_current = total_workers_current - idle_workers_current`
    as the effective current-pressure signal, while keeping raw
    `active_workers_current` only as supporting detail for continuity;
12. the machine-readable contract for that boundary now lives at
    `benchmarks/contracts/m15-pressure-provider-contract-v1.json` and is
    checked against the derived, live, adapter, and preview baselines via a
    repo-owned contract-validation lane;
13. `twq_pressure_provider_adapter.h`,
    `twq_pressure_provider_adapter.c`, and
    `twq_pressure_provider_adapter_probe.c` now define a versioned aggregate
    adapter view above the raw snapshot and below any SPI claim;
14. `extract-m15-pressure-provider-adapter.py`,
    `compare-m15-pressure-provider-adapter-smoke.py`, and
    `run-m15-pressure-provider-adapter-smoke.sh` now provide the repo-owned
    adapter smoke lane, with the first checked-in baseline at
    `benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json`;
15. the adapter boundary is now recorded in
    `m15-pressure-provider-adapter-smoke.md` and visible through
    `TwqTest.PressureProviderAdapter` plus
    `TwqTest.VM.run_m15_pressure_provider_adapter_smoke/1`;
16. `csrc/twq_pressure_provider_observer.h`,
    `csrc/twq_pressure_provider_observer.c`, and
    `csrc/twq_pressure_provider_observer_probe.c` now define a policyless
    observer summary above the aggregate adapter view and below any real
    consumer integration;
17. `extract-m15-pressure-provider-observer.py`,
    `compare-m15-pressure-provider-observer-smoke.py`, and
    `run-m15-pressure-provider-observer-smoke.sh` now provide the repo-owned
    observer smoke lane, with the first checked-in baseline at
    `benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json`;
18. the observer boundary is now recorded in
    `m15-pressure-provider-observer-smoke.md` and visible through
    `TwqTest.PressureProviderObserver` plus
    `TwqTest.VM.run_m15_pressure_provider_observer_smoke/1`;
19. `csrc/twq_pressure_provider_preview.h` and
    `csrc/twq_pressure_provider_preview.c` now define a versioned raw snapshot
    v1 shape below the higher-level pressure-only artifacts;
20. `csrc/twq_pressure_provider_preview_probe.c`,
    `extract-m15-pressure-provider-preview.py`,
    `compare-m15-pressure-provider-preview-smoke.py`, and
    `run-m15-pressure-provider-preview-smoke.sh` now provide the repo-owned
    raw preview smoke lane;
21. the first checked-in raw preview baseline now lives at
    `benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json`;
22. the raw preview boundary is now recorded in
    `m15-pressure-provider-preview-smoke.md` and visible through
    `TwqTest.PressureProviderPreview` plus
    `TwqTest.VM.run_m15_pressure_provider_preview_smoke/1`.

Exit criteria:

1. the checked-in crossover artifact reproduces the checked-in provider
   baseline;
2. the comparison lane stays green;
3. the guest-side live smoke lane stays green against the checked-in live
   baseline;
4. the boundary remains pressure-only and still does not claim a live SPI;
5. current-pressure quiescence is judged by total/non-idle worker return to
   zero, not by raw `active_workers_current` alone;
6. the derived, live, adapter, and preview artifact families still conform to
   the same checked-in pressure-provider contract;
7. the observer lane stays above the aggregate adapter view and below any real
   consumer/runtime integration;
8. the raw preview lane stays versioned, comparable, and explicitly below any
   claimed private SPI preview.

Why it matters:

This is the first concrete upper-boundary prep step after `M13` closeout. It
creates a stable future-consumer surface without pretending that the project
already has a live provider ABI. The live smoke extension now proves the same
pressure-only boundary can also be emitted in-guest with real sequencing and
real monotonic time, while still staying probe-scoped instead of becoming an
ABI claim. The later `nonidle_workers_current` promotion keeps that boundary
honest by exposing the stronger live signal already implicit in the current
`TWQ` totals rather than overstating raw `active_workers_current`. The
aggregate adapter lane now proves that there is also a stable aggregate-only C
view above the raw data, and the new observer lane proves that a consumer-side
summary can sit above that adapter view without promoting per-bucket details
or claiming a real integration surface. The raw preview lane still proves that
there is also a versioned struct-shaped snapshot boundary under those
higher-level artifacts, which remains the last useful prep step before any
actual SPI-preview discussion. The machine-readable contract then freezes that
same boundary explicitly so future
consumer work starts from one checked-in surface instead of from drift between
docs, baselines, and comparators.

## M15: Optional Deep Integration

Status: `later`

Goal:

1. revisit features that were intentionally deferred;
2. deepen integration only if it remains natural on FreeBSD.

Possible work:

1. scheduler refinement beyond the initial 6-bucket admission model;
2. per-CPU or more nuanced accounting if profiling justifies it;
3. reconsider direct kevent delivery if it becomes compelling;
4. reconsider workloops only if they make sense technically and architecturally.

Exit criteria:

1. there is a concrete benefit that the existing design cannot deliver cleanly;
2. the additional complexity does not distort the FreeBSD kernel model.

Why it matters:

This milestone exists to prevent premature complexity while still leaving room
for a future cleaner system.

## Parallel Work Notes

Some milestones can overlap safely:

1. M01 and M02 can proceed in parallel;
2. M02 and M03 can proceed in parallel;
3. M08 should begin as soon as M06 and M07 are concrete enough to expose the
   kernel behavior;
4. M13 should start early enough that benchmarks exist before major tuning.

Some milestones should not be rushed in parallel:

1. M06 should not be half-defined before M07 starts;
2. M09 should not invent SPI behavior that M06 and M07 do not support;
3. M11 should not become the bring-up target before M10 has proven the real
   path on FreeBSD first.

## Decision Gates

These are the points where the project should pause and evaluate before
charging ahead:

### Gate 1: After M01

Question:

1. is the donor still the right source for the kernel core after a real
   FreeBSD 15 audit?

### Gate 2: After M06

Question:

1. is the ABI and state layout clean enough to live with for a long time?

### Gate 3: After M10

Question:

1. is the real dispatch path strong enough that the platform story has changed
   materially?

### Gate 4: After M13 and M14

Question:

1. where is the biggest remaining gap: semantics, stability, or performance?

## Immediate Focus

The highest-value next milestones are:

1. M13: keep the schema-`3` FreeBSD benchmark, DTrace, and regression tooling
   in place, with the focused repeat gate and the closed
   `mainq -> default.overcommit` seam treated as stable reference lanes rather
   than fresh tuning targets
2. M11: continue to use Apple source and native macOS behavior only as a
   reference lane for future targeted questions, not as a broad compile target
3. M15: revisit deeper integration only if future evidence points to a
   different real gap than the seam now closed by M14

That order gives the project:

1. a precise optimization target inside staged `libdispatch`, instead of
   treating remaining churn as a generic worker-request problem;
2. a way to keep Swift-facing regressions honest without confusing them with a
   now-ruled-out concurrent-lane redirect hypothesis;
3. a better foundation for later macOS comparison, because the comparison lane
   is more useful after the FreeBSD side has an honest explanation for its own
   repeat-lane root redrive.

## Bottom Line

This project should move in stages that are small enough to verify and strong
enough to matter.

The roadmap therefore emphasizes:

1. many explicit milestones instead of vague phases;
2. semantics before optimization;
3. real testing before optimism;
4. macOS comparison as a reference lane, not a trap;
5. a FreeBSD-native end state that still feels meaningfully close to canonical
   `libdispatch` behavior.
