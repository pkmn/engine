const std = @import("std");
const builtin = @import("builtin");

pub const Options = struct {
    showdown: ?bool = null,
    log: ?bool = null,
    chance: ?bool = null,
    calc: ?bool = null,
};

pub fn module(b: *std.Build, options: Options) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const build_options = b.addOptions();
    build_options.addOption(?bool, "showdown", options.showdown);
    build_options.addOption(?bool, "log", options.log);
    build_options.addOption(?bool, "chance", options.chance);
    build_options.addOption(?bool, "calc", options.calc);
    return b.createModule(.{
        .root_source_file = .{ .path = dirname ++ "/src/lib/pkmn.zig" },
        .imports = &.{.{ .name = "build_options", .module = build_options.createModule() }},
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
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary");
    const pic = b.option(bool, "pic", "Force position independent code");
    const emit_asm = b.option(bool, "emit-asm", "Output .s (assembly code)") orelse false;
    const emit_ll = b.option(bool, "emit-ll", "Output .ll (LLVM IR)") orelse false;

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
    const chance = b.option(bool, "chance", "Enable update probability tracking") orelse false;
    const calc = b.option(bool, "calc", "Enable damage calculator support") orelse false;

    const options = b.addOptions();
    options.addOption(?bool, "showdown", showdown);
    options.addOption(?bool, "log", log);
    options.addOption(?bool, "chance", chance);
    options.addOption(?bool, "calc", calc);

    const name = if (showdown) "pkmn-showdown" else "pkmn";

    var c = false;
    if (node_headers) |headers| {
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addSharedLibrary(.{
            .name = addon,
            .root_source_file = .{ .path = "src/lib/node.zig" },
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("build_options", options);
        lib.addSystemIncludePath(.{ .path = headers });
        lib.linkLibC();
        if (node_import_lib) |il| {
            lib.addObjectFile(.{ .path = il });
        } else if (target.result.os.tag == .windows) {
            try std.io.getStdErr().writeAll("Must provide --node-import-library path on Windows\n");
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO: ziglang/zig#2231 - using the following used to work (though was hacky):
        //
        //    lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{addon}) };
        //    b.getInstallStep().dependOn(&lib.step);
        //
        // But ziglang/zig#14647 broke this so we now need to do an install() and then manually
        // rename the file ourself in install-pkmn-engine
        b.installArtifact(lib);
    } else if (wasm) {
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/wasm.zig" },
            .optimize = switch (optimize) {
                .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
                else => optimize,
            },
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .strip = strip,
            .pic = pic,
        });
        exe.root_module.addOptions("build_options", options);
        exe.root_module.export_symbol_names = &[_][]const u8{
            "SHOWDOWN",
            "LOG",
            "CHANCE",
            "CALC",
            "GEN1_CHOICES_SIZE",
            "GEN1_LOGS_SIZE",
        };
        exe.entry = .disabled;
        exe.stack_size = wasm_stack_size;
        const opt = b.findProgram(&.{"wasm-opt"}, &.{"./node_modules/.bin"}) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&.{ opt.?, "-O4" });
            sh.addArtifactArg(exe);
            sh.addArg("-o");
            sh.addFileArg(.{ .path = out });
            b.getInstallStep().dependOn(&sh.step);
        } else {
            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
                .dest_dir = .{ .override = std.Build.InstallDir{ .lib = {} } },
            }).step);
        }
    } else if (dynamic) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/c.zig" },
            .version = try std.SemanticVersion.parse(version),
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("build_options", options);
        lib.addIncludePath(.{ .path = "src/include" });
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        b.installArtifact(lib);
        c = true;
    } else {
        const lib = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/c.zig" },
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("build_options", options);
        lib.addIncludePath(.{ .path = "src/include" });
        lib.bundle_compiler_rt = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (emit_asm) {
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(
                lib.getEmittedAsm(),
                .prefix,
                b.fmt("{s}.s", .{name}),
            ).step);
        }
        if (emit_ll) {
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(
                lib.getEmittedLlvmIr(),
                .prefix,
                b.fmt("{s}.ll", .{name}),
            ).step);
        }
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

    // TODO: tests can be run multiple times due to @imports
    const tests = TestStep.create(b, options, config);

    var exes = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    const tools: ToolConfig = .{
        .options = .{
            .showdown = showdown,
            .log = log,
            .chance = chance,
            .calc = calc,
        },
        .general = config,
        .tool = .{
            .tests = if (tests.build) tests else null,
            .exes = &exes,
        },
    };

    var benchmark_config = tools;
    benchmark_config.general.optimize = .ReleaseFast;
    benchmark_config.general.strip = true;
    const benchmark = try tool(b, "src/test/benchmark.zig", benchmark_config);

    var fuzz_config = tools;
    fuzz_config.general.strip = false;
    fuzz_config.tool.name = "fuzz";
    const fuzz = try tool(b, "src/test/fuzz.zig", fuzz_config);

    const analyze = try tool(b, "src/tools/analyze.zig", tools);
    const dump = try tool(b, "src/tools/dump.zig", tools);
    const transitions = try tool(b, "src/tools/transitions.zig", tools);

    // FIXME: serde randomly fails to build in some release configurations
    var hack = tools;
    if (optimize != .Debug) hack.tool.tests = null;
    const serde = try tool(b, "src/tools/serde.zig", hack);

    if (analyze) |t| b.step("analyze", "Run LLVM analysis tool").dependOn(&t.step);
    if (benchmark) |t| b.step("benchmark", "Run benchmark code").dependOn(&t.step);
    if (dump) |t| b.step("dump", "Run protocol dump tool").dependOn(&t.step);
    if (fuzz) |t| b.step("fuzz", "Run fuzz tester").dependOn(&t.step);
    if (serde) |t| b.step("serde", "Run serialization/deserialization tool").dependOn(&t.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
    b.step("tools", "Install tools").dependOn(&ToolsStep.create(b, &exes).step);
    if (transitions) |t| {
        b.step("transitions", "Visualize transitions algorithm search").dependOn(&t.step);
    }
}

