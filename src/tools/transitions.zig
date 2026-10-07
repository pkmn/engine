const pkmn = @import("pkmn");
const std = @import("std");

const move = pkmn.gen1.helpers.move;
// const swtch = pkmn.gen1.helpers.swtch;

pub const pkmn_options = pkmn.Options{ .internal = true };

const debug = false; // DEBUG

pub fn main(init: std.process.Init) !void {
    std.debug.assert(pkmn.options.calc and pkmn.options.chance);

    const arena = init.arena.allocator();
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    var err = std.Io.File.stderr().writer(init.io, &.{});
    if (args.len < 2 or args.len > 3) usageAndExit(&err.interface, args[0]);

    var buf: [pkmn.LOGS_SIZE]u8 = undefined;
    var writer = pkmn.protocol.Writer{ .buffer = &buf };

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit(&err.interface, "gen", args[1], args[0]);
    if (gen < 1 or gen > 9) errorAndExit(&err.interface, "gen", args[1], args[0]);

    const seed = if (args.len > 2) try std.fmt.parseUnsigned(u64, args[2], 0) else 0x1234568;

    // const PAR = pkmn.gen1.Status.init(.PAR);
    var battle = switch (gen) {
        1 => pkmn.gen1.helpers.Battle.init(
            seed,
            &.{.{ .species = .Zapdos, .moves = &.{ .ConfuseRay, .Teleport } }},
            &.{.{ .species = .Mew, .moves = &.{ .Thrash, .Teleport } }},

            // ONE DAMAGE
            // &.{.{ .species = .Wartortle, .level = 33, .moves = &.{.Scratch} }},
            // &.{.{ .species = .Rhyhorn, .moves = &.{.Flamethrower} }},

            // MAX_FRONTIER
            // &.{.{ .species = .Hitmonlee, .hp = 118, .status = PAR, .moves = &.{
            //     .RollingKick,
            //     .ConfuseRay,
            // } }},
            // &.{.{ .species = .Hitmonlee, .hp = 118, .status = PAR, .moves = &.{
            //     .RollingKick,
            //     .ConfuseRay,
            // } }},
        ),
        else => unreachable,
    };

    var options = switch (gen) {
        1 => options: {
            var chance = pkmn.gen1.Chance(pkmn.Rational(u128)){ .probability = .{} };
            break :options pkmn.battle.options(
                pkmn.protocol.FixedLog{ .writer = &writer },
                &chance,
                pkmn.gen1.calc.NULL,
            );
        },
        else => unreachable,
    };

    _ = try battle.update(.{}, .{}, &options);
    format(gen, &writer);
    options.chance.reset();

    _ = try battle.update(move(1), move(1), &options);
    format(gen, &writer);
    std.debug.print("\x1b[41m{f} {f}\x1b[K\x1b[0m\n", .{
        options.chance.actions,
        options.chance.durations,
    });
    options.chance.reset();

    _ = try battle.update(move(1), move(0), &options);
    format(gen, &writer);
    std.debug.print("\x1b[41m{f} {f}\x1b[K\x1b[0m\n", .{
        options.chance.actions,
        options.chance.durations,
    });
    options.chance.reset();

    // _ = try battle.update(move(1), move(0), &options);
    // format(gen, &writer);
    // std.debug.print("\x1b[41m{f} {f}\x1b[K\x1b[0m\n", .{
    //     options.chance.actions,
    //     options.chance.durations,
    // });
    // options.chance.reset();

    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var out = &stdout.interface;

    var discarding: std.Io.Writer.Discarding = .init(&.{});
    const drop = &discarding.writer;

    const stats = try pkmn.gen1.calc.transitions(battle, move(1), move(0), allocator, out, drop, .{
        .durations = options.chance.durations,
        .cap = true,
        .seed = seed,
    });
    try out.print("{}\n", .{stats.?});
}

fn format(gen: u8, writer: *pkmn.protocol.Writer) void {
    if (!pkmn.options.log or !debug) return;
    pkmn.protocol.format(switch (gen) {
        1 => pkmn.gen1,
        else => unreachable,
    }, writer.buffer[0..writer.pos], null, false);
    writer.reset();
}

fn errorAndExit(err: *std.Io.Writer, msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    err.print("Invalid {s}: {any}\n", .{ msg, arg }) catch {};
    usageAndExit(err, cmd);
}

fn usageAndExit(err: *std.Io.Writer, cmd: []const u8) noreturn {
    err.print("Usage: {s} <GEN> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}
