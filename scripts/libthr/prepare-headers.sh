#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: prepare-headers.sh [--help]

Environment:
  TWQ_PTHREAD_HEADERS_DIR  Output directory for staged pthread_workqueue headers
  TWQ_FREEBSD_SRC_ROOT     FreeBSD source tree root containing include/ headers
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
src_root=${TWQ_FREEBSD_SRC_ROOT:-/usr/src}
headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${repo_root}/../artifacts/pthread-headers}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Required header not found: $1" >&2
    exit 66
  fi
}

require_file "${src_root}/include/pthread/qos.h"
require_file "${src_root}/include/pthread/qos_private.h"
require_file "${src_root}/include/pthread/workqueue_private.h"
require_file "${src_root}/include/pthread_workqueue.h"

mkdir -p "${headers_dir}/pthread"
cp -f "${src_root}/include/pthread/qos.h" "${headers_dir}/pthread/qos.h"
cp -f "${src_root}/include/pthread/qos_private.h" "${headers_dir}/pthread/qos_private.h"
cp -f "${src_root}/include/pthread/workqueue_private.h" \
  "${headers_dir}/pthread/workqueue_private.h"
cp -f "${src_root}/include/pthread_workqueue.h" \
  "${headers_dir}/pthread_workqueue.h"
