#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract the last workqueue wake benchmark JSON object from a guest serial log."
    )
    parser.add_argument("--serial-log", required=True, help="Serial log produced by run-workqueue-wake-bench.sh")
    parser.add_argument("--out", required=True, help="Output JSON path")
    parser.add_argument("--label", required=True, help="Benchmark label")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Extract all workqueue-bench JSON objects into a suite artifact.",
    )
    return parser.parse_args()


def mode_key(benchmark: dict) -> str:
    data = benchmark.get("data", {})
    mode = data.get("mode")
    if not isinstance(mode, str) or not mode:
        raise SystemExit(f"workqueue-bench object is missing data.mode: {benchmark!r}")
    return mode.replace("-", "_")


def main() -> int:
    args = parse_args()
    serial_log = Path(args.serial_log)
    out_path = Path(args.out)

    benchmarks = []
    for raw_line in serial_log.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if '"kind":"workqueue-bench"' not in line:
            continue
        benchmarks.append(json.loads(line))

    if not benchmarks:
        raise SystemExit(f"no workqueue-bench JSON object found in {serial_log}")

    if args.all:
        suite = {}
        for benchmark in benchmarks:
            key = mode_key(benchmark)
            if key in suite:
                raise SystemExit(f"duplicate workqueue-bench mode in serial log: {key}")
            suite[key] = benchmark
        payload = {
            "schema_version": 1,
            "label": args.label,
            "serial_log": str(serial_log),
            "benchmarks": suite,
        }
    else:
        payload = {
            "schema_version": 1,
            "label": args.label,
            "serial_log": str(serial_log),
            "benchmark": benchmarks[-1],
        }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
