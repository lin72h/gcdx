#!/usr/bin/env python3
"""Validate raw or normalized M14 artifacts before comparison."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from m14_validation import render_validation_text, validate_source


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Artifact to validate")
    parser.add_argument(
        "--kind",
        default="auto",
        choices=(
            "auto",
            "report",
            "benchmark-json",
            "round-snapshots",
            "serial-log",
            "normalized",
        ),
        help="Artifact kind. Defaults to auto-detection.",
    )
    parser.add_argument(
        "--platform",
        default="auto",
        choices=("auto", "freebsd", "macos"),
        help="Expected platform. Defaults to auto.",
    )
    parser.add_argument(
        "--steady-state-start-round",
        type=int,
        default=8,
        help="Steady-state start round used when a raw artifact must be normalized",
    )
    parser.add_argument("--json-out", type=Path, help="Optional JSON output path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    expected_platform = None if args.platform == "auto" else args.platform
    payload = validate_source(
        args.path,
        kind=args.kind,
        expected_platform=expected_platform,
        start_round=args.steady_state_start_round,
    )

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(render_validation_text(payload), end="")
    return 0 if payload["comparison_ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
