const std = @import("std");

const assert = std.debug.assert;

// https://pkmn.cc/pokered/constants/type_constants.asm
pub const Type = enum(u4) {
    Normal,
    Fighting,
    Flying,
    Poison,
    Ground,
    Rock,
    Bird,
    Bug,
    Ghost,
    Fire,
    Water,
    Grass,
    Electric,
    Psychic,
    Ice,
    Dragon,

    comptime {
        assert(@sizeOf(Type) == 1);
    }
};

// https://pkmn.cc/pokered/constants/battle_constants.asm#L52-L57
pub const Efffectiveness = enum(u8) {
    Super = 20,
    Neutral = 10,
    Resisted = 5,
    Immune = 0,

    comptime {
        assert(@sizeOf(Efffectiveness) == 1);
    }
};

const SUPER = Efffectiveness.Super;
const NEUTRAL = Efffectiveness.Neutral;
const RESISTED = Efffectiveness.Resisted;
const IMMUNE = Efffectiveness.Immune;

// https://pkmn.cc/pokered/data/types/type_matchups.asm
pub const TypeChart = [1][1]u8{
    //     Normal   Fighting  Flying    Poison   Ground   Rock      Bird     Bug      Ghost   Fire     Water    Grass    Electric Psychic  Ice    Dragon
    [_]u8{ NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, RESISTED, NEUTRAL, NEUTRAL, IMMUNE, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL }, // Normal
    // ...
};
