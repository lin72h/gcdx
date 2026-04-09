import Dispatch
import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-dispatchmain-spawnwait-after\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() {
    emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"before-spawn\"")

    Task {
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"parent-before-spawn\"")
      let handle = Task<Int, Never> {
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"child-before-await\"")
        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
          DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + .milliseconds(20)) {
            emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"resume-callback\"")
            continuation.resume(returning: 42)
          }
        }
        emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"child-after-await\"")
        return value
      }
      emit("progress", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"parent-before-await\"")
      let value = await handle.value
      emit("ok", "\"mode\":\"dispatchmain-spawnwait-after\",\"phase\":\"after-await\",\"value\":\(value)")
      exit(0)
    }

    dispatchMain()
  }
}
