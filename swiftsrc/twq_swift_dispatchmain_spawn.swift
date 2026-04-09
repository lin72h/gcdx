import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawn\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawn\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawn\",\"phase\":\"child-before-spawn\"")

      let handle = Task<Int, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawn\",\"phase\":\"grandchild-start\"")
        return 42
      }

      let value = await handle.value
      emit("ok", "\"mode\":\"dispatchmain-spawn\",\"phase\":\"after-await\",\"value\":\(value)")
      exit(0)
    }

    dispatchMain()
  }
}
