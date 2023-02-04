const std = @import("std");

const Pkg = std.build.Pkg;

pub fn pkg(b: *std.Build, build_options: Pkg) Pkg {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const source = .{ .path = dirname ++ "/src/lib/pkmn.zig" };
    return b.dupePkg(Pkg{ .name = "pkmn", .source = source, .dependencies = &.{build_options} });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;

    var parser = std.json.Parser.init(b.allocator, false);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("package.json"));
    defer tree.deinit();
    const version = tree.root.Object.get("version").?.String;

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "showdown", showdown);
    options.addOption(bool, "trace", trace);

    const build_options = options.getPackage("build_options");
    const pkmn = pkg(b, build_options);

    const lib = if (showdown) "pkmn-showdown" else "pkmn";

    const static_lib = b.addStaticLibrary(.{
        .name = lib,
        .root_source_file = .{ .path = "src/lib/binding/c.zig" },
        .optimize = optimize,
        .target = target,
    });
    static_lib.addOptions("build_options", options);
    static_lib.setMainPkgPath("./");
    static_lib.addIncludePath("src/include");
    static_lib.bundle_compiler_rt = true;
    static_lib.strip = strip;
    static_lib.install();

    const dynamic_lib = b.addSharedLibrary(.{
        .name = lib,
        .root_source_file = .{ .path = "src/lib/binding/c.zig" },
        .version = try std.builtin.Version.parse(version),
        .optimize = optimize,
        .target = target,
    });
    dynamic_lib.addOptions("build_options", options);
    static_lib.setMainPkgPath("./");
    dynamic_lib.addIncludePath("src/include");
    dynamic_lib.strip = strip;
    dynamic_lib.install();

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    if (node_headers) |headers| {
        const name = b.fmt("{s}.node", .{lib});
        const node_lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/node.zig" },
            .optimize = optimize,
            .target = target,
        });
        node_lib.addOptions("build_options", options);
        node_lib.setMainPkgPath("./");
        node_lib.addSystemIncludePath(headers);
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

    const tests = b.addTest(.{
        .root_source_file = .{ .path = test_file },
        .kind = if (test_no_exec) .test_exe else .@"test",
        .optimize = optimize,
        .target = target,
    });
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", options);
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

    const format = b.addFmt(&.{"."});
    const lint_exe =
        b.addExecutable(.{ .name = "lint", .root_source_file = .{ .path = "src/tools/lint.zig" } });
    if (test_step) |ts| ts.dependOn(&lint_exe.step);
    const lint = lint_exe.run();
    lint.step.dependOn(b.getInstallStep());

    const benchmark = tool(b, &.{pkmn}, "src/test/benchmark.zig", .{
        .showdown = showdown,
        .strip = true,
        .test_step = test_step,
        .target = target,
        .optimize = .ReleaseFast,
    });
    const fuzz = tool(b, &.{pkmn}, "src/test/benchmark.zig", .{
        .showdown = showdown,
        .strip = false,
        .test_step = test_step,
        .target = target,
        .optimize = optimize,
    });
    const config = .{
        .showdown = showdown,
        .strip = strip,
        .test_step = test_step,
        .target = target,
        .optimize = optimize,
    };
    const serde = tool(b, &.{pkmn}, "src/tools/serde.zig", config);
    const protocol = tool(b, &.{pkmn}, "src/tools/protocol.zig", config);

    b.step("benchmark", "Run benchmark code").dependOn(&benchmark.step);
    b.step("format", "Format source files").dependOn(&format.step);
    b.step("fuzz", "Run fuzz tester").dependOn(&fuzz.step);
    b.step("lint", "Lint source files").dependOn(&lint.step);
    b.step("protocol", "Run protocol dump tool").dependOn(&protocol.step);
    b.step("serde", "Run serialization/deserialization tool").dependOn(&serde.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
}

const Config = struct {
    showdown: bool,
    strip: bool,
    test_step: ?*std.Build.Step,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
};

fn tool(
    b: *std.Build,
    pkgs: []const Pkg,
    path: []const u8,
    config: Config,
) *std.Build.RunStep {
    var name = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (config.showdown) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = path },
        .target = config.target,
        .optimize = config.optimize,
    });
    for (pkgs) |p| exe.addPackage(p);
    exe.single_threaded = true;
    exe.strip = config.strip;
    if (config.test_step) |ts| ts.dependOn(&exe.step);

    const run_exe = exe.run();
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    return run_exe;
}
