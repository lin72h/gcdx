#!/usr/bin/env python3
"""Extract a pressure-provider bundle smoke artifact from a guest serial log."""

from __future__ import annotations

import argparse
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial-log", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-bundle-smoke")
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

            if record.get("kind") == "pressure-provider-bundle-summary":
                records.append(record)

    return records


def normalize_summary(record: dict) -> tuple[str | None, dict]:
    data = dict(record.get("data") or {})
    bundle = dict(data.get("bundle") or {})
    label = data.get("label")

    summary = {
        "label": label,
        "interval_ms": data.get("interval_ms"),
        "duration_ms": data.get("duration_ms"),
        "struct_version": bundle.get("version"),
        "struct_size": bundle.get("struct_size"),
        "source_session_version": bundle.get("source_session_version"),
        "source_session_struct_size": bundle.get("source_session_struct_size"),
        "source_view_version": bundle.get("source_view_version"),
        "source_view_struct_size": bundle.get("source_view_struct_size"),
        "source_observer_version": bundle.get("source_observer_version"),
        "source_observer_struct_size": bundle.get("source_observer_struct_size"),
        "source_tracker_version": bundle.get("source_tracker_version"),
        "source_tracker_struct_size": bundle.get("source_tracker_struct_size"),
        "sample_count": bundle.get("sample_count"),
        "generation_first": bundle.get("generation_first"),
        "generation_last": bundle.get("generation_last"),
        "generation_contiguous": bundle.get("generation_contiguous"),
        "monotonic_increasing": bundle.get("monotonic_increasing"),
        "monotonic_time_first_ns": bundle.get("monotonic_time_first_ns"),
        "monotonic_time_last_ns": bundle.get("monotonic_time_last_ns"),
        "current_generation": bundle.get("current_generation"),
        "current_monotonic_time_ns": bundle.get("current_monotonic_time_ns"),
        "current_total_workers_current": bundle.get("current_total_workers_current"),
        "current_idle_workers_current": bundle.get("current_idle_workers_current"),
        "current_nonidle_workers_current": bundle.get("current_nonidle_workers_current"),
        "current_active_workers_current": bundle.get("current_active_workers_current"),
        "current_request_backlog_total": bundle.get("current_request_backlog_total"),
        "current_block_backlog_total": bundle.get("current_block_backlog_total"),
        "current_pressure_visible": bundle.get("current_pressure_visible"),
        "current_quiescent": bundle.get("current_quiescent"),
        "current_narrow_feedback": bundle.get("current_narrow_feedback"),
        "observer_pressure_visible_samples": bundle.get("observer_pressure_visible_samples"),
        "observer_nonidle_samples": bundle.get("observer_nonidle_samples"),
        "observer_request_backlog_samples": bundle.get("observer_request_backlog_samples"),
        "observer_block_backlog_samples": bundle.get("observer_block_backlog_samples"),
        "observer_narrow_feedback_samples": bundle.get("observer_narrow_feedback_samples"),
        "observer_quiescent_samples": bundle.get("observer_quiescent_samples"),
        "observer_max_nonidle_workers_current": bundle.get("observer_max_nonidle_workers_current"),
        "observer_max_request_backlog_total": bundle.get("observer_max_request_backlog_total"),
        "observer_max_block_backlog_total": bundle.get("observer_max_block_backlog_total"),
        "tracker_pressure_visible_rises": bundle.get("tracker_pressure_visible_rises"),
        "tracker_pressure_visible_falls": bundle.get("tracker_pressure_visible_falls"),
        "tracker_nonidle_rises": bundle.get("tracker_nonidle_rises"),
        "tracker_nonidle_falls": bundle.get("tracker_nonidle_falls"),
        "tracker_request_backlog_rises": bundle.get("tracker_request_backlog_rises"),
        "tracker_request_backlog_falls": bundle.get("tracker_request_backlog_falls"),
        "tracker_block_backlog_rises": bundle.get("tracker_block_backlog_rises"),
        "tracker_block_backlog_falls": bundle.get("tracker_block_backlog_falls"),
        "tracker_narrow_feedback_rises": bundle.get("tracker_narrow_feedback_rises"),
        "tracker_narrow_feedback_falls": bundle.get("tracker_narrow_feedback_falls"),
        "tracker_quiescent_rises": bundle.get("tracker_quiescent_rises"),
        "tracker_quiescent_falls": bundle.get("tracker_quiescent_falls"),
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
        "bundle_kind": "pressure_bundle_v1",
        "source_session_kind": "callable_session_v1",
        "source_view_kind": "aggregate_view_v1",
        "source_observer_kind": "pressure_observer_v1",
        "source_tracker_kind": "pressure_transition_tracker_v1",
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
