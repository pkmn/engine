const builtin = @import("builtin");
const std = @import("std");
const pkmn = @import("pkmn");

const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

const Frame = struct {
    log: []u8 = &.{},
    state: []u8,
    result: pkmn.Result = pkmn.Result.Default,
    c1: pkmn.Choice = .{},
    c2: pkmn.Choice = .{},
};

var gen: u8 = 0;
var last: u64 = 0;
var initial: []u8 = &.{};
var buf: ?std.ArrayList(u8) = null;
var frames: ?std.ArrayList(Frame) = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var fuzz = false;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3 or args.len > 5) usageAndExit(args[0], fuzz);

    gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0], fuzz);
    if (gen < 1 or gen > 9) errorAndExit("gen", args[1], args[0], fuzz);

    var warmup: ?usize = null;
    var battles: ?usize = null;
    var duration: ?usize = null;
    if (args[2].len > 1 and std.ascii.isAlphabetic(args[2][args[2].len - 1])) {
        fuzz = true;
        const end = args[2].len - 1;
        const mod: usize = switch (args[2][end]) {
            's' => 1,
            'm' => std.time.s_per_min,
            'h' => std.time.s_per_hour,
            'd' => std.time.s_per_day,
            else => errorAndExit("duration", args[2], args[0], fuzz),
        };
        duration = mod * (std.fmt.parseUnsigned(usize, args[2][0..end], 10) catch
            errorAndExit("duration", args[2], args[0], fuzz)) * std.time.ns_per_s;
    } else {
        var arg: []u8 = args[2];
        const index = std.mem.indexOfScalar(u8, arg, '/');
        if (index) |i| {
            warmup = std.fmt.parseUnsigned(usize, arg[0..i], 10) catch
                errorAndExit("warmup", args[2], args[0], fuzz);
            if (warmup.? == 0) errorAndExit("warmup", args[2], args[0], fuzz);
            arg = arg[(i + 1)..arg.len];
        }
        battles = std.fmt.parseUnsigned(usize, arg, 10) catch
            errorAndExit("battles", args[2], args[0], fuzz);
        if (battles.? == 0) errorAndExit("battles", args[2], args[0], fuzz);
    }
    const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
        errorAndExit("seed", args[3], args[0], fuzz) else seed: {
        var secret: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        std.crypto.random.bytes(&secret);
        var csprng = std.rand.DefaultCsprng.init(secret);
        const random = csprng.random();
        break :seed random.int(usize);
    };
    try benchmark(allocator, seed, warmup, battles, duration);
}

