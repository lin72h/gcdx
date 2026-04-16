#!/usr/bin/env python3
"""Summarize M13 push-vtable DTrace output.

The DTrace script logs runtime pointers. This helper infers the libdispatch
load slide from known vtable symbols, then maps root queue pointers and object
vtables to readable names.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import subprocess


ROOT_LABELS = [
    "maintenance",
    "maintenance.overcommit",
    "background",
    "background.overcommit",
    "utility",
    "utility.overcommit",
    "default",
    "default.overcommit",
    "user-initiated",
    "user-initiated.overcommit",
    "user-interactive",
    "user-interactive.overcommit",
]

ROOT_QUEUE_ENTRY_SIZE = 0x80


def parse_int(value: str) -> int | None:
    try:
        return int(value, 16 if value.startswith("0x") else 16)
    except ValueError:
        return None


def load_symbols(path: Path) -> dict[str, int]:
    output = subprocess.check_output(["nm", "-a", str(path)], text=True)
    symbols: dict[str, int] = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            addr = int(parts[0], 16)
        except ValueError:
            continue
        symbols[parts[2]] = addr
    return symbols


def parse_trace(path: Path) -> tuple[Counter[tuple[int, int]], Counter[int]]:
    pushes: Counter[tuple[int, int]] = Counter()
    pops: Counter[int] = Counter()
    with path.open(errors="ignore") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 7 and parts[1] == "push_vtable":
                rq = parse_int(parts[3])
                vt = parse_int(parts[5])
                if rq is not None and vt is not None:
                    pushes[(rq, vt)] += 1
            elif len(parts) >= 7 and parts[1] == "pop_vtable":
                vt = parse_int(parts[5])
                if vt is not None:
                    pops[vt] += 1
    return pushes, pops


def infer_slide(vtables: Counter[int], symbols: dict[str, int]) -> int | None:
    candidates: set[int] = set()
    known = {
        name: addr
        for name, addr in symbols.items()
        if "vtable" in name and name.startswith("__OS_dispatch_")
    }
    known_addrs = set(known.values())
    for runtime_addr in vtables:
        if runtime_addr < 0x1000:
            continue
        for symbol_addr in known.values():
            candidates.add(runtime_addr - symbol_addr)
    if not candidates:
        return None
    scored: Counter[int] = Counter()
    for candidate in candidates:
        for runtime_addr, count in vtables.items():
            if runtime_addr >= 0x1000 and runtime_addr - candidate in known_addrs:
                scored[candidate] += count
    if not scored:
        return None
    return scored.most_common(1)[0][0]


def nearest_symbol(offset: int, symbols: dict[str, int]) -> str:
    best_name = None
    best_addr = -1
    for name, addr in symbols.items():
        if addr <= offset and addr > best_addr:
            best_name = name
            best_addr = addr
    if best_name is None:
        return f"offset+0x{offset:x}"
    delta = offset - best_addr
    if delta == 0:
        return best_name
    return f"{best_name}+0x{delta:x}"


def root_label(rq: int, slide: int, symbols: dict[str, int]) -> str:
    root_base = symbols.get("_dispatch_root_queues")
    if root_base is None:
        return f"rq=0x{rq:x}"
    off = rq - slide - root_base
    if off < 0 or off % ROOT_QUEUE_ENTRY_SIZE != 0:
        return f"rq=0x{rq:x}"
    idx = off // ROOT_QUEUE_ENTRY_SIZE
    if 0 <= idx < len(ROOT_LABELS):
        return f"{ROOT_LABELS[idx]}[{idx}]"
    return f"root[{idx}]"


def describe_vtable(vt: int, slide: int, symbols: dict[str, int]) -> str:
    if vt < 0x1000:
        return f"continuation-inline-0x{vt:x}"
    return nearest_symbol(vt - slide, symbols)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("serial_log", type=Path)
    parser.add_argument(
        "--libdispatch",
        type=Path,
        default=Path("/Users/me/wip-gcd-tbb-fx/artifacts/libdispatch-stage/libdispatch.so"),
    )
    args = parser.parse_args()

    symbols = load_symbols(args.libdispatch)
    pushes, pops = parse_trace(args.serial_log)
    vtables = Counter()
    for (_, vt), count in pushes.items():
        vtables[vt] += count
    slide = infer_slide(vtables, symbols)
    if slide is None:
        raise SystemExit("could not infer libdispatch load slide")

    print(f"libdispatch_slide=0x{slide:x}")
    print("pushes_by_root_and_object:")
    for (rq, vt), count in pushes.most_common():
        print(
            f"  {count:5d} {root_label(rq, slide, symbols):32s} "
            f"{describe_vtable(vt, slide, symbols)}"
        )

    print("pops_by_object:")
    for vt, count in pops.most_common():
        print(f"  {count:5d} {describe_vtable(vt, slide, symbols)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
