# M13.5 Crossover Boundary

## Purpose

This document closes the open-ended part of `M13` after the durable wins and
the `M14` macOS stop result.

It is meant to answer one practical question:

1. what is stable enough to treat as current GCDX behavior;
2. what is intentionally frozen;
3. what is explicitly deferred.

This is not a speculative design note. It is the implementation boundary after
the current `M13` and `M14` work.

## Stable Now

The following are current stable implementation facts:

1. real kernel-backed `TWQ` dispatch semantics exist in the guest and are no
   longer a bring-up question;
2. the staged Swift full profile completes end-to-end under the staged
   `libdispatch` plus `libthr` stack;
3. worker lifecycle improvements that survived M13 are now part of the floor:
   same-lane handoff fast path, cross-lane `TWQ_OP_THREAD_TRANSFER`,
   wake-first planning, and per-lane idle tracking;
4. the low-level performance floor is durable:
   Zig lifecycle suite, workqueue wake suite, and the combined one-boot
   low-level gate;
5. the repeat-lane regression floor is durable:
   the focused schema-3 repeat gate now protects both the C repeat control and
   the Swift `dispatchMain()` repeat lane;
6. the `mainq -> default.overcommit` seam is no longer an open interpretive
   question:
   `M14` showed it is native-shaped enough to stop tuning on FreeBSD.

## Frozen Seams

The following are intentionally frozen until new evidence exists:

1. no more FreeBSD-side suppression work on
   `mainq -> default.overcommit`;
2. no more FreeBSD-side `ASYNC_REDIRECT` suppression work without a macOS
   comparison artifact for that specific seam;
3. no more repeat-lane optimization attempts justified only by a single
   promising run;
4. no more hot-path object-kind classification in staged `libdispatch` after
   MPSC publication.

## What Must Hold

Any future performance patch should keep these green:

1. the low-level one-boot gate;
2. the focused repeat-lane gate;
3. the full-matrix crossover assessment lane.

If a change improves one lane while regressing another, it is not ready.

## Deferred Work

The following are explicitly deferred:

1. deeper `M15`-style scheduler or workloop work without a concrete consumer;
2. ISA-assisted work such as `WAITPKG` or `UINTR` before the current software
   policy floor is exhausted on real workloads;
3. any broad attempt to clone more Apple-private dispatch behavior without a
   narrow consumer or comparison question;
4. broad harness expansion that does not close a known measurement gap.

## Current Next Decision

The next question is not "what else can be suppressed in the repeat lane?"

The next question is:

1. does the full current implementation still behave cleanly across the whole
   dispatch and Swift matrix after the M13 changes?

That is the purpose of the `M13.5` crossover assessment lane.

## Exit Rule

`M13` is ready to close once:

1. the low-level gate is green;
2. the repeat-lane gate is green;
3. the full-matrix crossover lane is green;
4. this boundary remains honest about what is frozen and what is deferred.

If all four are true, the project should stop searching for more repeat-lane
performance wins and decide the next milestone from a real external need.
