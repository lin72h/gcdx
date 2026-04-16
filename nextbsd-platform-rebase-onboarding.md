# NextBSD Platform Rebase Onboarding

## Purpose

This note is for the new agent/project that will rebase the remaining
NextBSD-derived Darwin-style platform pieces onto current FreeBSD 15.

Target scope:

1. Mach IPC compatibility;
2. `launchd`, `launchctl`, `liblaunch`, and `launchproxy`;
3. `libnotify`, `notifyd`, and `notifyutil`;
4. ASL logging: `libasl`, `asld`, `aslmanager`, and `aslutil`;
5. the C-first common object runtime substrate;
6. supporting XPC, plist, and binary-plist work where needed by the above.

This is intentionally separate from `GCDX`.

`GCDX` is the kernel-integrated `libdispatch` / `pthread_workqueue` / `TWQ`
project. The new project should not redo that work. It should use the
engineering lessons and test workflow from this repo, then build the remaining
platform services as their own stack.

## Current Local Context

Important local paths:

1. FreeBSD 15 target source tree:
   `/usr/src`
2. NextBSD donor tree:
   `../nx/NextBSD-NextBSD-CURRENT`
3. GCDX working repo:
   `/Users/me/wip-gcd-tbb-fx/wip-codex54x`
4. bhyve guest image currently used by GCDX:
   `/Users/me/wip-gcd-tbb-fx/vm/runs/twq-dev.img`
5. mounted/staged guest root currently used by GCDX:
   `/Users/me/wip-gcd-tbb-fx/vm/runs/twq-dev.root`
6. GCDX benchmark and serial artifacts:
   `/Users/me/wip-gcd-tbb-fx/artifacts`

Do not assume the new project must reuse the `twq-dev` image name. It should
probably create its own image/root names once it starts changing Mach,
launching, logging, or system service boot behavior.

## What GCDX Already Owns

Do not duplicate this work.

GCDX already owns:

1. kernel `TWQ` implementation in `/usr/src/sys/kern/kern_thrworkq.c`;
2. kernel `TWQ` ABI headers under `/usr/src/sys/sys/thrworkq.h`;
3. process/thread lifecycle hooks needed for `pthread_workqueue`;
4. scheduler feedback and block/unblock accounting for workqueue workers;
5. userland `_pthread_workqueue_*` bridge in `/usr/src/lib/libthr`;
6. staged `swift-corelibs-libdispatch` bring-up against custom `libthr`;
7. guest probes that prove `libdispatch` and Swift can drive the kernel-backed
   workqueue path;
8. `M13` performance work around repeated delayed-resume lanes.

Relevant GCDX docs:

1. `TERMINOLOGY.md`
2. `pthread-workqueue-port-plan.md`
3. `pthread-workqueue-testing-strategy.md`
4. `freebsd15-donor-hook-map.md`
5. `m09-libthr-bridge-progress.md`
6. `m10-libdispatch-bringup-progress.md`
7. `m12-swift-delayed-children-boundary-progress.md`
8. `m13-benchmark-baseline-progress.md`
9. `swift-libdispatch-workqueue-integration.md`

The new project may depend on the existence of working dispatch later. It
should not implement another worker-pool strategy, another `_pthread_workqueue`
bridge, or another patched `libdispatch` lane.

Boundary rule:

> If the task is worker admission, dispatch worker backpressure, Swift executor
> validation, or `_pthread_workqueue_*`, it belongs to GCDX. If the task is
> Mach ports, launch jobs, notification service semantics, ASL logging, XPC
> objects, or plist/bplist persistence, it belongs to the new platform rebase.

## Donor Inventory

The NextBSD donor tree has the relevant pieces already separated well enough to
start inventory work.

### Mach IPC

Primary donor paths:

1. `../nx/NextBSD-NextBSD-CURRENT/sys/compat/mach`
2. `../nx/NextBSD-NextBSD-CURRENT/sys/modules/mach`
3. `../nx/NextBSD-NextBSD-CURRENT/sys/sys/mach`
4. `../nx/NextBSD-NextBSD-CURRENT/sys/sys/mach_debug`
5. `../nx/NextBSD-NextBSD-CURRENT/include/mach`
6. `../nx/NextBSD-NextBSD-CURRENT/include/mach_debug`
7. `../nx/NextBSD-NextBSD-CURRENT/lib/libmach`
8. `../nx/NextBSD-NextBSD-CURRENT/usr.bin/migcom`
9. `../nx/NextBSD-NextBSD-CURRENT/usr.bin/mach-tests`

Expected hard part:

