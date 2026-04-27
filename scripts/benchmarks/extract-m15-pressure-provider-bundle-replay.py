#!/usr/bin/env python3
"""Derive a bundle smoke artifact from a session smoke artifact."""

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

MAX_BUCKETS = 16


class SnapshotV1(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("version", ctypes.c_uint32),
        ("bucket_count", ctypes.c_uint32),
        ("monotonic_time_ns", ctypes.c_uint64),
        ("reqthreads_count", ctypes.c_uint64),
        ("thread_enter_count", ctypes.c_uint64),
        ("thread_return_count", ctypes.c_uint64),
        ("switch_block_count", ctypes.c_uint64),
        ("switch_unblock_count", ctypes.c_uint64),
        ("should_narrow_true_count", ctypes.c_uint64),
        ("requested_workers_total", ctypes.c_uint64),
        ("admitted_workers_total", ctypes.c_uint64),
        ("blocked_workers_total", ctypes.c_uint64),
        ("unblocked_workers_total", ctypes.c_uint64),
        ("total_workers_current", ctypes.c_uint64),
        ("idle_workers_current", ctypes.c_uint64),
        ("nonidle_workers_current", ctypes.c_uint64),
        ("active_workers_current", ctypes.c_uint64),
        ("bucket_req_total", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_admit_total", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_switch_block_total", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_switch_unblock_total", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_total_current", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_idle_current", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_nonidle_current", ctypes.c_uint64 * MAX_BUCKETS),
        ("bucket_active_current", ctypes.c_uint64 * MAX_BUCKETS),
    ]


class ViewV1(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("version", ctypes.c_uint32),
        ("generation", ctypes.c_uint64),
        ("monotonic_time_ns", ctypes.c_uint64),
        ("request_events_total", ctypes.c_uint64),
        ("worker_entries_total", ctypes.c_uint64),
        ("worker_returns_total", ctypes.c_uint64),
        ("requested_workers_total", ctypes.c_uint64),
        ("admitted_workers_total", ctypes.c_uint64),
        ("blocked_events_total", ctypes.c_uint64),
        ("unblocked_events_total", ctypes.c_uint64),
        ("blocked_workers_total", ctypes.c_uint64),
        ("unblocked_workers_total", ctypes.c_uint64),
        ("total_workers_current", ctypes.c_uint64),
        ("idle_workers_current", ctypes.c_uint64),
        ("nonidle_workers_current", ctypes.c_uint64),
        ("active_workers_current", ctypes.c_uint64),
        ("should_narrow_true_total", ctypes.c_uint64),
        ("request_backlog_total", ctypes.c_uint64),
        ("block_backlog_total", ctypes.c_uint64),
        ("has_per_bucket_diagnostics", ctypes.c_uint8),
        ("has_admission_feedback", ctypes.c_uint8),
        ("has_block_feedback", ctypes.c_uint8),
        ("has_live_current_counts", ctypes.c_uint8),
        ("has_narrow_feedback", ctypes.c_uint8),
        ("pressure_visible", ctypes.c_uint8),
    ]


class SessionV1(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("version", ctypes.c_uint32),
        ("source_snapshot_struct_size", ctypes.c_size_t),
        ("source_snapshot_version", ctypes.c_uint32),
        ("bucket_count", ctypes.c_uint32),
        ("next_generation", ctypes.c_uint64),
        ("primed", ctypes.c_uint8),
        ("base_snapshot", SnapshotV1),
    ]


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


