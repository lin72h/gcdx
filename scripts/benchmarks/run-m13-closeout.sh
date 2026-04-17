#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m13-closeout.sh [--help]

Runs the current repo-owned M13 closeout stack:
1. low-level one-boot gate
2. focused repeat-lane gate
3. full-matrix M13.5 crossover assessment

Environment:
  TWQ_VM_IMAGE                               Raw guest disk image
  TWQ_GUEST_ROOT                             Guest root mount point
  TWQ_ARTIFACTS_ROOT                         Host artifacts root
  TWQ_M13_CLOSEOUT_OUT_DIR                   Output directory for all artifacts
  TWQ_M13_CLOSEOUT_SUMMARY_MD                Markdown summary output path
  TWQ_M13_CLOSEOUT_JSON                      Structured closeout manifest path

Optional child-lane overrides:
  TWQ_M13_CLOSEOUT_LOWLEVEL_BASELINE
  TWQ_M13_CLOSEOUT_LOWLEVEL_CANDIDATE_JSON
  TWQ_M13_CLOSEOUT_REPEAT_BASELINE
  TWQ_M13_CLOSEOUT_REPEAT_CANDIDATE_JSON
  TWQ_M13_CLOSEOUT_CROSSOVER_BASELINE
  TWQ_M13_CLOSEOUT_CROSSOVER_CANDIDATE_JSON

All normal sizing and bhyve environment consumed by the child gates is passed
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

out_dir=${TWQ_M13_CLOSEOUT_OUT_DIR:-${artifacts_root}/benchmarks/m13-closeout-${timestamp}}
summary_md=${TWQ_M13_CLOSEOUT_SUMMARY_MD:-${out_dir}/summary.md}
closeout_json=${TWQ_M13_CLOSEOUT_JSON:-${out_dir}/closeout.json}
boundary_doc=${repo_root}/m13-5-crossover-boundary.md

lowlevel_dir=${out_dir}/lowlevel
repeat_dir=${out_dir}/repeat
crossover_dir=${out_dir}/crossover

lowlevel_summary=${lowlevel_dir}/summary.md
lowlevel_comparison_json=${lowlevel_dir}/comparison.json
repeat_summary=${repeat_dir}/summary.md
repeat_comparison_json=${repeat_dir}/comparison.json
crossover_summary=${crossover_dir}/summary.md
crossover_comparison_json=${crossover_dir}/comparison.json

mkdir -p "$out_dir" "$lowlevel_dir" "$repeat_dir" "$crossover_dir" \
  "$(dirname "$summary_md")" "$(dirname "$closeout_json")"

lowlevel_rc=0
repeat_rc=0
crossover_rc=0

(
  export TWQ_M13_LOWLEVEL_GATE_DIR="$lowlevel_dir"
  export TWQ_M13_LOWLEVEL_SUMMARY_MD="$lowlevel_summary"
  export TWQ_M13_LOWLEVEL_COMPARISON_JSON="$lowlevel_comparison_json"
  if [ -n "${TWQ_M13_CLOSEOUT_LOWLEVEL_BASELINE:-}" ]; then
    export TWQ_M13_LOWLEVEL_BASELINE="$TWQ_M13_CLOSEOUT_LOWLEVEL_BASELINE"
  fi
  if [ -n "${TWQ_M13_CLOSEOUT_LOWLEVEL_CANDIDATE_JSON:-}" ]; then
    export TWQ_M13_LOWLEVEL_CANDIDATE_JSON="$TWQ_M13_CLOSEOUT_LOWLEVEL_CANDIDATE_JSON"
  fi
  sh "${script_dir}/run-m13-lowlevel-gate.sh"
) || lowlevel_rc=$?

(
  export TWQ_M13_REPEAT_OUT_DIR="$repeat_dir"
  export TWQ_M13_REPEAT_SUMMARY_MD="$repeat_summary"
  export TWQ_M13_REPEAT_COMPARISON_JSON="$repeat_comparison_json"
  if [ -n "${TWQ_M13_CLOSEOUT_REPEAT_BASELINE:-}" ]; then
    export TWQ_M13_REPEAT_BASELINE="$TWQ_M13_CLOSEOUT_REPEAT_BASELINE"
  fi
  if [ -n "${TWQ_M13_CLOSEOUT_REPEAT_CANDIDATE_JSON:-}" ]; then
    export TWQ_M13_REPEAT_CANDIDATE_JSON="$TWQ_M13_CLOSEOUT_REPEAT_CANDIDATE_JSON"
  fi
  sh "${script_dir}/run-m13-repeat-gate.sh"
) || repeat_rc=$?

