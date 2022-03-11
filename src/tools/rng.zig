const std = @import("std");

const rng = @import("rng");

const FixedRNG = rng.FixedRNG;

// https://en.wikipedia.org/wiki/ANSI_escape_code
pub const ANSI = struct {
    pub const RED = "\x1b[31m";
    pub const RESET = "\x1b[0m";
};

const CRIT: u8 = 93; // EDIT ME

const Tool = enum {
    crit,
    thrash,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) std.process.exit(1);

    var tool: Tool = undefined;
    if (std.mem.eql(u8, args[1], "crit")) {
        tool = .crit;
    } else if (std.mem.eql(u8, args[1], "thrash")) {
        tool = .thrash;
    } else {
        std.process.exit(1);
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
                .crit => {
                    const a = rng1.chance(CRIT, 256);
                    const b = std.math.rotl(u8, rng2.next(), 3) < CRIT;
                    break :match a == b;
                },
                .thrash => {
                    const a = rng1.range(3, 5);
                    const b = (rng2.next() & 3) + 2;
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
