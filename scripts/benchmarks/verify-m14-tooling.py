#!/usr/bin/env python3
"""Run fixture-based verification for the repo-native M14 comparison lane."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


PRIMARY_MODE = "swift.dispatchmain-taskhandles-after-repeat"
CONTROL_MODE = "dispatch.main-executor-resume-repeat"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def fixture_dir() -> Path:
    return repo_root() / "fixtures" / "benchmarks"


def run(
    cmd: list[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=repo_root(),
        env=env,
        check=check,
        text=True,
        capture_output=True,
    )


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def expect_close(actual: float, expected: float, message: str, tolerance: float = 1e-9) -> None:
    if abs(actual - expected) > tolerance:
        raise AssertionError(f"{message}: expected {expected}, got {actual}")


def extract_macos_report(source: Path, out: Path) -> dict:
    run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "extract-m14-benchmark.py"),
            "--macos-report",
            str(source),
            "--label",
            "fixture-macos-normalized",
            "--out",
            str(out),
        ]
    )
    return load(out)


def extract_freebsd(source: Path, out: Path) -> dict:
    run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "extract-m14-benchmark.py"),
            "--freebsd-benchmark-json",
            str(source),
            "--label",
            f"normalized-{source.stem}",
            "--out",
            str(out),
        ]
    )
    return load(out)


def extract_freebsd_round_snapshots(source: Path, out: Path) -> dict:
    run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "extract-m14-benchmark.py"),
            "--freebsd-round-snapshots-json",
            str(source),
            "--label",
            f"normalized-{source.stem}",
            "--out",
            str(out),
        ]
    )
    return load(out)


def compare(freebsd: Path, macos: Path, out: Path, expected: str) -> dict:
    run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "compare-m14-benchmarks.py"),
            str(freebsd),
            str(macos),
            "--json-out",
            str(out),
            "--expect-outcome",
            expected,
        ]
    )
    payload = load(out)
    expect(payload["decision"] == expected, f"unexpected decision for {freebsd.name}")
    return payload


def summarize(compare_json: Path) -> str:
    completed = run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "summarize-m14-compare.py"),
            str(compare_json),
        ]
    )
    return completed.stdout


def validate_artifact(
    source: Path,
    *,
    kind: str,
    platform: str,
    tmp: Path,
    expect_ready: bool,
) -> dict:
    json_out = tmp / f"{source.stem}.{platform}.validation.json"
    completed = run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "validate-m14-artifacts.py"),
            str(source),
            "--kind",
            kind,
            "--platform",
            platform,
            "--json-out",
            str(json_out),
        ],
        check=False,
    )
    payload = load(json_out)
    expect(
        payload["comparison_ready"] is expect_ready,
        f"unexpected validation readiness for {source.name}",
    )
    expect(
        (completed.returncode == 0) is expect_ready,
        f"unexpected validator exit code for {source.name}",
    )
    return payload


def audit_artifact(
    source: Path,
    *,
    kind: str,
    platform: str,
    tmp: Path,
    expect_unmapped: bool,
) -> dict:
    json_out = tmp / f"{source.stem}.{platform}.audit.json"
    completed = run(
        [
            sys.executable,
            str(repo_root() / "scripts" / "benchmarks" / "audit-m14-artifact-schema.py"),
            str(source),
            "--kind",
            kind,
            "--platform",
            platform,
            "--json-out",
            str(json_out),
        ]
    )
    payload = load(json_out)
    expect(
        payload["summary"]["has_unmapped_fields"] is expect_unmapped,
        f"unexpected audit unmapped result for {source.name}",
    )
    expect("summary:" in completed.stdout, "audit output omitted summary")
    return payload


def discover(roots: list[Path], out: Path) -> dict:
    cmd = [
        sys.executable,
        str(repo_root() / "scripts" / "benchmarks" / "discover-m14-artifacts.py"),
    ]
    for root in roots:
        cmd.extend(["--root", str(root)])
    cmd.extend(["--json-out", str(out)])
    run(cmd)
    return load(out)


def verify_macos_normalization(tmp: Path) -> Path:
    source = fixture_dir() / "m14-macos-report-minimal.json"
    out = tmp / "macos.normalized.json"
    payload = extract_macos_report(source, out)
    primary = payload["benchmarks"][PRIMARY_MODE]
    control = payload["benchmarks"][CONTROL_MODE]

    expect(primary["capabilities"]["steady_state_dispatch_metrics"], "macOS primary lost dispatch metrics")
    expect(primary["capabilities"]["steady_state_worker_metrics"], "macOS primary lost worker metrics")
    expect(control["classification"]["default_overcommit_receives_mainq_traffic"] is False, "macOS control misclassified")
    expect_close(
        primary["steady_state"]["metrics_per_round"]["dispatch_root_push_mainq_default_overcommit"]["mean"],
        2.0,
        "macOS primary mainq mean mismatch",
    )
    expect_close(
        primary["steady_state"]["metrics_per_round"]["dispatch_root_poke_slow_default_overcommit"]["mean"],
        2.0,
        "macOS primary poke mean mismatch",
    )
    expect_close(
        primary["steady_state"]["metrics_per_round"]["worker_requested_threads"]["mean"],
        11.0,
        "macOS primary worker mean mismatch",
    )
    return out


def verify_freebsd_normalization(tmp: Path, source_name: str) -> Path:
    source = fixture_dir() / source_name
    out = tmp / f"{source.stem}.normalized.json"
    extract_freebsd(source, out)
    return out


def verify_round_snapshot_normalization(tmp: Path, source_name: str) -> Path:
    source = fixture_dir() / source_name
    out = tmp / f"{source.stem}.normalized.json"
    payload = extract_freebsd_round_snapshots(source, out)
    primary = payload["benchmarks"][PRIMARY_MODE]
    expect(primary["capabilities"]["steady_state_dispatch_metrics"], "round-snapshot primary lost dispatch metrics")
    expect(primary["capabilities"]["steady_state_worker_metrics"], "round-snapshot primary lost worker metrics")
    expect_close(
        primary["steady_state"]["metrics_per_round"]["dispatch_root_push_mainq_default_overcommit"]["mean"],
        3.0,
        "round-snapshot mainq mean mismatch",
    )
    expect_close(
        primary["steady_state"]["metrics_per_round"]["worker_requested_threads"]["mean"],
        17.0,
        "round-snapshot worker mean mismatch",
    )
    return out


def verify_runner(tmp: Path, freebsd_source: Path, macos_source: Path) -> dict:
    out_dir = tmp / "runner"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    env = os.environ.copy()
    env["TWQ_M14_FREEBSD_SOURCE"] = str(freebsd_source)
    env["TWQ_M14_MACOS_REPORT"] = str(macos_source)
    run(
        [
            "sh",
            str(repo_root() / "scripts" / "benchmarks" / "run-m14-compare.sh"),
            "--out-dir",
            str(out_dir),
        ],
        env=env,
    )
    payload = load(out_dir / "comparison.json")
    expect(payload["decision"] == "stop_tuning_this_seam", "runner did not preserve stop decision")
    expect((out_dir / "freebsd.input-validation.json").exists(), "runner did not write FreeBSD input validation")
    expect((out_dir / "macos.input-validation.json").exists(), "runner did not write macOS input validation")
    expect((out_dir / "freebsd.input-audit.json").exists(), "runner did not write FreeBSD input audit")
    expect((out_dir / "macos.input-audit.json").exists(), "runner did not write macOS input audit")
    expect((out_dir / "freebsd.normalized-validation.json").exists(), "runner did not write FreeBSD normalized validation")
    expect((out_dir / "macos.normalized-validation.json").exists(), "runner did not write macOS normalized validation")
    return payload


def verify_runner_rejects_invalid_input(tmp: Path) -> None:
    out_dir = tmp / "runner-invalid"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    env = os.environ.copy()
    env["TWQ_M14_FREEBSD_SOURCE"] = str(fixture_dir() / "m14-round-snapshots-invalid.json")
    env["TWQ_M14_FREEBSD_SOURCE_KIND"] = "round-snapshots"
    env["TWQ_M14_MACOS_REPORT"] = str(fixture_dir() / "m14-macos-report-minimal.json")
    completed = run(
        [
            "sh",
            str(repo_root() / "scripts" / "benchmarks" / "run-m14-compare.sh"),
            "--out-dir",
            str(out_dir),
        ],
        env=env,
        check=False,
    )
    expect(completed.returncode == 66, "runner should reject invalid inputs before comparison")
    expect((out_dir / "freebsd.input-validation.json").exists(), "runner did not save invalid FreeBSD validation")
    expect(not (out_dir / "freebsd.normalized.json").exists(), "runner should not normalize invalid FreeBSD input")
    expect(not (out_dir / "comparison.json").exists(), "runner should not compare invalid inputs")


def verify_discovery(tmp: Path) -> dict:
    discovery = discover(
        [
            fixture_dir(),
        ],
        tmp / "discovery.json",
    )
    freebsd_best = discovery.get("freebsd", {}).get("best") or {}
    macos_best = discovery.get("macos", {}).get("best") or {}
    expect(
        freebsd_best.get("kind") == "round-snapshots",
        "discovery should prioritize round-snapshot FreeBSD inputs",
    )
    expect(
        freebsd_best.get("path", "").endswith("m14-round-snapshots-fixture.json"),
        "discovery chose the wrong FreeBSD fixture",
    )
    invalid_freebsd = [
        candidate
        for candidate in discovery.get("freebsd", {}).get("candidates", [])
        if candidate.get("path", "").endswith("m14-round-snapshots-invalid.json")
    ]
    expect(invalid_freebsd, "discovery did not include the invalid FreeBSD fixture")
    expect(
        invalid_freebsd[0].get("validation", {}).get("comparison_ready") is False,
        "invalid FreeBSD fixture should not be comparison-ready",
    )
    expect(
        macos_best.get("path", "").endswith("m14-macos-report-minimal.json"),
        "discovery should prefer the valid macOS fixture report",
    )
    invalid_macos = [
        candidate
        for candidate in discovery.get("macos", {}).get("candidates", [])
        if candidate.get("path", "").endswith("invalid-m14-report.json")
    ]
    expect(invalid_macos, "discovery did not include the invalid macOS fixture")
    expect(
        invalid_macos[0].get("validation", {}).get("comparison_ready") is False,
        "invalid macOS fixture should not be comparison-ready",
    )
    return discovery


def verify_auto_runner(tmp: Path) -> dict:
    out_dir = tmp / "auto-runner"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    env = os.environ.copy()
    env["TWQ_M14_FREEBSD_SOURCE"] = "auto"
    env["TWQ_M14_MACOS_REPORT"] = "auto"
    env["TWQ_M14_DISCOVER_ROOTS"] = str(fixture_dir())
    run(
        [
            "sh",
            str(repo_root() / "scripts" / "benchmarks" / "run-m14-compare.sh"),
            "--out-dir",
            str(out_dir),
        ],
        env=env,
    )
    payload = load(out_dir / "comparison.json")
    expect(payload["decision"] == "stop_tuning_this_seam", "auto runner did not preserve stop decision")
    expect((out_dir / "discovery.json").exists(), "auto runner did not write discovery.json")
    expect((out_dir / "report.txt").exists(), "auto runner did not write report.txt")
    expect((out_dir / "freebsd.input-validation.json").exists(), "auto runner did not write FreeBSD input validation")
    expect((out_dir / "macos.input-validation.json").exists(), "auto runner did not write macOS input validation")
    expect((out_dir / "freebsd.input-audit.json").exists(), "auto runner did not write FreeBSD input audit")
    expect((out_dir / "macos.input-audit.json").exists(), "auto runner did not write macOS input audit")
    return payload


def verify_audit_preference(tmp: Path) -> dict:
    audit_root = tmp / "audit-preference-root"
    if audit_root.exists():
        shutil.rmtree(audit_root)
    audit_root.mkdir(parents=True)

    freebsd_clean = audit_root / "m14-freebsd-clean.json"
    freebsd_drift = audit_root / "m14-freebsd-drift.json"
    macos_clean = audit_root / "m14-macos-clean-report.json"
    macos_drift = audit_root / "m14-macos-drift-report.json"

    shutil.copyfile(fixture_dir() / "m14-freebsd-reference.json", freebsd_clean)
    shutil.copyfile(fixture_dir() / "m14-freebsd-reference-drift.json", freebsd_drift)
    shutil.copyfile(fixture_dir() / "m14-macos-report-minimal.json", macos_clean)
    shutil.copyfile(fixture_dir() / "m14-macos-report-drift.json", macos_drift)

    now = int(time.time())
    os.utime(freebsd_clean, (now - 20, now - 20))
    os.utime(macos_clean, (now - 20, now - 20))
    os.utime(freebsd_drift, (now, now))
    os.utime(macos_drift, (now, now))

    discovery = discover([audit_root], tmp / "audit-preference-discovery.json")
    freebsd_best = discovery.get("freebsd", {}).get("best") or {}
    macos_best = discovery.get("macos", {}).get("best") or {}
    best_pair = discovery.get("pairs", {}).get("best") or {}

    expect(
        freebsd_best.get("path", "").endswith("m14-freebsd-clean.json"),
        "discovery should prefer the clean FreeBSD artifact over a newer driftier one",
    )
    expect(
        macos_best.get("path", "").endswith("m14-macos-clean-report.json"),
        "discovery should prefer the clean macOS artifact over a newer driftier one",
    )
    expect(
        (best_pair.get("freebsd") or {}).get("path", "").endswith("m14-freebsd-clean.json"),
        "best pair should prefer the clean FreeBSD artifact",
    )
    expect(
        (best_pair.get("macos") or {}).get("path", "").endswith("m14-macos-clean-report.json"),
        "best pair should prefer the clean macOS artifact",
    )
    return discovery


def verify_pair_aware_auto_runner(tmp: Path) -> dict:
    pair_root = tmp / "pair-aware-root"
    if pair_root.exists():
        shutil.rmtree(pair_root)
    pair_root.mkdir(parents=True)

    mismatch = pair_root / "m14-freebsd-newest-mismatch.json"
    reference = pair_root / "m14-freebsd-older-reference.json"
    macos = pair_root / "m14-macos-report.json"

    shutil.copyfile(fixture_dir() / "m14-freebsd-workload-mismatch.json", mismatch)
    shutil.copyfile(fixture_dir() / "m14-freebsd-reference.json", reference)
    shutil.copyfile(fixture_dir() / "m14-macos-report-minimal.json", macos)

    now = int(time.time())
    os.utime(reference, (now - 20, now - 20))
    os.utime(macos, (now - 10, now - 10))
    os.utime(mismatch, (now, now))

    discovery = discover([pair_root], tmp / "pair-aware-discovery.json")
    freebsd_best = discovery.get("freebsd", {}).get("best") or {}
    best_pair = discovery.get("pairs", {}).get("best") or {}
    best_pair_validation = best_pair.get("validation") or {}

    expect(
        freebsd_best.get("path", "").endswith("m14-freebsd-newest-mismatch.json"),
        "independent best FreeBSD candidate should remain the newer mismatch fixture",
    )
    expect(
        (best_pair.get("freebsd") or {}).get("path", "").endswith("m14-freebsd-older-reference.json"),
        "best pair should select the matched FreeBSD reference fixture",
    )
    expect(
        best_pair_validation.get("comparison_ready") is True,
        "best pair should be comparison-ready",
    )
    expect(
        best_pair_validation.get("stop_ready") is True,
        "best pair should be stop-ready",
    )

    out_dir = tmp / "pair-aware-runner"
    env = os.environ.copy()
    env["TWQ_M14_FREEBSD_SOURCE"] = "auto"
    env["TWQ_M14_MACOS_REPORT"] = "auto"
    env["TWQ_M14_DISCOVER_ROOTS"] = str(pair_root)
    run(
        [
            "sh",
            str(repo_root() / "scripts" / "benchmarks" / "run-m14-compare.sh"),
            "--out-dir",
            str(out_dir),
        ],
        env=env,
    )

    comparison = load(out_dir / "comparison.json")
    freebsd_normalized = load(out_dir / "freebsd.normalized.json")
    expect(
        comparison["decision"] == "stop_tuning_this_seam",
        "pair-aware auto runner should preserve the matched stop decision",
    )
    expect(
        freebsd_normalized.get("metadata", {}).get("source_path", "").endswith("m14-freebsd-older-reference.json"),
        "auto runner should normalize the best matched FreeBSD artifact, not the newest mismatch",
    )
    return comparison


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="m14-verify-") as tmpdir:
        tmp = Path(tmpdir)
        macos_validation = validate_artifact(
            fixture_dir() / "m14-macos-report-minimal.json",
            kind="report",
            platform="macos",
            tmp=tmp,
            expect_ready=True,
        )
        invalid_macos_validation = validate_artifact(
            fixture_dir() / "invalid-m14-report.json",
            kind="report",
            platform="macos",
            tmp=tmp,
            expect_ready=False,
        )
        expect(
            "missing primary decision metric: dispatch_root_push_mainq_default_overcommit"
            in invalid_macos_validation["blockers"],
            "invalid macOS fixture should report missing primary decision metrics",
        )
        drift_macos_validation = validate_artifact(
            fixture_dir() / "m14-macos-report-drift.json",
            kind="report",
            platform="macos",
            tmp=tmp,
            expect_ready=True,
        )
        expect(
            any("schema audit found unmapped raw fields" in warning for warning in drift_macos_validation["warnings"]),
            "drift macOS fixture should surface schema-audit warnings",
        )
        drift_macos_audit = audit_artifact(
            fixture_dir() / "m14-macos-report-drift.json",
            kind="report",
            platform="macos",
            tmp=tmp,
            expect_unmapped=True,
        )

        macos_normalized = verify_macos_normalization(tmp)

        freebsd_validation = validate_artifact(
            fixture_dir() / "m14-freebsd-reference.json",
            kind="benchmark-json",
            platform="freebsd",
            tmp=tmp,
            expect_ready=True,
        )
        invalid_freebsd_validation = validate_artifact(
            fixture_dir() / "m14-round-snapshots-invalid.json",
            kind="round-snapshots",
            platform="freebsd",
            tmp=tmp,
            expect_ready=False,
        )
        expect(
            "primary classification is incomplete (default_overcommit_receives_mainq_traffic,default_overcommit_continuation_dominant)"
            in invalid_freebsd_validation["blockers"],
            "invalid FreeBSD fixture should report incomplete primary classification",
        )
        drift_freebsd_validation = validate_artifact(
            fixture_dir() / "m14-freebsd-reference-drift.json",
            kind="benchmark-json",
            platform="freebsd",
            tmp=tmp,
            expect_ready=True,
        )
        expect(
            any("schema audit found unmapped raw fields" in warning for warning in drift_freebsd_validation["warnings"]),
            "drift FreeBSD fixture should surface schema-audit warnings",
        )
        drift_freebsd_audit = audit_artifact(
            fixture_dir() / "m14-freebsd-reference-drift.json",
            kind="benchmark-json",
            platform="freebsd",
            tmp=tmp,
            expect_unmapped=True,
        )

        reference_normalized = verify_freebsd_normalization(tmp, "m14-freebsd-reference.json")
        reference_compare = compare(
            reference_normalized,
            macos_normalized,
            tmp / "reference.compare.json",
            "stop_tuning_this_seam",
        )
        reference_summary = summarize(tmp / "reference.compare.json")
        expect("decision=stop_tuning_this_seam" in reference_summary, "summary omitted decision")
        expect("warnings:" in reference_summary, "summary omitted warnings section")
        expect(
            reference_compare["details"]["primary_metrics"]["dispatch_root_push_mainq_default_overcommit"][
                "within_about_target_band"
            ],
            "reference comparison should be within the about-1.5x band",
        )
        expect(
            not reference_compare["details"]["primary_metrics"]["dispatch_root_push_mainq_default_overcommit"][
                "within_target_band"
            ],
            "reference comparison should exceed the strict 1.50x band",
        )

        gap_normalized = verify_freebsd_normalization(tmp, "m14-freebsd-gap.json")
        gap_compare = compare(
            gap_normalized,
            macos_normalized,
            tmp / "gap.compare.json",
            "freebsd_likely_still_has_coalescing_gap",
        )
        expect(
            gap_compare["details"]["primary_metrics"]["dispatch_root_push_mainq_default_overcommit"][
                "freebsd_materially_higher"
            ],
            "gap comparison should exceed the material-gap threshold",
        )

        legacy_normalized = verify_freebsd_normalization(tmp, "m14-freebsd-worker-only-legacy.json")
        legacy_compare = compare(
            legacy_normalized,
            macos_normalized,
            tmp / "legacy.compare.json",
            "inconclusive",
        )
        expect(
            legacy_compare["details"]["primary_classification"]["same_qualitative_split"] is False,
            "legacy worker-only comparison should not claim same qualitative split",
        )

        mismatch_normalized = verify_freebsd_normalization(tmp, "m14-freebsd-workload-mismatch.json")
        mismatch_compare = compare(
            mismatch_normalized,
            macos_normalized,
            tmp / "mismatch.compare.json",
            "inconclusive",
        )
        mismatch_summary = summarize(tmp / "mismatch.compare.json")
        expect(
            "primary workload tuple differs" in mismatch_compare["details"]["rationale"],
            "mismatch rationale should report workload tuple drift",
        )
        expect(
            mismatch_compare["details"]["validation"]["decision_ready"] is False,
            "mismatch comparison should not be decision-ready",
        )
        expect(
            "primary workload tuple differs" in mismatch_summary,
            "mismatch summary should expose the workload blocker",
        )

        round_snapshot_normalized = verify_round_snapshot_normalization(
            tmp,
            "m14-round-snapshots-fixture.json",
        )
        round_snapshot_compare = compare(
            round_snapshot_normalized,
            macos_normalized,
            tmp / "round-snapshots.compare.json",
            "stop_tuning_this_seam",
        )
        expect(
            round_snapshot_compare["details"]["primary_metrics"]["dispatch_root_push_mainq_default_overcommit"][
                "within_about_target_band"
            ],
            "round-snapshot comparison should fall within the about-1.5x band",
        )

        runner_compare = verify_runner(
            tmp,
            fixture_dir() / "m14-freebsd-reference.json",
            fixture_dir() / "m14-macos-report-minimal.json",
        )
        expect(
            runner_compare["details"]["policy"]["about_within_ratio"] == 1.65,
            "runner did not preserve default about-within ratio",
        )

        round_snapshot_runner = verify_runner(
            tmp,
            fixture_dir() / "m14-round-snapshots-fixture.json",
            fixture_dir() / "m14-macos-report-minimal.json",
        )
        expect(
            round_snapshot_runner["decision"] == "stop_tuning_this_seam",
            "round-snapshot runner did not preserve stop decision",
        )
        verify_runner_rejects_invalid_input(tmp)
        discovery = verify_discovery(tmp)
        auto_runner = verify_auto_runner(tmp)
        audit_preference = verify_audit_preference(tmp)
        pair_aware_auto_runner = verify_pair_aware_auto_runner(tmp)

        print("verified m14 tooling")
        print(f"  macos_fixture={fixture_dir() / 'm14-macos-report-minimal.json'}")
        print(f"  macos_validation_ready={macos_validation['comparison_ready']}")
        print(f"  invalid_macos_fixture={fixture_dir() / 'invalid-m14-report.json'}")
        print(f"  invalid_macos_validation_ready={invalid_macos_validation['comparison_ready']}")
        print(f"  drift_macos_fixture={fixture_dir() / 'm14-macos-report-drift.json'}")
        print(f"  drift_macos_validation_ready={drift_macos_validation['comparison_ready']}")
        print(f"  drift_macos_unmapped_keys={drift_macos_audit['summary']['total_unmapped_unique_keys']}")
        print(f"  freebsd_reference_fixture={fixture_dir() / 'm14-freebsd-reference.json'}")
        print(f"  freebsd_validation_ready={freebsd_validation['comparison_ready']}")
        print(f"  drift_freebsd_fixture={fixture_dir() / 'm14-freebsd-reference-drift.json'}")
        print(f"  drift_freebsd_validation_ready={drift_freebsd_validation['comparison_ready']}")
        print(f"  drift_freebsd_unmapped_keys={drift_freebsd_audit['summary']['total_unmapped_unique_keys']}")
        print(f"  freebsd_gap_fixture={fixture_dir() / 'm14-freebsd-gap.json'}")
        print(f"  freebsd_legacy_fixture={fixture_dir() / 'm14-freebsd-worker-only-legacy.json'}")
        print(f"  freebsd_workload_mismatch_fixture={fixture_dir() / 'm14-freebsd-workload-mismatch.json'}")
        print(f"  freebsd_round_snapshots_fixture={fixture_dir() / 'm14-round-snapshots-fixture.json'}")
        print(f"  invalid_freebsd_fixture={fixture_dir() / 'm14-round-snapshots-invalid.json'}")
        print(f"  invalid_freebsd_validation_ready={invalid_freebsd_validation['comparison_ready']}")
        print(f"  reference_decision={reference_compare['decision']}")
        print(f"  gap_decision={gap_compare['decision']}")
        print(f"  legacy_decision={legacy_compare['decision']}")
        print(f"  mismatch_decision={mismatch_compare['decision']}")
        print(f"  round_snapshot_decision={round_snapshot_compare['decision']}")
        print(f"  runner_decision={runner_compare['decision']}")
        print(f"  round_snapshot_runner_decision={round_snapshot_runner['decision']}")
        print(f"  discovered_freebsd={discovery.get('freebsd', {}).get('best', {}).get('path')}")
        print(f"  discovered_macos={discovery.get('macos', {}).get('best', {}).get('path')}")
        print(f"  auto_runner_decision={auto_runner['decision']}")
        print(f"  audit_preference_freebsd={audit_preference.get('freebsd', {}).get('best', {}).get('path')}")
        print(f"  audit_preference_macos={audit_preference.get('macos', {}).get('best', {}).get('path')}")
        print(f"  pair_aware_auto_runner_decision={pair_aware_auto_runner['decision']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
