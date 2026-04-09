import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-yield\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"parent-before-spawn\"")
      let handle = Task<Int, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"child-before-yield\"")
        await Task.yield()
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"child-after-yield\"")
        return 42
      }
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"parent-before-await\"")
      let value = await handle.value
      emit("ok", "\"mode\":\"dispatchmain-spawnwait-yield\",\"phase\":\"after-await\",\"value\":\(value)")
      exit(0)
    }

    dispatchMain()
  }
}
