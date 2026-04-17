#!/usr/bin/env python3
"""Compare combined M13 low-level benchmark artifacts against a baseline."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--max-latency-ratio", type=float, default=3.0)
    parser.add_argument("--latency-slack-ns", type=int, default=1000)
    parser.add_argument("--max-counter-ratio", type=float, default=1.0)
    parser.add_argument("--counter-slack", type=int, default=0)
    parser.add_argument("--allow-config-mismatch", action="store_true")
    parser.add_argument("--warn-only", action="store_true")
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def child_suite(artifact: dict, name: str) -> dict:
    suites = artifact.get("suites")
    if not isinstance(suites, dict) or not isinstance(suites.get(name), dict):
        raise SystemExit(f"missing suite {name!r} in combined artifact")
    return suites[name]


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def common_compare_args(args: argparse.Namespace) -> list[str]:
    argv = [
        "--max-latency-ratio",
        str(args.max_latency_ratio),
        "--latency-slack-ns",
        str(args.latency_slack_ns),
        "--max-counter-ratio",
        str(args.max_counter_ratio),
        "--counter-slack",
        str(args.counter_slack),
    ]
    if args.allow_config_mismatch:
        argv.append("--allow-config-mismatch")
    if args.warn_only:
        argv.append("--warn-only")
    return argv


def run_child_compare(script: Path, baseline: Path, candidate: Path, args: list[str]) -> int:
    result = subprocess.run(
        [sys.executable, str(script), str(baseline), str(candidate), *args],
        check=False,
    )
    return result.returncode


def main() -> int:
    args = parse_args()
    baseline = load_json(args.baseline)
    candidate = load_json(args.candidate)
    script_dir = Path(__file__).resolve().parent
    common_args = common_compare_args(args)

    with tempfile.TemporaryDirectory(prefix="gcdx-m13-lowlevel-") as tmpdir:
        tmpdir_path = Path(tmpdir)

        zig_baseline = tmpdir_path / "zig-baseline.json"
        zig_candidate = tmpdir_path / "zig-candidate.json"
        wake_baseline = tmpdir_path / "wake-baseline.json"
        wake_candidate = tmpdir_path / "wake-candidate.json"

        write_json(zig_baseline, child_suite(baseline, "zig_hotpath"))
        write_json(zig_candidate, child_suite(candidate, "zig_hotpath"))
        write_json(wake_baseline, child_suite(baseline, "workqueue_wake"))
        write_json(wake_candidate, child_suite(candidate, "workqueue_wake"))

        print(f"baseline={args.baseline}")
        print(f"candidate={args.candidate}")
        print("==> Comparing combined zig hot-path suite")
        zig_rc = run_child_compare(
            script_dir / "compare-zig-hotpath-baseline.py",
            zig_baseline,
            zig_candidate,
            common_args,
        )

        print("==> Comparing combined workqueue wake suite")
        wake_rc = run_child_compare(
            script_dir / "compare-workqueue-wake-baseline.py",
            wake_baseline,
            wake_candidate,
            common_args,
        )

    ok = zig_rc == 0 and wake_rc == 0
    verdict = "ok" if ok else "fail"

    payload = {
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "ok": ok,
        "verdict": verdict,
        "warn_only": args.warn_only,
        "suites": {
            "zig_hotpath": {"exit_status": zig_rc, "ok": zig_rc == 0},
            "workqueue_wake": {"exit_status": wake_rc, "ok": wake_rc == 0},
        },
    }

    if args.json_out is not None:
        write_json(args.json_out, payload)

    print(f"verdict={verdict}")

    if ok:
        return 0
    return 0 if args.warn_only else 1


if __name__ == "__main__":
    raise SystemExit(main())
