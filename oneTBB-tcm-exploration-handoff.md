# oneTBB TCM Exploration Handoff

## Purpose

This note is for a separate sidecar agent that will explore oneTBB's TCM
surface and its relationship to the same problem space as this repo's
`pthread_workqueue` / `libdispatch` effort.

Project name:

1. the main implementation effort in this repo is `GCDX`.

The user's actual intent is stronger than "TCM is an adjacent interesting
runtime":

1. TCM looks close enough to our current kernel/user-space collaboration
   problem that it may benefit our implementation thinking.
2. oneTBB is a real user-space library we likely need to support on this
   platform.
3. oneTBB already has a public TCM-facing glue layer but not a public full TCM
   implementation.
4. that creates an opportunity:
   provide a concrete implementation for the TCM-facing surface on this
   platform, backed by our own work where it makes sense.
5. if we can reuse the same core strategy and machinery we are already
   building for `libdispatch` / `pthread_workqueue`, we reduce duplication and
   make oneTBB support less invasive on our platform.

So the sidecar task is not only:

1. infer what TCM does from the public surface;
2. compare it with TWQ/libdispatch;

It is also:

1. evaluate whether we can provide a platform-specific TCM-compatible service
   surface;
2. evaluate whether oneTBB can benefit from our existing work rather than
   needing a wholly separate resource-coordination stack;
3. identify the most realistic implementation strategies and their risks.

This note is intentionally scoped so the sidecar agent can get productive
without re-learning the main repo's entire history.

## Explicit Mission For The Sidecar Agent

The sidecar agent should treat this as a concrete platform-design task.

The mission is:

1. reverse-engineer the public TCM contract from local oneTBB sources;
2. determine what minimum TCM semantics oneTBB actually depends on;
3. compare those semantics with what our current TWQ/libdispatch work already
   provides;
4. propose whether this platform should:
   - implement a `libtcm.so.1`-compatible service layer,
   - adapt oneTBB more directly to platform facilities,
   - or use a hybrid approach;
5. explain how that choice would let us support oneTBB while reusing as much
   of our existing effort as possible.

## Separation From The Main Lane

This repo's main lane is still:

1. FreeBSD kernel `TWQ` support in `/usr/src`;
2. `libthr` bridge for `_pthread_workqueue_*`;
3. staged `libdispatch` on the real TWQ path;
4. Swift validation as both a product goal and a high-value test vehicle.

The TCM exploration is adjacent, not a replacement.

The sidecar agent should not assume:

1. TCM is automatically the right architectural answer for this repo;
2. TCM should replace kernel-backed workqueue feedback;
3. TCM and `pthread_workqueue` solve the same problem at the same layer.
4. oneTBB must be rewritten around `libdispatch`;
5. a TCM-compatible layer must expose every hidden Intel implementation detail
   to be useful.

The most useful outcome is a clear comparison:

1. what TCM governs;
2. what TWQ governs;
3. where they overlap;
4. where they are complementary;
5. whether a concrete TCM-facing implementation on this platform is practical;
6. how oneTBB support can reuse the existing TWQ/libdispatch effort.

## Current Main-Repo Context

If the sidecar agent needs the main project status, start here:

1. [roadmap.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/roadmap.md)
2. [pthread-workqueue-port-plan.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/pthread-workqueue-port-plan.md)
3. [pthread-workqueue-testing-strategy.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/pthread-workqueue-testing-strategy.md)
4. [swift-integration-rationale.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/swift-integration-rationale.md)
5. [m10-libdispatch-bringup-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m10-libdispatch-bringup-progress.md)
6. [m12-swift-delayed-children-boundary-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m12-swift-delayed-children-boundary-progress.md)

Very short current summary:

1. the kernel-backed TWQ path is real;
2. backpressure into staged `libdispatch` is proven;
3. custom `libthr` is real;
4. the remaining main-lane bug is not the kernel and not raw C dispatch;
5. the current boundary is staged custom `libdispatch` plus Swift async
   interaction for delayed child-task resumptions.

