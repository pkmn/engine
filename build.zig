const std = @import("std");

const Debug: std.builtin.OptimizeMode =
    if (@hasDecl(std.builtin.OptimizeMode, "Debug")) .debug else .Debug;
const ReleaseSafe: std.builtin.OptimizeMode =
    if (@hasDecl(std.builtin.OptimizeMode, "ReleaseSafe")) .safe else .ReleaseSafe;
const ReleaseFast: std.builtin.OptimizeMode =
    if (@hasDecl(std.builtin.OptimizeMode, "ReleaseFast")) .fast else .ReleaseFast;
const ReleaseSmall: std.builtin.OptimizeMode =
    if (@hasDecl(std.builtin.OptimizeMode, "ReleaseSmall")) .small else .ReleaseSmall;

fn ArrayList(comptime T: type) type {
    return std.array_list.Aligned(T, null);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    const demo = if (try exists(b, "src/tools/demo.zig"))
        b.option(bool, "demo", "Build the demo library") orelse false
    else
        false;
    const wasm = b.option(bool, "wasm", "Build a WASM library") orelse false;
    const wasm_stack_size =
        b.option(u64, "wasm-stack-size", "The size of WASM stack") orelse std.wasm.page_size;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary");
    const unwind_tables: ?std.builtin.UnwindTables = if (strip orelse false) .none else null;
    const pic = b.option(bool, "pic", "Force position independent code");
    const emit_asm = b.option(bool, "emit-asm", "Output .s (assembly code)") orelse false;
    const emit_ll = b.option(bool, "emit-ll", "Output .ll (LLVM IR)") orelse false;

    const json = @embedFile("package.json");
    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version").?.string;
    const description = parsed.value.object.get("description").?.string;
    var repository = std.mem.splitScalar(u8, parsed.value.object.get("repository").?.string, ':');
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

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

    const pkmn = b.addModule("pkmn", .{
        .root_source_file = b.path("src/lib/pkmn.zig"),
        .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
    });

    var c = false;
    if (node_headers) |headers| {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/lib/napi.h"),
            .target = target,
            // TODO: workaround for ziglang/zig#35515
            .optimize = Debug,
        });
        translate_c.addSystemIncludePath(b.path(headers));
        const addon = b.fmt("{s}.node", .{name});
        const path = b.path("src/lib/node.zig");
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = addon,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .unwind_tables = unwind_tables,
                .pic = pic,
            }),
        });
        lib.discard_local_symbols = strip orelse false;
        lib.root_module.addOptions("build_options", options);
        lib.root_module.addImport("napi", translate_c.createModule());
        lib.root_module.link_libc = true;
        if (node_import_lib) |il| {
            lib.root_module.addObjectFile(b.path(il));
        } else if (target.result.os.tag == .windows) {
            var err = std.Io.File.stderr().writer(b.graph.io, &.{});
            try err.interface.writeAll("Must provide --node-import-library path on Windows\n");
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .lib },
            .dest_sub_path = addon,
            .implib_dir = .disabled,
            .pdb_dir = .disabled,
        }).step);
    } else if (wasm) {
        const path = "src/lib/wasm.zig";
        try buildWasm(b, name, path, optimize, strip, pic, wasm_stack_size, null, options);
    } else if (demo) {
        const path = "src/tools/demo.zig";
        const n = if (showdown) "demo-showdown" else "demo";
        const mod = pkmn;
        try buildWasm(b, n, path, optimize, strip, pic, wasm_stack_size, mod, options);
    } else if (dynamic) {
        const path = b.path("src/lib/c.zig");
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .unwind_tables = unwind_tables,
                .pic = pic,
            }),
        });
        lib.discard_local_symbols = strip orelse false;
        lib.root_module.addOptions("build_options", options);
        lib.root_module.addIncludePath(b.path("src/include"));
        b.installArtifact(lib);
        c = true;
    } else {
        const path = b.path("src/lib/c.zig");
        const lib = b.addLibrary(.{
            .linkage = .static,
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .unwind_tables = unwind_tables,
                .pic = pic,
            }),
        });
        lib.discard_local_symbols = strip orelse false;
        lib.root_module.addOptions("build_options", options);
        lib.root_module.addIncludePath(b.path("src/include"));
        if (target.result.os.tag != .macos) {
            lib.bundle_compiler_rt = true;
        }
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
        const path = b.path("src/include/pkmn.h");
        const header = b.addInstallFileWithDir(path, .header, "pkmn.h");
        b.getInstallStep().dependOn(&header.step);

        const content = try std.fmt.allocPrint(b.allocator,
            \\prefix=${{pcfiledir}}/../..
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{0s}
            \\URL: https://github.com/{1s}
            \\Description: {2s}
            \\Version: {3s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{0s}
        , .{ name, repository.next().?, description, version });

        const pc = b.fmt("lib{s}.pc", .{name});
        if (@hasDecl(std.Build, "FindProgramOptions")) {
            const write_file = b.addWriteFiles();
            const pkgconfig = write_file.add(pc, content);
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(
                pkgconfig,
                .prefix,
                b.fmt("share/pkgconfig/{s}", .{pc}),
            ).step);
        } else {
            const cwd = try std.process.currentPathAlloc(b.graph.io, b.allocator);
            const file = try std.Io.Dir.path.relative(
                b.allocator,
                cwd,
                &b.graph.environ_map,
                cwd,
                try b.cache_root.join(b.allocator, &.{pc}),
            );
            const pkgconfig = try std.Io.Dir.cwd().createFile(b.graph.io, file, .{});
            defer pkgconfig.close(b.graph.io);

            var writer = pkgconfig.writer(b.graph.io, &.{});
            try writer.interface.writeAll(content);

            b.installFile(file, b.fmt("share/pkgconfig/{s}", .{pc}));
        }
    }

    const config: Config = .{
        .target = target,
        .optimize = optimize,
        .pic = pic,
        .strip = strip,
    };

    // TODO: tests can be run multiple times due to @imports
    const tests = TestStep.create(b, options, config);

    var exes: ArrayList(*std.Build.Step.Compile) = .empty;
    const tools: ToolConfig = .{
        .showdown = showdown,
        .module = pkmn,
        .general = config,
        .tool = .{
            .tests = if (tests.build) tests else null,
            .exes = &exes,
        },
    };

    var benchmark_config = tools;
    benchmark_config.general.optimize = ReleaseFast;
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
    if (optimize != Debug) hack.tool.tests = null;
    const serde = try tool(b, "src/tools/serde.zig", hack);

    if (analyze) |t| b.step("analyze", "Run LLVM analysis tool").dependOn(&t.step);
    if (benchmark) |t| b.step("benchmark", "Run benchmark code").dependOn(&t.step);
    if (dump) |t| b.step("dump", "Run protocol dump tool").dependOn(&t.step);
    if (fuzz) |t| b.step("fuzz", "Run fuzz tester").dependOn(&t.step);
    if (serde) |t| b.step("serde", "Run serialization/deserialization tool").dependOn(&t.step);
    b.step("test", "Run all tests").dependOn(tests.step);
    b.step("tools", "Install tools").dependOn(ToolsStep.create(b, &exes).step);
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
    const mode = switch (optimize) {
        ReleaseFast, ReleaseSafe => ReleaseSmall,
        else => optimize,
    };
    // https://webassembly.org/features/
    const features = std.Target.wasm.featureSet(&.{
        .atomics,
        .bulk_memory,
        // .exception_handling,
        .extended_const,
        // .half_precision,
        // .multimemory,
        .multivalue,
        .mutable_globals,
        .nontrapping_fptoint,
        .reference_types,
        // .relaxed_simd,
        .sign_ext,
        .simd128,
        // .tail_call,
    });
    const freestanding = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = features,
    });
    const path = b.path(root_src_file);
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = path,
            .optimize = mode,
            .target = freestanding,
            .strip = strip,
            .unwind_tables = if (strip orelse false) .none else null,
            .pic = pic,
        }),
    });
    exe.discard_local_symbols = strip orelse false;

    if (@hasDecl(std.Build, "FindProgramOptions")) b.dependOnFileContents(path);
    var file = try std.Io.Dir.cwd().openFile(b.graph.io, root_src_file, .{});
    defer file.close(b.graph.io);
    var reader = file.reader(b.graph.io, &.{});
    const bytes = try reader.interface.allocRemaining(b.allocator, .unlimited);
    exe.root_module.export_symbol_names = try exports(b, bytes);
    exe.entry = .disabled;

    if (import) |i| {
        exe.root_module.addImport("pkmn", i);
    }
    exe.stack_size = wasm_stack_size;
    exe.root_module.addOptions("build_options", options);

    const opt = if (optimize == Debug)
        null
    else if (@hasDecl(std.Build, "FindProgramOptions")) blk: {
        if (exists(b, "./node_modules/.bin/wasm-opt") catch false) {
            break :blk "./node_modules/.bin/wasm-opt";
        }
        break :blk b.findProgram(.{ .names = &.{"wasm-opt"} });
    } else b.findProgram(&.{"wasm-opt"}, &.{"./node_modules/.bin"}) catch null;
    if (opt) |wasm_opt| {
        const out = b.fmt("{s}.wasm", .{name});
        const sh = b.addSystemCommand(&.{
            wasm_opt,
            "--enable-bulk-memory",
            "--enable-simd",
            "-O4",
        });
        sh.addArtifactArg(exe);
        sh.addArg("-o");
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            sh.addOutputFileArg(out),
            .lib,
            out,
        ).step);
    } else {
        b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .lib },
        }).step);
    }
}

