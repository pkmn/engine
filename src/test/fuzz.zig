const builtin = @import("builtin");
const std = @import("std");
const pkmn = @import("pkmn");

pub const pkmn_options = pkmn.Options{ .internal = true };

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

const showdown = pkmn.options.showdown;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3 or args.len > 5) usageAndExit(args[0]);

    gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0]);
    if (gen < 1 or gen > 9) errorAndExit("gen", args[1], args[0]);

    const end = args[2].len - 1;
    const mod: usize = switch (args[2][end]) {
        's' => 1,
        'm' => std.time.s_per_min,
        'h' => std.time.s_per_hour,
        'd' => std.time.s_per_day,
        else => errorAndExit("duration", args[2], args[0]),
    };
    var duration = mod * (std.fmt.parseUnsigned(usize, args[2][0..end], 10) catch
        errorAndExit("duration", args[2], args[0])) * std.time.ns_per_s;

    const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
        errorAndExit("seed", args[3], args[0]) else seed: {
        var secret: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
        std.crypto.random.bytes(&secret);
        var csprng = std.rand.DefaultCsprng.init(secret);
        const random = csprng.random();
        break :seed random.int(usize);
    };

    try fuzz(allocator, seed, duration);
}

pub fn fuzz(allocator: std.mem.Allocator, seed: u64, duration: usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    const save = pkmn.options.log and builtin.mode == .Debug;

    var random = pkmn.PSRNG.init(seed);

    var elapsed = try std.time.Timer.start();
    while (elapsed.read() < duration) {
        last = random.src.seed;

        const opt = .{ .cleric = showdown, .block = false };
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, opt),
            else => unreachable,
        };
        var max = switch (gen) {
            1 => pkmn.gen1.MAX_LOGS,
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

        switch (gen) {
            1 => if (save) blk: {
                const options =
                    pkmn.battle.options(log.?, pkmn.gen1.chance.NULL, pkmn.gen1.calc.NULL);
                break :blk try run(&battle, &random, save, max, allocator, options);
            } else try run(&battle, &random, save, max, allocator, pkmn.gen1.NULL),
            else => unreachable,
        }
    }
    if (frames != null) deinit(allocator);
}

fn run(
    battle: anytype,
    random: *pkmn.PSRNG,
    save: bool,
    max: usize,
    allocator: std.mem.Allocator,
    options: anytype,
) !void {
    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;

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

        if (save) {
            std.debug.assert(buf.?.items.len <= max);
            try frames.?.append(.{
                .result = result,
                .c1 = c1,
                .c2 = c2,
                .state = try allocator.dupe(u8, std.mem.toBytes(battle.*)[0..]),
                .log = try buf.?.toOwnedSlice(),
            });
        }
        if (pkmn.options.chance and pkmn.options.calc) {
            // TODO: transitions function + MAX_FRONTIER_SIZE
        }
    }

    std.debug.assert(!showdown or result.type != .Error);
}

fn errorAndExit(msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd);
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <GEN> <DURATION> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}

fn deinit(allocator: std.mem.Allocator) void {
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

        try w.writeByte(@intFromBool(showdown));
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
