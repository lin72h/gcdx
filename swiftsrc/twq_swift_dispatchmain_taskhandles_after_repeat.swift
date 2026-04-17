import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@_silgen_name("sysctlbyname")
private func c_sysctlbyname(
  _ name: UnsafePointer<CChar>,
  _ oldp: UnsafeMutableRawPointer?,
  _ oldlenp: UnsafeMutablePointer<Int>?,
  _ newp: UnsafeRawPointer?,
  _ newlen: Int
) -> CInt

private typealias DispatchTwqCounterEmitSnapshotFn = @convention(c) (
  UnsafePointer<CChar>,
  UnsafePointer<CChar>,
  UnsafePointer<CChar>,
  UInt64,
  UInt64
) -> Void

private let dispatchTwqCounterEmitSnapshotFn: DispatchTwqCounterEmitSnapshotFn? = {
  guard let handle = dlopen(nil, Int32(RTLD_NOW)) else {
    return nil
  }
  guard let symbol = dlsym(handle, "_dispatch_twq_counter_emit_snapshot") else {
    return nil
  }
  return unsafeBitCast(symbol, to: DispatchTwqCounterEmitSnapshotFn.self)
}()

private struct TwqRoundCounters {
  let reqthreadsCount: UInt64
  let threadEnterCount: UInt64
  let threadReturnCount: UInt64
}

private struct TwqDispatchCounters {
  var rootPushTotalDefault: UInt64
  var rootPushEmptyDefault: UInt64
  var rootPushSourceDefault: UInt64
  var rootPushContinuationDefault: UInt64
  var rootPokeSlowDefault: UInt64
  var rootRequestedThreadsDefault: UInt64
  var rootPushTotalDefaultOvercommit: UInt64
  var rootPushEmptyDefaultOvercommit: UInt64
  var rootPushMainqDefaultOvercommit: UInt64
  var rootPushContinuationDefaultOvercommit: UInt64
  var rootPokeSlowDefaultOvercommit: UInt64
  var rootRequestedThreadsDefaultOvercommit: UInt64
  var pthreadWorkqueueAddthreadsCalls: UInt64
  var pthreadWorkqueueAddthreadsRequestedThreads: UInt64
}

@_silgen_name("twq_macos_dispatch_introspection_install")
private func twqDispatchIntrospectionInstall() -> Int32

@_silgen_name("twq_macos_dispatch_introspection_available")
private func twqDispatchIntrospectionAvailable() -> Int32

@_silgen_name("twq_macos_dispatch_introspection_snapshot")
private func twqDispatchIntrospectionSnapshot(
  _ out: UnsafeMutablePointer<TwqDispatchCounters>
) -> Int32

@_silgen_name("twq_macos_dispatch_introspection_last_error")
private func twqDispatchIntrospectionLastError() -> UnsafePointer<CChar>?

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskhandles-after-repeat\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

private func readSysctlU64(_ name: String) -> (UInt64?, CInt) {
  var value = UInt64(0)
  var len = MemoryLayout<UInt64>.size
  let rc = name.withCString { cstr in
    c_sysctlbyname(cstr, &value, &len, nil, 0)
  }
  if rc != 0 {
    return (nil, errno)
  }
  switch len {
  case MemoryLayout<UInt32>.size:
    return (UInt64(UInt32(truncatingIfNeeded: value)), 0)
  case MemoryLayout<UInt64>.size, MemoryLayout<UInt>.size:
    return (value, 0)
  default:
    return (nil, EPROTO)
  }
}

private func readTwqRoundCounters() -> (TwqRoundCounters?, CInt) {
#if os(FreeBSD)
  let (reqthreads, reqErr) = readSysctlU64("kern.twq.reqthreads_count")
  if let reqthreads {
    let (threadEnter, enterErr) = readSysctlU64("kern.twq.thread_enter_count")
    if let threadEnter {
      let (threadReturn, returnErr) = readSysctlU64("kern.twq.thread_return_count")
      if let threadReturn {
        return (
          TwqRoundCounters(
            reqthreadsCount: reqthreads,
            threadEnterCount: threadEnter,
            threadReturnCount: threadReturn
          ),
          0
        )
      }
      return (nil, returnErr)
    }
    return (nil, enterErr)
  }
  return (nil, reqErr)
#else
  return (nil, ENOTSUP)
#endif
}

