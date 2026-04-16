#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import json
import platform
import re
import shutil
import subprocess
from pathlib import Path


SYMBOLS = (
    {
        "name": "_dispatch_root_queue_push",
        "library": "libdispatch",
        "sdk_relpath": "usr/lib/system/libdispatch.tbd",
        "runtime_library": "/usr/lib/libSystem.dylib",
    },
    {
        "name": "_dispatch_root_queue_poke_slow",
        "library": "libdispatch",
        "sdk_relpath": "usr/lib/system/libdispatch.tbd",
        "runtime_library": "/usr/lib/libSystem.dylib",
    },
    {
        "name": "_pthread_workqueue_addthreads",
        "library": "libpthread",
        "sdk_relpath": "usr/lib/system/libsystem_pthread.tbd",
        "runtime_library": "/usr/lib/libpthread.dylib",
    },
    {
        "name": "_dispatch_queue_cleanup2",
        "library": "libdispatch",
        "sdk_relpath": "usr/lib/system/libdispatch.tbd",
        "runtime_library": "/usr/lib/libSystem.dylib",
    },
    {
        "name": "_dispatch_lane_barrier_complete",
        "library": "libdispatch",
        "sdk_relpath": "usr/lib/system/libdispatch.tbd",
        "runtime_library": "/usr/lib/libSystem.dylib",
    },
)

RELEVANT_XCTRACE_INSTRUMENTS = (
    "GCD Performance",
    "Runloops",
    "Swift Tasks",
    "Thread State Trace",
    "os_signpost",
)

RELEVANT_XCTRACE_TEMPLATES = (
    "Swift Concurrency",
    "System Trace",
    "Time Profiler",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inspect stock macOS symbol visibility and traceability for the M14 comparison seams."
    )
    parser.add_argument(
        "--out",
        type=Path,
        help="Optional JSON output path. Defaults to stdout.",
    )
    return parser.parse_args()


def run_command(*argv: str) -> dict:
    try:
        completed = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        return {
            "argv": list(argv),
            "rc": None,
            "stdout": "",
            "stderr": str(exc),
        }
    return {
        "argv": list(argv),
        "rc": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def tool_output(command: dict) -> str:
    stdout = command.get("stdout", "")
    stderr = command.get("stderr", "")
    return "\n".join(part for part in (stdout.strip(), stderr.strip()) if part)


def find_sdk_path() -> Path | None:
    result = run_command("xcrun", "--show-sdk-path")
    if result["rc"] != 0:
        return None
    sdk = result["stdout"].strip()
    return Path(sdk) if sdk else None


def has_token(text: str, token: str) -> bool:
    pattern = re.compile(rf"(?<![A-Za-z0-9$_]){re.escape(token)}(?![A-Za-z0-9$_])")
    return bool(pattern.search(text))


def macho_export_name(source_symbol: str) -> str:
    return f"_{source_symbol}"


def load_tbd(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def runtime_lookup(symbol: str, library_path: str) -> int | None:
    try:
        lib = ctypes.CDLL(library_path)
    except OSError:
        return None
    try:
        return ctypes.cast(getattr(lib, symbol), ctypes.c_void_p).value
    except AttributeError:
        return None


def classify_traceability(
    sdk_exports_source_symbol: bool,
    sdk_exports_macho_symbol: bool,
    runtime_dlsym_resolvable: bool,
    dtrace_accessible: bool,
) -> str:
    if runtime_dlsym_resolvable and dtrace_accessible:
        return "runtime_resolvable_and_dtrace_accessible"
    if runtime_dlsym_resolvable:
        return "runtime_resolvable_but_dtrace_blocked_or_unavailable"
    if sdk_exports_source_symbol or sdk_exports_macho_symbol:
        return "sdk_exported_but_not_runtime_resolved"
    return "not_exported_in_stock_sdk"


def collect_xctrace_support() -> dict:
    xctrace_path = shutil.which("xctrace")
    result = {
        "path": xctrace_path,
        "available": xctrace_path is not None,
        "relevant_instruments": {},
        "relevant_templates": {},
    }
    if not xctrace_path:
        return result

    instruments = run_command(xctrace_path, "list", "instruments")
    instrument_text = tool_output(instruments)
    result["list_instruments_rc"] = instruments["rc"]
    for name in RELEVANT_XCTRACE_INSTRUMENTS:
        result["relevant_instruments"][name] = name in instrument_text

    templates = run_command(xctrace_path, "list", "templates")
    template_text = tool_output(templates)
    result["list_templates_rc"] = templates["rc"]
    for name in RELEVANT_XCTRACE_TEMPLATES:
        result["relevant_templates"][name] = name in template_text
    return result


def collect_metadata(sdk_path: Path | None) -> dict:
    metadata = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "sdk_path": str(sdk_path) if sdk_path else None,
        "swift_version": tool_output(run_command("swiftc", "--version")),
        "xcode_swift_version": tool_output(
            run_command("xcrun", "--toolchain", "XcodeDefault", "swiftc", "--version")
        ),
        "sw_vers": tool_output(run_command("sw_vers")),
        "uname": tool_output(run_command("uname", "-a")),
        "xcodebuild_version": tool_output(run_command("xcodebuild", "-version")),
    }
    return metadata


def main() -> int:
    args = parse_args()
    sdk_path = find_sdk_path()
    dtrace = run_command("dtrace", "-l")
    dtrace_accessible = dtrace["rc"] == 0

    payload = {
        "metadata": collect_metadata(sdk_path),
        "tools": {
            "dtrace": {
                "rc": dtrace["rc"],
                "accessible": dtrace_accessible,
                "message": tool_output(dtrace),
            },
            "xctrace": collect_xctrace_support(),
        },
        "symbols": {},
    }

    for spec in SYMBOLS:
        sdk_tbd_path = sdk_path / spec["sdk_relpath"] if sdk_path else None
        tbd_text = ""
        if sdk_tbd_path and sdk_tbd_path.exists():
            tbd_text = load_tbd(sdk_tbd_path)

        source_symbol = spec["name"]
        macho_symbol = macho_export_name(source_symbol)
        sdk_exports_source_symbol = bool(tbd_text) and has_token(tbd_text, source_symbol)
        sdk_exports_macho_symbol = bool(tbd_text) and has_token(tbd_text, macho_symbol)
        runtime_ptr = runtime_lookup(source_symbol, spec["runtime_library"])

        payload["symbols"][source_symbol] = {
            "library": spec["library"],
            "sdk_tbd_path": str(sdk_tbd_path) if sdk_tbd_path else None,
            "sdk_exports_source_symbol": sdk_exports_source_symbol,
            "sdk_exports_macho_symbol": sdk_exports_macho_symbol,
            "runtime_library": spec["runtime_library"],
            "runtime_dlsym_resolvable": runtime_ptr is not None,
            "runtime_pointer": runtime_ptr,
            "stock_live_traceability": classify_traceability(
                sdk_exports_source_symbol=sdk_exports_source_symbol,
                sdk_exports_macho_symbol=sdk_exports_macho_symbol,
                runtime_dlsym_resolvable=runtime_ptr is not None,
                dtrace_accessible=dtrace_accessible,
            ),
        }

    rendered = json.dumps(payload, indent=2, sort_keys=True)
    if args.out:
        args.out.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
