//! Fundamental Pokémon data types required for battle simulation.
//! Data not strictly required for battles is elided at this layer.
//! **NOTE**: code in `data/` is generated and re-exported below.

const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const types = @import("data/types.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");

/// The name of each stat (cf. Pokémon Showdown's `StatName`).
///
/// *See:* https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L54-L67
///
pub const Stat = enum(u3) {
    hp,
    atk,
    def,
    spe,
    spa,
    spd,

    comptime {
        assert(@bitSizeOf(Stat) == 3);
    }
};

/// A structure for storing information for each `Stat` (cf. Pokémon Showdown's `StatTable`).
pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spa: T = 0,
        spd: T = 0,
    };

    comptime {
        assert(@bitSizeOf(Stats(u8)) == 6 * 8);
    }
}

test "Stats" {
    const stats = Stats(u4){ .spd = 2, .spe = 3 };
    try expectEqual(2, stats.spd);
    try expectEqual(0, stats.def);
}

/// The name of each boost/mod (cf. Pokémon Showdown's `BoostName`).
///
/// *See:* https://pkmn.cc/pokecrystal/constants/battle_constants.asm#L30-L39
///
pub const Boost = enum(u3) {
    atk,
    def,
    spe,
    spa,
    spd,
    accuracy,
    evasion,

    comptime {
        assert(@bitSizeOf(Boost) == 3);
    }
};

/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6...6.
pub fn Boosts(comptime T: type) type {
    return packed struct {
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spa: T = 0,
        spd: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };

    comptime {
        assert(@bitSizeOf(Boosts(i4)) == 3 * 8 + 4);
    }
}

test "Boosts" {
    const boosts = Boosts(i4){ .spd = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spd);
}

pub const Moves = moves.Moves;

/// *See:* https://pkmn.cc/pokecrystal/data/moves/moves.asm
pub const Move = packed struct {
    bp: u8,
    type: Type,
    accuracy: u8,
    pp: u4, // pp / 5
    chance: u4, //

    comptime {
        assert(@bitSizeOf(Move) == 4 * 8);
    }
};

test "Moves" {
    try expectEqual(2, @enumToInt(Moves.KarateChop));
    const move = Moves.get(.Pound);
    try expectEqual(@as(u8, 35), move.pp);
}
