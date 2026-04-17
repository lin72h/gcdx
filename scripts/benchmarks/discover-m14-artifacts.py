#!/usr/bin/env python3
"""Discover likely M14 FreeBSD/macOS artifacts under one or more roots."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from m14_validation import detect_source_kind, pair_validation_summary, validate_source


FREEBSD_PATTERNS = (
    "*m14-round-snapshots*.json",
    "*round-snapshots*.json",
    "*m14*steady*.json",
    "*m14*compare*.json",
    "*m14*.json",
)

MACOS_PATTERNS = (
    "*/m14-report.json",
    "*m14-report.json",
    "*m14*report*.json",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        action="append",
        default=[],
        help="Root directory to scan. Defaults to ../artifacts and fixtures/benchmarks",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        help="Optional JSON output path",
    )
    return parser.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_roots() -> list[Path]:
    root = repo_root()
    return [
        root / "../artifacts",
        root / "fixtures" / "benchmarks",
    ]


def resolve_roots(values: list[str]) -> list[Path]:
    if values:
        roots = [Path(value).expanduser().resolve() for value in values]
    else:
        roots = [path.resolve() for path in default_roots()]
    return [root for root in roots if root.exists()]


def validation_summary(path: Path, kind: str, role: str) -> dict[str, Any]:
    payload = validate_source(
        path,
        kind=kind,
        expected_platform=role,
    )
    normalized_validation = payload.get("normalized_validation") or {}
    schema_audit = payload.get("schema_audit") or {}
    schema_audit_summary = schema_audit.get("summary") or {}
    source_benchmarks = normalized_validation.get("benchmarks") or {}
    benchmarks: dict[str, Any] = {}
    for mode, benchmark in source_benchmarks.items():
        if not isinstance(benchmark, dict):
            continue
        benchmarks[mode] = {
            "workload": benchmark.get("workload") or {},
            "steady_state": benchmark.get("steady_state") or {},
        }
    return {
        "comparison_ready": payload["comparison_ready"],
        "stop_ready": payload["stop_ready"],
        "blockers": payload["blockers"],
        "stop_blockers": payload["stop_blockers"],
        "warnings": payload["warnings"],
        "normalized_platform": normalized_validation.get("platform"),
        "schema_audit_summary": {
            "has_unmapped_fields": schema_audit_summary.get("has_unmapped_fields", False),
            "total_unmapped_unique_keys": schema_audit_summary.get("total_unmapped_unique_keys", 0),
            "total_unmapped_occurrences": schema_audit_summary.get("total_unmapped_occurrences", 0),
        },
        "benchmarks": benchmarks,
    }


def candidate_record(path: Path, kind: str, role: str) -> dict[str, Any]:
    stat = path.stat()
    return {
        "path": str(path),
        "kind": kind,
        "role": role,
        "mtime_ns": stat.st_mtime_ns,
        "size": stat.st_size,
        "validation": validation_summary(path, kind, role),
    }


def pair_record(freebsd: dict[str, Any], macos: dict[str, Any]) -> dict[str, Any]:
    freebsd_audit = (freebsd.get("validation") or {}).get("schema_audit_summary") or {}
    macos_audit = (macos.get("validation") or {}).get("schema_audit_summary") or {}
    validation = pair_validation_summary(
        freebsd.get("validation") or {},
        macos.get("validation") or {},
    )
    validation["schema_audit_summary"] = {
        "has_unmapped_fields": bool(
            freebsd_audit.get("has_unmapped_fields") or macos_audit.get("has_unmapped_fields")
        ),
        "total_unmapped_unique_keys": int(freebsd_audit.get("total_unmapped_unique_keys") or 0)
        + int(macos_audit.get("total_unmapped_unique_keys") or 0),
        "total_unmapped_occurrences": int(freebsd_audit.get("total_unmapped_occurrences") or 0)
        + int(macos_audit.get("total_unmapped_occurrences") or 0),
    }
    return {
        "freebsd": {
            "path": freebsd["path"],
            "kind": freebsd["kind"],
        },
        "macos": {
            "path": macos["path"],
            "kind": macos["kind"],
        },
        "validation": validation,
    }


def collect_freebsd(root: Path) -> list[dict[str, Any]]:
    seen: set[Path] = set()
    candidates: list[dict[str, Any]] = []
    for pattern in FREEBSD_PATTERNS:
        for path in root.glob(f"**/{pattern}"):
            if not path.is_file() or path in seen:
                continue
            seen.add(path)
            if "macos" in path.parts or "macos" in path.name:
                continue
            kind = detect_source_kind(path)
            if kind == "comparison":
                continue
            candidate = candidate_record(path, kind, "freebsd")
            normalized_platform = candidate.get("validation", {}).get("normalized_platform")
            if normalized_platform is not None and normalized_platform != "freebsd":
                continue
            candidates.append(candidate)
    return candidates


def collect_macos(root: Path) -> list[dict[str, Any]]:
    seen: set[Path] = set()
    candidates: list[dict[str, Any]] = []
    for pattern in MACOS_PATTERNS:
        for path in root.glob(f"**/{pattern}"):
            if not path.is_file() or path in seen:
                continue
            seen.add(path)
            kind = detect_source_kind(path)
            if kind == "comparison":
                continue
            candidate = candidate_record(path, kind, "macos")
            normalized_platform = candidate.get("validation", {}).get("normalized_platform")
            if normalized_platform is not None and normalized_platform != "macos":
                continue
            candidates.append(candidate)
    return candidates


def preference_key(candidate: dict[str, Any]) -> tuple[int, int, int, int, int, str]:
    kind_order = {
        "round-snapshots": 0,
        "benchmark-json": 1,
        "normalized": 2,
        "report": 0,
    }
    path = candidate["path"]
    path_bonus = 0
    if "introspection-final" in path or "round-snapshots" in path:
        path_bonus = -1
    validation = candidate.get("validation") or {}
    comparison_penalty = 0 if validation.get("comparison_ready") else 1
    stop_penalty = 0 if validation.get("stop_ready") else 1
    audit_penalty = int(
        (validation.get("schema_audit_summary") or {}).get("total_unmapped_unique_keys") or 0
    )
    return (
        comparison_penalty,
        stop_penalty,
        audit_penalty,
        kind_order.get(candidate["kind"], 9),
        path_bonus,
        -int(candidate["mtime_ns"]),
        path,
    )


def pick_best(candidates: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not candidates:
        return None
    return sorted(candidates, key=preference_key)[0]


def pair_preference_key(pair: dict[str, Any], freebsd_index: dict[str, dict[str, Any]], macos_index: dict[str, dict[str, Any]]) -> tuple[Any, ...]:
    validation = pair.get("validation") or {}
    freebsd_path = (pair.get("freebsd") or {}).get("path")
    macos_path = (pair.get("macos") or {}).get("path")
    freebsd = freebsd_index.get(freebsd_path or "")
    macos = macos_index.get(macos_path or "")

    readiness_penalty = 2
    if validation.get("stop_ready"):
        readiness_penalty = 0
    elif validation.get("comparison_ready"):
        readiness_penalty = 1
    audit_penalty = int(
        (validation.get("schema_audit_summary") or {}).get("total_unmapped_unique_keys") or 0
    )

    return (
        readiness_penalty,
        audit_penalty,
        preference_key(freebsd) if freebsd is not None else (9, 9, 9, 9, 9, ""),
        preference_key(macos) if macos is not None else (9, 9, 9, 9, 9, ""),
        freebsd_path or "",
        macos_path or "",
    )


def pair_candidates(
    freebsd_candidates: list[dict[str, Any]],
    macos_candidates: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    return [
        pair_record(freebsd, macos)
        for freebsd in freebsd_candidates
        for macos in macos_candidates
    ]


def pick_best_pair(
    freebsd_candidates: list[dict[str, Any]],
    macos_candidates: list[dict[str, Any]],
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    pairs = pair_candidates(freebsd_candidates, macos_candidates)
    if not pairs:
        return None, []

    freebsd_index = {candidate["path"]: candidate for candidate in freebsd_candidates}
    macos_index = {candidate["path"]: candidate for candidate in macos_candidates}
    ordered = sorted(
        pairs,
        key=lambda pair: pair_preference_key(pair, freebsd_index, macos_index),
    )
    return ordered[0], ordered


def main() -> int:
    args = parse_args()
    roots = resolve_roots(args.root)
    freebsd_candidates: list[dict[str, Any]] = []
    macos_candidates: list[dict[str, Any]] = []
    for root in roots:
        freebsd_candidates.extend(collect_freebsd(root))
        macos_candidates.extend(collect_macos(root))

    freebsd_sorted = sorted(freebsd_candidates, key=preference_key)
    macos_sorted = sorted(macos_candidates, key=preference_key)
    best_pair, pair_list = pick_best_pair(freebsd_sorted, macos_sorted)

    payload = {
        "schema_version": 1,
        "roots": [str(root) for root in roots],
        "freebsd": {
            "best": pick_best(freebsd_sorted),
            "candidates": freebsd_sorted,
        },
        "macos": {
            "best": pick_best(macos_sorted),
            "candidates": macos_sorted,
        },
        "pairs": {
            "best": best_pair,
            "candidates": pair_list,
        },
    }

    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
