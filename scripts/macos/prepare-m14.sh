#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: prepare-m14.sh [--help]

Environment:
  TWQ_ARTIFACTS_ROOT                     Artifacts root used for derived outputs
  TWQ_MACOS_SWIFT_REPEAT_BIN             Output binary for the Swift dispatchMain repeat lane
  TWQ_MACOS_C_RESUME_REPEAT_BIN          Output binary for the C calibration lane
  TWQ_MACOS_DISPATCH_INTROSPECTION_OBJ   Output object for the macOS dispatch introspection shim
  TWQ_MACOS_SWIFT_REPEAT_SRC             Swift source to compile
  TWQ_MACOS_C_RESUME_REPEAT_SRC          C source to compile
  TWQ_MACOS_DISPATCH_INTROSPECTION_SRC   C source for the macOS dispatch introspection shim
  TWQ_MACOS_SWIFTC                       Swift compiler to use
  TWQ_MACOS_CLANG                        C compiler to use
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
swift_repeat_bin=${TWQ_MACOS_SWIFT_REPEAT_BIN:-${artifacts_root}/macos/bin/twq-swift-dispatchmain-taskhandles-after-repeat}
c_resume_repeat_bin=${TWQ_MACOS_C_RESUME_REPEAT_BIN:-${artifacts_root}/macos/bin/twq-macos-dispatch-resume-repeat}
dispatch_introspection_obj=${TWQ_MACOS_DISPATCH_INTROSPECTION_OBJ:-${artifacts_root}/macos/obj/twq-macos-dispatch-introspection.o}
swift_repeat_src=${TWQ_MACOS_SWIFT_REPEAT_SRC:-${repo_root}/swiftsrc/twq_swift_dispatchmain_taskhandles_after_repeat.swift}
c_resume_repeat_src=${TWQ_MACOS_C_RESUME_REPEAT_SRC:-${repo_root}/csrc/twq_macos_dispatch_resume_repeat.c}
dispatch_introspection_src=${TWQ_MACOS_DISPATCH_INTROSPECTION_SRC:-${repo_root}/csrc/twq_macos_dispatch_introspection.c}
swiftc_bin=${TWQ_MACOS_SWIFTC:-}
clang_bin=${TWQ_MACOS_CLANG:-}
sdk_root=

if command -v xcrun >/dev/null 2>&1; then
  sdk_root=$(xcrun --show-sdk-path 2>/dev/null || true)
fi

if [ -z "$swiftc_bin" ]; then
  if command -v xcrun >/dev/null 2>&1; then
    swiftc_bin=$(xcrun --toolchain XcodeDefault --find swiftc 2>/dev/null || true)
  fi
fi
if [ -z "$swiftc_bin" ] && command -v swiftc >/dev/null 2>&1; then
  swiftc_bin=$(command -v swiftc)
fi
if [ -z "$swiftc_bin" ] || [ ! -x "$swiftc_bin" ]; then
  echo "swiftc not found for macOS M14 build" >&2
  exit 66
fi

if [ -z "$sdk_root" ] || [ ! -d "$sdk_root" ]; then
  echo "macOS SDK not found for M14 build" >&2
  exit 66
fi

if [ -z "$clang_bin" ]; then
  if command -v xcrun >/dev/null 2>&1; then
    clang_bin=$(xcrun --toolchain XcodeDefault --find clang 2>/dev/null || true)
  fi
fi
if [ -z "$clang_bin" ] && command -v clang >/dev/null 2>&1; then
  clang_bin=$(command -v clang)
fi
if [ -z "$clang_bin" ] || [ ! -x "$clang_bin" ]; then
  echo "clang not found for macOS M14 build" >&2
  exit 66
fi

mkdir -p \
  "$(dirname "$swift_repeat_bin")" \
  "$(dirname "$c_resume_repeat_bin")" \
  "$(dirname "$dispatch_introspection_obj")"

"$clang_bin" \
  -O2 \
  -Wall \
  -Wextra \
  -std=c11 \
  -I"${repo_root}/csrc" \
  -isysroot "$sdk_root" \
  -c "$dispatch_introspection_src" \
  -o "$dispatch_introspection_obj"

"$swiftc_bin" \
  -parse-as-library \
  -sdk "$sdk_root" \
  "$swift_repeat_src" \
  "$dispatch_introspection_obj" \
  -o "$swift_repeat_bin"

"$clang_bin" \
  -O2 \
  -Wall \
  -Wextra \
  -std=c11 \
  -I"${repo_root}/csrc" \
  -isysroot "$sdk_root" \
  "$c_resume_repeat_src" \
  "$dispatch_introspection_obj" \
  -o "$c_resume_repeat_bin"

printf 'swift_repeat_bin=%s\n' "$swift_repeat_bin"
printf 'c_resume_repeat_bin=%s\n' "$c_resume_repeat_bin"
printf 'dispatch_introspection_obj=%s\n' "$dispatch_introspection_obj"
