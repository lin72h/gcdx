#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-workqueue-wake-suite.sh [--help]

Runs the default workqueue wake benchmark suite in one guest boot.

Environment:
  TWQ_VM_IMAGE                                  Raw guest disk image
  TWQ_GUEST_ROOT                                Guest root mount point
  TWQ_ARTIFACTS_ROOT                            Host artifacts root
  TWQ_WORKQUEUE_WAKE_SUITE_PLAN                 Optional output path for the generated plan
  TWQ_WORKQUEUE_WAKE_DEFAULT_SAMPLES            wake-default sample count
  TWQ_WORKQUEUE_WAKE_DEFAULT_WARMUP             wake-default warmup count
  TWQ_WORKQUEUE_WAKE_OVERCOMMIT_SAMPLES         wake-overcommit sample count
  TWQ_WORKQUEUE_WAKE_OVERCOMMIT_WARMUP          wake-overcommit warmup count
  TWQ_WORKQUEUE_WAKE_SETTLE_MS                  Settle delay around counter snapshots
  TWQ_WORKQUEUE_WAKE_PRIME_TIMEOUT_MS           Prime callback timeout
  TWQ_WORKQUEUE_WAKE_CALLBACK_TIMEOUT_MS        Per-sample callback timeout
  TWQ_WORKQUEUE_WAKE_QUIESCENT_TIMEOUT_MS       Per-sample quiescent timeout

All other environment accepted by run-workqueue-wake-bench.sh is passed through.
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

wake_default_samples=${TWQ_WORKQUEUE_WAKE_DEFAULT_SAMPLES:-256}
wake_default_warmup=${TWQ_WORKQUEUE_WAKE_DEFAULT_WARMUP:-32}
wake_overcommit_samples=${TWQ_WORKQUEUE_WAKE_OVERCOMMIT_SAMPLES:-256}
wake_overcommit_warmup=${TWQ_WORKQUEUE_WAKE_OVERCOMMIT_WARMUP:-32}
settle_ms=${TWQ_WORKQUEUE_WAKE_SETTLE_MS:-50}
prime_timeout_ms=${TWQ_WORKQUEUE_WAKE_PRIME_TIMEOUT_MS:-3000}
callback_timeout_ms=${TWQ_WORKQUEUE_WAKE_CALLBACK_TIMEOUT_MS:-3000}
quiescent_timeout_ms=${TWQ_WORKQUEUE_WAKE_QUIESCENT_TIMEOUT_MS:-3000}

plan_path=${TWQ_WORKQUEUE_WAKE_SUITE_PLAN:-${artifacts_root}/benchmarks/workqueue-wake-suite-${timestamp}.plan}
serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/workqueue-wake-suite-${timestamp}.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/workqueue-wake-suite-${timestamp}.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-workqueue-wake-suite}

mkdir -p "$(dirname "$plan_path")" "$(dirname "$serial_log")" "$(dirname "$benchmark_json")"
cat > "$plan_path" <<EOF
--mode wake-default --samples ${wake_default_samples} --warmup ${wake_default_warmup} --settle-ms ${settle_ms} --prime-timeout-ms ${prime_timeout_ms} --callback-timeout-ms ${callback_timeout_ms} --quiescent-timeout-ms ${quiescent_timeout_ms}
--mode wake-overcommit --samples ${wake_overcommit_samples} --warmup ${wake_overcommit_warmup} --settle-ms ${settle_ms} --prime-timeout-ms ${prime_timeout_ms} --callback-timeout-ms ${callback_timeout_ms} --quiescent-timeout-ms ${quiescent_timeout_ms}
EOF

env \
  TWQ_WORKQUEUE_WAKE_BENCH_PLAN="$plan_path" \
  TWQ_SERIAL_LOG="$serial_log" \
  TWQ_BENCHMARK_JSON="$benchmark_json" \
  TWQ_BENCHMARK_LABEL="$benchmark_label" \
  sh "${repo_root}/scripts/benchmarks/run-workqueue-wake-bench.sh"
