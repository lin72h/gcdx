# M15 TBBX N0 GCD-Only Baseline

## Purpose

This lane records the GCD-only half of the future mixed GCD + oneTBB
oversubscription experiment.

It is condition `A.0`:

1. GCD/libdispatch is active;
2. oneTBB is absent;
3. TCM is absent;
4. no synthetic reserve permit exists;
5. no private pressure SPI is frozen.

The goal is to establish the TWQ pressure shape produced by GCD alone before
comparing against oneTBB-only and mixed-runtime runs.

## Command

The repo-owned wrapper is:

1. `scripts/benchmarks/run-m15-tbbx-n0-gcd-only-baseline.sh`

It intentionally reuses:

1. `scripts/benchmarks/run-m15-pressure-provider-bundle-smoke.sh`

The wrapper captures:

1. `dispatch.pressure`;
2. `dispatch.sustained`.

These are enough for the first GCD-only resource-shape baseline because they
exercise TWQ pressure, sustained admission, block/unblock accounting, and
quiescence through the same bundle artifact TBBX will later consume.

## Boundary

This lane does not introduce a new ABI and does not add TCM vocabulary.

It is a baseline artifact lane only. The underlying pressure-provider bundle
remains a repo-local preview surface.

## What It Can Prove

This lane can prove:

1. the GCD-only pressure bundle remains structurally valid;
2. GCD-only `dispatch.pressure` and `dispatch.sustained` have stable TWQ
   pressure summaries;
3. future mixed-runtime runs can be compared against a known GCD-only shape.

It cannot prove:

1. whether TCM builds on FreeBSD;
2. whether oneTBB uses TCM correctly;
3. whether a reserve permit improves mixed workloads;
4. whether a private pressure SPI should be frozen.

Those are `N1`, `N2`, `N3`, and `N4` respectively.

## Future N3 Comparison

The future mixed workload should compare:

1. `A.0`: GCD-only baseline from this lane;
2. `A.1`: oneTBB-only baseline without GCD;
3. `B`: mixed GCD + oneTBB with TCM disabled;
4. `C`: mixed GCD + oneTBB with TCM enabled and no bridge;
5. `D`: mixed GCD + oneTBB with TCM enabled and the pressure reserve bridge.

The bridge is worth pursuing only if `D` improves over `C` by reducing peak
threads or context switches without materially reducing throughput.