class TrackerV1(ctypes.Structure):
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
        ("pressure_visible_rises", ctypes.c_uint64),
        ("pressure_visible_falls", ctypes.c_uint64),
        ("nonidle_rises", ctypes.c_uint64),
        ("nonidle_falls", ctypes.c_uint64),
        ("request_backlog_rises", ctypes.c_uint64),
        ("request_backlog_falls", ctypes.c_uint64),
        ("block_backlog_rises", ctypes.c_uint64),
        ("block_backlog_falls", ctypes.c_uint64),
        ("narrow_feedback_rises", ctypes.c_uint64),
        ("narrow_feedback_falls", ctypes.c_uint64),
        ("quiescent_rises", ctypes.c_uint64),
        ("quiescent_falls", ctypes.c_uint64),
        ("generation_contiguous", ctypes.c_uint8),
        ("monotonic_increasing", ctypes.c_uint8),
        ("initial_pressure_visible", ctypes.c_uint8),
        ("initial_nonidle", ctypes.c_uint8),
        ("initial_request_backlog", ctypes.c_uint8),
        ("initial_block_backlog", ctypes.c_uint8),
        ("initial_narrow_feedback", ctypes.c_uint8),
        ("initial_quiescent", ctypes.c_uint8),
        ("final_pressure_visible", ctypes.c_uint8),
        ("final_nonidle", ctypes.c_uint8),
        ("final_request_backlog", ctypes.c_uint8),
        ("final_block_backlog", ctypes.c_uint8),
        ("final_narrow_feedback", ctypes.c_uint8),
        ("final_quiescent", ctypes.c_uint8),
    ]


class BundleV1(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("version", ctypes.c_uint32),
        ("source_session_struct_size", ctypes.c_size_t),
        ("source_session_version", ctypes.c_uint32),
        ("source_view_struct_size", ctypes.c_size_t),
        ("source_view_version", ctypes.c_uint32),
        ("source_observer_struct_size", ctypes.c_size_t),
        ("source_observer_version", ctypes.c_uint32),
        ("source_tracker_struct_size", ctypes.c_size_t),
        ("source_tracker_version", ctypes.c_uint32),
        ("sample_count", ctypes.c_uint64),
        ("generation_first", ctypes.c_uint64),
        ("generation_last", ctypes.c_uint64),
        ("monotonic_time_first_ns", ctypes.c_uint64),
        ("monotonic_time_last_ns", ctypes.c_uint64),
        ("generation_contiguous", ctypes.c_uint8),
        ("monotonic_increasing", ctypes.c_uint8),
        ("current_pressure_visible", ctypes.c_uint8),
        ("current_quiescent", ctypes.c_uint8),
        ("current_narrow_feedback", ctypes.c_uint8),
        ("current_view", ViewV1),
        ("observer", ObserverV1),
        ("tracker", TrackerV1),
        ("session", SessionV1),
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-artifact", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-bundle-replay")
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


def state_map(snapshot: dict) -> dict[str, bool]:
    return {
        "pressure_visible": flag_value(snapshot, "pressure_visible"),
        "nonidle": aggregate_value(snapshot, "nonidle_workers_current") > 0,
        "request_backlog": aggregate_value(snapshot, "request_backlog_total") > 0,
        "block_backlog": aggregate_value(snapshot, "block_backlog_total") > 0,
        "narrow_feedback": aggregate_value(snapshot, "should_narrow_true_total") > 0,
        "quiescent": aggregate_value(snapshot, "total_workers_current") == 0
        and aggregate_value(snapshot, "nonidle_workers_current") == 0,
    }


