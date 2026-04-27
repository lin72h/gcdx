#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m15-pressure-provider-stack-gate.sh [--help]

Runs the current repo-owned pressure-provider stack gate:
1. derived pressure-only prep lane
2. live pressure smoke lane
3. raw preview smoke lane
4. aggregate adapter smoke lane
5. callable session smoke lane
6. observer smoke lane
7. tracker smoke lane
8. bundle smoke lane
9. observer replay lane
10. tracker replay lane
11. bundle replay lane
12. shared contract-check lane across the actual artifacts used above

By default this gate reuses the checked-in baselines for the live families so
the stack stays runnable without booting multiple guests. Child candidate
overrides may point at fresh artifacts when needed.

Environment:
  TWQ_ARTIFACTS_ROOT                         Host artifacts root
  TWQ_M15_STACK_OUT_DIR                      Output directory for all artifacts
  TWQ_M15_STACK_SUMMARY_MD                   Markdown summary output path
  TWQ_M15_STACK_JSON                         Structured stack manifest path
  TWQ_M15_STACK_CONTRACT_JSON                Checked-in contract JSON path
  TWQ_M15_STACK_CROSSOVER_SOURCE             Source crossover artifact for the derived lane
  TWQ_M15_STACK_DERIVED_BASELINE             Derived baseline JSON
  TWQ_M15_STACK_LIVE_BASELINE                Live baseline JSON
  TWQ_M15_STACK_PREVIEW_BASELINE             Preview baseline JSON
  TWQ_M15_STACK_ADAPTER_BASELINE             Adapter baseline JSON
  TWQ_M15_STACK_SESSION_BASELINE             Session baseline JSON
  TWQ_M15_STACK_OBSERVER_BASELINE            Observer baseline JSON
  TWQ_M15_STACK_TRACKER_BASELINE             Tracker baseline JSON
  TWQ_M15_STACK_BUNDLE_BASELINE              Bundle baseline JSON

Optional child artifact overrides:
  TWQ_M15_STACK_DERIVED_CANDIDATE_JSON
  TWQ_M15_STACK_LIVE_CANDIDATE_JSON
  TWQ_M15_STACK_PREVIEW_CANDIDATE_JSON
  TWQ_M15_STACK_ADAPTER_CANDIDATE_JSON
  TWQ_M15_STACK_SESSION_CANDIDATE_JSON
  TWQ_M15_STACK_OBSERVER_CANDIDATE_JSON
  TWQ_M15_STACK_TRACKER_CANDIDATE_JSON
  TWQ_M15_STACK_BUNDLE_CANDIDATE_JSON
  TWQ_M15_STACK_OBSERVER_REPLAY_SESSION_ARTIFACT
  TWQ_M15_STACK_TRACKER_REPLAY_SESSION_ARTIFACT
  TWQ_M15_STACK_BUNDLE_REPLAY_SESSION_ARTIFACT

All normal bhyve environment consumed by the child lanes is passed through
unchanged.
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

out_dir=${TWQ_M15_STACK_OUT_DIR:-${artifacts_root}/benchmarks/m15-pressure-provider-stack-${timestamp}}
summary_md=${TWQ_M15_STACK_SUMMARY_MD:-${out_dir}/summary.md}
stack_json=${TWQ_M15_STACK_JSON:-${out_dir}/stack.json}
contract_json=${TWQ_M15_STACK_CONTRACT_JSON:-${repo_root}/benchmarks/contracts/m15-pressure-provider-contract-v1.json}
boundary_doc=${repo_root}/m15-pressure-provider-stack-gate.md

