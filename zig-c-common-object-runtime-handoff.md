# GCDX Zig/C Common Object Runtime Handoff

## Purpose

This note is for the separate sidecar agent that owns the `Zig`/`C`
interoperability lane around:

1. Clang Blocks;
2. C ABI design;
3. object lifetime rules across language boundaries.

This is not the main `GCDX` execution lane. The main lane remains the staged
`libdispatch` delayed-child correctness fix.

The purpose of this side task is narrower:

> Define what a `GCDX` common object runtime should mean at the C ABI layer,
> how it should interact with Blocks and Zig, and where it should stop before
> it turns into a full Objective-C or Foundation portability project.

## Why This Is Assigned To The Zig/C Sidecar

The NextBSD talk uses the phrase "Common Object Runtime" in a way that is
closer to a C-level ownership and object-model substrate than to the full
Objective-C runtime.

At the referenced timestamp, the talk describes it as:

1. `create/delete/retain/release`
2. shared by internal objects like `dispatch_object_t`, `asl_object_t`, and
   `xpc_object_t`
3. a rendezvous point for higher-level languages like ObjC and C++

That is exactly where the Zig/C sidecar is strongest:

1. ABI boundaries;
2. lifetime semantics;
3. header design;
4. block capture behavior;
5. how non-ObjC clients consume system objects safely.

This means the sidecar agent should treat the common object runtime as a
language boundary and ownership problem first, not as an AppKit/Foundation
porting problem.

## Key Conclusion Up Front

The common object runtime should not be treated as "just the Objective-C
runtime."

For `GCDX`, the cleaner target is:

1. a C-first object substrate;
2. optional Objective-C bridging later;
3. optional Swift overlay later;
4. clear interop with Blocks and Zig from day one.

This matches the direction already present in portable `libdispatch` and the
NextBSD `libxpc` code better than any "ObjC everywhere" design.

## What The Local Trees Show

### 1. Portable `libdispatch` already separates object semantics from ObjC

Relevant local file:

1. `../nx/swift-corelibs-libdispatch/os/object.h`

Important local points:

1. objects default to ObjC declarations only when the platform/compiler can
   support that mode;
2. `OS_OBJECT_USE_OBJC=0` is a supported escape hatch;
3. the core model is therefore not inherently tied to ObjC messaging.

That means `dispatch` already expects a world where:

1. object lifetime semantics are fundamental;
2. ObjC exposure is conditional policy, not the underlying truth.

### 2. NextBSD `libxpc` already implements a plain C retained object model

Relevant local files:

1. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc/xpc.h`
2. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc_misc.c`
3. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc_internal.h`
4. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc/base.h`

Important local points:

1. `xpc_object_t` is a plain `void *` when ObjC mode is off;
2. `xpc_retain()` and `xpc_release()` are explicit C entry points;
3. the internal object stores its own type tag and reference count;
4. ObjC bridge macros exist, but the core lifetime machinery is still C.

This is strong evidence that the "common object runtime" idea can be
implemented cleanly without making ObjC a mandatory base layer.

### 3. CoreFoundation is related, but it is not the same layer

Relevant local files:

1. `../nx/ravynos-darwin/Frameworks/CoreFoundation/CFRuntime.h`
2. `../nx/ravynos-darwin/Frameworks/CoreFoundation/CFPropertyList.h`
3. `../nx/ravynos-darwin/Frameworks/CoreFoundation/CFPropertyList.c`
4. `../nx/ravynos-darwin/Frameworks/CoreFoundation/CFBinaryPList.c`
5. `../nx/ravynos-darwin/Docs/SourceMap.md`
6. `../nx/ravynos-darwin/Docs/CONTRIBUTING.md`

Important local points:

1. `CFRuntime` is a real object-runtime substrate with class registration,
   finalization, hashing, equality, formatting, and custom refcount hooks;
2. plist and binary plist live above that layer as serialization of allowed
   value graphs;
3. ravyn itself treats `CoreFoundation` and "Swift CF-Lite" as the place where
   this substrate belongs, not `libobjc`.

For this sidecar task, that means:

1. `CFRuntime` is a useful reference for object-runtime shape;
2. plist/bplist should be treated as an adjacent, higher layer;
3. the sidecar agent should not drift into building all of Foundation.

### 4. BlocksRuntime is now a local donor/reference tree

Relevant local tree:

1. `../nx/swift-corelibs-blocksruntime`

Practical meaning:

1. block copy/dispose and retain/release hooks are now locally inspectable;
2. the sidecar agent should treat this as the reference for how captured
   `GCDX` objects need to behave in block literals and block copies;
3. this is one of the most important local trees for the object-runtime task,
   because block capture is where ownership bugs become visible first.

### 5. Foundation is a reference for the value layer, not the ownership core

Relevant local tree:

1. `../nx/swift-corelibs-foundation`

Practical meaning:

1. it matters for property-list expectations, bridged values, and higher-level
   serialization semantics;
2. it should not define the low-level `GCDX` common object runtime by itself;
3. it is a consumer/reference layer, not the primary owner of this sidecar
   design.

