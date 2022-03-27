const std = @import("std");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatability mode") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "showdown", showdown);
    options.addOption(bool, "trace", trace);

    const build_options = Pkg{ .name = "build_options", .path = options.getSource() };

    const pkmn = Pkg{
        .name = "pkmn",
        .path = .{ .path = "src/lib/all.zig" },
        .dependencies = &.{build_options},
    };

    const lib = b.addStaticLibrary(if (showdown) "pkmn-showdown" else "pkmn", "src/lib/pkmn.zig");
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
    tests.addOptions("build_options", options);
    tests.setBuildMode(mode);
    tests.single_threaded = true;
    tests.strip = strip;
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }

    const format = b.addFmt(&[_][]const u8{"."});

    const rng = try executable(b, &.{pkmn}, "src/tools/rng.zig", showdown, strip);
    const debug = try executable(b, &.{pkmn}, "src/tools/debug.zig", showdown, strip);
    const protocol = try executable(b, &.{pkmn}, "src/tools/protocol.zig", showdown, strip);

    b.step("debug", "Run debugging tool").dependOn(&debug.step);
    b.step("format", "Format source files").dependOn(&format.step);
    b.step("protocol", "Run protocol tool").dependOn(&protocol.step);
    b.step("rng", "Run RNG calculator tool").dependOn(&rng.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
}

fn executable(
    b: *Builder,
    pkgs: []Pkg,
    path: []const u8,
    showdown: bool,
    strip: bool,
) !*std.build.RunStep {
    var name = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (showdown) name = try std.fmt.allocPrint(b.allocator, "{s}-showdown", .{name});

    const exe = b.addExecutable(name, path);
    for (pkgs) |pkg| exe.addPackage(pkg);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.single_threaded = true;
    exe.strip = strip;
    exe.install();

    const run_exe = exe.run();
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    return run_exe;
}
