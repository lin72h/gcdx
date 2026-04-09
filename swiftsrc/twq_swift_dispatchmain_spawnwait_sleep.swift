import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"parent-before-spawn\"")
      let handle = Task<Int, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"child-before-sleep\"")
        try? await Task.sleep(nanoseconds: 20_000_000)
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"child-after-sleep\"")
        return 42
      }
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"parent-before-await\"")
      let value = await handle.value
      emit("ok", "\"mode\":\"dispatchmain-spawnwait-sleep\",\"phase\":\"after-await\",\"value\":\(value)")
      exit(0)
    }

    dispatchMain()
  }
}
