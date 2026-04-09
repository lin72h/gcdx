const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("pthread/workqueue_private.h");
    @cInclude("pthread.h");
    @cInclude("unistd.h");
});

const default_priority: u64 = 0x15 << 8;

var callback_count = std.atomic.Value(u32).init(0);
var last_priority = std.atomic.Value(u64).init(0);
var narrow_true_count = std.atomic.Value(u32).init(0);
var narrow_false_count = std.atomic.Value(u32).init(0);

fn emitResult(
    writer: anytype,
    mode: []const u8,
    status: []const u8,
    rc: i32,
    requested: u32,
    observed: u32,
    timed_out: bool,
    features: i32,
    priority: u64,
    narrow_true: u32,
    narrow_false: u32,
) !void {
    try writer.print(
        "{{\"kind\":\"zig-workq-probe\",\"status\":\"{s}\",\"data\":{{\"mode\":\"{s}\",\"rc\":{d},\"requested\":{d},\"observed\":{d},\"timed_out\":{s},\"features\":{d},\"priority\":{d},\"narrow_true\":{d},\"narrow_false\":{d}}},\"meta\":{{\"component\":\"zig\",\"binary\":\"twq-workqueue-probe\"}}}}\n",
        .{
            status,
            mode,
            rc,
            requested,
            observed,
            if (timed_out) "true" else "false",
            features,
            priority,
            narrow_true,
            narrow_false,
        },
    );
}

fn workerCallback(priority: c.pthread_priority_t) callconv(.c) void {
    _ = callback_count.fetchAdd(1, .seq_cst);
    last_priority.store(@as(u64, priority), .seq_cst);
    if (c._pthread_workqueue_should_narrow(priority)) {
        _ = narrow_true_count.fetchAdd(1, .seq_cst);
    } else {
        _ = narrow_false_count.fetchAdd(1, .seq_cst);
    }
    _ = c.usleep(10_000);
}

fn waitForCallbacks(target: u32, timeout_ms: u32) bool {
    const deadline = std.time.milliTimestamp() + @as(i64, timeout_ms);

    while (callback_count.load(.seq_cst) < target) {
        if (std.time.milliTimestamp() >= deadline)
            return true;
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var numthreads: u32 = 2;
    var timeout_ms: u32 = 2_000;

    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--numthreads")) {
            const value = args.next() orelse return error.MissingValue;
            numthreads = try std.fmt.parseInt(u32, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--timeout-ms")) {
            const value = args.next() orelse return error.MissingValue;
            timeout_ms = try std.fmt.parseInt(u32, value, 10);
            continue;
        }
        return error.UnknownArgument;
    }

    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;
    const supported = c._pthread_workqueue_supported();
    try emitResult(writer, "supported", "ok", supported, 0, 0, false, supported, 0, 0, 0);

    const init_rc = c._pthread_workqueue_init(workerCallback, 16, 0);
    try emitResult(writer, "init", if (init_rc == 0) "ok" else "error", init_rc, 0, 0, false, supported, 0, 0, 0);
    if (init_rc != 0)
        return error.WorkqueueInitFailed;

    const add_rc = c.pthread_workqueue_addthreads_np(c.WORKQ_DEFAULT_PRIOQUEUE, 0, @as(c_int, @intCast(numthreads)));
    try emitResult(writer, "addthreads", if (add_rc == 0) "ok" else "error", add_rc, numthreads, 0, false, supported, default_priority, 0, 0);
    if (add_rc != 0)
        return error.WorkqueueAddthreadsFailed;

    const timed_out = waitForCallbacks(numthreads, timeout_ms);
    const observed = callback_count.load(.seq_cst);
    const priority = last_priority.load(.seq_cst);
    const narrow_true = narrow_true_count.load(.seq_cst);
    const narrow_false = narrow_false_count.load(.seq_cst);

    try emitResult(
        writer,
        "callbacks",
        if (!timed_out and observed >= numthreads) "ok" else "error",
        0,
        numthreads,
        observed,
        timed_out,
        supported,
        priority,
        narrow_true,
        narrow_false,
    );

    if (timed_out or observed < numthreads)
        return error.WorkqueueCallbacksIncomplete;
}
