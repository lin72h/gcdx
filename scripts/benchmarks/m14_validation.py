#!/usr/bin/env python3
"""Shared validation helpers for repo-native M14 artifacts."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from m14_audit import audit_source


PRIMARY_MODE = "swift.dispatchmain-taskhandles-after-repeat"
CONTROL_MODE = "dispatch.main-executor-resume-repeat"

PRIMARY_DECISION_METRICS = (
    "dispatch_root_push_mainq_default_overcommit",
    "dispatch_root_poke_slow_default_overcommit",
)
PRIMARY_SUPPORTING_METRICS = ("worker_requested_threads",)
CONTROL_METRICS = PRIMARY_DECISION_METRICS

WORKLOAD_KEYS = ("rounds", "tasks", "delay_ms")
CLASSIFICATION_KEYS = (
    "default_receives_source_traffic",
    "default_overcommit_receives_mainq_traffic",
    "default_overcommit_continuation_dominant",
)

NORMALIZED_MARKERS = ('"platform"', '"source_kind"')
COMPARISON_MARKERS = ('"decision"', '"details"', '"freebsd"', '"macos"')


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def read_text(path: Path, limit: int = 32768) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:limit]
    except OSError:
        return ""


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def detect_source_kind(path: Path) -> str:
    if not path.exists() or not path.is_file():
        return "missing"
    if path.suffix == ".log":
        return "serial-log"

    text = read_text(path)
    if not text:
        return "unknown"
    if all(marker in text for marker in COMPARISON_MARKERS):
        return "comparison"
    if all(marker in text for marker in NORMALIZED_MARKERS):
        return "normalized"
    if "round-snapshots" in path.name or '"round_snapshots"' in text or '"roundSnapshots"' in text:
        return "round-snapshots"
    if any(marker in text for marker in ('"measurement_setup"', '"symbol_probe_reality"')):
        return "report"
    return "benchmark-json"


def detect_platform_from_payload(payload: dict[str, Any], path: Path | None = None) -> str | None:
    platform = payload.get("platform")
    if isinstance(platform, str):
        return platform

    metadata = payload.get("metadata")
    if isinstance(metadata, dict):
        source_kind = metadata.get("source_kind")
        if isinstance(source_kind, str):
            if source_kind.startswith("macos"):
                return "macos"
            if source_kind.startswith("freebsd"):
                return "freebsd"

    if "measurement_setup" in payload or "symbol_probe_reality" in payload:
        return "macos"

    benchmarks = payload.get("benchmarks")
    if isinstance(benchmarks, dict):
        for benchmark in benchmarks.values():
            if not isinstance(benchmark, dict):
                continue
            bench_platform = benchmark.get("platform")
            if isinstance(bench_platform, str):
                return bench_platform
            if benchmark.get("dispatch_introspection_available") is True:
                return "macos"

    if path is not None:
        path_string = str(path).lower()
        if "macos" in path_string:
            return "macos"
        if "freebsd" in path_string:
            return "freebsd"

    return None


def benchmark(report: dict[str, Any], mode: str) -> dict[str, Any] | None:
    value = report.get("benchmarks", {}).get(mode)
    return value if isinstance(value, dict) else None


def workload_summary(benchmark_payload: dict[str, Any] | None) -> dict[str, Any]:
    workload = {}
    if isinstance(benchmark_payload, dict):
        value = benchmark_payload.get("workload")
        if isinstance(value, dict):
            workload = value

    missing = [key for key in WORKLOAD_KEYS if not isinstance(workload.get(key), int)]
    return {
        "value": workload,
        "missing_keys": missing,
        "complete": not missing,
    }


def classification_summary(benchmark_payload: dict[str, Any] | None) -> dict[str, Any]:
    classification = {}
    if isinstance(benchmark_payload, dict):
        value = benchmark_payload.get("classification")
        if isinstance(value, dict):
            classification = value

    missing = [
        key for key in CLASSIFICATION_KEYS if not isinstance(classification.get(key), bool)
    ]
    return {
        "value": classification,
        "missing_keys": missing,
        "complete": not missing,
    }


def steady_metric_mean(benchmark_payload: dict[str, Any] | None, metric: str) -> float | None:
    if not isinstance(benchmark_payload, dict):
        return None
    steady_state = benchmark_payload.get("steady_state")
    if not isinstance(steady_state, dict):
        return None
    metrics = steady_state.get("metrics_per_round")
    if not isinstance(metrics, dict):
        return None
    entry = metrics.get(metric)
    if not isinstance(entry, dict):
        return None
    mean_value = entry.get("mean")
    if isinstance(mean_value, (int, float)):
        return float(mean_value)
    return None


def steady_state_summary(benchmark_payload: dict[str, Any] | None) -> dict[str, Any]:
    steady_state = {}
    if isinstance(benchmark_payload, dict):
        value = benchmark_payload.get("steady_state")
        if isinstance(value, dict):
            steady_state = value

    start_round = steady_state.get("start_round")
    included_rounds = steady_state.get("included_rounds")
    metrics = steady_state.get("metrics_per_round")
    metrics_present = isinstance(metrics, dict) and bool(metrics)
    return {
        "value": steady_state,
        "start_round": start_round if isinstance(start_round, int) else None,
        "included_rounds": included_rounds if isinstance(included_rounds, int) else None,
        "metrics_present": metrics_present,
        "usable": isinstance(start_round, int)
        and isinstance(included_rounds, int)
        and included_rounds > 0
        and metrics_present,
    }


def metric_coverage(benchmark_payload: dict[str, Any] | None, metrics: tuple[str, ...]) -> dict[str, bool]:
    return {metric: steady_metric_mean(benchmark_payload, metric) is not None for metric in metrics}


def benchmark_validation(
    report: dict[str, Any],
    mode: str,
    *,
    required_metrics: tuple[str, ...],
) -> dict[str, Any]:
    payload = benchmark(report, mode)
    if payload is None:
        return {
            "present": False,
            "status": None,
            "status_ok": False,
            "workload": {"value": {}, "missing_keys": list(WORKLOAD_KEYS), "complete": False},
            "steady_state": {
                "value": {},
                "start_round": None,
                "included_rounds": None,
                "metrics_present": False,
                "usable": False,
            },
            "classification": {
                "value": {},
                "missing_keys": list(CLASSIFICATION_KEYS),
                "complete": False,
            },
            "metric_coverage": {metric: False for metric in required_metrics},
            "capabilities": {},
        }

    status = payload.get("status")
    workload = workload_summary(payload)
    steady_state = steady_state_summary(payload)
    classification = classification_summary(payload)
    coverage = metric_coverage(payload, required_metrics)
    capabilities = payload.get("capabilities")

    return {
        "present": True,
        "status": status if isinstance(status, str) else None,
        "status_ok": status == "ok",
        "workload": workload,
        "steady_state": steady_state,
        "classification": classification,
        "metric_coverage": coverage,
        "capabilities": capabilities if isinstance(capabilities, dict) else {},
    }


def workload_pair_summary(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    left_workload = ((left.get("workload") or {}).get("value") or {}) if isinstance(left, dict) else {}
    right_workload = ((right.get("workload") or {}).get("value") or {}) if isinstance(right, dict) else {}

    compared_keys = [
        key
        for key in WORKLOAD_KEYS
        if isinstance(left_workload.get(key), int) and isinstance(right_workload.get(key), int)
    ]
    missing_keys = [
        key
        for key in WORKLOAD_KEYS
        if not isinstance(left_workload.get(key), int) or not isinstance(right_workload.get(key), int)
    ]
    differing_keys = [
        key
        for key in compared_keys
        if int(left_workload[key]) != int(right_workload[key])
    ]
    return {
        "left": left_workload,
        "right": right_workload,
        "compared_keys": compared_keys,
        "missing_keys": missing_keys,
        "differing_keys": differing_keys,
        "matched": not missing_keys and not differing_keys,
    }


def pair_validation_summary(
    freebsd_validation: dict[str, Any],
    macos_validation: dict[str, Any],
) -> dict[str, Any]:
    blockers: list[str] = []
    stop_blockers: list[str] = []
    warnings: list[str] = []

    freebsd_benchmarks = freebsd_validation.get("benchmarks") or {}
    macos_benchmarks = macos_validation.get("benchmarks") or {}
    freebsd_primary = freebsd_benchmarks.get(PRIMARY_MODE) or {}
    macos_primary = macos_benchmarks.get(PRIMARY_MODE) or {}
    freebsd_control = freebsd_benchmarks.get(CONTROL_MODE) or {}
    macos_control = macos_benchmarks.get(CONTROL_MODE) or {}

    primary_workload = workload_pair_summary(freebsd_primary, macos_primary)
    control_workload = workload_pair_summary(freebsd_control, macos_control)

    freebsd_start = ((freebsd_primary.get("steady_state") or {}).get("start_round"))
    macos_start = ((macos_primary.get("steady_state") or {}).get("start_round"))
    steady_state_window = {
        "freebsd_start_round": freebsd_start if isinstance(freebsd_start, int) else None,
        "macos_start_round": macos_start if isinstance(macos_start, int) else None,
        "matched": isinstance(freebsd_start, int)
        and isinstance(macos_start, int)
        and freebsd_start == macos_start,
    }

    if not freebsd_validation.get("comparison_ready"):
        blockers.append("freebsd artifact is not comparison-ready")
        warnings.extend(f"freebsd: {value}" for value in freebsd_validation.get("blockers", []))
    if not macos_validation.get("comparison_ready"):
        blockers.append("macos artifact is not comparison-ready")
        warnings.extend(f"macos: {value}" for value in macos_validation.get("blockers", []))
    if not primary_workload["matched"]:
        if primary_workload["missing_keys"]:
            blockers.append(
                "primary workload tuple is incomplete "
                f"({','.join(primary_workload['missing_keys'])})"
            )
        elif primary_workload["differing_keys"]:
            blockers.append(
                "primary workload tuple differs "
                f"({','.join(primary_workload['differing_keys'])})"
            )
    if not steady_state_window["matched"]:
        blockers.append(
            "primary steady-state start round differs "
            f"(freebsd={steady_state_window['freebsd_start_round']} "
            f"macos={steady_state_window['macos_start_round']})"
        )

    if not freebsd_validation.get("stop_ready"):
        stop_blockers.append("freebsd artifact is not stop-ready")
        warnings.extend(f"freebsd-stop: {value}" for value in freebsd_validation.get("stop_blockers", []))
    if not macos_validation.get("stop_ready"):
        stop_blockers.append("macos artifact is not stop-ready")
        warnings.extend(f"macos-stop: {value}" for value in macos_validation.get("stop_blockers", []))
    if not control_workload["matched"]:
        if control_workload["missing_keys"]:
            stop_blockers.append(
                "control workload tuple is incomplete "
                f"({','.join(control_workload['missing_keys'])})"
            )
        elif control_workload["differing_keys"]:
            stop_blockers.append(
                "control workload tuple differs "
                f"({','.join(control_workload['differing_keys'])})"
            )

    return {
        "comparison_ready": not blockers,
        "stop_ready": not blockers and not stop_blockers,
        "blockers": blockers,
        "stop_blockers": stop_blockers,
        "warnings": warnings,
        "primary_workload": primary_workload,
        "control_workload": control_workload,
        "steady_state_window": steady_state_window,
    }


def validate_normalized_report(
    report: dict[str, Any],
    *,
    expected_platform: str | None,
) -> dict[str, Any]:
    blockers: list[str] = []
    stop_blockers: list[str] = []
    warnings: list[str] = []

    schema_version = report.get("schema_version")
    platform = detect_platform_from_payload(report)
    metadata = report.get("metadata")
    benchmarks = report.get("benchmarks")

    if not isinstance(schema_version, int):
        blockers.append("schema_version is missing or not an integer")
    if not isinstance(metadata, dict):
        blockers.append("metadata is missing or not an object")
    elif not isinstance(metadata.get("source_kind"), str):
        blockers.append("metadata.source_kind is missing or not a string")
    if not isinstance(benchmarks, dict):
        blockers.append("benchmarks is missing or not an object")

    if expected_platform is not None:
        if platform is None:
            blockers.append(f"platform could not be determined (expected {expected_platform})")
        elif platform != expected_platform:
            blockers.append(f"platform mismatch (expected {expected_platform}, got {platform})")

    primary = benchmark_validation(
        report,
        PRIMARY_MODE,
        required_metrics=PRIMARY_DECISION_METRICS + PRIMARY_SUPPORTING_METRICS,
    )
    control = benchmark_validation(
        report,
        CONTROL_MODE,
        required_metrics=CONTROL_METRICS,
    )

    if not primary["present"]:
        blockers.append("primary benchmark is missing")
    if not primary["status_ok"]:
        blockers.append(f"primary benchmark status is not ok ({primary['status']})")
    if not primary["workload"]["complete"]:
        blockers.append(
            "primary workload tuple is incomplete "
            f"({','.join(primary['workload']['missing_keys'])})"
        )
    if not primary["steady_state"]["usable"]:
        blockers.append("primary steady-state summary is missing or empty")
    if not primary["classification"]["complete"]:
        blockers.append(
            "primary classification is incomplete "
            f"({','.join(primary['classification']['missing_keys'])})"
        )
    for metric in PRIMARY_DECISION_METRICS:
        if not primary["metric_coverage"][metric]:
            blockers.append(f"missing primary decision metric: {metric}")
    for metric in PRIMARY_SUPPORTING_METRICS:
        if not primary["metric_coverage"][metric]:
            warnings.append(f"missing supporting primary metric: {metric}")

    if not control["present"]:
        stop_blockers.append("control benchmark is missing")
    if not control["status_ok"]:
        stop_blockers.append(f"control benchmark status is not ok ({control['status']})")
    if not control["workload"]["complete"]:
        stop_blockers.append(
            "control workload tuple is incomplete "
            f"({','.join(control['workload']['missing_keys'])})"
        )
    if not control["steady_state"]["usable"]:
        stop_blockers.append("control steady-state summary is missing or empty")
    if not control["classification"]["complete"]:
        stop_blockers.append(
            "control classification is incomplete "
            f"({','.join(control['classification']['missing_keys'])})"
        )
    for metric in CONTROL_METRICS:
        if not control["metric_coverage"][metric]:
            stop_blockers.append(f"missing control metric: {metric}")

    return {
        "schema_version": schema_version,
        "platform": platform,
        "expected_platform": expected_platform,
        "label": report.get("label"),
        "comparison_ready": not blockers,
        "stop_ready": not blockers and not stop_blockers,
        "blockers": blockers,
        "stop_blockers": stop_blockers,
        "warnings": warnings,
        "benchmarks": {
            PRIMARY_MODE: primary,
            CONTROL_MODE: control,
        },
        "metadata": metadata if isinstance(metadata, dict) else {},
    }


def normalize_source(
    path: Path,
    *,
    kind: str,
    expected_platform: str | None,
    start_round: int,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    if kind == "normalized":
        return load_json(path), {
            "attempted": False,
            "succeeded": True,
            "kind": kind,
            "used_existing": True,
        }

    if kind in {"missing", "unknown", "comparison"}:
        return None, {
            "attempted": False,
            "succeeded": False,
            "kind": kind,
            "error": f"unsupported source kind: {kind}",
        }

    script = repo_root() / "scripts" / "benchmarks" / "extract-m14-benchmark.py"
    command = [
        sys.executable,
        str(script),
        "--steady-state-start-round",
        str(start_round),
        "--label",
        f"validated-{path.stem}",
    ]
    if kind == "report":
        command.extend(["--macos-report", str(path)])
    elif kind == "benchmark-json":
        command.extend(["--freebsd-benchmark-json", str(path)])
    elif kind == "round-snapshots":
        command.extend(["--freebsd-round-snapshots-json", str(path)])
    elif kind == "serial-log":
        command.extend(["--freebsd-serial-log", str(path)])
    else:
        return None, {
            "attempted": False,
            "succeeded": False,
            "kind": kind,
            "error": f"unsupported source kind: {kind}",
        }

    with tempfile.TemporaryDirectory(prefix="m14-validate-") as tmpdir:
        output_path = Path(tmpdir) / "normalized.json"
        completed_command = command + ["--out", str(output_path)]
        try:
            completed = subprocess.run(
                completed_command,
                cwd=repo_root(),
                text=True,
                capture_output=True,
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            return None, {
                "attempted": True,
                "succeeded": False,
                "kind": kind,
                "expected_platform": expected_platform,
                "command": completed_command,
                "returncode": exc.returncode,
                "stdout": exc.stdout,
                "stderr": exc.stderr,
                "error": "normalization failed",
            }
        return load_json(output_path), {
            "attempted": True,
            "succeeded": True,
            "kind": kind,
            "expected_platform": expected_platform,
            "command": completed_command,
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }


def validate_source(
    path: Path,
    *,
    kind: str = "auto",
    expected_platform: str | None = None,
    start_round: int = 8,
) -> dict[str, Any]:
    detected_kind = detect_source_kind(path) if kind == "auto" else kind
    schema_audit = audit_source(
        path,
        kind=detected_kind,
        platform=expected_platform,
    )
    normalized, normalization = normalize_source(
        path,
        kind=detected_kind,
        expected_platform=expected_platform,
        start_round=start_round,
    )

    if normalized is None:
        blockers = list(normalization.get("error") and [str(normalization["error"])] or [])
        return {
            "path": str(path),
            "kind": detected_kind,
            "expected_platform": expected_platform,
            "comparison_ready": False,
            "stop_ready": False,
            "blockers": blockers,
            "stop_blockers": [],
            "warnings": [],
            "normalization": normalization,
            "normalized_validation": None,
            "schema_audit": schema_audit,
        }

    normalized_validation = validate_normalized_report(
        normalized,
        expected_platform=expected_platform,
    )
    warnings = list(normalized_validation["warnings"])
    audit_summary = schema_audit.get("summary") or {}
    if audit_summary.get("has_unmapped_fields"):
        warnings.append(
            "schema audit found unmapped raw fields "
            f"(unique={audit_summary.get('total_unmapped_unique_keys')} "
            f"occurrences={audit_summary.get('total_unmapped_occurrences')})"
        )
    return {
        "path": str(path),
        "kind": detected_kind,
        "expected_platform": expected_platform,
        "comparison_ready": normalized_validation["comparison_ready"],
        "stop_ready": normalized_validation["stop_ready"],
        "blockers": list(normalized_validation["blockers"]),
        "stop_blockers": list(normalized_validation["stop_blockers"]),
        "warnings": warnings,
        "normalization": normalization,
        "normalized_validation": normalized_validation,
        "schema_audit": schema_audit,
    }


def render_validation_text(payload: dict[str, Any]) -> str:
    normalized = payload.get("normalized_validation") or {}
    schema_audit = payload.get("schema_audit") or {}
    audit_summary = schema_audit.get("summary") or {}

    lines = [
        f"path={payload.get('path')}",
        f"kind={payload.get('kind')}",
        f"expected_platform={payload.get('expected_platform') or '-'}",
        f"detected_platform={normalized.get('platform') or '-'}",
        f"comparison_ready={payload.get('comparison_ready')}",
        f"stop_ready={payload.get('stop_ready')}",
    ]

    normalization = payload.get("normalization") or {}
    lines.append(
        "normalization:"
        f" attempted={normalization.get('attempted')}"
        f" succeeded={normalization.get('succeeded')}"
        f" used_existing={normalization.get('used_existing', False)}"
    )
    lines.append(
        "schema_audit:"
        f" available={schema_audit.get('available')}"
        f" has_unmapped_fields={audit_summary.get('has_unmapped_fields')}"
        f" total_unmapped_unique_keys={audit_summary.get('total_unmapped_unique_keys')}"
        f" total_unmapped_occurrences={audit_summary.get('total_unmapped_occurrences')}"
    )

    for label, values in (
        ("blockers", payload.get("blockers", [])),
        ("stop_blockers", payload.get("stop_blockers", [])),
        ("warnings", payload.get("warnings", [])),
    ):
        lines.append(f"{label}:")
        if values:
            lines.extend(f"  {value}" for value in values)
        else:
            lines.append("  none")

    benchmarks = normalized.get("benchmarks") or {}
    for label, mode in (("primary", PRIMARY_MODE), ("control", CONTROL_MODE)):
        benchmark_payload = benchmarks.get(mode) or {}
        workload = benchmark_payload.get("workload") or {}
        steady_state = benchmark_payload.get("steady_state") or {}
        classification = benchmark_payload.get("classification") or {}
        lines.append(
            f"{label}:"
            f" present={benchmark_payload.get('present')}"
            f" status={benchmark_payload.get('status')}"
            f" workload_complete={workload.get('complete')}"
            f" steady_state_usable={steady_state.get('usable')}"
            f" classification_complete={classification.get('complete')}"
        )
    return "\n".join(lines) + "\n"
