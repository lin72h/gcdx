#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-pressure-provider-bundle-replay.sh [--help]

Environment:
  TWQ_M15_BUNDLE_REPLAY_BASELINE           Checked-in bundle baseline JSON
  TWQ_M15_BUNDLE_REPLAY_SESSION_ARTIFACT   Session artifact used as replay source
  TWQ_M15_BUNDLE_REPLAY_CANDIDATE_JSON     Existing candidate JSON to compare directly
  TWQ_M15_BUNDLE_REPLAY_OUT_DIR            Output directory for generated artifacts
  TWQ_M15_BUNDLE_REPLAY_COMPARISON_JSON    Structured comparison JSON output path
  TWQ_M15_BUNDLE_REPLAY_COMPARISON_LOG     Raw comparator log path
  TWQ_M15_BUNDLE_REPLAY_SUMMARY_MD         Markdown summary output path
  TWQ_M15_BUNDLE_REPLAY_LABEL              Label stored in generated candidate metadata
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

out_dir=${TWQ_M15_BUNDLE_REPLAY_OUT_DIR:-${artifacts_root}/benchmarks/m15-pressure-provider-bundle-replay-${timestamp}}
baseline=${TWQ_M15_BUNDLE_REPLAY_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json}
session_artifact=${TWQ_M15_BUNDLE_REPLAY_SESSION_ARTIFACT:-${repo_root}/benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json}
candidate=${TWQ_M15_BUNDLE_REPLAY_CANDIDATE_JSON:-${out_dir}/m15-pressure-provider-bundle-replay-candidate.json}
comparison_json=${TWQ_M15_BUNDLE_REPLAY_COMPARISON_JSON:-${out_dir}/comparison.json}
comparison_log=${TWQ_M15_BUNDLE_REPLAY_COMPARISON_LOG:-${out_dir}/comparison.log}
summary_md=${TWQ_M15_BUNDLE_REPLAY_SUMMARY_MD:-${out_dir}/summary.md}
label=${TWQ_M15_BUNDLE_REPLAY_LABEL:-m15-pressure-provider-bundle-replay}
boundary_doc=${repo_root}/m15-pressure-provider-bundle-replay.md

mkdir -p "$out_dir" "$(dirname "$comparison_json")" "$(dirname "$comparison_log")" "$(dirname "$summary_md")"

if [ ! -f "$baseline" ]; then
  echo "M15 bundle baseline not found: $baseline" >&2
  exit 66
fi

generated_candidate=0
if [ -n "${TWQ_M15_BUNDLE_REPLAY_CANDIDATE_JSON:-}" ]; then
  if [ ! -f "$candidate" ]; then
    echo "M15 bundle replay candidate not found: $candidate" >&2
    exit 66
  fi
else
  generated_candidate=1
  if [ ! -f "$session_artifact" ]; then
    echo "M15 session artifact not found: $session_artifact" >&2
    exit 66
  fi

  python3 "${repo_root}/scripts/benchmarks/extract-m15-pressure-provider-bundle-replay.py" \
    --session-artifact "$session_artifact" \
    --out "$candidate" \
    --label "$label"
fi

python3 "${repo_root}/scripts/benchmarks/compare-m15-pressure-provider-bundle-smoke.py" \
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
  printf '# M15 Pressure Provider Bundle Replay\n\n'
  printf -- '- Baseline: `%s`\n' "$baseline"
  printf -- '- Session artifact: `%s`\n' "$session_artifact"
  printf -- '- Candidate: `%s`\n' "$candidate"
  printf -- '- Comparison JSON: `%s`\n' "$comparison_json"
  printf -- '- Comparator log: `%s`\n' "$comparison_log"
  printf -- '- Generated candidate this run: `%s`\n' "$generated_candidate"
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Comparator Output\n\n```text\n'
  cat "$comparison_log"
  printf '```\n'
} >"$summary_md"

echo "Baseline: $baseline"
echo "Session artifact: $session_artifact"
echo "Candidate: $candidate"
echo "Comparison JSON: $comparison_json"
echo "Summary: $summary_md"

if [ "$verdict" = "ok" ]; then
  exit 0
fi

exit 1
