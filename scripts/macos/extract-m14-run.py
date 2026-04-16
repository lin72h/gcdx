#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize a macOS M14 stock comparison run into one JSON artifact."
    )
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--label", default="m14-macos-stock")
    parser.add_argument("--swift-log", type=Path)
    parser.add_argument("--c-log", type=Path)
    parser.add_argument("--symbols-json", type=Path)
    parser.add_argument(
        "--steady-state-start-round",
        type=int,
        default=8,
        help="First round to include in steady-state summaries.",
    )
    return parser.parse_args()


def parse_json_lines(path: Path | None) -> list[dict]:
    if path is None or not path.exists():
        return []

    records: list[dict] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw_line.strip()
        if not stripped.startswith("{"):
            continue
        try:
            records.append(json.loads(stripped))
        except json.JSONDecodeError:
            continue
    return records


def collect_round_metrics(events: list[dict]) -> dict | None:
    if not events:
        return None

    phases: dict[str, list[dict]] = {}
    for event in events:
        phase = event.get("phase")
        round_id = event.get("round")
        if not isinstance(phase, str) or not isinstance(round_id, int):
            continue
        phases.setdefault(phase, []).append(event)

    metrics: dict[str, list[int]] = {}
    for phase, phase_events in phases.items():
        phase_events = sorted(phase_events, key=lambda item: item["round"])
        metrics[f"{phase}_rounds"] = [event["round"] for event in phase_events]
        for key in sorted(
            {
                key
                for event in phase_events
                for key, value in event.items()
                if key not in ("mode", "phase") and isinstance(value, int)
            }
        ):
            series = [event[key] for event in phase_events if isinstance(event.get(key), int)]
            if len(series) == len(phase_events):
                metrics[f"{phase}_{key}"] = series

    return metrics or None


def summarize_steady_state(round_metrics: dict | None, start_round: int) -> dict | None:
    if not round_metrics:
        return None

    rounds = round_metrics.get("round-ok_rounds")
    if not isinstance(rounds, list):
        return None

    included_indexes = [
        index for index, round_id in enumerate(rounds) if isinstance(round_id, int) and round_id >= start_round
    ]
    if not included_indexes:
        return None

    summary = {
        "start_round": start_round,
        "included_rounds": len(included_indexes),
        "first_included_round": rounds[included_indexes[0]],
        "last_included_round": rounds[included_indexes[-1]],
    }

    for key, values in sorted(round_metrics.items()):
        if not key.startswith("round-ok_") or key.endswith("_rounds"):
            continue
        if not isinstance(values, list) or not values:
            continue
        if not all(isinstance(value, int) for value in values):
            continue
        if len(values) != len(rounds):
            continue
        selected = [values[index] for index in included_indexes]
        metric_name = key[len("round-ok_") :]
        summary[metric_name] = {
            "mean": sum(selected) / len(selected),
            "min": min(selected),
            "max": max(selected),
        }

    return summary


def parse_probe_log(path: Path | None, expected_kind: str) -> dict | None:
    if path is None or not path.exists():
        return None

    records = parse_json_lines(path)
    terminal = None
    progress_events = []
    mode = None

    for record in records:
        if record.get("kind") != expected_kind:
            continue
        data = record.get("data", {})
        if not mode and isinstance(data.get("mode"), str):
            mode = data["mode"]
        if record.get("status") == "progress":
            progress_events.append(data)
            continue
        terminal = record

    round_metrics = collect_round_metrics(progress_events)
    benchmark = {
        "mode": mode,
        "status": terminal.get("status") if terminal else None,
        "terminal": terminal,
        "progress_event_count": len(progress_events),
        "round_metrics": round_metrics,
    }
    return benchmark


def main() -> int:
    args = parse_args()
    symbols = None
    if args.symbols_json and args.symbols_json.exists():
        symbols = json.loads(args.symbols_json.read_text(encoding="utf-8"))

    swift = parse_probe_log(args.swift_log, "swift-probe")
    c_lane = parse_probe_log(args.c_log, "dispatch-probe")

    benchmarks = {}
    if swift:
        swift["steady_state"] = summarize_steady_state(
            swift.get("round_metrics"),
            args.steady_state_start_round,
        )
        benchmarks["swift.dispatchmain-taskhandles-after-repeat"] = swift
    if c_lane:
        c_lane["steady_state"] = summarize_steady_state(
            c_lane.get("round_metrics"),
            args.steady_state_start_round,
        )
        benchmarks["dispatch.main-executor-resume-repeat"] = c_lane

    payload = {
        "schema_version": 1,
        "metadata": {
            "label": args.label,
            "swift_log": str(args.swift_log.resolve()) if args.swift_log and args.swift_log.exists() else None,
            "c_log": str(args.c_log.resolve()) if args.c_log and args.c_log.exists() else None,
            "symbols_json": str(args.symbols_json.resolve())
            if args.symbols_json and args.symbols_json.exists()
            else None,
            "steady_state_start_round": args.steady_state_start_round,
        },
        "stock_symbols": symbols,
        "benchmarks": benchmarks,
    }
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
