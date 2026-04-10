# oneTBB Integration Strategy

## Purpose

This document records the current strategy for supporting oneTBB on this
FreeBSD-based system and how that strategy relates to the main
`pthread_workqueue` / `libdispatch` effort in this repo.

Project name:

1. the main implementation effort in this repo is `GCDX`.

The important framing is:

1. oneTBB is not just an interesting adjacent library;
2. it is a real user-space library we likely need to support well;
3. the right goal is not to carry an entirely separate concurrency-governance
   world for oneTBB if our platform already has a stronger native direction.

## Current Conclusion

The more usable direction is:

1. oneTBB should benefit from our implementation;
2. our main TWQ / `libdispatch` work should not try to depend on oneTBB's
   hidden TCM implementation.

In plain terms:

1. we already have real mechanism;
2. oneTBB's public TCM surface mostly gives us interface and semantic clues;
3. therefore the platform should provide the implementation and let oneTBB
   consume it.

## Why This Direction Is Stronger

### We already have real mechanism

This repo already has meaningful concurrency-governance machinery:

1. kernel-backed `TWQ` state and admission logic;
2. userland `_pthread_workqueue_*` bridge in `libthr`;
3. staged `libdispatch` running on the real TWQ path;
4. proven dispatch backpressure and narrowing behavior;
5. a growing Swift validation lane.

That means we are not looking for a general idea of how dynamic concurrency
*might* work. We already have a working implementation family.

### oneTBB exposes contract, not the hidden engine

From the local oneTBB tree:

1. [tcm.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm.h)
2. [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp)
3. [tcm_adaptor.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.h)
4. [permit_manager.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/permit_manager.h)
5. [threading_control.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/threading_control.cpp)

What is visible publicly is mainly:

1. the TCM API surface;
2. the adaptor / dynamic-loading glue;
3. the points where oneTBB updates arena concurrency from permit grants.

What is *not* visible publicly is the real hidden TCM arbitration engine.

So there is relatively little implementation to reuse directly from oneTBB for
our core system work. The main value in oneTBB's TCM surface is:

1. API shape;
2. state vocabulary;
3. expectations about resource governance.

## What This Means For Platform Design

The likely clean architecture is:

1. keep oneTBB's scheduler and public semantics;
2. provide a platform-native resource-governance service underneath;
3. let oneTBB consume that service through the narrowest existing seam.

This is better than:

1. trying to rewrite oneTBB around `libdispatch`;
2. or carrying two unrelated dynamic concurrency systems on the same OS.

The design goal should be:

1. one public oneTBB-facing service layer;
2. one coherent platform-native implementation behind it.

## TCM Versus TWQ

The two systems live in a related but not identical problem space.

### TWQ

Our current TWQ work is best understood as:

1. kernel-backed concurrency feedback;
2. runtime-to-kernel interaction;
3. worker admission, pressure tracking, narrowing, and scheduling feedback;
4. execution-oriented mechanism.

### TCM

The oneTBB TCM surface appears to be:

1. user-space;
2. process-wide;
3. aimed at coordination between multiple cooperating runtimes;
4. permit- and callback-driven;
5. policy-oriented concurrency governance above schedulers.

### Working relationship

The best current reading is:

1. TWQ is closer to mechanism;
2. TCM is closer to policy and cross-runtime coordination.

So the likely long-term relationship is not competition but layering:

1. TWQ-like facilities can remain the native execution-feedback mechanism;
2. a TCM-facing surface can sit above that as a coordination layer for
   libraries like oneTBB.

## Preferred Integration Seams

### Option A: `libtcm.so.1` compatibility layer

This is currently the most elegant-looking seam.

Why:

1. oneTBB already dynamically loads `libtcm.so.1`;
2. `tcm_adaptor.cpp` already expects that boundary;
3. the public API contract exists in `tcm.h`;
4. this would keep oneTBB changes minimal on our platform.

If this works, the platform story becomes:

1. oneTBB keeps its normal TCM-facing glue;
2. we provide the service implementation;
3. the service is backed internally by our platform-native concurrency and
   scheduling policy.

### Option B: oneTBB-specific `permit_manager` implementation

This is the fallback seam if the TCM contract turns out too awkward or too
wide for a clean compatibility layer.

Why it exists:

1. [permit_manager.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/permit_manager.h)
   is already the internal abstraction seam;
2. [threading_control.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/threading_control.cpp)
   already switches between the generic market-based path and the TCM adaptor;
3. so oneTBB is structurally prepared for different resource-governance
   backends.

Why it is less attractive as phase 1:

1. it is more intrusive;
2. it is less reusable for other runtimes;
3. it gives up the advantage of an already-defined public service boundary.

### Current recommendation

The recommended order is:

1. evaluate `libtcm.so.1` compatibility first;
2. fall back to a more direct oneTBB-specific seam only if the public TCM
   surface does not map cleanly enough.

## What We Should Reuse From Our Existing Work

The platform should try to reuse:

1. the same general concurrency-governance philosophy already used for TWQ;
2. the same oversubscription-avoidance goals;
3. the same dynamic adjustment mindset rather than static thread caps;
4. the same emphasis on native FreeBSD behavior rather than generic
   portability-first compromise.

The platform should *not* assume oneTBB can directly call into our current
`libdispatch` or `libthr` implementation without a proper adaptor layer.

The correct level of reuse is:

1. policy and mechanism family;
2. internal implementation support;
3. shared observability and testing ideas;

not:

1. forcing oneTBB to become `libdispatch`;
2. or pretending the APIs are interchangeable.

## What We Should Reuse From oneTBB / TCM

The public oneTBB surface still gives us valuable ideas:

1. permit lifecycle vocabulary;
2. `ACTIVE` / `IDLE` / `INACTIVE` state modeling;
3. explicit renegotiation callback model;
4. process-wide coordination framing;
5. CPU/topology constraint vocabulary.

Those are useful as:

1. interface guidance;
2. compatibility targets;
3. phase-2 design inspiration.

They are not enough by themselves to replace our current kernel-backed work.

## Honest Current Bottom Line

The strongest current position is:

1. direct code reuse from oneTBB into our main TWQ implementation is low
   value;
2. semantic and API-surface reuse from TCM is high value;
3. oneTBB benefiting from our implementation is the most promising direction.

If we say it more bluntly:

1. our platform has more usable mechanism;
2. oneTBB exposes more usable interface clues.

That asymmetry is good news.

It means we can aim for:

1. elegant platform-native implementation;
2. minimal unnecessary duplication;
3. oneTBB support without abandoning our current architecture.

## Immediate Questions For Future Work

The next useful technical questions are:

1. what minimum subset of the TCM contract does oneTBB actually require for
   correct operation on this platform?
2. which TCM semantics are essential and which are only optimization hints?
3. can we implement a credible `libtcm.so.1` phase-1 surface using our
   existing concurrency-governance direction?
4. where do TCM permit semantics map cleanly onto our current TWQ-era
   concepts, and where do they not?
5. which oneTBB workloads should become part of our future validation lane?

## Practical Rule For This Repo

Until the sidecar exploration proves otherwise:

1. keep the main TWQ / `libdispatch` lane on its current track;
2. treat TCM as a likely compatibility and coordination surface, not as a
   replacement for the current implementation;
3. design oneTBB support to reuse platform-native machinery underneath rather
   than adding a second unrelated resource-management stack.
