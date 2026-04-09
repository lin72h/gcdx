import Glibc

@main
struct Main {
  static func main() async {
    let line =
      "{\"kind\":\"swift-probe\",\"status\":\"ok\",\"data\":{" +
      "\"mode\":\"async-smoke\"}," +
      "\"meta\":{\"component\":\"swift\",\"binary\":\"twq-swift-async-smoke\"}}\n"
    line.withCString { cstr in
      _ = fputs(cstr, stdout)
    }
    fflush(stdout)
  }
}
