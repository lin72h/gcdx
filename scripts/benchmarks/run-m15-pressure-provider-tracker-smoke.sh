#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-pressure-provider-tracker-smoke.sh [--help]

Environment:
  TWQ_VM_IMAGE                             Raw guest disk image
  TWQ_GUEST_ROOT                           Guest root mount point
  TWQ_VM_NAME                              bhyve guest name
  TWQ_VM_VCPUS                             Guest vCPU count
  TWQ_VM_MEMORY                            Guest memory size
  TWQ_ARTIFACTS_ROOT                       Host artifacts root
  TWQ_M15_TRACKER_BASELINE                 Checked-in tracker baseline JSON
  TWQ_M15_TRACKER_CANDIDATE_JSON           Existing candidate JSON to compare directly
  TWQ_M15_TRACKER_OUT_DIR                  Output directory for generated artifacts
  TWQ_M15_TRACKER_SERIAL_LOG               Serial log path when generating candidate
  TWQ_M15_TRACKER_COMPARISON_JSON          Structured comparison JSON output path
  TWQ_M15_TRACKER_COMPARISON_LOG           Raw comparator log path
  TWQ_M15_TRACKER_SUMMARY_MD               Markdown summary output path
  TWQ_M15_TRACKER_LABEL                    Label stored in generated candidate metadata
  TWQ_M15_TRACKER_CAPTURE_MODES            Dispatch modes to sample (`pressure,sustained` by default)
  TWQ_M15_TRACKER_INTERVAL_MS              Tracker sampling interval in milliseconds
  TWQ_M15_TRACKER_PRESSURE_MS              Tracker duration for dispatch pressure
  TWQ_M15_TRACKER_SUSTAINED_MS             Tracker duration for dispatch sustained
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
vm_name=${TWQ_VM_NAME:-twq-dev}

vm_image=${TWQ_VM_IMAGE:-${repo_root}/../vm/runs/${vm_name}.img}
guest_root=${TWQ_GUEST_ROOT:-${repo_root}/../vm/runs/${vm_name}.root}
vm_vcpus=${TWQ_VM_VCPUS:-4}
vm_memory=${TWQ_VM_MEMORY:-8G}

out_dir=${TWQ_M15_TRACKER_OUT_DIR:-${artifacts_root}/benchmarks/m15-pressure-provider-tracker-${timestamp}}
baseline=${TWQ_M15_TRACKER_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json}
candidate=${TWQ_M15_TRACKER_CANDIDATE_JSON:-${out_dir}/m15-pressure-provider-tracker-candidate.json}
serial_log=${TWQ_M15_TRACKER_SERIAL_LOG:-${out_dir}/m15-pressure-provider-tracker.serial.log}
comparison_json=${TWQ_M15_TRACKER_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M15_TRACKER_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M15_TRACKER_SUMMARY_MD:-${out_dir}/summary.md}
label=${TWQ_M15_TRACKER_LABEL:-m15-pressure-provider-tracker-smoke}
capture_modes=${TWQ_M15_TRACKER_CAPTURE_MODES:-pressure,sustained}
interval_ms=${TWQ_M15_TRACKER_INTERVAL_MS:-50}
pressure_duration_ms=${TWQ_M15_TRACKER_PRESSURE_MS:-2500}
sustained_duration_ms=${TWQ_M15_TRACKER_SUSTAINED_MS:-12000}

pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${artifacts_root}/libthr-stage}
pthread_headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${artifacts_root}/pthread-headers}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${artifacts_root}/libdispatch-stage}
dispatch_build_dir=${TWQ_LIBDISPATCH_BUILD_DIR:-${artifacts_root}/libdispatch-build}
dispatch_src_dir=${TWQ_LIBDISPATCH_SRC:-${repo_root}/../nx/swift-corelibs-libdispatch}
dispatch_probe_bin=${TWQ_DISPATCH_PROBE_BIN:-${artifacts_root}/zig/prefix/bin/twq-dispatch-probe}
tracker_probe_dir=${artifacts_root}/pressure-provider/bin
tracker_probe_bin=${TWQ_PRESSURE_PROVIDER_TRACKER_PROBE_BIN:-${tracker_probe_dir}/twq-pressure-provider-tracker-probe}
boundary_doc=${repo_root}/m15-pressure-provider-tracker-smoke.md