## The Recommended GCDX Layering

The sidecar agent should reason in this order:

### Layer A: Common Object Runtime

This is the actual sidecar scope.

It should define:

1. opaque object handles;
2. reference counting rules;
3. type identity;
4. create/destroy/finalize conventions;
5. thread-safety requirements for retain/release;
6. optional bridge hooks for other languages.

This is where `dispatch_object_t`-style and `xpc_object_t`-style conventions
should converge.

### Layer B: Value Objects

This is adjacent, but not the same task.

It should cover:

1. string;
2. data;
3. number;
4. boolean;
5. date;
6. UUID;
7. array;
8. dictionary;
9. null;
10. optional IPC/system-specific payloads such as fd, shmem, endpoint, or
    mach-port-like placeholders.

These objects may use Layer A for lifetime, but they are a distinct design
question.

### Layer C: plist/bplist

This is above both A and B.

It should cover:

1. XML plist;
2. binary plist;
3. validation rules for which value graphs are plist-safe;
4. conversion APIs and compatibility expectations.

This layer should not dictate the C object ABI.

### Layer D: Language Bridges

This is deliberately optional.

Examples:

1. ObjC bridge;
2. Swift overlay;
3. Zig wrapper layer.

The sidecar agent should assume these are clients of Layer A, not the
definition of Layer A itself.

## Explicit Scope Boundaries For The Sidecar Agent

### In Scope

1. a C-first retained object model for `GCDX`;
2. interaction with Clang Blocks capture/copy/dispose;
3. Zig importability of object headers and ownership APIs;
4. whether `dispatch` and future `xpc`-style objects should share a common
   base header or macro family;
5. whether the common object runtime should resemble `os_object`,
   `xpc_object`, `CFRuntime`, or a hybrid;
6. how to keep ObjC optional instead of mandatory.

### Out Of Scope

1. implementing Foundation;
2. implementing AppKit/Cocoa;
3. making ObjC a required top layer;
4. the kernel `pthread_workqueue`/`TWQ` implementation;
5. full plist/bplist implementation details except where they constrain the
   object/value ABI;
6. broad XPC/launchd semantics beyond what is needed to understand the object
   model.

## Concrete Tasks For The Sidecar Agent

### Task 1: Produce a donor map

Compare these local designs:

1. `../nx/swift-corelibs-libdispatch/os/object.h`
2. `../nx/swift-corelibs-libdispatch/os/object_private.h`
3. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc/xpc.h`
4. `../nx/NextBSD-NextBSD-CURRENT/lib/libxpc/xpc_misc.c`
5. `../nx/ravynos-darwin/Frameworks/CoreFoundation/CFRuntime.h`
6. `../nx/swift-corelibs-blocksruntime`

The output should classify what to:

1. reuse conceptually;
2. simplify;
3. reject;
4. defer.

### Task 2: Define the minimum `GCDX` common object ABI

Answer questions like:

1. Should there be a single base type like `gcdx_object_t`?
2. Should retain/release be always explicit C functions?
3. Should objects expose stable type tags?
4. Should finalizers exist at the base layer?
5. Should the ABI be macro-heavy like `os_object`, or plain-C and explicit?

The sidecar output should prefer something elegant and minimal, not a copied
Darwin compatibility shim.

### Task 3: Define Blocks interaction requirements

Use the local BlocksRuntime tree to answer:

1. what ownership behavior block copy/dispose expects;
2. whether custom retain/release hooks are sufficient;
3. how captured `GCDX` objects should behave in block literals;
4. what test cases are needed for stack block, heap block, nested block, and
   escaping block scenarios.

### Task 4: Define Zig interoperability requirements

Answer:

1. what should Zig see in headers;
2. whether Zig should use plain opaque pointers only;
3. whether block-aware APIs need C wrapper shims;
4. how ownership should be documented for Zig callers;
5. which parts can be imported directly versus wrapped.

### Task 5: Clarify the boundary to plist/bplist

Produce a short architectural note answering:

1. whether plist-safe values should be a subset of the common object runtime;
2. whether binary plist should serialize only value objects, never runtime
   control objects like queues or connections;
3. how far `dispatch_data_t`-like and `xpc_data`-like objects should align.

This task should stay architectural, not implementation-heavy.

## Deliverables Expected From The Sidecar Agent

The sidecar result should ideally produce:

1. a donor comparison note;
2. a proposed `GCDX` common object ABI note;
3. a Blocks interaction note;
4. a Zig import/wrapper note;
5. a short statement on the separation between object runtime and plist/bplist.

## Main Risk To Avoid

Do not let this task collapse into:

1. "port Objective-C runtime first";
2. "port all of CoreFoundation first";
3. "port all of Foundation first".

That would miss the real value.

The right target is smaller and cleaner:

1. define a platform-native C object substrate;
2. make it safe for Blocks;
3. make it consumable from Zig;
4. keep higher layers optional.

## Working Rule For The Sidecar Agent

If a design choice makes the common object runtime more dependent on ObjC than
portable `libdispatch` or NextBSD `libxpc` already require, that choice is
probably moving in the wrong direction.
