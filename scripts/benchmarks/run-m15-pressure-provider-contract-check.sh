#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-pressure-provider-contract-check.sh [--help]

Environment:
  TWQ_M15_PRESSURE_CONTRACT_JSON              Contract JSON to validate against
  TWQ_M15_PRESSURE_CONTRACT_DERIVED_ARTIFACT  Derived provider artifact to validate
  TWQ_M15_PRESSURE_CONTRACT_LIVE_ARTIFACT     Live provider artifact to validate
  TWQ_M15_PRESSURE_CONTRACT_ADAPTER_ARTIFACT  Adapter provider artifact to validate
  TWQ_M15_PRESSURE_CONTRACT_PREVIEW_ARTIFACT  Preview provider artifact to validate
  TWQ_M15_PRESSURE_CONTRACT_OUT_DIR           Output directory
  TWQ_M15_PRESSURE_CONTRACT_DERIVED_JSON      Derived validation JSON output
  TWQ_M15_PRESSURE_CONTRACT_LIVE_JSON         Live validation JSON output
  TWQ_M15_PRESSURE_CONTRACT_ADAPTER_JSON      Adapter validation JSON output
  TWQ_M15_PRESSURE_CONTRACT_PREVIEW_JSON      Preview validation JSON output
  TWQ_M15_PRESSURE_CONTRACT_DERIVED_LOG       Derived validation log output
  TWQ_M15_PRESSURE_CONTRACT_LIVE_LOG          Live validation log output
  TWQ_M15_PRESSURE_CONTRACT_ADAPTER_LOG       Adapter validation log output
  TWQ_M15_PRESSURE_CONTRACT_PREVIEW_LOG       Preview validation log output
  TWQ_M15_PRESSURE_CONTRACT_SUMMARY_MD        Markdown summary output
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

out_dir=${TWQ_M15_PRESSURE_CONTRACT_OUT_DIR:-${artifacts_root}/benchmarks/m15-pressure-provider-contract-${timestamp}}
contract_json=${TWQ_M15_PRESSURE_CONTRACT_JSON:-${repo_root}/benchmarks/contracts/m15-pressure-provider-contract-v1.json}
derived_artifact=${TWQ_M15_PRESSURE_CONTRACT_DERIVED_ARTIFACT:-${repo_root}/benchmarks/baselines/m15-pressure-provider-20260417.json}
live_artifact=${TWQ_M15_PRESSURE_CONTRACT_LIVE_ARTIFACT:-${repo_root}/benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json}
adapter_artifact=${TWQ_M15_PRESSURE_CONTRACT_ADAPTER_ARTIFACT:-${repo_root}/benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json}
preview_artifact=${TWQ_M15_PRESSURE_CONTRACT_PREVIEW_ARTIFACT:-${repo_root}/benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json}
derived_json=${TWQ_M15_PRESSURE_CONTRACT_DERIVED_JSON:-${out_dir}/derived-validation.json}
live_json=${TWQ_M15_PRESSURE_CONTRACT_LIVE_JSON:-${out_dir}/live-validation.json}
adapter_json=${TWQ_M15_PRESSURE_CONTRACT_ADAPTER_JSON:-${out_dir}/adapter-validation.json}
preview_json=${TWQ_M15_PRESSURE_CONTRACT_PREVIEW_JSON:-${out_dir}/preview-validation.json}
derived_log=${TWQ_M15_PRESSURE_CONTRACT_DERIVED_LOG:-${out_dir}/derived-validation.log}
live_log=${TWQ_M15_PRESSURE_CONTRACT_LIVE_LOG:-${out_dir}/live-validation.log}
adapter_log=${TWQ_M15_PRESSURE_CONTRACT_ADAPTER_LOG:-${out_dir}/adapter-validation.log}
preview_log=${TWQ_M15_PRESSURE_CONTRACT_PREVIEW_LOG:-${out_dir}/preview-validation.log}
summary_md=${TWQ_M15_PRESSURE_CONTRACT_SUMMARY_MD:-${out_dir}/summary.md}