That matters because the sidecar agent should compare TCM against the real
system we already have, not against an outdated idea of the project.

It also means the sidecar should assume there is already a meaningful
concurrency-governance substrate here:

1. kernel-backed admission and narrowing;
2. userland workqueue bridge;
3. dispatch-facing pressure and backpressure;
4. a growing Swift validation lane.

The relevant question is not "can we build a dynamic concurrency system at
all?" We already have one. The real question is whether the TCM surface can be
implemented or adapted in a way that leverages it.

## Local oneTBB Paths To Read First

Use the local clone, not the network.

Start here:

1. [tcm.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm.h)
2. [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp)
3. [tcm_adaptor.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.h)
4. [permit_manager.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/permit_manager.h)
5. [threading_control.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/threading_control.cpp)
6. [market.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/market.cpp)
7. [arena.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/arena.h)
8. [arena.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/arena.cpp)
9. [readme.org](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/rfcs/proposed/coordinate_cpu_resources_use/readme.org)
10. [appendix_B.rst](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/doc/main/tbb_userguide/appendix_B.rst)

These are the most important local facts:

1. `tcm.h` is public and exposes the TCM API surface.
2. `tcm_adaptor.cpp` dynamically loads `libtcm.so.1` and adapts oneTBB to it.
3. the RFC says TCM is a runtime coordination layer for CPU resource sharing.
4. the user guide says TCM is used to avoid oversubscription between runtimes.

## Why This Matters To oneTBB Support

The user intention is explicit:

1. oneTBB is an important user-space library we likely need to support;
2. it already has a public TCM-facing integration layer;
3. on this platform, reusing our existing concurrency and scheduling work is
   preferable to building a second unrelated resource-management system if the
   semantics line up well enough.

That means the sidecar should keep two goals in view at the same time:

1. understand TCM on its own terms;
2. identify the narrowest implementable compatibility surface that would let
   oneTBB benefit from our platform work.

## What TCM Appears To Be

Based on the local public surface, the strongest working model is:

1. TCM is a process-wide CPU resource coordination broker;
2. runtimes connect as clients;
3. each client requests a permit;
4. the permit describes how much concurrency is allowed right now, and
   optionally where it may run;
5. TCM can renegotiate permits asynchronously;
6. the runtime adapts its own worker count to match the granted permit.

That model is strongly supported by the local API and adaptor:

### API evidence

From [tcm.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm.h):

1. `tcmConnect` / `tcmDisconnect`
2. `tcmRequestPermit`
3. `tcmGetPermitData`
4. `tcmIdlePermit`
5. `tcmDeactivatePermit`
6. `tcmActivatePermit`
7. `tcmRegisterThread` / `tcmUnregisterThread`

The permit model has:

1. `concurrencies`
2. `cpu_masks`
3. `state`
4. `flags`

The request model has:

1. `min_sw_threads`
2. `max_sw_threads`
3. `cpu_constraints`
4. `priority`
5. flags including `request_as_inactive`

The state model is explicit:

1. `VOID`
2. `INACTIVE`
3. `PENDING`
4. `IDLE`
5. `ACTIVE`

The flags imply more than simple thread counting:

1. `stale`
2. `rigid_concurrency`
3. `exclusive`
4. `request_as_inactive`

The CPU-constraint model also goes beyond thread budgets:

1. CPU masks
2. NUMA node
3. core type
4. threads-per-core

### Adaptor evidence

From [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp):

1. oneTBB dynamically loads TCM rather than embedding it;
2. it connects with a renegotiation callback;
3. it builds a permit request from arena demand;
4. it calls `tcmRequestPermit(...)`;
5. it later calls `tcmGetPermitData(...)`;
6. it updates oneTBB arena concurrency from the granted permit;
7. it explicitly forces concurrency to zero if the permit state is
   `INACTIVE`, even when a numerical concurrency is present;
