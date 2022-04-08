const std = @import("std");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    var parser = std.json.Parser.init(b.allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(@embedFile("package.json"));
    defer tree.deinit();

    const version = tree.root.Object.get("version").?.String;

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatability mode") orelse false;
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

    const lib = if (showdown) "pkmn-showdown" else "pkmn";

    const static_lib = b.addStaticLibrary(lib, "src/lib/binding/c.zig");
    static_lib.addOptions("build_options", options);
    static_lib.setBuildMode(mode);
    static_lib.setTarget(target);
    static_lib.addIncludeDir("src/include");
    static_lib.linkLibC();
    static_lib.strip = strip;
    static_lib.install();
    b.getInstallStep().dependOn(&static_lib.step);

    const kind = .{ .versioned = try std.builtin.Version.parse(version) };
    const dynamic_lib = b.addSharedLibrary(lib, "src/lib/binding/c.zig", kind);
    dynamic_lib.addOptions("build_options", options);
    dynamic_lib.setBuildMode(mode);
    dynamic_lib.setTarget(target);
    dynamic_lib.addIncludeDir("src/include");
    dynamic_lib.linkLibC();
    dynamic_lib.strip = strip;
    dynamic_lib.install();
    b.getInstallStep().dependOn(&dynamic_lib.step);

    const header = b.addInstallFileWithDir(
        .{ .path = "src/include/pkmn.h" },
        .header,
        "pkmn.h",
    );
    b.getInstallStep().dependOn(&header.step);
    {
        const pc = try std.fmt.allocPrint(b.allocator, "lib{s}.pc", .{lib});
        defer b.allocator.free(pc);

        const file = try std.fs.path.join(
            b.allocator,
            &[_][]const u8{ b.cache_root, pc },
        );
        const pkgconfig_file = try std.fs.cwd().createFile(file, .{});

        const suffix = if (showdown) " Showdown!" else "";
        const writer = pkgconfig_file.writer();
        try writer.print(
            \\prefix={0s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{1s}
            \\URL: https://github.com/pkmn/engine
            \\Description: Library for simulating Pokémon{2s} battles.
            \\Version: {3s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{1s}
        , .{ b.install_prefix, lib, suffix, version });
        defer pkgconfig_file.close();

        const dest = try std.fmt.allocPrint(b.allocator, "share/pkgconfig/{s}", .{pc});
        defer b.allocator.free(dest);
        b.installFile(file, dest);
    }

    const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
    const test_file =
        b.option([]const u8, "test-file", "Input file for test") orelse "src/lib/test.zig";
    const test_bin = b.option([]const u8, "test-bin", "Emit test binary to");
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    const test_no_exec =
        b.option(bool, "test-no-exec", "Compiles test binary without running it") orelse false;

    const tests = if (test_no_exec) b.addTestExe("test_exe", test_file) else b.addTest(test_file);
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", options);
    tests.setBuildMode(mode);
    tests.setTarget(target);
    tests.single_threaded = true;
    tests.strip = strip;
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }
    if (coverage) |path| {
        tests.setExecCmd(&[_]?[]const u8{
            "kcov",
            "--include-pattern=src/lib",
            path,
            null,
        });
    }

    const format = b.addFmt(&[_][]const u8{"."});

    const rng = try tool(b, &.{pkmn}, "src/tools/rng.zig", showdown, strip);
    const serde = try tool(b, &.{pkmn}, "src/tools/serde.zig", showdown, strip);
    const protocol = try tool(b, &.{pkmn}, "src/tools/protocol.zig", showdown, strip);

    b.step("format", "Format source files").dependOn(&format.step);
    b.step("protocol", "Run protocol dump tool").dependOn(&protocol.step);
    b.step("rng", "Run RNG calculator tool").dependOn(&rng.step);
    b.step("serde", "Run serialization/deserialization tool").dependOn(&serde.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
}

fn tool(
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
    defer if (showdown) b.allocator.free(name);

    const exe = b.addExecutable(name, path);
    for (pkgs) |pkg| exe.addPackage(pkg);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.single_threaded = true;
    exe.strip = strip;

    const run_exe = exe.run();
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    return run_exe;
}
