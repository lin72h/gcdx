#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-tbbx-n0-gcd-only-baseline.sh [--help]

Environment:
  TWQ_M15_TBBX_N0_GCD_OUT_DIR          Output directory
  TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON   Existing bundle artifact to reuse
  TWQ_M15_TBBX_N0_GCD_SERIAL_LOG       Serial log path when generating
  TWQ_M15_TBBX_N0_GCD_SUMMARY_MD       N0 summary output path
  TWQ_M15_TBBX_N0_GCD_INTERVAL_MS      Bundle sampling interval
  TWQ_M15_TBBX_N0_GCD_PRESSURE_MS      dispatch.pressure capture duration
  TWQ_M15_TBBX_N0_GCD_SUSTAINED_MS     dispatch.sustained capture duration

This lane is the GCD-only A.0 baseline for future mixed GCD + oneTBB
experiments. It intentionally reuses the existing pressure-provider bundle
smoke lane and does not introduce a new provider ABI.
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

out_dir=${TWQ_M15_TBBX_N0_GCD_OUT_DIR:-${artifacts_root}/benchmarks/m15-tbbx-n0-gcd-only-${timestamp}}
bundle_out_dir=${out_dir}/bundle
summary_md=${TWQ_M15_TBBX_N0_GCD_SUMMARY_MD:-${out_dir}/summary.md}
boundary_doc=${repo_root}/m15-tbbx-n0-gcd-only-baseline.md
bundle_summary=${bundle_out_dir}/summary.md
bundle_candidate=${bundle_out_dir}/m15-pressure-provider-bundle-candidate.json
bundle_comparison=${bundle_out_dir}/comparison.json
bundle_serial=${TWQ_M15_TBBX_N0_GCD_SERIAL_LOG:-${bundle_out_dir}/m15-tbbx-n0-gcd-only.serial.log}
interval_ms=${TWQ_M15_TBBX_N0_GCD_INTERVAL_MS:-50}
pressure_ms=${TWQ_M15_TBBX_N0_GCD_PRESSURE_MS:-2500}
sustained_ms=${TWQ_M15_TBBX_N0_GCD_SUSTAINED_MS:-12000}

mkdir -p "$out_dir" "$bundle_out_dir" "$(dirname "$summary_md")"

child_env="
TWQ_M15_BUNDLE_OUT_DIR=$bundle_out_dir
TWQ_M15_BUNDLE_LABEL=m15-tbbx-n0-gcd-only-baseline
TWQ_M15_BUNDLE_CAPTURE_MODES=pressure,sustained
TWQ_M15_BUNDLE_INTERVAL_MS=$interval_ms
TWQ_M15_BUNDLE_PRESSURE_MS=$pressure_ms
TWQ_M15_BUNDLE_SUSTAINED_MS=$sustained_ms
TWQ_M15_BUNDLE_SERIAL_LOG=$bundle_serial
"

if [ -n "${TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON:-}" ]; then
  if [ ! -f "$TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON" ]; then
    echo "N0 GCD candidate not found: $TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON" >&2
    exit 66
  fi
  env $child_env \
    TWQ_M15_BUNDLE_CANDIDATE_JSON="$TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON" \
    sh "${repo_root}/scripts/benchmarks/run-m15-pressure-provider-bundle-smoke.sh"
else
  env $child_env \
    sh "${repo_root}/scripts/benchmarks/run-m15-pressure-provider-bundle-smoke.sh"
fi

if [ -n "${TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON:-}" ]; then
  n0_candidate=$TWQ_M15_TBBX_N0_GCD_CANDIDATE_JSON
else
  n0_candidate=$bundle_candidate
fi

verdict=$(python3 - <<'PY' "$bundle_comparison"
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("verdict", "fail"))
PY
)

{
  printf '# M15 TBBX N0 GCD-Only Baseline\n\n'
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Bundle candidate: `%s`\n' "$n0_candidate"
  printf -- '- Bundle comparison: `%s`\n' "$bundle_comparison"
  printf -- '- Bundle summary: `%s`\n' "$bundle_summary"
  printf -- '- Serial log: `%s`\n' "$bundle_serial"
  printf -- '- Capture modes: `pressure,sustained`\n'
  printf -- '- Interval ms: `%s`\n' "$interval_ms"
  printf -- '- Pressure duration ms: `%s`\n' "$pressure_ms"
  printf -- '- Sustained duration ms: `%s`\n' "$sustained_ms"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Scope\n\n'
  printf 'This is condition `A.0`: GCD/libdispatch only, no oneTBB, no TCM, no reserve bridge.\n\n'
  printf 'It establishes the TWQ pressure shape that the future mixed-runtime `N3` lane must not misread as oneTBB interaction.\n'
} >"$summary_md"

echo "Summary: $summary_md"
echo "Bundle candidate: $n0_candidate"
echo "Bundle comparison: $bundle_comparison"
echo "verdict=$verdict"

if [ "$verdict" = "ok" ]; then
  exit 0
fi

exit 1
