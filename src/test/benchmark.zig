const std = @import("std");
const pkmn = @import("pkmn");

const showdown = pkmn.options.showdown;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3 or args.len > 5) usageAndExit(args[0]);

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0]);
    if (gen < 1 or gen > 9) errorAndExit("gen", args[1], args[0]);

    var arg: []u8 = args[2];
    var warmup: ?usize = null;
    const index = std.mem.indexOfScalar(u8, arg, '/');
    if (index) |i| {
        warmup = std.fmt.parseUnsigned(usize, arg[0..i], 10) catch
            errorAndExit("warmup", args[2], args[0]);
        if (warmup.? == 0) errorAndExit("warmup", args[2], args[0]);
        arg = arg[(i + 1)..arg.len];
    }
    var battles = std.fmt.parseUnsigned(usize, arg, 10) catch
        errorAndExit("battles", args[2], args[0]);
    if (battles == 0) errorAndExit("battles", args[2], args[0]);

    const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
        errorAndExit("seed", args[3], args[0]) else seed: {
        var secret: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        std.crypto.random.bytes(&secret);
        var csprng = std.rand.DefaultCsprng.init(secret);
        const random = csprng.random();
        break :seed random.int(usize);
    };

    try benchmark(gen, seed, battles, warmup);
}

pub fn benchmark(gen: u8, seed: u64, battles: usize, warmup: ?usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;
    var random = pkmn.PSRNG.init(seed);

    var time: u64 = 0;
    var turns: usize = 0;

    var i: usize = 0;
    var w = warmup orelse 0;
    const num = battles + w;
    while (i < num) : (i += 1) {
        if (warmup != null and i == w) random = pkmn.PSRNG.init(seed);

        const opt = .{ .cleric = showdown, .block = showdown };
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, opt),
            else => unreachable,
        };
        var options = switch (gen) {
            1 => pkmn.gen1.NULL,
            else => unreachable,
        };

        std.debug.assert(!showdown or battle.side(.P1).get(1).hp > 0);
        std.debug.assert(!showdown or battle.side(.P2).get(1).hp > 0);

        var c1 = pkmn.Choice{};
        var c2 = pkmn.Choice{};

        var p1 = pkmn.PSRNG.init(random.newSeed());
        var p2 = pkmn.PSRNG.init(random.newSeed());

        var timer = try std.time.Timer.start();

        var result = try battle.update(c1, c2, &options);
        while (result.type == .None) : (result = try battle.update(c1, c2, &options)) {
            var n = battle.choices(.P1, result.p1, &choices);
            if (n == 0) break;
            c1 = choices[p1.range(u8, 0, n)];
            n = battle.choices(.P2, result.p2, &choices);
            if (n == 0) break;
            c2 = choices[p2.range(u8, 0, n)];
        }

        const t = timer.read();
        std.debug.assert(!showdown or result.type != .Error);

        if (i >= w) {
            time += t;
            turns += battle.turn;
        }
    }

    var out = std.io.getStdOut().writer();
    try out.print("{d},{d},{d}\n", .{ time, turns, random.src.seed });
}

fn errorAndExit(msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd);
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <GEN> <(WARMUP/)BATTLES> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}
