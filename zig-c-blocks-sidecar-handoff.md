# GCDX Zig/C Blocks Sidecar Handoff

## Purpose

This note is for a separate sidecar agent that will explore Zig/C support for
Clang Blocks and how that can benefit `GCDX`.

There is now a second dedicated handoff for the adjacent object-model task:

1. `zig-c-common-object-runtime-handoff.md`

Read that document as the companion scope for:

1. C-first object lifetime semantics;
2. `dispatch`/`xpc`-style retain-release conventions;
3. how a future `GCDX` common object runtime should intersect with Blocks,
   Zig, and foreign-language boundaries.

This is not the main `GCDX` execution lane. The current main lane remains the
Tier 1 staged-`libdispatch` delayed-child fix.

The point of this side task is to answer a narrower question:

> Can better Zig/C support for Clang Blocks help `GCDX` expose a more canonical
> dispatch API surface and a stronger client/testing story?

## Why This Matters To GCDX

`GCDX` currently proves the kernel-integrated dispatch path mostly through:

1. C probes using the `_f` dispatch APIs;
2. Zig low-level syscall and workqueue probes;
3. Swift integration probes.

That is enough for the current Tier 1 bring-up work, but it leaves an
important gap:

Most canonical `libdispatch` user-facing APIs are block-based, not `_f`-based.

Examples in the local `swift-corelibs-libdispatch` tree include:

1. `dispatch_async(...)`
2. `dispatch_group_async(...)`
3. `dispatch_after(...)`
4. `dispatch_barrier_async(...)`
5. `dispatch_block_create(...)`

Those APIs are exposed only when `__BLOCKS__` is available in the C frontend.

So better Blocks support matters for `GCDX` in at least three ways:

1. it could let us write C probes that are closer to the canonical dispatch API
   surface instead of staying on `_f` callbacks only;
2. it could let Zig-based tooling interact with block-aware C headers more
   naturally;
3. it could improve the platform story for user-space clients that want a more
   Apple-like dispatch experience.

## Important Current GCDX State

### 1. We already ship `BlocksRuntime` in the staged dispatch lane

Relevant local files:

1. `scripts/libdispatch/prepare-stage.sh`
2. `scripts/swift/prepare-stage.sh`
3. `scripts/bhyve/stage-guest.sh`

Current meaning:

1. the staged dispatch runtime copies `libBlocksRuntime.so`;
2. the staged Swift runtime also carries `libBlocksRuntime.so`;
3. the guest lane is already aware that block runtime support exists as a real
   runtime artifact.

So the missing piece is not "does the runtime library exist at all?".

The missing piece is more likely:

1. frontend support;
2. translation support;
3. clean integration into Zig/C test clients.

### 2. Our current C dispatch probe deliberately avoids Blocks syntax

Relevant local file:

1. `csrc/twq_dispatch_probe.c`

Current usage:

1. `dispatch_group_async_f(...)`
2. `dispatch_async_f(...)`
3. `dispatch_after_f(...)`

This is deliberate and important.

It means:

1. current `GCDX` dispatch validation does not depend on Clang Blocks syntax;
2. a new Blocks-enabled C/Zig lane would be a genuine new capability, not a
   duplicate of the current probe path.

### 3. Our current Zig lane does not yet validate block-based dispatch clients

Relevant local files:

1. `zig/build.zig`
2. `zig/README.md`
3. `elixir/lib/twq_test/zig.ex`

Current meaning:

1. Zig is already used for raw syscall probes, ABI checks, and low-level
   workqueue tests;
2. the userland dispatch probe is currently compiled in C with `cc`, not with a
   Zig-based Blocks-aware lane;
3. the current repo therefore does not answer whether Zig can participate in a
   canonical block-based dispatch client story.

### 4. A local Zig development toolchain is available

Verified local paths:

1. binary: `/usr/local/bin/zig-dev`
2. library root: `/usr/local/lib/zig-dev`

Verified local version:

1. `0.16.0-dev.3133+5ec8e45f3`

This matters because the local `arocc` PR trees already declare a Zig `0.16`
development-series requirement.

Practical meaning for the sidecar task:

1. prefer `/usr/local/bin/zig-dev` for `arocc` exploration and any Zig-driven
   Blocks experiments;
2. do not assume the repo's older verified Zig usage is sufficient for this
   sidecar lane;
3. when results differ between the repo's older Zig expectations and
   `zig-dev`, treat `zig-dev` as the more relevant lane for the `arocc`
   exploration.

## Why Blocks Matter Specifically For `libdispatch`

