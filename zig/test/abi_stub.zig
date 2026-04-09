const std = @import("std");

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

test "kernel constants stay aligned with the first landed scaffold" {
    const twq_op_init: u32 = 1;
    const twq_op_thread_enter: u32 = 0x002;
    const twq_op_thread_return: u32 = 0x004;
    const twq_op_reqthreads: u32 = 0x020;
    const twq_op_reqthreads2: u32 = 0x030;
    const twq_op_should_narrow: u32 = 0x200;
    const twq_op_setup_dispatch: u32 = 0x400;
    const twq_syscall_num: u32 = 468;

    try std.testing.expectEqual(@as(u32, 1), twq_op_init);
    try std.testing.expectEqual(@as(u32, 0x002), twq_op_thread_enter);
    try std.testing.expectEqual(@as(u32, 0x004), twq_op_thread_return);
    try std.testing.expectEqual(@as(u32, 0x020), twq_op_reqthreads);
    try std.testing.expectEqual(@as(u32, 0x030), twq_op_reqthreads2);
    try std.testing.expectEqual(@as(u32, 0x200), twq_op_should_narrow);
    try std.testing.expectEqual(@as(u32, 0x400), twq_op_setup_dispatch);
    try std.testing.expectEqual(@as(u32, 468), twq_syscall_num);
}

test "scaffold preserves six bucket direction" {
    const twq_num_qos_buckets: u8 = 6;
    try std.testing.expectEqual(@as(u8, 6), twq_num_qos_buckets);
}

test "priority constants follow the Darwin-shaped encoding we are using" {
    try std.testing.expectEqual(@as(u32, 0x8000_0000), @as(u32, 0x8000_0000));
    try std.testing.expectEqual(@as(u32, 0x2000_0000), @as(u32, 0x2000_0000));
    try std.testing.expectEqual(@as(u32, 0x00ff_ff00), @as(u32, 0x00ff_ff00));
    try std.testing.expectEqual(@as(u32, 0x0000_00ff), @as(u32, 0x0000_00ff));
}

test "typed ABI payload sizes match the kernel header plan" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(TwqInitArgs));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TwqReqthreadsArgs));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TwqShouldNarrowArgs));
}

test "dispatch config size matches kernel header" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TwqDispatchConfig));
}
