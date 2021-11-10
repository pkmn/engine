const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("lib/test.zig");
    tests.setBuildMode(mode);

    // FIXME: generated docs are just for zig std lib
    // const docs = b.addTest("lib/test.zig");
    // docs.emit_docs = true;
    // docs.emit_bin = false;
    // docs.output_dir = "docs";

    const format = b.addFmt(&[_][]const u8{"."});

    const generate = b.addSystemCommand(&[_][]const u8{ "node", "tools/generate" });
    if (b.args) |args| {
        generate.addArgs(args);
    }

    b.step("test", "Run all tests").dependOn(&tests.step);
    // b.step("docs", "Generate documentation based on source files").dependOn(&docs.step);
    b.step("format", "Run zig fmt on all source files").dependOn(&format.step);
    const g = b.step("generate", "Generate src/data code");
    g.dependOn(&generate.step);
    g.dependOn(&format.step);
}
