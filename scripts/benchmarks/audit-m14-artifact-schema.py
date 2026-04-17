#!/usr/bin/env python3
"""Audit raw M14 artifacts for schema drift and unmapped fields."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from m14_audit import audit_source, render_audit_text


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Artifact to audit")
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
    parser.add_argument("--json-out", type=Path, help="Optional JSON output path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    kind = args.kind
    if kind == "auto":
        from m14_validation import detect_source_kind

        kind = detect_source_kind(args.path)
    platform = None if args.platform == "auto" else args.platform
    payload = audit_source(args.path, kind=kind, platform=platform)

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(render_audit_text(payload), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
