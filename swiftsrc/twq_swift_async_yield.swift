import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-yield\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress",
      "\"mode\":\"async-yield\",\"phase\":\"before-yield\"")

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(1)) {
      emit("progress",
        "\"mode\":\"async-yield\",\"phase\":\"heartbeat-1s\"")
    }

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(5)) {
      emit("progress",
        "\"mode\":\"async-yield\",\"phase\":\"heartbeat-5s\"")
    }

    await Task.yield()

    emit("ok",
      "\"mode\":\"async-yield\",\"phase\":\"after-yield\"")
  }
}
