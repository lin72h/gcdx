#!/usr/bin/env python3
"""Extract a live pressure-provider smoke artifact from a guest serial log."""

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
    parser.add_argument("--label", default="m15-live-pressure-provider-smoke")
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

            if record.get("kind") == "pressure-provider-snapshot":
                snapshots.append(record)

    return snapshots


def max_metric(snapshots: list[dict], key: str) -> int | None:
    values = [
        aggregate_metric(snapshot, key)
        for snapshot in snapshots
        if isinstance(aggregate_metric(snapshot, key), int)
    ]
    return max(values) if values else None


def per_bucket_metric(snapshot: dict, key: str) -> list[int] | None:
    per_bucket = ((snapshot.get("diagnostics") or {}).get("per_bucket")) or {}
    value = per_bucket.get(key)

    if key == "nonidle_workers_current" and not isinstance(value, list):
        totals = per_bucket.get("total_workers_current")
        idles = per_bucket.get("idle_workers_current")
        if isinstance(totals, list) and isinstance(idles, list) and len(totals) == len(idles):
            values: list[int] = []
            for total, idle in zip(totals, idles):
                if not isinstance(total, int) or not isinstance(idle, int):
                    return None
                values.append(max(total - idle, 0))
            return values

    return value if isinstance(value, list) else None


def aggregate_metric(snapshot: dict, key: str) -> int | None:
    aggregate = snapshot.get("aggregate") or {}
    value = aggregate.get(key)

    if key == "nonidle_workers_current" and value is None:
        total = aggregate.get("total_workers_current")
        idle = aggregate.get("idle_workers_current")
        if isinstance(total, int) and isinstance(idle, int):
            return max(total - idle, 0)

    return value if isinstance(value, int) else None


def normalize_snapshot(snapshot: dict) -> dict:
    aggregate = dict(snapshot.get("aggregate") or {})
    diagnostics = dict(snapshot.get("diagnostics") or {})
    per_bucket = dict((diagnostics.get("per_bucket") or {}))

    nonidle = aggregate_metric(snapshot, "nonidle_workers_current")
    if nonidle is not None and "nonidle_workers_current" not in aggregate:
        aggregate["nonidle_workers_current"] = nonidle

    per_bucket_nonidle = per_bucket_metric(snapshot, "nonidle_workers_current")
    if per_bucket_nonidle is not None and "nonidle_workers_current" not in per_bucket:
        per_bucket["nonidle_workers_current"] = per_bucket_nonidle

    diagnostics["per_bucket"] = per_bucket

    normalized = dict(snapshot)
    normalized["aggregate"] = aggregate
    normalized["diagnostics"] = diagnostics
    return normalized


def summarize_capture(label: str, snapshots: list[dict]) -> dict:
    generations = [snapshot.get("generation") for snapshot in snapshots]
    monotonic_times = [snapshot.get("monotonic_time_ns") for snapshot in snapshots]
    pressure_visible_samples = sum(
        1
        for snapshot in snapshots
        if (snapshot.get("flags") or {}).get("pressure_visible") is True
    )

    generation_contiguous = generations == list(range(1, len(generations) + 1))
    monotonic_increasing = all(
        earlier < later for earlier, later in zip(monotonic_times, monotonic_times[1:])
    )

    final = snapshots[-1]
    final_aggregate = final.get("aggregate") or {}
    first = snapshots[0]

    return {
        "label": label,
        "sample_count": len(snapshots),
        "generation_first": generations[0],
        "generation_last": generations[-1],
        "generation_contiguous": generation_contiguous,
        "monotonic_increasing": monotonic_increasing,
        "interval_ms": first.get("interval_ms"),
        "duration_ms": first.get("duration_ms"),
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

        captures.setdefault(label, []).append(
            normalize_snapshot(
                {
                "generation": data.get("generation"),
                "monotonic_time_ns": data.get("monotonic_time_ns"),
                "interval_ms": data.get("interval_ms"),
                "duration_ms": data.get("duration_ms"),
                "aggregate": data.get("aggregate") or {},
                "flags": data.get("flags") or {},
                "diagnostics": data.get("diagnostics") or {},
                }
            )
        )

    summary_captures = {}
    for label, snapshots in sorted(captures.items()):
        ordered = sorted(snapshots, key=lambda snapshot: snapshot.get("generation") or 0)
        summary_captures[label] = summarize_capture(label, ordered)

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "capture_kind": "live_probe",
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
