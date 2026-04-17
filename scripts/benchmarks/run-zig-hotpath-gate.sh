#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-zig-hotpath-gate.sh [--help]

Runs the default Zig TWQ syscall hot-path suite and compares it against the
suite-native checked-in baseline.

Environment:
  TWQ_VM_IMAGE                    Raw guest disk image
  TWQ_GUEST_ROOT                  Guest root mount point
  TWQ_ARTIFACTS_ROOT              Host artifacts root
  TWQ_ZIG_HOTPATH_BASELINE        Baseline JSON path
  TWQ_ZIG_HOTPATH_COMPARE_ARGS    Extra args passed to compare-zig-hotpath-baseline.py
  TWQ_SERIAL_LOG                  Output serial log path
  TWQ_BENCHMARK_JSON              Output parsed benchmark JSON path
  TWQ_BENCHMARK_LABEL             Label stored in extracted JSON

All suite sizing environment accepted by run-zig-hotpath-suite.sh is passed
through unchanged.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/../.." && pwd)
artifacts_root=${TWQ_ARTIFACTS_ROOT:-${repo_root}/../artifacts}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)

baseline=${TWQ_ZIG_HOTPATH_BASELINE:-${repo_root}/benchmarks/baselines/m13-zig-hotpath-suite-20260416.json}
serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/zig-hotpath-gate-${timestamp}.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/zig-hotpath-gate-${timestamp}.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-zig-hotpath-gate}
compare_args=${TWQ_ZIG_HOTPATH_COMPARE_ARGS:-}

if [ ! -r "$baseline" ]; then
  echo "Baseline JSON is not readable: $baseline" >&2
  exit 66
fi

env \
  TWQ_SERIAL_LOG="$serial_log" \
  TWQ_BENCHMARK_JSON="$benchmark_json" \
  TWQ_BENCHMARK_LABEL="$benchmark_label" \
  sh "${script_dir}/run-zig-hotpath-suite.sh"

echo "==> Comparing Zig hot-path suite against baseline"
# Intentional word splitting for optional developer-provided comparator args.
# shellcheck disable=SC2086
python3 "${script_dir}/compare-zig-hotpath-baseline.py" \
  "$baseline" \
  "$benchmark_json" \
  ${compare_args}

echo "Baseline JSON: $baseline"
echo "Candidate JSON: $benchmark_json"
echo "Serial log: $serial_log"
