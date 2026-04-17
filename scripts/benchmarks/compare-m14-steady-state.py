#!/usr/bin/env python3
"""Compare FreeBSD M13/M14 repeat-lane data against a macOS M14 report."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


PRIMARY_METRICS = (
    "root_push_mainq_default_overcommit",
    "root_poke_slow_default_overcommit",
)

SECONDARY_METRICS = (
    "pthread_workqueue_addthreads_requested_threads",
    "root_push_empty_default",
    "root_poke_slow_default",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("freebsd_baseline", type=Path)
    parser.add_argument("macos_report", type=Path)
    parser.add_argument(
        "--mode",
        default="swift.dispatchmain-taskhandles-after-repeat",
        help="Benchmark key in the FreeBSD baseline JSON.",
    )
    parser.add_argument(
        "--steady-start",
        type=int,
        default=8,
        help="First steady-state round (inclusive, zero-based).",
    )
    parser.add_argument(
        "--steady-end",
        type=int,
        default=63,
        help="Last steady-state round (inclusive, zero-based).",
    )
    parser.add_argument(
        "--stop-ratio",
        type=float,
        default=1.5,
        help="Max symmetric ratio for the primary metrics before we stop tuning.",
    )
    parser.add_argument(
        "--tune-ratio",
        type=float,
        default=2.0,
        help="FreeBSD/macOS ratio that strongly suggests more tuning.",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        help="Optional structured JSON output path.",
    )
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def avg(values: list[float]) -> float:
    return sum(values) / len(values)


def inclusive_window(values: list[float], start: int, end: int) -> list[float]:
    if start < 0 or end < start:
        raise ValueError(f"invalid round window {start}-{end}")
    if len(values) <= end:
        raise ValueError(
            f"round window {start}-{end} exceeds series length {len(values)}"
        )
    return values[start : end + 1]


def symmetric_ratio(lhs: float, rhs: float) -> float:
    if lhs == 0 and rhs == 0:
        return 1.0
    if lhs == 0 or rhs == 0:
        return math.inf
    return max(lhs, rhs) / min(lhs, rhs)


def freebsd_workload(benchmark: dict) -> dict:
    probe = benchmark.get("probe") or {}
    return {
        "domain": benchmark.get("domain"),
        "mode": benchmark.get("mode"),
        "rounds": probe.get("rounds"),
        "tasks": probe.get("tasks"),
        "delay_ms": probe.get("delay_ms"),
    }


def fallback_series(total: int | float, rounds: int) -> list[float]:
    if rounds <= 0:
        raise ValueError("round count must be positive for fallback series")
    return [float(total) / float(rounds)] * rounds


def constant_series(value: int | float, rounds: int) -> list[float]:
    if rounds <= 0:
        raise ValueError("round count must be positive for constant series")
    return [float(value)] * rounds


def freebsd_metric_series(benchmark: dict, metric: str) -> tuple[list[float] | None, str]:
    round_metrics = benchmark.get("round_metrics") or {}
    counters = (benchmark.get("libdispatch_counters") or [{}])[-1]
    probe = benchmark.get("probe") or {}
    rounds = probe.get("rounds")

    if metric == "pthread_workqueue_addthreads_requested_threads":
        series = round_metrics.get("round_ok_reqthreads_delta")
        if isinstance(series, list) and series:
            return ([float(value) for value in series], "freebsd.round_ok_reqthreads_delta")
        total = (benchmark.get("twq_delta") or {}).get("kern.twq.reqthreads_count")
        if isinstance(total, int) and isinstance(rounds, int):
            return (
                fallback_series(total, rounds),
                "freebsd.twq_delta.reqthreads_count/fallback",
            )
        return (None, "-")

    round_key = f"libdispatch_round_ok_{metric}_delta"
    series = round_metrics.get(round_key)
    if isinstance(series, list) and series:
        return ([float(value) for value in series], f"freebsd.{round_key}")

    total = counters.get(metric)
    if isinstance(total, int) and isinstance(rounds, int):
        return (
            fallback_series(total, rounds),
            f"freebsd.libdispatch_counters.{metric}/fallback",
        )
    return (None, "-")


def macos_metric_series(report: dict, metric: str) -> tuple[list[float] | None, str]:
    metrics = report.get("metrics") or {}
    per_round = metrics.get("per_round") or {}
    steady_state_per_round = metrics.get("steady_state_per_round") or {}
    full_run = metrics.get("full_run") or {}
    workload = report.get("workload") or {}
    rounds = workload.get("rounds")

    series = per_round.get(metric)
    if isinstance(series, list) and series:
        return ([float(value) for value in series], f"macos.metrics.per_round.{metric}")

    steady_value = steady_state_per_round.get(metric)
    if isinstance(steady_value, (int, float)) and isinstance(rounds, int):
        return (
            constant_series(float(steady_value), rounds),
            f"macos.metrics.steady_state_per_round.{metric}",
        )

    total = full_run.get(metric)
    if isinstance(total, (int, float)) and isinstance(rounds, int):
        return (
            fallback_series(total, rounds),
            f"macos.metrics.full_run.{metric}/fallback",
        )
    return (None, "-")


def ensure_matching_tuple(freebsd: dict, macos: dict) -> list[str]:
    mismatches = []
    for key in ("rounds", "tasks", "delay_ms"):
        lhs = freebsd.get(key)
        rhs = macos.get(key)
        if lhs is None or rhs is None:
            continue
        if lhs != rhs:
            mismatches.append(f"{key}: freebsd={lhs} macos={rhs}")
    return mismatches


def evaluate_metric(
    metric: str,
    role: str,
    benchmark: dict,
    macos_report: dict,
    steady_start: int,
    steady_end: int,
) -> dict:
    freebsd_series, freebsd_source = freebsd_metric_series(benchmark, metric)
    macos_series, macos_source = macos_metric_series(macos_report, metric)

    result = {
        "name": metric,
        "role": role,
        "status": "ok",
        "freebsd_source": freebsd_source,
        "macos_source": macos_source,
    }

    if freebsd_series is None or macos_series is None:
        result["status"] = "missing"
        return result

    freebsd_window = inclusive_window(freebsd_series, steady_start, steady_end)
    macos_window = inclusive_window(macos_series, steady_start, steady_end)
    freebsd_avg = avg(freebsd_window)
    macos_avg = avg(macos_window)
    freebsd_over_macos = math.inf if macos_avg == 0.0 else freebsd_avg / macos_avg

    result.update(
        {
            "freebsd_avg": freebsd_avg,
            "macos_avg": macos_avg,
            "symmetric_ratio": symmetric_ratio(freebsd_avg, macos_avg),
            "freebsd_over_macos": freebsd_over_macos,
        }
    )
    return result


def decide_verdict(
    tuple_mismatches: list[str],
    classification_ok: bool,
    primary_results: list[dict],
    stop_ratio: float,
    tune_ratio: float,
) -> tuple[str, str]:
    if tuple_mismatches or not classification_ok or len(primary_results) != len(PRIMARY_METRICS):
        return ("review", "")

    if any(result["freebsd_over_macos"] >= tune_ratio for result in primary_results):
        return ("keep_tuning_this_seam", "")

    if all(result["symmetric_ratio"] <= stop_ratio for result in primary_results):
        return ("stop_tuning_this_seam", "")

    return (
        "stop_tuning_this_seam",
        "borderline_stop_between_stop_ratio_and_tune_ratio;"
        "same qualitative seam and less than tune threshold",
    )


def build_comparison(args: argparse.Namespace) -> dict:
    freebsd_data = load(args.freebsd_baseline)
    macos_report = load(args.macos_report)

    benchmark = (freebsd_data.get("benchmarks") or {}).get(args.mode)
    if benchmark is None:
        raise SystemExit(f"missing benchmark {args.mode!r} in {args.freebsd_baseline}")

    freebsd = freebsd_workload(benchmark)
    macos = macos_report.get("workload") or {}
    tuple_mismatches = ensure_matching_tuple(freebsd, macos)

    classification = macos_report.get("classification") or {}
    classification_result = {
        "default_receives_source_traffic": classification.get(
            "default_receives_source_traffic"
        ),
        "default_overcommit_receives_mainq_traffic": classification.get(
            "default_overcommit_receives_mainq_traffic"
        ),
        "default_overcommit_continuation_dominant": classification.get(
            "default_overcommit_continuation_dominant"
        ),
    }
    classification_result["ok"] = bool(
        classification_result["default_receives_source_traffic"]
        and classification_result["default_overcommit_receives_mainq_traffic"]
    )

    metrics = []
    for metric in PRIMARY_METRICS + SECONDARY_METRICS:
        role = "primary" if metric in PRIMARY_METRICS else "secondary"
        metrics.append(
            evaluate_metric(
                metric,
                role,
                benchmark,
                macos_report,
                args.steady_start,
                args.steady_end,
            )
        )

    primary_results = [
        result
        for result in metrics
        if result["role"] == "primary" and result["status"] == "ok"
    ]
    verdict, verdict_note = decide_verdict(
        tuple_mismatches,
        classification_result["ok"],
        primary_results,
        args.stop_ratio,
        args.tune_ratio,
    )

    return {
        "schema_version": 1,
        "lane": "m14-steady-state-comparison",
        "freebsd_baseline": str(args.freebsd_baseline),
        "macos_report": str(args.macos_report),
        "mode": args.mode,
        "steady_state_window": {
            "start_round": args.steady_start,
            "end_round": args.steady_end,
        },
        "thresholds": {
            "stop_ratio": args.stop_ratio,
            "tune_ratio": args.tune_ratio,
        },
        "workload": {
            "freebsd": freebsd,
            "macos": macos,
            "mismatches": tuple_mismatches,
        },
        "classification": classification_result,
        "metrics": metrics,
        "decision": {
            "verdict": verdict,
            "note": verdict_note,
        },
    }


def fmt_float(value: float | None) -> str:
    if value is None:
        return "-"
    if math.isinf(value):
        return "inf"
    return f"{value:.2f}"


def emit_text(comparison: dict) -> None:
    workload = comparison["workload"]
    classification = comparison["classification"]
    thresholds = comparison["thresholds"]
    decision = comparison["decision"]

    print(f"freebsd_baseline={comparison['freebsd_baseline']}")
    print(f"macos_report={comparison['macos_report']}")
    print(f"mode={comparison['mode']}")
    print(
        "steady_state_window="
        f"{comparison['steady_state_window']['start_round']}"
        f"-{comparison['steady_state_window']['end_round']}"
        f" stop_ratio={fmt_float(thresholds['stop_ratio'])}"
        f" tune_ratio={fmt_float(thresholds['tune_ratio'])}"
    )
    print(
        "workload:"
        f" freebsd rounds={workload['freebsd'].get('rounds')}"
        f" tasks={workload['freebsd'].get('tasks')}"
        f" delay_ms={workload['freebsd'].get('delay_ms')}"
        f" | macos rounds={workload['macos'].get('rounds')}"
        f" tasks={workload['macos'].get('tasks')}"
        f" delay_ms={workload['macos'].get('delay_ms')}"
    )
    if workload["mismatches"]:
        print("workload_mismatch:")
        for mismatch in workload["mismatches"]:
            print(f"  {mismatch}")

    print(
        "classification:"
        f" default_receives_source_traffic={classification['default_receives_source_traffic']}"
        f" default_overcommit_receives_mainq_traffic={classification['default_overcommit_receives_mainq_traffic']}"
        f" continuation_dominant={classification['default_overcommit_continuation_dominant']}"
    )

    for metric in comparison["metrics"]:
        if metric["status"] != "ok":
            print(
                f"{metric['name']}: role={metric['role']}"
                f" freebsd_source={metric['freebsd_source']}"
                f" macos_source={metric['macos_source']}"
                " status=missing"
            )
            continue

        print(
            f"{metric['name']}: role={metric['role']}"
            f" freebsd_avg={fmt_float(metric.get('freebsd_avg'))} ({metric['freebsd_source']})"
            f" macos_avg={fmt_float(metric.get('macos_avg'))} ({metric['macos_source']})"
            f" symmetric_ratio={fmt_float(metric.get('symmetric_ratio'))}"
            f" freebsd_over_macos={fmt_float(metric.get('freebsd_over_macos'))}"
        )

    print(f"verdict={decision['verdict']}")
    if decision["note"]:
        print(f"verdict_note={decision['note']}")


def maybe_write_json(path: Path | None, comparison: dict) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(comparison, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    comparison = build_comparison(args)
    emit_text(comparison)
    maybe_write_json(args.json_out, comparison)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
