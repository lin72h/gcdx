#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: prepare-stage.sh [--help]

Environment:
  TWQ_ARTIFACTS_ROOT             Artifacts root used for derived outputs
  TWQ_SWIFT_DISTFILE             Local Swift 6.3 self-hosted toolchain tarball
  TWQ_SWIFT_TOOLCHAIN_ROOT       Extracted toolchain root
  TWQ_SWIFT_STAGE_DIR            Guest staging directory for Swift runtime libs
  TWQ_SWIFT_STOCK_DISPATCH_STAGE_DIR Guest staging directory for stock toolchain Dispatch libs
  TWQ_SWIFT_CONCURRENCY_OVERRIDE_SO Optional replacement libswift_Concurrency.so
  TWQ_SWIFT_CONCURRENCY_HOOK_TRACE_SO Output shared library for Swift concurrency hook tracing
  TWQ_SWIFT_ASYNC_SMOKE_BIN      Output binary for the Swift async smoke probe
  TWQ_SWIFT_ASYNC_YIELD_BIN      Output binary for the Swift async yield probe
  TWQ_SWIFT_ASYNC_SLEEP_BIN      Output binary for the Swift async sleep probe
  TWQ_SWIFT_MAINQUEUE_RESUME_BIN Output binary for the Swift main-queue resume probe
  TWQ_SWIFT_MAINACTOR_SLEEP_BIN  Output binary for the Swift main-actor sleep probe
  TWQ_SWIFT_MAINACTOR_TASKGROUP_BIN Output binary for the Swift main-actor TaskGroup probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWN_BIN Output binary for the Swift dispatchMain spawn probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_YIELD_BIN Output binary for the Swift dispatchMain spawn-wait-yield probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_SLEEP_BIN Output binary for the Swift dispatchMain spawn-wait-sleep probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_AFTER_BIN Output binary for the Swift dispatchMain spawn-wait-after probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWNED_YIELD_BIN Output binary for the Swift dispatchMain spawned-yield probe
  TWQ_SWIFT_DISPATCHMAIN_SPAWNED_SLEEP_BIN Output binary for the Swift dispatchMain spawned-sleep probe
  TWQ_SWIFT_DISPATCHMAIN_YIELD_BIN Output binary for the Swift dispatchMain yield probe
  TWQ_SWIFT_DISPATCHMAIN_CONTINUATION_BIN Output binary for the Swift dispatchMain continuation probe
  TWQ_SWIFT_DISPATCHMAIN_SLEEP_BIN Output binary for the Swift dispatchMain sleep probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_BIN Output binary for the Swift dispatchMain TaskGroup probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_AFTER_BIN Output binary for the Swift dispatchMain TaskGroup after probe
  TWQ_SWIFT_DISPATCHMAIN_TASKHANDLES_AFTER_BIN Output binary for the Swift dispatchMain Task-handles after probe
  TWQ_SWIFT_DISPATCHMAIN_TASKHANDLES_AFTER_REPEAT_BIN Output binary for the repeated Swift dispatchMain Task-handles after stress probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_YIELD_BIN Output binary for the Swift dispatchMain TaskGroup yield probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_ONESLEEP_BIN Output binary for the Swift dispatchMain TaskGroup one-sleep probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_BIN Output binary for the Swift dispatchMain TaskGroup sleep probe
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_NEXT_BIN Output binary for the Swift dispatchMain TaskGroup sleep-next probe
  TWQ_SWIFT_DETACHED_SLEEP_BIN  Output binary for the Swift detached sleep probe
  TWQ_SWIFT_DETACHED_TASKGROUP_BIN Output binary for the Swift detached TaskGroup probe
  TWQ_SWIFT_CONTINUATION_RESUME_BIN Output binary for the Swift continuation resume probe
  TWQ_SWIFT_SPAWNED_CONTINUATION_BIN Output binary for the Swift spawned continuation probe
  TWQ_SWIFT_SPAWNED_YIELD_BIN    Output binary for the Swift spawned yield probe
  TWQ_SWIFT_SPAWNED_SLEEP_BIN    Output binary for the Swift spawned sleep probe
  TWQ_SWIFT_TASK_SPAWN_BIN       Output binary for the Swift task spawn probe
  TWQ_SWIFT_TASKGROUP_SPAWNED_BIN Output binary for the Swift spawned TaskGroup probe
  TWQ_SWIFT_TASKGROUP_IMMEDIATE_BIN Output binary for the immediate TaskGroup probe
  TWQ_SWIFT_TASKGROUP_YIELD_BIN  Output binary for the TaskGroup yield probe
  TWQ_SWIFT_TASKGROUP_PROBE_BIN  Output binary for the Swift TaskGroup pre-check
  TWQ_SWIFT_DISPATCH_PROBE_BIN   Output binary for the Swift Dispatch control
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
swift_distfile=${TWQ_SWIFT_DISTFILE:-/Users/me/wip-rnx/freebsd-swift630-artifacts/distfiles/swift-6.3-RELEASE-freebsd15-x86_64-selfhosted.tar.gz}
toolchain_root=${TWQ_SWIFT_TOOLCHAIN_ROOT:-/Users/me/wip-rnx/nx-/swift-source-vx-modified/install/rnx-vx-swift63-selfhost-install5/usr}
swift_stage_dir=${TWQ_SWIFT_STAGE_DIR:-${artifacts_root}/swift-stage}
swift_stock_dispatch_stage_dir=${TWQ_SWIFT_STOCK_DISPATCH_STAGE_DIR:-${artifacts_root}/swift-stock-dispatch-stage}
swift_concurrency_override_so=${TWQ_SWIFT_CONCURRENCY_OVERRIDE_SO:-}
swift_concurrency_hook_trace_so=${TWQ_SWIFT_CONCURRENCY_HOOK_TRACE_SO:-${artifacts_root}/swift/lib/libtwq-swift-concurrency-hooks.so}
async_smoke_bin=${TWQ_SWIFT_ASYNC_SMOKE_BIN:-${artifacts_root}/swift/bin/twq-swift-async-smoke}
async_yield_bin=${TWQ_SWIFT_ASYNC_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-async-yield}
async_sleep_bin=${TWQ_SWIFT_ASYNC_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-async-sleep}
mainqueue_resume_bin=${TWQ_SWIFT_MAINQUEUE_RESUME_BIN:-${artifacts_root}/swift/bin/twq-swift-mainqueue-resume}
mainactor_sleep_bin=${TWQ_SWIFT_MAINACTOR_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-mainactor-sleep}
mainactor_taskgroup_bin=${TWQ_SWIFT_MAINACTOR_TASKGROUP_BIN:-${artifacts_root}/swift/bin/twq-swift-mainactor-taskgroup}
dispatchmain_spawn_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWN_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawn}
dispatchmain_spawnwait_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawnwait-yield}
dispatchmain_spawnwait_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawnwait-sleep}
dispatchmain_spawnwait_after_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_AFTER_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawnwait-after}
dispatchmain_spawned_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNED_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawned-yield}
dispatchmain_spawned_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNED_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-spawned-sleep}
dispatchmain_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-yield}
dispatchmain_continuation_bin=${TWQ_SWIFT_DISPATCHMAIN_CONTINUATION_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-continuation}
dispatchmain_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-sleep}
dispatchmain_taskgroup_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup}
dispatchmain_taskgroup_after_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_AFTER_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup-after}
dispatchmain_taskhandles_after_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKHANDLES_AFTER_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskhandles-after}
dispatchmain_taskhandles_after_repeat_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKHANDLES_AFTER_REPEAT_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskhandles-after-repeat}
dispatchmain_taskgroup_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup-yield}
dispatchmain_taskgroup_onesleep_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_ONESLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup-onesleep}
dispatchmain_taskgroup_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup-sleep}
dispatchmain_taskgroup_sleep_next_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_NEXT_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatchmain-taskgroup-sleep-next}
detached_sleep_bin=${TWQ_SWIFT_DETACHED_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-detached-sleep}
detached_taskgroup_bin=${TWQ_SWIFT_DETACHED_TASKGROUP_BIN:-${artifacts_root}/swift/bin/twq-swift-detached-taskgroup}
continuation_resume_bin=${TWQ_SWIFT_CONTINUATION_RESUME_BIN:-${artifacts_root}/swift/bin/twq-swift-continuation-resume}
spawned_continuation_bin=${TWQ_SWIFT_SPAWNED_CONTINUATION_BIN:-${artifacts_root}/swift/bin/twq-swift-spawned-continuation}
spawned_yield_bin=${TWQ_SWIFT_SPAWNED_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-spawned-yield}
spawned_sleep_bin=${TWQ_SWIFT_SPAWNED_SLEEP_BIN:-${artifacts_root}/swift/bin/twq-swift-spawned-sleep}
task_spawn_bin=${TWQ_SWIFT_TASK_SPAWN_BIN:-${artifacts_root}/swift/bin/twq-swift-task-spawn}
taskgroup_spawned_bin=${TWQ_SWIFT_TASKGROUP_SPAWNED_BIN:-${artifacts_root}/swift/bin/twq-swift-taskgroup-spawned}
taskgroup_immediate_bin=${TWQ_SWIFT_TASKGROUP_IMMEDIATE_BIN:-${artifacts_root}/swift/bin/twq-swift-taskgroup-immediate}
taskgroup_yield_bin=${TWQ_SWIFT_TASKGROUP_YIELD_BIN:-${artifacts_root}/swift/bin/twq-swift-taskgroup-yield}
taskgroup_bin=${TWQ_SWIFT_TASKGROUP_PROBE_BIN:-${artifacts_root}/swift/bin/twq-swift-taskgroup-precheck}
dispatch_bin=${TWQ_SWIFT_DISPATCH_PROBE_BIN:-${artifacts_root}/swift/bin/twq-swift-dispatch-control}
async_smoke_src=${repo_root}/swiftsrc/twq_swift_async_smoke.swift
async_yield_src=${repo_root}/swiftsrc/twq_swift_async_yield.swift
async_sleep_src=${repo_root}/swiftsrc/twq_swift_async_sleep.swift
mainqueue_resume_src=${repo_root}/swiftsrc/twq_swift_mainqueue_resume.swift
mainactor_sleep_src=${repo_root}/swiftsrc/twq_swift_mainactor_sleep.swift
mainactor_taskgroup_src=${repo_root}/swiftsrc/twq_swift_mainactor_taskgroup.swift
dispatchmain_spawn_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawn.swift
dispatchmain_spawnwait_yield_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawnwait_yield.swift
dispatchmain_spawnwait_sleep_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawnwait_sleep.swift
dispatchmain_spawnwait_after_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawnwait_after.swift
dispatchmain_spawned_yield_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawned_yield.swift
dispatchmain_spawned_sleep_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_spawned_sleep.swift
dispatchmain_yield_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_yield.swift
dispatchmain_continuation_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_continuation.swift
dispatchmain_sleep_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_sleep.swift
dispatchmain_taskgroup_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup.swift
dispatchmain_taskgroup_after_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup_after.swift
dispatchmain_taskhandles_after_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskhandles_after.swift
dispatchmain_taskhandles_after_repeat_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskhandles_after_repeat.swift
dispatchmain_taskgroup_yield_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup_yield.swift
dispatchmain_taskgroup_onesleep_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup_onesleep.swift
dispatchmain_taskgroup_sleep_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup_sleep.swift
dispatchmain_taskgroup_sleep_next_src=${repo_root}/swiftsrc/twq_swift_dispatchmain_taskgroup_sleep_next.swift
detached_sleep_src=${repo_root}/swiftsrc/twq_swift_detached_sleep.swift
detached_taskgroup_src=${repo_root}/swiftsrc/twq_swift_detached_taskgroup.swift
continuation_resume_src=${repo_root}/swiftsrc/twq_swift_continuation_resume.swift
spawned_continuation_src=${repo_root}/swiftsrc/twq_swift_spawned_continuation.swift
spawned_yield_src=${repo_root}/swiftsrc/twq_swift_spawned_yield.swift
spawned_sleep_src=${repo_root}/swiftsrc/twq_swift_spawned_sleep.swift
task_spawn_src=${repo_root}/swiftsrc/twq_swift_task_spawn.swift
taskgroup_spawned_src=${repo_root}/swiftsrc/twq_swift_taskgroup_spawned.swift
taskgroup_immediate_src=${repo_root}/swiftsrc/twq_swift_taskgroup_immediate.swift
taskgroup_yield_src=${repo_root}/swiftsrc/twq_swift_taskgroup_yield.swift
taskgroup_src=${repo_root}/swiftsrc/twq_swift_taskgroup_precheck.swift
dispatch_src=${repo_root}/swiftsrc/twq_swift_dispatch_control.swift
swift_hook_trace_src=${repo_root}/csrc/twq_swift_concurrency_hooks.cpp
guest_rpath=/root/twq-swift/usr/lib/swift/freebsd

