#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> int:
    script = Path(__file__).with_name("compare-zig-hotpath-baseline.py")
    argv = [
        sys.executable,
        str(script),
        *sys.argv[1:],
        "--counter-metric",
        "reqthreads_count",
        "--counter-metric",
        "thread_enter_count",
        "--counter-metric",
        "thread_return_count",
        "--counter-metric",
        "thread_transfer_count",
        "--counter-metric",
        "thread_mismatch_count",
    ]
    os.execv(sys.executable, argv)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
