const std = @import("std");
const builtin = @import("builtin");

const NativeTargetInfo = std.zig.system.NativeTargetInfo;

pub const Options = struct { showdown: ?bool = null, trace: ?bool = null };

pub fn module(b: *std.Build, options: Options) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const build_options = b.addOptions();
    build_options.addOption(?bool, "showdown", options.showdown);
    build_options.addOption(?bool, "trace", options.trace);
    return b.createModule(.{
        .source_file = .{ .path = dirname ++ "/src/lib/pkmn.zig" },
        .dependencies = &.{.{ .name = "build_options", .module = build_options.createModule() }},
    });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    const wasm = b.option(bool, "wasm", "Build a WASM library") orelse false;
    const wasm_stack_size =
        b.option(u64, "wasm-stack-size", "The size of WASM stack") orelse std.wasm.page_size;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;
    const pic = b.option(bool, "pic", "Force position independent code") orelse false;

    const cmd = b.findProgram(&[_][]const u8{"strip"}, &[_][]const u8{}) catch null;

    var parser = std.json.Parser.init(b.allocator, false);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("package.json"));
    defer tree.deinit();
    const version = tree.root.Object.get("version").?.String;
    const description = tree.root.Object.get("description").?.String;
    var repository = std.mem.split(u8, tree.root.Object.get("repository").?.String, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode") orelse false;
    const trace = b.option(bool, "trace", "Enable trace logs") orelse false;

    const options = b.addOptions();
    options.addOption(?bool, "showdown", showdown);
    options.addOption(?bool, "trace", trace);

    const name = if (showdown) "pkmn-showdown" else "pkmn";

    var c = false;
    if (node_headers) |headers| {
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addSharedLibrary(.{
            .name = addon,
            .root_source_file = .{ .path = "src/lib/binding/node.zig" },
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addSystemIncludePath(headers);
        lib.linkLibC();
        if (node_import_lib) |il| {
            lib.addObjectFile(il);
        } else if ((try NativeTargetInfo.detect(target)).target.os.tag == .windows) {
            try std.io.getStdErr().writeAll("Must provide --node-import-library path on Windows\n");
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (pic) lib.force_pic = pic;
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO(ziglang/zig#2231): using the following used to work (though be hacky):
        //
        //    lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{addon}) };
        //    b.getInstallStep().dependOn(&lib.step);
        //
        // But ziglang/zig#14647 broke this so we now need to do an install() and then manually
        // rename the file ourself in install-pkmn-engine
        lib.install();
    } else if (wasm) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/wasm.zig" },
            .optimize = switch (optimize) {
                .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
                else => optimize,
            },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.stack_size = wasm_stack_size;
        lib.rdynamic = true;
        lib.strip = strip;
        if (pic) lib.force_pic = pic;
        const opt = b.findProgram(
            &[_][]const u8{"wasm-opt"},
            &[_][]const u8{"./node_modules/.bin"},
        ) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&[_][]const u8{ opt.?, "-O4" });
            sh.addArtifactArg(lib);
            sh.addArg("-o");
            sh.addFileSourceArg(.{ .path = out });
            b.getInstallStep().dependOn(&sh.step);
        }
        lib.install();
    } else if (dynamic) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .version = try std.builtin.Version.parse(version),
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addIncludePath("src/include");
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (pic) lib.force_pic = pic;
        lib.install();
        c = true;
    } else {
        const lib = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addIncludePath("src/include");
        lib.bundle_compiler_rt = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (pic) lib.force_pic = pic;
        lib.install();
        c = true;
    }

    if (c) {
        const header = b.addInstallFileWithDir(
            .{ .path = "src/include/pkmn.h" },
            .header,
            "pkmn.h",
        );
        b.getInstallStep().dependOn(&header.step);

        const pc = b.fmt("lib{s}.pc", .{name});
        const file = try b.cache_root.join(b.allocator, &.{pc});
        const pkgconfig_file = try std.fs.cwd().createFile(file, .{});

        const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
        const writer = pkgconfig_file.writer();
        try writer.print(
            \\prefix={0s}/{1s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{2s}
            \\URL: https://github.com/{3s}
            \\Description: {4s}
            \\Version: {5s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{2s}
        , .{ dirname, b.install_path, name, repository.next().?, description, version });
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
        .optimize = optimize,
        .target = target,
    });
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", options);
    tests.single_threaded = true;
    maybeStrip(b, tests, &tests.step, strip, cmd);
    if (pic) tests.force_pic = pic;
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }
    if (coverage) |path| {
        tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", path, null });
    }
    const test_step = if (test_filter != null) null else &tests.step;

    const lint_exe =
        b.addExecutable(.{ .name = "lint", .root_source_file = .{ .path = "src/tools/lint.zig" } });
    if (test_step) |ts| ts.dependOn(&lint_exe.step);
    const lint = lint_exe.run();

    const pkmn = .{
        .name = "pkmn",
        .module = module(b, .{ .showdown = showdown, .trace = trace }),
    };

    var exes = std.ArrayList(*std.Build.CompileStep).init(b.allocator);
    const config = .{
        .general = .{
            .target = target,
            .optimize = optimize,
            .pic = pic,
            .strip = strip,
            .cmd = cmd,
        },
        .tool = .{
            .showdown = showdown,
            .test_step = test_step,
            .exes = &exes,
        },
    };
    const benchmark = tool(b, &.{pkmn}, "src/test/benchmark.zig", .{
        .general = .{
            .target = target,
            .optimize = .ReleaseFast,
            .pic = pic,
            .strip = true,
            .cmd = cmd,
        },
        .tool = config.tool,
    });
    const fuzz = tool(b, &.{pkmn}, "src/test/benchmark.zig", .{
        .general = .{
            .target = target,
            .optimize = optimize,
            .pic = pic,
            .strip = false,
            .cmd = cmd,
        },
        .tool = .{
            .name = "fuzz",
            .showdown = showdown,
            .test_step = test_step,
            .exes = &exes,
        },
    });

    const serde = tool(b, &.{pkmn}, "src/tools/serde.zig", config);
    const protocol = tool(b, &.{pkmn}, "src/tools/protocol.zig", config);

    b.step("benchmark", "Run benchmark code").dependOn(&benchmark.step);
    b.step("fuzz", "Run fuzz tester").dependOn(&fuzz.step);
    b.step("lint", "Lint source files").dependOn(&lint.step);
    b.step("protocol", "Run protocol dump tool").dependOn(&protocol.step);
    b.step("serde", "Run serialization/deserialization tool").dependOn(&serde.step);
    b.step("test", "Run all tests").dependOn(if (test_no_exec) &tests.step else &tests.run().step);
    b.step("tools", "Install tools").dependOn(&ToolsStep.create(b, &exes).step);
}

