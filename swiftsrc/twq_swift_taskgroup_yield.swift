import Dispatch
import Glibc

final class Stats: @unchecked Sendable {
  private let lock = DispatchSemaphore(value: 1)
  private var started = 0
  private var completed = 0

  func markStarted() {
    lock.wait()
    started += 1
    lock.signal()
  }

  func markCompleted() {
    lock.wait()
    completed += 1
    lock.signal()
  }

  func snapshot() -> (started: Int, completed: Int) {
    lock.wait()
    let value = (started, completed)
    lock.signal()
    return value
  }
}

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-yield\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

private func emitProgress(_ label: String, _ stats: Stats) {
  let snapshot = stats.snapshot()
  emit("progress",
    "\"mode\":\"taskgroup-yield\",\"label\":\"\(label)\"," +
    "\"started\":\(snapshot.started),\"completed\":\(snapshot.completed)")
}

@main
struct Main {
  static func main() async {
    let tasks = 8
    var completed = 0
    let stats = Stats()

    emit("progress",
      "\"mode\":\"taskgroup-yield\",\"label\":\"before-group\"")

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(1)) {
      emitProgress("heartbeat-1s", stats)
    }

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(5)) {
      emitProgress("heartbeat-5s", stats)
    }

    let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
      for i in 0..<tasks {
        group.addTask {
          stats.markStarted()
          await Task.yield()
          stats.markCompleted()
          return i
        }
      }

      var total = 0
      for await value in group {
        completed += 1
        total += value
        if completed <= 2 {
          emitProgress("received-\(completed)", stats)
        }
      }
      emitProgress("after-group", stats)
      return total
    }

    emitProgress("before-ok", stats)
    emit("ok",
      "\"mode\":\"taskgroup-yield\",\"tasks\":\(tasks)," +
      "\"completed\":\(completed),\"sum\":\(sum)")
  }
}
