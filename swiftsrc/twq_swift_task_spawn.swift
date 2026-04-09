import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-task-spawn\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"task-spawn\",\"phase\":\"before-spawn\"")

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(1)) {
      emit("progress", "\"mode\":\"task-spawn\",\"phase\":\"heartbeat-1s\"")
    }

    DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .seconds(5)) {
      emit("progress", "\"mode\":\"task-spawn\",\"phase\":\"heartbeat-5s\"")
    }

    let handle = Task<Int, Never> {
      emit("progress", "\"mode\":\"task-spawn\",\"phase\":\"child-start\"")
      return 42
    }

    let value = await handle.value
    emit("ok", "\"mode\":\"task-spawn\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
