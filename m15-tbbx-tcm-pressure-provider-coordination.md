# M15 TBBX / TCM Pressure Provider Coordination

## Purpose

This note records the GCDX-side response to the TBBX open TCM integration
plan in:

1. `../wip-tbb-gpt54x/docs/TBBX-open-TCM-GCDX-integration-plan.md`
2. `../wip-tbb-gpt54x/docs/TBBX-PlanC.md`

The useful conclusion from the TBBX side is correct: open TCM should remain a
user-space coordination layer above GCDX / `pthread_workqueue` / TWQ. It should
consume aggregate platform pressure facts, not become part of TWQ or libthr's
worker-admission mechanism.

After review against the open TCM source shape, this boundary is stronger than
just a preference:

1. TCM is process-local user-space policy built around permits, callbacks,
   C++ containers, `std::mutex`, and hwloc topology state;
2. its platform input is already modeled as platform facts constraining a
   resource pool, not as scheduler mechanism;
3. its grant engine negotiates permits, so external TWQ pressure should enter
   TCM as another permit participant, not as a TWQ or kernel callback.

The GCDX answer is therefore: keep TWQ as mechanism, expose pressure facts
upward, and let TBBX/TCM translate those facts into TCM-native policy.

## GCDX Boundary

The lower provider line is GCDX/TWQ-owned.

For this repo that means:

1. no `tcm.h` include below the provider line;
2. no TCM permit handles, permit states, grant counts, or callbacks in TWQ,
   `pthread_workqueue`, or the pressure-provider C surface;
3. no `if (tcm_present)` branches in GCDX mechanism code;
4. no synthetic reserve permit in this repo's lower mechanism;
5. aggregate pressure facts only for the current provider version.

TBBX may translate the GCDX facts into a TCM policy object on its side. That is
an adapter concern above the line.

## Snapshot ABI Reading

The TBBX sketch:

```c
struct tbbx_twq_pressure_snapshot_v1 {
    uint32_t struct_size;
    uint32_t version;
    uint64_t generation;
    uint64_t timestamp_ns;

    uint32_t ncpu;
    uint32_t requested_workers;
    uint32_t admitted_workers;
    uint32_t active_workers;
    uint32_t blocked_workers;
    uint32_t idle_workers;
    uint32_t narrowed_workers;
    uint32_t pressure_state;

    uint32_t consumed_capacity_1024;
    uint32_t reserved[7];
};
```

is compatible with the direction of the current M15 provider stack as an
adapter-side projection, but GCDX should not adopt the `tbbx_` name below the
provider line. The GCDX-owned surface should stay in the
`twq_pressure_provider_*` namespace while it is a repo-local preview, and in a
future private libthr SPI it should use a pthread/workqueue-owned name.

Current local mapping:

1. `struct_size`, `version`, `generation`, and monotonic timestamp already
   exist in `twq_pressure_provider_view_v1` and the callable session family.
2. `requested_workers` maps to `requested_workers_total`.
3. `admitted_workers` maps to `admitted_workers_total`.
4. `active_workers` remains diagnostic; the effective current-pressure signal
   is `nonidle_workers_current = total_workers_current - idle_workers_current`.
5. `blocked_workers` maps to `block_backlog_total` for aggregate pressure.
6. `idle_workers` maps to `idle_workers_current`.
7. `narrowed_workers` should stay as feedback, currently represented by
   `should_narrow_true_total` and `has_narrow_feedback`.
8. `pressure_state` should be an adapter classification above the current
   pressure-only surface, not a new lower-layer policy enum in v1.
9. `consumed_capacity_1024` is a TCM-facing policy projection and should be
   derived above the provider line until a native capacity provider exists.

The important ABI rule is still `struct_size` first. The provider fills only
the fields the caller's size can hold once this becomes a real private SPI.

## Minimal Private SPI Shape

The current `twq_pressure_provider_*` structs are preview artifacts for
validation, not the final libthr ABI. If this graduates into a private
pthread/workqueue SPI, the smaller v1 shape should be:

