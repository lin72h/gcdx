#!/usr/bin/env python3
"""Extract a pressure-provider observer smoke artifact from a guest serial log."""

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
    parser.add_argument("--label", default="m15-pressure-provider-observer-smoke")
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

            if record.get("kind") == "pressure-provider-observer-summary":
                records.append(record)

    return records


def normalize_summary(record: dict) -> tuple[str | None, dict]:
    data = dict(record.get("data") or {})
    observer = dict(data.get("observer") or {})
    label = data.get("label")

    summary = {
        "label": label,
        "interval_ms": data.get("interval_ms"),
        "duration_ms": data.get("duration_ms"),
        "struct_version": observer.get("version"),
        "struct_size": observer.get("struct_size"),
        "source_session_version": observer.get("source_session_version"),
        "source_session_struct_size": observer.get("source_session_struct_size"),
        "source_view_version": observer.get("source_view_version"),
        "source_view_struct_size": observer.get("source_view_struct_size"),
        "sample_count": observer.get("sample_count"),
        "generation_first": observer.get("generation_first"),
        "generation_last": observer.get("generation_last"),
        "generation_contiguous": observer.get("generation_contiguous"),
        "monotonic_increasing": observer.get("monotonic_increasing"),
        "monotonic_time_first_ns": observer.get("monotonic_time_first_ns"),
        "monotonic_time_last_ns": observer.get("monotonic_time_last_ns"),
        "pressure_visible_samples": observer.get("pressure_visible_samples"),
        "nonidle_samples": observer.get("nonidle_samples"),
        "request_backlog_samples": observer.get("request_backlog_samples"),
        "block_backlog_samples": observer.get("block_backlog_samples"),
        "narrow_feedback_samples": observer.get("narrow_feedback_samples"),
        "quiescent_samples": observer.get("quiescent_samples"),
        "max_nonidle_workers_current": observer.get("max_nonidle_workers_current"),
        "max_request_backlog_total": observer.get("max_request_backlog_total"),
        "max_block_backlog_total": observer.get("max_block_backlog_total"),
        "final_total_workers_current": observer.get("final_total_workers_current"),
        "final_idle_workers_current": observer.get("final_idle_workers_current"),
        "final_nonidle_workers_current": observer.get("final_nonidle_workers_current"),
        "final_active_workers_current": observer.get("final_active_workers_current"),
        "final_pressure_visible": observer.get("final_pressure_visible"),
        "final_quiescent": observer.get("final_quiescent"),
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
        "observer_kind": "pressure_observer_v1",
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
