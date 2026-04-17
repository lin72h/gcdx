#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-zig-hotpath-bench.sh [--help]

Environment:
  TWQ_VM_IMAGE                Raw guest disk image
  TWQ_GUEST_ROOT              Guest root mount point
  TWQ_VM_NAME                 bhyve guest name
  TWQ_VM_VCPUS                Guest vCPU count
  TWQ_VM_MEMORY               Guest memory size
  TWQ_ARTIFACTS_ROOT          Host artifacts root
  TWQ_ZIG_BIN                 Zig compiler
  TWQ_SERIAL_LOG              Output serial log path
  TWQ_BENCHMARK_JSON          Output parsed benchmark JSON path
  TWQ_BENCHMARK_LABEL         Label stored in extracted JSON
  TWQ_ZIG_BENCH_MODE          Benchmark mode: should-narrow, reqthreads, reqthreads-overcommit,
                              thread-enter, thread-return, thread-transfer
  TWQ_ZIG_BENCH_SAMPLES       Sample count
  TWQ_ZIG_BENCH_WARMUP        Warmup count
  TWQ_ZIG_BENCH_REQUEST_COUNT Request count for reqthreads modes
  TWQ_ZIG_BENCH_REQUESTED_FEATURES Requested features for INIT
  TWQ_ZIG_BENCH_SETTLE_MS     Settle delay after warmup and sample phase
  TWQ_ZIG_HOTPATH_BENCH_PLAN  Optional host plan file with one benchmark arg line per run
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

bench_mode=${TWQ_ZIG_BENCH_MODE:-should-narrow}
bench_samples=${TWQ_ZIG_BENCH_SAMPLES:-2048}
bench_warmup=${TWQ_ZIG_BENCH_WARMUP:-256}
bench_request_count=${TWQ_ZIG_BENCH_REQUEST_COUNT:-1}
bench_requested_features=${TWQ_ZIG_BENCH_REQUESTED_FEATURES:-0}
bench_settle_ms=${TWQ_ZIG_BENCH_SETTLE_MS:-50}
bench_plan=${TWQ_ZIG_HOTPATH_BENCH_PLAN:-}

if [ -n "$bench_plan" ]; then
  serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/zig-hotpath-suite-${timestamp}.serial.log}
  benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/zig-hotpath-suite-${timestamp}.json}
  benchmark_label=${TWQ_BENCHMARK_LABEL:-zig-hotpath-suite}
else
  serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/zig-hotpath-${bench_mode}-${timestamp}.serial.log}
  benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/zig-hotpath-${bench_mode}-${timestamp}.json}
  benchmark_label=${TWQ_BENCHMARK_LABEL:-zig-hotpath-${bench_mode}}
fi

vm_image=${TWQ_VM_IMAGE:-}
guest_root=${TWQ_GUEST_ROOT:-}
vm_name=${TWQ_VM_NAME:-twq-dev}
vm_vcpus=${TWQ_VM_VCPUS:-4}
vm_memory=${TWQ_VM_MEMORY:-8G}

if [ -z "$vm_image" ] || [ -z "$guest_root" ]; then
  echo "TWQ_VM_IMAGE and TWQ_GUEST_ROOT are required" >&2
  exit 64
fi
if [ -n "$bench_plan" ] && [ ! -r "$bench_plan" ]; then
  echo "TWQ_ZIG_HOTPATH_BENCH_PLAN is not readable: $bench_plan" >&2
  exit 66
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

zig_prefix=${TWQ_ZIG_PREFIX:-${artifacts_root}/zig/prefix}
zig_cache_dir=${TWQ_ZIG_CACHE_DIR:-${artifacts_root}/zig/cache}
zig_global_cache_dir=${TWQ_ZIG_GLOBAL_CACHE_DIR:-${artifacts_root}/zig/global-cache}
pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${artifacts_root}/libthr-stage}
pthread_headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${artifacts_root}/pthread-headers}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${artifacts_root}/libdispatch-stage}
dispatch_build_dir=${TWQ_LIBDISPATCH_BUILD_DIR:-${artifacts_root}/libdispatch-build}
dispatch_probe_bin=${TWQ_DISPATCH_PROBE_BIN:-${zig_prefix}/bin/twq-dispatch-probe}
workqueue_probe_bin=${TWQ_WORKQUEUE_PROBE_BIN:-${zig_prefix}/bin/twq-workqueue-probe}
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

mkdir -p "$(dirname "$serial_log")" "$(dirname "$benchmark_json")" \
  "$zig_prefix/bin" "$zig_cache_dir" "$zig_global_cache_dir"

if [ -n "$bench_plan" ]; then
  bench_args=
else
  bench_args="--mode ${bench_mode} --samples ${bench_samples} --warmup ${bench_warmup} --request-count ${bench_request_count} --requested-features ${bench_requested_features} --settle-ms ${bench_settle_ms}"
fi

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
  TWQ_ZIG_HOTPATH_BENCH_ARGS="$bench_args" \
  TWQ_ZIG_HOTPATH_BENCH_PLAN="$bench_plan" \
  TWQ_DISPATCH_PROBE_FILTER="__none__" \
  TWQ_SWIFT_PROBE_PROFILE="validation" \
  TWQ_SWIFT_PROBE_FILTER="__none__" \
  sh "${repo_root}/scripts/bhyve/stage-guest.sh"

echo "==> Running guest hot-path benchmark"
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

echo "==> Extracting structured hot-path benchmark"
extract_args=
if [ -n "$bench_plan" ]; then
  extract_args="--all"
fi
python3 "${repo_root}/scripts/benchmarks/extract-zig-hotpath-bench.py" \
  --serial-log "$serial_log" \
  --out "$benchmark_json" \
  --label "$benchmark_label" \
  ${extract_args}

echo "Serial log: $serial_log"
echo "Benchmark JSON: $benchmark_json"
