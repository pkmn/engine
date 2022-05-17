const std = @import("std");
const pkmn = @import("pkmn");

const Timer = std.time.Timer;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3 or args.len > 5) usageAndExit(args[0]);

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0]);
    if (gen < 1 or gen > 8) errorAndExit("gen", args[1], args[0]);
    const battles = std.fmt.parseUnsigned(usize, args[2], 10) catch
        errorAndExit("battles", args[2], args[0]);
    if (battles == 0) errorAndExit("battles", args[2], args[0]);
    const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 10) catch
        errorAndExit("seed", args[3], args[0]) else 0x31415926;
    const playouts = if (args.len == 5) std.fmt.parseUnsigned(usize, args[4], 10) catch
        errorAndExit("playouts", args[4], args[0]) else null;

    try benchmark(gen, seed, battles, playouts);
}

pub fn benchmark(gen: u8, seed: u64, battles: usize, playouts: ?usize) !void {
    std.debug.assert(gen >= 1 and gen <= 8);

    var random = pkmn.PRNG.init(seed);
    var options: [pkmn.OPTIONS_SIZE]pkmn.Choice = undefined;

    var duration: u64 = 0;
    var turns: usize = 0;

    var i: usize = 0;
    while (i < battles) : (i += 1) {
        var original = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, playouts != null),
            else => unreachable,
        };

        var n = playouts orelse 1;
        var j: usize = 0;
        while (j < n) : (j += 1) {
            var battle = original;

            var c1 = pkmn.Choice{};
            var c2 = pkmn.Choice{};

            var p1 = pkmn.PRNG.init(random.newSeed());
            var p2 = pkmn.PRNG.init(random.newSeed());

            var timer = try Timer.start();
            var result = try battle.update(c1, c2, null);
            while (result.type == .None) : (result = try battle.update(c1, c2, null)) {
                c1 = options[p1.range(u8, 0, battle.choices(.P1, result.p1, &options))];
                c2 = options[p2.range(u8, 0, battle.choices(.P2, result.p2, &options))];
            }
            duration += timer.read();
            turns += battle.turn;
        }
    }

    var out = std.io.getStdOut().writer();
    try out.print("{d},{d},{d}\n", .{ duration, turns, random.src.seed });
}

fn errorAndExit(msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd);
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <GEN> <BATTLES> <SEED?> <PLAYOUTS?>\n", .{cmd}) catch {};
    std.process.exit(1);
}