private func emitRoundCounters(
  mode: String,
  phase: String,
  round: Int,
  completedRounds: Int,
  counters: TwqRoundCounters?,
  error: CInt,
  startCounters: TwqRoundCounters? = nil
) {
  if let counters {
    var payload =
      "\"mode\":\"\(mode)\",\"phase\":\"\(phase)\",\"round\":\(round),\"completed_rounds\":\(completedRounds)," +
      "\"reqthreads_count\":\(counters.reqthreadsCount),\"thread_enter_count\":\(counters.threadEnterCount)," +
      "\"thread_return_count\":\(counters.threadReturnCount)"
    if let startCounters {
      payload +=
        ",\"reqthreads_delta\":\(counters.reqthreadsCount - startCounters.reqthreadsCount)," +
        "\"thread_enter_delta\":\(counters.threadEnterCount - startCounters.threadEnterCount)," +
        "\"thread_return_delta\":\(counters.threadReturnCount - startCounters.threadReturnCount)"
    }
    emit("progress", payload)
  } else {
    emit(
      "progress",
      "\"mode\":\"\(mode)\",\"phase\":\"\(phase)\",\"round\":\(round),\"completed_rounds\":\(completedRounds),\"sysctl_error\":\(error)"
    )
  }
}

private func emitLibdispatchRoundSnapshot(
  domain: String,
  mode: String,
  phase: String,
  round: Int,
  completedRounds: Int
) {
  guard let emitSnapshot = dispatchTwqCounterEmitSnapshotFn else {
    return
  }
  domain.withCString { domainCStr in
    mode.withCString { modeCStr in
      phase.withCString { phaseCStr in
        emitSnapshot(
          domainCStr,
          modeCStr,
          phaseCStr,
          UInt64(round),
          UInt64(completedRounds)
        )
      }
    }
  }
}

private func envInt(_ name: String, default value: Int) -> Int {
  guard let raw = getenv(name) else {
    return value
  }
  let string = String(cString: raw)
  guard let parsed = Int(string), parsed > 0 else {
    return value
  }
  return parsed
}

private func emitDispatchCounters(
  mode: String,
  phase: String,
  round: Int,
  completedRounds: Int,
  counters: TwqDispatchCounters,
  startCounters: TwqDispatchCounters? = nil
) {
  emit(
    "progress",
    "\"mode\":\"\(mode)\",\"phase\":\"\(phase)\",\"round\":\(round),\"completed_rounds\":\(completedRounds)," +
      "\"root_push_total_default\":\(counters.rootPushTotalDefault)," +
      "\"root_push_empty_default\":\(counters.rootPushEmptyDefault)," +
      "\"root_push_source_default\":\(counters.rootPushSourceDefault)," +
      "\"root_push_continuation_default\":\(counters.rootPushContinuationDefault)," +
      "\"root_poke_slow_default\":\(counters.rootPokeSlowDefault)," +
      "\"root_requested_threads_default\":\(counters.rootRequestedThreadsDefault)," +
      "\"root_push_total_default_overcommit\":\(counters.rootPushTotalDefaultOvercommit)," +
      "\"root_push_empty_default_overcommit\":\(counters.rootPushEmptyDefaultOvercommit)," +
      "\"root_push_mainq_default_overcommit\":\(counters.rootPushMainqDefaultOvercommit)," +
      "\"root_push_continuation_default_overcommit\":\(counters.rootPushContinuationDefaultOvercommit)," +
      "\"root_poke_slow_default_overcommit\":\(counters.rootPokeSlowDefaultOvercommit)," +
      "\"root_requested_threads_default_overcommit\":\(counters.rootRequestedThreadsDefaultOvercommit)," +
      "\"pthread_workqueue_addthreads_calls\":\(counters.pthreadWorkqueueAddthreadsCalls)," +
      "\"pthread_workqueue_addthreads_requested_threads\":\(counters.pthreadWorkqueueAddthreadsRequestedThreads)"
  )

  guard let startCounters else {
    return
  }

  emit(
    "progress",
    "\"mode\":\"\(mode)\",\"phase\":\"\(phase)-delta\",\"round\":\(round),\"completed_rounds\":\(completedRounds)," +
      "\"root_push_total_default\":\(counters.rootPushTotalDefault - startCounters.rootPushTotalDefault)," +
      "\"root_push_empty_default\":\(counters.rootPushEmptyDefault - startCounters.rootPushEmptyDefault)," +
      "\"root_push_source_default\":\(counters.rootPushSourceDefault - startCounters.rootPushSourceDefault)," +
      "\"root_push_continuation_default\":\(counters.rootPushContinuationDefault - startCounters.rootPushContinuationDefault)," +
      "\"root_poke_slow_default\":\(counters.rootPokeSlowDefault - startCounters.rootPokeSlowDefault)," +
      "\"root_requested_threads_default\":\(counters.rootRequestedThreadsDefault - startCounters.rootRequestedThreadsDefault)," +
      "\"root_push_total_default_overcommit\":\(counters.rootPushTotalDefaultOvercommit - startCounters.rootPushTotalDefaultOvercommit)," +
      "\"root_push_empty_default_overcommit\":\(counters.rootPushEmptyDefaultOvercommit - startCounters.rootPushEmptyDefaultOvercommit)," +
      "\"root_push_mainq_default_overcommit\":\(counters.rootPushMainqDefaultOvercommit - startCounters.rootPushMainqDefaultOvercommit)," +
      "\"root_push_continuation_default_overcommit\":\(counters.rootPushContinuationDefaultOvercommit - startCounters.rootPushContinuationDefaultOvercommit)," +
      "\"root_poke_slow_default_overcommit\":\(counters.rootPokeSlowDefaultOvercommit - startCounters.rootPokeSlowDefaultOvercommit)," +
      "\"root_requested_threads_default_overcommit\":\(counters.rootRequestedThreadsDefaultOvercommit - startCounters.rootRequestedThreadsDefaultOvercommit)," +
      "\"pthread_workqueue_addthreads_calls\":\(counters.pthreadWorkqueueAddthreadsCalls - startCounters.pthreadWorkqueueAddthreadsCalls)," +
      "\"pthread_workqueue_addthreads_requested_threads\":\(counters.pthreadWorkqueueAddthreadsRequestedThreads - startCounters.pthreadWorkqueueAddthreadsRequestedThreads)"
  )
}

