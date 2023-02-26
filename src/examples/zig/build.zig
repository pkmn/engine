const std = @import("std");
const pkmn = @import("lib/pkmn/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode");
    const trace = b.option(bool, "trace", "Enable trace logs");

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "example.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("pkmn", pkmn.module(b, .{ .showdown = showdown, .trace = trace }));
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
