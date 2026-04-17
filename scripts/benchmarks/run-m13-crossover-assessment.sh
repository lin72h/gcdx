#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-crossover-assessment.sh [--help]

Environment:
  TWQ_M13_CROSSOVER_BASELINE        Checked-in full-matrix crossover baseline JSON.
  TWQ_M13_CROSSOVER_CANDIDATE_JSON  Existing candidate JSON to compare directly.
                                    If unset, the script generates one full
                                    matrix run through run-m13-baseline.sh.
  TWQ_M13_CROSSOVER_OUT_DIR         Output directory for generated artifacts.
  TWQ_M13_CROSSOVER_COMPARISON_JSON Structured comparison JSON output path.
  TWQ_M13_CROSSOVER_COMPARISON_LOG  Raw comparator log path.
  TWQ_M13_CROSSOVER_SUMMARY_MD      Markdown summary output path.
  TWQ_M13_CROSSOVER_SERIAL_LOG      Serial log path when generating candidate.
  TWQ_M13_CROSSOVER_BASELINE_LOG    Human-readable candidate summary log path.
  TWQ_M13_CROSSOVER_STEADY_START    First steady-state round (inclusive).
  TWQ_M13_CROSSOVER_STEADY_END      Last steady-state round (inclusive).

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

out_dir=${TWQ_M13_CROSSOVER_OUT_DIR:-${artifacts_root}/benchmarks/m13-crossover-${timestamp}}
baseline=${TWQ_M13_CROSSOVER_BASELINE:-${repo_root}/benchmarks/baselines/m13-crossover-full-20260417.json}
candidate=${TWQ_M13_CROSSOVER_CANDIDATE_JSON:-${out_dir}/m13-crossover-candidate.json}
comparison_json=${TWQ_M13_CROSSOVER_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M13_CROSSOVER_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M13_CROSSOVER_SUMMARY_MD:-${out_dir}/summary.md}
serial_log=${TWQ_M13_CROSSOVER_SERIAL_LOG:-${out_dir}/m13-crossover.serial.log}
baseline_log=${TWQ_M13_CROSSOVER_BASELINE_LOG:-${out_dir}/candidate-summary.log}
steady_start=${TWQ_M13_CROSSOVER_STEADY_START:-8}
steady_end=${TWQ_M13_CROSSOVER_STEADY_END:-63}
boundary_doc=${repo_root}/m13-5-crossover-boundary.md

mkdir -p "$out_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$baseline" ]; then
  echo "M13.5 crossover baseline not found: $baseline" >&2
  exit 66
fi

generated_candidate=0
if [ -n "${TWQ_M13_CROSSOVER_CANDIDATE_JSON:-}" ]; then
  if [ ! -f "$candidate" ]; then
    echo "M13.5 crossover candidate not found: $candidate" >&2
    exit 66
  fi
else
  generated_candidate=1
  env \
    TWQ_SERIAL_LOG="$serial_log" \
    TWQ_BENCHMARK_JSON="$candidate" \
    TWQ_BENCHMARK_LABEL="m13-crossover-candidate" \
    sh "${repo_root}/scripts/benchmarks/run-m13-baseline.sh"
fi

python3 "${repo_root}/scripts/benchmarks/summarize-m13-baseline.py" \
  "$candidate" \
  --steady-start "$steady_start" \
  --steady-end "$steady_end" | tee "$baseline_log"

python3 "${repo_root}/scripts/benchmarks/compare-m13-crossover-baseline.py" \
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
  printf '# M13.5 Crossover Assessment\n\n'
  printf -- '- Baseline: `%s`\n' "$baseline"
  printf -- '- Candidate: `%s`\n' "$candidate"
  printf -- '- Candidate summary log: `%s`\n' "$baseline_log"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated candidate this run: `%s`\n' "$generated_candidate"
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Candidate Summary\n\n```text\n'
  cat "$baseline_log"
  printf '```\n\n'
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "Baseline: $baseline"
echo "Candidate: $candidate"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"
