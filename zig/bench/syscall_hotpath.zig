const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("sys/sysctl.h");
    @cInclude("unistd.h");
});

const sys_twq_kernreturn: c_long = 468;
const twq_op_init: i32 = 0x001;
const twq_op_thread_enter: i32 = 0x002;
const twq_op_thread_return: i32 = 0x004;
const twq_op_thread_transfer: i32 = 0x008;
const twq_op_reqthreads: i32 = 0x020;
const twq_op_should_narrow: i32 = 0x200;
const twq_op_setup_dispatch: i32 = 0x400;
const twq_spi_version_current: u32 = 20170201;
const twq_dispatch_config_version: u32 = 2;
const twq_reqthreads_version: u32 = 1;
const twq_thread_transfer_version: u32 = 1;
const default_priority: u64 = @as(u64, 0x15) << 8;
const overcommit_flag: u64 = 0x8000_0000;

const Mode = enum {
    should_narrow,
    reqthreads,
    reqthreads_overcommit,
    thread_enter,
    thread_return,
    thread_transfer,
};

const TwqInitArgs = extern struct {
    version: u32,
    flags: u32,
    requested_features: u32,
    reserved: u32,
    dispatch_func: u64,
    stack_size: u64,
    guard_size: u64,
};

const TwqReqthreadsArgs = extern struct {
    version: u32,
    flags: u32,
    reqcount: u32,
    reserved: u32,
    priority: u64,
};

const TwqThreadTransferArgs = extern struct {
    version: u32,
    flags: u32,
    from_reqcount: u32,
    reserved: u32,
    from_priority: u64,
    to_priority: u64,
};

const TwqDispatchConfig = extern struct {
    version: u32,
    flags: u32,
    queue_serialno_offs: u64,
    queue_label_offs: u64,
};

const ChildResult = struct {
    rc: c_long,
    err: i32,
};

const CounterSnapshot = struct {
    init_count: u64,
    reqthreads_count: u64,
    thread_enter_count: u64,
    thread_return_count: u64,
    thread_transfer_count: u64,
};

const CounterDelta = struct {
    init_count: u64,
    reqthreads_count: u64,
    thread_enter_count: u64,
    thread_return_count: u64,
    thread_transfer_count: u64,
};

const Stats = struct {
    mean_ns: u64,
    median_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    min_ns: u64,
    max_ns: u64,
    stddev_ns: u64,
};

const Config = struct {
    mode: Mode = .should_narrow,
    samples: usize = 2048,
    warmup: usize = 256,
    request_count: u16 = 1,
    requested_features: u32 = 0,
    settle_ms: u32 = 50,
};

fn parseMode(value: []const u8) !Mode {
    if (std.mem.eql(u8, value, "should-narrow")) return .should_narrow;
    if (std.mem.eql(u8, value, "reqthreads")) return .reqthreads;
    if (std.mem.eql(u8, value, "reqthreads-overcommit")) return .reqthreads_overcommit;
    if (std.mem.eql(u8, value, "thread-enter")) return .thread_enter;
    if (std.mem.eql(u8, value, "thread-return")) return .thread_return;
    if (std.mem.eql(u8, value, "thread-transfer")) return .thread_transfer;
    return error.UnknownMode;
}

fn modeName(mode: Mode) []const u8 {
    return switch (mode) {
        .should_narrow => "should-narrow",
        .reqthreads => "reqthreads",
        .reqthreads_overcommit => "reqthreads-overcommit",
        .thread_enter => "thread-enter",
        .thread_return => "thread-return",
        .thread_transfer => "thread-transfer",
    };
}

