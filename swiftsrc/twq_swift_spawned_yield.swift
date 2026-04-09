import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-spawned-yield\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"spawned-yield\",\"phase\":\"before-spawn\"")

    let handle = Task<Int, Never> {
      emit("progress", "\"mode\":\"spawned-yield\",\"phase\":\"child-before-yield\"")
      await Task.yield()
      emit("progress", "\"mode\":\"spawned-yield\",\"phase\":\"child-after-yield\"")
      return 42
    }

    let value = await handle.value
    emit("ok", "\"mode\":\"spawned-yield\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
