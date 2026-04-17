#!/usr/bin/env python3
"""Extract a raw preview pressure-provider artifact from a guest serial log."""

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

MONOTONIC_FIELDS = (
    "reqthreads_count",
    "thread_enter_count",
    "thread_return_count",
    "switch_block_count",
    "switch_unblock_count",
    "should_narrow_true_count",
    "requested_workers_total",
    "admitted_workers_total",
    "blocked_workers_total",
    "unblocked_workers_total",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial-log", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m15-pressure-provider-preview-smoke")
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

            if record.get("kind") == "pressure-provider-preview-snapshot":
                snapshots.append(record)

    return snapshots


def monotonic_non_decreasing(values: list[int]) -> bool:
    return all(earlier <= later for earlier, later in zip(values, values[1:]))


def metric_delta(first: dict, final: dict, key: str) -> int | None:
    lhs = first.get(key)
    rhs = final.get(key)
    if isinstance(lhs, int) and isinstance(rhs, int):
        return max(rhs - lhs, 0)
    return None


def metric_max(snapshots: list[dict], key: str) -> int | None:
    values = [snapshot.get(key) for snapshot in snapshots if isinstance(snapshot.get(key), int)]
    return max(values) if values else None


def summarize_capture(label: str, snapshots: list[dict]) -> dict:
    generations = [snapshot.get("generation") for snapshot in snapshots]
    raw_snapshots = [snapshot.get("snapshot") or {} for snapshot in snapshots]
    monotonic_times = [snapshot.get("monotonic_time_ns") for snapshot in raw_snapshots]
    first = snapshots[0]
    first_raw = raw_snapshots[0]
    final_raw = raw_snapshots[-1]

    summary = {
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
        "struct_version": first_raw.get("version"),
        "struct_size": first_raw.get("struct_size"),
        "bucket_count": first_raw.get("bucket_count"),
        "max_total_workers_current": metric_max(raw_snapshots, "total_workers_current"),
        "max_idle_workers_current": metric_max(raw_snapshots, "idle_workers_current"),
        "max_nonidle_workers_current": metric_max(raw_snapshots, "nonidle_workers_current"),
        "max_active_workers_current": metric_max(raw_snapshots, "active_workers_current"),
        "final_total_workers_current": final_raw.get("total_workers_current"),
        "final_idle_workers_current": final_raw.get("idle_workers_current"),
        "final_nonidle_workers_current": final_raw.get("nonidle_workers_current"),
        "final_active_workers_current": final_raw.get("active_workers_current"),
        "delta_reqthreads_count": metric_delta(first_raw, final_raw, "reqthreads_count"),
        "delta_thread_enter_count": metric_delta(first_raw, final_raw, "thread_enter_count"),
        "delta_thread_return_count": metric_delta(first_raw, final_raw, "thread_return_count"),
        "delta_switch_block_count": metric_delta(first_raw, final_raw, "switch_block_count"),
        "delta_switch_unblock_count": metric_delta(first_raw, final_raw, "switch_unblock_count"),
        "delta_should_narrow_true_count": metric_delta(
            first_raw, final_raw, "should_narrow_true_count"
        ),
        "delta_requested_workers_total": metric_delta(
            first_raw, final_raw, "requested_workers_total"
        ),
        "delta_admitted_workers_total": metric_delta(
            first_raw, final_raw, "admitted_workers_total"
        ),
        "delta_blocked_workers_total": metric_delta(
            first_raw, final_raw, "blocked_workers_total"
        ),
        "delta_unblocked_workers_total": metric_delta(
            first_raw, final_raw, "unblocked_workers_total"
        ),
        "snapshots": snapshots,
    }

    for field in MONOTONIC_FIELDS:
        values = [snapshot.get(field) for snapshot in raw_snapshots if isinstance(snapshot.get(field), int)]
        summary[f"{field}_monotonic"] = monotonic_non_decreasing(values) if values else False

    return summary


def main() -> int:
    args = parse_args()
    snapshot_lines = load_snapshot_lines(args.serial_log)

    captures: dict[str, list[dict]] = {}
    for record in snapshot_lines:
        data = record.get("data") or {}
        label = data.get("label")
        if not isinstance(label, str):
            continue

        snapshot = data.get("snapshot") or {}
        captures.setdefault(label, []).append(
            {
                "generation": data.get("generation"),
                "interval_ms": data.get("interval_ms"),
                "duration_ms": data.get("duration_ms"),
                "snapshot": snapshot,
            }
        )

    summary_captures = {}
    for label, snapshots in sorted(captures.items()):
        ordered = sorted(snapshots, key=lambda snapshot: snapshot.get("generation") or 0)
        summary_captures[label] = summarize_capture(label, ordered)

    payload = {
        "schema_version": 1,
        "provider_scope": "pressure_only",
        "contract": CONTRACT,
        "preview_kind": "raw_snapshot_v1",
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