fn parseArgs() !Config {
    var config = Config{};
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--mode")) {
            const value = args.next() orelse return error.MissingValue;
            config.mode = try parseMode(value);
            continue;
        }
        if (std.mem.eql(u8, arg, "--samples")) {
            const value = args.next() orelse return error.MissingValue;
            config.samples = try std.fmt.parseInt(usize, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--warmup")) {
            const value = args.next() orelse return error.MissingValue;
            config.warmup = try std.fmt.parseInt(usize, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--request-count")) {
            const value = args.next() orelse return error.MissingValue;
            config.request_count = try std.fmt.parseInt(u16, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--requested-features")) {
            const value = args.next() orelse return error.MissingValue;
            config.requested_features = try std.fmt.parseInt(u32, value, 0);
            continue;
        }
        if (std.mem.eql(u8, arg, "--settle-ms")) {
            const value = args.next() orelse return error.MissingValue;
            config.settle_ms = try std.fmt.parseInt(u32, value, 10);
            continue;
        }
        return error.UnknownArgument;
    }

    if (config.samples == 0) return error.InvalidSampleCount;
    return config;
}

fn invokeSyscall(op: i32, arg2: ?*anyopaque, arg3: i32, arg4: i32) ChildResult {
    @as(*c_int, c.__error()).* = 0;
    const rc = c.syscall(sys_twq_kernreturn, op, arg2, arg3, arg4);
    const err = if (rc == -1) @as(i32, c.__error().*) else 0;
    return .{ .rc = rc, .err = err };
}

fn readCounterSnapshot() !CounterSnapshot {
    return .{
        .init_count = try readSysctlU64("kern.twq.init_count"),
        .reqthreads_count = try readSysctlU64("kern.twq.reqthreads_count"),
        .thread_enter_count = try readSysctlU64("kern.twq.thread_enter_count"),
        .thread_return_count = try readSysctlU64("kern.twq.thread_return_count"),
        .thread_transfer_count = try readSysctlU64("kern.twq.thread_transfer_count"),
    };
}

fn deltaCounters(before: CounterSnapshot, after: CounterSnapshot) CounterDelta {
    return .{
        .init_count = after.init_count - before.init_count,
        .reqthreads_count = after.reqthreads_count - before.reqthreads_count,
        .thread_enter_count = after.thread_enter_count - before.thread_enter_count,
        .thread_return_count = after.thread_return_count - before.thread_return_count,
        .thread_transfer_count = after.thread_transfer_count - before.thread_transfer_count,
    };
}

fn readSysctlU64(name: [:0]const u8) !u64 {
    var value: u64 = 0;
    var len: usize = @sizeOf(u64);
    if (c.sysctlbyname(name, &value, &len, null, 0) != 0) {
        return error.SysctlFailed;
    }
    return value;
}

fn readSysctlString(allocator: std.mem.Allocator, name: [:0]const u8) ![]u8 {
    var len: usize = 0;
    if (c.sysctlbyname(name, null, &len, null, 0) != 0) {
        return allocator.dupe(u8, "");
    }

    const alloc_len = if (len == 0) @as(usize, 1) else len;
    var buf = try allocator.alloc(u8, alloc_len);
    defer allocator.free(buf);

    if (c.sysctlbyname(name, buf.ptr, &len, null, 0) != 0) {
        return allocator.dupe(u8, "");
    }
    if (len == 0) {
        return allocator.dupe(u8, "");
    }
    const actual_len = if (buf[len - 1] == 0) len - 1 else len;
    return allocator.dupe(u8, buf[0..actual_len]);
}

fn currentPriority(mode: Mode) u64 {
    return switch (mode) {
        .should_narrow,
        .reqthreads,
        .thread_enter,
        .thread_return,
        .thread_transfer,
        => default_priority,
        .reqthreads_overcommit => default_priority | overcommit_flag,
    };
}

fn transferPriority() u64 {
    return default_priority | overcommit_flag;
}

fn priorityArg(priority: u64) i32 {
    return @bitCast(@as(u32, @truncate(priority)));
}

fn initRuntime(config: Config) !i32 {
    var init_args = TwqInitArgs{
        .version = twq_spi_version_current,
        .flags = 0,
        .requested_features = config.requested_features,
        .reserved = 0,
        .dispatch_func = 0xfeed_face_feed_0001,
        .stack_size = 0x20_000,
        .guard_size = 0x4_000,
    };
    var dispatch_cfg = TwqDispatchConfig{
        .version = twq_dispatch_config_version,
        .flags = 0,
        .queue_serialno_offs = 16,
        .queue_label_offs = 24,
    };

    const init_result = invokeSyscall(
        twq_op_init,
        @ptrCast(&init_args),
        @intCast(@sizeOf(TwqInitArgs)),
        0,
    );
    if (init_result.err != 0) return error.WorkqueueInitFailed;

    const dispatch_result = invokeSyscall(
        twq_op_setup_dispatch,
        @ptrCast(&dispatch_cfg),
        @intCast(@sizeOf(TwqDispatchConfig)),
        0,
    );
    if (dispatch_result.err != 0) return error.WorkqueueSetupDispatchFailed;

    return @intCast(init_result.rc);
}

fn performWarmup(config: Config, priority: u64) void {
    var req_args = TwqReqthreadsArgs{
        .version = twq_reqthreads_version,
        .flags = 0,
        .reqcount = config.request_count,
        .reserved = 0,
        .priority = priority,
    };
    var transfer_args = TwqThreadTransferArgs{
        .version = twq_thread_transfer_version,
        .flags = 0,
        .from_reqcount = config.request_count,
        .reserved = 0,
        .from_priority = priority,
        .to_priority = transferPriority(),
    };

    var i: usize = 0;
    while (i < config.warmup) : (i += 1) {
        switch (config.mode) {
            .should_narrow => {
                _ = invokeSyscall(twq_op_should_narrow, null, priorityArg(priority), 0);
            },
            .reqthreads, .reqthreads_overcommit => {
                _ = invokeSyscall(
                    twq_op_reqthreads,
                    @ptrCast(&req_args),
                    @intCast(@sizeOf(TwqReqthreadsArgs)),
                    0,
                );
            },
            .thread_enter => {
                _ = invokeSyscall(
                    twq_op_thread_enter,
                    null,
                    priorityArg(priority),
                    0,
                );
                _ = invokeSyscall(
                    twq_op_thread_return,
                    null,
                    priorityArg(priority),
                    0,
                );
            },
            .thread_return => {
                _ = invokeSyscall(
                    twq_op_thread_enter,
                    null,
                    priorityArg(priority),
                    0,
                );
                _ = invokeSyscall(
                    twq_op_thread_return,
                    null,
                    priorityArg(priority),
                    0,
                );
            },
            .thread_transfer => {
                _ = invokeSyscall(
                    twq_op_thread_enter,
                    null,
                    priorityArg(priority),
                    0,
                );
                _ = invokeSyscall(
                    twq_op_thread_transfer,
                    @ptrCast(&transfer_args),
                    @intCast(@sizeOf(TwqThreadTransferArgs)),
                    0,
                );
                _ = invokeSyscall(
                    twq_op_thread_return,
                    null,
                    priorityArg(transferPriority()),
                    0,
                );
            },
        }
    }
}

fn recordError(result: ChildResult, sample_errors: *u64, last_error: *i32) void {
    if (result.err != 0) {
        sample_errors.* += 1;
        last_error.* = result.err;
    }
}

fn recordSamples(config: Config, samples: []u64, priority: u64) struct {
    bool_true_count: u64,
    bool_false_count: u64,
    return_sum: i64,
    sample_errors: u64,
    last_error: i32,
} {
    var req_args = TwqReqthreadsArgs{
        .version = twq_reqthreads_version,
        .flags = 0,
        .reqcount = config.request_count,
        .reserved = 0,
        .priority = priority,
    };
    var transfer_args = TwqThreadTransferArgs{
        .version = twq_thread_transfer_version,
        .flags = 0,
        .from_reqcount = config.request_count,
        .reserved = 0,
        .from_priority = priority,
        .to_priority = transferPriority(),
    };

    var bool_true_count: u64 = 0;
    var bool_false_count: u64 = 0;
    var return_sum: i64 = 0;
    var sample_errors: u64 = 0;
    var last_error: i32 = 0;

    for (samples) |*sample| {
        var cleanup_result = ChildResult{ .rc = 0, .err = 0 };
        var setup_result = ChildResult{ .rc = 0, .err = 0 };

        if (config.mode == .thread_return or config.mode == .thread_transfer) {
            setup_result = invokeSyscall(
                twq_op_thread_enter,
                null,
                priorityArg(priority),
                0,
            );
            if (setup_result.err != 0) {
                sample.* = 0;
                recordError(setup_result, &sample_errors, &last_error);
                continue;
            }
        }

        const start = std.time.nanoTimestamp();
        const result = switch (config.mode) {
            .should_narrow => invokeSyscall(
                twq_op_should_narrow,
                null,
                priorityArg(priority),
                0,
            ),
            .reqthreads, .reqthreads_overcommit => invokeSyscall(
                twq_op_reqthreads,
                @ptrCast(&req_args),
                @intCast(@sizeOf(TwqReqthreadsArgs)),
                0,
            ),
            .thread_enter => invokeSyscall(
                twq_op_thread_enter,
                null,
                priorityArg(priority),
                0,
            ),
            .thread_return => invokeSyscall(
                twq_op_thread_return,
                null,
                priorityArg(priority),
                0,
            ),
            .thread_transfer => invokeSyscall(
                twq_op_thread_transfer,
                @ptrCast(&transfer_args),
                @intCast(@sizeOf(TwqThreadTransferArgs)),
                0,
            ),
        };
        const end = std.time.nanoTimestamp();
        sample.* = @intCast(end - start);

        switch (config.mode) {
            .thread_enter => {
                cleanup_result = invokeSyscall(
                    twq_op_thread_return,
                    null,
                    priorityArg(priority),
                    0,
                );
            },
            .thread_transfer => {
                cleanup_result = invokeSyscall(
                    twq_op_thread_return,
                    null,
                    priorityArg(transferPriority()),
                    0,
                );
            },
            else => {},
        }

        if (result.err != 0) {
            sample_errors += 1;
            last_error = result.err;
            continue;
        }
        recordError(cleanup_result, &sample_errors, &last_error);

        return_sum += result.rc;
        if (config.mode == .should_narrow) {
            if (result.rc != 0) {
                bool_true_count += 1;
            } else {
                bool_false_count += 1;
            }
        }
    }

    return .{
        .bool_true_count = bool_true_count,
        .bool_false_count = bool_false_count,
        .return_sum = return_sum,
        .sample_errors = sample_errors,
        .last_error = last_error,
    };
}

fn waitForSettle(settle_ms: u32) void {
    if (settle_ms == 0) return;
    std.Thread.sleep(@as(u64, settle_ms) * std.time.ns_per_ms);
}

fn computeStats(allocator: std.mem.Allocator, values: []u64) !Stats {
    const sorted = try allocator.dupe(u64, values);
    defer allocator.free(sorted);

    std.sort.heap(u64, sorted, {}, comptime std.sort.asc(u64));

    var sum: u128 = 0;
    for (values) |value| {
        sum += value;
    }
    const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(values.len));

    var variance_sum: f64 = 0;
    for (values) |value| {
        const delta = @as(f64, @floatFromInt(value)) - mean;
        variance_sum += delta * delta;
    }
    const variance = variance_sum / @as(f64, @floatFromInt(values.len));

    return .{
        .mean_ns = @intFromFloat(@round(mean)),
        .median_ns = percentile(sorted, 50),
        .p95_ns = percentile(sorted, 95),
        .p99_ns = percentile(sorted, 99),
        .min_ns = sorted[0],
        .max_ns = sorted[sorted.len - 1],
        .stddev_ns = @intFromFloat(@round(@sqrt(variance))),
    };
}

