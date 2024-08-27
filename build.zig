const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build library
    const lib = b.addStaticLibrary(.{
        .name = "zconn",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Examples
    const exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = b.path("examples/hello/hello.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zconn", &lib.root_module);
    b.installArtifact(exe);

    // Testing
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
