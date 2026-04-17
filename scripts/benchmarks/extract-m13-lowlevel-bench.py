#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract the combined M13 low-level benchmark suites from a guest serial log."
    )
    parser.add_argument("--serial-log", required=True, help="Serial log produced by run-m13-lowlevel-suite.sh")
    parser.add_argument("--out", required=True, help="Output JSON path")
    parser.add_argument("--label", required=True, help="Benchmark label")
    return parser.parse_args()


def mode_key(benchmark: dict) -> str:
    data = benchmark.get("data", {})
    mode = data.get("mode")
    if not isinstance(mode, str) or not mode:
        raise SystemExit(f"benchmark object is missing data.mode: {benchmark!r}")
    return mode.replace("-", "_")


def collect_benchmarks(serial_log: Path, kind: str) -> list[dict]:
    benchmarks = []
    for raw_line in serial_log.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if f'"kind":"{kind}"' not in line:
            continue
        benchmarks.append(json.loads(line))
    return benchmarks


def suite_payload(label: str, serial_log: Path, benchmarks: list[dict]) -> dict:
    suite = {}
    for benchmark in benchmarks:
        key = mode_key(benchmark)
        if key in suite:
            raise SystemExit(f"duplicate benchmark mode in serial log: {key}")
        suite[key] = benchmark
    return {
        "schema_version": 1,
        "label": label,
        "serial_log": str(serial_log),
        "benchmarks": suite,
    }


def kernel_metadata(benchmark: dict) -> dict[str, str] | None:
    meta = benchmark.get("meta", {})
    if not isinstance(meta, dict):
        return None

    ident = meta.get("kernel_ident")
    osrelease = meta.get("kernel_osrelease")
    bootfile = meta.get("kernel_bootfile")
    if not all(isinstance(value, str) and value for value in (ident, osrelease, bootfile)):
        return None

    return {
        "ident": ident,
        "osrelease": osrelease,
        "bootfile": bootfile,
    }


def first_kernel_metadata(*benchmark_groups: list[dict]) -> dict[str, str] | None:
    for group in benchmark_groups:
        for benchmark in group:
            metadata = kernel_metadata(benchmark)
            if metadata is not None:
                return metadata
    return None


def main() -> int:
    args = parse_args()
    serial_log = Path(args.serial_log)
    out_path = Path(args.out)

    zig_benchmarks = collect_benchmarks(serial_log, "zig-bench")
    wake_benchmarks = collect_benchmarks(serial_log, "workqueue-bench")

    if not zig_benchmarks:
        raise SystemExit(f"no zig-bench JSON object found in {serial_log}")
    if not wake_benchmarks:
        raise SystemExit(f"no workqueue-bench JSON object found in {serial_log}")

    payload = {
        "schema_version": 1,
        "label": args.label,
        "serial_log": str(serial_log),
        "suites": {
            "zig_hotpath": suite_payload(f"{args.label}-zig-hotpath", serial_log, zig_benchmarks),
            "workqueue_wake": suite_payload(
                f"{args.label}-workqueue-wake", serial_log, wake_benchmarks
            ),
        },
    }

    metadata = first_kernel_metadata(zig_benchmarks, wake_benchmarks)
    if metadata is not None:
        payload["kernel"] = metadata

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
