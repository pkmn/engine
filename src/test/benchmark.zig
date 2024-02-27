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

    const battles = std.fmt.parseUnsigned(usize, args[2], 10) catch
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

    try experiment(gen, seed, battles);
}

pub fn experiment(gen: u8, seed: u64, battles: usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;
    var random = pkmn.PSRNG.init(seed);

    var results = [_]usize{0, 0, 0};

    var i: usize = 0;
    while (i < battles) : (i += 1) {
        const opt = .{ .cleric = true, .block = false };
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, opt),
            else => unreachable,
        };
        var options = switch (gen) {
            1 => pkmn.gen1.NULL,
            else => unreachable,
        };

        var c1 = pkmn.Choice{};
        var c2 = pkmn.Choice{};

        var p1 = pkmn.PSRNG.init(random.newSeed());
        var p2 = pkmn.PSRNG.init(random.newSeed());

        var result = try battle.update(c1, c2, &options);
        while (result.type == .None) : (result = try battle.update(c1, c2, &options)) {
            var n = battle.choices(.P1, result.p1, &choices);
            if (n == 0) break;
            c1 = choices[p1.range(u8, 0, n)];
            n = battle.choices(.P2, result.p2, &choices);
            if (n == 0) break;
            c2 = choices[p2.range(u8, 0, n)];
        }

        std.debug.assert(!showdown or result.type != .Error);
        results[@intFromEnum(result.type) - 1] += 1;
    }

    var out = std.io.getStdOut().writer();
    try out.print("P1:{d} P2:{d} (T:{d})\n", .{results[0], results[1], results[2]});
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