pub fn benchmark(
    allocator: Allocator,
    seed: u64,
    warmup: ?usize,
    battles: ?usize,
    duration: ?usize,
) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    const fuzz = duration != null;
    const showdown = pkmn.options.showdown;
    const save = pkmn.options.log and builtin.mode == .Debug and fuzz;

    var random = pkmn.PSRNG.init(seed);
    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;

    var time: u64 = 0;
    var turns: usize = 0;
    var elapsed = try Timer.start();

    var out = std.io.getStdOut().writer();

    var i: usize = 0;
    var w = warmup orelse 0;
    var num = if (battles) |b| b + w else std.math.maxInt(usize);
    while (i < num and (if (duration) |d| elapsed.read() < d else true)) : (i += 1) {
        if (fuzz) last = random.src.seed;
        if (warmup != null and i == w) random = pkmn.PSRNG.init(seed);

        const opt = .{ .cleric = showdown or !fuzz, .block = showdown and !fuzz };
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, opt),
            else => unreachable,
        };
        var max = switch (gen) {
            1 => pkmn.gen1.MAX_LOGS,
            else => unreachable,
        };
        var chance = switch (gen) {
            1 => pkmn.gen1.Chance(pkmn.Rational(u64)),
            else => unreachable,
        };

        var log: ?pkmn.protocol.Log(std.ArrayList(u8).Writer) = null;
        if (save) {
            if (frames != null) deinit(allocator);
            initial = try allocator.dupe(u8, std.mem.toBytes(battle)[0..]);
            frames = std.ArrayList(Frame).init(allocator);
            buf = std.ArrayList(u8).init(allocator);
            log = pkmn.protocol.Log(std.ArrayList(u8).Writer){ .writer = buf.?.writer() };
        }

        std.debug.assert(!showdown or battle.side(.P1).get(1).hp > 0);
        std.debug.assert(!showdown or battle.side(.P2).get(1).hp > 0);

        var c1 = pkmn.Choice{};
        var c2 = pkmn.Choice{};

        var p1 = pkmn.PSRNG.init(random.newSeed());
        var p2 = pkmn.PSRNG.init(random.newSeed());

        var timer = try Timer.start();

        var result = try update(&battle, c1, c2, log, chance);
        while (result.type == .None) : (result = try update(&battle, c1, c2, log, chance)) {
            var n = battle.choices(.P1, result.p1, &choices);
            if (n == 0) break;
            c1 = choices[p1.range(u8, 0, n)];
            n = battle.choices(.P2, result.p2, &choices);
            if (n == 0) break;
            c2 = choices[p2.range(u8, 0, n)];

            if (save) {
                std.debug.assert(buf.?.items.len <= max);
                try frames.?.append(.{
                    .result = result,
                    .c1 = c1,
                    .c2 = c2,
                    .state = try allocator.dupe(u8, std.mem.toBytes(battle)[0..]),
                    .log = try buf.?.toOwnedSlice(),
                });
            }
        }

        const t = timer.read();
        if (i >= w) {
            time += t;
            turns += battle.turn;
        }
        std.debug.assert(!showdown or result.type != .Error);
    }
    if (frames != null) deinit(allocator);
    if (battles != null) try out.print("{d},{d},{d}\n", .{ time, turns, random.src.seed });
}

inline fn update(
    battle: anytype,
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    log: ?pkmn.protocol.Log(std.ArrayList(u8).Writer),
    chance: type,
) !pkmn.Result {
    if (pkmn.options.log and builtin.mode == .Debug and log != null) {
        const Options = pkmn.battle.Options(pkmn.protocol.Log(std.ArrayList(u8).Writer), chance);
        return battle.update(c1, c2, &Options{ .log = log.?, .chance = null });
    } else {
        const Options = pkmn.battle.Options(@TypeOf(pkmn.protocol.NULL));
        return battle.update(c1, c2, &Options{ .log = pkmn.protocol.NULL, .chance = null });
    }
}

fn errorAndExit(msg: []const u8, arg: []const u8, cmd: []const u8, fuzz: bool) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd, fuzz);
}

fn usageAndExit(cmd: []const u8, fuzz: bool) noreturn {
    const err = std.io.getStdErr().writer();
    if (fuzz) {
        err.print("Usage: {s} <GEN> <(WARMUP/)DURATION> <SEED?>\n", .{cmd}) catch {};
    } else {
        err.print("Usage: {s} <GEN> <BATTLES> <SEED?>\n", .{cmd}) catch {};
    }
    std.process.exit(1);
}

fn deinit(allocator: Allocator) void {
    std.debug.assert(initial.len > 0);
    allocator.free(initial);
    std.debug.assert(frames != null);
    for (frames.?.items) |frame| {
        allocator.free(frame.state);
        allocator.free(frame.log);
    }
    frames.?.deinit();
    std.debug.assert(buf != null);
    buf.?.deinit();
}

fn dump() !void {
    const out = std.io.getStdOut();
    var bw = std.io.bufferedWriter(out.writer());
    var w = bw.writer();

    if (out.isTty() or builtin.mode != .Debug) {
        try w.print("0x{X}\n", .{last});
    } else {
        try w.writeIntNative(u64, last);

        try w.writeByte(@intFromBool(pkmn.options.showdown));
        try w.writeByte(gen);
        try w.writeAll(initial);

        if (frames) |frame| {
            for (frame.items) |d| {
                try w.writeAll(d.log);
                try w.writeAll(d.state);
                try w.writeStruct(d.result);
                try w.writeStruct(d.c1);
                try w.writeStruct(d.c2);
            }
        }
        if (buf) |b| try w.writeAll(b.items);
    }

    try bw.flush();
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    dump() catch unreachable;
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
}