```c
struct _pthread_workqueue_pressure_snapshot_v1 {
    size_t   struct_size;        /* Primary ABI gate. */
    uint32_t version;            /* Informational; branch on struct_size. */
    uint32_t _pad0;              /* Keep generation aligned. */
    uint64_t generation;         /* Provider-owned monotonic sequence. */
    uint64_t timestamp_ns;       /* CLOCK_MONOTONIC at capture. */

    uint32_t total_workers;      /* Instantaneous TWQ worker count. */
    uint32_t idle_workers;       /* Instantaneous idle TWQ workers. */
    uint32_t nonidle_workers;    /* Primary external-consumption signal. */

    uint32_t requested_workers;  /* Cumulative provider counter. */
    uint32_t admitted_workers;   /* Cumulative provider counter. */
    uint32_t blocked_workers;    /* Cumulative block events. */
    uint32_t unblocked_workers;  /* Cumulative unblock events. */
    uint32_t narrowed_events;    /* Cumulative narrowing feedback. */

    uint32_t reserved[6];        /* Zeroed by provider. */
};

int __pthread_workqueue_pressure_snapshot_np(
    struct _pthread_workqueue_pressure_snapshot_v1 *snapshot);
```

The repo now carries this as a candidate handoff header in
`csrc/pthread_workqueue_pressure_snapshot_np.h`, plus a standalone probe and
demand-projection helper. Those files make the field contract compile-testable
without installing or freezing the real libthr SPI.

Provider rules:

1. caller zeros the struct and sets `struct_size`;
2. provider fills only complete fields covered by `struct_size`;
3. provider zeros reserved fields;
4. `version` is informational, not the compatibility branch point;
5. gauges are instantaneous and suitable for policy;
6. cumulative counters are diagnostics and must not be treated as current
   consumption;
7. cumulative `uint32_t` counters may wrap, so consumers must compute deltas
   with unsigned wrapping arithmetic;
8. `generation == 0` means no provider data has been captured yet;
9. the initial private SPI is LP64-only in practice, matching the current
   FreeBSD 15 target.

Intentionally excluded from v1:

1. `pressure_state`;
2. `consumed_capacity_1024`;
3. TCM permit count or grant state;
4. callbacks or callback state;
5. per-QoS policy decisions;
6. topology or CPU-kind state.

## Synthetic Reserve Permit

The synthetic reserve permit is the right TCM-side integration mechanism.

It should live entirely in TCM or a TBBX-owned TCM adapter:

```text
GCDX/TWQ aggregate pressure
  -> GCDX-owned pressure snapshot
  -> TBBX/TCM adapter projection
  -> private TCM reserve permit demand
  -> normal TCM renegotiation and callbacks
```

This lets TCM reuse its own grant, renegotiation, and callback machinery while
GCDX remains unaware of TCM. That is the correct layering.

The GCDX provider must not emit permit counts or reserve-permit hints. It should
emit enough aggregate pressure to let TBBX compute an external consumption
number outside the lower mechanism.

The important implementation correction is that the first reserve-permit
experiment should not require TCM source changes. A TBBX-owned adapter can use
the public TCM API as a normal client:

```c
static tcm_result_t
reserve_noop_callback(tcm_permit_handle_t permit, void *arg,
    tcm_callback_flags_t flags)
{
    return TCM_RESULT_SUCCESS;
}

tcm_client_id_t reserve_client;
tcm_permit_handle_t reserve_permit = NULL;

tcmConnect(reserve_noop_callback, &reserve_client);

/* On pressure update. */
tcm_permit_request_t req = TCM_PERMIT_REQUEST_INITIALIZER;
req.min_sw_threads = demand;
req.max_sw_threads = demand;
req.flags.rigid_concurrency = 1;
tcmRequestPermit(reserve_client, req, NULL, &reserve_permit, NULL);
```

`demand` should initially be derived from `nonidle_workers_current`, capped by
TCM's platform concurrency. Smoothing, hold-down timers, and quantization are
adapter policy and must stay above the provider line.

The reserve client must be separate from oneTBB's normal TCM client. Sharing a
client would force the oneTBB callback path to distinguish arena permits from
the synthetic reserve permit. A separate client with a no-op callback keeps the
reserve participant isolated.

The adapter should be a sidecar library, not a TCM patch and not a separate
process. A reasonable shape is `libtbbx_twq_bridge.so`: it links to TCM, reads
the private pressure SPI once that SPI exists, and owns the reserve permit
lifecycle.

