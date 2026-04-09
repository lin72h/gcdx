#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: stage-guest.sh [--dry-run] [--help]

Environment:
  TWQ_VM_IMAGE              Raw guest disk image
  TWQ_GUEST_ROOT            Mount point for the guest root
  TWQ_KERNEL_CONF           Kernel config name to install (default: TWQDEBUG)
  TWQ_KERNEL_OBJDIRPREFIX   Kernel objdir prefix (default: /tmp/twqobj)
  TWQ_PROBE_BIN             Probe binary to copy into the guest
  TWQ_WORKQUEUE_PROBE_BIN   Userland pthread_workqueue probe to copy
  TWQ_DISPATCH_PROBE_BIN    Userland libdispatch probe to copy
  TWQ_SWIFT_ASYNC_SMOKE_BIN     Swift async smoke probe to copy
  TWQ_SWIFT_ASYNC_YIELD_BIN     Swift async yield probe to copy
  TWQ_SWIFT_ASYNC_SLEEP_BIN     Swift async sleep probe to copy
  TWQ_SWIFT_MAINQUEUE_RESUME_BIN Swift main-queue resume probe to copy
  TWQ_SWIFT_MAINACTOR_SLEEP_BIN Swift main-actor sleep probe to copy
  TWQ_SWIFT_MAINACTOR_TASKGROUP_BIN Swift main-actor TaskGroup probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWN_BIN Swift dispatchMain spawn probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_YIELD_BIN Swift dispatchMain spawn-wait-yield probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_SLEEP_BIN Swift dispatchMain spawn-wait-sleep probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_AFTER_BIN Swift dispatchMain spawn-wait-after probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWNED_YIELD_BIN Swift dispatchMain spawned-yield probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SPAWNED_SLEEP_BIN Swift dispatchMain spawned-sleep probe to copy
  TWQ_SWIFT_DISPATCHMAIN_YIELD_BIN Swift dispatchMain yield probe to copy
  TWQ_SWIFT_DISPATCHMAIN_CONTINUATION_BIN Swift dispatchMain continuation probe to copy
  TWQ_SWIFT_DISPATCHMAIN_SLEEP_BIN Swift dispatchMain sleep probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_BIN Swift dispatchMain TaskGroup probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_AFTER_BIN Swift dispatchMain TaskGroup after probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_YIELD_BIN Swift dispatchMain TaskGroup yield probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_ONESLEEP_BIN Swift dispatchMain TaskGroup one-sleep probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_BIN Swift dispatchMain TaskGroup sleep probe to copy
  TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_NEXT_BIN Swift dispatchMain TaskGroup sleep-next probe to copy
  TWQ_SWIFT_DETACHED_SLEEP_BIN Swift detached sleep probe to copy
  TWQ_SWIFT_DETACHED_TASKGROUP_BIN Swift detached TaskGroup probe to copy
  TWQ_SWIFT_CONTINUATION_RESUME_BIN Swift continuation resume probe to copy
  TWQ_SWIFT_SPAWNED_CONTINUATION_BIN Swift spawned continuation probe to copy
  TWQ_SWIFT_SPAWNED_YIELD_BIN   Swift spawned yield probe to copy
  TWQ_SWIFT_SPAWNED_SLEEP_BIN   Swift spawned sleep probe to copy
  TWQ_SWIFT_TASK_SPAWN_BIN      Swift task spawn probe to copy
  TWQ_SWIFT_TASKGROUP_SPAWNED_BIN Swift spawned TaskGroup probe to copy
  TWQ_SWIFT_TASKGROUP_IMMEDIATE_BIN Swift TaskGroup immediate probe to copy
  TWQ_SWIFT_TASKGROUP_YIELD_BIN Swift TaskGroup yield probe to copy
  TWQ_SWIFT_TASKGROUP_PROBE_BIN Swift TaskGroup sleep probe to copy
  TWQ_SWIFT_DISPATCH_PROBE_BIN  Swift Dispatch control probe to copy
  TWQ_LIBPTHREAD_STAGE_DIR  Directory containing the staged custom libthr
  TWQ_LIBDISPATCH_STAGE_DIR Directory containing staged libdispatch libraries
  TWQ_SWIFT_STAGE_DIR       Directory containing staged Swift runtime libraries
  TWQ_SWIFT_STOCK_DISPATCH_STAGE_DIR Directory containing stock toolchain Dispatch libraries
  TWQ_SWIFT_PROBE_PROFILE   `validation` for the stable Swift lane, `full` for diagnostics too
  TWQ_SWIFT_PROBE_FILTER    Optional comma-separated Swift probe mode filter
EOF
}

dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
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

vm_image=${TWQ_VM_IMAGE:-}
guest_root=${TWQ_GUEST_ROOT:-}
kernel_conf=${TWQ_KERNEL_CONF:-TWQDEBUG}
kernel_objdirprefix=${TWQ_KERNEL_OBJDIRPREFIX:-/tmp/twqobj}
probe_bin=${TWQ_PROBE_BIN:-${repo_root}/../artifacts/zig/prefix/bin/twq-probe-stub}
workqueue_probe_bin=${TWQ_WORKQUEUE_PROBE_BIN:-${repo_root}/../artifacts/zig/prefix/bin/twq-workqueue-probe}
dispatch_probe_bin=${TWQ_DISPATCH_PROBE_BIN:-${repo_root}/../artifacts/zig/prefix/bin/twq-dispatch-probe}
swift_async_smoke_bin=${TWQ_SWIFT_ASYNC_SMOKE_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-async-smoke}
swift_async_yield_bin=${TWQ_SWIFT_ASYNC_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-async-yield}
swift_async_sleep_bin=${TWQ_SWIFT_ASYNC_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-async-sleep}
swift_mainqueue_resume_bin=${TWQ_SWIFT_MAINQUEUE_RESUME_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-mainqueue-resume}
swift_mainactor_sleep_bin=${TWQ_SWIFT_MAINACTOR_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-mainactor-sleep}
swift_mainactor_taskgroup_bin=${TWQ_SWIFT_MAINACTOR_TASKGROUP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-mainactor-taskgroup}
swift_dispatchmain_spawn_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWN_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawn}
swift_dispatchmain_spawnwait_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawnwait-yield}
swift_dispatchmain_spawnwait_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawnwait-sleep}
swift_dispatchmain_spawnwait_after_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNWAIT_AFTER_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawnwait-after}
swift_dispatchmain_spawned_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNED_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawned-yield}
swift_dispatchmain_spawned_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SPAWNED_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-spawned-sleep}
swift_dispatchmain_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-yield}
swift_dispatchmain_continuation_bin=${TWQ_SWIFT_DISPATCHMAIN_CONTINUATION_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-continuation}
swift_dispatchmain_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-sleep}
swift_dispatchmain_taskgroup_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup}
swift_dispatchmain_taskgroup_after_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_AFTER_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup-after}
swift_dispatchmain_taskgroup_yield_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup-yield}
swift_dispatchmain_taskgroup_onesleep_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_ONESLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup-onesleep}
swift_dispatchmain_taskgroup_sleep_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup-sleep}
swift_dispatchmain_taskgroup_sleep_next_bin=${TWQ_SWIFT_DISPATCHMAIN_TASKGROUP_SLEEP_NEXT_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatchmain-taskgroup-sleep-next}
swift_detached_sleep_bin=${TWQ_SWIFT_DETACHED_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-detached-sleep}
swift_detached_taskgroup_bin=${TWQ_SWIFT_DETACHED_TASKGROUP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-detached-taskgroup}
swift_continuation_resume_bin=${TWQ_SWIFT_CONTINUATION_RESUME_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-continuation-resume}
swift_spawned_continuation_bin=${TWQ_SWIFT_SPAWNED_CONTINUATION_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-spawned-continuation}
swift_spawned_yield_bin=${TWQ_SWIFT_SPAWNED_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-spawned-yield}
swift_spawned_sleep_bin=${TWQ_SWIFT_SPAWNED_SLEEP_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-spawned-sleep}
swift_task_spawn_bin=${TWQ_SWIFT_TASK_SPAWN_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-task-spawn}
swift_taskgroup_spawned_bin=${TWQ_SWIFT_TASKGROUP_SPAWNED_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-taskgroup-spawned}
swift_taskgroup_immediate_bin=${TWQ_SWIFT_TASKGROUP_IMMEDIATE_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-taskgroup-immediate}
swift_taskgroup_yield_bin=${TWQ_SWIFT_TASKGROUP_YIELD_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-taskgroup-yield}
swift_taskgroup_probe_bin=${TWQ_SWIFT_TASKGROUP_PROBE_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-taskgroup-precheck}
swift_dispatch_probe_bin=${TWQ_SWIFT_DISPATCH_PROBE_BIN:-${repo_root}/../artifacts/swift/bin/twq-swift-dispatch-control}
pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${repo_root}/../artifacts/libthr-stage}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${repo_root}/../artifacts/libdispatch-stage}
swift_stage_dir=${TWQ_SWIFT_STAGE_DIR:-${repo_root}/../artifacts/swift-stage}
swift_stock_dispatch_stage_dir=${TWQ_SWIFT_STOCK_DISPATCH_STAGE_DIR:-${repo_root}/../artifacts/swift-stock-dispatch-stage}
swift_probe_profile=${TWQ_SWIFT_PROBE_PROFILE:-validation}
swift_probe_filter=${TWQ_SWIFT_PROBE_FILTER:-}

