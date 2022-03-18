const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatability mode") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "showdown", showdown);
    build_options.addOption(bool, "trace", trace);

    const test_file = b.option([]const u8, "test-file", "Input file for test") orelse "src/lib/test.zig";
    const test_bin = b.option([]const u8, "test-bin", "Emit test binary to");
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    const test_no_exec = b.option(bool, "test-no-exec", "Compiles test binary without running it") orelse false;

    const tests = if (test_no_exec) b.addTestExe("test_exe", test_file) else b.addTest(test_file);
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", build_options);
    tests.setBuildMode(mode);
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }

    const format = b.addFmt(&[_][]const u8{"."});

    const rng = b.addExecutable("rng", "src/tools/rng.zig");
    rng.addPackagePath("rng", "src/lib/common/rng.zig");
    rng.addOptions("build_options", build_options);
    rng.setBuildMode(mode);
    rng.install();

    const run_rng = rng.run();
    run_rng.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_rng.addArgs(args);
    }

    b.step("test", "Run all tests").dependOn(&tests.step);
    b.step("format", "Format source files").dependOn(&format.step);
    b.step("rng", "Run RNG calculator tool").dependOn(&run_rng.step);
}