(
  export TWQ_M13_CROSSOVER_OUT_DIR="$crossover_dir"
  export TWQ_M13_CROSSOVER_SUMMARY_MD="$crossover_summary"
  export TWQ_M13_CROSSOVER_COMPARISON_JSON="$crossover_comparison_json"
  if [ -n "${TWQ_M13_CLOSEOUT_CROSSOVER_BASELINE:-}" ]; then
    export TWQ_M13_CROSSOVER_BASELINE="$TWQ_M13_CLOSEOUT_CROSSOVER_BASELINE"
  fi
  if [ -n "${TWQ_M13_CLOSEOUT_CROSSOVER_CANDIDATE_JSON:-}" ]; then
    export TWQ_M13_CROSSOVER_CANDIDATE_JSON="$TWQ_M13_CLOSEOUT_CROSSOVER_CANDIDATE_JSON"
  fi
  sh "${script_dir}/run-m13-crossover-assessment.sh"
) || crossover_rc=$?

python3 - <<'PY' \
  "$closeout_json" \
  "$boundary_doc" \
  "$lowlevel_summary" \
  "$lowlevel_comparison_json" \
  "$repeat_summary" \
  "$repeat_comparison_json" \
  "$crossover_summary" \
  "$crossover_comparison_json" \
  "$lowlevel_rc" \
  "$repeat_rc" \
  "$crossover_rc"
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
boundary_doc = sys.argv[2]
lowlevel_summary = sys.argv[3]
lowlevel_comparison = sys.argv[4]
repeat_summary = sys.argv[5]
repeat_comparison = sys.argv[6]
crossover_summary = sys.argv[7]
crossover_comparison = sys.argv[8]
lowlevel_rc = int(sys.argv[9])
repeat_rc = int(sys.argv[10])
crossover_rc = int(sys.argv[11])


def load_json(path_str: str):
    path = Path(path_str)
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


lowlevel_payload = load_json(lowlevel_comparison) or {}
repeat_payload = load_json(repeat_comparison) or {}
crossover_payload = load_json(crossover_comparison) or {}

overall_ok = lowlevel_rc == 0 and repeat_rc == 0 and crossover_rc == 0
verdict = "close_m13" if overall_ok else "hold"

payload = {
    "ok": overall_ok,
    "verdict": verdict,
    "boundary_doc": boundary_doc,
    "lanes": {
        "lowlevel": {
            "exit_status": lowlevel_rc,
            "ok": lowlevel_rc == 0,
            "summary_md": lowlevel_summary,
            "comparison_json": lowlevel_comparison,
            "comparison": lowlevel_payload,
        },
        "repeat": {
            "exit_status": repeat_rc,
            "ok": repeat_rc == 0,
            "summary_md": repeat_summary,
            "comparison_json": repeat_comparison,
            "comparison": repeat_payload,
        },
        "crossover": {
            "exit_status": crossover_rc,
            "ok": crossover_rc == 0,
            "summary_md": crossover_summary,
            "comparison_json": crossover_comparison,
            "comparison": crossover_payload,
        },
    },
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(verdict)
PY

verdict=$(python3 - <<'PY' "$closeout_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
    print(data.get('verdict', 'hold'))
PY
)

{
  printf '# M13 Closeout\n\n'
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Closeout JSON: `%s`\n' "$closeout_json"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Lane Status\n\n'
  printf -- '- Low-level gate: `%s` (`%s`)\n' "$lowlevel_rc" "$lowlevel_summary"
  printf -- '- Repeat gate: `%s` (`%s`)\n' "$repeat_rc" "$repeat_summary"
  printf -- '- Crossover assessment: `%s` (`%s`)\n\n' "$crossover_rc" "$crossover_summary"
  printf '## Exit Rule\n\n'
  printf 'M13 is closeable when all three child lanes are green and the boundary remains honest.\n'
} >"$summary_md"

echo "Summary: $summary_md"
echo "Closeout JSON: $closeout_json"
echo "verdict=$verdict"

if [ "$lowlevel_rc" -eq 0 ] && [ "$repeat_rc" -eq 0 ] && [ "$crossover_rc" -eq 0 ]; then
  exit 0
fi

exit 1
