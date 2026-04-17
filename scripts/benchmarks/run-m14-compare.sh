#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m14-compare.sh [--help] [--out-dir DIR]

Environment:
  TWQ_ARTIFACTS_ROOT             Artifacts root for derived outputs
  TWQ_M14_FREEBSD_SOURCE         FreeBSD input path, or auto for discovery
  TWQ_M14_FREEBSD_SOURCE_KIND    auto|benchmark-json|round-snapshots|serial-log|normalized
  TWQ_M14_MACOS_REPORT           macOS report JSON, or auto for discovery
  TWQ_M14_MACOS_SOURCE_KIND      report|normalized
  TWQ_M14_DISCOVER_ROOTS         Colon-separated roots for artifact discovery
  TWQ_M14_STEADY_STATE_START_ROUND  First steady-state round (default: 8)
  TWQ_M14_WITHIN_RATIO           Strict comparison ratio (default: 1.5)
  TWQ_M14_ABOUT_WITHIN_RATIO     Soft about-1.5x ratio (default: 1.65)
  TWQ_M14_MATERIAL_GAP_RATIO     Gap ratio for tuning decision (default: 2.0)
EOF
}

validate_artifact() {
  source_path=$1
  source_kind=$2
  source_platform=$3
  validation_json=$4
  validation_txt=$5

  validator_status=0
  if ! python3 "${repo_root}/scripts/benchmarks/validate-m14-artifacts.py" \
    "$source_path" \
    --kind "$source_kind" \
    --platform "$source_platform" \
    --steady-state-start-round "$start_round" \
    --json-out "$validation_json" >"$validation_txt"; then
    validator_status=$?
  fi

  comparison_ready=$(python3 - <<'PY' "$validation_json"
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print("1" if payload.get("comparison_ready") else "0")
PY
)
  if [ "$comparison_ready" != "1" ]; then
    echo "Artifact is not comparison-ready: $source_path" >&2
    cat "$validation_txt" >&2
    exit 66
  fi

  return "$validator_status"
}

audit_artifact() {
  source_path=$1
  source_kind=$2
  source_platform=$3
  audit_json=$4
  audit_txt=$5

  python3 "${repo_root}/scripts/benchmarks/audit-m14-artifact-schema.py" \
    "$source_path" \
    --kind "$source_kind" \
    --platform "$source_platform" \
    --json-out "$audit_json" >"$audit_txt"
}

