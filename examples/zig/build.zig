const std = @import("std");
const pkmn = @import("pkmn");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const showdown = b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode");
    const log = b.option(bool, "log", "Enable protocol message logging");

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "example.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("pkmn", pkmn.module(b, .{
        .showdown = showdown,
        .log = log,
    }));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
