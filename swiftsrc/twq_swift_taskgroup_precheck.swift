import Glibc

@main
struct Main {
  static func main() async {
    let tasks = 8
    var completed = 0
    let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
      for i in 0..<tasks {
        group.addTask {
          try? await Task.sleep(nanoseconds: 20_000_000)
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

    let line =
      "{\"kind\":\"swift-probe\",\"status\":\"ok\",\"data\":{" +
      "\"mode\":\"taskgroup\",\"tasks\":\(tasks),\"completed\":\(completed),\"sum\":\(sum)}," +
      "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-taskgroup-precheck\"}}\n"
    line.withCString { cstr in
      _ = fputs(cstr, stdout)
    }
    fflush(stdout)
  }
}
