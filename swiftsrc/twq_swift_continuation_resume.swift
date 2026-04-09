import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-continuation-resume\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"continuation-resume\",\"phase\":\"before-await\"")

    let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
      DispatchQueue.global(qos: .default).async {
        emit("progress", "\"mode\":\"continuation-resume\",\"phase\":\"resume-callback\"")
        continuation.resume(returning: 42)
      }
    }

    emit("ok", "\"mode\":\"continuation-resume\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
