#!/usr/bin/env python3
"""Normalize M14 artifacts into a common comparison schema."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from statistics import mean
from typing import Any


PRIMARY_MODE = "swift.dispatchmain-taskhandles-after-repeat"
CONTROL_MODE = "dispatch.main-executor-resume-repeat"

ROUND_METADATA_FIELDS = {"round", "completed_rounds", "elapsed_ns"}

WORKLOAD_FIELDS = {
    "rounds",
    "tasks",
    "delay_ms",
    "completed_rounds",
    "expected_total_sum",
    "total_sum",
}

FREEBSD_CONTAINER_KEYS = (
    "benchmarks",
    "round_snapshots",
    "roundSnapshots",
    "lanes",
    "modes",
    "runs",
)

FREEBSD_ROW_CONTAINER_KEYS = (
    "round_snapshots",
    "roundSnapshots",
    "snapshots",
    "rows",
)

FREEBSD_STEADY_STATE_KEYS = (
    "steady_state",
    "steadyState",
)

FREEBSD_FULL_RUN_KEYS = (
    "full_run_metrics",
    "full_run",
    "totals",
)

MODE_ALIASES = {
    PRIMARY_MODE: PRIMARY_MODE,
    "dispatchmain-taskhandles-after-repeat": PRIMARY_MODE,
    CONTROL_MODE: CONTROL_MODE,
    "main-executor-resume-repeat": CONTROL_MODE,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--macos-report",
        type=Path,
        help="Normalized macOS M14 report produced by scripts/macos/extract-m14-introspection-report.py",
    )
    source.add_argument(
        "--freebsd-benchmark-json",
        type=Path,
        help="FreeBSD benchmark JSON produced by scripts/benchmarks/extract-m13-baseline.py",
    )
    source.add_argument(
        "--freebsd-round-snapshots-json",
        type=Path,
        help="FreeBSD M14 round-snapshot JSON with per-round seam metrics",
    )
    source.add_argument(
        "--freebsd-serial-log",
        type=Path,
        help="FreeBSD guest serial log. This is first converted through extract-m13-baseline.py.",
    )
    parser.add_argument("--out", required=True, type=Path, help="Normalized JSON output path")
    parser.add_argument("--label", default="m14-benchmark", help="Label stored in metadata")
    parser.add_argument(
        "--steady-state-start-round",
        type=int,
        default=8,
        help="First round included in steady-state summaries",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def maybe_float(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    return None


def mean_summary(values: list[float]) -> dict[str, float]:
    return {
        "mean": mean(values),
        "min": min(values),
        "max": max(values),
    }


def canonical_metric_name(raw_name: str) -> str | None:
    if raw_name.startswith("dispatch_root_") or raw_name.startswith("worker_"):
        return raw_name
    explicit = {
        "pthread_workqueue_addthreads_calls": "worker_addthreads_calls",
        "pthread_workqueue_addthreads_requested_threads": "worker_requested_threads",
        "reqthreads_count": "worker_requested_threads",
        "reqthreads_delta": "worker_requested_threads",
        "thread_enter_count": "worker_thread_enter",
        "thread_enter_delta": "worker_thread_enter",
        "thread_return_count": "worker_thread_return",
        "thread_return_delta": "worker_thread_return",
    }
    if raw_name in explicit:
        return explicit[raw_name]
    if raw_name.startswith("root_"):
        return f"dispatch_{raw_name}"
    if raw_name in ROUND_METADATA_FIELDS:
        return raw_name
    return None


def canonical_mode_name(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    return MODE_ALIASES.get(value.strip())


def as_dict(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return value
    return None


def as_list(value: Any) -> list[Any] | None:
    if isinstance(value, list):
        return value
    return None


def normalize_workload(data: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(data, dict):
        return {}
    return {
        key: value
        for key, value in data.items()
        if key in WORKLOAD_FIELDS and isinstance(value, int)
    }


def workload_candidate(benchmark: dict[str, Any]) -> dict[str, Any]:
    for key in ("probe", "workload", "config"):
        value = as_dict(benchmark.get(key))
        if value:
            normalized = normalize_workload(value)
            if normalized:
                return normalized
    terminal = as_dict(benchmark.get("terminal"))
    if terminal:
        data = as_dict(terminal.get("data"))
        if data:
            normalized = normalize_workload(data)
            if normalized:
                return normalized
    direct = normalize_workload(benchmark)
    if direct:
        return direct
    return {}


def summarize_rows(rows: list[dict[str, Any]], start_round: int) -> dict[str, Any]:
    selected = [
        row
        for row in rows
        if isinstance(row.get("round"), int) and row["round"] >= start_round
    ]
    summary: dict[str, Any] = {
        "start_round": start_round,
        "end_round": selected[-1]["round"] if selected else None,
        "included_rounds": len(selected),
        "metrics_per_round": {},
    }
    if not selected:
        return summary

    metric_names = sorted(
        {
            key
            for row in selected
            for key, value in row.items()
            if key not in ROUND_METADATA_FIELDS and isinstance(value, (int, float))
        }
    )
    for metric in metric_names:
        values = [float(row[metric]) for row in selected if isinstance(row.get(metric), (int, float))]
        if len(values) != len(selected):
            continue
        summary["metrics_per_round"][metric] = mean_summary(values)
    return summary


def derive_classification(
    full_run_metrics: dict[str, Any],
    steady_state_metrics: dict[str, Any],
    existing: dict[str, Any] | None = None,
) -> dict[str, bool | None]:
    if isinstance(existing, dict):
        return {
            "default_receives_source_traffic": existing.get("default_receives_source_traffic"),
            "default_overcommit_receives_mainq_traffic": existing.get(
                "default_overcommit_receives_mainq_traffic"
            ),
            "default_overcommit_continuation_dominant": existing.get(
                "default_overcommit_continuation_dominant"
            ),
        }

    def metric_max(name: str) -> float | None:
        values: list[float] = []
        full_value = maybe_float(full_run_metrics.get(name))
        if full_value is not None:
            values.append(full_value)
        steady_value = maybe_float(
            steady_state_metrics.get(name, {}).get("mean")
            if isinstance(steady_state_metrics.get(name), dict)
            else None
        )
        if steady_value is not None:
            values.append(steady_value)
        return max(values) if values else None

    source_default = metric_max("dispatch_root_push_source_default")
    mainq = metric_max("dispatch_root_push_mainq_default_overcommit")
    continuation = metric_max("dispatch_root_push_continuation_default_overcommit")
    continuation_dominant = None
    if continuation is not None and mainq is not None:
        continuation_dominant = continuation > mainq

    return {
        "default_receives_source_traffic": None if source_default is None else source_default > 0.0,
        "default_overcommit_receives_mainq_traffic": None if mainq is None else mainq > 0.0,
        "default_overcommit_continuation_dominant": continuation_dominant,
    }


def capability_flags(
    full_run_metrics: dict[str, Any],
    steady_state_metrics: dict[str, Any],
) -> dict[str, bool]:
    full_keys = set(full_run_metrics)
    steady_keys = set(steady_state_metrics)
    return {
        "full_run_dispatch_metrics": any(key.startswith("dispatch_") for key in full_keys),
        "full_run_worker_metrics": any(key.startswith("worker_") for key in full_keys),
        "steady_state_dispatch_metrics": any(key.startswith("dispatch_") for key in steady_keys),
        "steady_state_worker_metrics": any(key.startswith("worker_") for key in steady_keys),
    }


def build_macos_rows(benchmark: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source_row in benchmark.get("per_round", {}).get("rows", []):
        if not isinstance(source_row, dict):
            continue
        row: dict[str, Any] = {}
        for key, value in source_row.items():
            canonical = canonical_metric_name(key)
            if canonical is None:
                if key in ROUND_METADATA_FIELDS and isinstance(value, int):
                    row[key] = value
                continue
            if canonical in ROUND_METADATA_FIELDS and isinstance(value, int):
                row[canonical] = value
                continue
            if isinstance(value, int):
                row[canonical] = value
        if row:
            rows.append(row)
    return rows


def build_macos_metrics(metrics: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical: dict[str, Any] = {}
    raw: dict[str, Any] = {}
    for raw_name, value in metrics.items():
        if not isinstance(value, (int, float)):
            continue
        raw[raw_name] = value
        name = canonical_metric_name(raw_name)
        if name is None or name in ROUND_METADATA_FIELDS:
            continue
        canonical[name] = value
    return canonical, raw


def normalize_existing_steady_state(steady_state: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(steady_state, dict):
        return None

    source_metrics = steady_state.get("metrics_per_round")
    if not isinstance(source_metrics, dict):
        return None

    normalized: dict[str, Any] = {
        "start_round": steady_state.get("start_round"),
        "end_round": steady_state.get("end_round"),
        "included_rounds": steady_state.get("included_rounds"),
        "metrics_per_round": {},
    }
    for raw_name, value in source_metrics.items():
        canonical = canonical_metric_name(raw_name)
        if canonical is None or canonical in ROUND_METADATA_FIELDS:
            continue
        if not isinstance(value, dict):
            continue
        mean_value = value.get("mean")
        min_value = value.get("min")
        max_value = value.get("max")
        if not all(isinstance(item, (int, float)) for item in (mean_value, min_value, max_value)):
            continue
        normalized["metrics_per_round"][canonical] = {
            "mean": float(mean_value),
            "min": float(min_value),
            "max": float(max_value),
        }
    return normalized


def benchmark_status(benchmark: dict[str, Any]) -> str | None:
    status = benchmark.get("status")
    if isinstance(status, str):
        return status
    terminal = as_dict(benchmark.get("terminal"))
    if terminal and isinstance(terminal.get("status"), str):
        return terminal["status"]
    return None


def existing_classification_source(benchmark: dict[str, Any]) -> dict[str, Any] | None:
    source = as_dict(benchmark.get("classification"))
    if source:
        return source
    values = {
        "default_receives_source_traffic": benchmark.get("default_receives_source_traffic"),
        "default_overcommit_receives_mainq_traffic": benchmark.get(
            "default_overcommit_receives_mainq_traffic"
        ),
        "default_overcommit_continuation_dominant": benchmark.get(
            "default_overcommit_continuation_dominant"
        ),
    }
    if any(value is not None for value in values.values()):
        return values
    return None


def existing_steady_state_source(benchmark: dict[str, Any]) -> dict[str, Any] | None:
    for key in FREEBSD_STEADY_STATE_KEYS:
        source = as_dict(benchmark.get(key))
        if source:
            return source
    per_round = benchmark.get("per_round")
    if isinstance(per_round, dict):
        for key in FREEBSD_STEADY_STATE_KEYS:
            source = as_dict(per_round.get(key))
            if source:
                return source
    summary = as_dict(benchmark.get("summary"))
    if summary:
        for key in FREEBSD_STEADY_STATE_KEYS:
            source = as_dict(summary.get(key))
            if source:
                return source
    return None


def full_run_sources(benchmark: dict[str, Any]) -> list[dict[str, Any]]:
    sources: list[dict[str, Any]] = []
    for key in FREEBSD_FULL_RUN_KEYS:
        source = as_dict(benchmark.get(key))
        if source:
            sources.append(source)
    summary = as_dict(benchmark.get("summary"))
    if summary:
        for key in FREEBSD_FULL_RUN_KEYS:
            source = as_dict(summary.get(key))
            if source:
                sources.append(source)
    return sources


def row_sources(benchmark: dict[str, Any]) -> list[list[Any]]:
    sources: list[list[Any]] = []
    per_round = benchmark.get("per_round")
    if isinstance(per_round, list):
        sources.append(per_round)
    elif isinstance(per_round, dict):
        rows = as_list(per_round.get("rows"))
        if rows:
            sources.append(rows)
        for key in FREEBSD_ROW_CONTAINER_KEYS:
            rows = as_list(per_round.get(key))
            if rows:
                sources.append(rows)
    for key in FREEBSD_ROW_CONTAINER_KEYS:
        rows = as_list(benchmark.get(key))
        if rows:
            sources.append(rows)
    return sources


def coerce_freebsd_benchmark(entry: dict[str, Any], mode: str) -> dict[str, Any]:
    benchmark = dict(entry)
    benchmark.setdefault("mode", mode)

    workload = workload_candidate(benchmark)
    if workload:
        benchmark.setdefault("probe", workload)

    steady = existing_steady_state_source(benchmark)
    if steady and "steady_state" not in benchmark:
        benchmark["steady_state"] = steady

    if "classification" not in benchmark:
        classification = existing_classification_source(benchmark)
        if classification:
            benchmark["classification"] = classification

    if "status" not in benchmark:
        status = benchmark_status(benchmark)
        if status is not None:
            benchmark["status"] = status

    if "per_round" not in benchmark:
        for rows in row_sources(benchmark):
            benchmark["per_round"] = {"rows": rows}
            break

    if "full_run" not in benchmark and "full_run_metrics" not in benchmark:
        sources = full_run_sources(benchmark)
        if sources:
            benchmark["full_run"] = sources[0]

    return benchmark


def register_candidate(target: dict[str, dict[str, Any]], mode: str | None, entry: Any) -> None:
    if mode is None or not isinstance(entry, dict):
        return
    target.setdefault(mode, coerce_freebsd_benchmark(entry, mode))


def benchmark_index_from_payload(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    benchmarks: dict[str, dict[str, Any]] = {}

    for key in FREEBSD_CONTAINER_KEYS:
        container = payload.get(key)
        if isinstance(container, dict):
            for entry_key, entry_value in container.items():
                mode = canonical_mode_name(entry_key)
                if mode is None and isinstance(entry_value, dict):
                    mode = canonical_mode_name(entry_value.get("mode"))
                register_candidate(benchmarks, mode, entry_value)
        elif isinstance(container, list):
            for entry in container:
                if not isinstance(entry, dict):
                    continue
                mode = None
                for mode_key in ("mode", "benchmark", "name", "label"):
                    mode = canonical_mode_name(entry.get(mode_key))
                    if mode is not None:
                        break
                register_candidate(benchmarks, mode, entry)

    for mode in (PRIMARY_MODE, CONTROL_MODE):
        if mode in benchmarks:
            continue
        direct = payload.get(mode)
        if isinstance(direct, dict):
            register_candidate(benchmarks, mode, direct)

    if benchmarks:
        return benchmarks

    def walk(value: Any, depth: int = 0) -> None:
        if depth > 4:
            return
        if isinstance(value, dict):
            for mode_key in ("mode", "benchmark", "name", "label"):
                mode = canonical_mode_name(value.get(mode_key))
                if mode is not None:
                    register_candidate(benchmarks, mode, value)
                    break
            for child_key, child_value in value.items():
                child_mode = canonical_mode_name(child_key)
                if child_mode is not None and isinstance(child_value, dict):
                    register_candidate(benchmarks, child_mode, child_value)
                walk(child_value, depth + 1)
        elif isinstance(value, list):
            for item in value:
                walk(item, depth + 1)

    walk(payload)
    return benchmarks


def normalize_macos_report(path: Path, label: str, start_round: int) -> dict[str, Any]:
    payload = load_json(path)
    output = {
        "schema_version": 1,
        "label": label,
        "platform": "macos",
        "metadata": {
            "source_kind": "macos-report",
            "source_path": str(path.resolve()),
            "steady_state_start_round": start_round,
            "source_label": payload.get("label"),
            "symbol_probe_reality": payload.get("symbol_probe_reality"),
            "measurement_setup": payload.get("measurement_setup"),
        },
        "benchmarks": {},
    }

    for mode in (PRIMARY_MODE, CONTROL_MODE):
        benchmark = payload.get("benchmarks", {}).get(mode)
        if not isinstance(benchmark, dict):
            continue

        workload = workload_candidate(benchmark)
        full_run_metrics, raw_full_run_metrics = build_macos_metrics(benchmark.get("full_run") or {})
        rows = build_macos_rows(benchmark)
        steady_state = summarize_rows(rows, start_round)
        classification = derive_classification(
            full_run_metrics,
            steady_state.get("metrics_per_round", {}),
            benchmark.get("classification"),
        )
        output["benchmarks"][mode] = {
            "mode": mode,
            "platform": "macos",
            "status": benchmark.get("terminal", {}).get("status"),
            "workload": workload,
            "full_run_metrics": full_run_metrics,
            "steady_state": steady_state,
            "per_round": {
                "row_count": len(rows),
                "rows": rows,
            },
            "classification": classification,
            "capabilities": capability_flags(
                full_run_metrics,
                steady_state.get("metrics_per_round", {}),
            ),
            "source_metrics": {
                "full_run": raw_full_run_metrics,
            },
            "artifacts": {
                "raw_log": benchmark.get("raw_log"),
            },
        }

    return output


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def extract_freebsd_json_from_serial_log(serial_log: Path, label: str) -> dict[str, Any]:
    extract_script = repo_root() / "scripts" / "benchmarks" / "extract-m13-baseline.py"
    with tempfile.TemporaryDirectory(prefix="m14-freebsd-") as tmpdir:
        tmp_json = Path(tmpdir) / "freebsd-benchmark.json"
        subprocess.run(
            [
                sys.executable,
                str(extract_script),
                "--serial-log",
                str(serial_log),
                "--out",
                str(tmp_json),
                "--label",
                label,
            ],
            check=True,
            cwd=repo_root(),
        )
        return load_json(tmp_json)


def load_freebsd_source(
    path: Path | None,
    serial_log: Path | None,
    label: str,
    source_kind: str,
) -> tuple[dict[str, Any], str]:
    if path is not None:
        return load_json(path), source_kind
    if serial_log is not None:
        return extract_freebsd_json_from_serial_log(serial_log, label), "freebsd-serial-log"
    raise ValueError("one FreeBSD source is required")


def extract_freebsd_full_run_metrics(benchmark: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    canonical: dict[str, Any] = {}
    raw: dict[str, Any] = {}

    for source_metrics in full_run_sources(benchmark):
        for raw_name, value in source_metrics.items():
            if not isinstance(value, (int, float)):
                continue
            raw[raw_name] = value
            name = canonical_metric_name(raw_name)
            if name is not None and name not in ROUND_METADATA_FIELDS:
                canonical[name] = value

    twq_delta = benchmark.get("twq_delta") or {}
    for raw_name, value in twq_delta.items():
        if not isinstance(value, int):
            continue
        raw[raw_name] = value
        name = canonical_metric_name(raw_name)
        if name is not None and name not in ROUND_METADATA_FIELDS:
            canonical[name] = value

    last_dispatch = None
    counters = benchmark.get("libdispatch_counters") or []
    if counters and isinstance(counters[-1], dict):
        last_dispatch = counters[-1]
    if isinstance(last_dispatch, dict):
        for raw_name, value in last_dispatch.items():
            if not isinstance(value, int):
                continue
            raw[raw_name] = value
            name = canonical_metric_name(raw_name)
            if name is not None and name not in ROUND_METADATA_FIELDS:
                canonical[name] = value

    return canonical, raw


def build_freebsd_rows(benchmark: dict[str, Any]) -> list[dict[str, Any]]:
    for existing_rows in row_sources(benchmark):
        rows: list[dict[str, Any]] = []
        for source_row in existing_rows:
            if not isinstance(source_row, dict):
                continue
            row: dict[str, Any] = {}
            for raw_name, value in source_row.items():
                canonical = canonical_metric_name(raw_name)
                if canonical is None:
                    if raw_name in ROUND_METADATA_FIELDS and isinstance(value, int):
                        row[raw_name] = value
                    continue
                if canonical in ROUND_METADATA_FIELDS and isinstance(value, int):
                    row[canonical] = value
                    continue
                if isinstance(value, (int, float)):
                    row[canonical] = value
            if row:
                rows.append(row)
        if rows:
            return rows

    round_metrics = benchmark.get("round_metrics") or {}
    rounds = round_metrics.get("round_ok_rounds")
    if not isinstance(rounds, list) or not all(isinstance(value, int) for value in rounds):
        return []

    rows = [{"round": round_id} for round_id in rounds]
    completed = round_metrics.get("round_ok_completed_rounds")
    if isinstance(completed, list) and len(completed) == len(rows):
        for row, value in zip(rows, completed):
            if isinstance(value, int):
                row["completed_rounds"] = value

    for raw_name, values in round_metrics.items():
        if not raw_name.startswith("round_ok_"):
            continue
        if raw_name in {"round_ok_rounds", "round_ok_completed_rounds"}:
            continue
        if not isinstance(values, list) or len(values) != len(rows):
            continue

        metric_name = raw_name[len("round_ok_") :]
        canonical = canonical_metric_name(metric_name)
        if canonical is None or canonical in ROUND_METADATA_FIELDS:
            continue
        if not all(isinstance(value, int) for value in values):
            continue
        for row, value in zip(rows, values):
            row[canonical] = value

    return rows


def normalize_freebsd_report(
    path: Path | None,
    serial_log: Path | None,
    source_kind: str,
    label: str,
    start_round: int,
) -> dict[str, Any]:
    payload, source_kind = load_freebsd_source(path, serial_log, label, source_kind)
    source_path = path.resolve() if path is not None else serial_log.resolve()
    source_label = payload.get("baseline") or payload.get("metadata", {}).get("label") or payload.get("label")
    output = {
        "schema_version": 1,
        "label": label,
        "platform": "freebsd",
        "metadata": {
            "source_kind": source_kind,
            "source_path": str(source_path),
            "steady_state_start_round": start_round,
            "source_label": source_label,
            "source_metadata": payload.get("metadata"),
        },
        "benchmarks": {},
    }

    benchmarks = benchmark_index_from_payload(payload)
    for mode in (PRIMARY_MODE, CONTROL_MODE):
        benchmark = benchmarks.get(mode)
        if not isinstance(benchmark, dict):
            continue

        workload = workload_candidate(benchmark)
        full_run_metrics, raw_full_run_metrics = extract_freebsd_full_run_metrics(benchmark)
        rows = build_freebsd_rows(benchmark)
        steady_state = summarize_rows(rows, start_round)
        existing_steady_state = normalize_existing_steady_state(existing_steady_state_source(benchmark))
        if steady_state.get("included_rounds", 0) == 0 and existing_steady_state is not None:
            steady_state = existing_steady_state
        classification = derive_classification(
            full_run_metrics,
            steady_state.get("metrics_per_round", {}),
            existing_classification_source(benchmark),
        )
        output["benchmarks"][mode] = {
            "mode": mode,
            "platform": "freebsd",
            "status": benchmark_status(benchmark),
            "workload": workload,
            "full_run_metrics": full_run_metrics,
            "steady_state": steady_state,
            "per_round": {
                "row_count": len(rows),
                "rows": rows,
            },
            "classification": classification,
            "capabilities": capability_flags(
                full_run_metrics,
                steady_state.get("metrics_per_round", {}),
            ),
            "source_metrics": {
                "full_run": raw_full_run_metrics,
            },
            "artifacts": {
                "serial_log": str(serial_log.resolve()) if serial_log is not None else None,
            },
        }

    return output


def main() -> int:
    args = parse_args()
    if args.macos_report is not None:
        payload = normalize_macos_report(args.macos_report, args.label, args.steady_state_start_round)
    else:
        freebsd_path = args.freebsd_benchmark_json
        freebsd_kind = "freebsd-benchmark-json"
        if args.freebsd_round_snapshots_json is not None:
            freebsd_path = args.freebsd_round_snapshots_json
            freebsd_kind = "freebsd-round-snapshots-json"
        payload = normalize_freebsd_report(
            freebsd_path,
            args.freebsd_serial_log,
            freebsd_kind,
            args.label,
            args.steady_state_start_round,
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
