#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-zig-hotpath-suite.sh [--help]

Runs the default Zig TWQ syscall hot-path suite in one guest boot.

Environment:
  TWQ_VM_IMAGE                         Raw guest disk image
  TWQ_GUEST_ROOT                       Guest root mount point
  TWQ_ARTIFACTS_ROOT                   Host artifacts root
  TWQ_ZIG_HOTPATH_SUITE_PLAN           Optional output path for the generated plan
  TWQ_ZIG_BENCH_SHOULD_NARROW_SAMPLES  should-narrow sample count
  TWQ_ZIG_BENCH_SHOULD_NARROW_WARMUP   should-narrow warmup count
  TWQ_ZIG_BENCH_REQTHREADS_SAMPLES     reqthreads sample count
  TWQ_ZIG_BENCH_REQTHREADS_WARMUP      reqthreads warmup count
  TWQ_ZIG_BENCH_OVERCOMMIT_SAMPLES     reqthreads-overcommit sample count
  TWQ_ZIG_BENCH_OVERCOMMIT_WARMUP      reqthreads-overcommit warmup count
  TWQ_ZIG_BENCH_THREAD_ENTER_SAMPLES   thread-enter sample count
  TWQ_ZIG_BENCH_THREAD_ENTER_WARMUP    thread-enter warmup count
  TWQ_ZIG_BENCH_THREAD_RETURN_SAMPLES  thread-return sample count
  TWQ_ZIG_BENCH_THREAD_RETURN_WARMUP   thread-return warmup count
  TWQ_ZIG_BENCH_THREAD_TRANSFER_SAMPLES thread-transfer sample count
  TWQ_ZIG_BENCH_THREAD_TRANSFER_WARMUP thread-transfer warmup count
  TWQ_ZIG_BENCH_REQUEST_COUNT          Request count for reqthreads modes
  TWQ_ZIG_BENCH_REQUESTED_FEATURES     Requested features for INIT
  TWQ_ZIG_BENCH_SETTLE_MS              Settle delay after warmup and sample phase

All other environment accepted by run-zig-hotpath-bench.sh is passed through.
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

should_narrow_samples=${TWQ_ZIG_BENCH_SHOULD_NARROW_SAMPLES:-1024}
should_narrow_warmup=${TWQ_ZIG_BENCH_SHOULD_NARROW_WARMUP:-128}
reqthreads_samples=${TWQ_ZIG_BENCH_REQTHREADS_SAMPLES:-256}
reqthreads_warmup=${TWQ_ZIG_BENCH_REQTHREADS_WARMUP:-32}
overcommit_samples=${TWQ_ZIG_BENCH_OVERCOMMIT_SAMPLES:-256}
overcommit_warmup=${TWQ_ZIG_BENCH_OVERCOMMIT_WARMUP:-32}
thread_enter_samples=${TWQ_ZIG_BENCH_THREAD_ENTER_SAMPLES:-256}
thread_enter_warmup=${TWQ_ZIG_BENCH_THREAD_ENTER_WARMUP:-32}
thread_return_samples=${TWQ_ZIG_BENCH_THREAD_RETURN_SAMPLES:-256}
thread_return_warmup=${TWQ_ZIG_BENCH_THREAD_RETURN_WARMUP:-32}
thread_transfer_samples=${TWQ_ZIG_BENCH_THREAD_TRANSFER_SAMPLES:-256}
thread_transfer_warmup=${TWQ_ZIG_BENCH_THREAD_TRANSFER_WARMUP:-32}
request_count=${TWQ_ZIG_BENCH_REQUEST_COUNT:-1}
requested_features=${TWQ_ZIG_BENCH_REQUESTED_FEATURES:-0}
settle_ms=${TWQ_ZIG_BENCH_SETTLE_MS:-50}

plan_path=${TWQ_ZIG_HOTPATH_SUITE_PLAN:-${artifacts_root}/benchmarks/zig-hotpath-suite-${timestamp}.plan}
serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/zig-hotpath-suite-${timestamp}.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/zig-hotpath-suite-${timestamp}.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-zig-hotpath-suite}

mkdir -p "$(dirname "$plan_path")" "$(dirname "$serial_log")" "$(dirname "$benchmark_json")"
cat > "$plan_path" <<EOF
--mode should-narrow --samples ${should_narrow_samples} --warmup ${should_narrow_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
--mode reqthreads --samples ${reqthreads_samples} --warmup ${reqthreads_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
--mode reqthreads-overcommit --samples ${overcommit_samples} --warmup ${overcommit_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
--mode thread-enter --samples ${thread_enter_samples} --warmup ${thread_enter_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
--mode thread-return --samples ${thread_return_samples} --warmup ${thread_return_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
--mode thread-transfer --samples ${thread_transfer_samples} --warmup ${thread_transfer_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${settle_ms}
EOF

env \
  TWQ_ZIG_HOTPATH_BENCH_PLAN="$plan_path" \
  TWQ_SERIAL_LOG="$serial_log" \
  TWQ_BENCHMARK_JSON="$benchmark_json" \
  TWQ_BENCHMARK_LABEL="$benchmark_label" \
  sh "${repo_root}/scripts/benchmarks/run-zig-hotpath-bench.sh"
