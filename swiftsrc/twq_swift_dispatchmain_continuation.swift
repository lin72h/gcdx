import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-continuation\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-continuation\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-continuation\",\"phase\":\"child-before-await\"")

      let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
        DispatchQueue.global(qos: .default).async {
          emit("progress", "\"mode\":\"dispatchmain-continuation\",\"phase\":\"resume-callback\"")
          continuation.resume(returning: 42)
        }
      }

      emit("ok", "\"mode\":\"dispatchmain-continuation\",\"phase\":\"after-await\",\"value\":\(value)")
      exit(0)
    }

    dispatchMain()
  }
}
