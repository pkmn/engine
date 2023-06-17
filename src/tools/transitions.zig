const std = @import("std");

const pkmn = @import("pkmn");

const move = pkmn.gen1.helpers.move;

pub const pkmn_options = pkmn.Options{ .internal = true };

pub fn main() !void {
    std.debug.assert(pkmn.options.calc and pkmn.options.chance);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const seed = if (args.len > 1) try std.fmt.parseUnsigned(u64, args[1], 0) else 0x1234568;

    var battle = pkmn.gen1.helpers.Battle.init(
        seed,
        // &.{.{ .species = .Charmander, .moves = &.{.BodySlam} }},
        // &.{.{ .species = .Squirtle, .stats = .{}, .moves = &.{.Surf} }},
        &.{.{ .species = .Charmander, .hp = 5, .level = 5, .stats = .{}, .moves = &.{.Scratch} }},
        &.{.{ .species = .Squirtle, .hp = 4, .level = 5, .stats = .{}, .moves = &.{.Tackle} }},
    );
    _ = try battle.update(.{}, .{}, &pkmn.gen1.NULL);

    const out = std.io.getStdOut();
    // var buf = std.io.bufferedWriter(out.writer());
    // var w = buf.writer();
    var w = out.writer();

    _ = try pkmn.gen1.calc.transitions(battle, move(1), move(1), .{}, seed, allocator, w);

    // try buf.flush();
}
