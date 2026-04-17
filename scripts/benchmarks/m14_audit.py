#!/usr/bin/env python3
"""Audit raw M14 artifacts for unmapped fields before normalization."""

from __future__ import annotations

from collections import Counter
from functools import lru_cache
import importlib.util
import json
from pathlib import Path
from typing import Any


PRIMARY_MODE = "swift.dispatchmain-taskhandles-after-repeat"
CONTROL_MODE = "dispatch.main-executor-resume-repeat"
CLASSIFICATION_KEYS = (
    "default_receives_source_traffic",
    "default_overcommit_receives_mainq_traffic",
    "default_overcommit_continuation_dominant",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


@lru_cache(maxsize=1)
def extractor_module() -> Any:
    path = repo_root() / "scripts" / "benchmarks" / "extract-m14-benchmark.py"
    spec = importlib.util.spec_from_file_location("m14_extract_benchmark", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load extractor module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_metric_name(raw_name: str) -> str | None:
    return extractor_module().canonical_metric_name(raw_name)


def canonical_mode_name(value: Any) -> str | None:
    return extractor_module().canonical_mode_name(value)


def count_unknown_metric_keys(mapping: dict[str, Any]) -> Counter[str]:
    counter: Counter[str] = Counter()
    for raw_name, value in mapping.items():
        if raw_name in extractor_module().ROUND_METADATA_FIELDS:
            continue
        if canonical_metric_name(raw_name) is None:
            counter[raw_name] += 1
    return counter


def count_unknown_row_keys(rows: list[Any]) -> Counter[str]:
    counter: Counter[str] = Counter()
    for row in rows:
        if not isinstance(row, dict):
            continue
        for raw_name in row:
            if raw_name in extractor_module().ROUND_METADATA_FIELDS:
                continue
            if canonical_metric_name(raw_name) is None:
                counter[raw_name] += 1
    return counter


def workload_sources(benchmark: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    sources: list[tuple[str, dict[str, Any]]] = []
    for key in ("probe", "workload", "config"):
        value = benchmark.get(key)
        if isinstance(value, dict):
            sources.append((key, value))
    terminal = benchmark.get("terminal")
    if isinstance(terminal, dict):
        data = terminal.get("data")
        if isinstance(data, dict):
            sources.append(("terminal.data", data))
    return sources


def workload_audit(benchmark: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    known = set(extractor_module().WORKLOAD_FIELDS)
    for location, source in workload_sources(benchmark):
        unknown_keys = sorted(key for key in source if key not in known)
        if unknown_keys:
            findings.append(
                {
                    "location": location,
                    "unknown_keys": unknown_keys,
                }
            )
    return findings


def classification_audit(benchmark: dict[str, Any]) -> list[str]:
    source = benchmark.get("classification")
    if not isinstance(source, dict):
        return []
    return sorted(key for key in source if key not in CLASSIFICATION_KEYS)


def full_run_metric_audit(benchmark: dict[str, Any]) -> list[str]:
    counter: Counter[str] = Counter()
    for source in extractor_module().full_run_sources(benchmark):
        if isinstance(source, dict):
            counter.update(count_unknown_metric_keys(source))
    twq_delta = benchmark.get("twq_delta")
    if isinstance(twq_delta, dict):
        counter.update(count_unknown_metric_keys(twq_delta))
    counters = benchmark.get("libdispatch_counters")
    if isinstance(counters, list) and counters and isinstance(counters[-1], dict):
        counter.update(count_unknown_metric_keys(counters[-1]))
    return sorted(counter)


def steady_state_metric_audit(benchmark: dict[str, Any]) -> list[str]:
    steady = extractor_module().existing_steady_state_source(benchmark)
    if not isinstance(steady, dict):
        return []
    metrics = steady.get("metrics_per_round")
    if not isinstance(metrics, dict):
        return []
    return sorted(count_unknown_metric_keys(metrics))


def per_round_metric_audit(benchmark: dict[str, Any]) -> dict[str, int]:
    for rows in extractor_module().row_sources(benchmark):
        counter = count_unknown_row_keys(rows)
        if counter:
            return dict(sorted(counter.items()))
        if rows:
            return {}
    return {}


def round_metrics_audit(benchmark: dict[str, Any]) -> list[str]:
    round_metrics = benchmark.get("round_metrics")
    if not isinstance(round_metrics, dict):
        return []
    unknown: set[str] = set()
    for raw_name, value in round_metrics.items():
        if raw_name in {"round_ok_rounds", "round_ok_completed_rounds"}:
            continue
        if not raw_name.startswith("round_ok_"):
            continue
        metric_name = raw_name[len("round_ok_") :]
        if metric_name in extractor_module().ROUND_METADATA_FIELDS:
            continue
        if canonical_metric_name(metric_name) is None and isinstance(value, list):
            unknown.add(metric_name)
    return sorted(unknown)


def benchmark_audit(benchmark: dict[str, Any]) -> dict[str, Any]:
    workload = workload_audit(benchmark)
    classification = classification_audit(benchmark)
    full_run = full_run_metric_audit(benchmark)
    steady_state = steady_state_metric_audit(benchmark)
    per_round = per_round_metric_audit(benchmark)
    round_metrics = round_metrics_audit(benchmark)

    unique_keys = set(classification) | set(full_run) | set(steady_state) | set(round_metrics)
    occurrences = len(classification) + len(full_run) + len(steady_state) + len(round_metrics)
    for item in workload:
        unique_keys.update(item["unknown_keys"])
        occurrences += len(item["unknown_keys"])
    unique_keys.update(per_round)
    occurrences += sum(per_round.values())

    sections = [
        "workload",
        "classification",
        "full_run_metrics",
        "steady_state_metrics",
        "per_round_rows",
        "round_metrics",
    ]
    sections_with_unmapped = [
        section
        for section, has_values in (
            ("workload", bool(workload)),
            ("classification", bool(classification)),
            ("full_run_metrics", bool(full_run)),
            ("steady_state_metrics", bool(steady_state)),
            ("per_round_rows", bool(per_round)),
            ("round_metrics", bool(round_metrics)),
        )
        if has_values
    ]
    return {
        "workload": workload,
        "classification_unknown_keys": classification,
        "full_run_unknown_metric_keys": full_run,
        "steady_state_unknown_metric_keys": steady_state,
        "per_round_unknown_metric_keys": per_round,
        "round_metrics_unknown_metric_keys": round_metrics,
        "summary": {
            "has_unmapped_fields": bool(unique_keys),
            "unmapped_unique_keys": len(unique_keys),
            "unmapped_occurrences": occurrences,
            "sections_checked": sections,
            "sections_with_unmapped_fields": sections_with_unmapped,
        },
    }


def audit_macos_payload(payload: dict[str, Any]) -> dict[str, Any]:
    benchmarks: dict[str, Any] = {}
    source_benchmarks = payload.get("benchmarks")
    if isinstance(source_benchmarks, dict):
        for entry_key, benchmark in source_benchmarks.items():
            if not isinstance(benchmark, dict):
                continue
            mode = canonical_mode_name(entry_key) or canonical_mode_name(benchmark.get("mode"))
            if mode is None:
                continue
            benchmarks[mode] = benchmark_audit(benchmark)
    return benchmarks


def audit_freebsd_payload(payload: dict[str, Any]) -> dict[str, Any]:
    benchmarks: dict[str, Any] = {}
    index = extractor_module().benchmark_index_from_payload(payload)
    for mode in (PRIMARY_MODE, CONTROL_MODE):
        benchmark = index.get(mode)
        if isinstance(benchmark, dict):
            benchmarks[mode] = benchmark_audit(benchmark)
    return benchmarks


def summarize_audit(benchmarks: dict[str, Any]) -> dict[str, Any]:
    total_unique = 0
    total_occurrences = 0
    benchmarks_with_unmapped = 0
    sections: Counter[str] = Counter()
    for benchmark in benchmarks.values():
        if not isinstance(benchmark, dict):
            continue
        summary = benchmark.get("summary") or {}
        total_unique += int(summary.get("unmapped_unique_keys") or 0)
        total_occurrences += int(summary.get("unmapped_occurrences") or 0)
        if summary.get("has_unmapped_fields"):
            benchmarks_with_unmapped += 1
        for section in summary.get("sections_with_unmapped_fields") or []:
            sections[section] += 1
    return {
        "has_unmapped_fields": total_unique > 0,
        "benchmarks_with_unmapped_fields": benchmarks_with_unmapped,
        "total_unmapped_unique_keys": total_unique,
        "total_unmapped_occurrences": total_occurrences,
        "sections_with_unmapped_fields": dict(sorted(sections.items())),
    }


def audit_source(path: Path, *, kind: str, platform: str | None) -> dict[str, Any]:
    payload: dict[str, Any]
    note = None
    if kind == "missing":
        return {
            "path": str(path),
            "kind": kind,
            "platform": platform,
            "available": False,
            "note": "artifact path does not exist",
            "summary": {
                "has_unmapped_fields": False,
                "benchmarks_with_unmapped_fields": 0,
                "total_unmapped_unique_keys": 0,
                "total_unmapped_occurrences": 0,
                "sections_with_unmapped_fields": {},
            },
            "benchmarks": {},
        }
    if kind == "normalized":
        return {
            "path": str(path),
            "kind": kind,
            "platform": platform,
            "available": False,
            "note": "normalized artifacts do not preserve dropped raw fields for schema audit",
            "summary": {
                "has_unmapped_fields": False,
                "benchmarks_with_unmapped_fields": 0,
                "total_unmapped_unique_keys": 0,
                "total_unmapped_occurrences": 0,
                "sections_with_unmapped_fields": {},
            },
            "benchmarks": {},
        }
    if kind == "serial-log":
        payload = extractor_module().extract_freebsd_json_from_serial_log(path, f"audit-{path.stem}")
        note = "serial log audited via extracted FreeBSD benchmark JSON"
        benchmarks = audit_freebsd_payload(payload)
    elif platform == "macos" or kind == "report":
        payload = load_json(path)
        benchmarks = audit_macos_payload(payload)
    else:
        payload = load_json(path)
        benchmarks = audit_freebsd_payload(payload)

    return {
        "path": str(path),
        "kind": kind,
        "platform": platform,
        "available": True,
        "note": note,
        "summary": summarize_audit(benchmarks),
        "benchmarks": benchmarks,
    }


def render_audit_text(payload: dict[str, Any]) -> str:
    lines = [
        f"path={payload.get('path')}",
        f"kind={payload.get('kind')}",
        f"platform={payload.get('platform') or '-'}",
        f"available={payload.get('available')}",
    ]
    if payload.get("note"):
        lines.append(f"note={payload.get('note')}")
    summary = payload.get("summary") or {}
    lines.append(
        "summary:"
        f" has_unmapped_fields={summary.get('has_unmapped_fields')}"
        f" benchmarks_with_unmapped_fields={summary.get('benchmarks_with_unmapped_fields')}"
        f" total_unmapped_unique_keys={summary.get('total_unmapped_unique_keys')}"
        f" total_unmapped_occurrences={summary.get('total_unmapped_occurrences')}"
    )
    for mode in (PRIMARY_MODE, CONTROL_MODE):
        benchmark = (payload.get("benchmarks") or {}).get(mode) or {}
        benchmark_summary = benchmark.get("summary") or {}
        lines.append(
            f"{mode}:"
            f" has_unmapped_fields={benchmark_summary.get('has_unmapped_fields')}"
            f" unique={benchmark_summary.get('unmapped_unique_keys')}"
            f" occurrences={benchmark_summary.get('unmapped_occurrences')}"
            f" sections={','.join(benchmark_summary.get('sections_with_unmapped_fields') or []) or '-'}"
        )
    return "\n".join(lines) + "\n"
