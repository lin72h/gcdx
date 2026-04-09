const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const libpthread_dir = b.option([]const u8, "libpthread-dir", "Directory containing the staged custom libpthread/libthr") orelse "/usr/lib";
    const pthread_include_dir = b.option([]const u8, "pthread-include-dir", "Directory containing pthread/workqueue_private.h") orelse "/usr/include";

    const probe = b.addExecutable(.{
        .name = "twq-probe-stub",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/twq_probe_stub.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(probe);

    const abi_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/abi_stub.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_abi_tests = b.addRunArtifact(abi_tests);
    const abi_step = b.step("test-abi", "Run ABI scaffold tests");
    abi_step.dependOn(&run_abi_tests.step);

    const bench = b.addExecutable(.{
        .name = "twq-bench-thread-return-stub",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/thread_return_stub.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(bench);

    const bench_step = b.step("bench-thread-return", "Build the thread-return benchmark stub");
    bench_step.dependOn(&bench.step);

    const workqueue_probe = b.addExecutable(.{
        .name = "twq-workqueue-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/twq_workqueue_probe.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    workqueue_probe.linkLibC();
    workqueue_probe.root_module.addIncludePath(.{ .cwd_relative = pthread_include_dir });
    workqueue_probe.root_module.addLibraryPath(.{ .cwd_relative = libpthread_dir });
    workqueue_probe.root_module.linkSystemLibrary("thr", .{});

    const install_workqueue_probe = b.addInstallArtifact(workqueue_probe, .{});
    const workqueue_probe_step = b.step("workqueue-probe", "Build the pthread_workqueue userland probe");
    workqueue_probe_step.dependOn(&install_workqueue_probe.step);
}
