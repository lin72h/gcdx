#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m14-comparison.sh [--help]

Environment:
  TWQ_M14_FREEBSD_JSON       Existing FreeBSD schema-3 repeat baseline JSON.
                             If unset, the script generates one by running the
                             focused repeat lane through run-m13-baseline.sh.
  TWQ_M14_MACOS_REPORT       macOS normalized M14 report JSON.
  TWQ_M14_OUT_DIR            Output directory for generated artifacts.
  TWQ_M14_COMPARISON_JSON    Structured comparison JSON output path.
  TWQ_M14_COMPARISON_LOG     Raw text comparator log path.
  TWQ_M14_SUMMARY_MD         Markdown summary output path.
  TWQ_M14_SERIAL_LOG         Serial log path when generating the FreeBSD run.
  TWQ_M14_SWIFT_PROFILE      Swift guest profile used for the focused run.
  TWQ_M14_STEADY_START       First steady-state round (inclusive).
  TWQ_M14_STEADY_END         Last steady-state round (inclusive).
  TWQ_M14_STOP_RATIO         Stop threshold for the primary seam metrics.
  TWQ_M14_TUNE_RATIO         Tune threshold for the primary seam metrics.

Inherited when generating the FreeBSD run:
  TWQ_VM_IMAGE
  TWQ_GUEST_ROOT
  TWQ_VM_NAME
  TWQ_VM_VCPUS
  TWQ_VM_MEMORY
  TWQ_ARTIFACTS_ROOT
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

out_dir=${TWQ_M14_OUT_DIR:-${artifacts_root}/benchmarks/m14-comparison-${timestamp}}
freebsd_json=${TWQ_M14_FREEBSD_JSON:-${out_dir}/m14-freebsd-repeat.json}
macos_report=${TWQ_M14_MACOS_REPORT:-${repo_root}/benchmarks/baselines/m14-macos-stock-introspection-20260416.json}
comparison_json=${TWQ_M14_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M14_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M14_SUMMARY_MD:-${out_dir}/summary.md}
serial_log=${TWQ_M14_SERIAL_LOG:-${out_dir}/m14-freebsd-repeat.serial.log}
swift_profile=${TWQ_M14_SWIFT_PROFILE:-full}
steady_start=${TWQ_M14_STEADY_START:-8}
steady_end=${TWQ_M14_STEADY_END:-63}
stop_ratio=${TWQ_M14_STOP_RATIO:-1.5}
tune_ratio=${TWQ_M14_TUNE_RATIO:-2.0}

mkdir -p "$out_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$macos_report" ]; then
  echo "macOS report not found: $macos_report" >&2
  exit 66
fi

generated_freebsd=0
if [ -n "${TWQ_M14_FREEBSD_JSON:-}" ]; then
  if [ ! -f "$freebsd_json" ]; then
    echo "FreeBSD baseline not found: $freebsd_json" >&2
    exit 66
  fi
else
  generated_freebsd=1
  env \
    TWQ_LIBDISPATCH_COUNTERS=1 \
    TWQ_SERIAL_LOG="$serial_log" \
    TWQ_BENCHMARK_JSON="$freebsd_json" \
    TWQ_BENCHMARK_LABEL="m14-freebsd-repeat" \
    TWQ_M13_DISPATCH_FILTER="main-executor-resume-repeat" \
    TWQ_M13_SWIFT_FILTER="dispatchmain-taskhandles-after-repeat" \
    TWQ_M13_SWIFT_PROFILE="$swift_profile" \
    sh "${repo_root}/scripts/benchmarks/run-m13-baseline.sh"
fi

python3 "${repo_root}/scripts/benchmarks/compare-m14-steady-state.py" \
  "$freebsd_json" \
  "$macos_report" \
  --steady-start "$steady_start" \
  --steady-end "$steady_end" \
  --stop-ratio "$stop_ratio" \
  --tune-ratio "$tune_ratio" \
  --json-out "$comparison_json" | tee "$comparison_log"

verdict=$(python3 - <<'PY' "$comparison_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    print(json.load(handle)["decision"]["verdict"])
PY
)

{
  printf '# M14 Steady-State Comparison\n\n'
  printf -- '- FreeBSD baseline: `%s`\n' "$freebsd_json"
  printf -- '- macOS report: `%s`\n' "$macos_report"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated FreeBSD baseline this run: `%s`\n' "$generated_freebsd"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "FreeBSD baseline: $freebsd_json"
echo "macOS report: $macos_report"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"
