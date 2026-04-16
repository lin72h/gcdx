#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean


PRIMARY_FREEBSD_STEADY_STATE = {
    "root_push_mainq_default_overcommit": 3.21,
    "root_poke_slow_default_overcommit": 3.21,
    "pthread_workqueue_addthreads_requested_threads": 18.36,
}

CONTROL_FREEBSD_STEADY_STATE = {
    "root_push_mainq_default_overcommit": 0.00,
    "root_poke_slow_default_overcommit": 0.00,
}

REQUIRED_METRICS = (
    "root_push_mainq_default_overcommit",
    "root_poke_slow_default_overcommit",
    "pthread_workqueue_addthreads_calls",
    "pthread_workqueue_addthreads_requested_threads",
    "root_push_empty_default",
    "root_poke_slow_default",
    "root_push_source_default",
)

EXTRA_METRICS = (
    "root_push_total_default",
    "root_push_continuation_default",
    "root_requested_threads_default",
    "root_push_total_default_overcommit",
    "root_push_empty_default_overcommit",
    "root_push_continuation_default_overcommit",
    "root_requested_threads_default_overcommit",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build an M14 macOS comparison report from introspection-backed workload logs."
    )
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--swift-log", required=True, type=Path)
    parser.add_argument("--c-log", required=True, type=Path)
    parser.add_argument("--symbols-json", type=Path)
    parser.add_argument("--label", default="m14-macos-introspection")
    parser.add_argument("--steady-state-start-round", type=int, default=8)
    return parser.parse_args()


def parse_json_lines(path: Path) -> list[dict]:
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


def phase_index(records: list[dict]) -> dict[str, list[dict]]:
    phases: dict[str, list[dict]] = {}
    for record in records:
        data = record.get("data", {})
        phase = data.get("phase")
        if isinstance(phase, str):
            phases.setdefault(phase, []).append(data)
    for phase_records in phases.values():
        phase_records.sort(key=lambda item: item.get("round", -1))
    return phases


def last_counter_event(events: list[dict]) -> dict | None:
    for event in reversed(events):
        if any(isinstance(event.get(metric), int) for metric in REQUIRED_METRICS):
            return event
    return None


def full_run_metrics(phases: dict[str, list[dict]]) -> dict[str, int] | None:
    last = last_counter_event(phases.get("round-ok-counters", []))
    if not last:
        return None
    metrics = {
        metric: int(last.get(metric, 0))
        for metric in (*REQUIRED_METRICS, *EXTRA_METRICS)
        if isinstance(last.get(metric), int)
    }
    metrics["round"] = int(last.get("round", -1))
    metrics["completed_rounds"] = int(last.get("completed_rounds", 0))
    return metrics


def build_per_round(phases: dict[str, list[dict]]) -> list[dict]:
    delta_by_round = {
        int(event["round"]): event
        for event in phases.get("round-ok-counters-delta", [])
        if isinstance(event.get("round"), int)
    }
    ok_by_round = {
        int(event["round"]): event
        for event in phases.get("round-ok", [])
        if isinstance(event.get("round"), int)
    }
    rows: list[dict] = []
    for round_id in sorted(delta_by_round):
        delta = delta_by_round[round_id]
        ok = ok_by_round.get(round_id, {})
        row = {
            "round": round_id,
            "completed_rounds": int(delta.get("completed_rounds", 0)),
        }
        if isinstance(ok.get("elapsed_ns"), int):
            row["elapsed_ns"] = int(ok["elapsed_ns"])
        for metric in (*REQUIRED_METRICS, *EXTRA_METRICS):
            if isinstance(delta.get(metric), int):
                row[metric] = int(delta[metric])
        rows.append(row)
    return rows


def steady_state_summary(per_round: list[dict], start_round: int) -> dict:
    selected = [row for row in per_round if row.get("round", -1) >= start_round]
    summary = {
        "start_round": start_round,
        "end_round": selected[-1]["round"] if selected else None,
        "included_rounds": len(selected),
        "metrics_per_round": {},
    }
    if not selected:
        return summary

    metric_names = [
        key
        for key in selected[0]
        if key not in {"round", "completed_rounds"} and all(isinstance(row.get(key), int) for row in selected)
    ]
    for metric in sorted(metric_names):
        values = [int(row[metric]) for row in selected]
        summary["metrics_per_round"][metric] = {
            "mean": mean(values),
            "min": min(values),
            "max": max(values),
        }
    return summary


def classify(full_run: dict | None, steady_state: dict) -> dict[str, bool]:
    metrics = steady_state.get("metrics_per_round", {})
    mainq = metrics.get("root_push_mainq_default_overcommit", {}).get("mean", 0.0)
    continuation = metrics.get("root_push_continuation_default_overcommit", {}).get("mean", 0.0)
    source_default = metrics.get("root_push_source_default", {}).get("mean", 0.0)
    if full_run:
        source_default = max(source_default, float(full_run.get("root_push_source_default", 0)))
        mainq = max(mainq, float(full_run.get("root_push_mainq_default_overcommit", 0)))
        continuation = max(
            continuation,
            float(full_run.get("root_push_continuation_default_overcommit", 0)),
        )
    return {
        "default_receives_source_traffic": source_default > 0.0,
        "default_overcommit_receives_mainq_traffic": mainq > 0.0,
        "default_overcommit_continuation_dominant": continuation > mainq,
    }


