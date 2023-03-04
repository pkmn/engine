const std = @import("std");
const pkmn = @import("../pkmn.zig");

export const SHOWDOWN = pkmn.options.showdown;
export const TRACE = pkmn.options.trace;

export const GEN1_OPTIONS_SIZE =
    std.math.ceilPowerOfTwo(u32, @truncate(u32, pkmn.gen1.OPTIONS_SIZE)) catch unreachable;
export const GEN1_LOG_SIZE =
    std.math.ceilPowerOfTwo(u32, @truncate(u32, pkmn.gen1.LOG_SIZE)) catch unreachable;
