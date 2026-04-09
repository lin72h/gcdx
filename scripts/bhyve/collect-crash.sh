#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: collect-crash.sh [--dry-run] [--help]

Environment:
  TWQ_CRASH_SOURCE   Directory containing dumps or savecore output
  TWQ_CRASH_DEST     Destination directory for copied crash artifacts
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

crash_source=${TWQ_CRASH_SOURCE:-}
crash_dest=${TWQ_CRASH_DEST:-}

if [ "$dry_run" -eq 1 ]; then
  echo "collect crash from ${crash_source} into ${crash_dest}"
  exit 0
fi

if [ -z "$crash_source" ] || [ -z "$crash_dest" ]; then
  echo "TWQ_CRASH_SOURCE and TWQ_CRASH_DEST are required unless --dry-run is used" >&2
  exit 64
fi

doas mkdir -p "${crash_dest}"
doas cp -R "${crash_source}/." "${crash_dest}/"
