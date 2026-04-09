#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: run-guest.sh [--dry-run] [--help]

Environment:
  TWQ_VM_NAME      Guest name
  TWQ_VM_IMAGE     Guest disk image
  TWQ_VM_VCPUS     Virtual CPU count
  TWQ_VM_MEMORY    Guest memory size
  TWQ_SERIAL_LOG   Serial log path
  TWQ_BHYVE_FLAGS  Extra bhyve flags
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

vm_name=${TWQ_VM_NAME:-twq-dev}
vm_image=${TWQ_VM_IMAGE:-}
vm_vcpus=${TWQ_VM_VCPUS:-4}
vm_memory=${TWQ_VM_MEMORY:-8G}
serial_log=${TWQ_SERIAL_LOG:-}
bhyve_flags=${TWQ_BHYVE_FLAGS:-}

cleanup_cmd="doas bhyvectl --destroy --vm=${vm_name} >/dev/null 2>&1 || true"
load_cmd="doas bhyveload -m ${vm_memory} -d ${vm_image} ${vm_name}"
run_cmd="doas bhyve -AHP ${bhyve_flags} -c ${vm_vcpus} -m ${vm_memory} -l com1,stdio -s 0,hostbridge -s 31,lpc -s 4:0,virtio-blk,${vm_image} ${vm_name}"

if [ "$dry_run" -eq 1 ]; then
  echo "$cleanup_cmd"
  echo "$load_cmd"
  echo "$run_cmd"
  if [ -n "$serial_log" ]; then
    echo "# capture serial output in: ${serial_log}"
  fi
  exit 0
fi

if [ -z "$vm_image" ]; then
  echo "TWQ_VM_IMAGE is required unless --dry-run is used" >&2
  exit 64
fi

trap 'sh -c "$cleanup_cmd"' EXIT INT TERM
sh -c "$cleanup_cmd"
sh -c "$load_cmd"

status=0
if [ -n "$serial_log" ]; then
  mkdir -p -- "$(dirname -- "$serial_log")"
  set -o pipefail
  sh -c "$run_cmd" 2>&1 | tee "$serial_log"
  status=$?
else
  sh -c "$run_cmd"
  status=$?
fi

exit "$status"
