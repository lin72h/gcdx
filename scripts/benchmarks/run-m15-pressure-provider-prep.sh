#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-pressure-provider-prep.sh [--help]

Derives the current pressure-only provider view from a crossover artifact and
compares it against the checked-in baseline.

Environment:
  TWQ_M15_PRESSURE_BASELINE            Checked-in provider baseline JSON
  TWQ_M15_PRESSURE_SOURCE_ARTIFACT     Existing crossover source artifact
  TWQ_M15_PRESSURE_CANDIDATE_JSON      Output derived provider JSON path
  TWQ_M15_PRESSURE_OUT_DIR             Output directory for generated artifacts
  TWQ_M15_PRESSURE_COMPARISON_JSON     Structured comparison JSON output path
  TWQ_M15_PRESSURE_COMPARISON_LOG      Raw comparator log path
  TWQ_M15_PRESSURE_SUMMARY_MD          Markdown summary output path

Inherited when generating the crossover source artifact:
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

out_dir=${TWQ_M15_PRESSURE_OUT_DIR:-${artifacts_root}/benchmarks/m15-pressure-provider-${timestamp}}
baseline=${TWQ_M15_PRESSURE_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-20260417.json}
source_artifact=${TWQ_M15_PRESSURE_SOURCE_ARTIFACT:-}
candidate=${TWQ_M15_PRESSURE_CANDIDATE_JSON:-${out_dir}/m15-pressure-provider-candidate.json}
comparison_json=${TWQ_M15_PRESSURE_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M15_PRESSURE_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M15_PRESSURE_SUMMARY_MD:-${out_dir}/summary.md}
boundary_doc=${repo_root}/m15-pressure-provider-prep.md
crossover_dir=${out_dir}/crossover
crossover_summary=${crossover_dir}/summary.md

mkdir -p "$out_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$baseline" ]; then
  echo "M15 pressure-provider baseline not found: $baseline" >&2
  exit 66
fi

generated_source=0
if [ -n "$source_artifact" ]; then
  if [ ! -f "$source_artifact" ]; then
    echo "M15 pressure-provider source artifact not found: $source_artifact" >&2
    exit 66
  fi
else
  generated_source=1
  mkdir -p "$crossover_dir"
  env \
    TWQ_M13_CROSSOVER_OUT_DIR="$crossover_dir" \
    sh "${repo_root}/scripts/benchmarks/run-m13-crossover-assessment.sh"
  source_artifact=${crossover_dir}/m13-crossover-candidate.json
fi

python3 "${repo_root}/scripts/benchmarks/extract-m15-pressure-provider.py" \
  "$source_artifact" \
  --out "$candidate"

python3 "${repo_root}/scripts/benchmarks/compare-m15-pressure-provider-baseline.py" \
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
  printf '# M15 Pressure Provider Prep\n\n'
  printf -- '- Baseline: `%s`\n' "$baseline"
  printf -- '- Source crossover artifact: `%s`\n' "$source_artifact"
  printf -- '- Candidate provider JSON: `%s`\n' "$candidate"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated source this run: `%s`\n' "$generated_source"
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  if [ "$generated_source" -eq 1 ]; then
    printf -- '- Generated crossover summary: `%s`\n' "$crossover_summary"
  fi
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "Baseline: $baseline"
echo "Source artifact: $source_artifact"
echo "Candidate: $candidate"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"

if [ "$verdict" = "ok" ]; then
  exit 0
fi

exit 1
