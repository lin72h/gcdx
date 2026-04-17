#!/usr/bin/env python3
"""Compare focused FreeBSD repeat-lane artifacts against the checked-in baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


MODE_POLICIES = {
    "dispatch.main-executor-resume-repeat": {
        "label": "dispatch repeat control",
        "checks": (
            {
                "metric": "round_ok_reqthreads_delta",
                "label": "reqthreads_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
            {
                "metric": "libdispatch_round_ok_root_push_mainq_default_overcommit_delta",
                "label": "root_push_mainq_default_overcommit_per_round",
                "max_ratio": 1.0,
                "slack": 0.0,
            },
            {
                "metric": "libdispatch_round_ok_root_poke_slow_default_overcommit_delta",
                "label": "root_poke_slow_default_overcommit_per_round",
                "max_ratio": 1.0,
                "slack": 0.0,
            },
            {
                "metric": "libdispatch_round_ok_root_push_empty_default_delta",
                "label": "root_push_empty_default_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
            {
                "metric": "libdispatch_round_ok_root_poke_slow_default_delta",
                "label": "root_poke_slow_default_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
        ),
    },
    "swift.dispatchmain-taskhandles-after-repeat": {
        "label": "swift dispatchMain repeat",
        "checks": (
            {
                "metric": "round_ok_reqthreads_delta",
                "label": "reqthreads_per_round",
                "max_ratio": 1.5,
                "slack": 4.0,
            },
            {
                "metric": "libdispatch_round_ok_root_push_mainq_default_overcommit_delta",
                "label": "root_push_mainq_default_overcommit_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
            {
                "metric": "libdispatch_round_ok_root_poke_slow_default_overcommit_delta",
                "label": "root_poke_slow_default_overcommit_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
            {
                "metric": "libdispatch_round_ok_root_push_empty_default_delta",
                "label": "root_push_empty_default_per_round",
                "max_ratio": 2.0,
                "slack": 2.0,
            },
            {
                "metric": "libdispatch_round_ok_root_poke_slow_default_delta",
                "label": "root_poke_slow_default_per_round",
                "max_ratio": 2.0,
                "slack": 2.0,
            },
        ),
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
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
        "--json-out",
        type=Path,
        help="Optional structured JSON output path.",
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="Print failures but exit 0.",
    )
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def inclusive_window(values: list[float], start: int, end: int) -> list[float]:
    if start < 0 or end < start:
        raise ValueError(f"invalid round window {start}-{end}")
    if len(values) <= end:
        raise ValueError(
            f"round window {start}-{end} exceeds series length {len(values)}"
        )
    return values[start : end + 1]


def avg(values: list[float]) -> float:
    return sum(values) / len(values)


def allowed_value(baseline: float, max_ratio: float, slack: float) -> float:
    return max(baseline * max_ratio, baseline + slack)


def workload_tuple(benchmark: dict) -> dict:
    probe = benchmark.get("probe") or {}
    return {
        "domain": benchmark.get("domain"),
        "mode": benchmark.get("mode"),
        "rounds": probe.get("rounds"),
        "tasks": probe.get("tasks"),
        "delay_ms": probe.get("delay_ms"),
    }


def workload_mismatches(baseline: dict, candidate: dict) -> list[str]:
    mismatches = []
    for key in ("rounds", "tasks", "delay_ms"):
        lhs = baseline.get(key)
        rhs = candidate.get(key)
        if lhs is None or rhs is None:
            continue
        if lhs != rhs:
            mismatches.append(f"{key}: baseline={lhs} candidate={rhs}")
    return mismatches


def metric_round_key(round_metrics: dict, metric: str, series_length: int) -> str | None:
    candidates: list[str] = []

    if metric.startswith("libdispatch_round_ok_") and metric.endswith("_delta"):
        candidates.extend(
            ("libdispatch_round_ok_delta_rounds", "libdispatch_round_ok_rounds")
        )
    elif metric.startswith("libdispatch_round_ok_"):
        candidates.append("libdispatch_round_ok_rounds")
    elif metric.startswith("libdispatch_round_start_"):
        candidates.append("libdispatch_round_start_rounds")
    elif metric.startswith("round_ok_"):
        candidates.append("round_ok_rounds")
    elif metric.startswith("round_start_"):
        candidates.append("round_start_rounds")

    for key in candidates:
        rounds = round_metrics.get(key)
        if isinstance(rounds, list) and len(rounds) == series_length:
            return key
    return None


def metric_round_map(
    benchmark: dict, metric: str, start: int, end: int
) -> dict[int, float] | None:
    round_metrics = benchmark.get("round_metrics") or {}
    series = round_metrics.get(metric)
    if not isinstance(series, list) or not series:
        return None

    round_key = metric_round_key(round_metrics, metric, len(series))
    if round_key is None:
        return {
            round_number: float(value)
            for round_number, value in enumerate(series)
            if start <= round_number <= end
        }

    rounds = round_metrics.get(round_key) or []
    return {
        int(round_number): float(value)
        for round_number, value in zip(rounds, series)
        if isinstance(round_number, int) and start <= round_number <= end
    }


def steady_avg_pair(
    baseline_benchmark: dict,
    candidate_benchmark: dict,
    metric: str,
    start: int,
    end: int,
) -> tuple[float | None, float | None, list[int]]:
    baseline_map = metric_round_map(baseline_benchmark, metric, start, end)
    candidate_map = metric_round_map(candidate_benchmark, metric, start, end)

    if baseline_map is None or candidate_map is None:
        return None, None, []

    common_rounds = sorted(set(baseline_map) & set(candidate_map))
    if not common_rounds:
        return None, None, []

    return (
        avg([baseline_map[round_number] for round_number in common_rounds]),
        avg([candidate_map[round_number] for round_number in common_rounds]),
        common_rounds,
    )


def compare_mode(
    mode: str,
    policy: dict,
    baseline_benchmark: dict | None,
    candidate_benchmark: dict | None,
    start: int,
    end: int,
) -> tuple[dict, list[str]]:
    result = {
        "label": policy["label"],
        "status": "ok",
        "baseline_status": None,
        "candidate_status": None,
        "workload": {},
        "checks": [],
        "failures": [],
    }
    failures: list[str] = []

    if baseline_benchmark is None:
        result["status"] = "missing-baseline"
        failures.append(f"{mode}: missing from baseline")
        result["failures"] = failures
        return result, failures

    if candidate_benchmark is None:
        result["status"] = "missing-candidate"
        failures.append(f"{mode}: missing from candidate")
        result["failures"] = failures
        return result, failures

    baseline_workload = workload_tuple(baseline_benchmark)
    candidate_workload = workload_tuple(candidate_benchmark)
    result["baseline_status"] = baseline_benchmark.get("status")
    result["candidate_status"] = candidate_benchmark.get("status")
    result["workload"] = {
        "baseline": baseline_workload,
        "candidate": candidate_workload,
        "mismatches": workload_mismatches(baseline_workload, candidate_workload),
    }

    if baseline_benchmark.get("status") == "ok" and candidate_benchmark.get("status") != "ok":
        failures.append(
            f"{mode}: status regressed {baseline_benchmark.get('status')!r}->{candidate_benchmark.get('status')!r}"
        )

    for mismatch in result["workload"]["mismatches"]:
        failures.append(f"{mode}: workload mismatch {mismatch}")

    for check in policy["checks"]:
        baseline_avg, candidate_avg, common_rounds = steady_avg_pair(
            baseline_benchmark,
            candidate_benchmark,
            check["metric"],
            start,
            end,
        )
        status = "ok"
        failure = None
        limit = None

        if baseline_avg is None or candidate_avg is None:
            status = "missing"
            failure = f"{mode}: missing metric {check['metric']}"
            failures.append(failure)
        else:
            limit = allowed_value(baseline_avg, check["max_ratio"], check["slack"])
            if candidate_avg > limit:
                status = "fail"
                failure = (
                    f"{mode}: {check['label']} {candidate_avg:.2f} exceeds {limit:.2f} "
                    f"(baseline {baseline_avg:.2f})"
                )
                failures.append(failure)

        result["checks"].append(
            {
                "metric": check["metric"],
                "label": check["label"],
                "baseline_avg": baseline_avg,
                "candidate_avg": candidate_avg,
                "limit": limit,
                "rounds_compared": common_rounds,
                "status": status,
                "failure": failure,
            }
        )

    result["failures"] = failures
    result["status"] = "fail" if failures else "ok"
    return result, failures


def build_comparison(args: argparse.Namespace) -> dict:
    baseline = load(args.baseline)
    candidate = load(args.candidate)
    baseline_benchmarks = baseline.get("benchmarks", {})
    candidate_benchmarks = candidate.get("benchmarks", {})

    modes: dict[str, dict] = {}
    failures: list[str] = []
    for mode, policy in MODE_POLICIES.items():
        mode_result, mode_failures = compare_mode(
            mode,
            policy,
            baseline_benchmarks.get(mode),
            candidate_benchmarks.get(mode),
            args.steady_start,
            args.steady_end,
        )
        modes[mode] = mode_result
        failures.extend(mode_failures)

    return {
        "schema_version": 1,
        "lane": "m13-repeat-gate",
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "steady_state_window": {
            "start_round": args.steady_start,
            "end_round": args.steady_end,
        },
        "ok": failures == [],
        "failures": failures,
        "modes": modes,
    }


def emit_text(comparison: dict) -> None:
    print(f"baseline={comparison['baseline']}")
    print(f"candidate={comparison['candidate']}")
    print(
        "steady_state_window="
        f"{comparison['steady_state_window']['start_round']}"
        f"-{comparison['steady_state_window']['end_round']}"
    )
    for mode, result in comparison["modes"].items():
        workload = result.get("workload") or {}
        mismatches = workload.get("mismatches") or []
        print(
            f"{mode}: status={result['status']}"
            f" baseline_status={result.get('baseline_status', '-')}"
            f" candidate_status={result.get('candidate_status', '-')}"
        )
        for mismatch in mismatches:
            print(f"  workload_mismatch={mismatch}")
        for check in result["checks"]:
            baseline_avg = check["baseline_avg"]
            candidate_avg = check["candidate_avg"]
            limit = check["limit"]
            print(
                f"  {check['label']}: "
                f"baseline={baseline_avg if baseline_avg is not None else '-'} "
                f"candidate={candidate_avg if candidate_avg is not None else '-'} "
                f"limit={limit if limit is not None else '-'} "
                f"status={check['status']}"
            )
    print(f"verdict={'ok' if comparison['ok'] else 'fail'}")
    if comparison["failures"]:
        print("failures:")
        for failure in comparison["failures"]:
            print(f"  {failure}")


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
    if comparison["ok"] or args.warn_only:
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