def count_edges(snapshots: list[dict], key: str) -> tuple[int, int]:
    rises = 0
    falls = 0

    for previous, current in zip(snapshots, snapshots[1:]):
        lhs = state_map(previous)[key]
        rhs = state_map(current)[key]
        if not lhs and rhs:
            rises += 1
        elif lhs and not rhs:
            falls += 1

    return rises, falls


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
    final = state_map(last)

    pressure_visible_rises, pressure_visible_falls = count_edges(
        snapshots, "pressure_visible"
    )
    nonidle_rises, nonidle_falls = count_edges(snapshots, "nonidle")
    request_backlog_rises, request_backlog_falls = count_edges(
        snapshots, "request_backlog"
    )
    block_backlog_rises, block_backlog_falls = count_edges(
        snapshots, "block_backlog"
    )
    narrow_feedback_rises, narrow_feedback_falls = count_edges(
        snapshots, "narrow_feedback"
    )
    quiescent_rises, quiescent_falls = count_edges(snapshots, "quiescent")

    return {
        "label": label,
        "interval_ms": first.get("interval_ms"),
        "duration_ms": first.get("duration_ms"),
        "struct_version": 1,
        "struct_size": ctypes.sizeof(BundleV1),
        "source_session_version": first_session.get("version"),
        "source_session_struct_size": first_session.get("struct_size"),
        "source_view_version": first_view.get("version"),
        "source_view_struct_size": first_view.get("struct_size"),
        "source_observer_version": 1,
        "source_observer_struct_size": ctypes.sizeof(ObserverV1),
        "source_tracker_version": 1,
        "source_tracker_struct_size": ctypes.sizeof(TrackerV1),
        "sample_count": len(snapshots),
        "generation_first": generations[0],
        "generation_last": generations[-1],
        "generation_contiguous": generations == list(range(generations[0], generations[0] + len(generations))),
        "monotonic_increasing": all(
            earlier < later for earlier, later in zip(monotonic_times, monotonic_times[1:])
        ),
        "monotonic_time_first_ns": monotonic_times[0],
        "monotonic_time_last_ns": monotonic_times[-1],
        "current_generation": last.get("generation"),
        "current_monotonic_time_ns": last.get("monotonic_time_ns"),
        "current_total_workers_current": aggregate_value(last, "total_workers_current"),
        "current_idle_workers_current": aggregate_value(last, "idle_workers_current"),
        "current_nonidle_workers_current": aggregate_value(last, "nonidle_workers_current"),
        "current_active_workers_current": aggregate_value(last, "active_workers_current"),
        "current_request_backlog_total": aggregate_value(last, "request_backlog_total"),
        "current_block_backlog_total": aggregate_value(last, "block_backlog_total"),
        "current_pressure_visible": final["pressure_visible"],
        "current_quiescent": final["quiescent"],
        "current_narrow_feedback": final["narrow_feedback"],
        "observer_pressure_visible_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["pressure_visible"]
        ),
        "observer_nonidle_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["nonidle"]
        ),
        "observer_request_backlog_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["request_backlog"]
        ),
        "observer_block_backlog_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["block_backlog"]
        ),
        "observer_narrow_feedback_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["narrow_feedback"]
        ),
        "observer_quiescent_samples": sum(
            1 for snapshot in snapshots if state_map(snapshot)["quiescent"]
        ),
        "observer_max_nonidle_workers_current": max(
            aggregate_value(snapshot, "nonidle_workers_current") for snapshot in snapshots
        ),
        "observer_max_request_backlog_total": max(
            aggregate_value(snapshot, "request_backlog_total") for snapshot in snapshots
        ),
        "observer_max_block_backlog_total": max(
            aggregate_value(snapshot, "block_backlog_total") for snapshot in snapshots
        ),
        "tracker_pressure_visible_rises": pressure_visible_rises,
        "tracker_pressure_visible_falls": pressure_visible_falls,
        "tracker_nonidle_rises": nonidle_rises,
        "tracker_nonidle_falls": nonidle_falls,
        "tracker_request_backlog_rises": request_backlog_rises,
        "tracker_request_backlog_falls": request_backlog_falls,
        "tracker_block_backlog_rises": block_backlog_rises,
        "tracker_block_backlog_falls": block_backlog_falls,
        "tracker_narrow_feedback_rises": narrow_feedback_rises,
        "tracker_narrow_feedback_falls": narrow_feedback_falls,
        "tracker_quiescent_rises": quiescent_rises,
        "tracker_quiescent_falls": quiescent_falls,
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
        "bundle_kind": "pressure_bundle_v1",
        "source_session_kind": "callable_session_v1",
        "source_view_kind": "aggregate_view_v1",
        "source_observer_kind": "pressure_observer_v1",
        "source_tracker_kind": "pressure_transition_tracker_v1",
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
    print(f"struct_size={ctypes.sizeof(BundleV1)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
