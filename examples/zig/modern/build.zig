const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const showdown =
        b.option(bool, "showdown", "Enable Pokémon Showdown compatibility mode") orelse false;
    const log = b.option(bool, "log", "Enable protocol message logging") orelse false;

    const exe = b.addExecutable(if (@hasDecl(std.Build.ExecutableOptions, "root_source_file")) .{
        .name = "example",
        .root_source_file = if (@hasField(std.Build.LazyPath, "path"))
            .{ .path = "example.zig" }
        else
            b.path("example.zig"),
        .optimize = optimize,
        .target = target,
    } else .{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    const pkmn = b.dependency("pkmn", .{ .showdown = showdown, .log = log });
    exe.root_module.addImport("pkmn", pkmn.module("pkmn"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
