#!/usr/bin/env python3
"""Compare pressure-provider observer smoke artifacts against the baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

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
    ("observer_kind",),
    ("source_session_kind",),
    ("source_view_kind",),
    ("metadata", "generation_kind"),
    ("metadata", "monotonic_time_kind"),
    ("metadata", "label_count"),
)

CAPTURE_EQUAL_FIELDS = (
    "label",
    "interval_ms",
    "duration_ms",
    "struct_version",
    "struct_size",
    "source_session_version",
    "source_session_struct_size",
    "source_view_version",
    "source_view_struct_size",
    "final_pressure_visible",
    "final_quiescent",
)

REQUIRED_TRUE_FIELDS = ("generation_contiguous", "monotonic_increasing", "final_quiescent")

MIN_RATIO_FIELDS = {
    "sample_count": 0.50,
    "pressure_visible_samples": 0.25,
    "nonidle_samples": 0.25,
    "request_backlog_samples": 0.25,
    "block_backlog_samples": 0.25,
    "narrow_feedback_samples": 0.25,
    "quiescent_samples": 0.25,
    "max_nonidle_workers_current": 0.50,
    "max_request_backlog_total": 0.50,
    "max_block_backlog_total": 0.50,
}

UPPER_LIMIT_FIELDS = ("final_total_workers_current", "final_nonidle_workers_current")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--warn-only", action="store_true")
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def nested_get(payload: dict, path: tuple[str, ...]):
    value = payload
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def minimum_value(baseline_value: int, ratio: float) -> float:
    if baseline_value <= 1:
        return float(baseline_value)
    return baseline_value * ratio


def compare_capture(label: str, baseline_capture: dict | None, candidate_capture: dict | None):
    result = {"status": "ok", "checks": [], "failures": []}
    failures: list[str] = []

    if baseline_capture is None:
        failure = f"{label}: missing from baseline"
        return {"status": "missing-baseline", "checks": [], "failures": [failure]}, [failure]

    if candidate_capture is None:
        failure = f"{label}: missing from candidate"
        return {"status": "missing-candidate", "checks": [], "failures": [failure]}, [failure]

    for field in REQUIRED_TRUE_FIELDS:
        candidate_value = candidate_capture.get(field)
        status = "ok"
        failure = None
        if candidate_value is not True:
            status = "fail"
            failure = f"{label}: {field} is not true"
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "boolean_required",
                "field": field,
                "candidate_value": candidate_value,
                "status": status,
                "failure": failure,
            }
        )

    for field in CAPTURE_EQUAL_FIELDS:
        lhs = baseline_capture.get(field)
        rhs = candidate_capture.get(field)
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = f"{label}: {field} differs (baseline {lhs!r}, candidate {rhs!r})"
            failures.append(failure)
        result["checks"].append(
            {
                "kind": "equal",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    for field, ratio in MIN_RATIO_FIELDS.items():
        lhs = baseline_capture.get(field)
        rhs = candidate_capture.get(field)
        status = "ok"
        failure = None
        minimum = None

        if lhs is None:
            status = "not_applicable"
        elif rhs is None:
            status = "missing"
            failure = f"{label}: {field} missing from candidate"
            failures.append(failure)
        else:
            minimum = minimum_value(int(lhs), ratio)
            if float(rhs) < minimum:
                status = "fail"
                failure = (
                    f"{label}: {field} {rhs} is below {minimum:.2f} "
                    f"(baseline {lhs})"
                )
                failures.append(failure)

        result["checks"].append(
            {
                "kind": "minimum_ratio",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "minimum": minimum,
                "status": status,
                "failure": failure,
            }
        )

    for field in UPPER_LIMIT_FIELDS:
        lhs = baseline_capture.get(field)
        rhs = candidate_capture.get(field)
        status = "ok"
        failure = None
        limit = lhs

        if lhs is None:
            status = "not_applicable"
        elif rhs is None:
            status = "missing"
            failure = f"{label}: {field} missing from candidate"
            failures.append(failure)
        elif int(rhs) > int(lhs):
            status = "fail"
            failure = f"{label}: {field} {rhs} exceeds {lhs}"
            failures.append(failure)

        result["checks"].append(
            {
                "kind": "upper_limit",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "limit": limit,
                "status": status,
                "failure": failure,
            }
        )

    result["status"] = "ok" if not failures else "fail"
    result["failures"] = failures
    return result, failures


def main() -> int:
    args = parse_args()
    baseline = load(args.baseline)
    candidate = load(args.candidate)

    top_level_checks = []
    failures: list[str] = []
    for path in TOP_LEVEL_FIELDS:
        lhs = nested_get(baseline, path)
        rhs = nested_get(candidate, path)
        status = "ok"
        failure = None
        if lhs != rhs:
            status = "fail"
            failure = f"{'.'.join(path)} differs (baseline {lhs!r}, candidate {rhs!r})"
            failures.append(failure)
        top_level_checks.append(
            {
                "path": list(path),
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )

    baseline_captures = baseline.get("captures") or {}
    candidate_captures = candidate.get("captures") or {}
    labels = sorted(set(baseline_captures) | set(candidate_captures))

    results = {}
    for label in labels:
        result, label_failures = compare_capture(
            label,
            baseline_captures.get(label),
            candidate_captures.get(label),
        )
        results[label] = result
        failures.extend(label_failures)

    payload = {
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "ok": not failures,
        "verdict": "ok" if not failures else "fail",
        "top_level": top_level_checks,
        "captures": results,
        "failures": failures,
    }

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    print(f"baseline={args.baseline}")
    print(f"candidate={args.candidate}")
    for check in top_level_checks:
        print(
            f"top_level:{'.'.join(check['path'])} "
            f"baseline={check['baseline_value']!r} "
            f"candidate={check['candidate_value']!r} "
            f"status={check['status']}"
        )
    for label in labels:
        print(f"{label}: status={results[label]['status']}")
        for check in results[label]["checks"]:
            if check["kind"] == "minimum_ratio":
                print(
                    f"  minimum:{check['field']} baseline={check['baseline_value']} "
                    f"candidate={check['candidate_value']} minimum={check['minimum']} "
                    f"status={check['status']}"
                )
            elif check["kind"] == "upper_limit":
                print(
                    f"  upper:{check['field']} baseline={check['baseline_value']} "
                    f"candidate={check['candidate_value']} limit={check['limit']} "
                    f"status={check['status']}"
                )
            else:
                print(
                    f"  required:{check['field']} candidate={check.get('candidate_value')!r} "
                    f"status={check['status']}"
                )

    print(f"verdict={payload['verdict']}")
    if failures:
        print("failures:")
        for failure in failures:
            print(f"  {failure}")

    if not failures:
        return 0
    return 0 if args.warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main())
