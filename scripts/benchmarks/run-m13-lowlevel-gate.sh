#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-lowlevel-gate.sh [--help]

Runs the current M13 low-level regression floor in one guest boot and compares
it against the suite-native combined baseline.

Environment:
  TWQ_VM_IMAGE                         Raw guest disk image
  TWQ_GUEST_ROOT                       Guest root mount point
  TWQ_ARTIFACTS_ROOT                   Host artifacts root
  TWQ_M13_LOWLEVEL_GATE_DIR            Optional run directory for all outputs
  TWQ_M13_LOWLEVEL_BASELINE            Optional combined baseline path
  TWQ_M13_LOWLEVEL_CANDIDATE_JSON      Existing combined candidate JSON to compare directly.
                                       If unset, the script generates one fresh
                                       candidate through run-m13-lowlevel-suite.sh.
  TWQ_M13_LOWLEVEL_COMPARISON_JSON     Structured comparison JSON output path
  TWQ_M13_LOWLEVEL_COMPARISON_LOG      Raw comparator log path
  TWQ_M13_LOWLEVEL_SUMMARY_MD          Markdown summary output path
  TWQ_M13_LOWLEVEL_COMPARE_ARGS        Optional extra args for the combined comparator

All suite sizing environment accepted by run-m13-lowlevel-suite.sh is passed
through unchanged.
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
run_dir=${TWQ_M13_LOWLEVEL_GATE_DIR:-${artifacts_root}/benchmarks/m13-lowlevel-gate-${timestamp}}
summary_path=${TWQ_M13_LOWLEVEL_SUMMARY_MD:-${run_dir}/summary.md}
comparison_json=${TWQ_M13_LOWLEVEL_COMPARISON_JSON:-${run_dir}/comparison.json}
comparison_log=${TWQ_M13_LOWLEVEL_COMPARISON_LOG:-${run_dir}/comparison.log}

mkdir -p "$run_dir" "$(dirname "$summary_path")" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")"

serial_log=${run_dir}/m13-lowlevel.serial.log
benchmark_json=${TWQ_M13_LOWLEVEL_CANDIDATE_JSON:-${run_dir}/m13-lowlevel.json}
benchmark_label=m13-lowlevel-gate
baseline=${TWQ_M13_LOWLEVEL_BASELINE:-${repo_root}/benchmarks/baselines/m13-lowlevel-suite-20260416.json}
compare_args=${TWQ_M13_LOWLEVEL_COMPARE_ARGS:-}
generated_candidate=0

if [ ! -r "$baseline" ]; then
  echo "Baseline JSON is not readable: $baseline" >&2
  exit 66
fi

if [ -n "${TWQ_M13_LOWLEVEL_CANDIDATE_JSON:-}" ]; then
  if [ ! -r "$benchmark_json" ]; then
    echo "Candidate JSON is not readable: $benchmark_json" >&2
    exit 66
  fi
else
  generated_candidate=1
  echo "==> Running combined M13 low-level suite"
  env \
    TWQ_M13_LOWLEVEL_SUITE_DIR="$run_dir" \
    TWQ_SERIAL_LOG="$serial_log" \
    TWQ_BENCHMARK_JSON="$benchmark_json" \
    TWQ_BENCHMARK_LABEL="$benchmark_label" \
    sh "${script_dir}/run-m13-lowlevel-suite.sh"
fi

echo "==> Comparing combined M13 low-level suite against baseline"
# Intentional word splitting for optional developer-provided comparator args.
# shellcheck disable=SC2086
python3 "${script_dir}/compare-m13-lowlevel-baseline.py" \
  "$baseline" \
  "$benchmark_json" \
  --json-out "$comparison_json" \
  ${compare_args} | tee "$comparison_log"

verdict=$(python3 - <<'PY' "$comparison_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
    print(data.get('verdict', 'fail'))
PY
)

cat > "$summary_path" <<EOF
# M13 Low-Level Gate

## Inputs

- Combined baseline: ${baseline}
- Combined candidate: ${benchmark_json}

## Outputs

- Comparison JSON: ${comparison_json}
- Comparator log: ${comparison_log}
- Generated candidate this run: ${generated_candidate}
EOF

if [ "$generated_candidate" -eq 1 ]; then
cat >> "$summary_path" <<EOF
- Combined serial log: ${serial_log}
EOF
fi

cat >> "$summary_path" <<EOF

## Status

- Verdict: ${verdict}

## Comparator Output

\`\`\`text
EOF

cat "$comparison_log" >> "$summary_path"

cat >> "$summary_path" <<'EOF'
```
EOF

echo "Run directory: $run_dir"
echo "Summary: $summary_path"