derived_baseline=${TWQ_M15_STACK_DERIVED_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-20260417.json}
live_baseline=${TWQ_M15_STACK_LIVE_BASELINE:-${repo_root}/benchmarks/baselines/m15-live-pressure-provider-smoke-20260417.json}
preview_baseline=${TWQ_M15_STACK_PREVIEW_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-preview-smoke-20260417.json}
adapter_baseline=${TWQ_M15_STACK_ADAPTER_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-adapter-smoke-20260417.json}
session_baseline=${TWQ_M15_STACK_SESSION_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-session-smoke-20260417.json}
observer_baseline=${TWQ_M15_STACK_OBSERVER_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-observer-smoke-20260417.json}
tracker_baseline=${TWQ_M15_STACK_TRACKER_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-tracker-smoke-20260417.json}
bundle_baseline=${TWQ_M15_STACK_BUNDLE_BASELINE:-${repo_root}/benchmarks/baselines/m15-pressure-provider-bundle-smoke-20260417.json}
crossover_source=${TWQ_M15_STACK_CROSSOVER_SOURCE:-${repo_root}/benchmarks/baselines/m13-crossover-full-20260417.json}

derived_dir=${out_dir}/derived
live_dir=${out_dir}/live
preview_dir=${out_dir}/preview
adapter_dir=${out_dir}/adapter
session_dir=${out_dir}/session
observer_dir=${out_dir}/observer
tracker_dir=${out_dir}/tracker
bundle_dir=${out_dir}/bundle
replay_dir=${out_dir}/observer-replay
tracker_replay_dir=${out_dir}/tracker-replay
bundle_replay_dir=${out_dir}/bundle-replay
contract_dir=${out_dir}/contract

derived_summary=${derived_dir}/summary.md
derived_comparison_json=${derived_dir}/comparison.json
derived_candidate=${TWQ_M15_STACK_DERIVED_CANDIDATE_JSON:-${derived_dir}/m15-pressure-provider-candidate.json}

live_summary=${live_dir}/summary.md
live_comparison_json=${live_dir}/comparison.json
live_candidate=${TWQ_M15_STACK_LIVE_CANDIDATE_JSON:-$live_baseline}

preview_summary=${preview_dir}/summary.md
preview_comparison_json=${preview_dir}/comparison.json
preview_candidate=${TWQ_M15_STACK_PREVIEW_CANDIDATE_JSON:-$preview_baseline}

adapter_summary=${adapter_dir}/summary.md
adapter_comparison_json=${adapter_dir}/comparison.json
adapter_candidate=${TWQ_M15_STACK_ADAPTER_CANDIDATE_JSON:-$adapter_baseline}

session_summary=${session_dir}/summary.md
session_comparison_json=${session_dir}/comparison.json
session_candidate=${TWQ_M15_STACK_SESSION_CANDIDATE_JSON:-$session_baseline}

observer_summary=${observer_dir}/summary.md
observer_comparison_json=${observer_dir}/comparison.json
observer_candidate=${TWQ_M15_STACK_OBSERVER_CANDIDATE_JSON:-$observer_baseline}

tracker_summary=${tracker_dir}/summary.md
tracker_comparison_json=${tracker_dir}/comparison.json
tracker_candidate=${TWQ_M15_STACK_TRACKER_CANDIDATE_JSON:-$tracker_baseline}

bundle_summary=${bundle_dir}/summary.md
bundle_comparison_json=${bundle_dir}/comparison.json
bundle_candidate=${TWQ_M15_STACK_BUNDLE_CANDIDATE_JSON:-$bundle_baseline}

replay_summary=${replay_dir}/summary.md
replay_comparison_json=${replay_dir}/comparison.json
replay_session_artifact=${TWQ_M15_STACK_OBSERVER_REPLAY_SESSION_ARTIFACT:-$session_candidate}

tracker_replay_summary=${tracker_replay_dir}/summary.md
tracker_replay_comparison_json=${tracker_replay_dir}/comparison.json
tracker_replay_session_artifact=${TWQ_M15_STACK_TRACKER_REPLAY_SESSION_ARTIFACT:-$session_candidate}