const Config = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pic: ?bool,
    strip: ?bool,
};

const TestStep = struct {
    step: *std.Build.Step,
    build: bool,

    pub fn create(b: *std.Build, options: *std.Build.Step.Options, config: Config) *TestStep {
        const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
        const test_filter =
            b.option([]const u8, "test-filter", "Skip tests that do not match filter");

        const self = b.allocator.create(TestStep) catch @panic("OOM");

        const path = b.path("src/lib/test.zig");
        const tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = path,
                .optimize = config.optimize,
                .target = config.target,
                .single_threaded = true,
                .strip = config.strip,
                .unwind_tables = if (config.strip orelse false) .none else null,
                .pic = config.pic,
            }),
            .filters = if (test_filter) |filter| &.{filter} else &.{},
        });
        tests.discard_local_symbols = config.strip orelse false;
        tests.root_module.addOptions("build_options", options);

        if (coverage) |c| {
            const kcov_run = b.addSystemCommand(&.{ "kcov", "--include-pattern=src/lib", c });
            kcov_run.addArtifactArg(tests);
            kcov_run.enableTestRunnerMode();
            self.* = .{ .step = &kcov_run.step, .build = test_filter == null };
        } else {
            const run_step = b.addRunArtifact(tests);
            self.* = .{ .step = &run_step.step, .build = test_filter == null };
        }

        return self;
    }
};