if [ -z "$vm_image" ] || [ -z "$guest_root" ]; then
  echo "TWQ_VM_IMAGE and TWQ_GUEST_ROOT are required unless --dry-run is used" >&2
  exit 64
fi

find_root_partition() {
  doas gpart list "$1" | awk '
    $2 == "Name:" { name = $3 }
    $1 == "type:" && $2 == "freebsd-ufs" { print "/dev/" name; exit }
  '
}

append_if_missing() {
  target=$1
  line=$2

  if doas test -f "$target" && doas grep -Fqx "$line" "$target"; then
    return 0
  fi
  printf '%s\n' "$line" | doas tee -a "$target" >/dev/null
}

if [ "$dry_run" -eq 1 ]; then
  cat <<EOF
attach image with mdconfig
mount first freebsd-ufs partition under ${guest_root}
install kernel ${kernel_conf} from ${kernel_objdirprefix}
copy probe ${probe_bin} into guest
copy userland probe ${workqueue_probe_bin} into guest
copy libdispatch probe ${dispatch_probe_bin} into guest
copy Swift async smoke probe ${swift_async_smoke_bin} into guest
copy Swift async yield probe ${swift_async_yield_bin} into guest
copy Swift async sleep probe ${swift_async_sleep_bin} into guest
copy Swift main-queue resume probe ${swift_mainqueue_resume_bin} into guest
copy Swift main-actor sleep probe ${swift_mainactor_sleep_bin} into guest
copy Swift main-actor TaskGroup probe ${swift_mainactor_taskgroup_bin} into guest
copy Swift dispatchMain spawn probe ${swift_dispatchmain_spawn_bin} into guest
copy Swift dispatchMain spawn-wait-yield probe ${swift_dispatchmain_spawnwait_yield_bin} into guest
copy Swift dispatchMain spawn-wait-sleep probe ${swift_dispatchmain_spawnwait_sleep_bin} into guest
copy Swift dispatchMain spawn-wait-after probe ${swift_dispatchmain_spawnwait_after_bin} into guest
copy Swift dispatchMain spawned-yield probe ${swift_dispatchmain_spawned_yield_bin} into guest
copy Swift dispatchMain spawned-sleep probe ${swift_dispatchmain_spawned_sleep_bin} into guest
copy Swift dispatchMain yield probe ${swift_dispatchmain_yield_bin} into guest
copy Swift dispatchMain continuation probe ${swift_dispatchmain_continuation_bin} into guest
copy Swift dispatchMain sleep probe ${swift_dispatchmain_sleep_bin} into guest
copy Swift dispatchMain TaskGroup probe ${swift_dispatchmain_taskgroup_bin} into guest
copy Swift dispatchMain TaskGroup after probe ${swift_dispatchmain_taskgroup_after_bin} into guest
copy Swift dispatchMain TaskGroup yield probe ${swift_dispatchmain_taskgroup_yield_bin} into guest
copy Swift dispatchMain TaskGroup one-sleep probe ${swift_dispatchmain_taskgroup_onesleep_bin} into guest
copy Swift dispatchMain TaskGroup sleep probe ${swift_dispatchmain_taskgroup_sleep_bin} into guest
copy Swift dispatchMain TaskGroup sleep-next probe ${swift_dispatchmain_taskgroup_sleep_next_bin} into guest
copy Swift detached sleep probe ${swift_detached_sleep_bin} into guest
copy Swift detached TaskGroup probe ${swift_detached_taskgroup_bin} into guest
copy Swift continuation resume probe ${swift_continuation_resume_bin} into guest
copy Swift spawned continuation probe ${swift_spawned_continuation_bin} into guest
copy Swift spawned yield probe ${swift_spawned_yield_bin} into guest
copy Swift spawned sleep probe ${swift_spawned_sleep_bin} into guest
copy Swift task spawn probe ${swift_task_spawn_bin} into guest
copy Swift spawned TaskGroup probe ${swift_taskgroup_spawned_bin} into guest
copy Swift TaskGroup immediate probe ${swift_taskgroup_immediate_bin} into guest
copy Swift TaskGroup yield probe ${swift_taskgroup_yield_bin} into guest
copy Swift TaskGroup sleep probe ${swift_taskgroup_probe_bin} into guest
copy Swift Dispatch control probe ${swift_dispatch_probe_bin} into guest
copy staged custom libthr from ${pthread_stage_dir}
copy staged libdispatch runtime from ${dispatch_stage_dir}
copy staged Swift runtime from ${swift_stage_dir}
copy stock toolchain Dispatch runtime from ${swift_stock_dispatch_stage_dir}
write Swift probe profile ${swift_probe_profile}
write Swift probe filter ${swift_probe_filter}
install one-shot twqprobe rc script
enable serial console loader settings
EOF
  exit 0
fi

if [ ! -f "$vm_image" ]; then
  echo "Guest image not found: $vm_image" >&2
  exit 66
fi

if [ ! -x "$probe_bin" ]; then
  echo "Probe binary not found or not executable: $probe_bin" >&2
  exit 66
fi

if [ ! -x "$workqueue_probe_bin" ]; then
  echo "Workqueue probe binary not found or not executable: $workqueue_probe_bin" >&2
  exit 66
fi

if [ ! -x "$dispatch_probe_bin" ]; then
  echo "Dispatch probe binary not found or not executable: $dispatch_probe_bin" >&2
  exit 66
fi

if [ ! -x "$swift_async_smoke_bin" ]; then
  echo "Swift async smoke probe binary not found or not executable: $swift_async_smoke_bin" >&2
  exit 66
fi

if [ ! -x "$swift_async_yield_bin" ]; then
  echo "Swift async yield probe binary not found or not executable: $swift_async_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_async_sleep_bin" ]; then
  echo "Swift async sleep probe binary not found or not executable: $swift_async_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_mainqueue_resume_bin" ]; then
  echo "Swift main-queue resume probe binary not found or not executable: $swift_mainqueue_resume_bin" >&2
  exit 66
fi

if [ ! -x "$swift_mainactor_sleep_bin" ]; then
  echo "Swift main-actor sleep probe binary not found or not executable: $swift_mainactor_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_mainactor_taskgroup_bin" ]; then
  echo "Swift main-actor TaskGroup probe binary not found or not executable: $swift_mainactor_taskgroup_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawn_bin" ]; then
  echo "Swift dispatchMain spawn probe binary not found or not executable: $swift_dispatchmain_spawn_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawnwait_yield_bin" ]; then
  echo "Swift dispatchMain spawn-wait-yield probe binary not found or not executable: $swift_dispatchmain_spawnwait_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawnwait_sleep_bin" ]; then
  echo "Swift dispatchMain spawn-wait-sleep probe binary not found or not executable: $swift_dispatchmain_spawnwait_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawnwait_after_bin" ]; then
  echo "Swift dispatchMain spawn-wait-after probe binary not found or not executable: $swift_dispatchmain_spawnwait_after_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawned_yield_bin" ]; then
  echo "Swift dispatchMain spawned-yield probe binary not found or not executable: $swift_dispatchmain_spawned_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_spawned_sleep_bin" ]; then
  echo "Swift dispatchMain spawned-sleep probe binary not found or not executable: $swift_dispatchmain_spawned_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_yield_bin" ]; then
  echo "Swift dispatchMain yield probe binary not found or not executable: $swift_dispatchmain_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_continuation_bin" ]; then
  echo "Swift dispatchMain continuation probe binary not found or not executable: $swift_dispatchmain_continuation_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_sleep_bin" ]; then
  echo "Swift dispatchMain sleep probe binary not found or not executable: $swift_dispatchmain_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_bin" ]; then
  echo "Swift dispatchMain TaskGroup probe binary not found or not executable: $swift_dispatchmain_taskgroup_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_after_bin" ]; then
  echo "Swift dispatchMain TaskGroup after probe binary not found or not executable: $swift_dispatchmain_taskgroup_after_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_yield_bin" ]; then
  echo "Swift dispatchMain TaskGroup yield probe binary not found or not executable: $swift_dispatchmain_taskgroup_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_onesleep_bin" ]; then
  echo "Swift dispatchMain TaskGroup one-sleep probe binary not found or not executable: $swift_dispatchmain_taskgroup_onesleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_sleep_bin" ]; then
  echo "Swift dispatchMain TaskGroup sleep probe binary not found or not executable: $swift_dispatchmain_taskgroup_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatchmain_taskgroup_sleep_next_bin" ]; then
  echo "Swift dispatchMain TaskGroup sleep-next probe binary not found or not executable: $swift_dispatchmain_taskgroup_sleep_next_bin" >&2
  exit 66
