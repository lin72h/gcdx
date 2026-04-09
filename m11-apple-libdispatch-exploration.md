# M11 Exploration: Local Apple `libdispatch` Build Boundary

## Outcome

The local Apple open-source `libdispatch` tree under
`../nx/apple-opensource-libdispatch` now:

1. configures successfully on FreeBSD against the staged TWQ-aware pthread
   surface;
2. builds materially further than the original workgroup and Mach header
   failure point;
3. no longer looks blocked on `pthread_workqueue` semantics;
4. is now blocked on broader Darwin-private runtime and portability
   assumptions that are not specific to the workqueue path.

This is the point where the local Apple-tree build stops being the best use of
time for phase 1.

## What Was Proven

### 1. Configure viability is real

The Apple tree accepts the staged FreeBSD pthread surface well enough to
generate build files with:

1. `ENABLE_INTERNAL_PTHREAD_WORKQUEUES=OFF`;
2. staged headers from `../artifacts/pthread-headers`;
3. staged custom `libthr` from `../artifacts/libthr-stage`.

That means the current FreeBSD-side pthread/workqueue shape is already close
enough for the Apple tree to recognize.

### 2. The first blocker was only surface-level

The initial failures were in:

1. missing generic `os/` ABI macros;
2. unconditional workgroup imports pulling in Mach headers;
3. one warning-as-error in `BlocksRuntime`.

Those were exploratory shimmable issues, not evidence that the TWQ bridge was
wrong.

### 3. The second blocker is different in kind

After adding a non-Mach workgroup shim and routing non-Mach internal includes
through it, the build frontier moved. The remaining failures are now centered
around:

1. Apple-private QoS header assumptions;
2. Apple-private lock encoding and thread-id assumptions;
3. Swift-concurrency private interfaces;
4. voucher and other Apple-private helper macro expectations.

That is a much wider problem than `pthread_workqueue`.

## Exploratory Local Patches

The local Apple tree was patched only far enough to expose the real boundary.
Important exploratory edits were made in:

1. `../nx/apple-opensource-libdispatch/os/generic_unix_base.h`
2. `../nx/apple-opensource-libdispatch/os/generic_unix_workgroup.h`
3. `../nx/apple-opensource-libdispatch/os/workgroup.h`
4. `../nx/apple-opensource-libdispatch/os/workgroup_private.h`
5. `../nx/apple-opensource-libdispatch/private/swift_concurrency_private.h`
6. `../nx/apple-opensource-libdispatch/src/internal.h`
7. `../nx/apple-opensource-libdispatch/src/shims/priority.h`

These changes were useful because they proved where the local Apple build stops
being a narrow workqueue exercise.

## Current Compile Boundary

The build now stalls on issues such as:

### 1. QoS/private QoS surface mismatches

Examples:

1. `src/shims/priority.h`
2. `src/shims.h`

The Apple tree expects a particular relationship between:

1. `pthread/qos.h`
2. `pthread/qos_private.h`
3. generated `HAVE_*` feature macros

The staged FreeBSD headers are usable, but the Apple tree’s portability logic
is now depending on details outside the workqueue path.

### 2. Apple-private lock encoding assumptions

Examples:

1. `src/shims/lock.h`
2. `private/swift_concurrency_private.h`

The Apple tree expects a defined lock and thread-id encoding scheme for this
platform. This is not about worker creation or narrowing. It is about broader
private runtime assumptions shared with Swift concurrency and Apple’s internal
locking model.

This is the strongest signal that continuing to force the Apple tree to build
locally would drift into a wider Darwin-compatibility effort.

### 3. Non-workqueue Apple-private helper assumptions

Examples:

1. `os/voucher_private.h`
2. generic helper macros like `__header_always_inline`
3. allocator annotations like `_MALLOC_TYPED`

These are fixable in isolation, but they are not moving the TWQ project
forward in a proportionate way anymore.

## Comparison Against Local Donors

The local `swift-corelibs-libdispatch` tree under
`../nx/swift-corelibs-libdispatch` is now the better donor for FreeBSD-side
portability decisions than the Apple tree itself.

Two useful examples:

1. `../nx/swift-corelibs-libdispatch/src/shims/lock.h`
   already has a FreeBSD lock encoding path;
2. `../nx/swift-corelibs-libdispatch`
   does not drag in the newer Apple-only Swift-concurrency private surface in
   the same way.

This confirms that the Apple tree is now failing for reasons that are broader
than the current project goal.

## Decision

Stop the local Apple-tree build effort here for phase 1.

Reason:

1. further progress would mostly mean porting unrelated Darwin-private runtime
   surface;
2. that work is no longer tightly coupled to `pthread_workqueue`;
3. it would compete with the FreeBSD-native implementation effort rather than
   validate it.

This is a real boundary, not a temporary lack of persistence.

## Recommended Next Step

Use this split going forward:

1. FreeBSD execution lane:
   continue with the staged `swift-corelibs-libdispatch` and the real TWQ-aware
   `libthr` bridge;
2. Apple reference lane:
   treat the Apple open-source tree as a code-reading source and API
   reference, not the immediate local build target;
3. macOS lane:
   use native macOS for canonical behavior comparison when workload matching is
   ready, instead of forcing the Apple tree to build locally through unrelated
   Darwin-private layers.

## macOS Need

macOS is not required to continue productive FreeBSD-side TWQ work right now.

The next good use of the macOS lane is:

1. matched workload comparison against native Apple `libdispatch`;
2. confirming behavior once the FreeBSD lane moves into deeper Swift and
   dispatch validation.

It is not needed to solve the current local Apple-tree build boundary.
