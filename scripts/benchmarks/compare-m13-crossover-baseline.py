#!/usr/bin/env python3
"""Compare full-matrix M13.5 crossover artifacts against the checked-in baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DEFAULT_TWQ_CHECKS = (
    {"metric": "reqthreads_count", "label": "reqthreads_count", "max_ratio": 1.5, "slack": 8},
    {"metric": "thread_enter_count", "label": "thread_enter_count", "max_ratio": 1.5, "slack": 8},
    {"metric": "thread_return_count", "label": "thread_return_count", "max_ratio": 1.5, "slack": 8},
)


MODE_POLICIES = {
    "dispatch.basic": {
        "label": "dispatch basic",
        "probe_equal": ("requested", "completed"),
        "invariants": ("completed_eq_requested",),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "dispatch.pressure": {
        "label": "dispatch pressure",
        "probe_equal": (
            "requested_default",
            "requested_high",
            "completed_default",
            "completed_high",
        ),
        "invariants": (
            "completed_default_eq_requested_default",
            "completed_high_eq_requested_high",
        ),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "dispatch.burst-reuse": {
        "label": "dispatch burst reuse",
        "probe_equal": ("requested", "rounds", "rounds_completed", "warm_floor"),
        "probe_list_equal": ("round_new_threads",),
        "invariants": (
            "settled_total_le_warm_floor",
            "settled_idle_eq_settled_total",
            "settled_active_zero",
        ),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "dispatch.timeout-gap": {
        "label": "dispatch timeout gap",
        "probe_equal": ("requested", "rounds", "rounds_completed", "warm_floor"),
        "probe_list_equal": ("round_new_threads",),
        "invariants": (
            "settled_total_le_warm_floor",
            "settled_idle_eq_settled_total",
            "settled_active_zero",
        ),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "dispatch.sustained": {
        "label": "dispatch sustained",
        "probe_equal": (
            "requested_default",
            "requested_high",
            "completed_default",
            "completed_high",
            "warm_floor",
        ),
        "probe_upper_bound": (
            {"field": "peak_sample_total", "label": "peak_sample_total", "max_ratio": 1.25, "slack": 1.0},
            {"field": "settled_total", "label": "settled_total", "max_ratio": 1.25, "slack": 1.0},
        ),
        "invariants": (
            "completed_default_eq_requested_default",
            "completed_high_eq_requested_high",
            "settled_total_le_warm_floor",
            "settled_idle_eq_settled_total",
            "settled_active_zero",
        ),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "dispatch.main-executor-resume-repeat": {
        "label": "dispatch repeat control",
        "probe_equal": (
            "rounds",
            "tasks",
            "delay_ms",
            "completed_rounds",
            "total_sum",
            "expected_total_sum",
        ),
        "invariants": (
            "completed_rounds_eq_rounds",
            "total_sum_eq_expected_total_sum",
        ),
        "round_checks": (
            {
                "metric": "round_ok_reqthreads_delta",
                "label": "reqthreads_per_round",
                "max_ratio": 1.5,
                "slack": 1.0,
            },
        ),
    },
    "swift.dispatch-control": {
        "label": "swift dispatch control",
        "probe_equal": ("tasks", "completed", "sum"),
        "invariants": (
            "not_timed_out",
            "completed_eq_tasks",
        ),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "swift.mainqueue-resume": {
        "label": "swift mainqueue resume",
        "probe_equal": ("phase", "value"),
        "twq_checks": DEFAULT_TWQ_CHECKS,
    },
    "swift.dispatchmain-taskhandles-after-repeat": {
        "label": "swift dispatchMain repeat",
        "probe_equal": (
            "rounds",
            "tasks",
            "delay_ms",
            "completed_rounds",
            "total_sum",
            "expected_total_sum",
        ),
        "invariants": (
            "completed_rounds_eq_rounds",
            "total_sum_eq_expected_total_sum",
        ),
        "round_checks": (
            {
                "metric": "round_ok_reqthreads_delta",
                "label": "reqthreads_per_round",
                "max_ratio": 1.5,
                "slack": 4.0,
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


def allowed_value(baseline: float, max_ratio: float, slack: float) -> float:
    return max(baseline * max_ratio, baseline + slack)


def metric_value(delta: dict, metric: str):
    if metric in delta:
        return delta[metric]
    qualified = f"kern.twq.{metric}"
    if qualified in delta:
        return delta[qualified]
    return None


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


def avg(values: list[float]) -> float:
    return sum(values) / len(values)


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
        rounds = list(range(len(series)))
    else:
        rounds = round_metrics.get(round_key) or []
        if not isinstance(rounds, list) or len(rounds) != len(series):
            return None

    values: dict[int, float] = {}
    for round_number, value in zip(rounds, series):
        if not isinstance(round_number, int):
            continue
        if start <= round_number <= end:
            values[round_number] = float(value)
    return values or None


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


def evaluate_invariant(name: str, probe: dict) -> tuple[bool, str]:
    if name == "completed_eq_requested":
        return probe.get("completed") == probe.get("requested"), "completed == requested"
    if name == "completed_eq_tasks":
        return probe.get("completed") == probe.get("tasks"), "completed == tasks"
    if name == "completed_default_eq_requested_default":
        return (
            probe.get("completed_default") == probe.get("requested_default"),
            "completed_default == requested_default",
        )
    if name == "completed_high_eq_requested_high":
        return (
            probe.get("completed_high") == probe.get("requested_high"),
            "completed_high == requested_high",
        )
    if name == "settled_total_le_warm_floor":
        settled_total = probe.get("settled_total")
        warm_floor = probe.get("warm_floor")
        return (
            isinstance(settled_total, int)
            and isinstance(warm_floor, int)
            and settled_total <= warm_floor,
            "settled_total <= warm_floor",
        )
    if name == "settled_idle_eq_settled_total":
        return (
            probe.get("settled_idle") == probe.get("settled_total"),
            "settled_idle == settled_total",
        )
    if name == "settled_active_zero":
        return probe.get("settled_active") == 0, "settled_active == 0"
    if name == "not_timed_out":
        return probe.get("timed_out") is False, "timed_out == false"
    if name == "completed_rounds_eq_rounds":
        return (
            probe.get("completed_rounds") == probe.get("rounds"),
            "completed_rounds == rounds",
        )
    if name == "total_sum_eq_expected_total_sum":
        return (
            probe.get("total_sum") == probe.get("expected_total_sum"),
            "total_sum == expected_total_sum",
        )
    raise ValueError(f"unknown invariant {name}")


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

    baseline_probe = baseline_benchmark.get("probe") or {}
    candidate_probe = candidate_benchmark.get("probe") or {}

    for field in policy.get("probe_equal", ()):
        baseline_value = baseline_probe.get(field)
        candidate_value = candidate_probe.get(field)
        status = "ok"
        failure = None
        if baseline_value != candidate_value:
            status = "fail"
            failure = (
                f"{mode}: probe field {field} differs "
                f"(baseline {baseline_value!r}, candidate {candidate_value!r})"
            )
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "probe_equal",
                "field": field,
                "baseline_value": baseline_value,
                "candidate_value": candidate_value,
                "status": status,
                "failure": failure,
            }
        )

    for field in policy.get("probe_list_equal", ()):
        baseline_value = baseline_probe.get(field)
        candidate_value = candidate_probe.get(field)
        status = "ok"
        failure = None
        if baseline_value != candidate_value:
            status = "fail"
            failure = (
                f"{mode}: probe list {field} differs "
                f"(baseline {baseline_value!r}, candidate {candidate_value!r})"
            )
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "probe_list_equal",
                "field": field,
                "baseline_value": baseline_value,
                "candidate_value": candidate_value,
                "status": status,
                "failure": failure,
            }
        )

    for rule in policy.get("probe_upper_bound", ()):
        field = rule["field"]
        baseline_value = baseline_probe.get(field)
        candidate_value = candidate_probe.get(field)
        status = "ok"
        failure = None
        limit = None

        if not isinstance(baseline_value, (int, float)) or not isinstance(candidate_value, (int, float)):
            status = "missing"
            failure = f"{mode}: missing probe field {field}"
            failures.append(failure)
        else:
            limit = allowed_value(float(baseline_value), rule["max_ratio"], rule["slack"])
            if float(candidate_value) > limit:
                status = "fail"
                failure = (
                    f"{mode}: probe field {field} {candidate_value} exceeds {limit:.2f} "
                    f"(baseline {baseline_value})"
                )
                failures.append(failure)

        result["checks"].append(
            {
                "kind": "probe_upper_bound",
                "field": field,
                "baseline_value": baseline_value,
                "candidate_value": candidate_value,
                "limit": limit,
                "status": status,
                "failure": failure,
            }
        )

    for invariant in policy.get("invariants", ()):
        ok, label = evaluate_invariant(invariant, candidate_probe)
        status = "ok" if ok else "fail"
        failure = None if ok else f"{mode}: invariant failed: {label}"
        if failure:
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "invariant",
                "field": invariant,
                "label": label,
                "status": status,
                "failure": failure,
            }
        )

    baseline_delta = baseline_benchmark.get("twq_delta") or {}
    candidate_delta = candidate_benchmark.get("twq_delta") or {}
    for check in policy.get("twq_checks", ()):
        baseline_value = metric_value(baseline_delta, check["metric"])
        candidate_value = metric_value(candidate_delta, check["metric"])
        status = "ok"
        failure = None
        limit = None
        if baseline_value is None:
            status = "not_applicable"
        elif candidate_value is None:
            status = "missing"
            failure = f"{mode}: missing TWQ metric {check['metric']}"
            failures.append(failure)
        else:
            limit = allowed_value(float(baseline_value), check["max_ratio"], check["slack"])
            if float(candidate_value) > limit:
                status = "fail"
                failure = (
                    f"{mode}: {check['label']} {candidate_value} exceeds {limit:.2f} "
                    f"(baseline {baseline_value})"
                )
                failures.append(failure)
        result["checks"].append(
            {
                "kind": "twq_metric",
                "metric": check["metric"],
                "label": check["label"],
                "baseline_value": baseline_value,
                "candidate_value": candidate_value,
                "limit": limit,
                "status": status,
                "failure": failure,
            }
        )

    for check in policy.get("round_checks", ()):
        baseline_avg, candidate_avg, common_rounds = steady_avg_pair(
            baseline_benchmark, candidate_benchmark, check["metric"], start, end
        )
        status = "ok"
        failure = None
        limit = None
        if baseline_avg is None or candidate_avg is None:
            status = "missing"
            failure = f"{mode}: missing round metric {check['metric']}"
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
                "kind": "round_metric",
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
        "lane": "m13.5-crossover-assessment",
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
        print(
            f"{mode}: status={result['status']}"
            f" baseline_status={result.get('baseline_status', '-')}"
            f" candidate_status={result.get('candidate_status', '-')}"
        )
        for mismatch in (result.get("workload") or {}).get("mismatches") or []:
            print(f"  workload_mismatch={mismatch}")
        for check in result["checks"]:
            if check["kind"] == "probe_equal":
                print(
                    f"  probe_equal:{check['field']} "
                    f"baseline={check['baseline_value']!r} "
                    f"candidate={check['candidate_value']!r} "
                    f"status={check['status']}"
                )
            elif check["kind"] == "probe_list_equal":
                print(
                    f"  probe_list_equal:{check['field']} "
                    f"baseline={check['baseline_value']!r} "
                    f"candidate={check['candidate_value']!r} "
                    f"status={check['status']}"
                )
            elif check["kind"] == "probe_upper_bound":
                print(
                    f"  probe_upper_bound:{check['field']} "
                    f"baseline={check['baseline_value']!r} "
                    f"candidate={check['candidate_value']!r} "
                    f"limit={check['limit'] if check['limit'] is not None else '-'} "
                    f"status={check['status']}"
                )
            elif check["kind"] == "invariant":
                print(
                    f"  invariant:{check['label']} status={check['status']}"
                )
            elif check["kind"] == "twq_metric":
                print(
                    f"  twq_metric:{check['label']} "
                    f"baseline={check['baseline_value'] if check['baseline_value'] is not None else '-'} "
                    f"candidate={check['candidate_value'] if check['candidate_value'] is not None else '-'} "
                    f"limit={check['limit'] if check['limit'] is not None else '-'} "
                    f"status={check['status']}"
                )
            elif check["kind"] == "round_metric":
                print(
                    f"  round_metric:{check['label']} "
                    f"baseline={check['baseline_avg'] if check['baseline_avg'] is not None else '-'} "
                    f"candidate={check['candidate_avg'] if check['candidate_avg'] is not None else '-'} "
                    f"limit={check['limit'] if check['limit'] is not None else '-'} "
                    f"rounds={check['rounds_compared']} "
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
