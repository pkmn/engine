const std = @import("std");
const pkmn = @import("../pkmn.zig");

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
    return @bitCast(u8, pkmn.Choice{
        .type = @enumFromInt(pkmn.Choice.Type, choice),
        .data = @intCast(u4, data),
    });
}

export fn pkmn_choice_type(choice: u8) u8 {
    return @as(u8, @intFromEnum(@bitCast(pkmn.Choice, choice).type));
}

export fn pkmn_choice_data(choice: u8) u8 {
    return @as(u8, @bitCast(pkmn.Choice, choice).data);
}

export fn pkmn_result_type(result: u8) u8 {
    return @intFromEnum(@bitCast(pkmn.Result, result).type);
}

export fn pkmn_result_p1(result: u8) u8 {
    assert(!pkmn_error(result));
    return @intFromEnum(@bitCast(pkmn.Result, result).p1);
}

export fn pkmn_result_p2(result: u8) u8 {
    assert(!pkmn_error(result));
    return @intFromEnum(@bitCast(pkmn.Result, result).p2);
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

export const PKMN_GEN1_MAX_CHOICES = pkmn.gen1.MAX_CHOICES;
export const PKMN_GEN1_CHOICES_SIZE = pkmn.gen1.CHOICES_SIZE;
export const PKMN_GEN1_MAX_LOGS = pkmn.gen1.MAX_LOGS;
export const PKMN_GEN1_LOGS_SIZE = pkmn.gen1.LOGS_SIZE;

const pkmn_gen1_log_options = extern struct {
    buf: [*]u8,
    len: usize,
};

const pkmn_gen1_battle_options = extern struct {
    log: ?*pkmn_gen1_log_options,
    chance: ?*pkmn.gen1.Chance(pkmn.Rational(f64)),
    calc: ?*pkmn.gen1.Calc,
};

export fn pkmn_gen1_battle_update(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    options: ?*pkmn_gen1_battle_options,
) pkmn.Result {
    if (pkmn.options.log or pkmn.options.chance or pkmn.options.calc and options != null) {
        const opts = options.?;
        if (pkmn.options.log and opts.log != null) {
            if (pkmn.options.chance and opts.chance != null) {
                if (pkmn.options.calc and opts.calc != null) {
                    // log & chance & calc
                }
                // log & chance
            }
            if (pkmn.options.calc and opts.calc != null) {
                // log & calc
            }
            // log
        }
        if (pkmn.options.chance and opts.chance != null) {
            if (pkmn.options.calc and opts.calc != null) {
                // chance & calc
            }
            // chance
        }
        if (pkmn.options.calc and opts.calc != null) {
            // calc
        }
    }
    return battle.update(c1, c2, &pkmn.gen1.NULL) catch unreachable;
}

export fn pkmn_gen1_battle_choices(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    player: u8,
    request: u8,
    out: [*]u8,
    len: usize,
) u8 {
    assert(player <= @typeInfo(pkmn.Player).Enum.fields.len);
    assert(request <= @typeInfo(pkmn.Choice.Type).Enum.fields.len);
    assert(!pkmn.options.showdown or len > 0);
    return battle.choices(
        @enumFromInt(pkmn.Player, player),
        @enumFromInt(pkmn.Choice.Type, request),
        @ptrCast([]pkmn.Choice, out[0..len]),
    );
}
