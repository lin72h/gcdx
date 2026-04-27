#!/usr/bin/env python3
"""Derive an observer smoke artifact from a session smoke artifact."""

from __future__ import annotations

import argparse
import ctypes
import json
from pathlib import Path

CONTRACT = {
    "name": "twq_pressure_provider",
    "version": 1,
    "current_signal_field": "nonidle_workers_current",
    "current_signal_kind": "total_minus_idle",
    "quiescence_kind": "total_and_nonidle_zero",
    "per_bucket_scope": "diagnostic_only",
    "diagnostic_fields": ["active_workers_current"],
}


class ObserverV1(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("version", ctypes.c_uint32),
        ("source_session_struct_size", ctypes.c_size_t),
        ("source_session_version", ctypes.c_uint32),
        ("source_view_struct_size", ctypes.c_size_t),
        ("source_view_version", ctypes.c_uint32),
        ("sample_count", ctypes.c_uint64),
        ("generation_first", ctypes.c_uint64),
        ("generation_last", ctypes.c_uint64),
        ("monotonic_time_first_ns", ctypes.c_uint64),
        ("monotonic_time_last_ns", ctypes.c_uint64),
        ("pressure_visible_samples", ctypes.c_uint64),
        ("nonidle_samples", ctypes.c_uint64),
        ("request_backlog_samples", ctypes.c_uint64),
        ("block_backlog_samples", ctypes.c_uint64),
        ("narrow_feedback_samples", ctypes.c_uint64),
        ("quiescent_samples", ctypes.c_uint64),
        ("max_nonidle_workers_current", ctypes.c_uint64),
        ("max_request_backlog_total", ctypes.c_uint64),
        ("max_block_backlog_total", ctypes.c_uint64),
        ("final_total_workers_current", ctypes.c_uint64),
        ("final_idle_workers_current", ctypes.c_uint64),
        ("final_nonidle_workers_current", ctypes.c_uint64),
        ("final_active_workers_current", ctypes.c_uint64),
        ("generation_contiguous", ctypes.c_uint8),
        ("monotonic_increasing", ctypes.c_uint8),
        ("final_pressure_visible", ctypes.c_uint8),
        ("final_quiescent", ctypes.c_uint8),
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-artifact", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-observer-replay")
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def aggregate_value(snapshot: dict, key: str) -> int:
    aggregate = ((snapshot.get("view") or {}).get("aggregate")) or {}
    value = aggregate.get(key)
    return int(value or 0)


def flag_value(snapshot: dict, key: str) -> bool:
    flags = ((snapshot.get("view") or {}).get("flags")) or {}
    return flags.get(key) is True


def is_quiescent(snapshot: dict) -> bool:
    return (
        aggregate_value(snapshot, "total_workers_current") == 0
        and aggregate_value(snapshot, "nonidle_workers_current") == 0
    )


def summarize_capture(label: str, capture: dict) -> dict:
    snapshots = sorted(capture.get("snapshots") or [], key=lambda item: item.get("generation") or 0)
    if not snapshots:
        raise ValueError(f"{label}: no session snapshots")

    generations = [snapshot.get("generation") for snapshot in snapshots]
    monotonic_times = [snapshot.get("monotonic_time_ns") for snapshot in snapshots]
    first = snapshots[0]
    last = snapshots[-1]
    first_session = first.get("session") or {}
    first_view = first.get("view") or {}

    return {
        "label": label,
        "interval_ms": first.get("interval_ms"),
        "duration_ms": first.get("duration_ms"),
        "struct_version": 1,
        "struct_size": ctypes.sizeof(ObserverV1),
        "source_session_version": first_session.get("version"),
        "source_session_struct_size": first_session.get("struct_size"),
        "source_view_version": first_view.get("version"),
        "source_view_struct_size": first_view.get("struct_size"),
        "sample_count": len(snapshots),
        "generation_first": generations[0],
        "generation_last": generations[-1],
        "generation_contiguous": generations == list(range(generations[0], generations[0] + len(generations))),
        "monotonic_increasing": all(
            earlier < later for earlier, later in zip(monotonic_times, monotonic_times[1:])
        ),
        "monotonic_time_first_ns": monotonic_times[0],
        "monotonic_time_last_ns": monotonic_times[-1],
        "pressure_visible_samples": sum(1 for snapshot in snapshots if flag_value(snapshot, "pressure_visible")),
        "nonidle_samples": sum(
            1 for snapshot in snapshots if aggregate_value(snapshot, "nonidle_workers_current") > 0
        ),
        "request_backlog_samples": sum(
            1 for snapshot in snapshots if aggregate_value(snapshot, "request_backlog_total") > 0
        ),
        "block_backlog_samples": sum(
            1 for snapshot in snapshots if aggregate_value(snapshot, "block_backlog_total") > 0
        ),
        "narrow_feedback_samples": sum(
            1 for snapshot in snapshots if aggregate_value(snapshot, "should_narrow_true_total") > 0
        ),
        "quiescent_samples": sum(1 for snapshot in snapshots if is_quiescent(snapshot)),
        "max_nonidle_workers_current": max(
            aggregate_value(snapshot, "nonidle_workers_current") for snapshot in snapshots
        ),
        "max_request_backlog_total": max(
            aggregate_value(snapshot, "request_backlog_total") for snapshot in snapshots
        ),
        "max_block_backlog_total": max(
            aggregate_value(snapshot, "block_backlog_total") for snapshot in snapshots
        ),
        "final_total_workers_current": aggregate_value(last, "total_workers_current"),
        "final_idle_workers_current": aggregate_value(last, "idle_workers_current"),
        "final_nonidle_workers_current": aggregate_value(last, "nonidle_workers_current"),
        "final_active_workers_current": aggregate_value(last, "active_workers_current"),
        "final_pressure_visible": flag_value(last, "pressure_visible"),
        "final_quiescent": is_quiescent(last),
    }


def main() -> int:
    args = parse_args()
    session_artifact = load(args.session_artifact)
    session_captures = session_artifact.get("captures") or {}

    captures = {
        label: summarize_capture(label, capture)
        for label, capture in sorted(session_captures.items())
    }

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "observer_kind": "pressure_observer_v1",
        "source_session_kind": "callable_session_v1",
        "source_view_kind": "aggregate_view_v1",
        "metadata": {
            "label": args.label,
            "session_artifact": args.session_artifact.name,
            "generation_kind": "monotonic_sequence",
            "monotonic_time_kind": "clock_monotonic",
            "label_count": len(captures),
        },
        "captures": captures,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"session_artifact={args.session_artifact}")
    print(f"out={args.out}")
    print(f"labels={','.join(sorted(captures))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
