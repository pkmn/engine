const builtin = @import("builtin");
const std = @import("std");

pub const Options = struct {
    showdown: ?bool = null,
    log: ?bool = null,
    chance: ?bool = null,
    calc: ?bool = null,
};

const Step = if (@hasDecl(std.Build, "Step")) std.Build.Step else .{
    .Compile = std.Build.CompileStep,
    .Options = std.Build.OptionsStep,
    .Run = std.Build.RunStep,
};
const has_path = @hasField(std.Build.LazyPath, "path");
const root_module = @hasField(Step.Compile, "root_module");
const lib_helper = @hasDecl(std.Build, "addSharedLibrary");
const writergate = @hasDecl(std.fs.File, "stdout");
const force_pic = lib_helper and !@hasField(std.Build.SharedLibraryOptions, "pic");
const ResolvedTarget =
    if (@hasDecl(std.Build, "ResolvedTarget")) std.Build.ResolvedTarget else std.zig.CrossTarget;
const ArrayList = if (@hasDecl(std, "array_list")) std.array_list.Managed else std.ArrayList;

pub fn module(b: *std.Build, options: Options) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const build_options = b.addOptions();
    build_options.addOption(?bool, "showdown", options.showdown);
    build_options.addOption(?bool, "log", options.log);
    build_options.addOption(?bool, "chance", options.chance);
    build_options.addOption(?bool, "calc", options.calc);

    const root_source_file: std.Build.LazyPath =
        .{ .cwd_relative = dirname ++ "/src/lib/pkmn.zig" };
    const Import = if (@hasDecl(std.Build.Module, "Import"))
        std.Build.Module.Import
    else
        std.Build.ModuleDependency;
    const imports: []const Import =
        &.{.{ .name = "build_options", .module = build_options.createModule() }};
    return b.createModule(if (@hasDecl(std.Build, "CreateModuleOptions"))
        .{ .source_file = root_source_file, .dependencies = imports }
    else
        .{ .root_source_file = root_source_file, .imports = imports });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default: ?bool = if (force_pic) false else null;
    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    const demo = if (try exists("src/tools/demo.zig"))
        b.option(bool, "demo", "Build the demo library") orelse false
    else
        false;
    const wasm = b.option(bool, "wasm", "Build a WASM library") orelse false;
    const wasm_stack_size =
        b.option(u64, "wasm-stack-size", "The size of WASM stack") orelse std.wasm.page_size;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse default;
    const pic = b.option(bool, "pic", "Force position independent code") orelse default;
    const emit_asm = b.option(bool, "emit-asm", "Output .s (assembly code)") orelse false;
    const emit_ll = b.option(bool, "emit-ll", "Output .ll (LLVM IR)") orelse false;

    const cmd = b.findProgram(&.{"strip"}, &.{}) catch null;

    const json = @embedFile("package.json");
    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version").?.string;
    const description = parsed.value.object.get("description").?.string;
    var repository = std.mem.splitSequence(u8, parsed.value.object.get("repository").?.string, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const fast = try std.SemanticVersion.parse("0.12.0-dev.866+3a47bc715");
    const patched = std.mem.endsWith(u8, builtin.zig_version_string, "patched");
    if (optimize != .Debug and fast.order(builtin.zig_version) == .lt and !patched) {
        std.log.warn("Release builds are ~10-20% slower than before Zig " ++
            "v0.12.0-dev.866+3a47bc715 due to ziglang/zig#17768", .{});
    }

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode") orelse false;
    const log = b.option(bool, "log", "Enable protocol message logging") orelse false;
    const chance = b.option(bool, "chance", "Enable update probability tracking") orelse false;
    const calc = b.option(bool, "calc", "Enable damage calculator support") orelse false;
    const extra = b.option([]const []const u8, "option", "Enable extra option");

    const options = b.addOptions();
    options.addOption(?bool, "showdown", showdown);
    options.addOption(?bool, "log", log);
    options.addOption(?bool, "chance", chance);
    options.addOption(?bool, "calc", calc);

    if (extra) |opts| {
        for (opts) |opt| {
            if (std.mem.indexOfScalar(u8, opt, '=')) |i| {
                options.addOption(?bool, opt[0..i], if (std.mem.eql(u8, opt[i + 1 ..], "true"))
                    true
                else if (std.mem.eql(u8, opt[i + 1 ..], "false"))
                    false
                else {
                    std.log.err("Invalid option: {s}\n", .{opt});
                    return error.InvalidOption;
                });
            } else {
                options.addOption(?bool, opt, true);
            }
        }
    }

    const name = if (showdown) "pkmn-showdown" else "pkmn";

    const pkmn: ?*std.Build.Module = if (@hasDecl(std.Build, "CreateModuleOptions"))
        null
    else
        b.addModule("pkmn", .{
            .root_source_file = if (has_path)
                .{ .path = "src/lib/pkmn.zig" }
            else
                b.path("src/lib/pkmn.zig"),
            .optimize = optimize,
            .target = target,
            .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
        });

    var c = false;
    if (node_headers) |headers| {
        const TranslateC = std.Build.Step.TranslateC;
        const translate_c = b.addTranslateC(if (@hasField(TranslateC.Options, "source_file")) .{
            .source_file = .{ .path = "src/lib/napi.h" },
            .target = target,
            .optimize = optimize,
        } else .{
            .root_source_file = b.path("src/lib/napi.h"),
            .target = target,
            .optimize = optimize,
        });
        if (@hasDecl(TranslateC, "addSystemIncludePath")) {
            translate_c.addSystemIncludePath(b.path(headers));
        } else {
            translate_c.addIncludeDir(headers);
        }

        const addon = b.fmt("{s}.node", .{name});
        const path = if (has_path) .{ .path = "src/lib/node.zig" } else b.path("src/lib/node.zig");
        const lib = if (lib_helper) b.addSharedLibrary(if (force_pic) .{
            .name = addon,
            .root_source_file = path,
            .optimize = optimize,
            .target = target,
        } else .{
            .name = addon,
            .root_source_file = path,
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        }) else b.addLibrary(.{
            .linkage = .dynamic,
            .name = addon,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        if (root_module) {
            lib.root_module.addOptions("build_options", options);
            lib.root_module.addImport("napi", translate_c.createModule());
        } else {
            lib.addOptions("build_options", options);
            lib.addModule("napi", translate_c.createModule());
        }
        lib.linkLibC();
        if (node_import_lib) |il| {
            lib.addObjectFile(if (has_path) .{ .path = il } else b.path(il));
        } else if (detect(target).os.tag == .windows) {
            const msg = "Must provide --node-import-library path on Windows\n";
            if (writergate) {
                var writer = std.fs.File.stderr().writer(&.{});
                try writer.interface.writeAll(msg);
            } else {
                try std.io.getStdErr().writeAll(msg);
            }
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (force_pic and pic orelse false) lib.force_pic = pic;
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
        const path = "src/lib/wasm.zig";
        try buildWasm(b, name, path, optimize, strip, pic, wasm_stack_size, null, options);
    } else if (demo) {
        const path = "src/tools/demo.zig";
        const n = if (showdown) "demo-showdown" else "demo";
        const mod = pkmn orelse module(b, .{
            .showdown = showdown,
            .log = log,
            .chance = chance,
            .calc = calc,
        });
        try buildWasm(b, n, path, optimize, strip, pic, wasm_stack_size, mod, options);
    } else if (dynamic) {
        const path = if (has_path) .{ .path = "src/lib/c.zig" } else b.path("src/lib/c.zig");
        const lib = if (lib_helper) b.addSharedLibrary(if (force_pic) .{
            .name = name,
            .root_source_file = path,
            .version = try std.SemanticVersion.parse(version),
            .optimize = optimize,
            .target = target,
        } else .{
            .name = name,
            .root_source_file = path,
            .version = try std.SemanticVersion.parse(version),
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        }) else b.addLibrary(.{
            .linkage = .dynamic,
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        (if (root_module) lib.root_module else lib).addOptions("build_options", options);
        lib.addIncludePath(if (has_path) .{ .path = "src/include" } else b.path("src/include"));
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (force_pic and pic orelse false) lib.force_pic = pic;
        b.installArtifact(lib);
        c = true;
    } else {
        const path = if (has_path) .{ .path = "src/lib/c.zig" } else b.path("src/lib/c.zig");
        const lib = if (lib_helper) b.addStaticLibrary(if (force_pic) .{
            .name = name,
            .root_source_file = path,
            .optimize = optimize,
            .target = target,
        } else .{
            .name = name,
            .root_source_file = path,
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        }) else b.addLibrary(.{
            .linkage = .static,
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        (if (root_module) lib.root_module else lib).addOptions("build_options", options);
        lib.addIncludePath(if (has_path) .{ .path = "src/include" } else b.path("src/include"));
        lib.bundle_compiler_rt = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        if (force_pic and pic orelse false) lib.force_pic = pic;
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
        const path =
            if (has_path) .{ .path = "src/include/pkmn.h" } else b.path("src/include/pkmn.h");
        const header = b.addInstallFileWithDir(path, .header, "pkmn.h");
        b.getInstallStep().dependOn(&header.step);

        const pc = b.fmt("lib{s}.pc", .{name});
        const file = try std.fs.path.relative(
            b.allocator,
            try std.process.getCwdAlloc(b.allocator),
            try b.cache_root.join(b.allocator, &.{pc}),
        );
        const pkgconfig_file = try std.fs.cwd().createFile(file, .{});

        const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
        var writer = if (writergate) pkgconfig_file.writer(&.{}) else pkgconfig_file;
        try (if (writergate) writer.interface else writer.writer()).print(
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

    const config: Config = .{
        .target = target,
        .optimize = optimize,
        .pic = pic,
        .strip = strip,
        .cmd = cmd,
    };

    // TODO: tests can be run multiple times due to @imports
    const tests = TestStep.create(b, options, config);

    var exes = ArrayList(*Step.Compile).init(b.allocator);
    const tools: ToolConfig = .{
        .options = .{
            .showdown = showdown,
            .log = log,
            .chance = chance,
            .calc = calc,
        },
        .module = pkmn,
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

fn buildWasm(
    b: *std.Build,
    name: []const u8,
    root_src_file: []const u8,
    optimize: std.builtin.OptimizeMode,
    strip: ?bool,
    pic: ?bool,
    wasm_stack_size: u64,
    import: ?*std.Build.Module,
    options: anytype,
) !void {
    const entry = @hasDecl(Step.Compile, "Entry");
    const mode = switch (optimize) {
        .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
        else => optimize,
    };
    // https://webassembly.org/features/
    var features = std.Target.wasm.featureSet(&.{
        .atomics,
        .bulk_memory,
        // .exception_handling,
        .extended_const,
        // .half_precision,
        // .multimemory,
        .mutable_globals,
        .nontrapping_fptoint,
        .reference_types,
        // .relaxed_simd,
        .sign_ext,
        .simd128,
        // .tail_call,
    });
    if (builtin.zig_version.order(try std.SemanticVersion.parse("0.12.0")) != .lt) {
        features.addFeature(@intFromEnum(std.Target.wasm.Feature.multivalue));
    }
    const freestanding = if (@hasDecl(std.Build, "resolveTargetQuery"))
        b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = features,
        })
    else
        ResolvedTarget{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = features,
        };
    const path = if (has_path) .{ .path = root_src_file } else b.path(root_src_file);
    const bin = if (entry) bin: {
        const exe = b.addExecutable(if (!lib_helper) .{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = mode,
                .target = freestanding,
                .strip = strip,
                .pic = pic,
            }),
        } else if (force_pic) .{
            .name = name,
            .root_source_file = path,
            .optimize = mode,
            .target = freestanding,
        } else .{
            .name = name,
            .root_source_file = path,
            .optimize = mode,
            .target = freestanding,
            .strip = strip,
            .pic = pic,
        });

        var file = try std.fs.cwd().openFile(root_src_file, .{});
        defer file.close();
        const bytes = try file.readToEndAlloc(b.allocator, std.math.maxInt(usize));
        (if (root_module) exe.root_module else exe).export_symbol_names = try exports(b, bytes);
        exe.entry = .disabled;
        break :bin exe;
    } else bin: {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = path,
            .optimize = mode,
            .target = freestanding,
        });
        lib.rdynamic = true;
        break :bin lib;
    };
    if (import) |i| {
        if (root_module) {
            bin.root_module.addImport("pkmn", i);
        } else {
            bin.addModule("pkmn", i);
        }
    }
    bin.stack_size = wasm_stack_size;
    if (@hasDecl(@TypeOf(bin.*), "strip")) bin.strip = strip orelse false;
    if (force_pic and pic orelse false) bin.force_pic = pic;
    (if (root_module) bin.root_module else bin).addOptions("build_options", options);

    const opt = b.findProgram(&.{"wasm-opt"}, &.{"./node_modules/.bin"}) catch null;
    if (optimize != .Debug and opt != null) {
        const out = b.fmt("build/lib/{s}.wasm", .{name});
        const sh = b.addSystemCommand(&.{ opt.?, "--enable-bulk-memory", "--enable-simd", "-O4" });
        sh.addArtifactArg(bin);
        sh.addArg("-o");
        if (@hasDecl(@TypeOf(sh.*), "addFileSourceArg")) {
            sh.addFileSourceArg(if (has_path) .{ .path = out } else b.path(out));
        } else {
            sh.addFileArg(if (has_path) .{ .path = out } else b.path(out));
        }
        b.getInstallStep().dependOn(&sh.step);
        if (!entry) b.installArtifact(bin);
    } else if (entry) {
        b.getInstallStep().dependOn(&b.addInstallArtifact(bin, .{
            .dest_dir = .{ .override = std.Build.InstallDir{ .lib = {} } },
        }).step);
    } else {
        b.installArtifact(bin);
    }
}

fn maybeStrip(
    b: *std.Build,
    artifact: *Step.Compile,
    step: *std.Build.Step,
    strip: ?bool,
    cmd: ?[]const u8,
) void {
    if (@hasDecl(@TypeOf(artifact.*), "strip")) artifact.strip = strip orelse false;
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
    target: ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pic: ?bool,
    strip: ?bool,
    cmd: ?[]const u8,
};

const TestStep = struct {
    step: std.Build.Step,
    build: bool,

    pub fn create(b: *std.Build, options: *Step.Options, config: Config) *TestStep {
        const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
        const test_filter =
            b.option([]const u8, "test-filter", "Skip tests that do not match filter");

        const self = b.allocator.create(TestStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Run all tests", .owner = b });
        self.* = .{ .step = step, .build = test_filter == null };

        const path = if (has_path) .{ .path = "src/lib/test.zig" } else b.path("src/lib/test.zig");
        const tests = b.addTest(if (lib_helper) if (force_pic) .{
            .root_source_file = path,
            .optimize = config.optimize,
            .target = config.target,
            .filter = test_filter,
        } else .{
            .root_source_file = path,
            .optimize = config.optimize,
            .target = config.target,
            .filter = test_filter,
            .single_threaded = true,
            .strip = config.strip,
            .pic = config.pic,
        } else .{
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = config.optimize,
                .target = config.target,
                .single_threaded = true,
                .strip = config.strip,
                .pic = config.pic,
            }),
            .filters = if (test_filter) |filter| &.{filter} else &.{},
        });
        (if (root_module) tests.root_module else tests).addOptions("build_options", options);

        maybeStrip(b, tests, &tests.step, config.strip, config.cmd);
        if (force_pic) {
            tests.single_threaded = true;
            if (config.pic orelse false) tests.force_pic = config.pic;
        }
        if (coverage) |c| {
            tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", c, null });
        }
        self.step.dependOn(&b.addRunArtifact(tests).step);

        return self;
    }
};

const ToolConfig = struct {
    options: Options,
    module: ?*std.Build.Module,
    general: Config,
    tool: struct {
        tests: ?*TestStep,
        name: ?[]const u8 = null,
        exes: *ArrayList(*Step.Compile),
    },
};

fn tool(b: *std.Build, path: []const u8, config: ToolConfig) !?*Step.Run {
    if (!try exists(path)) return null;
    var name = config.tool.name orelse std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (config.options.showdown orelse false) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(if (!lib_helper) .{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = if (has_path) .{ .path = path } else b.path(path),
            .target = config.general.target,
            .optimize = config.general.optimize,
            .strip = config.general.strip,
            .pic = config.general.pic,
        }),
    } else if (force_pic) .{
        .name = name,
        .root_source_file = if (has_path) .{ .path = path } else b.path(path),
        .target = config.general.target,
        .optimize = config.general.optimize,
    } else .{
        .name = name,
        .root_source_file = if (has_path) .{ .path = path } else b.path(path),
        .target = config.general.target,
        .optimize = config.general.optimize,
        .single_threaded = true,
        .strip = config.general.strip,
        .pic = config.general.pic,
    });

    if (root_module) {
        const import = if (config.module) |m| m else module(b, config.options);
        exe.root_module.addImport("pkmn", import);
        if (detect(config.general.target).os.tag == .windows) {
            exe.root_module.linkSystemLibrary("advapi32", .{});
        }
    } else {
        exe.addModule("pkmn", module(b, config.options));
    }

    if (force_pic) {
        exe.single_threaded = true;
        if (config.general.pic orelse false) exe.force_pic = config.general.pic;
    }
    if (config.tool.tests) |ts| ts.step.dependOn(&exe.step);
    config.tool.exes.append(exe) catch @panic("OOM");

    const run = b.addRunArtifact(exe);
    maybeStrip(b, exe, &run.step, config.general.strip, config.general.cmd);
    if (b.args) |args| run.addArgs(args);

    return run;
}

fn exists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

const ToolsStep = struct {
    step: std.Build.Step,

    pub fn create(b: *std.Build, exes: *ArrayList(*Step.Compile)) *ToolsStep {
        const self = b.allocator.create(ToolsStep) catch @panic("OOM");
        const step = std.Build.Step.init(.{ .id = .custom, .name = "Install tools", .owner = b });
        self.* = .{ .step = step };
        for (exes.items) |t| self.step.dependOn(&b.addInstallArtifact(t, .{}).step);
        return self;
    }
};

fn detect(target: anytype) std.Target {
    if (@hasField(@TypeOf(target), "result")) return target.result;
    return (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target;
}

pub fn exports(b: *std.Build, bytes: []const u8) ![][]const u8 {
    var symbols = ArrayList([]const u8).init(b.allocator);

    var it = std.mem.splitSequence(u8, bytes, "export ");
    _ = it.next();
    while (it.next()) |s| {
        if (std.mem.startsWith(u8, s, "const ")) {
            const i = std.mem.indexOf(u8, s[6..], " ").?;
            try symbols.append(s[6 .. 6 + i]);
        } else { // "fn "
            const i = std.mem.indexOf(u8, s[3..], "(").?;
            try symbols.append(s[3 .. 3 + i]);
        }
    }

    return symbols.items;
}
