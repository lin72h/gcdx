# TERMINOLOGY

## Purpose

This note defines the terminology used in this repo for comparing:

1. open-source portable `libdispatch` deployments;
2. `GCDX`, the current FreeBSD `TWQ` / `pthread_workqueue` effort;
3. native macOS `libdispatch` and workqueue behavior.

The goal is to stop using vague phrases like:

1. "real dispatch";
2. "native support";
3. "kernel support";
4. "partial support";

without a shared definition.

## Two Separate Axes

There are two different ideas that should not be conflated.

### 1. Platform ownership

This answers:

> Is the implementation shaped as a first-class facility of the platform?

On that axis, our current project is trying to become native to this
FreeBSD-based system, even if it is not yet as complete as macOS.

So "native" by itself is not a good tier name.

### 2. Integration depth

This answers:

> How deeply do Swift / `libdispatch` / the kernel collaborate?

This is the axis that matters for the support spectrum.

The rest of this note defines the tiers on this integration-depth axis.

## The Three Support Tiers

### Tier 0: Portable Dispatch

Definition:

`libdispatch` works as a user-space runtime, but there is no meaningful kernel
workqueue contract shaping worker admission and backpressure.

Typical properties:

1. worker pools are created and managed in user space;
2. concurrency heuristics are inferred in user space;
3. event backends may still be efficient, but worker policy is not
   kernel-directed;
4. compatibility and portability are the main strengths.

Examples:

1. open-source `libdispatch` on Linux without a platform workqueue backend;
2. stock non-TWQ dispatch lanes that do not call `_pthread_workqueue_*`.

Short name:

`portable`

Repo product label:

`libdispatch`

## Tier 1: Kernel-Integrated Dispatch

Definition:

`libdispatch` uses a real kernel-facing workqueue contract for worker requests,
QoS-aware admission, and backpressure, but the full Apple/macOS depth is not
yet present.

Typical properties:

1. user space can request workers from the kernel;
2. the kernel can influence concurrency through admission or narrowing;
3. QoS and pressure are visible across the boundary;
4. worker lifecycle may still be partly user-space-managed;
5. some advanced native-macOS features may still be missing.

Examples:

1. the current staged FreeBSD `TWQ` lane in this repo;
2. any future FreeBSD-native dispatch lane with real kernel feedback but
   without the full macOS workqueue feature set.

Short name:

`kernel-integrated`

Repo product label:

`GCDX`

## Tier 2: Platform-Complete Dispatch

Definition:

The dispatch stack is a first-class, full-stack platform facility with deep
kernel ownership of the worker model and the advanced features expected by the
platform's native runtime stack.

Typical properties:

1. the kernel owns or strongly governs worker lifecycle behavior;
2. dispatch and kernel event delivery are tightly integrated;
3. advanced queue classes and execution modes are first-class concepts;
4. higher-level runtimes inherit these semantics naturally.

For the current project, this tier means "macOS-class completeness", not
"only Apple can ever do this."

Examples:

1. native macOS `libdispatch` plus XNU workqueue support.

Short name:

`platform-complete`

Repo product label:

`GCD`

## Product Naming Used In This Repo

To make design discussions shorter, this repo uses three product-style labels
in addition to the support-tier names.

Project naming rule:

1. the project being built in this repo is named `GCDX`;
2. `GCDX` is not just a tier label, it is the project name going forward.

### `libdispatch`

Use `libdispatch` as the repo-local name for the portable open-source dispatch
implementation.

Meaning in this repo:

1. the open-source baseline;
2. the compatibility-first or portability-first implementation family;
3. the Tier 0 reference point on the left side of the spectrum.

Typical examples:

1. open-source `swift-corelibs-libdispatch`;
2. Linux deployments without a real kernel workqueue contract;
3. any stock dispatch runtime that is not actually using our `TWQ` path.

### `GCDX`

Use `GCDX` as the repo-local name for our FreeBSD-based, kernel-integrated
dispatch effort and as the project name for this repo.

Meaning in this repo:

1. starts from `libdispatch`;
2. adds real kernel-facing workqueue semantics;
3. targets a FreeBSD-native implementation;
4. moves the platform from Tier 0 toward Tier 2.

So `GCDX` is the middle ground:

1. more than portable `libdispatch`;
2. not yet macOS-complete `GCD`.