private func monotonicNowNs() -> UInt64 {
  var ts = timespec()
  guard clock_gettime(CLOCK_MONOTONIC, &ts) == 0 else {
    return 0
  }
  return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
}

@main
struct Main {
  static func main() {
    let rounds = envInt("TWQ_REPEAT_ROUNDS", default: 64)
    let tasks = envInt("TWQ_REPEAT_TASKS", default: 8)
    let delayMs = envInt("TWQ_REPEAT_DELAY_MS", default: 20)
    let debugFirstRound = envInt("TWQ_REPEAT_DEBUG_FIRST_ROUND", default: 0) != 0
    let roundSum = tasks * (tasks - 1) / 2
    let dispatchCountersAvailable =
      twqDispatchIntrospectionInstall() == 0 && twqDispatchIntrospectionAvailable() != 0

    emit(
      "progress",
      "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"before-spawn\",\"rounds\":\(rounds),\"tasks\":\(tasks),\"delay_ms\":\(delayMs),\"dispatch_introspection_available\":\(dispatchCountersAvailable ? "true" : "false")"
    )
    if !dispatchCountersAvailable, let error = twqDispatchIntrospectionLastError() {
      emit(
        "progress",
        "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"dispatch-introspection-error\",\"message\":\"\(String(cString: error))\""
      )
    }

    Task {
      var completedRounds = 0
      var totalSum = 0
      var roundStartDispatchCounters = TwqDispatchCounters(
        rootPushTotalDefault: 0,
        rootPushEmptyDefault: 0,
        rootPushSourceDefault: 0,
        rootPushContinuationDefault: 0,
        rootPokeSlowDefault: 0,
        rootRequestedThreadsDefault: 0,
        rootPushTotalDefaultOvercommit: 0,
        rootPushEmptyDefaultOvercommit: 0,
        rootPushMainqDefaultOvercommit: 0,
        rootPushContinuationDefaultOvercommit: 0,
        rootPokeSlowDefaultOvercommit: 0,
        rootRequestedThreadsDefaultOvercommit: 0,
        pthreadWorkqueueAddthreadsCalls: 0,
        pthreadWorkqueueAddthreadsRequestedThreads: 0
      )

      for round in 0..<rounds {
        let (roundStartCounters, roundStartError) = readTwqRoundCounters()
        let roundStartNs = monotonicNowNs()
        if dispatchCountersAvailable {
          var snapshot = roundStartDispatchCounters
          if twqDispatchIntrospectionSnapshot(&snapshot) == 0 {
            roundStartDispatchCounters = snapshot
          }
        }
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"round-start\",\"round\":\(round),\"completed_rounds\":\(completedRounds),\"ts_ns\":\(roundStartNs)"
        )
        emitRoundCounters(
          mode: "dispatchmain-taskhandles-after-repeat",
          phase: "round-start-counters",
          round: round,
          completedRounds: completedRounds,
          counters: roundStartCounters,
          error: roundStartError
        )
        if dispatchCountersAvailable {
          emitDispatchCounters(
            mode: "dispatchmain-taskhandles-after-repeat",
            phase: "round-start-counters",
            round: round,
            completedRounds: completedRounds,
            counters: roundStartDispatchCounters
          )
        }
        emitLibdispatchRoundSnapshot(
          domain: "swift",
          mode: "dispatchmain-taskhandles-after-repeat",
          phase: "round-start-counters",
          round: round,
          completedRounds: completedRounds
        )

        let handles = (0..<tasks).map { i in
          Task<Int, Never> {
            if debugFirstRound && round == 0 {
              emit(
                "progress",
                "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"child-start\",\"round\":0,\"task\":\(i)"
              )
            }
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
              DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                if debugFirstRound && round == 0 {
                  emit(
                    "progress",
                    "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"child-after-delay\",\"round\":0,\"task\":\(i)"
                  )
                }
                continuation.resume(returning: i)
              }
            }
            if debugFirstRound && round == 0 {
              emit(
                "progress",
                "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"child-after-await\",\"round\":0,\"task\":\(i)"
              )
            }
            return i
          }
        }

