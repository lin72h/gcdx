#!/usr/bin/env python3
"""Derive a tracker smoke artifact from a session smoke artifact."""

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-artifact", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-tracker-replay")
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


def nonidle_state(snapshot: dict) -> bool:
    return aggregate_value(snapshot, "nonidle_workers_current") > 0


def request_backlog_state(snapshot: dict) -> bool:
    return aggregate_value(snapshot, "request_backlog_total") > 0


def block_backlog_state(snapshot: dict) -> bool:
    return aggregate_value(snapshot, "block_backlog_total") > 0


def narrow_feedback_state(snapshot: dict) -> bool:
    return aggregate_value(snapshot, "should_narrow_true_total") > 0


def quiescent_state(snapshot: dict) -> bool:
    return (
        aggregate_value(snapshot, "total_workers_current") == 0
        and aggregate_value(snapshot, "nonidle_workers_current") == 0
    )


def state_map(snapshot: dict) -> dict[str, bool]:
    return {
        "pressure_visible": flag_value(snapshot, "pressure_visible"),
        "nonidle": nonidle_state(snapshot),
        "request_backlog": request_backlog_state(snapshot),
        "block_backlog": block_backlog_state(snapshot),
        "narrow_feedback": narrow_feedback_state(snapshot),
        "quiescent": quiescent_state(snapshot),
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
    initial = state_map(first)
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
        "struct_size": ctypes.sizeof(TrackerV1),
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
        "initial_pressure_visible": initial["pressure_visible"],
        "initial_nonidle": initial["nonidle"],
        "initial_request_backlog": initial["request_backlog"],
        "initial_block_backlog": initial["block_backlog"],
        "initial_narrow_feedback": initial["narrow_feedback"],
        "initial_quiescent": initial["quiescent"],
        "pressure_visible_rises": pressure_visible_rises,
        "pressure_visible_falls": pressure_visible_falls,
        "nonidle_rises": nonidle_rises,
        "nonidle_falls": nonidle_falls,
        "request_backlog_rises": request_backlog_rises,
        "request_backlog_falls": request_backlog_falls,
        "block_backlog_rises": block_backlog_rises,
        "block_backlog_falls": block_backlog_falls,
        "narrow_feedback_rises": narrow_feedback_rises,
        "narrow_feedback_falls": narrow_feedback_falls,
        "quiescent_rises": quiescent_rises,
        "quiescent_falls": quiescent_falls,
        "final_pressure_visible": final["pressure_visible"],
        "final_nonidle": final["nonidle"],
        "final_request_backlog": final["request_backlog"],
        "final_block_backlog": final["block_backlog"],
        "final_narrow_feedback": final["narrow_feedback"],
        "final_quiescent": final["quiescent"],
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
        "tracker_kind": "pressure_transition_tracker_v1",
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
    print(f"struct_size={ctypes.sizeof(TrackerV1)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
