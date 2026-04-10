# CHANGELOG

## 2026-04-10

### Project naming standardized

The repo now treats `GCDX` as the explicit project name for the current
FreeBSD-based kernel-integrated dispatch effort.

The terminology map is now:

1. `libdispatch` = portable Tier 0 baseline;
2. `GCDX` = this project, the kernel-integrated Tier 1 lane;
3. `GCD` = the platform-complete macOS reference lane.

### Swift 6.3 stock-dispatch boundary corrected

The repo now records an important Swift validation correction:

1. the stock Swift 6.3 toolchain `libdispatch.so` does not reference
   `_pthread_workqueue_*` symbols at all;
2. the staged custom `libdispatch.so` does;
3. the stock-dispatch plus custom-`libthr` guest control completes a delayed
   child-completion probe successfully, but shows zero TWQ counter deltas
   during that probe window.

This means the stock Swift 6.3 dispatch lane is a useful runtime control, but
it is not a TWQ-backed control lane. Real Swift/TWQ validation still depends
on the staged custom `libdispatch` lane.

### Swift delayed-child boundary narrowed again

The repo now has a stronger staged Swift diagnosis:

1. a new pure-C `worker-after-group` dispatch mode succeeds on the staged TWQ
   lane;
2. a new Swift `dispatchmain-taskhandles-after` probe still times out there,
   while passing on the stock host Swift 6.3 lane.

This means the remaining problem is no longer best described as a
`TaskGroup`-only bug. The tighter boundary is:

1. multiple delayed Swift child-task resumptions awaited by a parent async
   context on the staged custom-`libdispatch` lane.

### Current macOS-gap reading

The repo now carries an explicit estimate for how close the current port is to
native macOS `libdispatch` behavior:

1. roughly `70-80%` for the kernel-backed workqueue behavior that matters most
   to this project;
2. roughly `45-55%` for broader native-macOS `libdispatch` parity overall.

### Why the estimate is already meaningfully high

The following are already real and working:

1. kernel `TWQ` support in `/usr/src`;
2. real pressure-aware admission and narrowing;
3. real backpressure from the kernel workqueue path into staged
   `libdispatch`;
4. a real `libthr` pthread_workqueue bridge;
5. repeatable `bhyve` guest validation;
6. a stable Swift validation profile that proves the staged stack is not just
   a synthetic C-only demo.

### Why the estimate is not higher yet

The following important gaps remain:

1. no direct kevent-workqueue delivery;
2. no workloops;
3. no cooperative-pool semantics;
4. worker lifecycle is still not kernel-owned the way it is on macOS;
5. no turnstile-style priority inheritance for this path;
6. no structured macOS-side comparison lane has been run yet;
7. one staged custom-`libdispatch` bug is still open:
   delayed `TaskGroup` child completion on the TWQ lane.

### Current position

The project is already past the stage where it can be honestly called a shim or
compatibility-only dispatch story. It has crossed the boundary into a real
kernel-backed dispatch implementation on FreeBSD.

The remaining work is no longer "make pthread_workqueue exist at all." It is:

1. fix the remaining staged custom-`libdispatch` delayed child-completion bug;
2. expand Swift validation without lying about what is already stable;
3. build the macOS comparison lane;
4. decide later which deeper macOS features are worth adopting naturally on
   FreeBSD.
