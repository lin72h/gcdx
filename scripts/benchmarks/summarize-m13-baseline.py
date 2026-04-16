#!/usr/bin/env python3
"""Print a compact M13 baseline summary.

The structured baseline JSON is the durable artifact. This helper exists for
quick triage after guest runs, especially when libdispatch root counters are
enabled.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


TWQ_KEYS = (
    "reqthreads_count",
    "thread_enter_count",
    "thread_return_count",
)

LIBDISPATCH_KEYS = (
    "root_push_empty_default",
    "root_push_append_default",
    "root_poke_slow_default",
    "root_repoke_default",
    "root_repoke_suppressed_after_source_default",
    "root_push_empty_default_overcommit",
    "root_push_mainq_default_overcommit",
    "root_poke_slow_default_overcommit",
    "root_repoke_default_overcommit",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline_json", type=Path)
    parser.add_argument(
        "--mode",
        action="append",
        default=[],
        help="Benchmark key to show, for example swift.dispatchmain-taskhandles-after-repeat",
    )
    return parser.parse_args()


def fmt_value(value) -> str:
    if value is None:
        return "-"
    if isinstance(value, list):
        return ",".join(str(item) for item in value)
    return str(value)


def metric_value(delta: dict, metric: str):
    if metric in delta:
        return delta[metric]
    qualified = f"kern.twq.{metric}"
    if qualified in delta:
        return delta[qualified]
    return None


def summarize_rounds(round_metrics: dict | None) -> str:
    if not round_metrics:
        return ""
    deltas = round_metrics.get("round_ok_reqthreads_delta")
    if not deltas:
        return ""
    return (
        f" rounds={len(deltas)}"
        f" req/round_avg={sum(deltas) / len(deltas):.2f}"
        f" req/round_min={min(deltas)}"
        f" req/round_max={max(deltas)}"
    )


def main() -> int:
    args = parse_args()
    data = json.loads(args.baseline_json.read_text(encoding="utf-8"))
    benchmarks = data.get("benchmarks", {})
    selected = args.mode or sorted(benchmarks)

    print(f"baseline={args.baseline_json}")
    print(f"label={data.get('metadata', {}).get('label', '-')}")
    print(f"schema_version={data.get('schema_version', '-')}")

    for key in selected:
        benchmark = benchmarks.get(key)
        if benchmark is None:
            print(f"{key}: missing")
            continue

        delta = benchmark.get("twq_delta", {})
        twq = " ".join(
            f"{twq_key}={fmt_value(metric_value(delta, twq_key))}"
            for twq_key in TWQ_KEYS
        )
        print(
            f"{key}: status={benchmark.get('status')} {twq}"
            f"{summarize_rounds(benchmark.get('round_metrics'))}"
        )

        for counters in benchmark.get("libdispatch_counters", []):
            picked = [
                f"{counter_key}={fmt_value(counters.get(counter_key))}"
                for counter_key in LIBDISPATCH_KEYS
                if counter_key in counters
            ]
            if picked:
                print(f"{key}: libdispatch " + " ".join(picked))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