def ratio(macos_value: float, freebsd_value: float) -> float | None:
    if freebsd_value == 0:
        return 1.0 if macos_value == 0 else None
    return macos_value / freebsd_value


def compare_to_freebsd(steady_state: dict, freebsd_reference: dict[str, float]) -> dict:
    metrics = steady_state.get("metrics_per_round", {})
    out: dict[str, dict] = {}
    for metric, freebsd_value in freebsd_reference.items():
        macos_value = float(metrics.get(metric, {}).get("mean", 0.0))
        metric_ratio = ratio(macos_value, freebsd_value)
        out[metric] = {
            "macos_per_round": macos_value,
            "freebsd_per_round": freebsd_value,
            "ratio_vs_freebsd": metric_ratio,
            "within_1_5x": metric_ratio is not None and (1 / 1.5) <= metric_ratio <= 1.5,
            "within_about_1_5x": metric_ratio is not None and 0.6 <= metric_ratio <= 1.65,
            "materially_lower_than_freebsd": metric_ratio is not None and metric_ratio <= 0.5,
        }
    return out


def build_benchmark(path: Path, expected_kind: str, start_round: int, control: bool) -> dict:
    records = [record for record in parse_json_lines(path) if record.get("kind") == expected_kind]
    phases = phase_index(records)
    terminal = next((record for record in reversed(records) if record.get("status") != "progress"), None)
    before_spawn = phases.get("before-spawn", [{}])[0]
    per_round = build_per_round(phases)
    steady_state = steady_state_summary(per_round, start_round)
    full_run = full_run_metrics(phases)
    benchmark = {
        "mode": before_spawn.get("mode"),
        "dispatch_introspection_available": bool(before_spawn.get("dispatch_introspection_available")),
        "full_run": full_run,
        "per_round": {
            "rows": per_round,
            "steady_state": steady_state,
        },
        "classification": classify(full_run, steady_state),
        "terminal": terminal,
        "raw_log": str(path.resolve()),
    }
    benchmark["comparison_to_freebsd"] = compare_to_freebsd(
        steady_state,
        CONTROL_FREEBSD_STEADY_STATE if control else PRIMARY_FREEBSD_STEADY_STATE,
    )
    return benchmark


def build_decision(swift_benchmark: dict, c_benchmark: dict) -> dict:
    swift_compare = swift_benchmark["comparison_to_freebsd"]
    swift_class = swift_benchmark["classification"]
    control_compare = c_benchmark["comparison_to_freebsd"]

    push = swift_compare["root_push_mainq_default_overcommit"]
    poke = swift_compare["root_poke_slow_default_overcommit"]
    same_split = (
        swift_class["default_receives_source_traffic"]
        and swift_class["default_overcommit_receives_mainq_traffic"]
        and not swift_class["default_overcommit_continuation_dominant"]
    )
    control_zeroish = (
        control_compare["root_push_mainq_default_overcommit"]["macos_per_round"] == 0.0
        and control_compare["root_poke_slow_default_overcommit"]["macos_per_round"] == 0.0
    )

    if same_split and control_zeroish and push["within_about_1_5x"] and poke["within_about_1_5x"]:
        outcome = "stop_tuning_this_seam"
        rationale = (
            "macOS shows the same qualitative split, the C control stays at zero for the seam, "
            "and the primary mainq/poke rates remain within the intended 'about 1.5x' boundary"
        )
    elif push["materially_lower_than_freebsd"] and poke["materially_lower_than_freebsd"]:
        outcome = "freebsd_likely_still_has_coalescing_gap"
        rationale = (
            "macOS is materially lower on both mainq handoff pushes and default-overcommit poke_slow"
        )
    else:
        outcome = "inconclusive"
        rationale = "macOS classification or rate ratios do not cleanly satisfy the stop-versus-tune boundary"

    return {
        "window": "rounds 8-63",
        "same_qualitative_split": same_split,
        "control_supports_specificity": control_zeroish,
        "outcome": outcome,
        "rationale": rationale,
    }


def main() -> int:
    args = parse_args()
    symbols = None
    if args.symbols_json and args.symbols_json.exists():
        symbols = json.loads(args.symbols_json.read_text(encoding="utf-8"))

    swift_benchmark = build_benchmark(args.swift_log, "swift-probe", args.steady_state_start_round, control=False)
    c_benchmark = build_benchmark(args.c_log, "dispatch-probe", args.steady_state_start_round, control=True)

    payload = {
        "schema_version": 1,
        "label": args.label,
        "measurement_setup": {
            "method": "stock-libdispatch-introspection-hooks",
            "dyld_library_path": "/usr/lib/system/introspection",
            "steady_state_start_round": args.steady_state_start_round,
            "primary_workload": "swift.dispatchmain-taskhandles-after-repeat",
            "secondary_workload": "dispatch.main-executor-resume-repeat",
        },
        "symbol_probe_reality": symbols,
        "freebsd_reference": {
            "primary_steady_state": PRIMARY_FREEBSD_STEADY_STATE,
            "control_steady_state": CONTROL_FREEBSD_STEADY_STATE,
        },
        "benchmarks": {
            "swift.dispatchmain-taskhandles-after-repeat": swift_benchmark,
            "dispatch.main-executor-resume-repeat": c_benchmark,
        },
        "decision": build_decision(swift_benchmark, c_benchmark),
    }
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
