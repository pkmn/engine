const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatability mode") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "showdown", showdown);
    build_options.addOption(bool, "trace", trace);

    const tests = b.addTest("src/lib/test.zig");
    tests.addOptions("build_options", build_options);

    tests.setBuildMode(mode);

    const format = b.addFmt(&[_][]const u8{"."});

    b.step("test", "Run all tests").dependOn(&tests.step);
    b.step("format", "Format source files").dependOn(&format.step);
}
