const std = @import("std");
const builtin = @import("builtin");

pub const Options = struct { showdown: ?bool = null, log: ?bool = null };

pub fn module(b: *std.Build, options: Options) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const build_options = b.addOptions();
    build_options.addOption(?bool, "showdown", options.showdown);
    build_options.addOption(?bool, "log", options.log);
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
    const emit_asm = b.option(bool, "emit-asm", "Output .s (assembly code)") orelse false;

    const cmd = b.findProgram(&.{"strip"}, &.{}) catch null;

    const json = @embedFile("package.json");
    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version").?.string;
    const description = parsed.value.object.get("description").?.string;
    var repository = std.mem.split(u8, parsed.value.object.get("repository").?.string, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode") orelse false;
    const log = b.option(bool, "log", "Enable protocol message logging") orelse false;

    const options = b.addOptions();
    options.addOption(?bool, "showdown", showdown);
    options.addOption(?bool, "log", log);

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
        } else if ((try std.zig.system.NativeTargetInfo.detect(target)).target.os.tag == .windows) {
            try std.io.getStdErr().writeAll("Must provide --node-import-library path on Windows\n");
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (pic) lib.force_pic = pic;
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO(ziglang/zig#2231): using the following used to work (though was hacky):
        //
        //    lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{addon}) };
        //    b.getInstallStep().dependOn(&lib.step);
        //
        // But ziglang/zig#14647 broke this so we now need to do an install() and then manually
        // rename the file ourself in install-pkmn-engine
        b.installArtifact(lib);
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
        const opt = b.findProgram(&.{"wasm-opt"}, &.{"./node_modules/.bin"}) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&.{ opt.?, "-O4" });
            sh.addArtifactArg(lib);
            sh.addArg("-o");
            sh.addFileSourceArg(.{ .path = out });
            b.getInstallStep().dependOn(&sh.step);
        }
        b.installArtifact(lib);
    } else if (dynamic) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .version = try std.SemanticVersion.parse(version),
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addIncludePath("src/include");
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (pic) lib.force_pic = pic;
        b.installArtifact(lib);
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
        if (emit_asm) lib.emit_asm = .emit;
        b.installArtifact(lib);
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

    const config = .{
        .target = target,
        .optimize = optimize,
        .pic = pic,
        .strip = strip,
        .cmd = cmd,
    };
    const tests = TestStep.create(b, options, config);

    var exes = std.ArrayList(*std.Build.CompileStep).init(b.allocator);
    const tools: ToolConfig = .{
        .general = config,
        .tool = .{
            .showdown = showdown,
            .log = log,
            .tests = if (tests.build) tests else null,
            .exes = &exes,
        },
    };

    var benchmark_config = tools;
    benchmark_config.general.optimize = .ReleaseFast;
    benchmark_config.general.strip = true;
    const benchmark = tool(b, "src/test/benchmark.zig", benchmark_config);

    var fuzz_config = tools;
    fuzz_config.general.strip = false;
    fuzz_config.tool.name = "fuzz";
    const fuzz = tool(b, "src/test/benchmark.zig", fuzz_config);

    const serde = tool(b, "src/tools/serde.zig", tools);
    const protocol = tool(b, "src/tools/protocol.zig", tools);

    const lint_exe =
        b.addExecutable(.{ .name = "lint", .root_source_file = .{ .path = "src/tools/lint.zig" } });
    if (tests.build) tests.step.dependOn(&lint_exe.step);
    const lint = b.addRunArtifact(lint_exe);

    b.step("benchmark", "Run benchmark code").dependOn(&benchmark.step);
    b.step("fuzz", "Run fuzz tester").dependOn(&fuzz.step);
    b.step("lint", "Lint source files").dependOn(&lint.step);
    b.step("protocol", "Run protocol dump tool").dependOn(&protocol.step);
    b.step("serde", "Run serialization/deserialization tool").dependOn(&serde.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
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
    const sh = b.addSystemCommand(&.{ cmd.?, if (mac) "-x" else "-s" });
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

const TESTS = .{
    "src/lib/common/test.zig",
    "src/lib/gen1/test.zig",
    "src/lib/gen2/test.zig",
};

const TestStep = struct {
    step: std.Build.Step,
    build: bool,

    pub fn create(b: *std.Build, options: *std.Build.OptionsStep, config: Config) *TestStep {
        const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
        const test_file = b.option([]const u8, "test-file", "Input file for test");
        const test_filter =
            b.option([]const u8, "test-filter", "Skip tests that do not match filter");

        const self = b.allocator.create(TestStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Run all tests", .owner = b });
        self.* = TestStep{ .step = step, .build = test_filter == null };

        const paths: []const []const u8 =
            if (test_file) |t| &.{t} else if (coverage != null) &.{"src/lib/test.zig"} else &TESTS;
        for (paths) |path| {
            const tests = b.addTest(.{
                .name = std.fs.path.basename(std.fs.path.dirname(path).?),
                .root_source_file = .{ .path = path },
                .optimize = config.optimize,
                .target = config.target,
                .filter = test_filter,
            });
            tests.setMainPkgPath("./");
            tests.addOptions("build_options", options);
            tests.single_threaded = true;
            maybeStrip(b, tests, &tests.step, config.strip, config.cmd);
            if (config.pic) tests.force_pic = config.pic;
            if (coverage) |c| {
                tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", c, null });
            }
            self.step.dependOn(&b.addRunArtifact(tests).step);
        }
        return self;
    }
};

const ToolConfig = struct {
    general: Config,
    tool: struct {
        showdown: bool,
        log: bool,
        tests: ?*TestStep,
        name: ?[]const u8 = null,
        exes: *std.ArrayList(*std.Build.CompileStep),
    },
};

fn tool(b: *std.Build, path: []const u8, config: ToolConfig) *std.Build.RunStep {
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
    exe.addModule("pkmn", module(b, .{
        .showdown = config.tool.showdown,
        .log = config.tool.log,
    }));
    exe.single_threaded = true;
    if (config.general.pic) exe.force_pic = config.general.pic;
    if (config.tool.tests) |ts| ts.step.dependOn(&exe.step);
    config.tool.exes.append(exe) catch @panic("OOM");

    const run = b.addRunArtifact(exe);
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