In the local `swift-corelibs-libdispatch` headers:

1. `dispatch/object.h`
2. `dispatch/queue.h`
3. `dispatch/group.h`
4. `dispatch/block.h`

many public APIs are guarded by `#ifdef __BLOCKS__`.

Examples:

1. `dispatch_async(queue, block)`
2. `dispatch_sync(queue, block)`
3. `dispatch_after(when, queue, block)`
4. `dispatch_group_async(group, queue, block)`
5. `dispatch_block_create(flags, block)`

This means a frontend that cannot parse or expose block types and block
literals leaves clients on the less-canonical `_f` function-pointer APIs.

That is acceptable for Tier 1 bring-up.

It is not the best long-term client story for `GCDX`.

## Local Trees For The Sidecar Agent

### GCDX repo

Primary repo:

1. `./`

Relevant local files:

1. `csrc/twq_dispatch_probe.c`
2. `csrc/twq_workqueue_probe.c`
3. `zig/build.zig`
4. `zig/src/twq_probe_stub.zig`
5. `zig/src/twq_workqueue_probe.zig`
6. `elixir/lib/twq_test/zig.ex`
7. `scripts/libdispatch/prepare-stage.sh`
8. `scripts/swift/prepare-stage.sh`
9. `scripts/bhyve/stage-guest.sh`

### `libdispatch` tree

Reference tree:

1. `../nx/swift-corelibs-libdispatch`

Most relevant files:

1. `dispatch/object.h`
2. `dispatch/queue.h`
3. `dispatch/group.h`
4. `dispatch/block.h`

### Aro/aroCC block-support trees

Relevant local checkouts:

1. `../nx/arocc-pr969`
2. `../nx/arocc-pr971`

Current local branch state:

1. `../nx/arocc-pr969`
   - branch: `dotcarmen/block-types`
   - head: `512dc78`
2. `../nx/arocc-pr971`
   - branch: `dotcarmen/block-literals`
   - head: `5ff5ed9`

Toolchain fit:

1. the local `arocc` trees declare a minimum Zig version of
   `0.16.0-dev.3006+94355f192`;
2. the installed `/usr/local/bin/zig-dev` at
   `0.16.0-dev.3133+5ec8e45f3` is new enough to satisfy that baseline.

## What The Two Local Aro PR Trees Appear To Add

## PR 969: Block Type Support

Local tree:

1. `../nx/arocc-pr969`

Most relevant local files:

1. `src/aro/Driver.zig`
2. `src/aro/LangOpts.zig`
3. `src/aro/Parser.zig`
4. `src/aro/Parser/Diagnostic.zig`
5. `src/aro/TypeStore.zig`
6. `test/cases/block types.c`
7. `test/cases/ast/block types.c`

Current reading:

1. adds `-fblocks` driver support;
2. adds block type representation in the type system;
3. adds parser support for block pointer types;
4. adds diagnostics such as:
   - `blocks are not enabled`
   - `blocks are a Clang extension`
   - `block pointer to non-function type is invalid`
5. adds tests for block typedefs, block-pointer typing, casts, coercion, and
   AST printing.

This looks like:

1. type-level support for Blocks;
2. not yet full literal/capture support by itself.

## PR 971: Block Literals and `__block`

Local tree:

1. `../nx/arocc-pr971`

Most relevant local files:

1. `src/aro/Parser.zig`
2. `src/aro/Parser/Diagnostic.zig`
3. `src/aro/Tokenizer.zig`
4. `src/aro/Tree.zig`
5. `src/aro/Value.zig`
6. `src/backend/Interner.zig`
7. `test/cases/block literals.c`
8. `test/cases/ast/block literals.c`

Current reading:

1. builds on the block-type work;
2. adds parser-level support for block literals;
3. adds support for `__block` variables in the parser/AST layer;
4. models block captures and block literal AST nodes.

The AST test output is especially useful because it shows:

1. block literals;
2. captured variables;
3. `__block` storage variables;
4. nested blocks;
5. block invocation typing.

This looks like:

1. parser and AST support for real block expressions;
2. not yet proven full end-to-end codegen/runtime integration.

## Important Interpretation For The Sidecar Agent

Do not assume these PRs already give:

1. complete code generation for blocks;
2. complete ABI lowering for block invocation and capture layout;
3. seamless `zig translate-c` support for all block-heavy headers;
4. a finished Zig user story.

What they clearly give is:

1. meaningful frontend progress;
2. a much better foundation for parsing block-aware C APIs and test sources.

The sidecar task must determine how far that actually reaches.

