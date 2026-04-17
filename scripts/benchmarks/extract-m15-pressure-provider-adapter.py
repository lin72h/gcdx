#!/usr/bin/env python3
"""Extract a pressure-provider adapter smoke artifact from a guest serial log."""

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
    parser.add_argument("--label", default="m15-pressure-provider-adapter-smoke")
    return parser.parse_args()


def load_snapshot_lines(serial_log: Path) -> list[dict]:
    snapshots: list[dict] = []

    with serial_log.open("r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line.startswith("{"):
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            if record.get("kind") == "pressure-provider-adapter-snapshot":
                snapshots.append(record)

    return snapshots


def aggregate_metric(snapshot: dict, key: str) -> int | None:
    aggregate = snapshot.get("aggregate") or {}
    value = aggregate.get(key)
    return value if isinstance(value, int) else None


def max_metric(snapshots: list[dict], key: str) -> int | None:
    values = [
        aggregate_metric(snapshot, key)
        for snapshot in snapshots
        if isinstance(aggregate_metric(snapshot, key), int)
    ]
    return max(values) if values else None


def normalize_snapshot(record: dict) -> dict:
    data = record.get("data") or {}
    view = dict(data.get("view") or {})
    aggregate = dict(view.get("aggregate") or {})
    flags = dict(view.get("flags") or {})

    return {
        "generation": data.get("generation"),
        "monotonic_time_ns": data.get("monotonic_time_ns"),
        "interval_ms": data.get("interval_ms"),
        "duration_ms": data.get("duration_ms"),
        "aggregate": aggregate,
        "flags": flags,
        "view": {
            "struct_size": view.get("struct_size"),
            "version": view.get("version"),
            "generation": view.get("generation"),
            "monotonic_time_ns": view.get("monotonic_time_ns"),
        },
    }


def summarize_capture(label: str, snapshots: list[dict]) -> dict:
    generations = [snapshot.get("generation") for snapshot in snapshots]
    monotonic_times = [snapshot.get("monotonic_time_ns") for snapshot in snapshots]
    pressure_visible_samples = sum(
        1
        for snapshot in snapshots
        if (snapshot.get("flags") or {}).get("pressure_visible") is True
    )

    final = snapshots[-1]
    first = snapshots[0]
    first_view = first.get("view") or {}

    return {
        "label": label,
        "sample_count": len(snapshots),
        "generation_first": generations[0],
        "generation_last": generations[-1],
        "generation_contiguous": generations == list(range(1, len(generations) + 1)),
        "monotonic_increasing": all(
            earlier < later for earlier, later in zip(monotonic_times, monotonic_times[1:])
        ),
        "interval_ms": first.get("interval_ms"),
        "duration_ms": first.get("duration_ms"),
        "struct_version": first_view.get("version"),
        "struct_size": first_view.get("struct_size"),
        "pressure_visible_samples": pressure_visible_samples,
        "max_request_events_total": max_metric(snapshots, "request_events_total"),
        "max_requested_workers_total": max_metric(snapshots, "requested_workers_total"),
        "max_blocked_events_total": max_metric(snapshots, "blocked_events_total"),
        "max_worker_entries_total": max_metric(snapshots, "worker_entries_total"),
        "max_nonidle_workers_current": max_metric(snapshots, "nonidle_workers_current"),
        "max_active_workers_current": max_metric(snapshots, "active_workers_current"),
        "final_total_workers_current": aggregate_metric(final, "total_workers_current"),
        "final_idle_workers_current": aggregate_metric(final, "idle_workers_current"),
        "final_nonidle_workers_current": aggregate_metric(final, "nonidle_workers_current"),
        "final_active_workers_current": aggregate_metric(final, "active_workers_current"),
        "snapshots": snapshots,
    }


def main() -> int:
    args = parse_args()
    snapshot_lines = load_snapshot_lines(args.serial_log)

    captures: dict[str, list[dict]] = {}
    for record in snapshot_lines:
        data = record.get("data") or {}
        label = data.get("label")
        if not isinstance(label, str):
            continue

        captures.setdefault(label, []).append(normalize_snapshot(record))

    summary_captures = {}
    for label, snapshots in sorted(captures.items()):
        ordered = sorted(snapshots, key=lambda snapshot: snapshot.get("generation") or 0)
        summary_captures[label] = summarize_capture(label, ordered)

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "adapter_kind": "aggregate_view_v1",
        "metadata": {
            "label": args.label,
            "serial_log": args.serial_log.name,
            "generation_kind": "monotonic_sequence",
            "monotonic_time_kind": "clock_monotonic",
            "label_count": len(summary_captures),
        },
        "captures": summary_captures,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"serial_log={args.serial_log}")
    print(f"out={args.out}")
    print(f"labels={','.join(sorted(summary_captures))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
