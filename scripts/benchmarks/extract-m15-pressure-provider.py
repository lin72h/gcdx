#!/usr/bin/env python3
"""Derive a pressure-only provider view from a schema-3 crossover artifact."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


MODE_ORDER = [
    "dispatch.basic",
    "dispatch.pressure",
    "dispatch.burst-reuse",
    "dispatch.timeout-gap",
    "dispatch.sustained",
    "dispatch.main-executor-resume-repeat",
    "swift.dispatch-control",
    "swift.mainqueue-resume",
    "swift.dispatchmain-taskhandles-after-repeat",
]

CONTRACT = {
    "name": "twq_pressure_provider",
    "version": 1,
    "current_signal_field": "nonidle_workers_current",
    "current_signal_kind": "total_minus_idle",
    "quiescence_kind": "total_and_nonidle_zero",
    "per_bucket_scope": "diagnostic_only",
    "diagnostic_fields": ["active_workers_current"],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_artifact", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def metric_value(delta: dict, key: str):
    if key in delta:
        return delta[key]
    qualified = f"kern.twq.{key}"
    return delta.get(qualified)


def sum_if_list(value):
    if isinstance(value, list):
        return sum(item for item in value if isinstance(item, (int, float)))
    return None


def nonnegative_delta(lhs, rhs):
    if lhs is None or rhs is None:
        return None
    return max(lhs - rhs, 0)


def subtract_lists_nonnegative(lhs, rhs):
    if not isinstance(lhs, list) or not isinstance(rhs, list) or len(lhs) != len(rhs):
        return None

    values = []
    for left, right in zip(lhs, rhs):
        if not isinstance(left, (int, float)) or not isinstance(right, (int, float)):
            return None
        values.append(max(left - right, 0))
    return values


def workload_tuple(benchmark: dict) -> dict:
    probe = benchmark.get("probe") or {}
    return {
        "domain": benchmark.get("domain"),
        "mode": benchmark.get("mode"),
        "rounds": probe.get("rounds"),
        "tasks": probe.get("tasks"),
        "delay_ms": probe.get("delay_ms"),
    }


def per_bucket(delta: dict) -> dict:
    total_workers_current = metric_value(delta, "bucket_total_current")
    idle_workers_current = metric_value(delta, "bucket_idle_current")
    nonidle_workers_current = subtract_lists_nonnegative(
        total_workers_current, idle_workers_current
    )

    mapping = {
        "requested_workers": metric_value(delta, "bucket_req_total"),
        "admitted_workers": metric_value(delta, "bucket_admit_total"),
        "blocked_workers": metric_value(delta, "bucket_switch_block_total"),
        "unblocked_workers": metric_value(delta, "bucket_switch_unblock_total"),
        "total_workers_current": total_workers_current,
        "idle_workers_current": idle_workers_current,
        "nonidle_workers_current": nonidle_workers_current,
        "active_workers_current": metric_value(delta, "bucket_active_current"),
    }

    return {
        key: value
        for key, value in mapping.items()
        if isinstance(value, list) and value != []
    }


def aggregate(delta: dict) -> dict:
    requested_workers_by_bucket = metric_value(delta, "bucket_req_total")
    admitted_workers_by_bucket = metric_value(delta, "bucket_admit_total")
    blocked_workers_by_bucket = metric_value(delta, "bucket_switch_block_total")
    unblocked_workers_by_bucket = metric_value(delta, "bucket_switch_unblock_total")
    total_workers_current_by_bucket = metric_value(delta, "bucket_total_current")
    idle_workers_current_by_bucket = metric_value(delta, "bucket_idle_current")
    nonidle_workers_current_by_bucket = subtract_lists_nonnegative(
        total_workers_current_by_bucket, idle_workers_current_by_bucket
    )
    active_workers_current_by_bucket = metric_value(delta, "bucket_active_current")

    requested_workers_total = sum_if_list(requested_workers_by_bucket)
    admitted_workers_total = sum_if_list(admitted_workers_by_bucket)
    blocked_workers_total = sum_if_list(blocked_workers_by_bucket)
    unblocked_workers_total = sum_if_list(unblocked_workers_by_bucket)
    total_workers_current = sum_if_list(total_workers_current_by_bucket)
    idle_workers_current = sum_if_list(idle_workers_current_by_bucket)
    nonidle_workers_current = sum_if_list(nonidle_workers_current_by_bucket)
    active_workers_current = sum_if_list(active_workers_current_by_bucket)

    return {
        "request_events_total": metric_value(delta, "reqthreads_count"),
        "worker_entries_total": metric_value(delta, "thread_enter_count"),
        "worker_returns_total": metric_value(delta, "thread_return_count"),
        "requested_workers_total": requested_workers_total,
        "admitted_workers_total": admitted_workers_total,
        "blocked_events_total": metric_value(delta, "switch_block_count"),
        "unblocked_events_total": metric_value(delta, "switch_unblock_count"),
        "blocked_workers_total": blocked_workers_total,
        "unblocked_workers_total": unblocked_workers_total,
        "total_workers_current": total_workers_current,
        "idle_workers_current": idle_workers_current,
        "nonidle_workers_current": nonidle_workers_current,
        "active_workers_current": active_workers_current,
        "should_narrow_true_total": metric_value(delta, "should_narrow_true_count"),
        "request_backlog_total": nonnegative_delta(
            requested_workers_total, admitted_workers_total
        ),
        "block_backlog_total": nonnegative_delta(
            blocked_workers_total, unblocked_workers_total
        ),
    }


def flags(aggregate_values: dict, per_bucket_values: dict) -> dict:
    request_backlog_total = aggregate_values.get("request_backlog_total")
    blocked_workers_total = aggregate_values.get("blocked_workers_total")
    should_narrow_true_total = aggregate_values.get("should_narrow_true_total")
    nonidle_workers_current = aggregate_values.get("nonidle_workers_current")

    return {
        "has_per_bucket_diagnostics": per_bucket_values != {},
        "has_admission_feedback": (
            aggregate_values.get("requested_workers_total") is not None
            and aggregate_values.get("admitted_workers_total") is not None
        ),
        "has_block_feedback": (
            aggregate_values.get("blocked_workers_total") is not None
            and aggregate_values.get("unblocked_workers_total") is not None
        ),
        "has_live_current_counts": (
            aggregate_values.get("total_workers_current") is not None
            and aggregate_values.get("idle_workers_current") is not None
            and aggregate_values.get("nonidle_workers_current") is not None
        ),
        "has_narrow_feedback": aggregate_values.get("should_narrow_true_total") is not None,
        "pressure_visible": bool(
            (request_backlog_total is not None and request_backlog_total > 0)
            or (blocked_workers_total is not None and blocked_workers_total > 0)
            or (should_narrow_true_total is not None and should_narrow_true_total > 0)
            or (nonidle_workers_current is not None and nonidle_workers_current > 0)
        ),
    }


def derived_snapshot(mode: str, benchmark: dict, generation: int) -> dict:
    delta = benchmark.get("twq_delta") or {}
    per_bucket_values = per_bucket(delta)
    aggregate_values = aggregate(delta)

    return {
        "generation": generation,
        "monotonic_time_ns": None,
        "timestamp_kind": "derived_from_artifact",
        "status": benchmark.get("status"),
        "workload": workload_tuple(benchmark),
        "aggregate": aggregate_values,
        "flags": flags(aggregate_values, per_bucket_values),
        "diagnostics": {
            "per_bucket": per_bucket_values,
        },
    }


def main() -> int:
    args = parse_args()
    source = load_json(args.source_artifact)
    benchmarks = source.get("benchmarks") or {}

    snapshots = {}
    generation = 0
    for mode in MODE_ORDER:
        benchmark = benchmarks.get(mode)
        if not isinstance(benchmark, dict):
            continue
        generation += 1
        snapshots[mode] = derived_snapshot(mode, benchmark, generation)

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "source_schema_version": source.get("schema_version"),
        "source_artifact": str(args.source_artifact),
        "source_label": (source.get("metadata") or {}).get("label"),
        "metadata": {
            "generation_kind": "synthetic_sequence",
            "monotonic_time_kind": "unavailable_in_derived_view",
            "snapshot_count": len(snapshots),
        },
        "snapshots": snapshots,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"source={args.source_artifact}")
    print(f"out={args.out}")
    print(f"snapshots={len(snapshots)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