## What The Sidecar Agent Should Figure Out

The mission is to answer these questions concretely.

### 1. Frontend capability

Determine exactly what the local `arocc` PR trees can already handle:

1. block typedefs;
2. block pointer declarations;
3. block literals;
4. captures;
5. `__block` variables;
6. nested blocks;
7. calls through block variables.

### 2. Dispatch header viability

Determine whether those trees are enough to consume the `libdispatch` public
headers in a useful way when `__BLOCKS__` is enabled.

The practical target is not "all Clang Blocks semantics in the world."

The practical target is:

1. can a block-aware frontend meaningfully parse the block-based `dispatch/*`
   APIs that matter to `GCDX`?

### 3. Zig story

Determine what "Zig support" actually means here.

Possible meanings:

1. Zig can invoke a C compiler path that supports `-fblocks`;
2. Zig can consume translated block-aware C declarations;
3. Zig can interoperate with block-based dispatch APIs through extern surfaces;
4. Zig can compile small C-with-blocks helpers as part of a Zig build;
5. Zig can directly express or call block literals in some usable form.

Do not assume these are all the same problem.

### 4. Runtime viability

Determine what runtime is needed for actual execution:

1. `libBlocksRuntime.so`
2. compile flags like `-fblocks`
3. any target-specific conditions or header defines

`GCDX` already stages `libBlocksRuntime.so`, so the question is:

1. what extra frontend/build glue is still needed to make a block-based client
   path practical?

### 5. Testing value for `GCDX`

Determine whether this side path can produce high-value new tests for `GCDX`.

The strongest candidates are:

1. a canonical block-based C dispatch probe;
2. a Zig-driven build of a C-with-blocks dispatch client;
3. header-compatibility tests proving block-aware `dispatch/*` surfaces are
   usable on this platform.

## Suggested First Experiments

### Experiment 1: Minimal block-based C dispatch program

Write or stage a tiny C program that uses:

1. `dispatch_async(...)`
2. `dispatch_group_async(...)`
3. `dispatch_after(...)`

with real block syntax and the staged `GCDX` dispatch runtime.

The purpose is to verify:

1. the basic compile+link story with `BlocksRuntime`;
2. the basic execution story against staged `libdispatch`.

### Experiment 2: Same program via Zig-owned build orchestration

Try to build the same C-with-blocks client through a Zig-controlled path.

This may mean:

1. `/usr/local/bin/zig-dev cc -fblocks ...`
2. a build.zig step invoking an external compiler path
3. or an Aro-based path if that is already usable locally

The question is not elegance first.

The first question is:

1. can Zig be the build/orchestration layer for block-aware C dispatch clients?

### Experiment 3: Header-consumption viability

Pick a minimal dispatch header set and determine whether the `arocc` PRs can
parse enough of it under `-fblocks` to be useful.

Start small:

1. `dispatch/object.h`
2. `dispatch/queue.h`
3. `dispatch/group.h`
4. `dispatch/block.h`

### Experiment 4: Decide whether this helps the main repo

At the end of the first pass, answer:

1. should `GCDX` add a block-based C probe lane soon?
2. should `GCDX` add a Zig-driven C-with-blocks probe lane soon?
3. or is this still too immature and should remain exploration only?

## Boundaries

This sidecar task should not:

1. distract the main repo from M12;
2. require kernel changes;
3. require staged `libdispatch` semantic changes;
4. turn into a general-purpose Aro compiler project;
5. assume that block support in the frontend automatically means production
   quality for `GCDX`.

This task is successful if it clarifies:

1. what is possible now;
2. what is missing;
3. what is worth integrating later.

## Deliverables Expected From The Sidecar Agent

The sidecar agent should ideally return:

1. a capability map:
   - block types
   - block literals
   - `__block`
   - header parsing
   - translation
   - linking/runtime
2. a recommendation:
   - integrate soon
   - keep as exploratory
   - or defer completely
3. one or more tiny concrete repro programs or build recipes;
4. a clear statement of whether this improves the `GCDX` testing/client story
   materially.

## Bottom Line

The sidecar thesis is:

1. `GCDX` already has a real staged dispatch runtime with `BlocksRuntime`
   present;
2. its current probes deliberately avoid Blocks and stay on `_f` APIs;
3. the local Aro PRs look like the first serious path toward better block-aware
   Zig/C frontend support;
4. if that support is real enough, it could give `GCDX` a more canonical
   block-based C/Zig client and testing lane.

That is worth exploring, but it is a sidecar task, not the current critical
path.
