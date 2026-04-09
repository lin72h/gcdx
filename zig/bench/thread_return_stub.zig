const std = @import("std");

pub fn main() !void {
    var timer = try std.time.Timer.start();
    var acc: u64 = 0;

    var i: u64 = 0;
    while (i < 100_000) : (i += 1) {
        acc +%= i;
    }

    const elapsed_ns = timer.read();

    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;

    try writer.print(
        "{{\"kind\":\"zig-bench-stub\",\"status\":\"ok\",\"data\":{{\"iterations\":100000,\"elapsed_ns\":{d},\"acc\":{d}}},\"meta\":{{\"benchmark\":\"thread-return-stub\"}}}}\n",
        .{ elapsed_ns, acc },
    );
}