bundle_replay_summary=${bundle_replay_dir}/summary.md
bundle_replay_comparison_json=${bundle_replay_dir}/comparison.json
bundle_replay_session_artifact=${TWQ_M15_STACK_BUNDLE_REPLAY_SESSION_ARTIFACT:-$session_candidate}

contract_summary=${contract_dir}/summary.md

mkdir -p \
  "$out_dir" \
  "$derived_dir" \
  "$live_dir" \
  "$preview_dir" \
  "$adapter_dir" \
  "$session_dir" \
  "$observer_dir" \
  "$tracker_dir" \
  "$bundle_dir" \
  "$replay_dir" \
  "$tracker_replay_dir" \
  "$bundle_replay_dir" \
  "$contract_dir" \
  "$(dirname "$summary_md")" \
  "$(dirname "$stack_json")"

derived_rc=0
live_rc=0
preview_rc=0
adapter_rc=0
session_rc=0
observer_rc=0
tracker_rc=0
bundle_rc=0
replay_rc=0
tracker_replay_rc=0
bundle_replay_rc=0
contract_rc=0

(
  export TWQ_M15_PRESSURE_OUT_DIR="$derived_dir"
  export TWQ_M15_PRESSURE_SUMMARY_MD="$derived_summary"
  export TWQ_M15_PRESSURE_COMPARISON_JSON="$derived_comparison_json"
  export TWQ_M15_PRESSURE_BASELINE="$derived_baseline"
  export TWQ_M15_PRESSURE_SOURCE_ARTIFACT="$crossover_source"
  export TWQ_M15_PRESSURE_CANDIDATE_JSON="$derived_candidate"
  sh "${script_dir}/run-m15-pressure-provider-prep.sh"
) || derived_rc=$?

(
  export TWQ_M15_LIVE_PRESSURE_OUT_DIR="$live_dir"
  export TWQ_M15_LIVE_PRESSURE_SUMMARY_MD="$live_summary"
  export TWQ_M15_LIVE_PRESSURE_COMPARISON_JSON="$live_comparison_json"
  export TWQ_M15_LIVE_PRESSURE_BASELINE="$live_baseline"
  export TWQ_M15_LIVE_PRESSURE_CANDIDATE_JSON="$live_candidate"
  sh "${script_dir}/run-m15-live-pressure-provider-smoke.sh"
) || live_rc=$?

(
  export TWQ_M15_PREVIEW_OUT_DIR="$preview_dir"
  export TWQ_M15_PREVIEW_SUMMARY_MD="$preview_summary"
  export TWQ_M15_PREVIEW_COMPARISON_JSON="$preview_comparison_json"
  export TWQ_M15_PREVIEW_BASELINE="$preview_baseline"
  export TWQ_M15_PREVIEW_CANDIDATE_JSON="$preview_candidate"
  sh "${script_dir}/run-m15-pressure-provider-preview-smoke.sh"
) || preview_rc=$?

(
  export TWQ_M15_ADAPTER_OUT_DIR="$adapter_dir"
  export TWQ_M15_ADAPTER_SUMMARY_MD="$adapter_summary"
  export TWQ_M15_ADAPTER_COMPARISON_JSON="$adapter_comparison_json"
  export TWQ_M15_ADAPTER_BASELINE="$adapter_baseline"
  export TWQ_M15_ADAPTER_CANDIDATE_JSON="$adapter_candidate"
  sh "${script_dir}/run-m15-pressure-provider-adapter-smoke.sh"
) || adapter_rc=$?

(
  export TWQ_M15_SESSION_OUT_DIR="$session_dir"
  export TWQ_M15_SESSION_SUMMARY_MD="$session_summary"
  export TWQ_M15_SESSION_COMPARISON_JSON="$session_comparison_json"
  export TWQ_M15_SESSION_BASELINE="$session_baseline"
  export TWQ_M15_SESSION_CANDIDATE_JSON="$session_candidate"
  sh "${script_dir}/run-m15-pressure-provider-session-smoke.sh"
) || session_rc=$?

