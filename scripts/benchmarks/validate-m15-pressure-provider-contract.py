#!/usr/bin/env python3
"""Validate pressure-provider artifacts against the checked-in contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", type=Path)
    parser.add_argument("artifact", type=Path)
    parser.add_argument(
        "--kind",
        choices=(
            "derived",
            "live",
            "adapter",
            "session",
            "observer",
            "tracker",
            "bundle",
            "preview",
        ),
        required=True,
    )
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def nested_get(payload: dict, path: tuple[str, ...]):
    value = payload
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def add_check(result: dict, *, kind: str, field: str, status: str, expected=None, actual=None, failure=None):
    result["checks"].append(
        {
            "kind": kind,
            "field": field,
            "status": status,
            "expected": expected,
            "actual": actual,
            "failure": failure,
        }
    )
    if failure:
        result["failures"].append(failure)


def expected_contract_fields(contract: dict) -> dict:
    return {
        "name": contract.get("name"),
        "version": contract.get("version"),
        "current_signal_field": contract.get("current_signal_field"),
        "current_signal_kind": contract.get("current_signal_kind"),
        "quiescence_kind": contract.get("quiescence_kind"),
        "per_bucket_scope": contract.get("per_bucket_scope"),
        "diagnostic_fields": contract.get("diagnostic_fields"),
    }


def validate_top_level(contract: dict, artifact: dict, kind: str, result: dict) -> None:
    provider_scope = artifact.get("provider_scope")
    expected_scope = contract.get("provider_scope")
    if provider_scope == expected_scope:
        add_check(result, kind="top_level", field="provider_scope", status="ok", expected=expected_scope, actual=provider_scope)
    else:
        add_check(
            result,
            kind="top_level",
            field="provider_scope",
            status="fail",
            expected=expected_scope,
            actual=provider_scope,
            failure=f"provider_scope differs (expected {expected_scope!r}, actual {provider_scope!r})",
        )

    actual_contract = artifact.get("contract")
    expected_contract = expected_contract_fields(contract)
    if actual_contract == expected_contract:
        add_check(result, kind="top_level", field="contract", status="ok", expected=expected_contract, actual=actual_contract)
    else:
        add_check(
            result,
            kind="top_level",
            field="contract",
            status="fail",
            expected=expected_contract,
            actual=actual_contract,
            failure=f"contract metadata differs (expected {expected_contract!r}, actual {actual_contract!r})",
        )

    if kind == "derived":
        expected_generation = nested_get(contract, ("derived", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("derived", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "live":
        expected_capture_kind = nested_get(contract, ("live", "capture_kind"))
        actual_capture_kind = artifact.get("capture_kind")
        if actual_capture_kind == expected_capture_kind:
            add_check(result, kind="top_level", field="capture_kind", status="ok", expected=expected_capture_kind, actual=actual_capture_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="capture_kind",
                status="fail",
                expected=expected_capture_kind,
                actual=actual_capture_kind,
                failure=f"capture_kind differs (expected {expected_capture_kind!r}, actual {actual_capture_kind!r})",
            )

        expected_generation = nested_get(contract, ("live", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("live", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "session":
        expected_session_kind = nested_get(contract, ("session", "session_kind"))
        actual_session_kind = artifact.get("session_kind")
        if actual_session_kind == expected_session_kind:
            add_check(result, kind="top_level", field="session_kind", status="ok", expected=expected_session_kind, actual=actual_session_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="session_kind",
                status="fail",
                expected=expected_session_kind,
                actual=actual_session_kind,
                failure=f"session_kind differs (expected {expected_session_kind!r}, actual {actual_session_kind!r})",
            )

        expected_view_kind = nested_get(contract, ("session", "view_kind"))
        actual_view_kind = artifact.get("view_kind")
        if actual_view_kind == expected_view_kind:
            add_check(result, kind="top_level", field="view_kind", status="ok", expected=expected_view_kind, actual=actual_view_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="view_kind",
                status="fail",
                expected=expected_view_kind,
                actual=actual_view_kind,
                failure=f"view_kind differs (expected {expected_view_kind!r}, actual {actual_view_kind!r})",
            )

        expected_generation = nested_get(contract, ("session", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("session", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "observer":
        expected_observer_kind = nested_get(contract, ("observer", "observer_kind"))
        actual_observer_kind = artifact.get("observer_kind")
        if actual_observer_kind == expected_observer_kind:
            add_check(result, kind="top_level", field="observer_kind", status="ok", expected=expected_observer_kind, actual=actual_observer_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="observer_kind",
                status="fail",
                expected=expected_observer_kind,
                actual=actual_observer_kind,
                failure=f"observer_kind differs (expected {expected_observer_kind!r}, actual {actual_observer_kind!r})",
            )

        expected_source_session_kind = nested_get(contract, ("observer", "source_session_kind"))
        actual_source_session_kind = artifact.get("source_session_kind")
        if actual_source_session_kind == expected_source_session_kind:
            add_check(result, kind="top_level", field="source_session_kind", status="ok", expected=expected_source_session_kind, actual=actual_source_session_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="source_session_kind",
                status="fail",
                expected=expected_source_session_kind,
                actual=actual_source_session_kind,
                failure=f"source_session_kind differs (expected {expected_source_session_kind!r}, actual {actual_source_session_kind!r})",
            )

        expected_source_view_kind = nested_get(contract, ("observer", "source_view_kind"))
        actual_source_view_kind = artifact.get("source_view_kind")
        if actual_source_view_kind == expected_source_view_kind:
            add_check(result, kind="top_level", field="source_view_kind", status="ok", expected=expected_source_view_kind, actual=actual_source_view_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="source_view_kind",
                status="fail",
                expected=expected_source_view_kind,
                actual=actual_source_view_kind,
                failure=f"source_view_kind differs (expected {expected_source_view_kind!r}, actual {actual_source_view_kind!r})",
            )

        expected_generation = nested_get(contract, ("observer", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("observer", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "tracker":
        expected_tracker_kind = nested_get(contract, ("tracker", "tracker_kind"))
        actual_tracker_kind = artifact.get("tracker_kind")
        if actual_tracker_kind == expected_tracker_kind:
            add_check(result, kind="top_level", field="tracker_kind", status="ok", expected=expected_tracker_kind, actual=actual_tracker_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="tracker_kind",
                status="fail",
                expected=expected_tracker_kind,
                actual=actual_tracker_kind,
                failure=f"tracker_kind differs (expected {expected_tracker_kind!r}, actual {actual_tracker_kind!r})",
            )

        expected_source_session_kind = nested_get(contract, ("tracker", "source_session_kind"))
        actual_source_session_kind = artifact.get("source_session_kind")
        if actual_source_session_kind == expected_source_session_kind:
            add_check(result, kind="top_level", field="source_session_kind", status="ok", expected=expected_source_session_kind, actual=actual_source_session_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="source_session_kind",
                status="fail",
                expected=expected_source_session_kind,
                actual=actual_source_session_kind,
                failure=f"source_session_kind differs (expected {expected_source_session_kind!r}, actual {actual_source_session_kind!r})",
            )

        expected_source_view_kind = nested_get(contract, ("tracker", "source_view_kind"))
        actual_source_view_kind = artifact.get("source_view_kind")
        if actual_source_view_kind == expected_source_view_kind:
            add_check(result, kind="top_level", field="source_view_kind", status="ok", expected=expected_source_view_kind, actual=actual_source_view_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="source_view_kind",
                status="fail",
                expected=expected_source_view_kind,
                actual=actual_source_view_kind,
                failure=f"source_view_kind differs (expected {expected_source_view_kind!r}, actual {actual_source_view_kind!r})",
            )

        expected_generation = nested_get(contract, ("tracker", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("tracker", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "bundle":
        expected_bundle_kind = nested_get(contract, ("bundle", "bundle_kind"))
        actual_bundle_kind = artifact.get("bundle_kind")
        if actual_bundle_kind == expected_bundle_kind:
            add_check(result, kind="top_level", field="bundle_kind", status="ok", expected=expected_bundle_kind, actual=actual_bundle_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="bundle_kind",
                status="fail",
                expected=expected_bundle_kind,
                actual=actual_bundle_kind,
                failure=f"bundle_kind differs (expected {expected_bundle_kind!r}, actual {actual_bundle_kind!r})",
            )

        for source_field in ("source_session_kind", "source_view_kind", "source_observer_kind", "source_tracker_kind"):
            expected_source_kind = nested_get(contract, ("bundle", source_field))
            actual_source_kind = artifact.get(source_field)
            if actual_source_kind == expected_source_kind:
                add_check(result, kind="top_level", field=source_field, status="ok", expected=expected_source_kind, actual=actual_source_kind)
            else:
                add_check(
                    result,
                    kind="top_level",
                    field=source_field,
                    status="fail",
                    expected=expected_source_kind,
                    actual=actual_source_kind,
                    failure=f"{source_field} differs (expected {expected_source_kind!r}, actual {actual_source_kind!r})",
                )

        expected_generation = nested_get(contract, ("bundle", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("bundle", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    elif kind == "preview":
        expected_preview_kind = nested_get(contract, ("preview", "preview_kind"))
        actual_preview_kind = artifact.get("preview_kind")
        if actual_preview_kind == expected_preview_kind:
            add_check(result, kind="top_level", field="preview_kind", status="ok", expected=expected_preview_kind, actual=actual_preview_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="preview_kind",
                status="fail",
                expected=expected_preview_kind,
                actual=actual_preview_kind,
                failure=f"preview_kind differs (expected {expected_preview_kind!r}, actual {actual_preview_kind!r})",
            )

        expected_generation = nested_get(contract, ("preview", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("preview", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )
    else:
        expected_adapter_kind = nested_get(contract, ("adapter", "adapter_kind"))
        actual_adapter_kind = artifact.get("adapter_kind")
        if actual_adapter_kind == expected_adapter_kind:
            add_check(result, kind="top_level", field="adapter_kind", status="ok", expected=expected_adapter_kind, actual=actual_adapter_kind)
        else:
            add_check(
                result,
                kind="top_level",
                field="adapter_kind",
                status="fail",
                expected=expected_adapter_kind,
                actual=actual_adapter_kind,
                failure=f"adapter_kind differs (expected {expected_adapter_kind!r}, actual {actual_adapter_kind!r})",
            )

        expected_generation = nested_get(contract, ("adapter", "generation_kind"))
        actual_generation = nested_get(artifact, ("metadata", "generation_kind"))
        if actual_generation == expected_generation:
            add_check(result, kind="top_level", field="metadata.generation_kind", status="ok", expected=expected_generation, actual=actual_generation)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.generation_kind",
                status="fail",
                expected=expected_generation,
                actual=actual_generation,
                failure=f"metadata.generation_kind differs (expected {expected_generation!r}, actual {actual_generation!r})",
            )

        expected_time = nested_get(contract, ("adapter", "monotonic_time_kind"))
        actual_time = nested_get(artifact, ("metadata", "monotonic_time_kind"))
        if actual_time == expected_time:
            add_check(result, kind="top_level", field="metadata.monotonic_time_kind", status="ok", expected=expected_time, actual=actual_time)
        else:
            add_check(
                result,
                kind="top_level",
                field="metadata.monotonic_time_kind",
                status="fail",
                expected=expected_time,
                actual=actual_time,
                failure=f"metadata.monotonic_time_kind differs (expected {expected_time!r}, actual {actual_time!r})",
            )


def validate_snapshot_shape(prefix: str, contract: dict, snapshot: dict, result: dict) -> None:
    aggregate = snapshot.get("aggregate") or {}
    flags = snapshot.get("flags") or {}
    per_bucket = ((snapshot.get("diagnostics") or {}).get("per_bucket")) or {}

    for field in contract.get("required_aggregate_fields") or []:
        if field in aggregate:
            add_check(result, kind="shape", field=f"{prefix}.aggregate.{field}", status="ok")
        else:
            add_check(
                result,
                kind="shape",
                field=f"{prefix}.aggregate.{field}",
                status="fail",
                failure=f"{prefix}: aggregate field {field} missing",
            )

    for field in contract.get("required_flag_fields") or []:
        if field in flags:
            add_check(result, kind="shape", field=f"{prefix}.flags.{field}", status="ok")
        else:
            add_check(
                result,
                kind="shape",
                field=f"{prefix}.flags.{field}",
                status="fail",
                failure=f"{prefix}: flag field {field} missing",
            )

    if flags.get("has_per_bucket_diagnostics") is True:
        for gating_flag, fields in (contract.get("per_bucket_fields_by_flag") or {}).items():
            if flags.get(gating_flag) is not True:
                continue
            for field in fields:
                if field in per_bucket:
                    add_check(result, kind="shape", field=f"{prefix}.diagnostics.per_bucket.{field}", status="ok")
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"{prefix}.diagnostics.per_bucket.{field}",
                        status="fail",
                        failure=f"{prefix}: per-bucket field {field} missing",
                    )


def validate_derived(contract: dict, artifact: dict, result: dict) -> None:
    snapshots = artifact.get("snapshots")
    if not isinstance(snapshots, dict) or not snapshots:
        add_check(
            result,
            kind="shape",
            field="snapshots",
            status="fail",
            failure="derived artifact is missing snapshots",
        )
        return

    for label, snapshot in sorted(snapshots.items()):
        validate_snapshot_shape(f"snapshots.{label}", contract, snapshot, result)


def validate_live(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="live artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("live", "required_capture_fields")) or [])
    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )

        snapshots = capture.get("snapshots")
        if not isinstance(snapshots, list) or not snapshots:
            add_check(
                result,
                kind="shape",
                field=f"captures.{label}.snapshots",
                status="fail",
                failure=f"captures.{label}: snapshots missing or empty",
            )
            continue

        for index, snapshot in enumerate(snapshots):
            validate_snapshot_shape(f"captures.{label}.snapshots[{index}]", contract, snapshot, result)


def validate_adapter(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="adapter artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("adapter", "required_capture_fields")) or [])
    required_sample_fields = set(nested_get(contract, ("adapter", "required_sample_fields")) or [])
    required_view_fields = set(nested_get(contract, ("adapter", "required_view_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )

        snapshots = capture.get("snapshots")
        if not isinstance(snapshots, list) or not snapshots:
            add_check(
                result,
                kind="shape",
                field=f"captures.{label}.snapshots",
                status="fail",
                failure=f"captures.{label}: snapshots missing or empty",
            )
            continue

        for index, snapshot in enumerate(snapshots):
            prefix = f"captures.{label}.snapshots[{index}]"
            for field in sorted(required_sample_fields):
                if field in snapshot:
                    add_check(result, kind="shape", field=f"{prefix}.{field}", status="ok")
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"{prefix}.{field}",
                        status="fail",
                        failure=f"{prefix}: field {field} missing",
                    )

            view = snapshot.get("view")
            if not isinstance(view, dict):
                add_check(
                    result,
                    kind="shape",
                    field=f"{prefix}.view",
                    status="fail",
                    failure=f"{prefix}: view missing or not an object",
                )
                continue

            for field in sorted(required_view_fields):
                if field in view:
                    add_check(result, kind="shape", field=f"{prefix}.view.{field}", status="ok")
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"{prefix}.view.{field}",
                        status="fail",
                        failure=f"{prefix}: view field {field} missing",
                    )

            validate_snapshot_shape(prefix, contract, snapshot, result)


def validate_session(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="session artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("session", "required_capture_fields")) or [])
    required_sample_fields = set(nested_get(contract, ("session", "required_sample_fields")) or [])
    required_session_fields = set(nested_get(contract, ("session", "required_session_fields")) or [])
    required_view_fields = set(nested_get(contract, ("session", "required_view_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )

        snapshots = capture.get("snapshots")
        if not isinstance(snapshots, list) or not snapshots:
            add_check(
                result,
                kind="shape",
                field=f"captures.{label}.snapshots",
                status="fail",
                failure=f"captures.{label}: snapshots missing or empty",
            )
            continue

        for index, snapshot in enumerate(snapshots):
            prefix = f"captures.{label}.snapshots[{index}]"
            for field in sorted(required_sample_fields):
                if field in snapshot:
                    add_check(result, kind="shape", field=f"{prefix}.{field}", status="ok")
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"{prefix}.{field}",
                        status="fail",
                        failure=f"{prefix}: field {field} missing",
                    )

            session = snapshot.get("session")
            if not isinstance(session, dict):
                add_check(
                    result,
                    kind="shape",
                    field=f"{prefix}.session",
                    status="fail",
                    failure=f"{prefix}: session missing or not an object",
                )
            else:
                for field in sorted(required_session_fields):
                    if field in session:
                        add_check(result, kind="shape", field=f"{prefix}.session.{field}", status="ok")
                    else:
                        add_check(
                            result,
                            kind="shape",
                            field=f"{prefix}.session.{field}",
                            status="fail",
                            failure=f"{prefix}: session field {field} missing",
                        )

            view = snapshot.get("view")
            if not isinstance(view, dict):
                add_check(
                    result,
                    kind="shape",
                    field=f"{prefix}.view",
                    status="fail",
                    failure=f"{prefix}: view missing or not an object",
                )
                continue

            for field in sorted(required_view_fields):
                if field in view:
                    add_check(result, kind="shape", field=f"{prefix}.view.{field}", status="ok")
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"{prefix}.view.{field}",
                        status="fail",
                        failure=f"{prefix}: view field {field} missing",
                    )

            validate_snapshot_shape(f"{prefix}.view", contract, view, result)


def validate_preview(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="preview artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("preview", "required_capture_fields")) or [])
    required_sample_fields = set(nested_get(contract, ("preview", "required_sample_fields")) or [])
    required_snapshot_fields = set(nested_get(contract, ("preview", "required_snapshot_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )

        snapshots = capture.get("snapshots")
        if not isinstance(snapshots, list) or not snapshots:
            add_check(
                result,
                kind="shape",
                field=f"captures.{label}.snapshots",
                status="fail",
                failure=f"captures.{label}: snapshots missing or empty",
            )
            continue

        for index, snapshot in enumerate(snapshots):
            for field in sorted(required_sample_fields):
                if field in snapshot:
                    add_check(
                        result,
                        kind="shape",
                        field=f"captures.{label}.snapshots[{index}].{field}",
                        status="ok",
                    )
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"captures.{label}.snapshots[{index}].{field}",
                        status="fail",
                        failure=f"captures.{label}.snapshots[{index}]: field {field} missing",
                    )

            raw_snapshot = snapshot.get("snapshot")
            if not isinstance(raw_snapshot, dict):
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.snapshots[{index}].snapshot",
                    status="fail",
                    failure=f"captures.{label}.snapshots[{index}]: snapshot missing or not an object",
                )
                continue

            for field in sorted(required_snapshot_fields):
                if field in raw_snapshot:
                    add_check(
                        result,
                        kind="shape",
                        field=f"captures.{label}.snapshots[{index}].snapshot.{field}",
                        status="ok",
                    )
                else:
                    add_check(
                        result,
                        kind="shape",
                        field=f"captures.{label}.snapshots[{index}].snapshot.{field}",
                        status="fail",
                        failure=f"captures.{label}.snapshots[{index}]: raw field {field} missing",
                    )


def validate_observer(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="observer artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("observer", "required_capture_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )


def validate_tracker(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="tracker artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("tracker", "required_capture_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )


def validate_bundle(contract: dict, artifact: dict, result: dict) -> None:
    captures = artifact.get("captures")
    if not isinstance(captures, dict) or not captures:
        add_check(
            result,
            kind="shape",
            field="captures",
            status="fail",
            failure="bundle artifact is missing captures",
        )
        return

    required_capture_fields = set(nested_get(contract, ("bundle", "required_capture_fields")) or [])

    for label, capture in sorted(captures.items()):
        for field in sorted(required_capture_fields):
            if field in capture:
                add_check(result, kind="shape", field=f"captures.{label}.{field}", status="ok")
            else:
                add_check(
                    result,
                    kind="shape",
                    field=f"captures.{label}.{field}",
                    status="fail",
                    failure=f"captures.{label}: field {field} missing",
                )


def main() -> int:
    args = parse_args()
    contract = load(args.contract)
    artifact = load(args.artifact)

    result = {
        "verdict": "ok",
        "kind": args.kind,
        "contract": str(args.contract),
        "artifact": str(args.artifact),
        "checks": [],
        "failures": [],
    }

    validate_top_level(contract, artifact, args.kind, result)
    if args.kind == "derived":
        validate_derived(contract, artifact, result)
    elif args.kind == "live":
        validate_live(contract, artifact, result)
    elif args.kind == "adapter":
        validate_adapter(contract, artifact, result)
    elif args.kind == "session":
        validate_session(contract, artifact, result)
    elif args.kind == "observer":
        validate_observer(contract, artifact, result)
    elif args.kind == "tracker":
        validate_tracker(contract, artifact, result)
    elif args.kind == "bundle":
        validate_bundle(contract, artifact, result)
    else:
        validate_preview(contract, artifact, result)

    if result["failures"]:
        result["verdict"] = "fail"

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"contract={args.contract}")
    print(f"artifact={args.artifact}")
    print(f"kind={args.kind}")
    print(f"verdict={result['verdict']}")
    for failure in result["failures"]:
        print(f"failure={failure}")

    return 0 if result["verdict"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
