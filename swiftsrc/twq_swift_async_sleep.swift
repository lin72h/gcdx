import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress",
      "\"mode\":\"async-sleep\",\"phase\":\"before-sleep\"")

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(1)) {
      emit("progress",
        "\"mode\":\"async-sleep\",\"phase\":\"heartbeat-1s\"")
    }

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(5)) {
      emit("progress",
        "\"mode\":\"async-sleep\",\"phase\":\"heartbeat-5s\"")
    }

    try? await Task.sleep(nanoseconds: 20_000_000)

    emit("ok",
      "\"mode\":\"async-sleep\",\"phase\":\"after-sleep\"")
  }
}
