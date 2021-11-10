const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // const lib = b.addStaticLibrary("pkmn", "src/main.zig");
    // lib.setBuildMode(mode);
    // lib.install();

    const main_tests = b.addTest("lib/test.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&main_tests.step);

    const main_fmts = b.addFmt(&[_][]const u8{"."});
    const fmt_step = b.step("format", "Run zig fmt on all source files");
    fmt_step.dependOn(&main_fmts.step);

    const gen_data = b.addSystemCommand(&[_][]const u8{ "node", "tools/generate" });
    if (b.args) |args| {
        gen_data.addArgs(args);
    }
    const gen_step = b.step("generate", "Generate src/data code");
    gen_step.dependOn(&gen_data.step);
    gen_step.dependOn(&main_fmts.step);
}
