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

private func emitProgress(_ mode: String, _ label: String, _ stats: Stats) {
  let snapshot = stats.snapshot()
  let line =
    "{\"kind\":\"swift-probe-progress\",\"status\":\"progress\",\"data\":{" +
    "\"mode\":\"\(mode)\",\"label\":\"\(label)\",\"started\":\(snapshot.started),\"completed\":\(snapshot.completed)}," +
    "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-immediate\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    let tasks = 8
    var completed = 0
    let stats = Stats()

    emitProgress("taskgroup-immediate", "before-group", stats)

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(1)) {
      emitProgress("taskgroup-immediate", "after-1s", stats)
    }

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(5)) {
      emitProgress("taskgroup-immediate", "after-5s", stats)
    }

    let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
      for i in 0..<tasks {
        group.addTask {
          if i < 2 {
            let line =
              "{\"kind\":\"swift-probe-progress\",\"status\":\"progress\",\"data\":{" +
              "\"mode\":\"taskgroup-immediate\",\"label\":\"child-start-\(i)\"}," +
              "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-immediate\"}}\n"
            line.withCString { cstr in
              _ = fputs(cstr, stdout)
            }
            fflush(stdout)
          }
          stats.markStarted()
          stats.markCompleted()
          if i < 2 {
            let line =
              "{\"kind\":\"swift-probe-progress\",\"status\":\"progress\",\"data\":{" +
              "\"mode\":\"taskgroup-immediate\",\"label\":\"child-complete-\(i)\"}," +
              "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-immediate\"}}\n"
            line.withCString { cstr in
              _ = fputs(cstr, stdout)
            }
            fflush(stdout)
          }
          return i
        }
      }

      var total = 0
      for await value in group {
        completed += 1
        total += value
        if completed <= 2 {
          emitProgress("taskgroup-immediate", "received-\(completed)", stats)
        }
      }
      emitProgress("taskgroup-immediate", "after-group", stats)
      return total
    }

    emitProgress("taskgroup-immediate", "before-ok", stats)
    let line =
      "{\"kind\":\"swift-probe\",\"status\":\"ok\",\"data\":{" +
      "\"mode\":\"taskgroup-immediate\",\"tasks\":\(tasks),\"completed\":\(completed),\"sum\":\(sum)}," +
      "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-immediate\"}}\n"
    line.withCString { cstr in
      _ = fputs(cstr, stdout)
    }
    fflush(stdout)
  }
}