8. it registers and unregisters worker threads with TCM.

That is enough to say:

1. the open repo contains the glue and contract;
2. the hidden library contains the actual arbitration engine;
3. the hidden engine is almost certainly not just "thread count accounting."
4. oneTBB is already structurally prepared to speak to an external
   composability service through this API.

## My Current Read Of The Overlap With TWQ

This is the most important part for the sidecar agent.

### Shared problem space

TCM and TWQ both live in the broad space of:

1. avoiding oversubscription;
2. letting a runtime adjust its concurrency dynamically;
3. reacting to changing demand;
4. using feedback rather than static thread counts.

That is why this exploration is relevant.

And that relevance is not abstract. It may enable a concrete support story for
oneTBB on this platform.

### Layer difference

But they operate at different layers.

Our current TWQ work is:

1. kernel-backed;
2. tied to one runtime path at a time through `libthr` / `libdispatch`;
3. focused on worker admission, pressure, narrowing, and scheduling feedback;
4. informed by thread state transitions observed in the kernel.

TCM appears to be:

1. user-space;
2. process-wide;
3. explicitly multi-runtime;
4. focused on budget arbitration between cooperating schedulers;
5. not a scheduler replacement, but a concurrency governor above them.

In one sentence:

1. TWQ is a runtime-to-kernel feedback channel;
2. TCM is a runtime-to-runtime coordination broker.

### Strong analogy points

These mappings are useful, even if they are not exact:

1. TCM permit grant is analogous to the concurrency budget our kernel
   computes for a bucket.
2. TCM renegotiation callback is analogous to our backpressure loop where
   dispatch asks again and narrows when conditions change.
3. TCM `INACTIVE` / `IDLE` / `ACTIVE` state is richer than our current
   request/return/narrow model, but conceptually close to worker demand state.
4. TCM CPU masks and topology constraints are conceptually similar to future
   extensions we do not currently have in TWQ.

### Important non-overlap

These are likely not the same thing:

1. TCM is not obviously a replacement for kernel scheduler hooks.
2. TCM is not obviously a replacement for workqueue worker admission.
3. TCM does not appear to solve direct kernel feedback from blocking threads.
4. TWQ does not solve explicit process-wide coordination between different
   runtimes like oneTBB and OpenMP.

That means the sidecar should compare them as potentially complementary,
not automatically competing.

It also suggests a likely design direction:

1. TWQ may remain the execution-feedback and admission mechanism;
2. a TCM-facing layer, if implemented here, would likely sit above that as a
   policy and coordination service for libraries like oneTBB.

## Concrete Implementation Directions To Evaluate

The sidecar agent should evaluate these implementation directions explicitly,
not just discuss TCM conceptually.

### Option A: `libtcm.so.1` compatibility layer on this platform

Idea:

1. implement the public TCM API ourselves;
2. satisfy oneTBB's dynamic loader path in
   [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp);
3. back it with platform-native policy and signals.

Why this is attractive:

1. oneTBB already expects to dlopen `libtcm.so.1`;
2. this keeps oneTBB changes minimal;
3. the compatibility point is narrow and already defined by [tcm.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm.h).

What the sidecar should determine:

1. how much of the API must be real for oneTBB to benefit;
2. which states and flags oneTBB actually depends on;
3. whether a meaningful first implementation can ignore some advanced policy
   features while still being correct enough.

### Option B: oneTBB-specific platform adaptor

Idea:

1. do not implement `libtcm.so.1` as a general service initially;
2. patch or adapt oneTBB on this platform to use our platform facilities more
   directly.

Why this is less attractive initially:

1. it is more intrusive;
2. it is less reusable for other runtimes;
3. it gives up the advantage of an already-defined public API contract.

But the sidecar should still evaluate it, because:

1. some TCM semantics may not map cleanly onto our current work;
2. a oneTBB-specific adaptor may be the practical phase-1 path even if a
   generic `libtcm` remains a later goal.

