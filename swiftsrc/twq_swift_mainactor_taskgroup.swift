import Glibc

private func emit(_ status: String, _ data: String) {
  let line =
    "{\"kind\":\"swift-probe\",\"status\":\"\(status)\",\"data\":{" +
    data +
    "},\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-mainactor-taskgroup\"}}\n"
  line.withCString { cstr in
    _ = fputs(cstr, stdout)
  }
  fflush(stdout)
}

@main
struct Main {
  static func main() async {
    emit("progress", "\"mode\":\"mainactor-taskgroup\",\"phase\":\"before-spawn\"")

    let handle = Task<Int, Never> { @MainActor in
      emit("progress", "\"mode\":\"mainactor-taskgroup\",\"phase\":\"child-before-group\"")
      var completed = 0
      let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
        for i in 0..<8 {
          group.addTask {
            if i < 2 {
              emit("progress", "\"mode\":\"mainactor-taskgroup\",\"phase\":\"child-start-\(i)\"")
            }
            return i
          }
        }

        var total = 0
        for await value in group {
          completed += 1
          total += value
        }
        return total
      }

      emit("progress", "\"mode\":\"mainactor-taskgroup\",\"phase\":\"child-after-group\",\"completed\":\(completed),\"sum\":\(sum)")
      return sum
    }

    let value = await handle.value
    emit("ok", "\"mode\":\"mainactor-taskgroup\",\"phase\":\"after-await\",\"value\":\(value)")
  }
}
