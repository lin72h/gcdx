#!/usr/bin/env python3
"""Compare derived pressure-provider artifacts against the checked-in baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


AGGREGATE_LIMITS = {
    "request_events_total": {"max_ratio": 1.5, "slack": 8},
    "worker_entries_total": {"max_ratio": 1.5, "slack": 8},
    "worker_returns_total": {"max_ratio": 1.5, "slack": 8},
    "requested_workers_total": {"max_ratio": 1.5, "slack": 16},
    "admitted_workers_total": {"max_ratio": 1.5, "slack": 8},
    "blocked_events_total": {"max_ratio": 1.5, "slack": 16},
    "unblocked_events_total": {"max_ratio": 1.5, "slack": 16},
    "blocked_workers_total": {"max_ratio": 1.5, "slack": 32},
    "unblocked_workers_total": {"max_ratio": 1.5, "slack": 32},
    "total_workers_current": {"max_ratio": 1.0, "slack": 0},
    "idle_workers_current": {"max_ratio": 1.0, "slack": 0},
    "nonidle_workers_current": {"max_ratio": 1.0, "slack": 0},
    "active_workers_current": {"max_ratio": 1.0, "slack": 0},
    "should_narrow_true_total": {"max_ratio": 1.5, "slack": 2},
    "request_backlog_total": {"max_ratio": 1.5, "slack": 16},
    "block_backlog_total": {"max_ratio": 1.5, "slack": 16},
}

TOP_LEVEL_FIELDS = (
    ("schema_version",),
    ("provider_scope",),
    ("contract", "name"),
    ("contract", "version"),
    ("contract", "current_signal_field"),
    ("contract", "current_signal_kind"),
    ("contract", "quiescence_kind"),
    ("contract", "per_bucket_scope"),
    ("contract", "diagnostic_fields"),
    ("source_schema_version",),
    ("metadata", "generation_kind"),
    ("metadata", "monotonic_time_kind"),
    ("metadata", "snapshot_count"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--warn-only", action="store_true")
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def allowed_value(baseline: float, max_ratio: float, slack: float) -> float:
    return max(baseline * max_ratio, baseline + slack)


def nested_get(payload: dict, path: tuple[str, ...]):
    value = payload
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def compare_snapshot(mode: str, baseline_snapshot: dict | None, candidate_snapshot: dict | None):
    result = {
        "status": "ok",
        "checks": [],
        "failures": [],
    }
    failures: list[str] = []

    if baseline_snapshot is None:
        result["status"] = "missing-baseline"
        failures.append(f"{mode}: missing from baseline")
        result["failures"] = failures
        return result, failures

    if candidate_snapshot is None:
        result["status"] = "missing-candidate"
        failures.append(f"{mode}: missing from candidate")
        result["failures"] = failures
        return result, failures

    for field in ("status", "generation", "timestamp_kind", "monotonic_time_ns"):
        lhs = baseline_snapshot.get(field)
        rhs = candidate_snapshot.get(field)
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = f"{mode}: {field} differs (baseline {lhs!r}, candidate {rhs!r})"
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "snapshot_equal",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    for field in ("domain", "mode", "rounds", "tasks", "delay_ms"):
        lhs = (baseline_snapshot.get("workload") or {}).get(field)
        rhs = (candidate_snapshot.get("workload") or {}).get(field)
        if lhs is None or rhs is None:
            continue
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = f"{mode}: workload field {field} differs (baseline {lhs!r}, candidate {rhs!r})"
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "workload_equal",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    for field in (
        "has_per_bucket_diagnostics",
        "has_admission_feedback",
        "has_block_feedback",
        "has_live_current_counts",
        "has_narrow_feedback",
        "pressure_visible",
    ):
        lhs = (baseline_snapshot.get("flags") or {}).get(field)
        rhs = (candidate_snapshot.get("flags") or {}).get(field)
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = f"{mode}: flag {field} differs (baseline {lhs!r}, candidate {rhs!r})"
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "flag_equal",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    baseline_aggregate = baseline_snapshot.get("aggregate") or {}
    candidate_aggregate = candidate_snapshot.get("aggregate") or {}
    for field, limit in AGGREGATE_LIMITS.items():
        lhs = baseline_aggregate.get(field)
        rhs = candidate_aggregate.get(field)
        status = "ok"
        failure = None
        allowed = None

        if lhs is None:
            status = "not_applicable"
        elif rhs is None:
            status = "missing"
            failure = f"{mode}: aggregate field {field} missing from candidate"
            failures.append(failure)
        else:
            allowed = allowed_value(float(lhs), limit["max_ratio"], limit["slack"])
            if float(rhs) > allowed:
                status = "fail"
                failure = (
                    f"{mode}: aggregate {field} {rhs} exceeds {allowed:.2f} "
                    f"(baseline {lhs})"
                )
                failures.append(failure)

        result["checks"].append(
            {
                "kind": "aggregate_limit",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "limit": allowed,
                "status": status,
                "failure": failure,
            }
        )

    result["status"] = "ok" if failures == [] else "fail"
    result["failures"] = failures
    return result, failures


def main() -> int:
    args = parse_args()
    baseline = load(args.baseline)
    candidate = load(args.candidate)

    baseline_snapshots = baseline.get("snapshots") or {}
    candidate_snapshots = candidate.get("snapshots") or {}
    modes = sorted(set(baseline_snapshots) | set(candidate_snapshots))

    top_level = []
    failures: list[str] = []
    for path in TOP_LEVEL_FIELDS:
        lhs = nested_get(baseline, path)
        rhs = nested_get(candidate, path)
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = (
                f"{'.'.join(path)} differs "
                f"(baseline {lhs!r}, candidate {rhs!r})"
            )
            failures.append(failure)

        top_level.append(
            {
                "path": list(path),
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    results = {}
    for mode in modes:
        result, mode_failures = compare_snapshot(
            mode,
            baseline_snapshots.get(mode),
            candidate_snapshots.get(mode),
        )
        results[mode] = result
        failures.extend(mode_failures)

    payload = {
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "ok": failures == [],
        "verdict": "ok" if failures == [] else "fail",
        "top_level": top_level,
        "modes": results,
        "failures": failures,
    }

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    print(f"baseline={args.baseline}")
    print(f"candidate={args.candidate}")
    for check in top_level:
        print(
            f"top_level:{'.'.join(check['path'])} "
            f"baseline={check['baseline_value']!r} "
            f"candidate={check['candidate_value']!r} "
            f"status={check['status']}"
        )
    for mode in modes:
        print(f"{mode}: status={results[mode]['status']}")
        for check in results[mode]["checks"]:
            if check["kind"] == "aggregate_limit":
                print(
                    f"  aggregate:{check['field']} baseline={check['baseline_value']} "
                    f"candidate={check['candidate_value']} limit={check['limit']} "
                    f"status={check['status']}"
                )
            else:
                print(
                    f"  {check['kind']}:{check['field']} baseline={check['baseline_value']!r} "
                    f"candidate={check['candidate_value']!r} status={check['status']}"
                )

    print(f"verdict={payload['verdict']}")
    if failures:
        print("failures:")
        for failure in failures:
            print(f"  {failure}")

    if failures == []:
        return 0
    return 0 if args.warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main())
