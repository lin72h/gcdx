#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-workqueue-wake-gate.sh [--help]

Runs the default workqueue wake benchmark suite and compares it against the
suite-native checked-in baseline.

Environment:
  TWQ_VM_IMAGE                         Raw guest disk image
  TWQ_GUEST_ROOT                       Guest root mount point
  TWQ_ARTIFACTS_ROOT                   Host artifacts root
  TWQ_WORKQUEUE_WAKE_BASELINE          Baseline JSON path
  TWQ_WORKQUEUE_WAKE_COMPARE_ARGS      Extra args passed to compare-workqueue-wake-baseline.py
  TWQ_SERIAL_LOG                       Output serial log path
  TWQ_BENCHMARK_JSON                   Output parsed benchmark JSON path
  TWQ_BENCHMARK_LABEL                  Label stored in extracted JSON

All suite sizing environment accepted by run-workqueue-wake-suite.sh is passed
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

baseline=${TWQ_WORKQUEUE_WAKE_BASELINE:-${repo_root}/benchmarks/baselines/m13-workqueue-wake-suite-20260416.json}
serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/workqueue-wake-gate-${timestamp}.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/workqueue-wake-gate-${timestamp}.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-workqueue-wake-gate}
compare_args=${TWQ_WORKQUEUE_WAKE_COMPARE_ARGS:-}

if [ ! -r "$baseline" ]; then
  echo "Baseline JSON is not readable: $baseline" >&2
  exit 66
fi

env \
  TWQ_SERIAL_LOG="$serial_log" \
  TWQ_BENCHMARK_JSON="$benchmark_json" \
  TWQ_BENCHMARK_LABEL="$benchmark_label" \
  sh "${script_dir}/run-workqueue-wake-suite.sh"

echo "==> Comparing workqueue wake suite against baseline"
# Intentional word splitting for optional developer-provided comparator args.
# shellcheck disable=SC2086
python3 "${script_dir}/compare-workqueue-wake-baseline.py" \
  "$baseline" \
  "$benchmark_json" \
  ${compare_args}

echo "Baseline JSON: $baseline"
echo "Candidate JSON: $benchmark_json"
echo "Serial log: $serial_log"