detect_kind() {
  path=$1
  if [ ! -f "$path" ]; then
    echo "missing"
    return 0
  fi
  case "$path" in
    *round-snapshots*.json)
      echo "round-snapshots"
      return 0
      ;;
    *.log)
      echo "serial-log"
      return 0
      ;;
  esac
  if grep -q '"platform"[[:space:]]*:' "$path" 2>/dev/null; then
    echo "normalized"
    return 0
  fi
  echo "benchmark-json"
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/../.." && pwd)
artifacts_root=${TWQ_ARTIFACTS_ROOT:-${repo_root}/../artifacts}
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out_dir=${artifacts_root}/benchmarks/m14-compare-${timestamp}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --out-dir)
      if [ $# -lt 2 ]; then
        echo "missing value for --out-dir" >&2
        exit 64
      fi
      out_dir=$2
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

discover_roots=${TWQ_M14_DISCOVER_ROOTS:-${artifacts_root}:${repo_root}/fixtures/benchmarks}
freebsd_source=${TWQ_M14_FREEBSD_SOURCE:-auto}
macos_source=${TWQ_M14_MACOS_REPORT:-auto}
macos_source_kind=${TWQ_M14_MACOS_SOURCE_KIND:-report}
freebsd_source_kind=${TWQ_M14_FREEBSD_SOURCE_KIND:-auto}

start_round=${TWQ_M14_STEADY_STATE_START_ROUND:-8}
within_ratio=${TWQ_M14_WITHIN_RATIO:-1.5}
about_within_ratio=${TWQ_M14_ABOUT_WITHIN_RATIO:-1.65}
material_gap_ratio=${TWQ_M14_MATERIAL_GAP_RATIO:-2.0}

mkdir -p "$out_dir"

discovery_json=${out_dir}/discovery.json
freebsd_input_validation_json=${out_dir}/freebsd.input-validation.json
freebsd_input_validation_txt=${out_dir}/freebsd.input-validation.txt
freebsd_input_audit_json=${out_dir}/freebsd.input-audit.json
freebsd_input_audit_txt=${out_dir}/freebsd.input-audit.txt
macos_input_validation_json=${out_dir}/macos.input-validation.json
macos_input_validation_txt=${out_dir}/macos.input-validation.txt
macos_input_audit_json=${out_dir}/macos.input-audit.json
macos_input_audit_txt=${out_dir}/macos.input-audit.txt
macos_normalized=${out_dir}/macos.normalized.json
macos_normalized_validation_json=${out_dir}/macos.normalized-validation.json
macos_normalized_validation_txt=${out_dir}/macos.normalized-validation.txt
freebsd_normalized=${out_dir}/freebsd.normalized.json
freebsd_normalized_validation_json=${out_dir}/freebsd.normalized-validation.json
freebsd_normalized_validation_txt=${out_dir}/freebsd.normalized-validation.txt
comparison_json=${out_dir}/comparison.json
summary_txt=${out_dir}/summary.txt
report_txt=${out_dir}/report.txt

discover_args=""
old_ifs=${IFS}
IFS=:
for root in $discover_roots; do
  discover_args="${discover_args} --root ${root}"
done
IFS=${old_ifs}

if [ "$freebsd_source" = "auto" ] || [ "$macos_source" = "auto" ]; then
  # shellcheck disable=SC2086
  python3 "${repo_root}/scripts/benchmarks/discover-m14-artifacts.py" \
    ${discover_args} \
    --json-out "$discovery_json" >/dev/null
fi

if [ "$freebsd_source" = "auto" ] && [ "$macos_source" = "auto" ]; then
  pair_selection=$(python3 - <<'PY' "$discovery_json"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
obj = json.loads(p.read_text(encoding='utf-8'))
best = obj.get('pairs', {}).get('best') or {}
freebsd = best.get('freebsd') or {}
macos = best.get('macos') or {}
print(freebsd.get('path', ''))
print(freebsd.get('kind', ''))
print(macos.get('path', ''))
print(macos.get('kind', ''))
PY
)
  freebsd_pair_source=$(printf '%s\n' "$pair_selection" | sed -n '1p')
  freebsd_pair_kind=$(printf '%s\n' "$pair_selection" | sed -n '2p')
  macos_pair_source=$(printf '%s\n' "$pair_selection" | sed -n '3p')
  macos_pair_kind=$(printf '%s\n' "$pair_selection" | sed -n '4p')
  if [ -n "$freebsd_pair_source" ] && [ -n "$macos_pair_source" ]; then
    freebsd_source=$freebsd_pair_source
    freebsd_source_kind=$freebsd_pair_kind
    macos_source=$macos_pair_source
    macos_source_kind=$macos_pair_kind
  fi
fi

if [ "$freebsd_source" = "auto" ]; then
  freebsd_source=$(python3 - <<'PY' "$discovery_json"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
obj = json.loads(p.read_text(encoding='utf-8'))
best = obj.get('freebsd', {}).get('best') or {}
print(best.get('path', ''))
PY
)
  freebsd_source_kind=$(python3 - <<'PY' "$discovery_json"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
obj = json.loads(p.read_text(encoding='utf-8'))
best = obj.get('freebsd', {}).get('best') or {}
print(best.get('kind', ''))
PY
)
fi

if [ -z "$freebsd_source" ]; then
  echo "Unable to discover a FreeBSD M14 source; set TWQ_M14_FREEBSD_SOURCE" >&2
  exit 66
fi
if [ ! -f "$freebsd_source" ]; then
  echo "FreeBSD source does not exist: $freebsd_source" >&2
  exit 66
fi
if [ "$freebsd_source_kind" = "auto" ]; then
  freebsd_source_kind=$(detect_kind "$freebsd_source")
fi
validate_artifact \
  "$freebsd_source" \
  "$freebsd_source_kind" \
  "freebsd" \
  "$freebsd_input_validation_json" \
  "$freebsd_input_validation_txt"
audit_artifact \
  "$freebsd_source" \
  "$freebsd_source_kind" \
  "freebsd" \
  "$freebsd_input_audit_json" \
  "$freebsd_input_audit_txt"

if [ "$macos_source" = "auto" ]; then
  macos_source=$(python3 - <<'PY' "$discovery_json"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
obj = json.loads(p.read_text(encoding='utf-8'))
best = obj.get('macos', {}).get('best') or {}
print(best.get('path', ''))
PY
)
  macos_source_kind=$(python3 - <<'PY' "$discovery_json"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
obj = json.loads(p.read_text(encoding='utf-8'))
best = obj.get('macos', {}).get('best') or {}
print(best.get('kind', ''))
PY
)
fi
if [ -z "$macos_source" ]; then
  echo "Unable to discover a macOS M14 source; set TWQ_M14_MACOS_REPORT" >&2
  exit 66
fi
if [ ! -f "$macos_source" ]; then
  echo "macOS source does not exist: $macos_source" >&2
  exit 66
fi
validate_artifact \
  "$macos_source" \
  "$macos_source_kind" \
  "macos" \
  "$macos_input_validation_json" \
  "$macos_input_validation_txt"
audit_artifact \
  "$macos_source" \
  "$macos_source_kind" \
  "macos" \
  "$macos_input_audit_json" \
  "$macos_input_audit_txt"

case "$macos_source_kind" in
  report)
    python3 "${repo_root}/scripts/benchmarks/extract-m14-benchmark.py" \
      --macos-report "$macos_source" \
      --steady-state-start-round "$start_round" \
      --label "m14-macos-normalized" \
      --out "$macos_normalized"
    ;;
  normalized)
    cp "$macos_source" "$macos_normalized"
    ;;
  *)
    echo "unsupported TWQ_M14_MACOS_SOURCE_KIND: $macos_source_kind" >&2
    exit 64
    ;;
