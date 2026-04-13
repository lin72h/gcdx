#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: prepare-stage.sh [--help]

Environment:
  TWQ_LIBPTHREAD_MANUAL_SO   Custom libthr shared object to stage
  TWQ_LIBPTHREAD_OBJDIR      libthr objdir used to relink the manual shared object
  TWQ_LIBPTHREAD_LIBC_OBJDIR libc objdir used for the manual relink
  TWQ_LIBPTHREAD_RELINK      Relink libthr.so.3.full.manual before staging (default: 1)
  TWQ_LIBPTHREAD_STAGE_DIR   Output directory with runtime symlinks
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

choose_default_manual_so() {
  latest_pico=$(find /tmp/twqlibobj -type f -path '*/lib/libthr/thr_workq.pico' \
    -exec stat -f '%m %N' {} \; 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
  if [ -n "${latest_pico}" ]; then
    printf '%s/libthr.so.3.full.manual\n' "$(dirname "${latest_pico}")"
  else
    printf '%s\n' /tmp/twqlibobj/usr/src/amd64.amd64/lib/libthr/libthr.so.3.full.manual
  fi
}

manual_so=${TWQ_LIBPTHREAD_MANUAL_SO:-$(choose_default_manual_so)}
manual_objdir=${TWQ_LIBPTHREAD_OBJDIR:-$(dirname "$manual_so")}
stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${repo_root}/../artifacts/libthr-stage}
relink_manual=${TWQ_LIBPTHREAD_RELINK:-1}
should_relink=0

case "$manual_objdir" in
  */lib/libthr)
    default_libc_objdir=${manual_objdir%/lib/libthr}/lib/libc
    ;;
  *)
    default_libc_objdir=
    ;;
esac

libc_objdir=${TWQ_LIBPTHREAD_LIBC_OBJDIR:-$default_libc_objdir}

relink_manual_so() {
  (
    cd "$manual_objdir"
    if [ -n "$libc_objdir" ] && [ -d "$libc_objdir" ]; then
      cc -Wl,-znodelete -Wl,-zinitfirst -Wl,--auxiliary,libsys.so.7 \
        -Wl,-zrelro -Wl,--version-script=Version.map \
        -Wl,--no-undefined-version -shared -Wl,-x \
        -Wl,--fatal-warnings -Wl,--warn-shared-textrel \
        -o "$manual_so" -Wl,-soname,libthr.so.3 \
        ./*.pico -L"$libc_objdir" -lc /lib/libsys.so.7
    else
      cc -Wl,-znodelete -Wl,-zinitfirst -Wl,--auxiliary,libsys.so.7 \
        -Wl,-zrelro -Wl,--version-script=Version.map \
        -Wl,--no-undefined-version -shared -Wl,-x \
        -Wl,--fatal-warnings -Wl,--warn-shared-textrel \
        -o "$manual_so" -Wl,-soname,libthr.so.3 \
        ./*.pico -lc /lib/libsys.so.7
    fi
  )
}

if [ "$relink_manual" != "0" ] &&
  [ -d "$manual_objdir" ] &&
  [ -f "$manual_objdir/Version.map" ] &&
  [ -f "$manual_objdir/thr_workq.pico" ]; then
  if [ ! -f "$manual_so" ]; then
    should_relink=1
  elif [ "$manual_objdir/Version.map" -nt "$manual_so" ]; then
    should_relink=1
  elif find "$manual_objdir" -maxdepth 1 -name '*.pico' ! -name '.depend.*' \
    -newer "$manual_so" | grep -q .; then
    should_relink=1
  fi
fi

if [ "$should_relink" -eq 1 ]; then
  echo "Refreshing staged libthr from ${manual_objdir}" >&2
  relink_manual_so
fi

if [ ! -f "$manual_so" ]; then
  echo "Custom libthr shared object not found: $manual_so" >&2
  exit 66
fi

mkdir -p "$stage_dir"
stage_dir=$(CDPATH= cd -- "$stage_dir" && pwd)

cp -f "$manual_so" "$stage_dir/libthr.so.3"
ln -sf libthr.so.3 "$stage_dir/libthr.so"
ln -sf libthr.so.3 "$stage_dir/libpthread.so"