fn percentile(sorted: []const u64, pct: u8) u64 {
    if (sorted.len == 1) return sorted[0];
    const rank = (@as(u128, sorted.len - 1) * pct) / 100;
    return sorted[@intCast(rank)];
}

fn emitJsonEscaped(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |ch| switch (ch) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.writeByte(ch),
    };
    try writer.writeByte('"');
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseArgs();
    const priority = currentPriority(config.mode);

    const kernel_ident = try readSysctlString(allocator, "kern.ident");
    defer allocator.free(kernel_ident);
    const kernel_osrelease = try readSysctlString(allocator, "kern.osrelease");
    defer allocator.free(kernel_osrelease);
    const kernel_bootfile = try readSysctlString(allocator, "kern.bootfile");
    defer allocator.free(kernel_bootfile);

    const init_features = try initRuntime(config);
    performWarmup(config, priority);
    waitForSettle(config.settle_ms);

    const before = try readCounterSnapshot();
    const samples = try allocator.alloc(u64, config.samples);
    defer allocator.free(samples);

    const results = recordSamples(config, samples, priority);
    waitForSettle(config.settle_ms);
    const after = try readCounterSnapshot();
    const stats = try computeStats(allocator, samples);
    const delta = deltaCounters(before, after);

    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;

    try writer.writeAll("{\"kind\":\"zig-bench\",\"status\":");
    try emitJsonEscaped(writer, if (results.sample_errors == 0) "ok" else "error");
    try writer.writeAll(",\"data\":{");
    try writer.print(
        "\"benchmark\":\"syscall-hotpath\",\"mode\":\"{s}\",\"samples\":{d},\"warmup\":{d},\"request_count\":{d},\"requested_features\":{d},\"settle_ms\":{d},\"init_features\":{d},\"priority\":{d},\"mean_ns\":{d},\"median_ns\":{d},\"p95_ns\":{d},\"p99_ns\":{d},\"min_ns\":{d},\"max_ns\":{d},\"stddev_ns\":{d},\"bool_true_count\":{d},\"bool_false_count\":{d},\"return_sum\":{d},\"sample_errors\":{d},\"last_error\":{d}",
        .{
            modeName(config.mode),
            config.samples,
            config.warmup,
            config.request_count,
            config.requested_features,
            config.settle_ms,
            init_features,
            priority,
            stats.mean_ns,
            stats.median_ns,
            stats.p95_ns,
            stats.p99_ns,
            stats.min_ns,
            stats.max_ns,
            stats.stddev_ns,
            results.bool_true_count,
            results.bool_false_count,
            results.return_sum,
            results.sample_errors,
            results.last_error,
        },
    );
    try writer.print(
        ",\"counter_delta\":{{\"init_count\":{d},\"reqthreads_count\":{d},\"thread_enter_count\":{d},\"thread_return_count\":{d},\"thread_transfer_count\":{d}}}",
        .{
            delta.init_count,
            delta.reqthreads_count,
            delta.thread_enter_count,
            delta.thread_return_count,
            delta.thread_transfer_count,
        },
    );
    try writer.writeAll("},\"meta\":{\"component\":\"zig\",\"binary\":\"twq-bench-syscall\",\"kernel_ident\":");
    try emitJsonEscaped(writer, kernel_ident);
    try writer.writeAll(",\"kernel_osrelease\":");
    try emitJsonEscaped(writer, kernel_osrelease);
    try writer.writeAll(",\"kernel_bootfile\":");
    try emitJsonEscaped(writer, kernel_bootfile);
    try writer.writeAll("}}\n");
}
