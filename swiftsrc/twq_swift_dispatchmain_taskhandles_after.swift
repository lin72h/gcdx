import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-taskhandles-after\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"before-spawn\"")

    Task {
      let tasks = 8
      emit("progress", "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"parent-before-handles\"")

      let handles = (0..<tasks).map { i in
        Task<Int, Never> {
          emit("progress", "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"child-start-\(i)\"")
          let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .milliseconds(20)) {
              emit("progress", "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"child-after-delay-\(i)\"")
              continuation.resume(returning: i)
            }
          }
          emit(
            "progress",
            "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"child-after-await-\(i)\",\"value\":\(value)"
          )
          return value
        }
      }

      emit("progress", "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"parent-before-await\"")
      var completed = 0
      var sum = 0
      for (index, handle) in handles.enumerated() {
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"parent-awaiting-\(index)\",\"completed\":\(completed),\"sum\":\(sum)"
        )
        let value = await handle.value
        sum += value
        completed += 1
        emit(
          "progress",
          "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"parent-after-await-\(index)\",\"completed\":\(completed),\"value\":\(value),\"sum\":\(sum)"
        )
      }

      emit(
        "ok",
        "\"mode\":\"dispatchmain-taskhandles-after\",\"phase\":\"after-await\",\"completed\":\(completed),\"sum\":\(sum)"
      )
      exit(0)
    }

    dispatchMain()
  }
}
