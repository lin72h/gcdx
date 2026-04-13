import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-after\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"child-before-group\"")
      let tasks = 8
      var completed = 0
      let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
        for i in 0..<tasks {
          group.addTask {
            emit("progress", "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"child-start-\(i)\"")
            return await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
              DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .milliseconds(20)) {
                emit("progress", "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"child-after-delay-\(i)\"")
                continuation.resume(returning: i)
              }
            }
          }
        }

        var total = 0
        for await value in group {
          completed += 1
          total += value
          emit(
            "progress",
            "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"group-next\",\"completed\":\(completed),\"value\":\(value),\"sum\":\(total)"
          )
        }
        return total
      }

      emit(
        "progress",
        "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"child-after-group\",\"completed\":\(completed),\"sum\":\(sum)"
      )
      emit(
        "ok",
        "\"mode\":\"dispatchmain-taskgroup-after\",\"phase\":\"after-await\",\"completed\":\(completed),\"sum\":\(sum)"
      )
      exit(0)
    }

    dispatchMain()
  }
}