fi

if [ ! -x "$swift_detached_sleep_bin" ]; then
  echo "Swift detached sleep probe binary not found or not executable: $swift_detached_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_detached_taskgroup_bin" ]; then
  echo "Swift detached TaskGroup probe binary not found or not executable: $swift_detached_taskgroup_bin" >&2
  exit 66
fi

if [ ! -x "$swift_continuation_resume_bin" ]; then
  echo "Swift continuation resume probe binary not found or not executable: $swift_continuation_resume_bin" >&2
  exit 66
fi

if [ ! -x "$swift_spawned_continuation_bin" ]; then
  echo "Swift spawned continuation probe binary not found or not executable: $swift_spawned_continuation_bin" >&2
  exit 66
fi

if [ ! -x "$swift_spawned_yield_bin" ]; then
  echo "Swift spawned yield probe binary not found or not executable: $swift_spawned_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_spawned_sleep_bin" ]; then
  echo "Swift spawned sleep probe binary not found or not executable: $swift_spawned_sleep_bin" >&2
  exit 66
fi

if [ ! -x "$swift_task_spawn_bin" ]; then
  echo "Swift task spawn probe binary not found or not executable: $swift_task_spawn_bin" >&2
  exit 66
fi

if [ ! -x "$swift_taskgroup_spawned_bin" ]; then
  echo "Swift spawned TaskGroup probe binary not found or not executable: $swift_taskgroup_spawned_bin" >&2
  exit 66
fi

if [ ! -x "$swift_taskgroup_immediate_bin" ]; then
  echo "Swift TaskGroup immediate probe binary not found or not executable: $swift_taskgroup_immediate_bin" >&2
  exit 66
fi

if [ ! -x "$swift_taskgroup_yield_bin" ]; then
  echo "Swift TaskGroup yield probe binary not found or not executable: $swift_taskgroup_yield_bin" >&2
  exit 66
fi

if [ ! -x "$swift_taskgroup_probe_bin" ]; then
  echo "Swift TaskGroup probe binary not found or not executable: $swift_taskgroup_probe_bin" >&2
  exit 66
fi

if [ ! -x "$swift_dispatch_probe_bin" ]; then
  echo "Swift Dispatch control probe binary not found or not executable: $swift_dispatch_probe_bin" >&2
  exit 66
fi

if [ ! -f "$pthread_stage_dir/libthr.so.3" ]; then
  echo "Staged custom libthr not found under: $pthread_stage_dir" >&2
  exit 66
fi

if [ ! -f "$dispatch_stage_dir/libdispatch.so" ] || [ ! -f "$dispatch_stage_dir/libBlocksRuntime.so" ]; then
  echo "Staged libdispatch runtime not found under: $dispatch_stage_dir" >&2
  exit 66
fi

if [ ! -f "$swift_stage_dir/usr/lib/swift/freebsd/libswiftCore.so" ]; then
  echo "Staged Swift runtime not found under: $swift_stage_dir" >&2
  exit 66
fi

if [ ! -f "$swift_stock_dispatch_stage_dir/libdispatch.so" ] || \
   [ ! -f "$swift_stock_dispatch_stage_dir/libBlocksRuntime.so" ]; then
  echo "Staged stock Dispatch runtime not found under: $swift_stock_dispatch_stage_dir" >&2
  exit 66
fi

mddev=
cleanup() {
  if doas mount | awk '{print $3}' | grep -Fxq "$guest_root"; then
    doas umount "$guest_root" || true
  fi
  if [ -n "$mddev" ]; then
    doas mdconfig -d -u "${mddev#md}" || true
  fi
}
trap cleanup EXIT INT TERM

doas mkdir -p "$guest_root"
guest_root=$(CDPATH= cd -- "$guest_root" && pwd)
mddev=$(doas mdconfig -a -t vnode -f "$vm_image")
root_part=$(find_root_partition "$mddev")

if [ -z "$root_part" ]; then
  echo "Unable to locate a freebsd-ufs partition in $vm_image" >&2
  exit 65
fi

doas mount -o rw -t ufs "$root_part" "$guest_root"

doas env MAKEOBJDIRPREFIX="$kernel_objdirprefix" make -C /usr/src installkernel \
  KERNCONF="$kernel_conf" INSTKERNNAME="$kernel_conf" NO_MODULES=yes \
  DESTDIR="$guest_root"

doas install -d -m 755 "$guest_root/root"
doas install -m 755 "$probe_bin" "$guest_root/root/twq-probe-stub"
doas install -m 755 "$workqueue_probe_bin" "$guest_root/root/twq-workqueue-probe"
doas install -m 755 "$dispatch_probe_bin" "$guest_root/root/twq-dispatch-probe"
doas install -m 755 "$swift_async_smoke_bin" "$guest_root/root/twq-swift-async-smoke"
doas install -m 755 "$swift_async_yield_bin" "$guest_root/root/twq-swift-async-yield"
doas install -m 755 "$swift_async_sleep_bin" "$guest_root/root/twq-swift-async-sleep"
doas install -m 755 "$swift_mainqueue_resume_bin" "$guest_root/root/twq-swift-mainqueue-resume"
doas install -m 755 "$swift_mainactor_sleep_bin" "$guest_root/root/twq-swift-mainactor-sleep"
doas install -m 755 "$swift_mainactor_taskgroup_bin" "$guest_root/root/twq-swift-mainactor-taskgroup"
doas install -m 755 "$swift_dispatchmain_spawn_bin" "$guest_root/root/twq-swift-dispatchmain-spawn"
doas install -m 755 "$swift_dispatchmain_spawnwait_yield_bin" "$guest_root/root/twq-swift-dispatchmain-spawnwait-yield"
doas install -m 755 "$swift_dispatchmain_spawnwait_sleep_bin" "$guest_root/root/twq-swift-dispatchmain-spawnwait-sleep"
doas install -m 755 "$swift_dispatchmain_spawnwait_after_bin" "$guest_root/root/twq-swift-dispatchmain-spawnwait-after"
doas install -m 755 "$swift_dispatchmain_spawned_yield_bin" "$guest_root/root/twq-swift-dispatchmain-spawned-yield"
doas install -m 755 "$swift_dispatchmain_spawned_sleep_bin" "$guest_root/root/twq-swift-dispatchmain-spawned-sleep"
doas install -m 755 "$swift_dispatchmain_yield_bin" "$guest_root/root/twq-swift-dispatchmain-yield"
doas install -m 755 "$swift_dispatchmain_continuation_bin" "$guest_root/root/twq-swift-dispatchmain-continuation"
doas install -m 755 "$swift_dispatchmain_sleep_bin" "$guest_root/root/twq-swift-dispatchmain-sleep"
doas install -m 755 "$swift_dispatchmain_taskgroup_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup"
doas install -m 755 "$swift_dispatchmain_taskgroup_after_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup-after"
doas install -m 755 "$swift_dispatchmain_taskgroup_yield_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup-yield"
doas install -m 755 "$swift_dispatchmain_taskgroup_onesleep_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup-onesleep"
doas install -m 755 "$swift_dispatchmain_taskgroup_sleep_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup-sleep"
doas install -m 755 "$swift_dispatchmain_taskgroup_sleep_next_bin" "$guest_root/root/twq-swift-dispatchmain-taskgroup-sleep-next"
doas install -m 755 "$swift_detached_sleep_bin" "$guest_root/root/twq-swift-detached-sleep"
doas install -m 755 "$swift_detached_taskgroup_bin" "$guest_root/root/twq-swift-detached-taskgroup"
doas install -m 755 "$swift_continuation_resume_bin" "$guest_root/root/twq-swift-continuation-resume"
doas install -m 755 "$swift_spawned_continuation_bin" "$guest_root/root/twq-swift-spawned-continuation"
doas install -m 755 "$swift_spawned_yield_bin" "$guest_root/root/twq-swift-spawned-yield"
doas install -m 755 "$swift_spawned_sleep_bin" "$guest_root/root/twq-swift-spawned-sleep"
doas install -m 755 "$swift_task_spawn_bin" "$guest_root/root/twq-swift-task-spawn"
doas install -m 755 "$swift_taskgroup_spawned_bin" "$guest_root/root/twq-swift-taskgroup-spawned"
doas install -m 755 "$swift_taskgroup_immediate_bin" "$guest_root/root/twq-swift-taskgroup-immediate"
doas install -m 755 "$swift_taskgroup_yield_bin" "$guest_root/root/twq-swift-taskgroup-yield"
doas install -m 755 "$swift_taskgroup_probe_bin" "$guest_root/root/twq-swift-taskgroup-precheck"
doas install -m 755 "$swift_dispatch_probe_bin" "$guest_root/root/twq-swift-dispatch-control"
doas rm -rf "$guest_root/root/twq-lib"
doas mkdir -p "$guest_root/root/twq-lib"
doas cp -a "$pthread_stage_dir/." "$guest_root/root/twq-lib/"
doas rm -rf "$guest_root/root/twq-dispatch"
doas mkdir -p "$guest_root/root/twq-dispatch"
doas cp -a "$dispatch_stage_dir/." "$guest_root/root/twq-dispatch/"
doas rm -rf "$guest_root/root/twq-swift"
doas mkdir -p "$guest_root/root/twq-swift"
doas cp -a "$swift_stage_dir/." "$guest_root/root/twq-swift/"
doas rm -rf "$guest_root/root/twq-stock-dispatch"
doas mkdir -p "$guest_root/root/twq-stock-dispatch"
doas cp -a "$swift_stock_dispatch_stage_dir/." "$guest_root/root/twq-stock-dispatch/"
printf '%s\n' "$swift_probe_profile" | doas tee "$guest_root/root/twq-swift-profile" >/dev/null
printf '%s\n' "$swift_probe_filter" | doas tee "$guest_root/root/twq-swift-filter" >/dev/null

