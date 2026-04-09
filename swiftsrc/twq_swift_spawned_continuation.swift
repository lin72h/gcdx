import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-spawned-continuation\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"spawned-continuation\",\"phase\":\"before-spawn\"")

    let handle = Task<Int, Never> {
      emit("progress", "\"mode\":\"spawned-continuation\",\"phase\":\"child-before-await\"")
      let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
        DispatchQueue.global(qos: .default).async {
          emit("progress", "\"mode\":\"spawned-continuation\",\"phase\":\"child-resume-callback\"")
          continuation.resume(returning: 42)
        }
      }
      emit("progress", "\"mode\":\"spawned-continuation\",\"phase\":\"child-after-await\",\"value\":\(value)")
      return value
    }

    let value = await handle.value
    emit("ok", "\"mode\":\"spawned-continuation\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
