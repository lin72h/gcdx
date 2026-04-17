#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-baseline.sh [--help]

Environment:
  TWQ_VM_IMAGE            Raw guest disk image
  TWQ_GUEST_ROOT          Guest root mount point
  TWQ_VM_NAME             bhyve guest name
  TWQ_VM_VCPUS            Guest vCPU count
  TWQ_VM_MEMORY           Guest memory size
  TWQ_ARTIFACTS_ROOT      Host artifacts root
  TWQ_ZIG_BIN             Zig binary used for host probe builds
  TWQ_SERIAL_LOG          Output serial log path
  TWQ_BENCHMARK_JSON      Output parsed benchmark JSON path
  TWQ_BENCHMARK_LABEL     Baseline label stored in JSON output
  TWQ_M13_DISPATCH_FILTER Comma-separated dispatch probe filter
  TWQ_M13_SWIFT_FILTER    Comma-separated Swift probe filter
  TWQ_M13_SWIFT_PROFILE   Swift profile for guest run (default: full)
  TWQ_DTRACE_MODE         Optional DTrace mode: push-poke-drain, push-vtable, root-summary
  TWQ_DTRACE_TARGET       Optional DTrace target: swift-repeat or c-repeat
  TWQ_DTRACE_TIMEOUT      Optional DTrace run timeout in seconds
  TWQ_DTRACE_ROUNDS       Optional repeat rounds for DTrace target
  TWQ_DTRACE_TASKS        Optional repeat tasks for DTrace target
  TWQ_DTRACE_DELAY_MS     Optional repeat delay for DTrace target
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

serial_log=${TWQ_SERIAL_LOG:-${artifacts_root}/benchmarks/m13-baseline-${timestamp}.serial.log}
benchmark_json=${TWQ_BENCHMARK_JSON:-${artifacts_root}/benchmarks/m13-baseline-${timestamp}.json}
benchmark_label=${TWQ_BENCHMARK_LABEL:-m13-initial}

dispatch_filter=${TWQ_M13_DISPATCH_FILTER:-basic,pressure,burst-reuse,timeout-gap,sustained,main-executor-resume-repeat}
swift_filter=${TWQ_M13_SWIFT_FILTER:-dispatch-control,mainqueue-resume,dispatchmain-taskhandles-after-repeat}
swift_profile=${TWQ_M13_SWIFT_PROFILE:-full}
dtrace_mode=${TWQ_DTRACE_MODE:-}
dtrace_target=${TWQ_DTRACE_TARGET:-swift-repeat}
dtrace_timeout=${TWQ_DTRACE_TIMEOUT:-120}
dtrace_rounds=${TWQ_DTRACE_ROUNDS:-64}
dtrace_tasks=${TWQ_DTRACE_TASKS:-8}
dtrace_delay_ms=${TWQ_DTRACE_DELAY_MS:-20}

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

zig_prefix=${TWQ_ZIG_PREFIX:-${artifacts_root}/zig/prefix}
zig_cache_dir=${TWQ_ZIG_CACHE_DIR:-${artifacts_root}/zig/cache}
zig_global_cache_dir=${TWQ_ZIG_GLOBAL_CACHE_DIR:-${artifacts_root}/zig/global-cache}
pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${artifacts_root}/libthr-stage}
pthread_headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${artifacts_root}/pthread-headers}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${artifacts_root}/libdispatch-stage}
dispatch_build_dir=${TWQ_LIBDISPATCH_BUILD_DIR:-${artifacts_root}/libdispatch-build}
dispatch_probe_bin=${TWQ_DISPATCH_PROBE_BIN:-${zig_prefix}/bin/twq-dispatch-probe}
workqueue_probe_bin=${TWQ_WORKQUEUE_PROBE_BIN:-${zig_prefix}/bin/twq-workqueue-probe}
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

echo "==> Refreshing libthr stage"
sh "${repo_root}/scripts/libthr/prepare-stage.sh"

echo "==> Refreshing pthread headers"
sh "${repo_root}/scripts/libthr/prepare-headers.sh"

echo "==> Refreshing libdispatch stage"
sh "${repo_root}/scripts/libdispatch/prepare-stage.sh"

echo "==> Refreshing Swift stage"
sh "${repo_root}/scripts/swift/prepare-stage.sh"

echo "==> Building raw Zig probe"
(cd "${repo_root}/zig" && "$zig_bin" build \
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
  -rdynamic \
  -ldispatch \
  -lthr \
  -lexecinfo \
  -lc \
  -o "$dispatch_probe_bin"

echo "==> Staging guest"
env \
  TWQ_VM_IMAGE="$vm_image" \
  TWQ_GUEST_ROOT="$guest_root" \
  TWQ_DISPATCH_PROBE_FILTER="$dispatch_filter" \
  TWQ_SWIFT_PROBE_PROFILE="$swift_profile" \
  TWQ_SWIFT_PROBE_FILTER="$swift_filter" \
  TWQ_DTRACE_MODE="$dtrace_mode" \
  TWQ_DTRACE_TARGET="$dtrace_target" \
  TWQ_DTRACE_TIMEOUT="$dtrace_timeout" \
  TWQ_DTRACE_ROUNDS="$dtrace_rounds" \
  TWQ_DTRACE_TASKS="$dtrace_tasks" \
  TWQ_DTRACE_DELAY_MS="$dtrace_delay_ms" \
  sh "${repo_root}/scripts/bhyve/stage-guest.sh"

echo "==> Running guest benchmark lane"
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

if [ -n "$dtrace_mode" ]; then
  echo "DTrace serial log: $serial_log"
  exit 0
fi

echo "==> Extracting structured benchmark baseline"
python3 "${repo_root}/scripts/benchmarks/extract-m13-baseline.py" \
  --serial-log "$serial_log" \
  --out "$benchmark_json" \
  --label "$benchmark_label" \
  --dispatch-filter "$dispatch_filter" \
  --swift-profile "$swift_profile" \
  --swift-filter "$swift_filter"

echo "==> Benchmark summary"
python3 "${repo_root}/scripts/benchmarks/summarize-m13-baseline.py" "$benchmark_json"

echo "Serial log: $serial_log"
echo "Benchmark JSON: $benchmark_json"
