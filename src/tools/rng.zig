const std = @import("std");

const pkmn = @import("pkmn");

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
    damage,
    disable,
    distribution,
    metronome,
    rampage,
    seed,
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
    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    const tool: Tool = std.meta.stringToEnum(Tool, args[1]) orelse usageAndExit(args[0]);
    var param: u64 = undefined;
    switch (tool) {
        .chance => {
            if (args.len != 3) {
                err.print("Usage: {s} chance <N>\n", .{args[0]}) catch {};
                std.process.exit(1);
            }
            param = std.fmt.parseUnsigned(u8, args[2], 10) catch {
                err.print("Usage: {s} chance <N>\n", .{args[0]}) catch {};
                std.process.exit(1);
            };
        },
        .crit => {
            if (args.len != 3) {
                err.print("Usage: {s} crit <Species>\n", .{args[0]}) catch {};
                std.process.exit(1);
            }
            const crit = std.meta.stringToEnum(pkmn.gen1.Species, args[2]) orelse {
                err.print("Usage: {s} crit <Species>\n", .{args[0]}) catch {};
                std.process.exit(1);
            };
            param = pkmn.gen1.Species.chance(crit);
        },
        .metronome => {
            if (args.len != 3) {
                err.print("Usage: {s} metronome <Move>\n", .{args[0]}) catch {};
                std.process.exit(1);
            }
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
        },
        .seed => {
            if (args.len != 3) {
                err.print("Usage: {s} seed <N>\n", .{args[0]}) catch {};
                std.process.exit(1);
            }
            param = std.fmt.parseUnsigned(u8, args[2], 10) catch {
                err.print("Usage: {s} seed <N>\n", .{args[0]}) catch {};
                std.process.exit(1);
            };

            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const a: u8 = 5 *% @truncate(u8, i) +% 1;
                const b: u8 = 5 *% a +% 1;
                const c: u8 = 5 *% b +% 1;
                if (c != param) continue;

                const d: u8 = 5 *% c +% 1;
                const e: u8 = 5 *% d +% 1;
                try w.print(
                    "{d} {d} {s}{d}{s} {d} {d}\n",
                    .{ a, b, ANSI.RED, c, ANSI.RESET, d, e },
                );
            }
            try buf.flush();
            std.process.exit(0);
        },
        else => if (args.len != 2) usageAndExit(args[0]),
    }

    try w.print("\nPokémon Red\n===========\n\n", .{});
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (tool == .chance or tool == .metronome) {
            try w.print("{d}", .{param});
            break;
        }
        const next = @truncate(u8, i);
        const value = switch (tool) {
            .bide, .rampage => (next & 1) + 2,
            .damage => std.math.rotr(u8, next, 1),
            .confusion, .distribution, .thrash => (next & 3) + 2,
            .crit => @boolToInt(std.math.rotl(u8, @truncate(u8, next), 3) < param),
            .disable => (next & 7) + 1,
            .sleep => next & 7,
            else => unreachable,
        };

        if (i != 0) _ = try w.write(if (i % 16 == 0) "\n" else " ");
        if (tool == .crit) {
            if (value == 0) {
                try w.print(" {s}F{s} ", .{ ANSI.RED, ANSI.RESET });
            } else {
                try w.print(" T ", .{});
            }
        } else if (tool == .damage) {
            if (value < 217) {
                try w.print("{s}{d: >3}{s}", .{ ANSI.RED, value, ANSI.RESET });
            } else {
                try w.print("{d: >3}", .{value});
            }
        } else {
            try w.print("{d: >3}", .{value});
        }
    }
    _ = try w.write("\n");

    try w.print("\nPokémon Showdown\n================\n\n", .{});
    i = 0;

    if (tool == .chance or tool == .crit) {
        try w.print("0x{X:0>8}", .{param * 0x1000000});
    } else if (tool == .metronome) {
        const range: u64 = @enumToInt(pkmn.gen1.Move.Struggle) - 2;
        const mod = @as(u2, (if (param < @enumToInt(pkmn.gen1.Move.Metronome) - 1) 1 else 2));
        try w.print("0x{X:0>8}", .{((param - mod) + 1) * (0x100000000 / range) - 1});
    } else if (tool == .distribution) {
        const range: u64 = 8;
        try w.print("0x{X:0>8} 0x{X:0>8} 0x{X:0>8} 0x{X:0>8}", .{
            0 * (0x100000000 / range),
            3 * (0x100000000 / range),
            6 * (0x100000000 / range),
            7 * (0x100000000 / range),
        });
    } else {
        var range: u64 = switch (tool) {
            .bide, .thrash => 5 - 3,
            .damage => 256 - 217,
            .rampage => 4 - 2,
            .confusion => 6 - 2,
            .sleep => 8 - 1,
            else => unreachable,
        };
        while (i < range) : (i += 1) {
            try w.print("0x{X:0>8}", .{i * (0x100000000 / range)});
            if (range > 9 and i % 3 == 2) {
                _ = try w.write("\n");
            } else if (i != range - 1) {
                _ = try w.write(" ");
            }
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
