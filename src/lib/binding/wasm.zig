const std = @import("std");
const pkmn = @import("../pkmn.zig");

export const SHOWDOWN = pkmn.options.showdown;
export const LOG = pkmn.options.log;
export const CHANCE = pkmn.options.chance;
export const CALC = pkmn.options.calc;

export const GEN1_CHOICES_SIZE =
    std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(pkmn.gen1.CHOICES_SIZE))) catch unreachable;
export const GEN1_LOGS_SIZE =
    std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(pkmn.gen1.LOGS_SIZE))) catch unreachable;
