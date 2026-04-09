import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawned-yield\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"parent-before-spawn\"")
      _ = Task<Void, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"child-before-yield\"")
        await Task.yield()
        emit("progress", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"child-after-yield\"")
        emit("ok", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"after-child-yield\"")
        exit(0)
      }
      emit("progress", "\"mode\":\"dispatchmain-spawned-yield\",\"phase\":\"parent-after-spawn\"")
    }

    dispatchMain()
  }
}
