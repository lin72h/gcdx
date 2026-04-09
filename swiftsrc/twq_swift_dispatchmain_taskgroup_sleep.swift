import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskgroup-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"child-before-group\"")
      let tasks = 8
      var completed = 0
      let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
        for i in 0..<tasks {
          group.addTask {
            if i < 2 {
              emit("progress", "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"child-start-\(i)\"")
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
            if i < 2 {
              emit("progress", "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"child-after-sleep-\(i)\"")
            }
            return i
          }
        }

        var total = 0
        for await value in group {
          completed += 1
          total += value
        }
        return total
      }

      emit(
        "progress",
        "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"child-after-group\",\"completed\":\(completed),\"sum\":\(sum)"
      )
      emit(
        "ok",
        "\"mode\":\"dispatchmain-taskgroup-sleep\",\"phase\":\"after-await\",\"completed\":\(completed),\"sum\":\(sum)"
      )
      exit(0)
    }

    dispatchMain()
  }
}
