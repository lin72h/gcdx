import Dispatch
import Glibc

final class Stats: @unchecked Sendable {
  private let lock = DispatchSemaphore(value: 1)
  private var completed = 0
  private var sum = 0

  func record(_ value: Int) {
    lock.wait()
    completed += 1
    sum += value
    lock.signal()
  }

  func snapshot() -> (completed: Int, sum: Int) {
    lock.wait()
    let value = (completed, sum)
    lock.signal()
    return value
  }
}

@main
struct Main {
  static func main() {
    let tasks = 8
    let queue = DispatchQueue.global(qos: .default)
    let group = DispatchGroup()
    let stats = Stats()

    for i in 0..<tasks {
      group.enter()
      queue.async {
        usleep(20_000)
        stats.record(i)
        group.leave()
      }
    }

    let waitResult = group.wait(timeout: .now() + .seconds(5))
    let snapshot = stats.snapshot()
    let ok = waitResult == .success && snapshot.completed == tasks
    let timedOut = waitResult != .success ? "true" : "false"
    let status = ok ? "ok" : "error"

    let line =
      "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
      "\"mode\":\"dispatch-control\",\"tasks\":\(tasks),\"completed\":\(snapshot.completed),\"sum\":\(snapshot.sum),\"timed_out\":\(timedOut)}," +
      "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatch-control\"}}\n"
    line.withCString { cstr in
      _ = fputs(cstr, stdout)
    }
    fflush(stdout)

    if !ok {
      exit(1)
    }
  }
}
