# Elixir Harness

This directory contains the primary host-side test harness for the
`pthread_workqueue` project.

## Current commands

Run formatting:

```sh
make -C elixir format
```

Run the ExUnit suite:

```sh
make -C elixir test
```

The M13 Zig hot-path baseline is now visible to ExUnit through
`TwqTest.ZigHotpath`. The default unit suite validates the checked-in baseline
shape, lifecycle counter invariants, and comparator behavior without booting a
VM. The current six-mode gate baseline is:

```text
../benchmarks/baselines/m13-zig-hotpath-suite-20260416.json
```

The warmed-worker wake benchmark baseline is also visible to ExUnit through
`TwqTest.WorkqueueWake`. The current wake suite baseline is:

```text
../benchmarks/baselines/m13-workqueue-wake-suite-20260416.json
```

The full one-boot low-level floor is now visible through `TwqTest.LowlevelBench`.
The current combined suite baseline is:

```text
../benchmarks/baselines/m13-lowlevel-suite-20260416.json
```

The checked-in M14 stop/tune decision is also visible to ExUnit through
`TwqTest.M14Comparison`. The current repo-owned comparison inputs are:

```text
../benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json
../benchmarks/baselines/m14-macos-stock-introspection-20260416.json
```

The focused FreeBSD repeat-lane regression gate is also visible to ExUnit
through `TwqTest.RepeatLane`. That gate compares generated or checked-in
schema-3 repeat artifacts against:

```text
../benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json
```

The post-M13 full-matrix crossover closeout lane is also visible through
`TwqTest.VM.run_m13_crossover_assessment/1`. The current checked-in crossover
baseline is:

```text
../benchmarks/baselines/m13-crossover-full-20260417.json
```

The top-level `M13` closeout decision is also visible through
`TwqTest.VM.run_m13_closeout/1`. That wrapper composes:

```text
run-m13-lowlevel-gate.sh
run-m13-repeat-gate.sh
run-m13-crossover-assessment.sh
```

into one closeout manifest and verdict.

