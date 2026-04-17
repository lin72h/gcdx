#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-lowlevel-suite.sh [--help]

Runs the full M13 low-level suite in one guest boot:

1. Zig TWQ syscall hot-path suite
2. warmed-worker workqueue wake suite

Environment:
  TWQ_VM_IMAGE                               Raw guest disk image
  TWQ_GUEST_ROOT                             Guest root mount point
  TWQ_VM_NAME                                bhyve guest name
  TWQ_VM_VCPUS                               Guest vCPU count
  TWQ_VM_MEMORY                              Guest memory size
  TWQ_ARTIFACTS_ROOT                         Host artifacts root
  TWQ_ZIG_BIN                                Zig compiler
  TWQ_SERIAL_LOG                             Output serial log path
  TWQ_BENCHMARK_JSON                         Output parsed combined benchmark JSON path
  TWQ_BENCHMARK_LABEL                        Label stored in extracted JSON
  TWQ_M13_LOWLEVEL_SUITE_DIR                 Optional directory used for generated plan files
  TWQ_ZIG_HOTPATH_SUITE_PLAN                 Optional explicit Zig plan path
  TWQ_WORKQUEUE_WAKE_SUITE_PLAN              Optional explicit wake plan path
  TWQ_ZIG_BENCH_SHOULD_NARROW_SAMPLES        should-narrow sample count
  TWQ_ZIG_BENCH_SHOULD_NARROW_WARMUP         should-narrow warmup count
  TWQ_ZIG_BENCH_REQTHREADS_SAMPLES           reqthreads sample count
  TWQ_ZIG_BENCH_REQTHREADS_WARMUP            reqthreads warmup count
  TWQ_ZIG_BENCH_OVERCOMMIT_SAMPLES           reqthreads-overcommit sample count
  TWQ_ZIG_BENCH_OVERCOMMIT_WARMUP            reqthreads-overcommit warmup count
  TWQ_ZIG_BENCH_THREAD_ENTER_SAMPLES         thread-enter sample count
  TWQ_ZIG_BENCH_THREAD_ENTER_WARMUP          thread-enter warmup count
  TWQ_ZIG_BENCH_THREAD_RETURN_SAMPLES        thread-return sample count
  TWQ_ZIG_BENCH_THREAD_RETURN_WARMUP         thread-return warmup count
  TWQ_ZIG_BENCH_THREAD_TRANSFER_SAMPLES      thread-transfer sample count
  TWQ_ZIG_BENCH_THREAD_TRANSFER_WARMUP       thread-transfer warmup count
  TWQ_ZIG_BENCH_REQUEST_COUNT                Request count for reqthreads modes
  TWQ_ZIG_BENCH_REQUESTED_FEATURES           Requested features for INIT
  TWQ_ZIG_BENCH_SETTLE_MS                    Settle delay after warmup and sample phase
  TWQ_WORKQUEUE_WAKE_DEFAULT_SAMPLES         wake-default sample count
  TWQ_WORKQUEUE_WAKE_DEFAULT_WARMUP          wake-default warmup count
  TWQ_WORKQUEUE_WAKE_OVERCOMMIT_SAMPLES      wake-overcommit sample count
  TWQ_WORKQUEUE_WAKE_OVERCOMMIT_WARMUP       wake-overcommit warmup count
  TWQ_WORKQUEUE_WAKE_SETTLE_MS               Settle delay around counter snapshots
  TWQ_WORKQUEUE_WAKE_PRIME_TIMEOUT_MS        Prime callback timeout
  TWQ_WORKQUEUE_WAKE_CALLBACK_TIMEOUT_MS     Per-sample callback timeout
  TWQ_WORKQUEUE_WAKE_QUIESCENT_TIMEOUT_MS    Per-sample quiescent timeout
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

suite_dir=${TWQ_M13_LOWLEVEL_SUITE_DIR:-${artifacts_root}/benchmarks/m13-lowlevel-suite-${timestamp}}
serial_log=${TWQ_SERIAL_LOG:-${suite_dir}/m13-lowlevel.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${suite_dir}/m13-lowlevel.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-m13-lowlevel-suite}
zig_plan=${TWQ_ZIG_HOTPATH_SUITE_PLAN:-${suite_dir}/zig-hotpath.plan}
wake_plan=${TWQ_WORKQUEUE_WAKE_SUITE_PLAN:-${suite_dir}/workqueue-wake.plan}

vm_image=${TWQ_VM_IMAGE:-}
guest_root=${TWQ_GUEST_ROOT:-}
vm_name=${TWQ_VM_NAME:-twq-dev}
vm_vcpus=${TWQ_VM_VCPUS:-4}
vm_memory=${TWQ_VM_MEMORY:-8G}

if [ -z "$vm_image" ] || [ -z "$guest_root" ]; then
  echo "TWQ_VM_IMAGE and TWQ_GUEST_ROOT are required" >&2
  exit 64