mkdir -p "$out_dir" "$tracker_probe_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$baseline" ]; then
  echo "M15 tracker baseline not found: $baseline" >&2
  exit 66
fi

generated_candidate=0
if [ -n "${TWQ_M15_TRACKER_CANDIDATE_JSON:-}" ]; then
  if [ ! -f "$candidate" ]; then
    echo "M15 tracker candidate not found: $candidate" >&2
    exit 66
  fi
else
  generated_candidate=1
  if [ ! -f "$vm_image" ]; then
    echo "Guest image not found: $vm_image" >&2
    exit 66
  fi
  mkdir -p "$guest_root"

  echo "==> Refreshing libthr stage"
  sh "${repo_root}/scripts/libthr/prepare-stage.sh"

  echo "==> Refreshing pthread headers"
  sh "${repo_root}/scripts/libthr/prepare-headers.sh"

  echo "==> Refreshing libdispatch stage"
  sh "${repo_root}/scripts/libdispatch/prepare-stage.sh"

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

  echo "==> Building pressure tracker probe"
  cc \
    "${repo_root}/csrc/twq_pressure_provider_preview.c" \
    "${repo_root}/csrc/twq_pressure_provider_adapter.c" \
    "${repo_root}/csrc/twq_pressure_provider_session.c" \
    "${repo_root}/csrc/twq_pressure_provider_tracker.c" \
    "${repo_root}/csrc/twq_pressure_provider_tracker_probe.c" \
    -lc \
    -o "$tracker_probe_bin"

  echo "==> Staging guest"
  env \
    TWQ_VM_IMAGE="$vm_image" \
    TWQ_GUEST_ROOT="$guest_root" \
    TWQ_VM_NAME="$vm_name" \
    TWQ_DISPATCH_PROBE_FILTER="$capture_modes" \
    TWQ_SWIFT_PROBE_FILTER="__none__" \
    TWQ_PRESSURE_PROVIDER_TRACKER_PROBE_BIN="$tracker_probe_bin" \
    TWQ_PRESSURE_PROVIDER_TRACKER_CAPTURE_MODES="$capture_modes" \
    TWQ_PRESSURE_PROVIDER_TRACKER_INTERVAL_MS="$interval_ms" \
    TWQ_PRESSURE_PROVIDER_TRACKER_PRESSURE_DURATION_MS="$pressure_duration_ms" \
    TWQ_PRESSURE_PROVIDER_TRACKER_SUSTAINED_DURATION_MS="$sustained_duration_ms" \
    sh "${repo_root}/scripts/bhyve/stage-guest.sh"

  echo "==> Running guest tracker pressure smoke lane"
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

  elapsed=0
  while [ "$elapsed" -lt 600 ]; do
    if [ -f "$serial_log" ] && grep -Fq "=== twq probe end ===" "$serial_log"; then
      probe_completed=1
      sleep 5
      if kill -0 "$run_pid" >/dev/null 2>&1; then
        doas bhyvectl --destroy --vm="$vm_name" >/dev/null 2>&1 || true
      fi
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

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

  echo "==> Extracting tracker pressure artifact"
  python3 "${repo_root}/scripts/benchmarks/extract-m15-pressure-provider-tracker.py" \
    --serial-log "$serial_log" \
    --out "$candidate" \
    --label "$label"
fi

python3 "${repo_root}/scripts/benchmarks/compare-m15-pressure-provider-tracker-smoke.py" \
  "$baseline" \
  "$candidate" \
  --json-out "$comparison_json" | tee "$comparison_log"

verdict=$(python3 - <<'PY' "$comparison_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
    print(data.get('verdict', 'fail'))
PY
)

{
  printf '# M15 Pressure Provider Tracker Smoke\n\n'
  printf -- '- Baseline: `%s`\n' "$baseline"
  printf -- '- Candidate: `%s`\n' "$candidate"
  printf -- '- Serial log: `%s`\n' "$serial_log"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated candidate this run: `%s`\n' "$generated_candidate"
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Capture modes: `%s`\n' "$capture_modes"
  printf -- '- Interval ms: `%s`\n' "$interval_ms"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "Baseline: $baseline"
echo "Candidate: $candidate"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"

if [ "$verdict" = "ok" ]; then
  exit 0
fi

exit 1
