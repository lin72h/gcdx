#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: prepare-stage.sh [--help]

Environment:
  TWQ_ARTIFACTS_ROOT        Artifact root (default: ../artifacts)
  TWQ_LIBDISPATCH_SRC       Local swift-corelibs-libdispatch checkout
  TWQ_LIBDISPATCH_BUILD_DIR Build directory
  TWQ_LIBDISPATCH_PREFIX    Install prefix
  TWQ_LIBDISPATCH_STAGE_DIR Output directory with staged runtime libraries
  TWQ_LIBPTHREAD_STAGE_DIR  Directory containing the staged custom libthr
  TWQ_PTHREAD_HEADERS_DIR   Directory containing staged pthread headers
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
dispatch_src=${TWQ_LIBDISPATCH_SRC:-${repo_root}/../nx/swift-corelibs-libdispatch}
dispatch_build_dir=${TWQ_LIBDISPATCH_BUILD_DIR:-${artifacts_root}/libdispatch-build}
dispatch_prefix=${TWQ_LIBDISPATCH_PREFIX:-${artifacts_root}/libdispatch-prefix}
dispatch_stage_dir=${TWQ_LIBDISPATCH_STAGE_DIR:-${artifacts_root}/libdispatch-stage}
pthread_stage_dir=${TWQ_LIBPTHREAD_STAGE_DIR:-${artifacts_root}/libthr-stage}
pthread_headers_dir=${TWQ_PTHREAD_HEADERS_DIR:-${artifacts_root}/pthread-headers}

if [ ! -d "$dispatch_src" ]; then
  echo "libdispatch source tree not found: $dispatch_src" >&2
  exit 66
fi

if [ ! -f "$pthread_stage_dir/libthr.so.3" ]; then
  echo "staged libthr not found under: $pthread_stage_dir" >&2
  exit 66
fi

if [ ! -f "$pthread_headers_dir/pthread/workqueue_private.h" ]; then
  echo "staged pthread headers not found under: $pthread_headers_dir" >&2
  exit 66
fi

normalize_config_ac() {
  config_ac=$1
  tmp=

  if [ ! -f "$config_ac" ]; then
    return 0
  fi

  tmp="${config_ac}.tmp"
  awk '
    /^#define HAVE_PTHREAD_QOS_H$/ {
      print "#define HAVE_PTHREAD_QOS_H 1"
      next
    }
    /^#define HAVE_PTHREAD_WORKQUEUE_H$/ {
      print "#define HAVE_PTHREAD_WORKQUEUE_H 1"
      next
    }
    /^#define HAVE_PTHREAD_WORKQUEUE_PRIVATE_H$/ {
      print "#define HAVE_PTHREAD_WORKQUEUE_PRIVATE_H 1"
      next
    }
    /^#define HAVE__PTHREAD_WORKQUEUE_INIT$/ {
      print "#define HAVE__PTHREAD_WORKQUEUE_INIT 1"
      next
    }
    { print }
  ' "$config_ac" > "$tmp"
  mv "$tmp" "$config_ac"
}

if [ -f "$dispatch_build_dir/CMakeCache.txt" ]; then
  cached_src=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' \
    "$dispatch_build_dir/CMakeCache.txt")
  if [ -n "$cached_src" ] && [ "$cached_src" != "$dispatch_src" ]; then
    rm -rf "$dispatch_build_dir" "$dispatch_prefix"
  fi
fi

mkdir -p "$dispatch_build_dir" "$dispatch_prefix" "$dispatch_stage_dir"

cmake -S "$dispatch_src" -B "$dispatch_build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$dispatch_prefix" \
  -DENABLE_INTERNAL_PTHREAD_WORKQUEUES=OFF \
  -DBUILD_TESTING=ON \
  -DCMAKE_C_FLAGS="-I${pthread_headers_dir} -Wno-error=implicit-int-conversion -Wno-error=sign-conversion -Wno-error=pointer-bool-conversion -Wno-error=sign-compare" \
  -DCMAKE_CXX_FLAGS="-I${pthread_headers_dir} -Wno-error=implicit-int-conversion -Wno-error=sign-conversion -Wno-error=pointer-bool-conversion -Wno-error=sign-compare" \
  -DCMAKE_EXE_LINKER_FLAGS="-L${pthread_stage_dir} -Wl,-rpath,${pthread_stage_dir}" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L${pthread_stage_dir} -Wl,-rpath,${pthread_stage_dir}" \
  -DCMAKE_REQUIRED_INCLUDES="${pthread_headers_dir}" \
  -DCMAKE_REQUIRED_LIBRARIES="thr;BlocksRuntime" \
  -DHAVE__PTHREAD_WORKQUEUE_INIT:BOOL=ON \
  -DHAVE_PTHREAD_WORKQUEUE_SETDISPATCH_NP:BOOL=ON \
  -DHAVE_PTHREAD_WORKQUEUE_PRIVATE_H:BOOL=ON \
  -DHAVE_PTHREAD_WORKQUEUE_H:BOOL=ON

normalize_config_ac "$dispatch_build_dir/config/config_ac.h"

ninja -C "$dispatch_build_dir" dispatch

cp -f "$dispatch_build_dir/libdispatch.so" "$dispatch_stage_dir/libdispatch.so"
cp -f "$dispatch_build_dir/libBlocksRuntime.so" "$dispatch_stage_dir/libBlocksRuntime.so"