if [ ! -x "$toolchain_root/bin/swiftc" ] && [ ! -x "$toolchain_root/usr/bin/swiftc" ]; then
  if [ ! -f "$swift_distfile" ]; then
    echo "Swift toolchain distfile not found: $swift_distfile" >&2
    exit 66
  fi
  mkdir -p "$toolchain_root"
  tar -xf "$swift_distfile" -C "$toolchain_root" --strip-components=1 \
    rnx-vx-swift63-selfhost-install5/usr
fi

if [ -x "$toolchain_root/bin/swiftc" ]; then
  swiftc_bin="$toolchain_root/bin/swiftc"
  swift_usr_root="$toolchain_root"
elif [ -x "$toolchain_root/usr/bin/swiftc" ]; then
  swiftc_bin="$toolchain_root/usr/bin/swiftc"
  swift_usr_root="$toolchain_root/usr"
else
  echo "Swift compiler not found after extraction under: $toolchain_root" >&2
  exit 66
fi

if [ -x "$swift_usr_root/bin/clang++" ]; then
  clangxx_bin="$swift_usr_root/bin/clang++"
elif command -v clang++ >/dev/null 2>&1; then
  clangxx_bin=$(command -v clang++)
else
  echo "C++ compiler not found for Swift hook trace library build" >&2
  exit 66
