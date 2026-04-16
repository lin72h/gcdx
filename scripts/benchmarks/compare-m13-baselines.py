#!/usr/bin/env python3
"""Compare two M13 benchmark JSON files with drift tolerance."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DEFAULT_METRICS = (
    "reqthreads_count",
    "thread_enter_count",
    "thread_return_count",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument(
        "--mode",
        action="append",
        default=[],
        help="Benchmark key to compare. Defaults to the intersection.",
    )
    parser.add_argument(
        "--metric",
        action="append",
        default=[],
        help="TWQ delta metric to compare. Defaults to req/enter/return.",
    )
    parser.add_argument(
        "--max-ratio",
        type=float,
        default=1.25,
        help="Allowed candidate/baseline ratio before failure.",
    )
    parser.add_argument(
        "--min-slack",
        type=int,
        default=20,
        help="Allowed absolute increase before ratio is enforced.",
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="Print failures but exit 0.",
    )
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def metric_value(delta: dict, metric: str):
    if metric in delta:
        return delta[metric]
    qualified = f"kern.twq.{metric}"
    if qualified in delta:
        return delta[qualified]
    return None


def allowed_value(baseline: int, max_ratio: float, min_slack: int) -> int:
    return max(int(baseline * max_ratio), baseline + min_slack)


def main() -> int:
    args = parse_args()
    baseline = load(args.baseline)
    candidate = load(args.candidate)
    baseline_benchmarks = baseline.get("benchmarks", {})
    candidate_benchmarks = candidate.get("benchmarks", {})
    metrics = args.metric or list(DEFAULT_METRICS)
    modes = args.mode or sorted(set(baseline_benchmarks) & set(candidate_benchmarks))

    failures: list[str] = []
    print(f"baseline={args.baseline}")
    print(f"candidate={args.candidate}")
    print(
        f"policy=max_ratio={args.max_ratio:.2f} min_slack={args.min_slack} "
        f"metrics={','.join(metrics)}"
    )

    for mode in modes:
        b = baseline_benchmarks.get(mode)
        c = candidate_benchmarks.get(mode)
        if b is None:
            failures.append(f"{mode}: missing from baseline")
            print(f"{mode}: missing baseline")
            continue
        if c is None:
            failures.append(f"{mode}: missing from candidate")
            print(f"{mode}: missing candidate")
            continue

        b_status = b.get("status")
        c_status = c.get("status")
        status = "ok"
        if b_status == "ok" and c_status != "ok":
            status = "FAIL"
            failures.append(f"{mode}: status regressed {b_status!r}->{c_status!r}")

        pieces = [f"{mode}: status={b_status}->{c_status} gate={status}"]
        b_delta = b.get("twq_delta", {})
        c_delta = c.get("twq_delta", {})
        for metric in metrics:
            b_value = metric_value(b_delta, metric)
            c_value = metric_value(c_delta, metric)
            if not isinstance(b_value, int) or not isinstance(c_value, int):
                pieces.append(f"{metric}=-")
                continue
            limit = allowed_value(b_value, args.max_ratio, args.min_slack)
            metric_status = "ok" if c_value <= limit else "FAIL"
            if metric_status == "FAIL":
                failures.append(
                    f"{mode}: {metric} {c_value} exceeds {limit} "
                    f"(baseline {b_value})"
                )
            pieces.append(f"{metric}={b_value}->{c_value} limit={limit} {metric_status}")
        print(" ".join(pieces))

    if failures:
        print("failures:")
        for failure in failures:
            print(f"  {failure}")
        return 0 if args.warn_only else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
