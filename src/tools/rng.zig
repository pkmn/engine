const std = @import("std");

const pkmn = @import("pkmn");

const FixedRNG = pkmn.rng.FixedRNG;

// https://en.wikipedia.org/wiki/ANSI_escape_code
pub const ANSI = struct {
    pub const RED = "\x1b[31m";
    pub const RESET = "\x1b[0m";
};

const Tool = enum {
    bide,
    confusion,
    chance,
    crit,
    disable,
    metronome,
    rampage,
    sleep,
    thrash,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) usageAndExit(args[0]);

    const err = std.io.getStdErr().writer();

    var tool: Tool = undefined;
    var param: u64 = undefined;
    if (std.mem.eql(u8, args[1], "bide")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .bide;
    } else if (std.mem.eql(u8, args[1], "chance")) {
        if (args.len != 3) {
            err.print("Usage: {s} chance <N>\n", .{args[0]}) catch {};
            std.process.exit(1);
        }
        tool = .chance;
        param = std.fmt.parseUnsigned(u8, args[2], 10) catch {
            err.print("Usage: {s} chance <N>\n", .{args[0]}) catch {};
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, args[1], "confusion")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .confusion;
    } else if (std.mem.eql(u8, args[1], "crit")) {
        if (args.len != 3) {
            err.print("Usage: {s} crit <Species>\n", .{args[0]}) catch {};
            std.process.exit(1);
        }
        tool = .crit;
        const crit = std.meta.stringToEnum(pkmn.gen1.Species, args[2]) orelse {
            err.print("Usage: {s} crit <N>\n", .{args[0]}) catch {};
            std.process.exit(1);
        };
        param = pkmn.gen1.Species.chance(crit);
    } else if (std.mem.eql(u8, args[1], "disable")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .disable;
    } else if (std.mem.eql(u8, args[1], "metronome")) {
        if (args.len != 3) {
            err.print("Usage: {s} metronome <Move>\n", .{args[0]}) catch {};
            std.process.exit(1);
        }
        tool = .metronome;
        const metronome = std.meta.stringToEnum(pkmn.gen1.Move, args[2]) orelse {
            err.print("Usage: {s} metronome <Move>\n", .{args[0]}) catch {};
            std.process.exit(1);
        };
        param = @enumToInt(metronome);
        const invalid = param >= @enumToInt(pkmn.gen1.Move.Struggle);
        if (invalid or metronome == .None or metronome == .Metronome) {
            err.print("Usage: {s} metronome <Move>\n", .{args[0]}) catch {};
            std.process.exit(1);
        }
    } else if (std.mem.eql(u8, args[1], "rampage")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .rampage;
    } else if (std.mem.eql(u8, args[1], "thrash")) {
        if (args.len != 2) std.process.exit(1);
        tool = .thrash;
    } else if (std.mem.eql(u8, args[1], "sleep")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .sleep;
    } else {
        usageAndExit(args[0]);
    }

    var expected: [256](if (pkmn.showdown) u32 else u8) = undefined;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        expected[i] = @truncate(u8, i);
    }

    var rng = FixedRNG(1, expected.len){ .rolls = expected };

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    try w.print("\nPokémon Red\n===========\n\n", .{});
    i = 0;
    while (i < 256) : (i += 1) {
        if (tool == .chance or tool == .metronome) {
            try w.print("{d}", .{param});
            break;
        }
        const value = switch (tool) {
            .bide, .rampage => (rng.next() & 1) + 2,
            .confusion, .thrash => (rng.next() & 3) + 2,
            .crit => @boolToInt(std.math.rotl(u8, @truncate(u8, rng.next()), 3) < param),
            .disable => (rng.next() & 7) + 1,
            .sleep => rng.next() & 7,
            else => unreachable,
        };

        if (i != 0) _ = try w.write(if (i % 16 == 0) "\n" else " ");
        if (tool == .crit) {
            if (value == 0) {
                try w.print(" {s}F{s} ", .{ ANSI.RED, ANSI.RESET });
            } else {
                try w.print(" T ", .{});
            }
        } else {
            try w.print("{d: >3}", .{value});
        }
    }
    _ = try w.write("\n");

    try w.print("\nPokémon Showdown\n================\n\n", .{});
    i = 0;

    if (tool == .chance or tool == .crit) {
        try w.print("0x{X:0<8}", .{param * 0x1000000});
    } else if (tool == .metronome) {
        const range: u64 = @enumToInt(pkmn.gen1.Move.Struggle) - 2;
        const mod = @as(u2, (if (param < @enumToInt(pkmn.gen1.Move.Metronome) - 1) 1 else 2));
        try w.print("0x{X:0<8}", .{(param - mod) * (0x100000000 / range)});
    } else {
        var range: u64 = switch (tool) {
            .bide, .thrash => 5 - 3,
            .rampage => 4 - 2,
            .confusion => 6 - 2,
            .sleep => 8 - 1,
            else => unreachable,
        };
        while (i < range) : (i += 1) {
            try w.print("0x{X:0<8}", .{i * (0x100000000 / range)});
            if (i != range - 1) try w.print(" ", .{});
        }
    }

    _ = try w.write("\n\n");
    try buf.flush();
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <TOOL> (<arg>...)?\n", .{cmd}) catch {};
    std.process.exit(1);
}