esac
validate_artifact \
  "$macos_normalized" \
  "normalized" \
  "macos" \
  "$macos_normalized_validation_json" \
  "$macos_normalized_validation_txt"

case "$freebsd_source_kind" in
  benchmark-json)
    python3 "${repo_root}/scripts/benchmarks/extract-m14-benchmark.py" \
      --freebsd-benchmark-json "$freebsd_source" \
      --steady-state-start-round "$start_round" \
      --label "m14-freebsd-normalized" \
      --out "$freebsd_normalized"
    ;;
  round-snapshots)
    python3 "${repo_root}/scripts/benchmarks/extract-m14-benchmark.py" \
      --freebsd-round-snapshots-json "$freebsd_source" \
      --steady-state-start-round "$start_round" \
      --label "m14-freebsd-normalized" \
      --out "$freebsd_normalized"
    ;;
  serial-log)
    python3 "${repo_root}/scripts/benchmarks/extract-m14-benchmark.py" \
      --freebsd-serial-log "$freebsd_source" \
      --steady-state-start-round "$start_round" \
      --label "m14-freebsd-normalized" \
      --out "$freebsd_normalized"
    ;;
  normalized)
    cp "$freebsd_source" "$freebsd_normalized"
    ;;
  *)
    echo "unsupported TWQ_M14_FREEBSD_SOURCE_KIND: $freebsd_source_kind" >&2
    exit 64
    ;;
esac
validate_artifact \
  "$freebsd_normalized" \
  "normalized" \
  "freebsd" \
  "$freebsd_normalized_validation_json" \
  "$freebsd_normalized_validation_txt"

python3 "${repo_root}/scripts/benchmarks/compare-m14-benchmarks.py" \
  "$freebsd_normalized" \
  "$macos_normalized" \
  --within-ratio "$within_ratio" \
  --about-within-ratio "$about_within_ratio" \
  --material-gap-ratio "$material_gap_ratio" \
  --json-out "$comparison_json" >"$summary_txt"

python3 "${repo_root}/scripts/benchmarks/summarize-m14-compare.py" \
  "$comparison_json" >"$report_txt"

printf 'out_dir=%s\n' "$out_dir"
if [ -f "$discovery_json" ]; then
  printf 'discovery_json=%s\n' "$discovery_json"
fi
printf 'freebsd_source=%s\n' "$freebsd_source"
printf 'freebsd_input_validation=%s\n' "$freebsd_input_validation_json"
printf 'freebsd_input_audit=%s\n' "$freebsd_input_audit_json"
printf 'macos_source=%s\n' "$macos_source"
printf 'macos_input_validation=%s\n' "$macos_input_validation_json"
printf 'macos_input_audit=%s\n' "$macos_input_audit_json"
printf 'freebsd_normalized=%s\n' "$freebsd_normalized"
printf 'freebsd_normalized_validation=%s\n' "$freebsd_normalized_validation_json"
printf 'macos_normalized=%s\n' "$macos_normalized"
printf 'macos_normalized_validation=%s\n' "$macos_normalized_validation_json"
printf 'comparison_json=%s\n' "$comparison_json"
printf 'summary=%s\n' "$summary_txt"
printf 'report=%s\n' "$report_txt"