### Option C: hybrid approach

Idea:

1. implement the subset of TCM needed by oneTBB first;
2. expose it as a real `libtcm.so.1` service surface;
3. keep the internal implementation platform-specific and backed by our own
   concurrency governor.

This is likely the most promising direction, but the sidecar should justify
that rather than assume it.

## What The Sidecar Agent Should Try To Answer

## What The Sidecar Agent Should Try To Answer

The most valuable questions are not "what is every symbol?" but:

1. What exact problem does TCM solve that TWQ does not?
2. What exact problem does TWQ solve that TCM does not?
3. Is TCM fundamentally policy, while TWQ is fundamentally mechanism?
4. Could a FreeBSD-based system eventually use both:
   kernel workqueue feedback for one runtime and a separate user-space broker
   for multiple runtimes?
5. Does the oneTBB surface imply a portable cross-runtime coordination model
   that could inform future phase-2 design?
6. Can we implement enough of TCM's public contract to support oneTBB
   meaningfully on this platform?
7. If yes, what is the narrowest credible phase-1 implementation?
8. If no, exactly which semantics are the blockers?

More concrete technical questions:

1. What does `permit_manager` abstract inside oneTBB, and how much of that
   abstraction assumes TCM-like semantics?
2. How does oneTBB decide when to call `request_permit`, `deactivate_permit`,
   `register_thread`, and `unregister_thread`?
3. What invariants does oneTBB expect from TCM when concurrency changes?
4. What do `priority`, `exclusive`, and `rigid_concurrency` likely mean in
   practice for arbitration?
5. Are CPU masks and topology constraints advisory or hard from oneTBB's
   point of view?
6. Does oneTBB require TCM to be globally process-wide, or can oneTBB be
   satisfied by a narrower per-process broker implementation?
7. Which calls are required for correctness versus merely for optimization:
   `IdlePermit`, `DeactivatePermit`, `ActivatePermit`, `RegisterThread`,
   `UnregisterThread`, and CPU-mask handling?
8. How should oneTBB's `thread_request_observer` and `permit_manager`
   expectations map onto our current TWQ/libdispatch-driven concurrency model?

## Specific Mapping Questions To Explore

The sidecar agent should try to produce explicit mappings or explicit
"cannot-map-cleanly" statements for:

1. `tcmRequestPermit(min_sw_threads, max_sw_threads)` versus our current
   runtime demand and kernel-computed admission;
2. TCM `ACTIVE` / `IDLE` / `INACTIVE` versus our current worker and demand
   states;
3. TCM renegotiation callback versus our current backpressure and re-check
   loops;
4. TCM `RegisterThread` / `UnregisterThread` versus thread-enter and
   thread-return visibility we already have;
5. TCM CPU masks and topology constraints versus current and possible future
   FreeBSD placement controls;
6. oneTBB arena concurrency updates versus dispatch queue-width / worker-budget
   updates in this repo.

Those mappings are where the real implementation feasibility will become
clear.

## My Suggestions For The Sidecar's Output

The best deliverable would be a reverse-engineered pseudo-spec plus an
implementation recommendation, not just a code tour.

Suggested structure:

1. short statement of what TCM is;
2. function-by-function meaning of the public API;
3. state machine of permit lifecycle;
4. inferred arbitration model and where inference is strong versus weak;
5. how oneTBB uses TCM step by step;
6. direct comparison with this repo's TWQ/libdispatch design;
7. candidate implementation strategies for this platform;
8. recommendation for a phase-1 oneTBB support path;
9. possible implications for future FreeBSD design.

If the sidecar agent wants a concrete skeleton, use:

1. `tcmConnect`: client registration and renegotiation channel
2. `tcmRequestPermit`: demand declaration and initial or renewed grant
3. `tcmGetPermitData`: grant refresh and callback follow-up
4. `tcmIdlePermit` / `tcmDeactivatePermit` / `tcmActivatePermit`: permit state
   transitions
