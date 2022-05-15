const std = @import("std");

const rng = @import("pkmn").rng;

const FixedRNG = rng.FixedRNG;

// https://en.wikipedia.org/wiki/ANSI_escape_code
pub const ANSI = struct {
    pub const RED = "\x1b[31m";
    pub const RESET = "\x1b[0m";
};

const Tool = enum {
    bide,
    confusion,
    crit,
    disable,
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

    var tool: Tool = undefined;
    var crit: u8 = undefined;
    if (std.mem.eql(u8, args[1], "bide")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .bide;
    } else if (std.mem.eql(u8, args[1], "confusion")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .confusion;
    } else if (std.mem.eql(u8, args[1], "crit")) {
        const err = std.io.getStdErr().writer();
        if (args.len != 3) {
            err.print("Usage: {s} crit <N>\n", .{args[0]}) catch {};
            std.process.exit(1);
        }
        tool = .crit;
        crit = std.fmt.parseUnsigned(u8, args[2], 10) catch {
            err.print("Usage: {s} crit <N>\n", .{args[0]}) catch {};
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, args[1], "disable")) {
        if (args.len != 2) usageAndExit(args[0]);
        tool = .disable;
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

    var expected: [256]u8 = undefined;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        expected[i] = @truncate(u8, i);
    }

    var rng1 = FixedRNG(1, expected.len){ .rolls = expected };
    var rng2 = FixedRNG(1, expected.len){ .rolls = expected };

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    i = 0;
    while (i < 256) : (i += 1) {
        const match = match: {
            switch (tool) {
                .bide => {
                    const a = rng1.range(u8, 3, 5) - 1;
                    const b = (rng2.next() & 1) + 2;
                    break :match a == b;
                },
                .confusion => {
                    const a = rng1.range(u8, 2, 6);
                    const b = (rng2.next() & 3) + 2;
                    break :match a == b;
                },
                .crit => {
                    const a = rng1.chance(u8, crit, 256);
                    const b = std.math.rotl(u8, rng2.next(), 3) < crit;
                    break :match a == b;
                },
                .disable => {
                    const a = rng1.range(u8, 1, 7) + 1;
                    const b = (rng2.next() & 7) + 1;
                    break :match a == b;
                },
                .thrash => {
                    const a = rng1.range(u8, 3, 5);
                    const b = (rng2.next() & 3) + 2;
                    break :match a == b;
                },
                .rampage => {
                    const a = rng1.range(u8, 2, 4);
                    const b = (rng2.next() & 1) + 2;
                    break :match a == b;
                },
                .sleep => {
                    const a = rng1.range(u8, 1, 8);
                    const b = (rng2.next() & 7);
                    break :match a == b;
                },
            }
        };

        if (i != 0) _ = try w.write(if (i % 16 == 0) "\n" else " ");
        if (match) {
            try w.print("{d: >3}", .{i});
        } else {
            try w.print("{s}{d: >3}{s}", .{ ANSI.RED, i, ANSI.RESET });
        }
    }
    _ = try w.write("\n");
    try buf.flush();
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <TOOL> (<arg>...)?\n", .{cmd}) catch {};
    std.process.exit(1);
}