fi

mkdir -p "$(dirname "$async_smoke_bin")" "$(dirname "$async_yield_bin")" "$(dirname "$async_sleep_bin")" \
  "$(dirname "$mainqueue_resume_bin")" "$(dirname "$mainactor_sleep_bin")" \
  "$(dirname "$mainactor_taskgroup_bin")" "$(dirname "$dispatchmain_spawn_bin")" \
  "$(dirname "$dispatchmain_spawnwait_yield_bin")" "$(dirname "$dispatchmain_spawnwait_sleep_bin")" "$(dirname "$dispatchmain_spawnwait_after_bin")" \
  "$(dirname "$dispatchmain_spawned_yield_bin")" "$(dirname "$dispatchmain_spawned_sleep_bin")" \
  "$(dirname "$dispatchmain_yield_bin")" "$(dirname "$dispatchmain_continuation_bin")" "$(dirname "$dispatchmain_sleep_bin")" \
  "$(dirname "$dispatchmain_taskgroup_bin")" "$(dirname "$dispatchmain_taskgroup_after_bin")" "$(dirname "$dispatchmain_taskhandles_after_bin")" "$(dirname "$dispatchmain_taskhandles_after_repeat_bin")" "$(dirname "$dispatchmain_taskgroup_yield_bin")" "$(dirname "$dispatchmain_taskgroup_onesleep_bin")" \
  "$(dirname "$dispatchmain_taskgroup_sleep_bin")" "$(dirname "$dispatchmain_taskgroup_sleep_next_bin")" "$(dirname "$detached_sleep_bin")" \
  "$(dirname "$detached_taskgroup_bin")" "$(dirname "$continuation_resume_bin")" \
  "$(dirname "$spawned_continuation_bin")" "$(dirname "$spawned_yield_bin")" "$(dirname "$spawned_sleep_bin")" "$(dirname "$task_spawn_bin")" \
  "$(dirname "$taskgroup_spawned_bin")" \
  "$(dirname "$taskgroup_immediate_bin")" "$(dirname "$taskgroup_yield_bin")" \
  "$(dirname "$taskgroup_bin")" "$(dirname "$dispatch_bin")" "$(dirname "$swift_concurrency_hook_trace_so")"