        var sum = 0
        for (index, handle) in handles.enumerated() {
          if debugFirstRound && round == 0 {
            emit(
              "progress",
              "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"parent-awaiting\",\"round\":0,\"task\":\(index),\"sum\":\(sum)"
            )
          }
          let value = await handle.value
          sum += value
          if debugFirstRound && round == 0 {
            emit(
              "progress",
              "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"parent-after-await\",\"round\":0,\"task\":\(index),\"sum\":\(sum)"
            )
          }
        }

        completedRounds += 1
        totalSum += sum
        let (roundEndCounters, roundEndError) = readTwqRoundCounters()
        let roundEndNs = monotonicNowNs()
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"round-ok\",\"round\":\(round),\"round_sum\":\(sum),\"expected_round_sum\":\(roundSum),\"completed_rounds\":\(completedRounds),\"total_sum\":\(totalSum),\"elapsed_ns\":\(roundEndNs - roundStartNs),\"ts_ns\":\(roundEndNs)"
        )
        emitRoundCounters(
          mode: "dispatchmain-taskhandles-after-repeat",
          phase: "round-ok-counters",
          round: round,
          completedRounds: completedRounds,
          counters: roundEndCounters,
          error: roundStartCounters != nil ? roundEndError : roundStartError,
          startCounters: roundStartCounters
        )
        if dispatchCountersAvailable {
          var roundEndDispatchCounters = roundStartDispatchCounters
          if twqDispatchIntrospectionSnapshot(&roundEndDispatchCounters) == 0 {
            emitDispatchCounters(
              mode: "dispatchmain-taskhandles-after-repeat",
              phase: "round-ok-counters",
              round: round,
              completedRounds: completedRounds,
              counters: roundEndDispatchCounters,
              startCounters: roundStartDispatchCounters
            )
          }
        }
        emitLibdispatchRoundSnapshot(
          domain: "swift",
          mode: "dispatchmain-taskhandles-after-repeat",
          phase: "round-ok-counters",
          round: round,
          completedRounds: completedRounds
        )
      }

      emit(
        "ok",
        "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"after-await\",\"rounds\":\(rounds),\"tasks\":\(tasks),\"delay_ms\":\(delayMs),\"completed_rounds\":\(completedRounds),\"total_sum\":\(totalSum),\"expected_total_sum\":\(rounds * roundSum)"
      )
      exit(0)
    }

    dispatchMain()
  }
}