(
  export TWQ_M15_OBSERVER_OUT_DIR="$observer_dir"
  export TWQ_M15_OBSERVER_SUMMARY_MD="$observer_summary"
  export TWQ_M15_OBSERVER_COMPARISON_JSON="$observer_comparison_json"
  export TWQ_M15_OBSERVER_BASELINE="$observer_baseline"
  export TWQ_M15_OBSERVER_CANDIDATE_JSON="$observer_candidate"
  sh "${script_dir}/run-m15-pressure-provider-observer-smoke.sh"
) || observer_rc=$?

(
  export TWQ_M15_TRACKER_OUT_DIR="$tracker_dir"
  export TWQ_M15_TRACKER_SUMMARY_MD="$tracker_summary"
  export TWQ_M15_TRACKER_COMPARISON_JSON="$tracker_comparison_json"
  export TWQ_M15_TRACKER_BASELINE="$tracker_baseline"
  export TWQ_M15_TRACKER_CANDIDATE_JSON="$tracker_candidate"
  sh "${script_dir}/run-m15-pressure-provider-tracker-smoke.sh"
) || tracker_rc=$?

(
  export TWQ_M15_BUNDLE_OUT_DIR="$bundle_dir"
  export TWQ_M15_BUNDLE_SUMMARY_MD="$bundle_summary"
  export TWQ_M15_BUNDLE_COMPARISON_JSON="$bundle_comparison_json"
  export TWQ_M15_BUNDLE_BASELINE="$bundle_baseline"
  export TWQ_M15_BUNDLE_CANDIDATE_JSON="$bundle_candidate"
  sh "${script_dir}/run-m15-pressure-provider-bundle-smoke.sh"
) || bundle_rc=$?

(
  export TWQ_M15_OBSERVER_REPLAY_OUT_DIR="$replay_dir"
  export TWQ_M15_OBSERVER_REPLAY_SUMMARY_MD="$replay_summary"
  export TWQ_M15_OBSERVER_REPLAY_COMPARISON_JSON="$replay_comparison_json"
  export TWQ_M15_OBSERVER_REPLAY_BASELINE="$observer_baseline"
  export TWQ_M15_OBSERVER_REPLAY_SESSION_ARTIFACT="$replay_session_artifact"
  sh "${script_dir}/run-m15-pressure-provider-observer-replay.sh"
) || replay_rc=$?

(
  export TWQ_M15_TRACKER_REPLAY_OUT_DIR="$tracker_replay_dir"
  export TWQ_M15_TRACKER_REPLAY_SUMMARY_MD="$tracker_replay_summary"
  export TWQ_M15_TRACKER_REPLAY_COMPARISON_JSON="$tracker_replay_comparison_json"
  export TWQ_M15_TRACKER_REPLAY_BASELINE="$tracker_baseline"
  export TWQ_M15_TRACKER_REPLAY_SESSION_ARTIFACT="$tracker_replay_session_artifact"
  sh "${script_dir}/run-m15-pressure-provider-tracker-replay.sh"
) || tracker_replay_rc=$?

(
  export TWQ_M15_BUNDLE_REPLAY_OUT_DIR="$bundle_replay_dir"
  export TWQ_M15_BUNDLE_REPLAY_SUMMARY_MD="$bundle_replay_summary"
  export TWQ_M15_BUNDLE_REPLAY_COMPARISON_JSON="$bundle_replay_comparison_json"
  export TWQ_M15_BUNDLE_REPLAY_BASELINE="$bundle_baseline"
  export TWQ_M15_BUNDLE_REPLAY_SESSION_ARTIFACT="$bundle_replay_session_artifact"
  sh "${script_dir}/run-m15-pressure-provider-bundle-replay.sh"
) || bundle_replay_rc=$?

