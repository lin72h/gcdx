import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-mainactor-sleep\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"mainactor-sleep\",\"phase\":\"before-spawn\"")

    let handle = Task<Int, Never> { @MainActor in
      emit("progress", "\"mode\":\"mainactor-sleep\",\"phase\":\"child-before-sleep\"")
      try? await Task.sleep(nanoseconds: 20_000_000)
      emit("progress", "\"mode\":\"mainactor-sleep\",\"phase\":\"child-after-sleep\"")
      return 42
    }

    let value = await handle.value
    emit("ok", "\"mode\":\"mainactor-sleep\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