fi

wait_for_serial_marker() {
  log_path=$1
  marker=$2
  timeout_sec=$3
  elapsed=0

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if [ -f "$log_path" ] && grep -Fq "$marker" "$log_path"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

mkdir -p "$suite_dir" "$(dirname "$serial_log")" "$(dirname "$benchmark_json")"

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
zig_settle_ms=${TWQ_ZIG_BENCH_SETTLE_MS:-50}

wake_default_samples=${TWQ_WORKQUEUE_WAKE_DEFAULT_SAMPLES:-256}
wake_default_warmup=${TWQ_WORKQUEUE_WAKE_DEFAULT_WARMUP:-32}
wake_overcommit_samples=${TWQ_WORKQUEUE_WAKE_OVERCOMMIT_SAMPLES:-256}
wake_overcommit_warmup=${TWQ_WORKQUEUE_WAKE_OVERCOMMIT_WARMUP:-32}
wake_settle_ms=${TWQ_WORKQUEUE_WAKE_SETTLE_MS:-50}
prime_timeout_ms=${TWQ_WORKQUEUE_WAKE_PRIME_TIMEOUT_MS:-3000}
callback_timeout_ms=${TWQ_WORKQUEUE_WAKE_CALLBACK_TIMEOUT_MS:-3000}
quiescent_timeout_ms=${TWQ_WORKQUEUE_WAKE_QUIESCENT_TIMEOUT_MS:-3000}

cat > "$zig_plan" <<EOF
--mode should-narrow --samples ${should_narrow_samples} --warmup ${should_narrow_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
--mode reqthreads --samples ${reqthreads_samples} --warmup ${reqthreads_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
--mode reqthreads-overcommit --samples ${overcommit_samples} --warmup ${overcommit_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
--mode thread-enter --samples ${thread_enter_samples} --warmup ${thread_enter_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
--mode thread-return --samples ${thread_return_samples} --warmup ${thread_return_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
--mode thread-transfer --samples ${thread_transfer_samples} --warmup ${thread_transfer_warmup} --request-count ${request_count} --requested-features ${requested_features} --settle-ms ${zig_settle_ms}
EOF

cat > "$wake_plan" <<EOF
--mode wake-default --samples ${wake_default_samples} --warmup ${wake_default_warmup} --settle-ms ${wake_settle_ms} --prime-timeout-ms ${prime_timeout_ms} --callback-timeout-ms ${callback_timeout_ms} --quiescent-timeout-ms ${quiescent_timeout_ms}
--mode wake-overcommit --samples ${wake_overcommit_samples} --warmup ${wake_overcommit_warmup} --settle-ms ${wake_settle_ms} --prime-timeout-ms ${prime_timeout_ms} --callback-timeout-ms ${callback_timeout_ms} --quiescent-timeout-ms ${quiescent_timeout_ms}
EOF

zig_prefix=${TWQ_ZIG_PREFIX:-${artifacts_root}/zig/prefix}
zig_cache_dir=${TWQ_ZIG_CACHE_DIR:-${artifacts_root}/zig/cache}
zig_global_cache_dir=${TWQ_ZIG_GLOBAL_CACHE_DIR:-${artifacts_root}/zig/global-cache}
pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${artifacts_root}/libthr-stage}
pthread_headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${artifacts_root}/pthread-headers}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${artifacts_root}/libdispatch-stage}
dispatch_build_dir=${TWQ_LIBDISPATCH_BUILD_DIR:-${artifacts_root}/libdispatch-build}
dispatch_probe_bin=${TWQ_DISPATCH_PROBE_BIN:-${zig_prefix}/bin/twq-dispatch-probe}
workqueue_probe_bin=${TWQ_WORKQUEUE_PROBE_BIN:-${zig_prefix}/bin/twq-workqueue-probe}
workqueue_wake_bench_bin=${TWQ_WORKQUEUE_WAKE_BENCH_BIN:-${zig_prefix}/bin/twq-bench-workqueue-wake}
zig_bench_bin=${TWQ_ZIG_HOTPATH_BENCH_BIN:-${zig_prefix}/bin/twq-bench-syscall}
dispatch_src_dir=${TWQ_LIBDISPATCH_SRC:-${repo_root}/../nx/swift-corelibs-libdispatch}

if [ -n "${TWQ_ZIG_BIN:-}" ]; then
  zig_bin=${TWQ_ZIG_BIN}
elif command -v zig >/dev/null 2>&1; then
  zig_bin=$(command -v zig)
elif [ -x /usr/local/bin/zig-dev ]; then
  zig_bin=/usr/local/bin/zig-dev
else
  echo "Unable to find a Zig compiler; set TWQ_ZIG_BIN or install zig/zig-dev" >&2
  exit 66
fi

mkdir -p "$zig_prefix/bin" "$zig_cache_dir" "$zig_global_cache_dir"

echo "==> Refreshing libthr stage"
sh "${repo_root}/scripts/libthr/prepare-stage.sh"

echo "==> Refreshing pthread headers"
sh "${repo_root}/scripts/libthr/prepare-headers.sh"

echo "==> Refreshing libdispatch stage"
sh "${repo_root}/scripts/libdispatch/prepare-stage.sh"

echo "==> Refreshing Swift stage"
sh "${repo_root}/scripts/swift/prepare-stage.sh"

echo "==> Building Zig helpers"
(cd "${repo_root}/zig" && "$zig_bin" build \
  --prefix "$zig_prefix" \
  --cache-dir "$zig_cache_dir" \
  --global-cache-dir "$zig_global_cache_dir")

echo "==> Building Zig hot-path benchmark"
(cd "${repo_root}/zig" && "$zig_bin" build bench-syscall \
  --prefix "$zig_prefix" \
  --cache-dir "$zig_cache_dir" \
  --global-cache-dir "$zig_global_cache_dir")

echo "==> Building workqueue probe"
cc \
  -I"$pthread_headers_dir" \
  "${repo_root}/csrc/twq_workqueue_probe.c" \
  -L"$pthread_stage_dir" \
  -Wl,-rpath,"$pthread_stage_dir" \
  -lthr \
  -lc \
  -o "$workqueue_probe_bin"

echo "==> Building workqueue wake benchmark"
cc \
  -I"$pthread_headers_dir" \
  "${repo_root}/csrc/twq_workqueue_wake_bench.c" \
  -L"$pthread_stage_dir" \
  -Wl,-rpath,"$pthread_stage_dir" \
  -lthr \
  -lm \
  -lc \
  -o "$workqueue_wake_bench_bin"

echo "==> Building libdispatch probe"
cc \
  -I"$dispatch_src_dir" \
  -I"$dispatch_build_dir" \
  -I"$pthread_headers_dir" \
  "${repo_root}/csrc/twq_dispatch_probe.c" \
  -L"$dispatch_stage_dir" \
  -L"$pthread_stage_dir" \
  -Wl,-rpath,"$dispatch_stage_dir" \
  -Wl,-rpath,"$pthread_stage_dir" \
  -ldispatch \
  -lthr \
  -lc \
  -o "$dispatch_probe_bin"

echo "==> Staging guest"
env \
  TWQ_VM_IMAGE="$vm_image" \
  TWQ_GUEST_ROOT="$guest_root" \
  TWQ_ZIG_HOTPATH_BENCH_BIN="$zig_bench_bin" \
  TWQ_ZIG_HOTPATH_BENCH_PLAN="$zig_plan" \
  TWQ_WORKQUEUE_WAKE_BENCH_BIN="$workqueue_wake_bench_bin" \
  TWQ_WORKQUEUE_WAKE_BENCH_PLAN="$wake_plan" \
  TWQ_DISPATCH_PROBE_FILTER="__none__" \
  TWQ_SWIFT_PROBE_PROFILE="validation" \
  TWQ_SWIFT_PROBE_FILTER="__none__" \
  sh "${repo_root}/scripts/bhyve/stage-guest.sh"

echo "==> Running guest M13 low-level suite"
run_rc=0
probe_completed=0
env \
  TWQ_VM_IMAGE="$vm_image" \
  TWQ_SERIAL_LOG="$serial_log" \
  TWQ_VM_NAME="$vm_name" \
  TWQ_VM_VCPUS="$vm_vcpus" \
  TWQ_VM_MEMORY="$vm_memory" \
  sh "${repo_root}/scripts/bhyve/run-guest.sh" &
run_pid=$!

if wait_for_serial_marker "$serial_log" "=== twq probe end ===" 300; then
  probe_completed=1
  sleep 5
  if kill -0 "$run_pid" >/dev/null 2>&1; then
    doas bhyvectl --destroy --vm="$vm_name" >/dev/null 2>&1 || true
  fi
fi

wait "$run_pid" || run_rc=$?

case "$run_rc" in
  0|1|2)
    ;;
  4)
    if [ "$probe_completed" -ne 1 ]; then
      echo "Guest run exited with status 4 before the probe completion marker" >&2
      exit "$run_rc"
    fi
    ;;
  *)
    echo "Guest run failed with unexpected status ${run_rc}" >&2
    exit "$run_rc"
    ;;
esac

echo "==> Extracting combined M13 low-level benchmark artifact"
python3 "${repo_root}/scripts/benchmarks/extract-m13-lowlevel-bench.py" \
  --serial-log "$serial_log" \
  --out "$benchmark_json" \
  --label "$benchmark_label"

echo "Suite directory: $suite_dir"
echo "Serial log: $serial_log"
echo "Benchmark JSON: $benchmark_json"
