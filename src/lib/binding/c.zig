const std = @import("std");
const pkmn = @import("../pkmn.zig");

const assert = std.debug.assert;

const ERROR = 0b1000;

export const PKMN_OPTIONS: pkmn.Options = .{
    .showdown = pkmn.options.showdown,
    .trace = pkmn.options.trace,
    .advance = pkmn.options.advance,
    .ebc = pkmn.options.ebc,
};

export const PKMN_MAX_OPTIONS = pkmn.MAX_OPTIONS;
export const PKMN_OPTIONS_SIZE = pkmn.OPTIONS_SIZE;
export const PKMN_MAX_LOGS = pkmn.MAX_LOGS;
export const PKMN_LOGS_SIZE = pkmn.LOGS_SIZE;

export fn pkmn_choice_init(choice: pkmn.Choice.Type, data: u8) pkmn.Choice {
    assert(data <= 6);
    return .{ .type = choice, .data = data };
}

export fn pkmn_result_type(result: u8) pkmn.Result.Type {
    if (pkmn_error(result)) return .Error;
    return @bitCast(pkmn.Result.Type, @as(u8, result)).type;
}

export fn pkmn_result_p1(result: u8) pkmn.Choice.Type {
    assert(!pkmn_error(result));
    return @bitCast(pkmn.Result.Type, @as(u8, result)).p1;
}

export fn pkmn_result_p2(result: u8) pkmn.Choice.Type {
    assert(!pkmn_error(result));
    return @bitCast(pkmn.Result.Type, @as(u8, result)).p2;
}

export fn pkmn_error(result: u8) bool {
    return (result & ERROR) > 0;
}

export fn pkmn_psrng_init(prng: *pkmn.PSRNG, seed: u64) pkmn.PSRNG {
    prng.src = .{ .seed = seed };
}

export fn pkmn_psrng_next(prng: *pkmn.PSRNG) u32 {
    return prng.next();
}

export const PKMN_GEN1_MAX_OPTIONS = pkmn.gen1.MAX_OPTIONS;
export const PKMN_GEN1_OPTIONS_SIZE = pkmn.gen1.OPTIONS_SIZE;
export const PKMN_GEN1_MAX_LOGS = pkmn.gen1.MAX_LOGS;
export const PKMN_GEN1_LOGS_SIZE = pkmn.gen1.LOGS_SIZE;

export fn pkmn_gen1_battle_update(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    buf: ?[*]u8,
) u8 {
    if (buf) |b| {
        var stream = std.io.fixedBufferStream(&b);
        var log = pkmn.protocol.FixedLog{ .writer = stream.writer() };
        return @bitCast(u8, battle.update(c1, c2, log)) catch return ERROR;
    }
    return @bitCast(u8, battle.update(c1, c2, null) catch unreachable);
}

export fn pkmn_gen1_battle_choices(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    player: pkmn.Player,
    request: pkmn.Choice.Type,
    out: [*]u8,
) u8 {
    return battle.choices(player, request, out);
}