(
  export TWQ_M15_PRESSURE_CONTRACT_OUT_DIR="$contract_dir"
  export TWQ_M15_PRESSURE_CONTRACT_SUMMARY_MD="$contract_summary"
  export TWQ_M15_PRESSURE_CONTRACT_JSON="$contract_json"
  export TWQ_M15_PRESSURE_CONTRACT_DERIVED_ARTIFACT="$derived_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_LIVE_ARTIFACT="$live_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_ADAPTER_ARTIFACT="$adapter_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_SESSION_ARTIFACT="$session_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_OBSERVER_ARTIFACT="$observer_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_TRACKER_ARTIFACT="$tracker_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_BUNDLE_ARTIFACT="$bundle_candidate"
  export TWQ_M15_PRESSURE_CONTRACT_PREVIEW_ARTIFACT="$preview_candidate"
  sh "${script_dir}/run-m15-pressure-provider-contract-check.sh"
) || contract_rc=$?

python3 - <<'PY' \
  "$stack_json" \
  "$boundary_doc" \
  "$contract_json" \
  "$derived_candidate" \
  "$live_candidate" \
  "$preview_candidate" \
  "$adapter_candidate" \
  "$session_candidate" \
  "$observer_candidate" \
  "$tracker_candidate" \
  "$bundle_candidate" \
  "$replay_session_artifact" \
  "$tracker_replay_session_artifact" \
  "$bundle_replay_session_artifact" \
  "$derived_summary" \
  "$derived_comparison_json" \
  "$live_summary" \
  "$live_comparison_json" \
  "$preview_summary" \
  "$preview_comparison_json" \
  "$adapter_summary" \
  "$adapter_comparison_json" \
  "$session_summary" \
  "$session_comparison_json" \
  "$observer_summary" \
  "$observer_comparison_json" \
  "$tracker_summary" \
  "$tracker_comparison_json" \
  "$bundle_summary" \
  "$bundle_comparison_json" \
  "$replay_summary" \
  "$replay_comparison_json" \
  "$tracker_replay_summary" \
  "$tracker_replay_comparison_json" \
  "$bundle_replay_summary" \
  "$bundle_replay_comparison_json" \
  "$contract_summary" \
  "$derived_rc" \
  "$live_rc" \
  "$preview_rc" \
  "$adapter_rc" \
  "$session_rc" \
  "$observer_rc" \
  "$tracker_rc" \
  "$bundle_rc" \
  "$replay_rc" \
  "$tracker_replay_rc" \
  "$bundle_replay_rc" \
  "$contract_rc"
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
boundary_doc = sys.argv[2]
contract_json = sys.argv[3]
derived_candidate = sys.argv[4]
live_candidate = sys.argv[5]
preview_candidate = sys.argv[6]
adapter_candidate = sys.argv[7]
session_candidate = sys.argv[8]
observer_candidate = sys.argv[9]
tracker_candidate = sys.argv[10]
bundle_candidate = sys.argv[11]
replay_session_artifact = sys.argv[12]
tracker_replay_session_artifact = sys.argv[13]
bundle_replay_session_artifact = sys.argv[14]
derived_summary = sys.argv[15]
derived_comparison = sys.argv[16]
live_summary = sys.argv[17]
live_comparison = sys.argv[18]
preview_summary = sys.argv[19]
preview_comparison = sys.argv[20]
adapter_summary = sys.argv[21]
adapter_comparison = sys.argv[22]
session_summary = sys.argv[23]
session_comparison = sys.argv[24]
observer_summary = sys.argv[25]
observer_comparison = sys.argv[26]
tracker_summary = sys.argv[27]
tracker_comparison = sys.argv[28]
bundle_summary = sys.argv[29]
bundle_comparison = sys.argv[30]
replay_summary = sys.argv[31]
replay_comparison = sys.argv[32]
tracker_replay_summary = sys.argv[33]
tracker_replay_comparison = sys.argv[34]
bundle_replay_summary = sys.argv[35]
bundle_replay_comparison = sys.argv[36]
contract_summary = sys.argv[37]
derived_rc = int(sys.argv[38])
live_rc = int(sys.argv[39])
preview_rc = int(sys.argv[40])
adapter_rc = int(sys.argv[41])
session_rc = int(sys.argv[42])
observer_rc = int(sys.argv[43])
tracker_rc = int(sys.argv[44])
bundle_rc = int(sys.argv[45])
replay_rc = int(sys.argv[46])
tracker_replay_rc = int(sys.argv[47])
bundle_replay_rc = int(sys.argv[48])
contract_rc = int(sys.argv[49])


