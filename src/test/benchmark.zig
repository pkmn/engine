const std = @import("std");
const pkmn = @import("pkmn");

const Timer = std.time.Timer;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 5) usageAndExit(args[0]);

    const err = std.io.getStdErr().writer();

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch {
        try err.print("Invalid gen: {s}\n", .{args[1]});
        usageAndExit(args[0]);
    };
    const battles = std.fmt.parseUnsigned(u64, args[2], 10) catch {
        try err.print("Invalid battles: {s}\n", .{args[2]});
        usageAndExit(args[0]);
    };
    const playouts = std.fmt.parseUnsigned(usize, args[3], 10) catch {
        try err.print("Invalid playouts: {s}\n", .{args[3]});
        usageAndExit(args[0]);
    };
    const seed = std.fmt.parseUnsigned(usize, args[4], 10)  catch {
        try err.print("Invalid seed: {s}\n", .{args[4]});
        usageAndExit(args[0]);
    };

    try benchmark(gen, battles, playouts, seed);
}

pub fn benchmark(gen: u8, battles: usize, playouts: usize, seed: u64) !void {
    std.debug.assert(gen >= 1 and gen <= 8);

    var random = pkmn.PRNG.init(seed);
    var options: [pkmn.MAX_OPTIONS_SIZE]pkmn.Choice = undefined;

    var duration: u64 = 0;
    var turns: usize = 0;

    var i: usize = 0;
    while (i <= battles) : (i += 1) {
        var original = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, true),
            // TODO: support additional generations
            else => unreachable,
        };

        var j: usize = 0;
        while (j <= playouts) : (j += 1) {
            var battle = original;

            var c1 = pkmn.Choice{};
            var c2 = pkmn.Choice{};

            var timer = try Timer.start();
            var result = try battle.update(c1, c2, null);
            while (result.type == .None) : (result = try battle.update(c1, c2, null)) {
                c1 = options[random.range(u8, 0, battle.choices(.P1, result.p1, &options))];
                c2 = options[random.range(u8, 0, battle.choices(.P2, result.p2, &options))];
            }
            duration += timer.read();
            turns += battle.turn;
        }
    }

    var out = std.io.getStdOut().writer();
    try out.print("{d},{d},{d}\n", .{ duration, turns, random.src.seed });
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <gen> <battles> <playouts> <seed>\n", .{cmd}) catch std.process.exit(1);
    std.process.exit(1);
}
