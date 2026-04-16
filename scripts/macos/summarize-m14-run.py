#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


SYMBOL_ORDER = (
    "_dispatch_root_queue_push",
    "_dispatch_root_queue_poke_slow",
    "_pthread_workqueue_addthreads",
    "_dispatch_queue_cleanup2",
    "_dispatch_lane_barrier_complete",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Print a compact macOS M14 run summary.")
    parser.add_argument("run_json", type=Path)
    return parser.parse_args()


def fmt_float(value) -> str:
    if value is None:
        return "-"
    return f"{value:.2f}"


def print_symbol_summary(data: dict) -> None:
    symbols = data.get("stock_symbols", {}).get("symbols", {})
    if not symbols:
        print("stock_symbols: missing")
        return

    print("stock_symbols:")
    for name in SYMBOL_ORDER:
        record = symbols.get(name, {})
        print(
            f"  {name}: "
            f"sdk_source={record.get('sdk_exports_source_symbol')} "
            f"sdk_macho={record.get('sdk_exports_macho_symbol')} "
            f"runtime={record.get('runtime_dlsym_resolvable')} "
            f"class={record.get('stock_live_traceability')}"
        )

    dtrace = data.get("stock_symbols", {}).get("tools", {}).get("dtrace", {})
    print(
        "dtrace:"
        f" accessible={dtrace.get('accessible')}"
        f" rc={dtrace.get('rc')}"
    )


def print_benchmark_summary(name: str, benchmark: dict) -> None:
    terminal = benchmark.get("terminal", {}) or {}
    data = terminal.get("data", {}) or {}
    steady_state = benchmark.get("steady_state", {}) or {}
    elapsed = steady_state.get("elapsed_ns", {})

    print(
        f"{name}: status={benchmark.get('status')}"
        f" rounds={data.get('rounds', data.get('completed_rounds', '-'))}"
        f" tasks={data.get('tasks', '-')}"
        f" delay_ms={data.get('delay_ms', '-')}"
        f" completed_rounds={data.get('completed_rounds', '-')}"
        f" steady_elapsed_ns_mean={fmt_float(elapsed.get('mean'))}"
        f" steady_elapsed_ns_min={fmt_float(elapsed.get('min'))}"
        f" steady_elapsed_ns_max={fmt_float(elapsed.get('max'))}"
    )


def main() -> int:
    args = parse_args()
    data = json.loads(args.run_json.read_text(encoding="utf-8"))

    print(f"run_json={args.run_json}")
    print(f"label={data.get('metadata', {}).get('label')}")
    print(f"steady_state_start_round={data.get('metadata', {}).get('steady_state_start_round')}")
    metadata = data.get("stock_symbols", {}).get("metadata", {})
    if metadata:
        print(f"machine={metadata.get('machine')}")
        print(f"sw_vers={metadata.get('sw_vers', '').splitlines()[0] if metadata.get('sw_vers') else '-'}")
        print(
            "xcode_swift="
            f"{metadata.get('xcode_swift_version', '').splitlines()[0] if metadata.get('xcode_swift_version') else '-'}"
        )
    print_symbol_summary(data)

    benchmarks = data.get("benchmarks", {})
    for name in sorted(benchmarks):
        print_benchmark_summary(name, benchmarks[name])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
