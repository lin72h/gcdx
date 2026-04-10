# GLM Review Action Memo

## Purpose

This note records the project-level response to the external GLM architectural
review.

The goal is not to archive every opinion. The goal is to capture the decisions
that should change `GCDX` execution immediately.

## Main Judgment

The review's strongest point is accepted:

1. `GCDX` has a real Tier 1 kernel policy layer;
2. the current credibility risk is not `TWQ` itself;
3. the current weak link is the staged `libdispatch` adaptation depth;
4. the remaining delayed-child timeout should now be treated as a Layer B
   dispatch correctness problem until proven otherwise.

In short:

The next step is not "more Swift narrowing." The next step is "fix the staged
`libdispatch` executor-style delayed-work path at the C level."

## What We Accept From The Review

### 1. The tier model is useful but must not become a checklist

`libdispatch -> GCDX -> GCD` remains the right communication model.

But internally it must stay a model of integration depth, not a percent-complete
feature checklist against macOS.

### 2. The current bug is no longer best treated as a Swift problem

The Swift lane did its job:

1. it exposed the failure;
2. it narrowed the failure;
3. it ruled out broad kernel failure and broad `libthr` failure.

That is enough narrowing for now.

### 3. Kernel-owned lifecycle is not yet the next conclusion

Kernel-owned worker lifecycle may still become the right long-term answer.

But the current evidence does not force that conclusion yet.

The current evidence first points to staged `libdispatch` worker-request and
delayed-resumption behavior.

### 4. The parity estimate needs a caveat

The current `70-80%` reading is acceptable only if it is read as:

1. mechanism coverage for the kernel-backed workqueue path;
2. not a claim that higher-level behavioral correctness is already close to
   macOS.

Until the delayed-child bug is fixed, the estimate must not be read more
strongly than that.

## Immediate Action Order

### 1. Freeze Swift probe expansion

Do not spend the next cycle inventing new Swift probes.

Keep the current Swift matrix as:

1. a validation lane;
2. a regression lane;
3. a comparison/control lane.

But do not make Swift the primary debugging surface for the next step.

### 2. Shift the fix vehicle to C

The next active debugging target is the staged `libdispatch` C path.

Required focus:

1. make `executor-after` deterministic, or find an equivalently small pure-C
   reproduction;
2. instrument delayed callback wakeup and root-queue worker-request paths;
3. compare stock dispatch against staged `GCDX` dispatch under the same
   executor-style delayed-work pattern;
4. determine whether staged dispatch is:
   - failing to request a worker,
   - requesting too late,
   - or mishandling resumed work on executor-style queues.

### 3. Re-run Swift only after the C path is clearer

Once the C-level fix or root-cause diagnosis exists, re-run the existing Swift
diagnostics to verify whether the same fix clears the staged Swift boundary.

## What This Defers

The following remain important, but they are not the next step:

1. cooperative-pool design;
2. direct kevent-workqueue delivery;
3. workloops;
4. stack reuse pool;
5. deeper kernel-owned worker lifecycle;
6. oneTBB / TCM implementation work.

These are later decisions, not the current blocker.

## Operational Rule

For the next milestone:

1. Swift remains the discovery and validation lane;
2. C becomes the primary reproduction and fix lane;
3. staged `libdispatch` is the primary suspect layer;
4. kernel lifecycle redesign is deferred unless the C-level diagnosis fails to
   explain the boundary.

## Bottom Line

`GCDX` should now behave like a project closing a Tier 1 correctness gap, not a
project still searching for the right symptom description.

The next milestone is:

1. isolate and fix the staged `libdispatch` executor-after / delayed-child bug
   at the C level;
2. then revalidate the existing Swift boundary on top of that fix.
