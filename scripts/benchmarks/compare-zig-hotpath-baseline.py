#!/usr/bin/env python3
"""Compare Zig TWQ hot-path benchmark artifacts against a baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


DEFAULT_LATENCY_METRICS = ("median_ns", "p95_ns", "p99_ns")
DEFAULT_COUNTER_METRICS = (
    "reqthreads_count",
    "thread_enter_count",
    "thread_return_count",
    "thread_transfer_count",
)
DEFAULT_CONFIG_FIELDS = (
    "samples",
    "request_count",
    "requested_features",
    "settle_ms",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument(
        "--mode",
        action="append",
        default=[],
        help="Mode key to compare. Defaults to the intersection.",
    )
    parser.add_argument(
        "--latency-metric",
        action="append",
        default=[],
        help="Latency metric to compare. Defaults to median_ns,p95_ns,p99_ns.",
    )
    parser.add_argument(
        "--counter-metric",
        action="append",
        default=[],
        help="Counter delta metric to compare. Defaults to reqthreads/thread enter/thread return/thread transfer.",
    )
    parser.add_argument(
        "--max-latency-ratio",
        type=float,
        default=3.0,
        help="Allowed candidate/baseline latency ratio before failure.",
    )
    parser.add_argument(
        "--latency-slack-ns",
        type=int,
        default=1000,
        help="Allowed absolute latency increase before ratio is enforced.",
    )
    parser.add_argument(
        "--max-counter-ratio",
        type=float,
        default=1.0,
        help="Allowed candidate/baseline counter ratio before failure.",
    )
    parser.add_argument(
        "--counter-slack",
        type=int,
        default=0,
        help="Allowed absolute counter increase before ratio is enforced.",
    )
    parser.add_argument(
        "--allow-config-mismatch",
        action="store_true",
        help="Do not fail when sample/request-count configuration differs.",
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="Print failures but exit 0.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_mode_key(value: str) -> str:
    return value.replace("-", "_")


def status_for(record: dict[str, Any]) -> str:
    status = record.get("status")
    if isinstance(status, str):
        return status
    sample_errors = record.get("sample_errors")
    if sample_errors == 0:
        return "ok"
    return "unknown"


def flatten_benchmark(benchmark: dict[str, Any], fallback_key: str | None = None) -> tuple[str, dict[str, Any]]:
    data = benchmark.get("data")
    if isinstance(data, dict):
        mode = data.get("mode")
        key = normalize_mode_key(mode) if isinstance(mode, str) else fallback_key
        if key is None:
            raise SystemExit(f"benchmark is missing data.mode: {benchmark!r}")
        flattened = dict(data)
        flattened["status"] = benchmark.get("status", status_for(flattened))
        flattened["meta"] = benchmark.get("meta", {})
        return key, flattened

    key = fallback_key
    if key is None:
        mode = benchmark.get("mode")
        if not isinstance(mode, str):
            raise SystemExit(f"benchmark is missing mode: {benchmark!r}")
        key = normalize_mode_key(mode)
    flattened = dict(benchmark)
    flattened["status"] = status_for(flattened)
    return key, flattened


def normalize_artifact(path: Path) -> dict[str, dict[str, Any]]:
    artifact = load_json(path)
    normalized: dict[str, dict[str, Any]] = {}

    modes = artifact.get("modes")
    if isinstance(modes, dict):
        for key, value in modes.items():
            if not isinstance(value, dict):
                continue
            mode_key, flattened = flatten_benchmark(value, normalize_mode_key(key))
            normalized[mode_key] = flattened

    benchmarks = artifact.get("benchmarks")
    if isinstance(benchmarks, dict):
        for key, value in benchmarks.items():
            if not isinstance(value, dict):
                continue
            mode_key, flattened = flatten_benchmark(value, normalize_mode_key(key))
            normalized[mode_key] = flattened

    benchmark = artifact.get("benchmark")
    if isinstance(benchmark, dict):
        mode_key, flattened = flatten_benchmark(benchmark)
        normalized[mode_key] = flattened

    if not normalized:
        raise SystemExit(f"no Zig hot-path benchmarks found in {path}")
    return normalized


def numeric(record: dict[str, Any], metric: str) -> int | None:
    value = record.get(metric)
    if isinstance(value, int):
        return value

    counters = record.get("counter_delta")
    if isinstance(counters, dict):
        counter_value = counters.get(metric)
        if isinstance(counter_value, int):
            return counter_value
        qualified = counters.get(f"kern.twq.{metric}")
        if isinstance(qualified, int):
            return qualified

    return None


def allowed_value(baseline: int, ratio: float, slack: int) -> int:
    return max(int(baseline * ratio), baseline + slack)


def compare_metric(
    mode: str,
    metric: str,
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    ratio: float,
    slack: int,
    failures: list[str],
) -> str:
    base_value = numeric(baseline, metric)
    cand_value = numeric(candidate, metric)
    if base_value is None or cand_value is None:
        return f"{metric}=-"

    limit = allowed_value(base_value, ratio, slack)
    status = "ok" if cand_value <= limit else "FAIL"
    if status == "FAIL":
        failures.append(
            f"{mode}: {metric} {cand_value} exceeds {limit} "
            f"(baseline {base_value})"
        )
    return f"{metric}={base_value}->{cand_value} limit={limit} {status}"


def compare_config(
    mode: str,
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    failures: list[str],
) -> str:
    pieces = []
    for field in DEFAULT_CONFIG_FIELDS:
        base_value = baseline.get(field)
        cand_value = candidate.get(field)
        if base_value is None or cand_value is None:
            continue
        if base_value != cand_value:
            failures.append(
                f"{mode}: {field} differs {base_value!r}->{cand_value!r}"
            )
            pieces.append(f"{field}={base_value}->{cand_value} FAIL")
        else:
            pieces.append(f"{field}={base_value}")
    return " ".join(pieces)


def main() -> int:
    args = parse_args()
    baseline = normalize_artifact(args.baseline)
    candidate = normalize_artifact(args.candidate)
    latency_metrics = args.latency_metric or list(DEFAULT_LATENCY_METRICS)
    counter_metrics = args.counter_metric or list(DEFAULT_COUNTER_METRICS)
    modes = args.mode or sorted(set(baseline) & set(candidate))

    failures: list[str] = []
    print(f"baseline={args.baseline}")
    print(f"candidate={args.candidate}")
    print(
        f"policy=max_latency_ratio={args.max_latency_ratio:.2f} "
        f"latency_slack_ns={args.latency_slack_ns} "
        f"max_counter_ratio={args.max_counter_ratio:.2f} "
        f"counter_slack={args.counter_slack}"
    )

    for mode in modes:
        b = baseline.get(mode)
        c = candidate.get(mode)
        if b is None:
            failures.append(f"{mode}: missing from baseline")
            print(f"{mode}: missing baseline")
            continue
        if c is None:
            failures.append(f"{mode}: missing from candidate")
            print(f"{mode}: missing candidate")
            continue

        b_status = status_for(b)
        c_status = status_for(c)
        pieces = [f"{mode}: status={b_status}->{c_status}"]
        if b_status == "ok" and c_status != "ok":
            failures.append(f"{mode}: status regressed {b_status!r}->{c_status!r}")
            pieces.append("status_gate=FAIL")
        else:
            pieces.append("status_gate=ok")

        b_errors = numeric(b, "sample_errors")
        c_errors = numeric(c, "sample_errors")
        if b_errors == 0 and c_errors not in (0, None):
            failures.append(f"{mode}: sample_errors regressed 0->{c_errors}")
            pieces.append(f"sample_errors=0->{c_errors} FAIL")
        elif c_errors is not None:
            pieces.append(f"sample_errors={b_errors}->{c_errors}")

        if not args.allow_config_mismatch:
            config_summary = compare_config(mode, b, c, failures)
            if config_summary:
                pieces.append(config_summary)

        for metric in latency_metrics:
            pieces.append(
                compare_metric(
                    mode,
                    metric,
                    b,
                    c,
                    args.max_latency_ratio,
                    args.latency_slack_ns,
                    failures,
                )
            )

        for metric in counter_metrics:
            pieces.append(
                compare_metric(
                    mode,
                    metric,
                    b,
                    c,
                    args.max_counter_ratio,
                    args.counter_slack,
                    failures,
                )
            )

        print(" ".join(pieces))

    if failures:
        print("failures:")
        for failure in failures:
            print(f"  {failure}")
        return 0 if args.warn_only else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
