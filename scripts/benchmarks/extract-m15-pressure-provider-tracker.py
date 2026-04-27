#!/usr/bin/env python3
"""Extract a pressure-provider tracker smoke artifact from a guest serial log."""

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
    parser.add_argument("--serial-log", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-tracker-smoke")
    return parser.parse_args()


def load_summary_lines(serial_log: Path) -> list[dict]:
    records: list[dict] = []

    with serial_log.open("r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line.startswith("{"):
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            if record.get("kind") == "pressure-provider-tracker-summary":
                records.append(record)

    return records


def normalize_summary(record: dict) -> tuple[str | None, dict]:
    data = dict(record.get("data") or {})
    tracker = dict(data.get("tracker") or {})
    label = data.get("label")

    summary = {
        "label": label,
        "interval_ms": data.get("interval_ms"),
        "duration_ms": data.get("duration_ms"),
        "struct_version": tracker.get("version"),
        "struct_size": tracker.get("struct_size"),
        "source_session_version": tracker.get("source_session_version"),
        "source_session_struct_size": tracker.get("source_session_struct_size"),
        "source_view_version": tracker.get("source_view_version"),
        "source_view_struct_size": tracker.get("source_view_struct_size"),
        "sample_count": tracker.get("sample_count"),
        "generation_first": tracker.get("generation_first"),
        "generation_last": tracker.get("generation_last"),
        "generation_contiguous": tracker.get("generation_contiguous"),
        "monotonic_increasing": tracker.get("monotonic_increasing"),
        "monotonic_time_first_ns": tracker.get("monotonic_time_first_ns"),
        "monotonic_time_last_ns": tracker.get("monotonic_time_last_ns"),
        "initial_pressure_visible": tracker.get("initial_pressure_visible"),
        "initial_nonidle": tracker.get("initial_nonidle"),
        "initial_request_backlog": tracker.get("initial_request_backlog"),
        "initial_block_backlog": tracker.get("initial_block_backlog"),
        "initial_narrow_feedback": tracker.get("initial_narrow_feedback"),
        "initial_quiescent": tracker.get("initial_quiescent"),
        "pressure_visible_rises": tracker.get("pressure_visible_rises"),
        "pressure_visible_falls": tracker.get("pressure_visible_falls"),
        "nonidle_rises": tracker.get("nonidle_rises"),
        "nonidle_falls": tracker.get("nonidle_falls"),
        "request_backlog_rises": tracker.get("request_backlog_rises"),
        "request_backlog_falls": tracker.get("request_backlog_falls"),
        "block_backlog_rises": tracker.get("block_backlog_rises"),
        "block_backlog_falls": tracker.get("block_backlog_falls"),
        "narrow_feedback_rises": tracker.get("narrow_feedback_rises"),
        "narrow_feedback_falls": tracker.get("narrow_feedback_falls"),
        "quiescent_rises": tracker.get("quiescent_rises"),
        "quiescent_falls": tracker.get("quiescent_falls"),
        "final_pressure_visible": tracker.get("final_pressure_visible"),
        "final_nonidle": tracker.get("final_nonidle"),
        "final_request_backlog": tracker.get("final_request_backlog"),
        "final_block_backlog": tracker.get("final_block_backlog"),
        "final_narrow_feedback": tracker.get("final_narrow_feedback"),
        "final_quiescent": tracker.get("final_quiescent"),
    }

    return label, summary


def main() -> int:
    args = parse_args()
    capture_records = load_summary_lines(args.serial_log)

    captures: dict[str, dict] = {}
    for record in capture_records:
        label, summary = normalize_summary(record)
        if isinstance(label, str):
            captures[label] = summary

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "tracker_kind": "pressure_transition_tracker_v1",
        "source_session_kind": "callable_session_v1",
        "source_view_kind": "aggregate_view_v1",
        "metadata": {
            "label": args.label,
            "serial_log": args.serial_log.name,
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
    print(f"serial_log={args.serial_log}")
    print(f"out={args.out}")
    print(f"labels={','.join(sorted(captures))}")
    print(f"struct_size={ctypes.sizeof(TrackerV1)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