fn maybeStrip(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    step: *std.Build.Step,
    strip: ?bool,
    cmd: ?[]const u8,
) void {
    if (!(strip orelse false) or cmd == null) return;
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
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pic: ?bool,
    strip: ?bool,
    cmd: ?[]const u8,
};

const TestStep = struct {
    step: std.Build.Step,
    build: bool,

    pub fn create(b: *std.Build, options: *std.Build.Step.Options, config: Config) *TestStep {
        const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
        const test_file = b.option([]const u8, "test-file", "Input file for test");
        const test_filter =
            b.option([]const u8, "test-filter", "Skip tests that do not match filter");

        const self = b.allocator.create(TestStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Run all tests", .owner = b });
        self.* = .{ .step = step, .build = test_filter == null };

        const path = test_file orelse "src/lib/test.zig";
        const tests = b.addTest(.{
            .name = b.fmt("{s}-{s}", .{
                std.fs.path.basename(std.fs.path.dirname(path).?),
                std.fs.path.stem(std.fs.path.basename(path)),
            }),
            .root_source_file = .{ .path = path },
            .optimize = config.optimize,
            .target = config.target,
            .filter = test_filter,
            .single_threaded = true,
            .strip = config.strip,
            .pic = config.pic,
        });
        tests.root_module.addOptions("build_options", options);
        maybeStrip(b, tests, &tests.step, config.strip, config.cmd);
        if (coverage) |c| {
            tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", c, null });
        }
        self.step.dependOn(&b.addRunArtifact(tests).step);

        return self;
    }
};

const ToolConfig = struct {
    options: Options,
    general: Config,
    tool: struct {
        tests: ?*TestStep,
        name: ?[]const u8 = null,
        exes: *std.ArrayList(*std.Build.Step.Compile),
    },
};

fn tool(b: *std.Build, path: []const u8, config: ToolConfig) !?*std.Build.Step.Run {
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |e| return e,
    };
    var name = config.tool.name orelse std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (config.options.showdown orelse false) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = path },
        .target = config.general.target,
        .optimize = config.general.optimize,
        .single_threaded = true,
        .strip = config.general.strip,
        .pic = config.general.pic,
    });
    exe.root_module.addImport("pkmn", module(b, config.options));

    if (config.tool.tests) |ts| ts.step.dependOn(&exe.step);
    config.tool.exes.append(exe) catch @panic("OOM");

    const run = b.addRunArtifact(exe);
    maybeStrip(b, exe, &run.step, config.general.strip, config.general.cmd);
    if (b.args) |args| run.addArgs(args);

    return run;
}

const ToolsStep = struct {
    step: std.Build.Step,

    pub fn create(b: *std.Build, exes: *std.ArrayList(*std.Build.Step.Compile)) *ToolsStep {
        const self = b.allocator.create(ToolsStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Install tools", .owner = b });
        self.* = .{ .step = step };
        for (exes.items) |t| self.step.dependOn(&b.addInstallArtifact(t, .{}).step);
        return self;
    }
};
