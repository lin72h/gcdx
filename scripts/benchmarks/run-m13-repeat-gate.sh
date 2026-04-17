#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-repeat-gate.sh [--help]

Environment:
  TWQ_M13_REPEAT_BASELINE        Checked-in repeat-lane baseline JSON.
  TWQ_M13_REPEAT_CANDIDATE_JSON  Existing candidate JSON to compare directly.
                                 If unset, the script generates one focused
                                 repeat-lane run through run-m13-baseline.sh.
  TWQ_M13_REPEAT_OUT_DIR         Output directory for generated artifacts.
  TWQ_M13_REPEAT_COMPARISON_JSON Structured comparison JSON output path.
  TWQ_M13_REPEAT_COMPARISON_LOG  Raw comparator log path.
  TWQ_M13_REPEAT_SUMMARY_MD      Markdown summary output path.
  TWQ_M13_REPEAT_SERIAL_LOG      Serial log path when generating the candidate.
  TWQ_M13_REPEAT_STEADY_START    First steady-state round (inclusive).
  TWQ_M13_REPEAT_STEADY_END      Last steady-state round (inclusive).
  TWQ_M13_REPEAT_SWIFT_PROFILE   Swift guest profile for the focused run.

Inherited when generating a candidate:
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

out_dir=${TWQ_M13_REPEAT_OUT_DIR:-${artifacts_root}/benchmarks/m13-repeat-gate-${timestamp}}
baseline=${TWQ_M13_REPEAT_BASELINE:-${repo_root}/benchmarks/baselines/m14-freebsd-round-snapshots-20260416.json}
candidate=${TWQ_M13_REPEAT_CANDIDATE_JSON:-${out_dir}/m13-repeat-candidate.json}
comparison_json=${TWQ_M13_REPEAT_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M13_REPEAT_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M13_REPEAT_SUMMARY_MD:-${out_dir}/summary.md}
serial_log=${TWQ_M13_REPEAT_SERIAL_LOG:-${out_dir}/m13-repeat.serial.log}
steady_start=${TWQ_M13_REPEAT_STEADY_START:-8}
steady_end=${TWQ_M13_REPEAT_STEADY_END:-63}
swift_profile=${TWQ_M13_REPEAT_SWIFT_PROFILE:-full}

mkdir -p "$out_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$baseline" ]; then
  echo "Repeat baseline not found: $baseline" >&2
  exit 66
fi

generated_candidate=0
if [ -n "${TWQ_M13_REPEAT_CANDIDATE_JSON:-}" ]; then
  if [ ! -f "$candidate" ]; then
    echo "Repeat candidate not found: $candidate" >&2
    exit 66
  fi
else
  generated_candidate=1
  env \
    TWQ_LIBDISPATCH_COUNTERS=1 \
    TWQ_SERIAL_LOG="$serial_log" \
    TWQ_BENCHMARK_JSON="$candidate" \
    TWQ_BENCHMARK_LABEL="m13-repeat-candidate" \
    TWQ_M13_DISPATCH_FILTER="main-executor-resume-repeat" \
    TWQ_M13_SWIFT_FILTER="dispatchmain-taskhandles-after-repeat" \
    TWQ_M13_SWIFT_PROFILE="$swift_profile" \
    sh "${repo_root}/scripts/benchmarks/run-m13-baseline.sh"
fi

python3 "${repo_root}/scripts/benchmarks/compare-m13-repeat-baseline.py" \
  "$baseline" \
  "$candidate" \
  --steady-start "$steady_start" \
  --steady-end "$steady_end" \
  --json-out "$comparison_json" | tee "$comparison_log"

verdict=$(python3 - <<'PY' "$comparison_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
    print('ok' if data['ok'] else 'fail')
PY
)

{
  printf '# M13 Repeat Gate\n\n'
  printf -- '- Baseline: `%s`\n' "$baseline"
  printf -- '- Candidate: `%s`\n' "$candidate"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated candidate this run: `%s`\n' "$generated_candidate"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "Baseline: $baseline"
echo "Candidate: $candidate"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"
