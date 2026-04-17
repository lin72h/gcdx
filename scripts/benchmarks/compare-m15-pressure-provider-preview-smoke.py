#!/usr/bin/env python3
"""Compare raw preview pressure-provider smoke artifacts against the baseline."""

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
    ("preview_kind",),
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
    "bucket_count",
)

REQUIRED_TRUE_FIELDS = (
    "generation_contiguous",
    "monotonic_increasing",
    "reqthreads_count_monotonic",
    "thread_enter_count_monotonic",
    "thread_return_count_monotonic",
    "switch_block_count_monotonic",
    "switch_unblock_count_monotonic",
    "should_narrow_true_count_monotonic",
    "requested_workers_total_monotonic",
    "admitted_workers_total_monotonic",
    "blocked_workers_total_monotonic",
    "unblocked_workers_total_monotonic",
)

MIN_RATIO_FIELDS = {
    "sample_count": 0.50,
    "delta_reqthreads_count": 0.50,
    "delta_thread_enter_count": 0.50,
    "delta_switch_block_count": 0.50,
    "delta_requested_workers_total": 0.50,
    "delta_blocked_workers_total": 0.50,
    "max_nonidle_workers_current": 0.50,
}

UPPER_LIMIT_FIELDS = (
    "final_total_workers_current",
    "final_nonidle_workers_current",
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
            minimum = minimum_value(lhs, ratio)
            if rhs * 1.0 < minimum:
                status = "fail"
                failure = f"{label}: {field} {rhs} is below {minimum} (baseline {lhs})"
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
        if lhs is None:
            status = "not_applicable"
        elif rhs is None:
            status = "missing"
            failure = f"{label}: {field} missing from candidate"
            failures.append(failure)
        elif rhs > lhs:
            status = "fail"
            failure = f"{label}: {field} {rhs} exceeds {lhs}"
            failures.append(failure)

        result["checks"].append(
            {
                "kind": "upper_limit",
                "field": field,
                "baseline_value": lhs,
                "candidate_value": rhs,
                "limit": lhs,
                "status": status,
                "failure": failure,
            }
        )

    if failures:
        result["status"] = "fail"
    result["failures"] = failures
    return result, failures


def main() -> int:
    args = parse_args()
    baseline = load(args.baseline)
    candidate = load(args.candidate)

    checks = []
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
        checks.append(
            {
                "kind": "top_level",
                "path": ".".join(path),
                "baseline_value": lhs,
                "candidate_value": rhs,
                "status": status,
                "failure": failure,
            }
        )
        print(
            f"top_level:{'.'.join(path)} baseline={lhs!r} candidate={rhs!r} status={status}"
        )

    baseline_captures = baseline.get("captures") or {}
    candidate_captures = candidate.get("captures") or {}

    labels = sorted(set(baseline_captures) | set(candidate_captures))
    capture_results = {}

    for label in labels:
        result, capture_failures = compare_capture(
            label,
            baseline_captures.get(label),
            candidate_captures.get(label),
        )
        capture_results[label] = result
        failures.extend(capture_failures)

        print(f"{label}: status={result['status']}")
        for check in result["checks"]:
            if check["kind"] == "boolean_required":
                print(
                    f"  required:{check['field']} candidate={check['candidate_value']!r} status={check['status']}"
                )
            elif check["kind"] == "equal":
                print(
                    f"  equal:{check['field']} baseline={check['baseline_value']!r} candidate={check['candidate_value']!r} status={check['status']}"
                )
            elif check["kind"] == "minimum_ratio":
                print(
                    f"  minimum:{check['field']} baseline={check['baseline_value']!r} candidate={check['candidate_value']!r} minimum={check['minimum']!r} status={check['status']}"
                )
            elif check["kind"] == "upper_limit":
                print(
                    f"  upper:{check['field']} baseline={check['baseline_value']!r} candidate={check['candidate_value']!r} limit={check['limit']!r} status={check['status']}"
                )

    verdict = "ok" if not failures else "fail"
    payload = {
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "verdict": verdict,
        "top_level": checks,
        "captures": capture_results,
        "failures": failures,
    }

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    print(f"verdict={verdict}")
    return 0 if verdict == "ok" or args.warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main())
