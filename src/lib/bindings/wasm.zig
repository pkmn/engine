const pkmn = @import("../pkmn.zig");
const std = @import("std");
const util = @import("../common/util.zig");

const assert = std.debug.assert;

pub const options = pkmn.options;

pub fn gen(comptime num: comptime_int) type {
    const g = @field(pkmn, "gen" ++ std.fmt.comptimePrint("{d}", .{num}));
    return struct {
        pub const CHOICES_SIZE = size(g.CHOICES_SIZE);
        pub const LOGS_SIZE = size(g.LOGS_SIZE);

        pub fn update(
            battle: *g.Battle(g.PRNG),
            c1: pkmn.Choice,
            c2: pkmn.Choice,
            options_: ?[*]u8,
        ) callconv(.c) pkmn.Result {
            return (if (options_) |o| result: {
                const buf = @as([*]u8, @ptrCast(o))[0..g.LOGS_SIZE];
                var writer: pkmn.protocol.Writer = .{ .buffer = buf };
                // TODO: extract out
                var opts = pkmn.battle.options(
                    pkmn.protocol.FixedLog{ .writer = &writer },
                    g.chance.NULL,
                    g.calc.NULL,
                );
                break :result battle.update(c1, c2, &opts);
            } else battle.update(c1, c2, &g.NULL)) catch unreachable;
        }

        pub fn choices(
            battle: *g.Battle(g.PRNG),
            player: u8,
            request: u8,
            buf: [*]u8,
        ) callconv(.c) u8 {
            assert(player <= util.EnumFieldsLen(pkmn.Player));
            assert(request <= util.EnumFieldsLen(pkmn.Choice.Type));

            const n = CHOICES_SIZE;
            return battle.choices(@enumFromInt(player), @enumFromInt(request), @ptrCast(buf[0..n]));
        }
    };
}

fn size(n: usize) u32 {
    return std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(n))) catch unreachable;
}
