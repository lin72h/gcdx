import Dispatch
import Glibc

@_silgen_name("sysctlbyname")
private func c_sysctlbyname(
  _ name: UnsafePointer<CChar>,
  _ oldp: UnsafeMutableRawPointer?,
  _ oldlenp: UnsafeMutablePointer<Int>?,
  _ newp: UnsafeRawPointer?,
  _ newlen: Int
) -> CInt

private struct TwqRoundCounters {
  let reqthreadsCount: UInt64
  let threadEnterCount: UInt64
  let threadReturnCount: UInt64
}

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

@main
struct Main {
  static func main() {
    let rounds = envInt("TWQ_REPEAT_ROUNDS", default: 64)
    let tasks = envInt("TWQ_REPEAT_TASKS", default: 8)
    let delayMs = envInt("TWQ_REPEAT_DELAY_MS", default: 20)
    let debugFirstRound = envInt("TWQ_REPEAT_DEBUG_FIRST_ROUND", default: 0) != 0
    let roundSum = tasks * (tasks - 1) / 2

    emit(
      "progress",
      "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"before-spawn\",\"rounds\":\(rounds),\"tasks\":\(tasks),\"delay_ms\":\(delayMs)"
    )

    Task {
      var completedRounds = 0
      var totalSum = 0

      for round in 0..<rounds {
        let (roundStartCounters, roundStartError) = readTwqRoundCounters()
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"round-start\",\"round\":\(round),\"completed_rounds\":\(completedRounds)"
        )
        emitRoundCounters(
          mode: "dispatchmain-taskhandles-after-repeat",
          phase: "round-start-counters",
          round: round,
          completedRounds: completedRounds,
          counters: roundStartCounters,
          error: roundStartError
        )

        let handles = (0..<tasks).map { i in
          Task<Int, Never> {
            if debugFirstRound && round == 0 {
              emit(
                "progress",
                "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"child-start\",\"round\":0,\"task\":\(i)"
              )
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
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
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after-repeat\",\"phase\":\"round-ok\",\"round\":\(round),\"round_sum\":\(sum),\"expected_round_sum\":\(roundSum),\"completed_rounds\":\(completedRounds),\"total_sum\":\(totalSum)"
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