1. kernel syscall and compat wiring changed substantially since the donor;
2. lock and proc/thread lifecycle assumptions need to be revalidated against
   FreeBSD 15;
3. Mach message and port object lifetime must be audited under `INVARIANTS`
   and `WITNESS`;
4. `mig`-generated interfaces need to be reproducible and testable, not
   hand-copied blindly.

Recommended first milestone:

1. build a `MACHDEBUG` kernel option/config that compiles and boots with the
   Mach compat module or scaffold present;
2. expose the smallest harmless Mach probe first, such as a version or
   allocation/deallocation smoke path;
3. return controlled `ENOSYS` / `ENOTSUP` for unimplemented operations rather
   than leaving traps ambiguous.

### launchd and liblaunch

Primary donor paths:

1. `../nx/NextBSD-NextBSD-CURRENT/sbin/launchd`
2. `../nx/NextBSD-NextBSD-CURRENT/bin/launchctl`
3. `../nx/NextBSD-NextBSD-CURRENT/lib/liblaunch`
4. `../nx/NextBSD-NextBSD-CURRENT/libexec/launchproxy`
5. `../nx/NextBSD-NextBSD-CURRENT/etc/launchd.d`

Expected hard part:

1. boot integration is dangerous because it can make the guest hard to reach;
2. `launchd` should not replace FreeBSD `init` or `rc` until it can run as a
   contained service manager under a normal boot;
3. service definitions may use plist or JSON-like donor formats that need a
   clear FreeBSD-native policy.

Recommended first milestone:

1. build `liblaunch`, `launchd`, and `launchctl` as staged userland artifacts;
2. run `launchd` in non-PID-1 test mode inside the guest;
3. use a single test job with a deterministic stdout/stderr marker;
4. only after that, evaluate whether any boot-level integration is justified.

### libnotify and notifyd

Primary donor paths:

1. `../nx/NextBSD-NextBSD-CURRENT/lib/libnotify`
2. `../nx/NextBSD-NextBSD-CURRENT/usr.sbin/notifyd`
3. `../nx/NextBSD-NextBSD-CURRENT/usr.bin/notifyutil`
4. `../nx/NextBSD-NextBSD-CURRENT/etc/launchd.d/com.apple.notifyd.json`

Recommended staged semantics:

1. implement and test `notify_register_check()` and `notify_check()` first;
2. then test state operations: `notify_set_state()` and `notify_get_state()`;
3. then test file-descriptor or signal delivery;
4. defer Mach-port notification delivery until the Mach IPC layer is real;
5. defer dispatch delivery until the service-level semantics are correct.

Important boundary:

`notify_register_dispatch()` may eventually consume working `libdispatch`, but
it must not carry a private worker pool or duplicate GCDX.

### ASL

Primary donor paths:

1. `../nx/NextBSD-NextBSD-CURRENT/lib/libasl`
2. `../nx/NextBSD-NextBSD-CURRENT/usr.sbin/asl`
3. `../nx/NextBSD-NextBSD-CURRENT/usr.sbin/aslmanager`
4. `../nx/NextBSD-NextBSD-CURRENT/usr.bin/aslutil`
5. `../nx/NextBSD-NextBSD-CURRENT/etc/asl.conf`

Recommended first milestone:

1. build `libasl` as a staged library;
2. run a local in-process ASL message create/retain/release/query test;
3. run `asld` as a contained daemon in the guest;
4. write one log message and query it through `aslutil`;
5. do not route core kernel logging or system logging through ASL until the
   daemon and store behavior are repeatable.

### Common Object Runtime, XPC, plist, and bplist

Primary donor paths:

1. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc`
2. `../nx/NextBSD-NextBSD-CURRENT/lib/libasl/asl_object.c`
3. `../nx/NextBSD-NextBSD-CURRENT/lib/libasl/asl_object.h`
4. `../nx/NextBSD-NextBSD-CURRENT/release/scripts/mtree-to-plist.awk`

Related local handoff already written:

1. `zig-c-common-object-runtime-handoff.md`
2. `zig-c-blocks-sidecar-handoff.md`

Current recommendation:

1. treat the common object runtime as a C-first lifetime and type-tag
   substrate;
2. do not make Objective-C mandatory;
3. support explicit retain/release, type identity, equality/hash hooks, and
   finalizers before language overlays;
4. treat plist/bplist as serialization of a restricted value graph above the
   object substrate, not as the object runtime itself;
5. keep Blocks integration at the C ABI boundary and coordinate with the
   Zig/C sidecar.

This common-object work is a shared foundation for `libxpc`, `libasl`, and
potentially dispatch-style objects, but the new project should not refactor
GCDX dispatch objects unless there is a separate explicit agreement.

## Reusable bhyve Methodology

The most valuable reusable asset from GCDX is the host-side build, stage, boot,
probe, and serial-capture loop.

Existing scripts to study:

1. `scripts/bhyve/stage-guest.sh`
2. `scripts/bhyve/run-guest.sh`
3. `scripts/bhyve/collect-crash.sh`
4. `scripts/benchmarks/run-m13-baseline.sh`
5. `elixir/lib/twq_test/vm.ex`

Do not copy them blindly. They are currently TWQ/GCDX-shaped. Copy the
workflow and factor out the project-specific pieces.

### 1. Use an alternate kernel slot

GCDX uses:

1. kernel config name: `TWQDEBUG`;
2. install slot: `/boot/TWQDEBUG`;
3. `INSTKERNNAME=TWQDEBUG`;
4. `NO_MODULES=yes`;
5. loader setting: `kernel="TWQDEBUG"`;
6. module path:
   `module_path="/boot/kernel;/boot/modules;/boot/TWQDEBUG"`.

For the new project, use a separate config name such as `MACHDEBUG` or
`NXPLATFORMDEBUG`. Do not overwrite `/boot/kernel` during early work.

Reason:

1. the guest remains recoverable;
2. the stock module tree remains available;
3. failed custom kernels can be replaced from the host;
4. serial logs clearly show which kernel booted.

### 2. Keep artifacts outside the repo

GCDX keeps large build products and logs outside the git repo:

1. kernel objdir: `/tmp/twqobj`
2. libthr objdir: `/tmp/twqlibobj`
3. VM image/root: `/Users/me/wip-gcd-tbb-fx/vm/runs/...`
4. benchmark logs: `/Users/me/wip-gcd-tbb-fx/artifacts/...`

The new project should do the same with its own names, for example:

1. `/tmp/nxplatform-obj`
2. `/tmp/nxplatform-userland-obj`
3. `/Users/me/wip-gcd-tbb-fx/vm/runs/nxplatform-dev.img`
4. `/Users/me/wip-gcd-tbb-fx/artifacts/nxplatform/...`

### 3. Use serial-first validation

Every guest test should emit structured markers:

1. `=== nxplatform probe start ===`
2. one JSON line per probe result;
3. `=== nxplatform probe end ===`

This keeps the host harness simple:

1. boot guest;
2. wait for the end marker;
3. destroy the VM;
4. parse serial output;
5. fail on missing markers, timeout, or malformed JSON.

### 4. Prefer rc-script probes before boot integration

The safe early model is:

1. stage binaries into `/root/nxplatform/`;
2. install a small `/etc/rc.d/nxplatform_probe` script;
3. run probes after normal FreeBSD boot;
4. power off the guest after probes finish.

Do not replace PID 1, system logging, or notification delivery during the
first milestones. Test as ordinary staged services first.

### 5. Always keep stock controls

Each feature should have at least two lanes:

1. stock FreeBSD guest, proving the feature is absent or returns controlled
   failure;
2. custom kernel/userland guest, proving the new behavior is present.

For userland-only pieces, keep a third lane when possible:

1. staged libraries with stock kernel;
2. staged libraries with custom kernel;
3. full staged stack.

This prevents false positives where a userland fallback works but the intended
kernel IPC path is not used.

## Suggested Initial Roadmap

### M00: Repo and Inventory Baseline

Deliverables:

1. initialize the new repo;
2. record source tree locations;
3. generate a donor inventory from `../nx/NextBSD-NextBSD-CURRENT`;
4. classify files as kernel, library, daemon, tool, test, config, or docs;
5. explicitly mark GCDX/TWQ files out of scope.

Exit criteria:

1. no ambiguity about which files belong to this project;
2. no accidental plan to redo `pthread_workqueue`.

### M01: bhyve Harness Skeleton

Deliverables:

1. clone/adapt `stage-guest.sh` and `run-guest.sh`;
2. use a project-specific kernel slot;
3. create a minimal guest rc probe;
4. emit structured JSON over serial;
5. add a host parser.

Exit criteria:

1. the stock guest boots and runs a no-op probe;
2. the custom guest boots and proves the alternate kernel slot is active;
3. the host can detect timeout, missing marker, and nonzero probe status.

### M02: Mach Scaffold

Deliverables:

1. identify modern FreeBSD 15 syscall/module hook points;
2. add a feature-gated Mach scaffold;
3. compile and boot a debug kernel;
4. run a userland Mach smoke probe that distinguishes stock from custom.

Exit criteria:

1. custom kernel returns controlled results for implemented and unimplemented
   Mach calls;
2. invalid calls fail predictably;
3. no panic under `INVARIANTS` and `WITNESS`.

### M03: libmach and MIG Tooling

Deliverables:

1. build `libmach` against the staged headers;
2. define how `migcom` output is generated and checked in or generated;
3. compile a minimal Mach client probe;
4. run `mach-tests` only after smaller probes are stable.

Exit criteria:

1. a small client can allocate/deallocate or otherwise exercise a safe Mach
   object path;
2. generated interfaces are reproducible.

### M04: notifyd / libnotify

Deliverables:

1. build `libnotify`, `notifyd`, and `notifyutil`;
2. test check-token delivery;
3. test state set/get;
4. test FD or signal delivery;
5. defer Mach-port delivery until Mach IPC is proven.

Exit criteria:

1. `notifyutil` can post and observe a notification in the guest;
2. daemon lifecycle is deterministic under the rc probe harness;
3. no dispatch-specific code path creates a duplicate worker model.

### M05: ASL Logging

Deliverables:

1. build `libasl`, `asld`, `aslmanager`, and `aslutil`;
2. run in-process object and message tests;
3. run contained daemon store/query tests;
4. collect log store artifacts after each guest run.

Exit criteria:

1. one test message can be written and queried;
2. daemon startup and shutdown are repeatable;
3. failures are visible in serial output and copied artifacts.

### M06: launchd as a Contained Service Manager

Deliverables:

1. build `liblaunch`, `launchd`, `launchctl`, and `launchproxy`;
2. run `launchd` outside PID 1 mode;
3. load one deterministic test job;
4. prove stdout/stderr and exit status propagation.

Exit criteria:

1. `launchctl` can load and inspect a job;
2. the job runs and exits with expected status;
3. the guest still boots through normal FreeBSD init/rc.

### M07: Common Object Runtime and XPC

Deliverables:

1. define the C object ABI;
2. align `libxpc` and `libasl` object lifetime with it;
3. add retain/release/type tests;
4. add plist/bplist value graph tests where needed.

Exit criteria:

1. common object tests pass without ObjC;
2. `xpc_object_t` and `asl_object_t` behavior is deterministic;
3. plist/bplist round trips are tested as serialization, not confused with the
   object runtime itself.

## What To Avoid

Avoid these failure modes:

1. importing NextBSD wholesale into `/usr/src` without first reducing it to a
   compile/boot scaffold;
2. replacing FreeBSD boot or logging paths before contained daemon tests pass;
3. reimplementing `pthread_workqueue`, `TWQ`, or staged `libdispatch`;
4. making Objective-C mandatory for common object runtime work;
5. treating plist/bplist as the object runtime instead of a serialization
   layer;
6. adding Mach vocabulary into GCDX/TWQ;
7. assuming `notify_register_dispatch()` validates dispatch itself;
8. relying on manual guest inspection instead of serial JSON probes.

## Concrete First Task For The New Agent

Do this first:

1. create a donor inventory table for:
   `sys/compat/mach`,
   `sys/modules/mach`,
   `include/mach`,
   `lib/libmach`,
   `usr.bin/migcom`,
   `sbin/launchd`,
   `lib/liblaunch`,
   `lib/libnotify`,
   `usr.sbin/notifyd`,
   `lib/libasl`,
   `usr.sbin/asl`,
   `lib/libxpc`;
2. classify each file as direct-port, rewrite, reference-only, or defer;
3. propose the smallest `MACHDEBUG` scaffold that can boot in bhyve;
4. clone/adapt the GCDX bhyve scripts under new names and produce a no-op
   serial JSON probe;
5. stop before importing large kernel code if the donor assumptions do not
   match FreeBSD 15 hook points.

The new project should earn its first milestone by proving the harness and a
custom kernel slot, not by landing a large untested donor diff.

## Coordination With GCDX

Use GCDX as:

1. a known-good example of FreeBSD 15 kernel iteration in bhyve;
2. a source of reusable staging and serial-log patterns;
3. the owner of kernel-integrated dispatch semantics;
4. a future dependency for `notify_register_dispatch()` or launch-related
   dispatch usage.

Do not use GCDX as:

1. a place to land Mach IPC changes;
2. a place to land launchd or ASL daemons;
3. an excuse to change `TWQ` for Mach/launchd needs;
4. a substitute for the new project's own guest harness and regression lane.

The clean long-term shape is:

1. GCDX provides kernel-integrated dispatch;
2. the new NextBSD platform rebase provides Mach/launch/notify/ASL/XPC/common
   object services;
3. both stacks are independently testable in bhyve;
4. integration happens only after each stack has its own passing validation
   lane.