const ToolConfig = struct {
    showdown: ?bool,
    module: *std.Build.Module,
    general: Config,
    tool: struct {
        tests: ?*TestStep,
        name: ?[]const u8 = null,
        exes: *ArrayList(*std.Build.Step.Compile),
    },
};

fn tool(b: *std.Build, path: []const u8, config: ToolConfig) !?*std.Build.Step.Run {
    if (!try exists(b, path)) return null;
    var name = config.tool.name orelse std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, name, '.');
    if (index) |i| name = name[0..i];
    if (config.showdown orelse false) name = b.fmt("{s}-showdown", .{name});

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = config.general.target,
            .optimize = config.general.optimize,
            .single_threaded = true,
            .strip = config.general.strip,
            .unwind_tables = if (config.general.strip orelse false) .none else null,
            .pic = config.general.pic,
        }),
    });
    exe.discard_local_symbols = config.general.strip orelse false;
    exe.root_module.addImport("pkmn", config.module);

    if (config.tool.tests) |ts| ts.step.dependOn(&exe.step);
    config.tool.exes.append(b.allocator, exe) catch @panic("OOM");

    const run = b.addRunArtifact(exe);
    if (@hasDecl(std.Build, "FindProgramOptions")) {
        run.addPassthruArgs();
    } else {
        if (b.args) |args| run.addArgs(args);
    }

    return run;
}

fn exists(b: *std.Build, path: []const u8) !bool {
    if (@hasDecl(std.Build, "FindProgramOptions")) b.dependOnFileMetadata(b.path(path));
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

const ToolsStep = struct {
    step: *std.Build.Step,

    pub fn create(b: *std.Build, exes: *ArrayList(*std.Build.Step.Compile)) *ToolsStep {
        const self = b.allocator.create(ToolsStep) catch @panic("OOM");

        if (@hasDecl(std.Build, "FindProgramOptions")) {
            const step = b.allocator.create(std.Build.Step.TopLevel) catch @panic("OOM");
            step.* = .{
                .step = std.Build.Step.init(.{
                    .tag = .top_level,
                    .name = "Install tools",
                    .owner = b,
                }),
                .description = "Install tools",
            };
            self.* = .{ .step = &step.step };
        } else {
            const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
            step.* = std.Build.Step.init(.{
                .id = .custom,
                .name = "Install tools",
                .owner = b,
            });
            self.* = .{ .step = step };
        }
        for (exes.items) |t| self.step.dependOn(&b.addInstallArtifact(t, .{}).step);

        return self;
    }
};

pub fn exports(b: *std.Build, bytes: []const u8) ![][]const u8 {
    var symbols: ArrayList([]const u8) = .empty;

    var it = std.mem.splitSequence(u8, bytes, "export ");
    _ = it.next();
    while (it.next()) |s| {
        if (std.mem.startsWith(u8, s, "const ")) {
            const i = std.mem.indexOf(u8, s[6..], " ").?;
            try symbols.append(b.allocator, s[6 .. 6 + i]);
        } else { // "fn "
            const i = std.mem.indexOf(u8, s[3..], "(").?;
            try symbols.append(b.allocator, s[3 .. 3 + i]);
        }
    }

    return symbols.items;
}
