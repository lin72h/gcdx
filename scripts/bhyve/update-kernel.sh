#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: update-kernel.sh [--dry-run] [--help]

Environment:
  TWQ_KERNEL_DIR   Built kernel directory to copy from
  TWQ_GUEST_ROOT   Mounted guest root to copy into
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

kernel_dir=${TWQ_KERNEL_DIR:-}
guest_root=${TWQ_GUEST_ROOT:-}
dest_dir="${guest_root}/boot/kernel"

if [ "$dry_run" -eq 1 ]; then
  echo "copy kernel from ${kernel_dir} to ${dest_dir}"
  exit 0
fi

if [ -z "$kernel_dir" ] || [ -z "$guest_root" ]; then
  echo "TWQ_KERNEL_DIR and TWQ_GUEST_ROOT are required unless --dry-run is used" >&2
  exit 64
fi

doas mkdir -p "${dest_dir}"
doas cp -R "${kernel_dir}/." "${dest_dir}/"