mkdir -p "$swift_stage_dir/usr/lib/swift" "$swift_stock_dispatch_stage_dir"
rm -rf "$swift_stage_dir/usr/lib/swift/freebsd"
cp -a "$swift_usr_root/lib/swift/freebsd" "$swift_stage_dir/usr/lib/swift/"

if [ -n "$swift_concurrency_override_so" ]; then
  if [ ! -f "$swift_concurrency_override_so" ]; then
    echo "Swift concurrency override library not found: $swift_concurrency_override_so" >&2
    exit 66
  fi
  cp -f "$swift_concurrency_override_so" \
    "$swift_stage_dir/usr/lib/swift/freebsd/libswift_Concurrency.so"
fi

rm -f "$swift_stage_dir/usr/lib/swift/freebsd/libdispatch.so"
rm -f "$swift_stage_dir/usr/lib/swift/freebsd/libBlocksRuntime.so"
rm -f "$swift_stock_dispatch_stage_dir/libdispatch.so" "$swift_stock_dispatch_stage_dir/libBlocksRuntime.so"
cp -a "$swift_usr_root/lib/swift/freebsd/libdispatch.so" "$swift_stock_dispatch_stage_dir/"
cp -a "$swift_usr_root/lib/swift/freebsd/libBlocksRuntime.so" "$swift_stock_dispatch_stage_dir/"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$async_smoke_src" \
  -o "$async_smoke_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$async_yield_src" \
  -o "$async_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$async_sleep_src" \
  -o "$async_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$mainqueue_resume_src" \
  -o "$mainqueue_resume_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$mainactor_sleep_src" \
  -o "$mainactor_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$mainactor_taskgroup_src" \
  -o "$mainactor_taskgroup_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawn_src" \
  -o "$dispatchmain_spawn_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawnwait_yield_src" \
  -o "$dispatchmain_spawnwait_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawnwait_sleep_src" \
  -o "$dispatchmain_spawnwait_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawnwait_after_src" \
  -o "$dispatchmain_spawnwait_after_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawned_yield_src" \
  -o "$dispatchmain_spawned_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_spawned_sleep_src" \
  -o "$dispatchmain_spawned_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_yield_src" \
  -o "$dispatchmain_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_continuation_src" \
  -o "$dispatchmain_continuation_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_sleep_src" \
  -o "$dispatchmain_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_src" \
  -o "$dispatchmain_taskgroup_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_after_src" \
  -o "$dispatchmain_taskgroup_after_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskhandles_after_src" \
  -o "$dispatchmain_taskhandles_after_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskhandles_after_repeat_src" \
  -o "$dispatchmain_taskhandles_after_repeat_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_yield_src" \
  -o "$dispatchmain_taskgroup_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_onesleep_src" \
  -o "$dispatchmain_taskgroup_onesleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_sleep_src" \
  -o "$dispatchmain_taskgroup_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatchmain_taskgroup_sleep_next_src" \
  -o "$dispatchmain_taskgroup_sleep_next_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$detached_sleep_src" \
  -o "$detached_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$detached_taskgroup_src" \
  -o "$detached_taskgroup_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$continuation_resume_src" \
  -o "$continuation_resume_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$spawned_continuation_src" \
  -o "$spawned_continuation_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$spawned_yield_src" \
  -o "$spawned_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$spawned_sleep_src" \
  -o "$spawned_sleep_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$task_spawn_src" \
  -o "$task_spawn_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$taskgroup_spawned_src" \
  -o "$taskgroup_spawned_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$taskgroup_immediate_src" \
  -o "$taskgroup_immediate_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$taskgroup_yield_src" \
  -o "$taskgroup_yield_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$taskgroup_src" \
  -o "$taskgroup_bin"

"$swiftc_bin" \
  -parse-as-library \
  -no-toolchain-stdlib-rpath \
  -Xlinker -rpath -Xlinker "$guest_rpath" \
  "$dispatch_src" \
  -o "$dispatch_bin"

"$clangxx_bin" \
  -std=c++17 \
  -fPIC \
  -shared \
  "$swift_hook_trace_src" \
  -o "$swift_concurrency_hook_trace_so"
