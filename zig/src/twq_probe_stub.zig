const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("pthread.h");
    @cInclude("signal.h");
    @cInclude("sys/sysctl.h");
    @cInclude("sys/types.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});

const sys_twq_kernreturn: c_long = 468;
const twq_op_init: i32 = 0x001;
const twq_op_thread_enter: i32 = 0x002;
const twq_op_thread_return: i32 = 0x004;
const twq_op_reqthreads: i32 = 0x020;
const twq_op_should_narrow: i32 = 0x200;
const twq_op_setup_dispatch: i32 = 0x400;
const twq_spi_version_current: u32 = 20170201;
const twq_dispatch_config_version: u32 = 2;

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

const TwqShouldNarrowArgs = extern struct {
    version: u32,
    flags: u32,
    reserved0: u32,
    reserved1: u32,
    priority: u64,
};

const TwqDispatchConfig = extern struct {
    version: u32,
    flags: u32,
    queue_serialno_offs: u64,
    queue_label_offs: u64,
};

const Mode = enum {
    raw,
    init,
    thread_enter,
    setup_dispatch,
    reqthreads,
    should_narrow,
    thread_return,
};

const Sequence = enum {
    none,
    basic,
    pressure,
    entered_pressure,
};

const EnterThreadState = extern struct {
    priority: u64,
    rc: c_long,
    err: c_int,
};

const ChildResult = extern struct {
    rc: c_long,
    err: c_int,
};

fn errnoName(err: i32) []const u8 {
    return switch (err) {
        0 => "OK",
        c.ENOSYS => "ENOSYS",
        c.ENOTSUP => "ENOTSUP",
        c.EINVAL => "EINVAL",
        c.EFAULT => "EFAULT",
        c.EPERM => "EPERM",
        else => "UNKNOWN",
    };
}

fn signalName(sig: i32) []const u8 {
    return switch (sig) {
        c.SIGSYS => "SIGSYS",
        c.SIGSEGV => "SIGSEGV",
        c.SIGBUS => "SIGBUS",
        c.SIGILL => "SIGILL",
        c.SIGABRT => "SIGABRT",
        else => "UNKNOWN",
    };
}

fn parseIntArg(value: []const u8) !i32 {
    return try std.fmt.parseInt(i32, value, 0);
}

fn parseU32Arg(value: []const u8) !u32 {
    return try std.fmt.parseInt(u32, value, 0);
}

fn parseU64Arg(value: []const u8) !u64 {
    return try std.fmt.parseInt(u64, value, 0);
}

fn parseMode(value: []const u8) !Mode {
    if (std.mem.eql(u8, value, "raw")) return .raw;
    if (std.mem.eql(u8, value, "init")) return .init;
    if (std.mem.eql(u8, value, "thread-enter")) return .thread_enter;
    if (std.mem.eql(u8, value, "setup-dispatch")) return .setup_dispatch;
    if (std.mem.eql(u8, value, "reqthreads")) return .reqthreads;
    if (std.mem.eql(u8, value, "should-narrow")) return .should_narrow;
    if (std.mem.eql(u8, value, "thread-return")) return .thread_return;
    return error.UnknownMode;
}

fn parseSequence(value: []const u8) !Sequence {
    if (std.mem.eql(u8, value, "basic")) return .basic;
    if (std.mem.eql(u8, value, "pressure")) return .pressure;
    if (std.mem.eql(u8, value, "entered-pressure")) return .entered_pressure;
    return error.UnknownSequence;
}

fn modeName(mode: Mode) []const u8 {
    return switch (mode) {
        .raw => "raw",
        .init => "init",
        .thread_enter => "thread-enter",
        .setup_dispatch => "setup-dispatch",
        .reqthreads => "reqthreads",
        .should_narrow => "should-narrow",
        .thread_return => "thread-return",
    };
}

fn syscallStatus(err: i32) []const u8 {
    return if (err == 0) "ok" else "syscall_error";
}

fn emitResult(
    writer: anytype,
    mode: []const u8,
    op: i32,
    arg3: i32,
    arg4: i32,
    rc: c_long,
    err: i32,
) !void {
    try writer.print(
        "{{\"kind\":\"zig-probe\",\"status\":\"{s}\",\"data\":{{\"mode\":\"{s}\",\"syscall\":{d},\"op\":{d},\"arg3\":{d},\"arg4\":{d},\"rc\":{d},\"errno\":{d},\"errno_name\":\"{s}\"}},\"meta\":{{\"component\":\"zig\",\"binary\":\"twq-probe-stub\"}}}}\n",
        .{ syscallStatus(err), mode, sys_twq_kernreturn, op, arg3, arg4, rc, err, errnoName(err) },
    );
}

fn enterThreadMain(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const state = @as(*EnterThreadState, @ptrCast(@alignCast(arg.?)));
    state.*.rc = -1;
    state.*.err = 0;
    const priority = @as(i32, @intCast(@min(state.priority, std.math.maxInt(i32))));
    const result = invokeSyscall(twq_op_thread_enter, null, priority, 0);
    state.*.rc = result.rc;
    state.*.err = result.err;
    _ = c.usleep(20_000);
    return null;
}

fn invokeSyscall(op: i32, arg2: ?*anyopaque, arg3: i32, arg4: i32) ChildResult {
    @as(*c_int, c.__error()).* = 0;
    const rc = c.syscall(sys_twq_kernreturn, op, arg2, arg3, arg4);
    const err = if (rc == -1) @as(i32, c.__error().*) else 0;
    return .{
        .rc = rc,
        .err = err,
    };
}

fn runBasicSequence(writer: anytype, priority: u64, count: u32, requested_features: u32) !void {
    const req_count = if (count == 0) @as(u32, 2) else count;
    var init_args = TwqInitArgs{
        .version = twq_spi_version_current,
        .flags = 0,
        .requested_features = requested_features,
        .reserved = 0,
        .dispatch_func = 0xfeed_face_feed_0001,
        .stack_size = 0x20_000,
        .guard_size = 0x4_000,
    };
    var req_args = TwqReqthreadsArgs{
        .version = 1,
        .flags = 0,
        .reqcount = req_count,
        .reserved = 0,
        .priority = priority,
    };
    var narrow_args = TwqShouldNarrowArgs{
        .version = 1,
        .flags = 0,
        .reserved0 = 0,
        .reserved1 = 0,
        .priority = priority,
    };
    var dispatch_cfg = TwqDispatchConfig{
        .version = twq_dispatch_config_version,
        .flags = 0,
        .queue_serialno_offs = 16,
        .queue_label_offs = 24,
    };

    var result = invokeSyscall(
        twq_op_init,
        @ptrCast(&init_args),
        @intCast(@sizeOf(TwqInitArgs)),
        0,
    );
    try emitResult(writer, "init", twq_op_init, @intCast(@sizeOf(TwqInitArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_setup_dispatch,
        @ptrCast(&dispatch_cfg),
        @intCast(@sizeOf(TwqDispatchConfig)),
        0,
    );
    try emitResult(writer, "setup-dispatch", twq_op_setup_dispatch, @intCast(@sizeOf(TwqDispatchConfig)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_reqthreads,
        @ptrCast(&req_args),
        @intCast(@sizeOf(TwqReqthreadsArgs)),
        0,
    );
    try emitResult(writer, "reqthreads", twq_op_reqthreads, @intCast(@sizeOf(TwqReqthreadsArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_should_narrow,
        @ptrCast(&narrow_args),
        @intCast(@sizeOf(TwqShouldNarrowArgs)),
        0,
    );
    try emitResult(writer, "should-narrow", twq_op_should_narrow, @intCast(@sizeOf(TwqShouldNarrowArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_thread_return,
        null,
        @intCast(@min(priority, std.math.maxInt(i32))),
        0,
    );
    try emitResult(writer, "thread-return", twq_op_thread_return, @intCast(@min(priority, std.math.maxInt(i32))), 0, result.rc, result.err);

    _ = c.usleep(1_000);

    result = invokeSyscall(
        twq_op_should_narrow,
        @ptrCast(&narrow_args),
        @intCast(@sizeOf(TwqShouldNarrowArgs)),
        0,
    );
    try emitResult(writer, "should-narrow", twq_op_should_narrow, @intCast(@sizeOf(TwqShouldNarrowArgs)), 0, result.rc, result.err);

    req_args.reqcount = 0;
    result = invokeSyscall(
        twq_op_reqthreads,
        @ptrCast(&req_args),
        @intCast(@sizeOf(TwqReqthreadsArgs)),
        0,
    );
    try emitResult(writer, "reqthreads", twq_op_reqthreads, @intCast(@sizeOf(TwqReqthreadsArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_should_narrow,
        @ptrCast(&narrow_args),
        @intCast(@sizeOf(TwqShouldNarrowArgs)),
        0,
    );
    try emitResult(writer, "should-narrow", twq_op_should_narrow, @intCast(@sizeOf(TwqShouldNarrowArgs)), 0, result.rc, result.err);

    result = invokeSyscall(9999, null, 0, 0);
    try emitResult(writer, "raw", 9999, 0, 0, result.rc, result.err);
}

fn runPressureSequence(writer: anytype, requested_features: u32) !void {
    const default_priority: u64 = @as(u64, 0x15) << 8;
    const interactive_priority: u64 = @as(u64, 0x21) << 8;
    var init_args = TwqInitArgs{
        .version = twq_spi_version_current,
        .flags = 0,
        .requested_features = requested_features,
        .reserved = 0,
        .dispatch_func = 0xfeed_face_feed_0001,
        .stack_size = 0x20_000,
        .guard_size = 0x4_000,
    };
    var interactive_req = TwqReqthreadsArgs{
        .version = 1,
        .flags = 0,
        .reqcount = 1,
        .reserved = 0,
        .priority = interactive_priority,
    };
    var default_req = TwqReqthreadsArgs{
        .version = 1,
        .flags = 0,
        .reqcount = 4,
        .reserved = 0,
        .priority = default_priority,
    };
    var dispatch_cfg = TwqDispatchConfig{
        .version = twq_dispatch_config_version,
        .flags = 0,
        .queue_serialno_offs = 16,
        .queue_label_offs = 24,
    };
    var result = invokeSyscall(
        twq_op_init,
        @ptrCast(&init_args),
        @intCast(@sizeOf(TwqInitArgs)),
        0,
    );
    try emitResult(writer, "init", twq_op_init, @intCast(@sizeOf(TwqInitArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_setup_dispatch,
        @ptrCast(&dispatch_cfg),
        @intCast(@sizeOf(TwqDispatchConfig)),
        0,
    );
    try emitResult(writer, "setup-dispatch", twq_op_setup_dispatch, @intCast(@sizeOf(TwqDispatchConfig)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_reqthreads,
        @ptrCast(&interactive_req),
        @intCast(@sizeOf(TwqReqthreadsArgs)),
        0,
    );
    try emitResult(writer, "reqthreads", twq_op_reqthreads, @intCast(@sizeOf(TwqReqthreadsArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_thread_return,
        null,
        @intCast(@min(interactive_priority, std.math.maxInt(i32))),
        0,
    );
    try emitResult(writer, "thread-return", twq_op_thread_return, @intCast(@min(interactive_priority, std.math.maxInt(i32))), 0, result.rc, result.err);

    _ = c.usleep(1_000);

    result = invokeSyscall(
        twq_op_reqthreads,
        @ptrCast(&default_req),
        @intCast(@sizeOf(TwqReqthreadsArgs)),
        0,
    );
    try emitResult(writer, "reqthreads", twq_op_reqthreads, @intCast(@sizeOf(TwqReqthreadsArgs)), 0, result.rc, result.err);

    result = invokeSyscall(9999, null, 0, 0);
    try emitResult(writer, "raw", 9999, 0, 0, result.rc, result.err);
}

fn runEnteredPressureSequence(writer: anytype, requested_features: u32) !void {
    const default_priority: u64 = @as(u64, 0x15) << 8;
    const interactive_priority: u64 = @as(u64, 0x21) << 8;
    var init_args = TwqInitArgs{
        .version = twq_spi_version_current,
        .flags = 0,
        .requested_features = requested_features,
        .reserved = 0,
        .dispatch_func = 0xfeed_face_feed_0001,
        .stack_size = 0x20_000,
        .guard_size = 0x4_000,
    };
    var default_req = TwqReqthreadsArgs{
        .version = 1,
        .flags = 0,
        .reqcount = 4,
        .reserved = 0,
        .priority = default_priority,
    };
    var dispatch_cfg = TwqDispatchConfig{
        .version = twq_dispatch_config_version,
        .flags = 0,
        .queue_serialno_offs = 16,
        .queue_label_offs = 24,
    };
    var result = invokeSyscall(
        twq_op_init,
        @ptrCast(&init_args),
        @intCast(@sizeOf(TwqInitArgs)),
        0,
    );
    try emitResult(writer, "init", twq_op_init, @intCast(@sizeOf(TwqInitArgs)), 0, result.rc, result.err);

    result = invokeSyscall(
        twq_op_setup_dispatch,
        @ptrCast(&dispatch_cfg),
        @intCast(@sizeOf(TwqDispatchConfig)),
        0,
    );
    try emitResult(writer, "setup-dispatch", twq_op_setup_dispatch, @intCast(@sizeOf(TwqDispatchConfig)), 0, result.rc, result.err);

    var worker_state = EnterThreadState{
        .priority = interactive_priority,
        .rc = -1,
        .err = c.EAGAIN,
    };
    var worker: c.pthread_t = undefined;
    const create_err = c.pthread_create(&worker, null, enterThreadMain, &worker_state);
    if (create_err != 0) {
        return error.ThreadCreateFailed;
    }

    _ = c.usleep(1_000);
    try emitResult(
        writer,
        "thread-enter",
        twq_op_thread_enter,
        @as(i32, @intCast(@min(interactive_priority, std.math.maxInt(i32)))),
        0,
        worker_state.rc,
        worker_state.err,
    );

    result = invokeSyscall(
        twq_op_reqthreads,
        @ptrCast(&default_req),
        @intCast(@sizeOf(TwqReqthreadsArgs)),
        0,
    );
    try emitResult(writer, "reqthreads", twq_op_reqthreads, @intCast(@sizeOf(TwqReqthreadsArgs)), 0, result.rc, result.err);

    _ = c.pthread_join(worker, null);

    result = invokeSyscall(9999, null, 0, 0);
    try emitResult(writer, "raw", 9999, 0, 0, result.rc, result.err);
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const argv = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, argv);

    var mode: Mode = .raw;
    var sequence: Sequence = .none;
    var op: i32 = 1;
    var arg3: i32 = 0;
    var arg4: i32 = 0;
    var priority: u64 = 0;
    var count: u32 = 0;
    var requested_features: u32 = 0;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            mode = try parseMode(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--sequence")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            sequence = try parseSequence(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--op")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            op = try parseIntArg(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--arg3")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            arg3 = try parseIntArg(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--arg4")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            arg4 = try parseIntArg(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--priority")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            priority = try parseU64Arg(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--count")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            count = try parseU32Arg(argv[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--requested-features")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            requested_features = try parseU32Arg(argv[i]);
            continue;
        }
        return error.UnknownArgument;
    }

    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;

    if (sequence != .none) {
        switch (sequence) {
            .none => unreachable,
            .basic => try runBasicSequence(writer, priority, count, requested_features),
            .pressure => try runPressureSequence(writer, requested_features),
            .entered_pressure => try runEnteredPressureSequence(writer, requested_features),
        }
        return;
    }

    var display_op = op;
    var display_arg3 = arg3;
    var display_arg4 = arg4;

    switch (mode) {
        .raw => {},
        .init => {
            display_op = twq_op_init;
            display_arg3 = @intCast(@sizeOf(TwqInitArgs));
            display_arg4 = 0;
        },
        .thread_enter => {
            display_op = twq_op_thread_enter;
            display_arg3 = @intCast(@min(priority, std.math.maxInt(i32)));
            display_arg4 = 0;
        },
        .setup_dispatch => {
            display_op = twq_op_setup_dispatch;
            display_arg3 = @intCast(@sizeOf(TwqDispatchConfig));
            display_arg4 = 0;
        },
        .reqthreads => {
            display_op = twq_op_reqthreads;
            display_arg3 = @intCast(@sizeOf(TwqReqthreadsArgs));
            display_arg4 = 0;
        },
        .should_narrow => {
            display_op = twq_op_should_narrow;
            display_arg3 = @intCast(@sizeOf(TwqShouldNarrowArgs));
            display_arg4 = 0;
        },
        .thread_return => {
            display_op = twq_op_thread_return;
            display_arg3 = @intCast(@min(priority, std.math.maxInt(i32)));
            display_arg4 = 0;
        },
    }

    var pipefd: [2]c_int = undefined;
    if (c.pipe(&pipefd) != 0) return error.PipeFailed;

    const pid = c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        _ = c.close(pipefd[0]);
        @as(*c_int, c.__error()).* = 0;
        var init_args = TwqInitArgs{
            .version = twq_spi_version_current,
            .flags = 0,
            .requested_features = requested_features,
            .reserved = 0,
            .dispatch_func = 0xfeed_face_feed_0001,
            .stack_size = 0x20_000,
            .guard_size = 0x4_000,
        };
        var req_args = TwqReqthreadsArgs{
            .version = 1,
            .flags = 0,
            .reqcount = count,
            .reserved = 0,
            .priority = priority,
        };
        var narrow_args = TwqShouldNarrowArgs{
            .version = 1,
            .flags = 0,
            .reserved0 = 0,
            .reserved1 = 0,
            .priority = priority,
        };
        var dispatch_cfg = TwqDispatchConfig{
            .version = twq_dispatch_config_version,
            .flags = 0,
            .queue_serialno_offs = 16,
            .queue_label_offs = 24,
        };

        var child_op = op;
        var child_arg3 = arg3;
        var child_arg4 = arg4;
        var child_arg2: ?*anyopaque = null;

        switch (mode) {
            .raw => {},
            .init => {
                child_op = twq_op_init;
                child_arg2 = @ptrCast(&init_args);
                child_arg3 = @intCast(@sizeOf(TwqInitArgs));
                child_arg4 = 0;
            },
            .thread_enter => {
                child_op = twq_op_thread_enter;
                child_arg3 = @intCast(@min(priority, std.math.maxInt(i32)));
                child_arg4 = 0;
            },
            .setup_dispatch => {
                child_op = twq_op_setup_dispatch;
                child_arg2 = @ptrCast(&dispatch_cfg);
                child_arg3 = @intCast(@sizeOf(TwqDispatchConfig));
                child_arg4 = 0;
            },
            .reqthreads => {
                child_op = twq_op_reqthreads;
                child_arg2 = @ptrCast(&req_args);
                child_arg3 = @intCast(@sizeOf(TwqReqthreadsArgs));
                child_arg4 = 0;
            },
            .should_narrow => {
                child_op = twq_op_should_narrow;
                child_arg2 = @ptrCast(&narrow_args);
                child_arg3 = @intCast(@sizeOf(TwqShouldNarrowArgs));
                child_arg4 = 0;
            },
            .thread_return => {
                child_op = twq_op_thread_return;
                child_arg2 = @as(?*anyopaque, null);
                child_arg3 = @intCast(@min(priority, std.math.maxInt(i32)));
                child_arg4 = 0;
            },
        }

        const rc = c.syscall(sys_twq_kernreturn, child_op, child_arg2, child_arg3, child_arg4);
        const err = if (rc == -1) @as(i32, c.__error().*) else 0;
        const result = ChildResult{
            .rc = rc,
            .err = err,
        };
        _ = c.write(pipefd[1], @ptrCast(&result), @sizeOf(ChildResult));
        c._exit(0);
    }

    _ = c.close(pipefd[1]);

    var result = ChildResult{
        .rc = 0,
        .err = 0,
    };
    const read_len = c.read(pipefd[0], @ptrCast(&result), @sizeOf(ChildResult));
    _ = c.close(pipefd[0]);

    var status_word: c_int = 0;
    _ = c.waitpid(pid, &status_word, 0);

    if (c.WIFSIGNALED(status_word)) {
        const sig = c.WTERMSIG(status_word);
        try writer.print(
            "{{\"kind\":\"zig-probe\",\"status\":\"signal\",\"data\":{{\"mode\":\"{s}\",\"syscall\":{d},\"op\":{d},\"arg3\":{d},\"arg4\":{d},\"signal\":{d},\"signal_name\":\"{s}\"}},\"meta\":{{\"component\":\"zig\",\"binary\":\"twq-probe-stub\"}}}}\n",
            .{ modeName(mode), sys_twq_kernreturn, display_op, display_arg3, display_arg4, sig, signalName(sig) },
        );
        return;
    }

    const rc = if (read_len == @sizeOf(ChildResult)) result.rc else -1;
    const err = if (read_len == @sizeOf(ChildResult)) @as(i32, result.err) else c.EIO;
    try emitResult(writer, modeName(mode), display_op, display_arg3, display_arg4, rc, err);
}
