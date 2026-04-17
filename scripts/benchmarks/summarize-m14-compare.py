#!/usr/bin/env python3
"""Render a concise decision-grade summary for an M14 comparison artifact."""

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("comparison_json", type=Path)
    return parser.parse_args()


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def fmt(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def workload_line(label: str, benchmark: dict[str, Any]) -> str:
    workload = benchmark.get("workload", {})
    return (
        f"{label}: status={benchmark.get('status')} "
        f"rounds={workload.get('rounds', '-')} "
        f"tasks={workload.get('tasks', '-')} "
        f"delay_ms={workload.get('delay_ms', '-')}"
    )


def print_list(label: str, values: list[str]) -> None:
    print(f"{label}:")
    if values:
        for value in values:
            print(f"  {value}")
    else:
        print("  none")


def main() -> int:
    args = parse_args()
    comparison = load(args.comparison_json)
    freebsd = load(Path(comparison["freebsd"]))
    macos = load(Path(comparison["macos"]))
    details = comparison.get("details", {})

    freebsd_primary = freebsd.get("benchmarks", {}).get(PRIMARY_MODE, {})
    freebsd_control = freebsd.get("benchmarks", {}).get(CONTROL_MODE, {})
    macos_primary = macos.get("benchmarks", {}).get(PRIMARY_MODE, {})
    macos_control = macos.get("benchmarks", {}).get(CONTROL_MODE, {})

    print(f"comparison_json={args.comparison_json}")
    print(f"decision={comparison.get('decision')}")
    print(f"rationale={details.get('rationale')}")
    print(
        "policy:"
        f" strict={fmt(details.get('policy', {}).get('strict_within_ratio'))}"
        f" about={fmt(details.get('policy', {}).get('about_within_ratio'))}"
        f" gap={fmt(details.get('policy', {}).get('material_gap_ratio'))}"
    )
    print(
        "window:"
        f" freebsd_start_round={fmt(details.get('window', {}).get('freebsd_start_round'))}"
        f" macos_start_round={fmt(details.get('window', {}).get('macos_start_round'))}"
    )

    print("workloads:")
    print(f"  {workload_line('freebsd primary', freebsd_primary)}")
    print(f"  {workload_line('macos primary', macos_primary)}")
    print(f"  {workload_line('freebsd control', freebsd_control)}")
    print(f"  {workload_line('macos control', macos_control)}")

    print("classification:")
    print(f"  same_qualitative_split={details.get('primary_classification', {}).get('same_qualitative_split')}")
    print(f"  control_zeroish={details.get('control_specificity', {}).get('both_zeroish')}")
    print(f"  freebsd={details.get('primary_classification', {}).get('freebsd')}")
    print(f"  macos={details.get('primary_classification', {}).get('macos')}")

    validation = details.get("validation", {})
    print("validation:")
    print(f"  decision_ready={validation.get('decision_ready')}")
    print(f"  stop_ready={validation.get('stop_ready')}")
    print(
        "  primary_workload_matched="
        f"{validation.get('primary_workload', {}).get('matched')}"
    )
    print(
        "  control_workload_matched="
        f"{validation.get('control_workload', {}).get('matched')}"
    )
    print(
        "  steady_state_window_matched="
        f"{validation.get('steady_state_window', {}).get('matched')}"
    )
    print(
        "  primary_classification_complete="
        f"{validation.get('primary_classification_complete', {}).get('matched')}"
    )

    print("primary:")
    for metric in PRIMARY_METRICS:
        info = details.get("primary_metrics", {}).get(metric, {})
        print(
            "  "
            f"{metric}: "
            f"freebsd={fmt(info.get('freebsd_per_round'))} "
            f"macos={fmt(info.get('macos_per_round'))} "
            f"ratio={fmt(info.get('freebsd_over_macos_ratio'))} "
            f"within={info.get('within_target_band')} "
            f"within_about={info.get('within_about_target_band')} "
            f"gap={info.get('freebsd_materially_higher')}"
        )

    print("control:")
    for metric in CONTROL_METRICS:
        info = details.get("control_specificity", {}).get("metrics", {}).get(metric, {})
        print(
            "  "
            f"{metric}: "
            f"freebsd={fmt(info.get('freebsd_per_round'))} "
            f"macos={fmt(info.get('macos_per_round'))} "
            f"ratio={fmt(info.get('freebsd_over_macos_ratio'))}"
        )

    print_list("blockers", validation.get("blockers", []))
    print_list("stop_blockers", validation.get("stop_blockers", []))
    print_list("warnings", validation.get("warnings", []))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
