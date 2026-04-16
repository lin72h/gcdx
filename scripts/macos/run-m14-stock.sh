#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-m14-stock.sh [--help] [--out-dir DIR] [--skip-swift] [--skip-c]

Environment:
  TWQ_ARTIFACTS_ROOT             Artifacts root used for derived outputs
  TWQ_REPEAT_ROUNDS              Round count for both lanes (default: 64)
  TWQ_REPEAT_TASKS               Task count for both lanes (default: 8)
  TWQ_REPEAT_DELAY_MS            Delay for both lanes in milliseconds (default: 20)
  TWQ_REPEAT_DEBUG_FIRST_ROUND   Emit first-round child markers for the Swift lane
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/../.." && pwd)
artifacts_root=${TWQ_ARTIFACTS_ROOT:-${repo_root}/../artifacts}
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
out_dir=${artifacts_root}/macos/m14-stock-${timestamp}
run_swift=1
run_c=1
swift_repeat_bin=${TWQ_MACOS_SWIFT_REPEAT_BIN:-${artifacts_root}/macos/bin/twq-swift-dispatchmain-taskhandles-after-repeat}
c_resume_repeat_bin=${TWQ_MACOS_C_RESUME_REPEAT_BIN:-${artifacts_root}/macos/bin/twq-macos-dispatch-resume-repeat}

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
    --skip-swift)
      run_swift=0
      shift
      ;;
    --skip-c)
      run_c=0
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

rounds=${TWQ_REPEAT_ROUNDS:-64}
tasks=${TWQ_REPEAT_TASKS:-8}
delay_ms=${TWQ_REPEAT_DELAY_MS:-20}
debug_first_round=${TWQ_REPEAT_DEBUG_FIRST_ROUND:-0}

mkdir -p "$out_dir"

sh "${repo_root}/scripts/macos/prepare-m14.sh" >/dev/null

sw_vers >"${out_dir}/sw_vers.txt" 2>&1 || true
uname -a >"${out_dir}/uname.txt" 2>&1 || true
sysctl -a >"${out_dir}/sysctl.txt" 2>/dev/null || true

python3 "${repo_root}/scripts/macos/check-m14-symbols.py" \
  --out "${out_dir}/stock-symbols.json"

swift_log=${out_dir}/swift-repeat.log
c_log=${out_dir}/c-repeat.log
swift_rc=0
c_rc=0

if [ "$run_swift" -eq 1 ]; then
  if env \
    TWQ_REPEAT_ROUNDS="$rounds" \
    TWQ_REPEAT_TASKS="$tasks" \
    TWQ_REPEAT_DELAY_MS="$delay_ms" \
    TWQ_REPEAT_DEBUG_FIRST_ROUND="$debug_first_round" \
    "$swift_repeat_bin" >"$swift_log" 2>&1; then
    swift_rc=0
  else
    swift_rc=$?
  fi
fi

if [ "$run_c" -eq 1 ]; then
  if "$c_resume_repeat_bin" \
    --mode main-executor-resume-repeat \
    --rounds "$rounds" \
    --tasks "$tasks" \
    --sleep-ms "$delay_ms" >"$c_log" 2>&1; then
    c_rc=0
  else
    c_rc=$?
  fi
fi

printf 'swift_rc=%s\n' "$swift_rc" >"${out_dir}/rc.txt"
printf 'c_rc=%s\n' "$c_rc" >>"${out_dir}/rc.txt"

python3 "${repo_root}/scripts/macos/extract-m14-run.py" \
  --out "${out_dir}/m14-run.json" \
  --label "m14-macos-stock" \
  --swift-log "$swift_log" \
  --c-log "$c_log" \
  --symbols-json "${out_dir}/stock-symbols.json"

python3 "${repo_root}/scripts/macos/summarize-m14-run.py" \
  "${out_dir}/m14-run.json" >"${out_dir}/summary.txt"

printf 'out_dir=%s\n' "$out_dir"
printf 'summary=%s\n' "${out_dir}/summary.txt"