def load_json(path_str: str):
    path = Path(path_str)
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


derived_payload = load_json(derived_comparison) or {}
live_payload = load_json(live_comparison) or {}
preview_payload = load_json(preview_comparison) or {}
adapter_payload = load_json(adapter_comparison) or {}
session_payload = load_json(session_comparison) or {}
observer_payload = load_json(observer_comparison) or {}
tracker_payload = load_json(tracker_comparison) or {}
bundle_payload = load_json(bundle_comparison) or {}
replay_payload = load_json(replay_comparison) or {}
tracker_replay_payload = load_json(tracker_replay_comparison) or {}
bundle_replay_payload = load_json(bundle_replay_comparison) or {}

overall_ok = (
    derived_rc == 0
    and live_rc == 0
    and preview_rc == 0
    and adapter_rc == 0
    and session_rc == 0
    and observer_rc == 0
    and tracker_rc == 0
    and bundle_rc == 0
    and replay_rc == 0
    and tracker_replay_rc == 0
    and bundle_replay_rc == 0
    and contract_rc == 0
)
verdict = "pressure_stack_ready" if overall_ok else "hold"

payload = {
    "ok": overall_ok,
    "verdict": verdict,
    "boundary_doc": boundary_doc,
    "contract_json": contract_json,
    "artifacts": {
        "derived": derived_candidate,
        "live": live_candidate,
        "preview": preview_candidate,
        "adapter": adapter_candidate,
        "session": session_candidate,
        "observer": observer_candidate,
        "tracker": tracker_candidate,
        "bundle": bundle_candidate,
        "observer_replay_session": replay_session_artifact,
        "tracker_replay_session": tracker_replay_session_artifact,
        "bundle_replay_session": bundle_replay_session_artifact,
    },
    "lanes": {
        "derived": {
            "exit_status": derived_rc,
            "ok": derived_rc == 0,
            "summary_md": derived_summary,
            "comparison_json": derived_comparison,
            "comparison": derived_payload,
        },
        "live": {
            "exit_status": live_rc,
            "ok": live_rc == 0,
            "summary_md": live_summary,
            "comparison_json": live_comparison,
            "comparison": live_payload,
        },
        "preview": {
            "exit_status": preview_rc,
            "ok": preview_rc == 0,
            "summary_md": preview_summary,
            "comparison_json": preview_comparison,
            "comparison": preview_payload,
        },
        "adapter": {
            "exit_status": adapter_rc,
            "ok": adapter_rc == 0,
            "summary_md": adapter_summary,
            "comparison_json": adapter_comparison,
            "comparison": adapter_payload,
        },
        "session": {
            "exit_status": session_rc,
            "ok": session_rc == 0,
            "summary_md": session_summary,
            "comparison_json": session_comparison,
            "comparison": session_payload,
        },
        "observer": {
            "exit_status": observer_rc,
            "ok": observer_rc == 0,
            "summary_md": observer_summary,
            "comparison_json": observer_comparison,
            "comparison": observer_payload,
        },
        "tracker": {
            "exit_status": tracker_rc,
            "ok": tracker_rc == 0,
            "summary_md": tracker_summary,
            "comparison_json": tracker_comparison,
            "comparison": tracker_payload,
        },
        "bundle": {
            "exit_status": bundle_rc,
            "ok": bundle_rc == 0,
            "summary_md": bundle_summary,
            "comparison_json": bundle_comparison,
            "comparison": bundle_payload,
        },
        "observer_replay": {
            "exit_status": replay_rc,
            "ok": replay_rc == 0,
            "summary_md": replay_summary,
            "comparison_json": replay_comparison,
            "comparison": replay_payload,
        },
        "tracker_replay": {
            "exit_status": tracker_replay_rc,
            "ok": tracker_replay_rc == 0,
            "summary_md": tracker_replay_summary,
            "comparison_json": tracker_replay_comparison,
            "comparison": tracker_replay_payload,
        },
        "bundle_replay": {
            "exit_status": bundle_replay_rc,
            "ok": bundle_replay_rc == 0,
            "summary_md": bundle_replay_summary,
            "comparison_json": bundle_replay_comparison,
            "comparison": bundle_replay_payload,
        },
        "contract": {
            "exit_status": contract_rc,
            "ok": contract_rc == 0,
            "summary_md": contract_summary,
        },
    },
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(verdict)
PY

verdict=$(python3 - <<'PY' "$stack_json"
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
    print(data.get('verdict', 'hold'))
PY
)

{
  printf '# M15 Pressure Provider Stack Gate\n\n'
  printf -- '- Boundary doc: `%s`\n' "$boundary_doc"
  printf -- '- Contract: `%s`\n' "$contract_json"
  printf -- '- Stack JSON: `%s`\n' "$stack_json"
  printf -- '- Verdict: `%s`\n\n' "$verdict"
  printf '## Lane Status\n\n'
  printf -- '- Derived prep: `%s` (`%s`)\n' "$derived_rc" "$derived_summary"
  printf -- '- Live smoke: `%s` (`%s`)\n' "$live_rc" "$live_summary"
  printf -- '- Preview smoke: `%s` (`%s`)\n' "$preview_rc" "$preview_summary"
  printf -- '- Adapter smoke: `%s` (`%s`)\n' "$adapter_rc" "$adapter_summary"
  printf -- '- Session smoke: `%s` (`%s`)\n' "$session_rc" "$session_summary"
  printf -- '- Observer smoke: `%s` (`%s`)\n' "$observer_rc" "$observer_summary"
  printf -- '- Tracker smoke: `%s` (`%s`)\n' "$tracker_rc" "$tracker_summary"
  printf -- '- Bundle smoke: `%s` (`%s`)\n' "$bundle_rc" "$bundle_summary"
  printf -- '- Observer replay: `%s` (`%s`)\n' "$replay_rc" "$replay_summary"
  printf -- '- Tracker replay: `%s` (`%s`)\n' "$tracker_replay_rc" "$tracker_replay_summary"
  printf -- '- Bundle replay: `%s` (`%s`)\n' "$bundle_replay_rc" "$bundle_replay_summary"
  printf -- '- Contract check: `%s` (`%s`)\n\n' "$contract_rc" "$contract_summary"
  printf '## Exit Rule\n\n'
  printf 'The pressure-provider stack is ready only when all twelve child lanes are green and the same checked-in contract still describes every artifact family used by the gate.\n'
} >"$summary_md"

echo "Summary: $summary_md"
echo "Stack JSON: $stack_json"
echo "verdict=$verdict"

if [ "$derived_rc" -eq 0 ] && \
   [ "$live_rc" -eq 0 ] && \
   [ "$preview_rc" -eq 0 ] && \
   [ "$adapter_rc" -eq 0 ] && \
   [ "$session_rc" -eq 0 ] && \
   [ "$observer_rc" -eq 0 ] && \
   [ "$tracker_rc" -eq 0 ] && \
   [ "$bundle_rc" -eq 0 ] && \
   [ "$replay_rc" -eq 0 ] && \
   [ "$tracker_replay_rc" -eq 0 ] && \
   [ "$bundle_replay_rc" -eq 0 ] && \
   [ "$contract_rc" -eq 0 ]; then
  exit 0
fi

exit 1
