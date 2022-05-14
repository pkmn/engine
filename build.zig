const std = @import("std");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn pkg(b: *Builder, build_options: Pkg) Pkg {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    return b.dupePkg(.{
        .name = "pkmn",
        .path = .{ .path = dirname ++ "/src/lib/pkmn.zig" },
        .dependencies = &.{build_options},
    });
}

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

    const build_options = options.getPackage("build_options");
    const pkmn = pkg(b, build_options);

    const lib = if (showdown) "pkmn-showdown" else "pkmn";

    const static_lib = b.addStaticLibrary(lib, "src/lib/binding/c.zig");
    static_lib.addOptions("build_options", options);
    static_lib.setBuildMode(mode);
    static_lib.setTarget(target);
    static_lib.addIncludeDir("src/include");
    static_lib.strip = strip;
    static_lib.install();

    const versioned = .{ .versioned = try std.builtin.Version.parse(version) };
    const dynamic_lib = b.addSharedLibrary(lib, "src/lib/binding/c.zig", versioned);
    dynamic_lib.addOptions("build_options", options);
    dynamic_lib.setBuildMode(mode);
    dynamic_lib.setTarget(target);
    dynamic_lib.addIncludeDir("src/include");
    dynamic_lib.strip = strip;
    dynamic_lib.install();

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    if (node_headers) |headers| {
        const name = b.fmt("{s}.node", .{lib});
        const node_lib = b.addSharedLibrary(name, "src/lib/binding/node.zig", .unversioned);
        node_lib.addSystemIncludeDir(headers);
        node_lib.addOptions("build_options", options);
        node_lib.setBuildMode(mode);
        node_lib.setTarget(target);
        node_lib.linkLibC();
        node_lib.linker_allow_shlib_undefined = true;
        node_lib.strip = strip;
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO: find alternative to emit_to that works properly with .install()
        node_lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{name}) };
        b.getInstallStep().dependOn(&node_lib.step);
    }

    const header = b.addInstallFileWithDir(
        .{ .path = "src/include/pkmn.h" },
        .header,
        "pkmn.h",
    );
    b.getInstallStep().dependOn(&header.step);
    {
        const pc = b.fmt("lib{s}.pc", .{lib});

        const file = try std.fs.path.join(
            b.allocator,
            &.{ b.cache_root, pc },
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

        b.installFile(file, b.fmt("share/pkgconfig/{s}", .{pc}));
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
        tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", path, null });
    }
    const test_step = if (test_filter != null) null else &tests.step;

    const bench = b.addExecutable(
        if (showdown) "benchmark-showdown" else "benchmark",
        "src/test/benchmark.zig",
    );
    bench.addPackage(pkmn);
    bench.setBuildMode(.ReleaseFast);
    bench.single_threaded = true;
    bench.strip = true;

    const benchmark = bench.run();
    benchmark.step.dependOn(b.getInstallStep());
    if (b.args) |args| benchmark.addArgs(args);
    if (test_step) |ts| ts.dependOn(&bench.step);

    const format = b.addFmt(&.{"."});

    const rng = try tool(b, &.{pkmn}, "src/tools/rng.zig", showdown, strip, test_step);
    const serde = try tool(b, &.{pkmn}, "src/tools/serde.zig", showdown, strip, test_step);
    const protocol = try tool(b, &.{pkmn}, "src/tools/protocol.zig", showdown, strip, test_step);

    b.step("benchmark", "Run benchmark code").dependOn(&benchmark.step);
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
    test_step: ?*std.build.Step,
) !*std.build.RunStep {
    var name = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (showdown) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(name, path);
    for (pkgs) |p| exe.addPackage(p);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.single_threaded = true;
    exe.strip = strip;
    if (test_step) |ts| ts.dependOn(&exe.step);

    const run_exe = exe.run();
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    return run_exe;
}
