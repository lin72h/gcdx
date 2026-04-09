# M12 Swift Delayed-Children Boundary

## Purpose

This note records the next narrowing step in the staged Swift/TWQ diagnosis.

The old boundary was:

1. delayed `TaskGroup` child completion times out on the staged custom
   `libdispatch` lane.

The new evidence is tighter than that.

## New Experiments

### 1. Pure-C `worker-after-group`

The C dispatch probe gained a new mode:

1. `worker-after-group`

Shape:

1. one dispatch worker schedules delayed children with `dispatch_after_f`;
2. that same worker waits for those delayed children to complete;
3. the process reports success or timeout.

Result on the staged TWQ lane:

1. success
2. `started=8`
3. `completed=8`
4. `unique_threads=2`
5. no timeout

This means raw delayed callbacks plus parent waiting do work below Swift.

### 2. Swift `dispatchmain-taskhandles-after`

A new Swift probe was added:

1. `twq_swift_dispatchmain_taskhandles_after.swift`

Shape:

1. a parent `Task` runs under `dispatchMain()`;
2. it creates 8 plain child `Task` handles, not a `TaskGroup`;
3. each child suspends via `withCheckedContinuation`;
4. each continuation is resumed from
   `DispatchQueue.global().asyncAfter(...)`;
5. the parent awaits every handle in sequence.

Result:

1. stock host Swift 6.3 lane: success
2. staged guest custom-`libdispatch` TWQ lane: timeout

## Corrected Boundary

The remaining staged Swift problem is no longer best described as
"`TaskGroup` after-delay is broken."

It is now more accurately:

1. multiple delayed Swift child-task resumptions awaited by a parent async
   context time out on the staged custom-`libdispatch` lane.

And it is also now clear what it is not:

1. not raw delayed dispatch callbacks in general;
2. not raw parent-waits-on-delayed-children in pure C;
3. not custom `libthr` by itself;
4. not stock Swift 6.3 in general.

## Why This Matters

This is a better debugging boundary than the old `TaskGroup` framing.

The problem space is now:

1. staged custom `libdispatch` plus Swift async-runtime interaction;
2. specifically where delayed callbacks resume suspended Swift child work;
3. while a parent async context is still awaiting those child completions.

That is a much smaller target than:

1. all of Swift concurrency;
2. all of `TaskGroup`;
3. all delayed dispatch work;
4. or the kernel TWQ implementation itself.

## Practical Next Step

The next high-value inspections should focus on:

1. staged custom `libdispatch` behavior on the Swift global executor queues;
2. Swift runtime delayed-enqueue and continuation-resume paths;
3. differences between the staged custom `libdispatch` snapshot and the stock
   Swift 6.3 runtime expectations.
