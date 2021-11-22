const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/lib/test.zig");
    tests.setBuildMode(mode);

    const format = b.addFmt(&[_][]const u8{"."});

    b.step("test", "Run all tests").dependOn(&tests.step);
    b.step("format", "Format source files").dependOn(&format.step);
}
