const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatability mode") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "showdown", showdown);
    options.addOption(bool, "trace", trace);

    const build_options = std.build.Pkg{ .name = "build_options", .path = options.getSource() };

    const common = std.build.Pkg{
        .name = "common",
        .path = .{ .path = "src/lib/common/main.zig" },
        .dependencies = &[_]std.build.Pkg{build_options},
    };

    const pkmn = std.build.Pkg{
        .name = "pkmn",
        .path = .{ .path = "src/lib/main.zig" },
        .dependencies = &[_]std.build.Pkg{ build_options, common },
    };

    const helpers = std.build.Pkg{
        .name = "helpers",
        .path = .{ .path = "src/lib/gen1/helpers.zig" },
        .dependencies = &[_]std.build.Pkg{ build_options, common },
    };

    const lib = b.addStaticLibrary("pkmn", "src/lib/main.zig");
    lib.addOptions("build_options", options);
    lib.setBuildMode(mode);
    lib.install();

    const test_file = b.option([]const u8, "test-file", "Input file for test") orelse "src/lib/test.zig";
    const test_bin = b.option([]const u8, "test-bin", "Emit test binary to");
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    const test_no_exec = b.option(bool, "test-no-exec", "Compiles test binary without running it") orelse false;

    const tests = if (test_no_exec) b.addTestExe("test_exe", test_file) else b.addTest(test_file);
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addPackage(common);
    tests.addOptions("build_options", options);
    tests.setBuildMode(mode);
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }

    const format = b.addFmt(&[_][]const u8{"."});

    const rng = executable(b, &[_]std.build.Pkg{common}, "src/tools/rng.zig");
    const debug = executable(b, &[_]std.build.Pkg{ pkmn, common, helpers }, "src/tools/debug.zig");
    const protocol = executable(b, &[_]std.build.Pkg{common}, "src/tools/protocol.zig");

    b.step("debug", "Run debugging tool").dependOn(&debug.step);
    b.step("format", "Format source files").dependOn(&format.step);
    b.step("protocol", "Run protocol tool").dependOn(&protocol.step);
    b.step("rng", "Run RNG calculator tool").dependOn(&rng.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
}

fn executable(b: *std.build.Builder, pkgs: []std.build.Pkg, path: []const u8) *std.build.RunStep {
    var name = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];

    const exe = b.addExecutable(name, path);
    for (pkgs) |pkg| exe.addPackage(pkg);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.install();

    const run_exe = exe.run();
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    return run_exe;
}
