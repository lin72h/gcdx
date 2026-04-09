# FreeBSD Swift 6.3 Toolchain Reference

## Purpose

This is the local reference for using the current FreeBSD Swift 6.3 toolchain
during `pthread_workqueue` / `libdispatch` / Swift integration work.

Use this file instead of rediscovering the correct toolchain root and
environment every time.

## Canonical Host Toolchain

The authoritative installed toolchain root is:

- `/Users/me/wip-rnx/nx-/swift-source-vx-modified/install/rnx-vx-swift63-selfhost-install5/usr`

This is the toolchain to use when the task is:

1. compiling or running Swift locally on the host;
2. validating local FreeBSD Swift 6.3 behavior;
3. building the guest Swift probes for this repo.

Do not silently substitute build-tree binaries when the task is about the
installed toolchain.

## Minimum Environment

```sh
export TOOLCHAIN_USR=/Users/me/wip-rnx/nx-/swift-source-vx-modified/install/rnx-vx-swift63-selfhost-install5/usr
export PATH="$TOOLCHAIN_USR/bin:$PATH"
export LD_LIBRARY_PATH="$TOOLCHAIN_USR/lib/swift/freebsd:$TOOLCHAIN_USR/lib:${LD_LIBRARY_PATH:-}"
```

This is enough for:

1. `swift`
2. `swiftc`
3. `swift build`
4. `swift test`
5. `lldb`

## Extended Environment

If the task touches dispatch headers, `sourcekit-lsp`, mixed C/C++ tooling, or
other include/library-sensitive surfaces, also export:

```sh
export CPATH="$TOOLCHAIN_USR/lib/swift:${CPATH:-}"
export CPLUS_INCLUDE_PATH="$TOOLCHAIN_USR/lib/swift:${CPLUS_INCLUDE_PATH:-}"
export LIBRARY_PATH="$TOOLCHAIN_USR/lib/swift/freebsd:$TOOLCHAIN_USR/lib:${LIBRARY_PATH:-}"
```

## Quick Sanity Check

```sh
export TOOLCHAIN_USR=/Users/me/wip-rnx/nx-/swift-source-vx-modified/install/rnx-vx-swift63-selfhost-install5/usr
export PATH="$TOOLCHAIN_USR/bin:$PATH"
export LD_LIBRARY_PATH="$TOOLCHAIN_USR/lib/swift/freebsd:$TOOLCHAIN_USR/lib:${LD_LIBRARY_PATH:-}"

swiftc --version
swift --version
lldb --version
which swift
which swiftc
which lldb
```

Expected:

1. `swift` and `swiftc` report `Swift version 6.3 (swift-6.3-RELEASE)`;
2. the target is `x86_64-unknown-freebsd15.0`;
3. `which` resolves under the installed toolchain root above.

## Repo Integration Notes

Current repo behavior:

1. [prepare-stage.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/swift/prepare-stage.sh)
   now uses this installed toolchain root by default;
2. the guest Swift lane stages runtime libraries from this toolchain into the
   `bhyve` guest;
3. the guest lane still overrides `libdispatch` and `libthr` with the staged
   TWQ-backed copies, so host-side and guest-side behavior are intentionally
   different.

## Host vs Guest Meaning

Use the host toolchain when you want to answer:

1. "Does FreeBSD Swift 6.3 itself handle this construct?"
2. "Is this probe shape inherently broken on local FreeBSD Swift?"

Use the `TWQDEBUG` guest when you want to answer:

1. "Does this Swift workload run on the staged TWQ-backed `libdispatch` path?"
2. "Does this Swift workload move real `kern.twq.*` counters?"
3. "Is the failure in the staged guest stack rather than in stock Swift 6.3?"

## Current Honest Boundary

Host-side verification during `M12` showed that the stock installed Swift 6.3
toolchain can run all of the current Swift probe entrypoint shapes successfully,
including:

1. top-level `async main` sleep;
2. top-level `TaskGroup`;
3. spawned `Task` wait;
4. `@MainActor` task wait;
5. `dispatchMain()`-rooted task wait;
6. detached task wait.

That matters because it means the remaining Swift failures in the guest are not
automatically "FreeBSD Swift is broken." They are guest staged-stack failures
until proven otherwise.