### `GCD`

Use `GCD` as the repo-local name for the platform-complete macOS reference
implementation.

Meaning in this repo:

1. Apple's Grand Central Dispatch as it exists with XNU workqueue support;
2. the Tier 2 reference point on the right side of the spectrum;
3. the behavioral target for features that make sense to inherit.

## Naming Map

This gives us a compact naming map:

1. `libdispatch` = Tier 0 = portable
2. `GCDX` = Tier 1 = kernel-integrated
3. `GCD` = Tier 2 = platform-complete

Or visually:

1. `libdispatch` -> `GCDX` -> `GCD`

That is the preferred shorthand for talking about project direction.

## Mapping The Current Three Reference Points

### Left side of the spectrum

Open-source `libdispatch` on Linux, without a true platform workqueue contract:

1. support tier: `portable`
2. shorthand: Tier 0
3. repo product label: `libdispatch`

### Middle of the spectrum

The current FreeBSD `TWQ` effort:

1. support tier: `kernel-integrated`
2. shorthand: Tier 1
3. repo product label: `GCDX`

Important nuance:

This does not mean "half-broken" or "fake native."

It means:

1. the platform has crossed from compatibility-only dispatch into real
   kernel-informed dispatch;
2. the stack is not yet as deep or complete as macOS.

### Right side of the spectrum

Native macOS:

1. support tier: `platform-complete`
2. shorthand: Tier 2
3. repo product label: `GCD`

## Why These Names Are Better

### Why not just say "native"?

Because our goal is to become native to this FreeBSD-based operating system
too.

If "native" is reserved only for macOS, the wording incorrectly implies that
everything else is permanently foreign or second-class.

### Why not say "partial"?

Because "partial" hides an important distinction.

A system with real kernel backpressure and worker admission is not merely a
partial version of a compatibility library. It has crossed an architectural
boundary.

The relevant distinction is not:

1. complete;
2. incomplete.

It is:

1. portable;
2. kernel-integrated;
3. platform-complete.

## The Three Architectural Layers

The support tier describes the whole stack, but it is still useful to refer to
the layers separately.

### Layer A: Client / Runtime Layer

Examples:

1. Swift concurrency;
2. user-space runtimes such as oneTBB;
3. applications using dispatch queues directly.

### Layer B: Dispatch Layer

Examples:

1. `libdispatch`;
2. `libthr` bridge code that exposes the workqueue SPI;
3. queueing, delayed execution, and worker request logic.

### Layer C: Kernel Policy Layer

Examples:

1. `TWQ`;
2. `pthread_workqueue`-style ABI;
3. scheduler feedback, QoS-aware admission, narrowing, and thread policy.

This gives us a clean way to say things like:

1. "Swift is a Layer A consumer validating a Tier 1 stack."
2. "The current bug appears in Layer A but likely belongs to Layer B."
3. "Linux portable dispatch has Layer B without a strong Layer C contract."

## How To Use These Terms In Project Docs

Recommended wording:

1. say `portable dispatch` for the user-space-only or mostly user-space-only
   lane;
2. say `kernel-integrated dispatch` for the current FreeBSD `TWQ` target;
3. say `platform-complete dispatch` when using macOS as the reference point;
4. use `macOS-complete` when the comparison is explicitly about Apple parity;
5. use `FreeBSD-native` only for platform ownership, not for support depth;
6. use `libdispatch`, `GCDX`, and `GCD` as the compact spectrum labels.

## Current Project Interpretation

The current project goal is not:

1. immediate Tier 2 parity with macOS in every feature.

The current practical goal is:

1. deliver a robust Tier 1 `kernel-integrated` dispatch implementation;
2. make it clearly better than Tier 0 `portable` dispatch for real workloads;
3. then move selectively toward Tier 2 features where they fit the
   FreeBSD-based design naturally.

## Bottom Line

Use this spectrum going forward:

1. Tier 0: `portable`
2. Tier 1: `kernel-integrated`
3. Tier 2: `platform-complete`

Mapped to the current reference systems:

1. Linux open-source `libdispatch` without kernel workqueue support:
   `libdispatch` = Tier 0
2. our current FreeBSD `TWQ` effort:
   `GCDX` = Tier 1
3. native macOS `libdispatch` plus XNU workqueue:
   `GCD` = Tier 2
