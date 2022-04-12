const std = @import("std");
const pkmn = @import("libs/pkmn/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const showdown = b.option(
        bool,
        "showdown",
        "Enable Pokémon Showdown compatability mode",
    ) orelse false;
    const trace = b.option(
        bool,
        "trace",
        "Enable trace logs",
    ) orelse false;

    const options = b.addOptions();
    options.addOption(bool, "showdown", showdown);
    options.addOption(bool, "trace", trace);

    const build_options = options.getPackage("build_options");

    const exe = b.addExecutable("zig", "example.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(pkmn.pkg(b, build_options));
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