tmp_run=$(mktemp)
cat > "$tmp_run" <<'EOF'
#!/bin/sh
set -eu

run_with_timeout()
{
  RUN_WITH_TIMEOUT_STATUS=0
  RUN_WITH_TIMEOUT_TIMED_OUT=0
  timeout_secs=$1
  shift
  timeout_flag="/tmp/twq-timeout.$$"
  timeout_label=${RUN_WITH_TIMEOUT_LABEL:-}
  timeout_diag=${RUN_WITH_TIMEOUT_DIAGNOSTIC:-0}
  rm -f "$timeout_flag"

  "$@" &
  cmd_pid=$!
  (
    sleep "$timeout_secs"
    if kill -0 "$cmd_pid" 2>/dev/null; then
      : > "$timeout_flag"
      if [ "$timeout_diag" -ne 0 ] && [ -n "$timeout_label" ]; then
        echo "=== twq timeout diagnostics ${timeout_label} start ==="
        procstat -t "$cmd_pid" 2>&1 || true
        procstat -kk "$cmd_pid" 2>&1 || true
        echo "=== twq timeout diagnostics ${timeout_label} end ==="
      fi
      kill -TERM "$cmd_pid" 2>/dev/null || true
      sleep 1
      if kill -0 "$cmd_pid" 2>/dev/null; then
        kill -KILL "$cmd_pid" 2>/dev/null || true
      fi
    fi
  ) &
  watcher_pid=$!

  if wait "$cmd_pid"; then
    RUN_WITH_TIMEOUT_STATUS=0
  else
    RUN_WITH_TIMEOUT_STATUS=$?
  fi

  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true

  if [ -f "$timeout_flag" ]; then
    RUN_WITH_TIMEOUT_TIMED_OUT=1
    rm -f "$timeout_flag"
  fi
}

swift_probe_profile=validation
if [ -r /root/twq-swift-profile ]; then
  swift_probe_profile=$(cat /root/twq-swift-profile)
fi

swift_probe_filter=
if [ -r /root/twq-swift-filter ]; then
  swift_probe_filter=$(cat /root/twq-swift-filter)
fi

swift_runtime_root=/root/twq-swift/usr/lib/swift/freebsd
swift_twq_ld=/root/twq-dispatch:${swift_runtime_root}:/root/twq-lib
swift_stock_dispatch_ld=/root/twq-stock-dispatch:${swift_runtime_root}
swift_stock_dispatch_customthr_ld=/root/twq-stock-dispatch:${swift_runtime_root}:/root/twq-lib

swift_profile_runs_diagnostics()
{
  [ "${swift_probe_profile}" = "full" ]
}

swift_run_full_unfiltered_diagnostics()
{
  swift_profile_runs_diagnostics && [ -z "${swift_probe_filter}" ]
}

swift_probe_selected()
{
  probe_mode=$1

  if [ -z "${swift_probe_filter}" ]; then
    return 0
  fi

  case ",${swift_probe_filter}," in
    *,"${probe_mode}",*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

swift_probe_should_run()
{
  probe_mode=$1
  probe_class=$2

  if ! swift_probe_selected "${probe_mode}"; then
    return 1
  fi

  case "${probe_class}" in
    validation)
      return 0
      ;;
    diagnostic)
      swift_profile_runs_diagnostics
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