5. `tcmRegisterThread` / `tcmUnregisterThread`: actual worker participation
6. `cpu_constraints`: placement and topology dimension
7. `priority` and flags: policy hints
8. minimum viable TCM subset for oneTBB-on-this-platform
9. what should be backed by existing TWQ/libdispatch work and what cannot

## What I Would Not Spend Time On First

The sidecar agent should avoid low-value rabbit holes initially:

1. do not try to reconstruct the hidden TCM source line by line from nothing;
2. do not start with build-system mechanics;
3. do not assume the RFC means the hidden implementation is already local;
4. do not treat internet PR pages as primary evidence if the local tree
   already contains the relevant RFC and adaptor surface.
5. do not jump straight into "patch oneTBB heavily" before evaluating whether
   the `libtcm.so.1` surface is already the cleaner compatibility point.

The highest-signal path is still:

1. API contract
2. adaptor behavior
3. docs
4. comparison with our current kernel-backed work
5. implementation-feasibility analysis for this platform

## Specific Local Clues Worth Following

These are especially high-value:

1. [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp)
   `actualize_permit()`:
   this is where oneTBB converts a permit into real arena concurrency.
2. [tcm_adaptor.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/tcm_adaptor.cpp)
   `adjust_demand()`:
   this is where oneTBB decides when to renegotiate or deactivate.
3. [threading_control.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/threading_control.cpp):
   this shows where TCM sits in oneTBB's threading-control architecture.
4. [arena.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/arena.h) and
   [arena.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/arena.cpp):
   these show what "update_concurrency" actually means operationally.
5. [readme.org](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/rfcs/proposed/coordinate_cpu_resources_use/readme.org):
   this states the intended TCM model in prose.
6. [appendix_B.rst](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/doc/main/tbb_userguide/appendix_B.rst):
   this states the end-user composition story.
7. [permit_manager.h](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/permit_manager.h):
   this is the abstraction seam oneTBB already uses for resource governance.
8. [threading_control.cpp](/Users/me/wip-gcd-tbb-fx/nx/oneTBB/src/tbb/threading_control.cpp):
   this shows that oneTBB already swaps between a generic market-based permit
   manager and the TCM adaptor depending on what is available.

That last point is especially important:

1. oneTBB already treats TCM as a pluggable permit manager;
2. this strengthens the case for implementing a platform service surface
   rather than trying to redesign oneTBB from scratch.

## My Current Bottom Line

My current working conclusion is:

1. TCM is best understood as a user-space composability governor for multiple
   cooperating runtimes in one process.
2. TWQ is best understood as a kernel-backed concurrency feedback mechanism
   for a specific runtime path.
3. They are related in goal, but not equivalent in layer or responsibility.
4. TCM is probably closer to a policy broker;
5. TWQ is probably closer to an execution feedback and admission mechanism.
6. oneTBB's current architecture makes a TCM-compatible service surface look
   like the cleanest first compatibility target.
7. if we can back that surface with our existing concurrency-governance work,
   we may support oneTBB with much less duplicated machinery.

That is why this sidecar exploration is worth doing:

1. not because TCM replaces our work,
2. but because it may let us reuse and extend our work,
3. support an important library on this platform,
4. and sharpen how we think about multi-runtime coordination,
   process-wide CPU budgeting, and future FreeBSD-native extensions.

## Handback Request To The Sidecar Agent

When the sidecar agent reports back, the most useful answers will be:

1. a concise pseudo-spec for TCM;
2. a direct TCM-versus-TWQ comparison table;
3. a recommendation for whether to implement a platform `libtcm.so.1`
   compatibility layer;
4. the minimum viable TCM feature subset needed for oneTBB support here;
5. a sketch of how that implementation could reuse our current
   `pthread_workqueue` / `libdispatch` effort;
6. explicit statements about what should not be copied from TCM into this
   repo because it lives at the wrong layer.
