const std = @import("std");

const pkmn = @import("pkmn.zig");

const assert = std.debug.assert;

const ERROR: u8 = 0b1100;

export const PKMN_OPTIONS: extern struct {
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

export const PKMN_MAX_CHOICES = pkmn.MAX_CHOICES;
export const PKMN_CHOICES_SIZE = pkmn.CHOICES_SIZE;
export const PKMN_MAX_LOGS = pkmn.MAX_LOGS;
export const PKMN_LOGS_SIZE = pkmn.LOGS_SIZE;

export fn pkmn_choice_init(choice: u8, data: u8) u8 {
    assert(choice <= @typeInfo(pkmn.Choice.Type).Enum.fields.len);
    assert(data <= 6);
    return @bitCast(pkmn.Choice{ .type = @enumFromInt(choice), .data = @intCast(data) });
}

export fn pkmn_choice_type(choice: u8) u8 {
    return @intFromEnum(@as(pkmn.Choice, @bitCast(choice)).type);
}

export fn pkmn_choice_data(choice: u8) u8 {
    return @as(u8, @as(pkmn.Choice, @bitCast(choice)).data);
}

export fn pkmn_result_type(result: u8) u8 {
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).type);
}

export fn pkmn_result_p1(result: u8) u8 {
    assert(!pkmn_error(result));
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).p1);
}

export fn pkmn_result_p2(result: u8) u8 {
    assert(!pkmn_error(result));
    return @intFromEnum(@as(pkmn.Result, @bitCast(result)).p2);
}

export fn pkmn_error(result: u8) bool {
    return result == ERROR;
}

export fn pkmn_psrng_init(prng: *pkmn.PSRNG, seed: u64) void {
    prng.src = .{ .seed = seed };
}

export fn pkmn_psrng_next(prng: *pkmn.PSRNG) u32 {
    return prng.next();
}

export fn pkmn_rational_init(rational: *pkmn.Rational(f64)) void {
    rational.reset();
}

export fn pkmn_rational_reduce(rational: *pkmn.Rational(f64)) void {
    rational.reduce();
}

export fn pkmn_rational_numerator(rational: *pkmn.Rational(f64)) f64 {
    return rational.p;
}

export fn pkmn_rational_denominator(rational: *pkmn.Rational(f64)) f64 {
    return rational.q;
}

export const PKMN_GEN1_MAX_CHOICES = pkmn.gen1.MAX_CHOICES;
export const PKMN_GEN1_CHOICES_SIZE = pkmn.gen1.CHOICES_SIZE;
export const PKMN_GEN1_MAX_LOGS = pkmn.gen1.MAX_LOGS;
export const PKMN_GEN1_LOGS_SIZE = pkmn.gen1.LOGS_SIZE;

const pkmn_gen1_log_options = extern struct {
    buf: [*]u8,
    len: usize,
};

const pkmn_gen1_chance_options = extern struct {
    probability: pkmn.Rational(f64),
    actions: pkmn.gen1.chance.Actions,
};

const pkmn_gen1_calc_options = extern struct {
    overrides: pkmn.gen1.calc.Overrides,
};

const pkmn_gen1_battle_options = struct {
    stream: pkmn.protocol.ByteStream,
    log: pkmn.protocol.FixedLog,
    chance: pkmn.gen1.Chance(pkmn.Rational(f64)),
    calc: pkmn.gen1.Calc,

    comptime {
        assert(@sizeOf(pkmn_gen1_battle_options) <= 128);
    }
};

export fn pkmn_gen1_battle_options_set(
    options: *pkmn_gen1_battle_options,
    log: ?*const pkmn_gen1_log_options,
    chance: ?*const pkmn_gen1_chance_options,
    calc: ?*const pkmn_gen1_calc_options,
) void {
    if (pkmn.options.log) {
        if (log) |l| {
            options.stream = .{ .buffer = l.buf[0..l.len] };
            options.log = .{ .writer = options.stream.writer() };
        } else {
            options.stream.reset();
        }
    }
    if (pkmn.options.chance) {
        if (chance) |c| {
            options.chance = .{ .probability = c.probability, .actions = c.actions };
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

export fn pkmn_gen1_battle_options_chance_probability(
    options: *pkmn_gen1_battle_options,
) *pkmn.Rational(f64) {
    return &options.chance.probability;
}

export fn pkmn_gen1_battle_options_chance_actions(
    options: *pkmn_gen1_battle_options,
) *pkmn.gen1.chance.Actions {
    return &options.chance.actions;
}

export fn pkmn_gen1_battle_options_calc_summaries(
    options: *pkmn_gen1_battle_options,
) *pkmn.gen1.calc.Summaries {
    return &options.calc.summaries;
}

export fn pkmn_gen1_battle_update(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    options: ?*pkmn_gen1_battle_options,
) pkmn.Result {
    if ((pkmn.options.log or pkmn.options.chance or pkmn.options.calc) and options != null) {
        return battle.update(c1, c2, options.?) catch return @bitCast(ERROR);
    }
    return battle.update(c1, c2, &pkmn.gen1.NULL) catch unreachable;
}

export fn pkmn_gen1_battle_choices(
    battle: *const pkmn.gen1.Battle(pkmn.gen1.PRNG),
    player: u8,
    request: u8,
    out: [*]u8,
    len: usize,
) u8 {
    assert(player <= @typeInfo(pkmn.Player).Enum.fields.len);
    assert(request <= @typeInfo(pkmn.Choice.Type).Enum.fields.len);
    assert(!pkmn.options.showdown or len > 0);
    return battle.choices(@enumFromInt(player), @enumFromInt(request), @ptrCast(out[0..len]));
}
