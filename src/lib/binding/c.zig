const std = @import("std");
const pkmn = @import("../pkmn.zig");

const assert = std.debug.assert;

const ERROR: u8 = 0b1100;

export const PKMN_OPTIONS: extern struct { showdown: bool, trace: bool } = .{
    .showdown = pkmn.options.showdown,
    .trace = pkmn.options.trace,
};

export const PKMN_MAX_OPTIONS = pkmn.MAX_OPTIONS;
export const PKMN_OPTIONS_SIZE = pkmn.OPTIONS_SIZE;
export const PKMN_MAX_LOGS = pkmn.MAX_LOGS;
export const PKMN_LOGS_SIZE = pkmn.LOGS_SIZE;

export fn pkmn_choice_init(choice: u8, data: u8) u8 {
    assert(choice <= @typeInfo(pkmn.Choice.Type).Enum.fields.len);
    assert(data <= 6);
    return @bitCast(u8, pkmn.Choice{
        .type = @intToEnum(pkmn.Choice.Type, choice),
        .data = @intCast(u4, data),
    });
}

export fn pkmn_choice_type(choice: u8) u8 {
    return @as(u8, @enumToInt(@bitCast(pkmn.Choice, choice).type));
}

export fn pkmn_choice_data(choice: u8) u8 {
    return @as(u8, @bitCast(pkmn.Choice, choice).data);
}

export fn pkmn_result_type(result: u8) u8 {
    return @enumToInt(@bitCast(pkmn.Result, result).type);
}

export fn pkmn_result_p1(result: u8) u8 {
    assert(!pkmn_error(result));
    return @enumToInt(@bitCast(pkmn.Result, result).p1);
}

export fn pkmn_result_p2(result: u8) u8 {
    assert(!pkmn_error(result));
    return @enumToInt(@bitCast(pkmn.Result, result).p2);
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

export const PKMN_GEN1_MAX_OPTIONS = pkmn.gen1.MAX_OPTIONS;
export const PKMN_GEN1_OPTIONS_SIZE = pkmn.gen1.OPTIONS_SIZE;
export const PKMN_GEN1_MAX_LOGS = pkmn.gen1.MAX_LOGS;
export const PKMN_GEN1_LOGS_SIZE = pkmn.gen1.LOGS_SIZE;

export fn pkmn_gen1_battle_update(
    battle: *pkmn.gen1.Battle(pkmn.gen1.PRNG),
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    buf: ?[*]u8,
    len: usize,
) pkmn.Result {
    if (pkmn.options.trace) {
        if (buf) |b| {
            var stream = pkmn.protocol.ByteStream{ .buffer = b[0..len] };
            var log = pkmn.protocol.FixedLog{ .writer = stream.writer() };
            return battle.update(c1, c2, log) catch return @bitCast(pkmn.Result, ERROR);
        }
    }
    return battle.update(c1, c2, pkmn.protocol.NULL) catch unreachable;
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
        @intToEnum(pkmn.Player, player),
        @intToEnum(pkmn.Choice.Type, request),
        @ptrCast([]pkmn.Choice, out[0..len]),
    );
}
