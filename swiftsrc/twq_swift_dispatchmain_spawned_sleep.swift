import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawned-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"parent-before-spawn\"")
      _ = Task<Void, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"child-before-sleep\"")
        try? await Task.sleep(nanoseconds: 20_000_000)
        emit("progress", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"child-after-sleep\"")
        emit("ok", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"after-child-sleep\"")
        exit(0)
      }
      emit("progress", "\"mode\":\"dispatchmain-spawned-sleep\",\"phase\":\"parent-after-spawn\"")
    }

    dispatchMain()
  }
}
