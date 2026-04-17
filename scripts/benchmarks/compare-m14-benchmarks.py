#!/usr/bin/env python3
"""Compare normalized FreeBSD and macOS M14 artifacts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


PRIMARY_MODE = "swift.dispatchmain-taskhandles-after-repeat"
CONTROL_MODE = "dispatch.main-executor-resume-repeat"

PRIMARY_METRICS = (
    "dispatch_root_push_mainq_default_overcommit",
    "dispatch_root_poke_slow_default_overcommit",
    "worker_requested_threads",
)

CONTROL_METRICS = (
    "dispatch_root_push_mainq_default_overcommit",
    "dispatch_root_poke_slow_default_overcommit",
)

PRIMARY_DECISION_METRICS = (
    "dispatch_root_push_mainq_default_overcommit",
    "dispatch_root_poke_slow_default_overcommit",
)

WORKLOAD_KEYS = (
    "rounds",
    "tasks",
    "delay_ms",
)

PRIMARY_CLASSIFICATION_KEYS = (
    "default_receives_source_traffic",
    "default_overcommit_receives_mainq_traffic",
    "default_overcommit_continuation_dominant",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("freebsd", type=Path, help="Normalized FreeBSD M14 artifact")
    parser.add_argument("macos", type=Path, help="Normalized macOS M14 artifact")
    parser.add_argument(
        "--within-ratio",
        type=float,
        default=1.5,
        help="Strict comparison band used for reporting only",
    )
    parser.add_argument(
        "--about-within-ratio",
        type=float,
        default=1.65,
        help="Soft comparison band used for the stop-tuning decision",
    )
    parser.add_argument(
        "--material-gap-ratio",
        type=float,
        default=2.0,
        help="FreeBSD/macOS ratio treated as a real remaining coalescing gap",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        help="Optional JSON output path for the full comparison result",
    )
    parser.add_argument(
        "--expect-outcome",
        choices=(
            "stop_tuning_this_seam",
            "freebsd_likely_still_has_coalescing_gap",
            "inconclusive",
        ),
        help="Exit 1 when the computed outcome differs",
    )
    return parser.parse_args()


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def benchmark(report: dict[str, Any], mode: str) -> dict[str, Any] | None:
    value = report.get("benchmarks", {}).get(mode)
    return value if isinstance(value, dict) else None


def steady_metric(report: dict[str, Any], mode: str, metric: str) -> float | None:
    bench = benchmark(report, mode)
    if not isinstance(bench, dict):
        return None
    entry = bench.get("steady_state", {}).get("metrics_per_round", {}).get(metric)
    if isinstance(entry, dict):
        value = entry.get("mean")
        if isinstance(value, (int, float)):
            return float(value)
    return None


def classification(report: dict[str, Any], mode: str) -> dict[str, Any]:
    bench = benchmark(report, mode)
    if not isinstance(bench, dict):
        return {}
    value = bench.get("classification")
    return value if isinstance(value, dict) else {}


def workload(report: dict[str, Any], mode: str) -> dict[str, Any]:
    bench = benchmark(report, mode)
    if not isinstance(bench, dict):
        return {}
    value = bench.get("workload")
    return value if isinstance(value, dict) else {}


def benchmark_status(report: dict[str, Any], mode: str) -> str | None:
    bench = benchmark(report, mode)
    if not isinstance(bench, dict):
        return None
    value = bench.get("status")
    return value if isinstance(value, str) else None


def steady_start_round(report: dict[str, Any], mode: str) -> int | None:
    bench = benchmark(report, mode)
    if not isinstance(bench, dict):
        return None
    value = bench.get("steady_state", {}).get("start_round")
    return value if isinstance(value, int) else None


def metric_present(report: dict[str, Any], mode: str, metric: str) -> bool:
    return steady_metric(report, mode, metric) is not None


def workload_match(freebsd: dict[str, Any], macos: dict[str, Any], mode: str) -> dict[str, Any]:
    freebsd_workload = workload(freebsd, mode)
    macos_workload = workload(macos, mode)
    compared_keys = [
        key
        for key in WORKLOAD_KEYS
        if isinstance(freebsd_workload.get(key), int) and isinstance(macos_workload.get(key), int)
    ]
    missing_keys = [
        key
        for key in WORKLOAD_KEYS
        if not isinstance(freebsd_workload.get(key), int) or not isinstance(macos_workload.get(key), int)
    ]
    differing_keys = [
        key
        for key in compared_keys
        if int(freebsd_workload[key]) != int(macos_workload[key])
    ]
    return {
        "freebsd": freebsd_workload,
        "macos": macos_workload,
        "compared_keys": compared_keys,
        "missing_keys": missing_keys,
        "differing_keys": differing_keys,
        "matched": not missing_keys and not differing_keys,
    }


def classification_complete(value: dict[str, Any]) -> bool:
    return all(key in value and isinstance(value.get(key), bool) for key in PRIMARY_CLASSIFICATION_KEYS)


def validation(
    freebsd: dict[str, Any],
    macos: dict[str, Any],
    primary: dict[str, Any],
    control: dict[str, Any],
) -> dict[str, Any]:
    blockers: list[str] = []
    stop_blockers: list[str] = []
    warnings: list[str] = []

    primary_workload = workload_match(freebsd, macos, PRIMARY_MODE)
    control_workload = workload_match(freebsd, macos, CONTROL_MODE)
    primary_freebsd_class = classification(freebsd, PRIMARY_MODE)
    primary_macos_class = classification(macos, PRIMARY_MODE)
    primary_classification_complete = (
        classification_complete(primary_freebsd_class) and classification_complete(primary_macos_class)
    )
    freebsd_primary_status = benchmark_status(freebsd, PRIMARY_MODE)
    macos_primary_status = benchmark_status(macos, PRIMARY_MODE)
    freebsd_control_status = benchmark_status(freebsd, CONTROL_MODE)
    macos_control_status = benchmark_status(macos, CONTROL_MODE)
    freebsd_start = steady_start_round(freebsd, PRIMARY_MODE)
    macos_start = steady_start_round(macos, PRIMARY_MODE)

    metric_coverage = {
        "primary": {
            metric: {
                "freebsd_present": metric_present(freebsd, PRIMARY_MODE, metric),
                "macos_present": metric_present(macos, PRIMARY_MODE, metric),
            }
            for metric in PRIMARY_METRICS
        },
        "control": {
            metric: {
                "freebsd_present": metric_present(freebsd, CONTROL_MODE, metric),
                "macos_present": metric_present(macos, CONTROL_MODE, metric),
            }
            for metric in CONTROL_METRICS
        },
    }

    if benchmark(freebsd, PRIMARY_MODE) is None or benchmark(macos, PRIMARY_MODE) is None:
        blockers.append("primary benchmark is missing on one side")
    if freebsd_primary_status != "ok" or macos_primary_status != "ok":
        blockers.append(
            f"primary benchmark status is not ok (freebsd={freebsd_primary_status} macos={macos_primary_status})"
        )
    if not primary_workload["matched"]:
        if primary_workload["missing_keys"]:
            blockers.append(
                "primary workload tuple is incomplete "
                f"(missing {','.join(primary_workload['missing_keys'])})"
            )
        elif primary_workload["differing_keys"]:
            blockers.append(
                "primary workload tuple differs "
                f"({','.join(primary_workload['differing_keys'])})"
            )
    if freebsd_start is None or macos_start is None or freebsd_start != macos_start:
        blockers.append(
            f"primary steady-state start round differs (freebsd={freebsd_start} macos={macos_start})"
        )
    if not primary_classification_complete:
        blockers.append("primary classification is incomplete on one side")
    for metric in PRIMARY_DECISION_METRICS:
        coverage = metric_coverage["primary"][metric]
        if not coverage["freebsd_present"] or not coverage["macos_present"]:
            blockers.append(f"missing primary decision metric: {metric}")
    worker_coverage = metric_coverage["primary"]["worker_requested_threads"]
    if not worker_coverage["freebsd_present"] or not worker_coverage["macos_present"]:
        warnings.append("missing supporting primary metric: worker_requested_threads")

    if benchmark(freebsd, CONTROL_MODE) is None or benchmark(macos, CONTROL_MODE) is None:
        stop_blockers.append("control benchmark is missing on one side")
    if freebsd_control_status != "ok" or macos_control_status != "ok":
        stop_blockers.append(
            f"control benchmark status is not ok (freebsd={freebsd_control_status} macos={macos_control_status})"
        )
    if not control_workload["matched"]:
        if control_workload["missing_keys"]:
            stop_blockers.append(
                "control workload tuple is incomplete "
                f"(missing {','.join(control_workload['missing_keys'])})"
            )
        elif control_workload["differing_keys"]:
            stop_blockers.append(
                "control workload tuple differs "
                f"({','.join(control_workload['differing_keys'])})"
            )
    for metric in CONTROL_METRICS:
        coverage = metric_coverage["control"][metric]
        if not coverage["freebsd_present"] or not coverage["macos_present"]:
            stop_blockers.append(f"missing control metric: {metric}")

    return {
        "decision_ready": not blockers,
        "stop_ready": not blockers and not stop_blockers,
        "blockers": blockers,
        "stop_blockers": stop_blockers,
        "warnings": warnings,
        "primary_workload": primary_workload,
        "control_workload": control_workload,
        "steady_state_window": {
            "freebsd_start_round": freebsd_start,
            "macos_start_round": macos_start,
            "matched": freebsd_start is not None and freebsd_start == macos_start,
        },
        "primary_classification_complete": {
            "freebsd": classification_complete(primary_freebsd_class),
            "macos": classification_complete(primary_macos_class),
            "matched": primary_classification_complete,
        },
        "metric_coverage": metric_coverage,
    }


def ratio(freebsd_value: float | None, macos_value: float | None) -> float | None:
    if freebsd_value is None or macos_value is None:
        return None
    if macos_value == 0:
        return 1.0 if freebsd_value == 0 else None
    return freebsd_value / macos_value


def zeroish(value: float | None, epsilon: float = 1e-9) -> bool | None:
    if value is None:
        return None
    return abs(value) <= epsilon


def same_split(value: dict[str, Any]) -> bool:
    return (
        value.get("default_receives_source_traffic") is True
        and value.get("default_overcommit_receives_mainq_traffic") is True
        and value.get("default_overcommit_continuation_dominant") is False
    )


def describe_metric(
    freebsd: dict[str, Any],
    macos: dict[str, Any],
    mode: str,
    metric: str,
    within_ratio: float,
    about_within_ratio: float,
    material_gap_ratio: float,
) -> dict[str, Any]:
    freebsd_value = steady_metric(freebsd, mode, metric)
    macos_value = steady_metric(macos, mode, metric)
    metric_ratio = ratio(freebsd_value, macos_value)
    within = metric_ratio is not None and (1 / within_ratio) <= metric_ratio <= within_ratio
    within_about = metric_ratio is not None and (1 / about_within_ratio) <= metric_ratio <= about_within_ratio
    gap = metric_ratio is not None and metric_ratio >= material_gap_ratio
    return {
        "freebsd_per_round": freebsd_value,
        "macos_per_round": macos_value,
        "freebsd_over_macos_ratio": metric_ratio,
        "within_target_band": within,
        "within_about_target_band": within_about,
        "freebsd_materially_higher": gap,
    }


def outcome(
    freebsd: dict[str, Any],
    macos: dict[str, Any],
    within_ratio: float,
    about_within_ratio: float,
    material_gap_ratio: float,
) -> tuple[str, dict[str, Any]]:
    primary = {
        metric: describe_metric(
            freebsd,
            macos,
            PRIMARY_MODE,
            metric,
            within_ratio,
            about_within_ratio,
            material_gap_ratio,
        )
        for metric in PRIMARY_METRICS
    }
    control = {
        metric: describe_metric(
            freebsd,
            macos,
            CONTROL_MODE,
            metric,
            within_ratio,
            about_within_ratio,
            material_gap_ratio,
        )
        for metric in CONTROL_METRICS
    }

    freebsd_primary_class = classification(freebsd, PRIMARY_MODE)
    macos_primary_class = classification(macos, PRIMARY_MODE)
    same_qualitative_split = same_split(freebsd_primary_class) and same_split(macos_primary_class)
    checks = validation(freebsd, macos, primary, control)

    control_zero = all(
        zeroish(control[metric]["freebsd_per_round"]) is True
        and zeroish(control[metric]["macos_per_round"]) is True
        for metric in CONTROL_METRICS
    )

    push = primary["dispatch_root_push_mainq_default_overcommit"]
    poke = primary["dispatch_root_poke_slow_default_overcommit"]

    if checks["blockers"]:
        decision = "inconclusive"
        rationale = "The normalized artifacts are not a fair primary comparison: " + "; ".join(
            checks["blockers"]
        )
    elif (
        checks["stop_ready"]
        and
        same_qualitative_split
        and control_zero
        and push["within_about_target_band"]
        and poke["within_about_target_band"]
    ):
        decision = "stop_tuning_this_seam"
        rationale = (
            "FreeBSD and macOS show the same qualitative split, the C control stays at zero for the seam, "
            "and the primary mainq/poke rates stay within the configured about-1.5x comparison band"
        )
    elif same_qualitative_split and push["freebsd_materially_higher"] and poke["freebsd_materially_higher"]:
        decision = "freebsd_likely_still_has_coalescing_gap"
        rationale = (
            "FreeBSD remains materially higher than macOS on both mainq handoff pushes and "
            "default-overcommit poke_slow in steady state"
        )
    else:
        decision = "inconclusive"
        if checks["stop_blockers"]:
            rationale = "The normalized artifacts do not support a stop decision: " + "; ".join(
                checks["stop_blockers"]
            )
        else:
            rationale = (
                "The normalized artifacts do not cleanly satisfy either the stop-tuning band "
                "or the materially-higher gap rule"
            )

    details = {
        "window": {
            "freebsd_start_round": freebsd.get("metadata", {}).get("steady_state_start_round"),
            "macos_start_round": macos.get("metadata", {}).get("steady_state_start_round"),
        },
        "policy": {
            "strict_within_ratio": within_ratio,
            "about_within_ratio": about_within_ratio,
            "material_gap_ratio": material_gap_ratio,
        },
        "primary_classification": {
            "freebsd": freebsd_primary_class,
            "macos": macos_primary_class,
            "same_qualitative_split": same_qualitative_split,
        },
        "control_specificity": {
            "both_zeroish": control_zero,
            "metrics": control,
        },
        "primary_metrics": primary,
        "validation": checks,
        "rationale": rationale,
    }
    return decision, details


def print_section(title: str, rows: list[str]) -> None:
    print(title)
    for row in rows:
        print(f"  {row}")


def main() -> int:
    args = parse_args()
    freebsd = load(args.freebsd)
    macos = load(args.macos)

    decision, details = outcome(
        freebsd,
        macos,
        args.within_ratio,
        args.about_within_ratio,
        args.material_gap_ratio,
    )

    print(f"freebsd={args.freebsd}")
    print(f"macos={args.macos}")
    print(
        f"policy=within_ratio={args.within_ratio:.2f} "
        f"about_within_ratio={args.about_within_ratio:.2f} "
        f"material_gap_ratio={args.material_gap_ratio:.2f}"
    )
    print()

    primary_rows = []
    for metric, info in details["primary_metrics"].items():
        primary_rows.append(
            f"{metric}: freebsd={info['freebsd_per_round']} macos={info['macos_per_round']} "
            f"ratio={info['freebsd_over_macos_ratio']} within={info['within_target_band']} "
            f"within_about={info['within_about_target_band']} "
            f"gap={info['freebsd_materially_higher']}"
        )
    print_section("primary", primary_rows)

    control_rows = []
    for metric, info in details["control_specificity"]["metrics"].items():
        control_rows.append(
            f"{metric}: freebsd={info['freebsd_per_round']} macos={info['macos_per_round']} "
            f"ratio={info['freebsd_over_macos_ratio']}"
        )
    print_section("control", control_rows)

    print_section(
        "classification",
        [
            f"same_qualitative_split={details['primary_classification']['same_qualitative_split']}",
            f"freebsd={details['primary_classification']['freebsd']}",
            f"macos={details['primary_classification']['macos']}",
            f"control_zeroish={details['control_specificity']['both_zeroish']}",
        ],
    )

    validation_rows = [
        f"decision_ready={details['validation']['decision_ready']}",
        f"stop_ready={details['validation']['stop_ready']}",
        f"primary_workload_matched={details['validation']['primary_workload']['matched']}",
        f"control_workload_matched={details['validation']['control_workload']['matched']}",
        f"steady_state_window_matched={details['validation']['steady_state_window']['matched']}",
        f"primary_classification_complete={details['validation']['primary_classification_complete']['matched']}",
    ]
    validation_rows.extend(f"blocker={item}" for item in details["validation"]["blockers"])
    validation_rows.extend(f"stop_blocker={item}" for item in details["validation"]["stop_blockers"])
    validation_rows.extend(f"warning={item}" for item in details["validation"]["warnings"])
    print_section("validation", validation_rows)

    print()
    print(f"decision={decision}")
    print(f"rationale={details['rationale']}")

    if args.json_out:
        payload = {
            "schema_version": 1,
            "freebsd": str(args.freebsd.resolve()),
            "macos": str(args.macos.resolve()),
            "decision": decision,
            "details": details,
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if args.expect_outcome and decision != args.expect_outcome:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