log=/var/log/twq-probe.log
{
  echo "=== twq probe start ==="
  date -u
  echo "=== twq swift profile ==="
  echo "${swift_probe_profile}"
  echo "=== twq swift profile end ==="
  echo "=== twq swift filter ==="
  if [ -n "${swift_probe_filter}" ]; then
    echo "${swift_probe_filter}"
  else
    echo "<none>"
  fi
  echo "=== twq swift filter end ==="
  sysctl kern.twq.busy_window_usecs=50000
  /root/twq-probe-stub --sequence basic --count 2
  /root/twq-probe-stub --sequence pressure
  /root/twq-probe-stub --sequence entered-pressure
  echo "=== twq stats start ==="
  sysctl kern.twq.busy_window_usecs \
    kern.twq.init_count \
    kern.twq.thread_enter_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_count \
    kern.twq.should_narrow_true_count \
    kern.twq.switch_block_count \
    kern.twq.switch_unblock_count \
    kern.twq.bucket_thread_enter_total \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_thread_return_total \
    kern.twq.bucket_switch_block_total \
    kern.twq.bucket_switch_unblock_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq stats end ==="
  echo "=== twq workqueue probe start ==="
  env LD_LIBRARY_PATH=/root/twq-lib /root/twq-workqueue-probe --numthreads 2 --timeout-ms 3000
  echo "=== twq workqueue probe end ==="
  echo "=== twq workqueue timeout stats before ==="
  sysctl kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq workqueue timeout stats before end ==="
  echo "=== twq workqueue timeout probe start ==="
  workqueue_timeout_rc=0
  env LD_LIBRARY_PATH=/root/twq-lib /root/twq-workqueue-probe --numthreads 8 --overcommit --timeout-ms 4000 --idle-wait-ms 8000 || workqueue_timeout_rc=$?
  echo "=== twq workqueue timeout probe end ==="
  echo "=== twq workqueue timeout stats after ==="
  sysctl kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq workqueue timeout stats after end ==="
  if [ "${workqueue_timeout_rc}" -ne 0 ]; then
    exit "${workqueue_timeout_rc}"
  fi
  echo "=== twq dispatch basic stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count
  echo "=== twq dispatch basic stats before end ==="
  echo "=== twq dispatch basic probe start ==="
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode basic --tasks 8 --sleep-ms 40 --timeout-ms 5000
  echo "=== twq dispatch basic probe end ==="
  echo "=== twq dispatch basic stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count
  echo "=== twq dispatch basic stats after end ==="
  echo "=== twq dispatch pressure stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.switch_block_count \
    kern.twq.switch_unblock_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_switch_block_total \
    kern.twq.bucket_switch_unblock_total
  echo "=== twq dispatch pressure stats before end ==="
  echo "=== twq dispatch pressure probe start ==="
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode pressure --tasks 8 --sleep-ms 40 --high-tasks 1 --high-sleep-ms 200 --timeout-ms 5000
  echo "=== twq dispatch pressure probe end ==="
  echo "=== twq dispatch pressure stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.switch_block_count \
    kern.twq.switch_unblock_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_switch_block_total \
    kern.twq.bucket_switch_unblock_total
  echo "=== twq dispatch pressure stats after end ==="
  echo "=== twq dispatch burst stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch burst stats before end ==="
  echo "=== twq dispatch burst probe start ==="
  burst_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode burst-reuse --tasks 24 --rounds 4 --sleep-ms 40 --pause-ms 300 --settle-ms 6500 --timeout-ms 5000 || burst_rc=$?
  echo "=== twq dispatch burst probe end ==="
  echo "=== twq dispatch burst stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch burst stats after end ==="
  if [ "${burst_rc}" -ne 0 ]; then
    exit "${burst_rc}"
  fi
  echo "=== twq dispatch timeout-gap stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch timeout-gap stats before end ==="
  echo "=== twq dispatch timeout-gap probe start ==="
  timeout_gap_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode timeout-gap --tasks 24 --rounds 2 --sleep-ms 40 --pause-ms 8000 --settle-ms 6500 --timeout-ms 5000 || timeout_gap_rc=$?
  echo "=== twq dispatch timeout-gap probe end ==="
  echo "=== twq dispatch timeout-gap stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch timeout-gap stats after end ==="
  if [ "${timeout_gap_rc}" -ne 0 ]; then
    exit "${timeout_gap_rc}"
  fi
  echo "=== twq dispatch sustained stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.switch_block_count \
    kern.twq.switch_unblock_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_switch_block_total \
    kern.twq.bucket_switch_unblock_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch sustained stats before end ==="
  echo "=== twq dispatch sustained probe start ==="
  sustained_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode sustained --tasks 640 --high-tasks 1 --sleep-ms 40 --high-sleep-ms 200 --sample-ms 100 --settle-ms 6500 --timeout-ms 25000 || sustained_rc=$?
  echo "=== twq dispatch sustained probe end ==="
  echo "=== twq dispatch sustained stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count \
    kern.twq.should_narrow_true_count \
    kern.twq.switch_block_count \
    kern.twq.switch_unblock_count \
    kern.twq.bucket_req_total \
    kern.twq.bucket_admit_total \
    kern.twq.bucket_switch_block_total \
    kern.twq.bucket_switch_unblock_total \
    kern.twq.bucket_total_current \
    kern.twq.bucket_idle_current \
    kern.twq.bucket_active_current
  echo "=== twq dispatch sustained stats after end ==="
  if [ "${sustained_rc}" -ne 0 ]; then
    exit "${sustained_rc}"
  fi
  probe_failure_rc=0
  echo "=== twq dispatch after stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch after stats before end ==="
  echo "=== twq dispatch after probe start ==="
  dispatch_after_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode after --tasks 8 --sleep-ms 40 --timeout-ms 5000 || dispatch_after_rc=$?
  echo "=== twq dispatch after probe end ==="
  echo "=== twq dispatch after stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch after stats after end ==="
  if [ "${dispatch_after_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_after_rc}
  fi
  echo "=== twq dispatch executor stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor stats before end ==="
  echo "=== twq dispatch executor probe start ==="
  dispatch_executor_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode executor --tasks 8 --sleep-ms 20 --timeout-ms 5000 || dispatch_executor_rc=$?
  echo "=== twq dispatch executor probe end ==="
  echo "=== twq dispatch executor stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor stats after end ==="
  if [ "${dispatch_executor_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_executor_rc}
  fi
  echo "=== twq dispatch executor-after stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor-after stats before end ==="
  echo "=== twq dispatch executor-after probe start ==="
  dispatch_executor_after_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode executor-after --tasks 8 --sleep-ms 40 --timeout-ms 5000 || dispatch_executor_after_rc=$?
  echo "=== twq dispatch executor-after probe end ==="
  echo "=== twq dispatch executor-after stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor-after stats after end ==="
  if [ "${dispatch_executor_after_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_executor_after_rc}
  fi
  echo "=== twq dispatch executor-after-settled stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor-after-settled stats before end ==="
  echo "=== twq dispatch executor-after-settled probe start ==="
  dispatch_executor_after_settled_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode executor-after-settled --tasks 8 --sleep-ms 40 --timeout-ms 5000 || dispatch_executor_after_settled_rc=$?
  echo "=== twq dispatch executor-after-settled probe end ==="
  echo "=== twq dispatch executor-after-settled stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch executor-after-settled stats after end ==="
  if [ "${dispatch_executor_after_settled_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_executor_after_settled_rc}
  fi
  echo "=== twq dispatch main stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch main stats before end ==="
  echo "=== twq dispatch main probe start ==="
  dispatch_main_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode main --tasks 4
  dispatch_main_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"dispatch-probe","status":"timeout","data":{"mode":"main","timed_out":true,"timeout_sec":15},"meta":{"component":"c","binary":"twq-dispatch-probe"}}'
    dispatch_main_rc=124
  fi
  echo "=== twq dispatch main probe end ==="
  echo "=== twq dispatch main stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch main stats after end ==="
  if [ "${dispatch_main_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_main_rc}
  fi
  echo "=== twq dispatch main-after stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch main-after stats before end ==="
  echo "=== twq dispatch main-after probe start ==="
  dispatch_main_after_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-lib /root/twq-dispatch-probe --mode main-after --tasks 4 --sleep-ms 40
  dispatch_main_after_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"dispatch-probe","status":"timeout","data":{"mode":"main-after","timed_out":true,"timeout_sec":15},"meta":{"component":"c","binary":"twq-dispatch-probe"}}'
    dispatch_main_after_rc=124
  fi
  echo "=== twq dispatch main-after probe end ==="
  echo "=== twq dispatch main-after stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq dispatch main-after stats after end ==="
  if [ "${dispatch_main_after_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${dispatch_main_after_rc}
  fi
  if swift_probe_should_run "async-smoke" validation; then
  echo "=== twq swift async smoke probe start ==="
  swift_async_smoke_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-async-smoke
  swift_async_smoke_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"async-smoke","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-async-smoke"}}'
    swift_async_smoke_rc=124
  elif [ "${swift_async_smoke_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"async-smoke\",\"timed_out\":false,\"rc\":${swift_async_smoke_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-smoke\"}}"
  fi
  echo "=== twq swift async smoke probe end ==="
  if [ "${swift_async_smoke_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_async_smoke_rc}
  fi
  fi
  if swift_run_full_unfiltered_diagnostics; then
  echo "=== twq swift async yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift async yield stats before end ==="
  echo "=== twq swift async yield probe start ==="
  swift_async_yield_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-async-yield
  swift_async_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"async-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-async-yield"}}'
    swift_async_yield_rc=124
  elif [ "${swift_async_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"async-yield\",\"timed_out\":false,\"rc\":${swift_async_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-yield\"}}"
  fi
  echo "=== twq swift async yield probe end ==="
  echo "=== twq swift async yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift async yield stats after end ==="
  if [ "${swift_async_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_async_yield_rc}
  fi
  echo "=== twq swift task spawn stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift task spawn stats before end ==="
  echo "=== twq swift task spawn probe start ==="
  swift_task_spawn_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-task-spawn
  swift_task_spawn_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"task-spawn","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-task-spawn"}}'
    swift_task_spawn_rc=124
  elif [ "${swift_task_spawn_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"task-spawn\",\"timed_out\":false,\"rc\":${swift_task_spawn_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-task-spawn\"}}"
  fi
  echo "=== twq swift task spawn probe end ==="
  echo "=== twq swift task spawn stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift task spawn stats after end ==="
  if [ "${swift_task_spawn_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_task_spawn_rc}
  fi
  echo "=== twq swift continuation resume stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift continuation resume stats before end ==="
  echo "=== twq swift continuation resume probe start ==="
  swift_continuation_resume_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-continuation-resume
  swift_continuation_resume_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"continuation-resume","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-continuation-resume"}}'
    swift_continuation_resume_rc=124
  elif [ "${swift_continuation_resume_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"continuation-resume\",\"timed_out\":false,\"rc\":${swift_continuation_resume_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-continuation-resume\"}}"
  fi
  echo "=== twq swift continuation resume probe end ==="
  echo "=== twq swift continuation resume stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift continuation resume stats after end ==="
  if [ "${swift_continuation_resume_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_continuation_resume_rc}
  fi
  echo "=== twq swift spawned continuation stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned continuation stats before end ==="
  echo "=== twq swift spawned continuation probe start ==="
  swift_spawned_continuation_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-spawned-continuation
  swift_spawned_continuation_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"spawned-continuation","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-spawned-continuation"}}'
    swift_spawned_continuation_rc=124
  elif [ "${swift_spawned_continuation_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"spawned-continuation\",\"timed_out\":false,\"rc\":${swift_spawned_continuation_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-spawned-continuation\"}}"
  fi
  echo "=== twq swift spawned continuation probe end ==="
  echo "=== twq swift spawned continuation stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned continuation stats after end ==="
  if [ "${swift_spawned_continuation_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_spawned_continuation_rc}
  fi
  fi
  if swift_probe_should_run "taskgroup-spawned" diagnostic; then
  echo "=== twq swift taskgroup spawned stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup spawned stats before end ==="
  echo "=== twq swift taskgroup spawned probe start ==="
  swift_taskgroup_spawned_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-taskgroup-spawned
  swift_taskgroup_spawned_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"taskgroup-spawned","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-taskgroup-spawned"}}'
    swift_taskgroup_spawned_rc=124
  elif [ "${swift_taskgroup_spawned_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"taskgroup-spawned\",\"timed_out\":false,\"rc\":${swift_taskgroup_spawned_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-spawned\"}}"
  fi
  echo "=== twq swift taskgroup spawned probe end ==="
  echo "=== twq swift taskgroup spawned stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup spawned stats after end ==="
  if [ "${swift_taskgroup_spawned_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_taskgroup_spawned_rc}
  fi
  fi
  if swift_probe_should_run "dispatch-control" validation; then
  echo "=== twq swift dispatch stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatch stats before end ==="
  echo "=== twq swift dispatch probe start ==="
  swift_dispatch_rc=0
  env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatch-control || swift_dispatch_rc=$?
  echo "=== twq swift dispatch probe end ==="
  echo "=== twq swift dispatch stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatch stats after end ==="
  if [ "${swift_dispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatch_rc}
  fi
  fi
  if swift_run_full_unfiltered_diagnostics; then
  echo "=== twq swift taskgroup immediate stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup immediate stats before end ==="
  echo "=== twq swift taskgroup immediate probe start ==="
  swift_taskgroup_immediate_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-taskgroup-immediate
  swift_taskgroup_immediate_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"taskgroup-immediate","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-taskgroup-immediate"}}'
    swift_taskgroup_immediate_rc=124
  elif [ "${swift_taskgroup_immediate_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"taskgroup-immediate\",\"timed_out\":false,\"rc\":${swift_taskgroup_immediate_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-immediate\"}}"
  fi
  echo "=== twq swift taskgroup immediate probe end ==="
  echo "=== twq swift taskgroup immediate stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup immediate stats after end ==="
  if [ "${swift_taskgroup_immediate_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_taskgroup_immediate_rc}
  fi
  echo "=== twq swift taskgroup yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup yield stats before end ==="
  echo "=== twq swift taskgroup yield probe start ==="
  swift_taskgroup_yield_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-taskgroup-yield
  swift_taskgroup_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"taskgroup-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-taskgroup-yield"}}'
    swift_taskgroup_yield_rc=124
  elif [ "${swift_taskgroup_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"taskgroup-yield\",\"timed_out\":false,\"rc\":${swift_taskgroup_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-yield\"}}"
  fi
  echo "=== twq swift taskgroup yield probe end ==="
  echo "=== twq swift taskgroup yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup yield stats after end ==="
  if [ "${swift_taskgroup_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_taskgroup_yield_rc}
  fi
  echo "=== twq swift async sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift async sleep stats before end ==="
  echo "=== twq swift async sleep probe start ==="
  swift_async_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-async-sleep
  swift_async_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"async-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-async-sleep"}}'
    swift_async_sleep_rc=124
  elif [ "${swift_async_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"async-sleep\",\"timed_out\":false,\"rc\":${swift_async_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-sleep\"}}"
  fi
  echo "=== twq swift async sleep probe end ==="
  echo "=== twq swift async sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift async sleep stats after end ==="
  if [ "${swift_async_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_async_sleep_rc}
  fi
  fi
  if swift_probe_should_run "mainqueue-resume" validation; then
  echo "=== twq swift mainqueue resume stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainqueue resume stats before end ==="
  echo "=== twq swift mainqueue resume probe start ==="
  swift_mainqueue_resume_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-mainqueue-resume
  swift_mainqueue_resume_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"mainqueue-resume","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-mainqueue-resume"}}'
    swift_mainqueue_resume_rc=124
  elif [ "${swift_mainqueue_resume_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"mainqueue-resume\",\"timed_out\":false,\"rc\":${swift_mainqueue_resume_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-mainqueue-resume\"}}"
  fi
  echo "=== twq swift mainqueue resume probe end ==="
  echo "=== twq swift mainqueue resume stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainqueue resume stats after end ==="
  if [ "${swift_mainqueue_resume_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_mainqueue_resume_rc}
  fi
  fi
  if swift_run_full_unfiltered_diagnostics; then
  echo "=== twq swift mainactor sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainactor sleep stats before end ==="
  echo "=== twq swift mainactor sleep probe start ==="
  swift_mainactor_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-mainactor-sleep
  swift_mainactor_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"mainactor-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-mainactor-sleep"}}'
    swift_mainactor_sleep_rc=124
  elif [ "${swift_mainactor_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"mainactor-sleep\",\"timed_out\":false,\"rc\":${swift_mainactor_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-mainactor-sleep\"}}"
  fi
  echo "=== twq swift mainactor sleep probe end ==="
  echo "=== twq swift mainactor sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainactor sleep stats after end ==="
  if [ "${swift_mainactor_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_mainactor_sleep_rc}
  fi
  echo "=== twq swift mainactor taskgroup stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainactor taskgroup stats before end ==="
  echo "=== twq swift mainactor taskgroup probe start ==="
  swift_mainactor_taskgroup_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-mainactor-taskgroup
  swift_mainactor_taskgroup_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"mainactor-taskgroup","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-mainactor-taskgroup"}}'
    swift_mainactor_taskgroup_rc=124
  elif [ "${swift_mainactor_taskgroup_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"mainactor-taskgroup\",\"timed_out\":false,\"rc\":${swift_mainactor_taskgroup_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-mainactor-taskgroup\"}}"
  fi
  echo "=== twq swift mainactor taskgroup probe end ==="
  echo "=== twq swift mainactor taskgroup stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift mainactor taskgroup stats after end ==="
  if [ "${swift_mainactor_taskgroup_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_mainactor_taskgroup_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawn" diagnostic; then
  echo "=== twq swift dispatchmain spawn stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawn stats before end ==="
  echo "=== twq swift dispatchmain spawn probe start ==="
  swift_dispatchmain_spawn_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawn
  swift_dispatchmain_spawn_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawn","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawn"}}'
    swift_dispatchmain_spawn_rc=124
  elif [ "${swift_dispatchmain_spawn_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawn\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawn_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawn\"}}"
  fi
  echo "=== twq swift dispatchmain spawn probe end ==="
  echo "=== twq swift dispatchmain spawn stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawn stats after end ==="
  if [ "${swift_dispatchmain_spawn_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawn_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawnwait-yield" diagnostic; then
  echo "=== twq swift dispatchmain spawnwait yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait yield stats before end ==="
  echo "=== twq swift dispatchmain spawnwait yield probe start ==="
  swift_dispatchmain_spawnwait_yield_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-spawnwait-yield
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawnwait-yield
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_spawnwait_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawnwait-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawnwait-yield"}}'
    swift_dispatchmain_spawnwait_yield_rc=124
  elif [ "${swift_dispatchmain_spawnwait_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawnwait-yield\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawnwait_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-yield\"}}"
  fi
  echo "=== twq swift dispatchmain spawnwait yield probe end ==="
  echo "=== twq swift dispatchmain spawnwait yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait yield stats after end ==="
  if [ "${swift_dispatchmain_spawnwait_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawnwait_yield_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawnwait-yield-stockdispatch" diagnostic; then
  echo "=== twq swift dispatchmain spawnwait yield stockdispatch probe start ==="
  swift_dispatchmain_spawnwait_yield_stockdispatch_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_ld} /root/twq-swift-dispatchmain-spawnwait-yield
  swift_dispatchmain_spawnwait_yield_stockdispatch_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawnwait-yield-stockdispatch","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawnwait-yield"}}'
    swift_dispatchmain_spawnwait_yield_stockdispatch_rc=124
  elif [ "${swift_dispatchmain_spawnwait_yield_stockdispatch_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawnwait-yield-stockdispatch\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawnwait_yield_stockdispatch_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-yield\"}}"
  fi
  echo "=== twq swift dispatchmain spawnwait yield stockdispatch probe end ==="
  if [ "${swift_dispatchmain_spawnwait_yield_stockdispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawnwait_yield_stockdispatch_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawnwait-sleep" diagnostic; then
  echo "=== twq swift dispatchmain spawnwait sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait sleep stats before end ==="
  echo "=== twq swift dispatchmain spawnwait sleep probe start ==="
  swift_dispatchmain_spawnwait_sleep_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-spawnwait-sleep
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawnwait-sleep
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_spawnwait_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawnwait-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawnwait-sleep"}}'
    swift_dispatchmain_spawnwait_sleep_rc=124
  elif [ "${swift_dispatchmain_spawnwait_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawnwait-sleep\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawnwait_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain spawnwait sleep probe end ==="
  echo "=== twq swift dispatchmain spawnwait sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait sleep stats after end ==="
  if [ "${swift_dispatchmain_spawnwait_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawnwait_sleep_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawnwait-sleep-stockdispatch" diagnostic; then
  echo "=== twq swift dispatchmain spawnwait sleep stockdispatch probe start ==="
  swift_dispatchmain_spawnwait_sleep_stockdispatch_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_ld} /root/twq-swift-dispatchmain-spawnwait-sleep
  swift_dispatchmain_spawnwait_sleep_stockdispatch_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawnwait-sleep-stockdispatch","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawnwait-sleep"}}'
    swift_dispatchmain_spawnwait_sleep_stockdispatch_rc=124
  elif [ "${swift_dispatchmain_spawnwait_sleep_stockdispatch_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawnwait-sleep-stockdispatch\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawnwait_sleep_stockdispatch_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain spawnwait sleep stockdispatch probe end ==="
  if [ "${swift_dispatchmain_spawnwait_sleep_stockdispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawnwait_sleep_stockdispatch_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawnwait-after" diagnostic; then
  echo "=== twq swift dispatchmain spawnwait after stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait after stats before end ==="
  echo "=== twq swift dispatchmain spawnwait after probe start ==="
  swift_dispatchmain_spawnwait_after_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-spawnwait-after
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawnwait-after
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_spawnwait_after_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawnwait-after","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawnwait-after"}}'
    swift_dispatchmain_spawnwait_after_rc=124
  elif [ "${swift_dispatchmain_spawnwait_after_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawnwait-after\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawnwait_after_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-after\"}}"
  fi
  echo "=== twq swift dispatchmain spawnwait after probe end ==="
  echo "=== twq swift dispatchmain spawnwait after stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawnwait after stats after end ==="
  if [ "${swift_dispatchmain_spawnwait_after_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawnwait_after_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawned-yield" diagnostic; then
  echo "=== twq swift dispatchmain spawned yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawned yield stats before end ==="
  echo "=== twq swift dispatchmain spawned yield probe start ==="
  swift_dispatchmain_spawned_yield_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawned-yield
  swift_dispatchmain_spawned_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawned-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawned-yield"}}'
    swift_dispatchmain_spawned_yield_rc=124
  elif [ "${swift_dispatchmain_spawned_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawned-yield\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawned_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawned-yield\"}}"
  fi
  echo "=== twq swift dispatchmain spawned yield probe end ==="
  echo "=== twq swift dispatchmain spawned yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawned yield stats after end ==="
  if [ "${swift_dispatchmain_spawned_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawned_yield_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-spawned-sleep" diagnostic; then
  echo "=== twq swift dispatchmain spawned sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawned sleep stats before end ==="
  echo "=== twq swift dispatchmain spawned sleep probe start ==="
  swift_dispatchmain_spawned_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-spawned-sleep
  swift_dispatchmain_spawned_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-spawned-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-spawned-sleep"}}'
    swift_dispatchmain_spawned_sleep_rc=124
  elif [ "${swift_dispatchmain_spawned_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-spawned-sleep\",\"timed_out\":false,\"rc\":${swift_dispatchmain_spawned_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawned-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain spawned sleep probe end ==="
  echo "=== twq swift dispatchmain spawned sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain spawned sleep stats after end ==="
  if [ "${swift_dispatchmain_spawned_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_spawned_sleep_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-yield" diagnostic; then
  echo "=== twq swift dispatchmain yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain yield stats before end ==="
  echo "=== twq swift dispatchmain yield probe start ==="
  swift_dispatchmain_yield_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-yield
  swift_dispatchmain_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-yield"}}'
    swift_dispatchmain_yield_rc=124
  elif [ "${swift_dispatchmain_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-yield\",\"timed_out\":false,\"rc\":${swift_dispatchmain_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-yield\"}}"
  fi
  echo "=== twq swift dispatchmain yield probe end ==="
  echo "=== twq swift dispatchmain yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain yield stats after end ==="
  if [ "${swift_dispatchmain_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_yield_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-continuation" diagnostic; then
  echo "=== twq swift dispatchmain continuation stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain continuation stats before end ==="
  echo "=== twq swift dispatchmain continuation probe start ==="
  swift_dispatchmain_continuation_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-continuation
  swift_dispatchmain_continuation_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-continuation","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-continuation"}}'
    swift_dispatchmain_continuation_rc=124
  elif [ "${swift_dispatchmain_continuation_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-continuation\",\"timed_out\":false,\"rc\":${swift_dispatchmain_continuation_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-continuation\"}}"
  fi
  echo "=== twq swift dispatchmain continuation probe end ==="
  echo "=== twq swift dispatchmain continuation stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain continuation stats after end ==="
  if [ "${swift_dispatchmain_continuation_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_continuation_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-sleep" diagnostic; then
  echo "=== twq swift dispatchmain sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain sleep stats before end ==="
  echo "=== twq swift dispatchmain sleep probe start ==="
  swift_dispatchmain_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-sleep
  swift_dispatchmain_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-sleep"}}'
    swift_dispatchmain_sleep_rc=124
  elif [ "${swift_dispatchmain_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-sleep\",\"timed_out\":false,\"rc\":${swift_dispatchmain_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain sleep probe end ==="
  echo "=== twq swift dispatchmain sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain sleep stats after end ==="
  if [ "${swift_dispatchmain_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_sleep_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup stats before end ==="
  echo "=== twq swift dispatchmain taskgroup probe start ==="
  swift_dispatchmain_taskgroup_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup
  swift_dispatchmain_taskgroup_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup"}}'
    swift_dispatchmain_taskgroup_rc=124
  elif [ "${swift_dispatchmain_taskgroup_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup probe end ==="
  echo "=== twq swift dispatchmain taskgroup stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-yield" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup yield stats before end ==="
  echo "=== twq swift dispatchmain taskgroup yield probe start ==="
  swift_dispatchmain_taskgroup_yield_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-yield
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup-yield
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-yield"}}'
    swift_dispatchmain_taskgroup_yield_rc=124
  elif [ "${swift_dispatchmain_taskgroup_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-yield\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-yield\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup yield probe end ==="
  echo "=== twq swift dispatchmain taskgroup yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup yield stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_yield_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-yield-stockdispatch" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup yield stockdispatch probe start ==="
  swift_dispatchmain_taskgroup_yield_stockdispatch_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-yield-stockdispatch
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_ld} /root/twq-swift-dispatchmain-taskgroup-yield
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_yield_stockdispatch_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-yield-stockdispatch","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-yield"}}'
    swift_dispatchmain_taskgroup_yield_stockdispatch_rc=124
  elif [ "${swift_dispatchmain_taskgroup_yield_stockdispatch_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-yield-stockdispatch\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_yield_stockdispatch_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-yield\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup yield stockdispatch probe end ==="
  if [ "${swift_dispatchmain_taskgroup_yield_stockdispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_yield_stockdispatch_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-yield-stockdispatch-customthr" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup yield stockdispatch customthr probe start ==="
  swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-yield-stockdispatch-customthr
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_customthr_ld} /root/twq-swift-dispatchmain-taskgroup-yield
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-yield-stockdispatch-customthr","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-yield"}}'
    swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc=124
  elif [ "${swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-yield-stockdispatch-customthr\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-yield\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup yield stockdispatch customthr probe end ==="
  if [ "${swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_yield_stockdispatch_customthr_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-onesleep" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup onesleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup onesleep stats before end ==="
  echo "=== twq swift dispatchmain taskgroup onesleep probe start ==="
  swift_dispatchmain_taskgroup_onesleep_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-onesleep
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup-onesleep
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_onesleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-onesleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-onesleep"}}'
    swift_dispatchmain_taskgroup_onesleep_rc=124
  elif [ "${swift_dispatchmain_taskgroup_onesleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-onesleep\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_onesleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-onesleep\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup onesleep probe end ==="
  echo "=== twq swift dispatchmain taskgroup onesleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup onesleep stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_onesleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_onesleep_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-sleep" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup sleep stats before end ==="
  echo "=== twq swift dispatchmain taskgroup sleep probe start ==="
  swift_dispatchmain_taskgroup_sleep_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-sleep
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup-sleep
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-sleep"}}'
    swift_dispatchmain_taskgroup_sleep_rc=124
  elif [ "${swift_dispatchmain_taskgroup_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-sleep\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup sleep probe end ==="
  echo "=== twq swift dispatchmain taskgroup sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup sleep stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_sleep_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-sleep-stockdispatch" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup sleep stockdispatch probe start ==="
  swift_dispatchmain_taskgroup_sleep_stockdispatch_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-sleep-stockdispatch
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_ld} /root/twq-swift-dispatchmain-taskgroup-sleep
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_sleep_stockdispatch_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-sleep-stockdispatch","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-sleep"}}'
    swift_dispatchmain_taskgroup_sleep_stockdispatch_rc=124
  elif [ "${swift_dispatchmain_taskgroup_sleep_stockdispatch_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-sleep-stockdispatch\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_sleep_stockdispatch_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup sleep stockdispatch probe end ==="
  if [ "${swift_dispatchmain_taskgroup_sleep_stockdispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_sleep_stockdispatch_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-sleep-stockdispatch-customthr" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup sleep stockdispatch customthr probe start ==="
  swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-sleep-stockdispatch-customthr
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_customthr_ld} /root/twq-swift-dispatchmain-taskgroup-sleep
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-sleep-stockdispatch-customthr","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-sleep"}}'
    swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc=124
  elif [ "${swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-sleep-stockdispatch-customthr\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-sleep\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup sleep stockdispatch customthr probe end ==="
  if [ "${swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_sleep_stockdispatch_customthr_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-after" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup after stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup after stats before end ==="
  echo "=== twq swift dispatchmain taskgroup after probe start ==="
  swift_dispatchmain_taskgroup_after_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-after
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup-after
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_after_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-after","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-after"}}'
    swift_dispatchmain_taskgroup_after_rc=124
  elif [ "${swift_dispatchmain_taskgroup_after_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-after\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_after_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-after\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup after probe end ==="
  echo "=== twq swift dispatchmain taskgroup after stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup after stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_after_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_after_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-after-stockdispatch" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup after stockdispatch probe start ==="
  swift_dispatchmain_taskgroup_after_stockdispatch_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-after-stockdispatch
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_ld} /root/twq-swift-dispatchmain-taskgroup-after
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_after_stockdispatch_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-after-stockdispatch","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-after"}}'
    swift_dispatchmain_taskgroup_after_stockdispatch_rc=124
  elif [ "${swift_dispatchmain_taskgroup_after_stockdispatch_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-after-stockdispatch\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_after_stockdispatch_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-after\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup after stockdispatch probe end ==="
  if [ "${swift_dispatchmain_taskgroup_after_stockdispatch_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_after_stockdispatch_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-after-stockdispatch-customthr" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup after stockdispatch customthr probe start ==="
  swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-after-stockdispatch-customthr
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=${swift_stock_dispatch_customthr_ld} /root/twq-swift-dispatchmain-taskgroup-after
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-after-stockdispatch-customthr","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-after"}}'
    swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc=124
  elif [ "${swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-after-stockdispatch-customthr\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-after\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup after stockdispatch customthr probe end ==="
  if [ "${swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_after_stockdispatch_customthr_rc}
  fi
  fi
  if swift_probe_should_run "dispatchmain-taskgroup-sleep-next" diagnostic; then
  echo "=== twq swift dispatchmain taskgroup sleep next stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup sleep next stats before end ==="
  echo "=== twq swift dispatchmain taskgroup sleep next probe start ==="
  swift_dispatchmain_taskgroup_sleep_next_rc=0
  RUN_WITH_TIMEOUT_LABEL=dispatchmain-taskgroup-sleep-next
  RUN_WITH_TIMEOUT_DIAGNOSTIC=1
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-dispatchmain-taskgroup-sleep-next
  RUN_WITH_TIMEOUT_LABEL=
  RUN_WITH_TIMEOUT_DIAGNOSTIC=0
  swift_dispatchmain_taskgroup_sleep_next_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"dispatchmain-taskgroup-sleep-next","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-dispatchmain-taskgroup-sleep-next"}}'
    swift_dispatchmain_taskgroup_sleep_next_rc=124
  elif [ "${swift_dispatchmain_taskgroup_sleep_next_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"dispatchmain-taskgroup-sleep-next\",\"timed_out\":false,\"rc\":${swift_dispatchmain_taskgroup_sleep_next_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-sleep-next\"}}"
  fi
  echo "=== twq swift dispatchmain taskgroup sleep next probe end ==="
  echo "=== twq swift dispatchmain taskgroup sleep next stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift dispatchmain taskgroup sleep next stats after end ==="
  if [ "${swift_dispatchmain_taskgroup_sleep_next_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_dispatchmain_taskgroup_sleep_next_rc}
  fi
  fi
  if swift_run_full_unfiltered_diagnostics; then
  echo "=== twq swift detached sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift detached sleep stats before end ==="
  echo "=== twq swift detached sleep probe start ==="
  swift_detached_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-detached-sleep
  swift_detached_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"detached-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-detached-sleep"}}'
    swift_detached_sleep_rc=124
  elif [ "${swift_detached_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"detached-sleep\",\"timed_out\":false,\"rc\":${swift_detached_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-detached-sleep\"}}"
  fi
  echo "=== twq swift detached sleep probe end ==="
  echo "=== twq swift detached sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift detached sleep stats after end ==="
  if [ "${swift_detached_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_detached_sleep_rc}
  fi
  echo "=== twq swift detached taskgroup stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift detached taskgroup stats before end ==="
  echo "=== twq swift detached taskgroup probe start ==="
  swift_detached_taskgroup_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-detached-taskgroup
  swift_detached_taskgroup_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"detached-taskgroup","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-detached-taskgroup"}}'
    swift_detached_taskgroup_rc=124
  elif [ "${swift_detached_taskgroup_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"detached-taskgroup\",\"timed_out\":false,\"rc\":${swift_detached_taskgroup_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-detached-taskgroup\"}}"
  fi
  echo "=== twq swift detached taskgroup probe end ==="
  echo "=== twq swift detached taskgroup stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift detached taskgroup stats after end ==="
  if [ "${swift_detached_taskgroup_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_detached_taskgroup_rc}
  fi
  echo "=== twq swift spawned yield stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned yield stats before end ==="
  echo "=== twq swift spawned yield probe start ==="
  swift_spawned_yield_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-spawned-yield
  swift_spawned_yield_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"spawned-yield","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-spawned-yield"}}'
    swift_spawned_yield_rc=124
  elif [ "${swift_spawned_yield_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"spawned-yield\",\"timed_out\":false,\"rc\":${swift_spawned_yield_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-spawned-yield\"}}"
  fi
  echo "=== twq swift spawned yield probe end ==="
  echo "=== twq swift spawned yield stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned yield stats after end ==="
  if [ "${swift_spawned_yield_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_spawned_yield_rc}
  fi
  echo "=== twq swift spawned sleep stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned sleep stats before end ==="
  echo "=== twq swift spawned sleep probe start ==="
  swift_spawned_sleep_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-spawned-sleep
  swift_spawned_sleep_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"spawned-sleep","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-spawned-sleep"}}'
    swift_spawned_sleep_rc=124
  elif [ "${swift_spawned_sleep_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"spawned-sleep\",\"timed_out\":false,\"rc\":${swift_spawned_sleep_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-spawned-sleep\"}}"
  fi
  echo "=== twq swift spawned sleep probe end ==="
  echo "=== twq swift spawned sleep stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift spawned sleep stats after end ==="
  if [ "${swift_spawned_sleep_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_spawned_sleep_rc}
  fi
  echo "=== twq swift taskgroup stats before ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup stats before end ==="
  echo "=== twq swift taskgroup probe start ==="
  swift_taskgroup_rc=0
  run_with_timeout 15 env LD_LIBRARY_PATH=/root/twq-dispatch:/root/twq-swift/usr/lib/swift/freebsd:/root/twq-lib /root/twq-swift-taskgroup-precheck
  swift_taskgroup_rc=${RUN_WITH_TIMEOUT_STATUS}
  if [ "${RUN_WITH_TIMEOUT_TIMED_OUT}" -ne 0 ]; then
    echo '{"kind":"swift-probe","status":"timeout","data":{"mode":"taskgroup","timed_out":true,"timeout_sec":15},"meta":{"component":"swift","binary":"twq-swift-taskgroup-precheck"}}'
    swift_taskgroup_rc=124
  elif [ "${swift_taskgroup_rc}" -ne 0 ]; then
    echo "{\"kind\":\"swift-probe\",\"status\":\"error\",\"data\":{\"mode\":\"taskgroup\",\"timed_out\":false,\"rc\":${swift_taskgroup_rc}},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-precheck\"}}"
  fi
  echo "=== twq swift taskgroup probe end ==="
  echo "=== twq swift taskgroup stats after ==="
  sysctl kern.twq.init_count \
    kern.twq.setup_dispatch_count \
    kern.twq.reqthreads_count \
    kern.twq.thread_enter_count \
    kern.twq.thread_return_count
  echo "=== twq swift taskgroup stats after end ==="
  if [ "${swift_taskgroup_rc}" -ne 0 ] && [ "${probe_failure_rc}" -eq 0 ]; then
    probe_failure_rc=${swift_taskgroup_rc}
  fi
  fi
  if [ "${probe_failure_rc}" -ne 0 ]; then
    exit "${probe_failure_rc}"
  fi
  echo "=== twq probe end ==="
} | tee -a "$log" >/dev/console
/sbin/shutdown -p now
EOF
doas install -m 755 "$tmp_run" "$guest_root/root/run-twq-probe.sh"
rm -f "$tmp_run"

tmp_rc=$(mktemp)
cat > "$tmp_rc" <<'EOF'
#!/bin/sh
#
# PROVIDE: twqprobe
# REQUIRE: LOGIN
# KEYWORD: nojail shutdown

. /etc/rc.subr

name=twqprobe
rcvar=twqprobe_enable
start_cmd="${name}_start"
stop_cmd=":"

twqprobe_start()
{
  /root/run-twq-probe.sh
}

load_rc_config "$name"
: ${twqprobe_enable:=NO}
run_rc_command "$1"
EOF
doas install -m 755 "$tmp_rc" "$guest_root/etc/rc.d/twqprobe"
rm -f "$tmp_rc"

append_if_missing "$guest_root/etc/rc.conf" 'twqprobe_enable="YES"'
append_if_missing "$guest_root/boot/loader.conf" "kernel=\"${kernel_conf}\""
append_if_missing "$guest_root/boot/loader.conf" "module_path=\"/boot/kernel;/boot/modules;/boot/${kernel_conf}\""
append_if_missing "$guest_root/boot/loader.conf" 'console="comconsole"'
append_if_missing "$guest_root/boot/loader.conf" 'boot_multicons="YES"'
append_if_missing "$guest_root/boot/loader.conf" 'autoboot_delay="1"'
