# Changelog

## 2026-04-10

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