mkdir -p "$out_dir" "$(dirname "$derived_json")" "$(dirname "$live_json")" "$(dirname "$adapter_json")" "$(dirname "$preview_json")" "$(dirname "$summary_md")"

for path in "$contract_json" "$derived_artifact" "$live_artifact" "$adapter_artifact" "$preview_artifact"; do
  if [ ! -f "$path" ]; then
    echo "Required artifact not found: $path" >&2
    exit 66
  fi
done

python3 "${repo_root}/scripts/benchmarks/validate-m15-pressure-provider-contract.py" \
  "$contract_json" \
  "$derived_artifact" \
  --kind derived \
  --json-out "$derived_json" | tee "$derived_log"

python3 "${repo_root}/scripts/benchmarks/validate-m15-pressure-provider-contract.py" \
  "$contract_json" \
  "$live_artifact" \
  --kind live \
  --json-out "$live_json" | tee "$live_log"

python3 "${repo_root}/scripts/benchmarks/validate-m15-pressure-provider-contract.py" \
  "$contract_json" \
  "$adapter_artifact" \
  --kind adapter \
  --json-out "$adapter_json" | tee "$adapter_log"

python3 "${repo_root}/scripts/benchmarks/validate-m15-pressure-provider-contract.py" \
  "$contract_json" \
  "$preview_artifact" \
  --kind preview \
  --json-out "$preview_json" | tee "$preview_log"

derived_verdict=$(python3 - <<'PY' "$derived_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    print(json.load(handle).get('verdict', 'fail'))
PY
)

live_verdict=$(python3 - <<'PY' "$live_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    print(json.load(handle).get('verdict', 'fail'))
PY
)

adapter_verdict=$(python3 - <<'PY' "$adapter_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    print(json.load(handle).get('verdict', 'fail'))
PY
)

preview_verdict=$(python3 - <<'PY' "$preview_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    print(json.load(handle).get('verdict', 'fail'))
PY
)

overall=ok
if [ "$derived_verdict" != "ok" ] || [ "$live_verdict" != "ok" ] || [ "$adapter_verdict" != "ok" ] || [ "$preview_verdict" != "ok" ]; then
  overall=fail
fi

{
  printf '# M15 Pressure Provider Contract Check\n\n'
  printf -- '- Contract: `%s`\n' "$contract_json"
  printf -- '- Derived artifact: `%s`\n' "$derived_artifact"
  printf -- '- Live artifact: `%s`\n' "$live_artifact"
  printf -- '- Adapter artifact: `%s`\n' "$adapter_artifact"
  printf -- '- Preview artifact: `%s`\n' "$preview_artifact"
  printf -- '- Derived validation JSON: `%s`\n' "$derived_json"
  printf -- '- Live validation JSON: `%s`\n' "$live_json"
  printf -- '- Adapter validation JSON: `%s`\n' "$adapter_json"
  printf -- '- Preview validation JSON: `%s`\n' "$preview_json"
  printf -- '- Derived verdict: `%s`\n' "$derived_verdict"
  printf -- '- Live verdict: `%s`\n' "$live_verdict"
  printf -- '- Adapter verdict: `%s`\n' "$adapter_verdict"
  printf -- '- Preview verdict: `%s`\n' "$preview_verdict"
  printf -- '- Overall verdict: `%s`\n\n' "$overall"
  printf '## Derived Validation\n\n```text\n'
  cat "$derived_log"
  printf '```\n\n'
  printf '## Live Validation\n\n```text\n'
  cat "$live_log"
  printf '```\n\n'
  printf '## Adapter Validation\n\n```text\n'
  cat "$adapter_log"
  printf '```\n\n'
  printf '## Preview Validation\n\n```text\n'
  cat "$preview_log"
  printf '```\n'
} >"$summary_md"

echo "Contract: $contract_json"
echo "Derived artifact: $derived_artifact"
echo "Live artifact: $live_artifact"
echo "Adapter artifact: $adapter_artifact"
echo "Preview artifact: $preview_artifact"
echo "Summary: $summary_md"

if [ "$overall" = "ok" ]; then
  exit 0
fi

exit 1