Adapter lifecycle rules:

1. if TCM is unavailable or disabled, the adapter must degrade to demand zero
   and must not fail the process;
2. if `TCM_ENABLE=1` is required for reliable TCM initialization, document that
   environment requirement and avoid surprising stderr suggestions from load
   order;
3. when `demand > 0`, request a rigid reserve permit with
   `min_sw_threads == max_sw_threads == demand`;
4. when `demand == 0`, deactivate the existing permit with
   `tcmDeactivatePermit` instead of repeatedly requesting a zero-sized permit;
5. keep the permit handle alive across zero-demand periods to avoid
   release/recreate churn;
6. for the first experiment, use no smoothing so raw demand behavior and any
   oscillation are visible.

For a first inactive-then-activate implementation, the adapter may also create
the permit with `request_as_inactive = 1`, then move it into service with
`tcmActivatePermit` once nonzero demand is observed. The important rules are
the same: no NULL callback, separate client, rigid reserve demand, and
`tcmDeactivatePermit` on zero demand.

If raw reserve demand oscillates in `N3`, smoothing remains adapter policy. The
order should be: quantize demand first, then hold-down on demand reductions,
then generation-based debounce if needed.

## Known Limitation: Trigger Latency

The v1 bridge is polling-driven unless TBBX adds its own adapter thread.
TCM is event-driven; if oneTBB is idle and GCD pressure changes, there may be
no TCM permit request or renegotiation event to force a fresh poll.

This is acceptable for the first proof, but it is not a complete long-term
notification story. The v2-compatible improvement is still one-way:

```text
TWQ pressure generation changed
  -> adapter wakes or polls sooner
  -> adapter updates reserve permit
```

It must not become a callback from TCM into TWQ, and TWQ must not call into
TCM.

## Current GCDX Work Item

The current M15 stack already has the right pieces below a real SPI claim:

1. raw preview snapshot;
2. aggregate adapter view;
3. callable session that owns base snapshot and generation sequencing;
4. observer summary;
5. transition tracker summary;
6. callable bundle that polls the session once and updates observer plus
   tracker from the same view;
7. stack gate and contract validation.

That gives TBBX a stable aggregate polling artifact for early adapter testing
without turning the artifact into a public ABI.

## Next Milestones

The next work should not widen TWQ. The critical path is:

1. `N0`: establish GCD-only and oneTBB-only baselines before coordination, so
   later mixed results are not compared against an unknown single-runtime
   shape;
2. `N1`: build open TCM on FreeBSD, including hwloc2 availability and clean
   non-Linux handling for Linux-only cgroup tests;
3. `N2`: verify oneTBB loads and uses open TCM on FreeBSD through its normal
   adaptor path;
4. `N3`: run a mixed GCD + oneTBB oversubscription baseline with TCM off, TCM
   on without pressure bridge, and TCM on with the pressure bridge;
5. `N4`: only after `N3` proves the bridge is needed, freeze the private
   snapshot SPI and wire the TBBX reserve-permit adapter to it.

`N3` is the decision point. If TCM alone already solves the observed
oversubscription, the pressure bridge is an optimization. If TCM alone does
not help because GCD/TWQ pressure dominates, the pressure bridge is the next
high-value integration step.

## Stop Rule

If TBBX needs fields that require TCM policy vocabulary below the provider
line, the answer is no for this provider version. The correct fix is a
TBBX-side projection or a new upper-layer adapter, not widening TWQ or
`pthread_workqueue` into a TCM-aware mechanism.

Additional stop rules:

1. if reserve-permit updates oscillate under mixed workloads, fix smoothing in
   the adapter before changing TWQ;
2. if the bridge gives no improvement over TCM-only in `N3`, do not add SPI
   complexity for no measured value;
3. if TCM requires bidirectional callbacks into libthr or TWQ, reject that
   path for FreeBSD;
4. if a future oneTBB worker pool starts using `pthread_workqueue` directly,
   reassess double-counting before treating all TWQ nonidle workers as
   external pressure;
5. if the uncoordinated `N3` baseline already has acceptable thread counts and
   throughput, close the bridge work as unnecessary for now;
6. if `TCM_ENABLE` or adapter load-order requirements create deployment
   friction larger than the measured gain, do not force the bridge into the
   default path.