fn maybeStrip(
    b: *std.Build,
    artifact: *std.Build.CompileStep,
    step: *std.Build.Step,
    strip: bool,
    cmd: ?[]const u8,
) void {
    artifact.strip = strip;
    if (!strip or cmd == null) return;
    // Using `strip -r -u` for dynamic libraries is supposed to work on macOS but doesn't...
    const mac = builtin.os.tag == .macos;
    if (mac and artifact.isDynamicLibrary()) return;
    // Assuming GNU strip, which complains "illegal pathname found in archive member"...
    if (!mac and artifact.isStaticLibrary()) return;
    const sh = b.addSystemCommand(&[_][]const u8{ cmd.?, if (mac) "-x" else "-s" });
    sh.addArtifactArg(artifact);
    step.dependOn(&sh.step);
}

const Config = struct {
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    pic: bool,
    strip: bool,
    cmd: ?[]const u8,
};

const ToolConfig = struct {
    general: Config,
    tool: struct {
        showdown: bool,
        test_step: ?*std.Build.Step,
        name: ?[]const u8 = null,
        exes: *std.ArrayList(*std.Build.CompileStep),
    },
};

fn tool(
    b: *std.Build,
    deps: []const std.Build.ModuleDependency,
    path: []const u8,
    config: ToolConfig,
) *std.Build.RunStep {
    var name = config.tool.name orelse std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (config.tool.showdown) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = path },
        .target = config.general.target,
        .optimize = config.general.optimize,
    });
    for (deps) |dep| exe.addModule(dep.name, dep.module);
    exe.single_threaded = true;
    if (config.general.pic) exe.force_pic = config.general.pic;
    if (config.tool.test_step) |ts| ts.dependOn(&exe.step);
    config.tool.exes.append(exe) catch @panic("OOM");

    const run = exe.run();
    maybeStrip(b, exe, &run.step, config.general.strip, config.general.cmd);
    if (b.args) |args| run.addArgs(args);

    return run;
}

const ToolsStep = struct {
    step: std.Build.Step,

    pub fn create(b: *std.Build, exes: *std.ArrayList(*std.Build.CompileStep)) *ToolsStep {
        const self = b.allocator.create(ToolsStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Install tools", .owner = b });
        self.* = ToolsStep{ .step = step };
        for (exes.items) |t| self.step.dependOn(&b.addInstallArtifact(t).step);
        return self;
    }
};
