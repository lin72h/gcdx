import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-sleep\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-sleep\",\"phase\":\"child-before-sleep\"")
      try? await Task.sleep(nanoseconds: 20_000_000)
      emit("progress", "\"mode\":\"dispatchmain-sleep\",\"phase\":\"child-after-sleep\"")
      emit("ok", "\"mode\":\"dispatchmain-sleep\",\"phase\":\"after-await\"")
      exit(0)
    }

    dispatchMain()
  }
}
