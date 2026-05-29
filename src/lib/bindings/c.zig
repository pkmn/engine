const pkmn = @import("../pkmn.zig");
const std = @import("std");
const util = @import("../common/util.zig");

const assert = std.debug.assert;

const ERROR: u8 = 0b1100;

pub const OPTIONS: extern struct {
    showdown: bool,
    log: bool,
    chance: bool,
    calc: bool,
} = .{
    .showdown = pkmn.options.showdown,
    .log = pkmn.options.log,
    .chance = pkmn.options.chance,
    .calc = pkmn.options.calc,
};

pub const MAX_CHOICES = pkmn.MAX_CHOICES;
pub const CHOICES_SIZE = pkmn.CHOICES_SIZE;
pub const MAX_LOGS = pkmn.MAX_LOGS;
pub const LOGS_SIZE = pkmn.LOGS_SIZE;

pub fn choice_init(choice: u8, data: u8) callconv(.c) u8 {
    assert(choice <= util.EnumFieldsLen(pkmn.Choice.Type));
    assert(data <= 6);
    return @bitCast(pkmn.Choice{ .type = @enumFromInt(choice), .data = @intCast(data) });
}

pub fn choice_type(choice: u8) callconv(.c) u8 {
    return @intFromEnum(@as(pkmn.Choice, @bitCast(choice)).type);
}

pub fn choice_data(choice: u8) callconv(.c) u8 {
    return @as(u8, @as(pkmn.Choice, @bitCast(choice)).data);
}

pub fn result_type(result: u8) callconv(.c) u8 {
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).type);
}

pub fn result_p1(result: u8) callconv(.c) u8 {
    assert(!err(result));
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).p1);
}

pub fn result_p2(result: u8) callconv(.c) u8 {
    assert(!err(result));
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).p2);
}

pub fn err(result: u8) callconv(.c) bool {
    return result == ERROR;
}

pub fn psrng_init(prng: *pkmn.PSRNG, seed: u64) callconv(.c) void {
    prng.src = .{ .seed = seed };
}

pub fn psrng_next(prng: *pkmn.PSRNG) callconv(.c) u32 {
    return prng.next();
}

pub fn rational_init(rational: *pkmn.Rational(f64)) callconv(.c) void {
    rational.reset();
}

pub fn rational_reduce(rational: *pkmn.Rational(f64)) callconv(.c) void {
    rational.reduce();
}

pub fn rational_numerator(rational: *const pkmn.Rational(f64)) callconv(.c) f64 {
    return rational.p;
}

pub fn rational_denominator(rational: *const pkmn.Rational(f64)) callconv(.c) f64 {
    return rational.q;
}

const log_options = extern struct {
    buf: [*]u8,
    len: usize,
};

pub fn gen(comptime num: comptime_int) type {
    const g = @field(pkmn, "gen" ++ std.fmt.comptimePrint("{d}", .{num}));

    return struct {
        pub const MAX_CHOICES = g.MAX_CHOICES;
        pub const CHOICES_SIZE = g.CHOICES_SIZE;
        pub const MAX_LOGS = g.MAX_LOGS;
        pub const LOGS_SIZE = g.LOGS_SIZE;

        const chance_options = extern struct {
            probability: pkmn.Rational(f64),
            actions: g.chance.Actions,
            durations: g.chance.Durations,
        };

        const calc_options = extern struct {
            overrides: g.chance.Actions,
        };

        const battle_options = struct {
            writer: pkmn.protocol.Writer,
            log: pkmn.protocol.FixedLog,
            chance: g.Chance(pkmn.Rational(f64)),
            calc: g.Calc,

            comptime {
                assert(@sizeOf(battle_options) <= 128);
            }
        };

        pub fn battle_options_set(
            options: *battle_options,
            log: ?*const log_options,
            chance: ?*const chance_options,
            calc: ?*const calc_options,
        ) callconv(.c) void {
            if (pkmn.options.log) {
                if (log) |l| {
                    options.writer = .{ .buffer = l.buf[0..l.len] };
                    options.log = .{ .writer = &options.writer };
                } else {
                    options.writer.reset();
                }
            }
            if (pkmn.options.chance) {
                if (chance) |c| {
                    options.chance = .{
                        .probability = c.probability,
                        .actions = c.actions,
                        .durations = c.durations,
                    };
                } else {
                    options.chance.reset();
                }
            }
            if (pkmn.options.calc) {
                if (calc) |c| {
                    options.calc = .{ .overrides = c.overrides };
                } else {
                    options.calc = .{};
                }
            }
        }

        pub fn battle_options_chance_probability(
            options: *battle_options,
        ) callconv(.c) *pkmn.Rational(f64) {
            return &options.chance.probability;
        }

        pub fn battle_options_chance_actions(
            options: *battle_options,
        ) callconv(.c) *g.chance.Actions {
            return &options.chance.actions;
        }

        pub fn battle_options_chance_durations(
            options: *battle_options,
        ) callconv(.c) *g.chance.Durations {
            return &options.chance.durations;
        }

        pub fn battle_options_calc_summaries(
            options: *battle_options,
        ) callconv(.c) *g.calc.Summaries {
            return &options.calc.summaries;
        }

        pub fn battle_update(
            battle: *g.Battle(g.PRNG),
            c1: pkmn.Choice,
            c2: pkmn.Choice,
            opts: ?*battle_options,
        ) callconv(.c) pkmn.Result {
            if ((pkmn.options.log or pkmn.options.chance or pkmn.options.calc) and opts != null) {
                return battle.update(c1, c2, opts.?) catch return @bitCast(ERROR);
            }
            return battle.update(c1, c2, &g.NULL) catch unreachable;
        }

        pub fn battle_choices(
            battle: *const g.Battle(g.PRNG),
            player: u8,
            request: u8,
            out: [*]u8,
            n: usize,
        ) callconv(.c) u8 {
            assert(player <= util.EnumFieldsLen(pkmn.Player));
            assert(request <= util.EnumFieldsLen(pkmn.Choice.Type));

            assert(!pkmn.options.showdown or n > 0);
            return battle.choices(@enumFromInt(player), @enumFromInt(request), @ptrCast(out[0..n]));
        }
    };
}