The post-`M13` pressure-provider prep lane is also visible through
`TwqTest.PressureProvider` and `TwqTest.VM.run_m15_pressure_provider_prep/1`.
The current checked-in derived baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-20260417.json
```

This lane is intentionally pressure-only. It validates the derived boundary
that future consumers can build against, but it does not claim that a live
provider SPI already exists. The current boundary uses
`nonidle_workers_current = total_workers_current - idle_workers_current` as the
effective current-pressure signal and retains raw `active_workers_current` only
as supporting detail.

The machine-readable contract for that boundary is also visible through
`TwqTest.PressureProviderContract`. The checked-in contract is:

```text
../benchmarks/contracts/m15-pressure-provider-contract-v1.json
```

The guest-side live pressure smoke lane is also visible through
`TwqTest.LivePressureProvider` and
`TwqTest.VM.run_m15_live_pressure_provider_smoke/1`. The current checked-in
live baseline is:

```text
../benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json
```

This lane is still pressure-only and still not a provider SPI. It exists to
validate the live probe-scoped shape with real generation numbers and real
monotonic timestamps for `dispatch.pressure` and `dispatch.sustained`. The
current live comparator treats `final_total_workers_current` and
`final_nonidle_workers_current` as the quiescence signal; raw
`active_workers_current` is retained only for continuity with the underlying
`kern.twq.*` view.

The raw preview pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderPreview` and
`TwqTest.VM.run_m15_pressure_provider_preview_smoke/1`. The current checked-in
preview baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json
```

This preview lane stays below any SPI claim. It validates the repo-local raw
snapshot v1 shape with real generation and real monotonic time, while keeping
the pressure-only rule frozen on `nonidle_workers_current`.

The aggregate adapter pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderAdapter` and
`TwqTest.VM.run_m15_pressure_provider_adapter_smoke/1`. The current checked-in
adapter baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json
```

This adapter lane still does not claim a SPI. It validates a versioned
aggregate-only C view above the raw preview snapshot and below any real system
surface.

The callable session pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderSession` and
`TwqTest.VM.run_m15_pressure_provider_session_smoke/1`. The current checked-in
session baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json
```

This session lane still does not claim a system SPI. It validates a versioned
callable session surface that owns the base snapshot and generation sequencing
while returning the same aggregate-only pressure view.

The observer pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderObserver` and
`TwqTest.VM.run_m15_pressure_provider_observer_smoke/1`. The current
checked-in observer baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json
```

This observer lane still does not claim an integration surface. It validates a
policyless consumer-side summary above the callable session surface, keeping
the pressure-only boundary intact while proving that quiescence and backlog
state can be tracked without promoting per-bucket diagnostics.

The host-side observer replay lane is also visible through
`TwqTest.VM.run_m15_pressure_provider_observer_replay/1`. It derives an
observer candidate from the checked-in session artifact and compares it
against the checked-in observer baseline without booting a guest.

The tracker pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderTracker` and
`TwqTest.VM.run_m15_pressure_provider_tracker_smoke/1`. The current checked-in
tracker baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json
```

This tracker lane still does not claim an integration surface. It validates a
policyless transition summary above the callable session surface, keeping the
pressure-only boundary intact while proving that the session artifact can
support edge-count tracking without promoting queue or per-bucket semantics.

The host-side tracker replay lane is also visible through
`TwqTest.VM.run_m15_pressure_provider_tracker_replay/1`. It derives a tracker
candidate from the checked-in session artifact and compares it against the
checked-in tracker baseline without booting a guest.

The bundle pressure-provider smoke lane is also visible through
`TwqTest.PressureProviderBundle` and
`TwqTest.VM.run_m15_pressure_provider_bundle_smoke/1`. The current checked-in
bundle baseline is:

```text
../benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json
```

This bundle lane still does not claim an integration surface. It validates a
callable preview that polls the session once and updates observer and tracker
summaries from that same aggregate view, which is the shape TBBX can consume
above the provider line without introducing TCM vocabulary below it.

The host-side bundle replay lane is also visible through
`TwqTest.VM.run_m15_pressure_provider_bundle_replay/1`. It derives a bundle
candidate from the checked-in session artifact and compares it against the
checked-in bundle baseline without booting a guest.

The TBBX `N0` GCD-only baseline wrapper is visible through
`TwqTest.VM.run_m15_tbbx_n0_gcd_only_baseline/1`. It reuses the checked-in
bundle lane as condition `A.0`: GCD active, oneTBB absent, TCM absent, and no
pressure bridge. This is a baseline artifact lane only, not a new provider
surface.

The top-level pressure-provider stack gate is also visible through
`TwqTest.VM.run_m15_pressure_provider_stack_gate/1`. It composes the derived
prep, live, preview, adapter, session, observer, tracker, bundle, replay, and
contract lanes into one repo-owned readiness verdict while still staying below
any real SPI claim.

To run the real guest suites from Elixir code, use
`TwqTest.Zig.run_hotpath_suite/1` for the raw syscall lane and
`TwqTest.Workqueue.run_wake_suite/1` for the warmed-worker wake lane, with the
normal `TWQ_VM_IMAGE` and `TWQ_GUEST_ROOT` environment configured. Those paths
still boot `bhyve`; the unit tests only exercise artifact parsing,
comparison logic, and host-side build wrappers.

The wake benchmark currently uses the same normalization and comparison policy
surface through `TwqTest.WorkqueueWake.compare/3`, so both low-level lanes stay
aligned on exact counter gating and coarse guest-latency tolerance. The
combined low-level artifact reuses those same child comparators through
`TwqTest.LowlevelBench.compare/3`.

For the Swift-first M14 comparison lane, `TwqTest.Swift.run_m14_comparison/1`
wraps the repo-owned shell lane. If `m14_freebsd_json:` is provided, that path
reuses the checked-in FreeBSD reference instead of booting a guest.

For the focused FreeBSD repeat guard, `TwqTest.VM.run_m13_repeat_gate/1` wraps
the repo-owned shell lane. The repeat comparator aligns per-round libdispatch
delta series by actual round number, so sparse-but-valid snapshot series from a
guest run do not create false failures.

For the broad closeout lane, `TwqTest.VM.run_m13_crossover_assessment/1` wraps
the repo-owned `M13.5` shell lane. That comparator treats shared-absent
metrics, such as `thread_return_count` on `dispatch.basic` and
`dispatch.pressure`, as not-applicable rather than as a failure.

For the full milestone decision, `TwqTest.VM.run_m13_closeout/1` wraps the
repo-owned top-level closeout script. In reuse mode it can validate the
composed shell workflow without booting a guest by passing the checked-in
candidate paths for the three child lanes.

For the post-`M13` provider-prep lane,
`TwqTest.VM.run_m15_pressure_provider_prep/1` wraps the repo-owned shell lane.
In reuse mode it derives the pressure-only view from the checked-in crossover
baseline instead of booting a guest again.

For the live pressure smoke lane,
`TwqTest.VM.run_m15_live_pressure_provider_smoke/1` wraps the repo-owned shell
lane. In reuse mode it can validate the checked-in live baseline against
itself without booting a guest; without a candidate override it stages the
guest probe, boots `bhyve`, extracts the live capture artifact, and compares
it against the checked-in live baseline.

For the raw preview smoke lane,
`TwqTest.VM.run_m15_pressure_provider_preview_smoke/1` wraps the repo-owned
shell lane. In reuse mode it can validate the checked-in preview baseline
against itself without booting a guest; without a candidate override it stages
the raw preview probe, boots `bhyve`, extracts the preview capture artifact,
and compares it against the checked-in preview baseline.

For the observer smoke lane,
`TwqTest.VM.run_m15_pressure_provider_observer_smoke/1` wraps the repo-owned
shell lane. In reuse mode it can validate the checked-in observer baseline
against itself without booting a guest; without a candidate override it stages
the observer probe, boots `bhyve`, extracts the observer artifact, and
compares it against the checked-in observer baseline. The observer artifact
now records the callable session surface as an explicit source, not just the
aggregate view it consumes.

For the observer replay lane,
`TwqTest.VM.run_m15_pressure_provider_observer_replay/1` wraps the repo-owned
host-only shell lane. It derives an observer candidate from the checked-in
session artifact and compares it against the checked-in observer baseline
without a guest boot.

For the bundle smoke lane,
`TwqTest.VM.run_m15_pressure_provider_bundle_smoke/1` wraps the repo-owned
shell lane. In reuse mode it can validate the checked-in bundle baseline
against itself without booting a guest; without a candidate override it stages
the bundle probe, boots `bhyve`, extracts the bundle artifact, and compares it
against the checked-in bundle baseline.

For the bundle replay lane,
`TwqTest.VM.run_m15_pressure_provider_bundle_replay/1` wraps the repo-owned
host-only shell lane. It derives a bundle candidate from the checked-in
session artifact and compares it against the checked-in bundle baseline
without a guest boot.

For the TBBX `N0` GCD-only baseline lane,
`TwqTest.VM.run_m15_tbbx_n0_gcd_only_baseline/1` wraps the repo-owned shell
lane. In reuse mode it validates an existing bundle artifact, and without a
candidate override it runs the bundle smoke lane against `dispatch.pressure`
and `dispatch.sustained` to capture the GCD-only pressure shape.

For the top-level stack gate,
`TwqTest.VM.run_m15_pressure_provider_stack_gate/1` wraps the repo-owned shell
lane. In its default mode it reuses the checked-in live-family baselines,
re-derives the provider view from the checked-in crossover artifact, runs the
observer/tracker/bundle replay lanes from the checked-in session artifact, and
then validates the actual artifact paths used by the stack through the shared
contract lane.

For the session smoke lane,
`TwqTest.VM.run_m15_pressure_provider_session_smoke/1` wraps the repo-owned
shell lane. In reuse mode it can validate the checked-in session baseline
against itself without booting a guest; without a candidate override it stages
the session probe, boots `bhyve`, extracts the session artifact, and compares
it against the checked-in session baseline.

For the machine-readable pressure contract,
`TwqTest.PressureProviderContract.validate/3` checks the derived, live,
adapter, session, observer, tracker, bundle, or preview artifact family
against the checked-in contract file. This keeps the boundary
self-describing without claiming that it is already a callable provider SPI.

The default suite covers `should-narrow`, constrained and overcommit
`reqthreads`, `thread-enter`, `thread-return`, and `thread-transfer`.
Counter deltas are gated exactly by default; latency drift is intentionally
coarse (`3.0x` plus `1000ns`) because the normal lane runs in a WITNESS-enabled
bhyve guest.

## OTP note for this host

The installed Elixir was built against Erlang/OTP 28 while the default `erl`
on this machine is OTP 26.

The local wrapper commands in `Makefile` solve this by preferring:

```text
/usr/local/lib/erlang28/bin
```

That keeps the workaround local to the harness instead of modifying the host
globally.
