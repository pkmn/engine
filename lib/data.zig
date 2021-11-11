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
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L5-L12
///
pub const Stat = enum {
    hp,
    atk,
    def,
    spe,
    spc,

    comptime {
        assert(@sizeOf(Stat) == 1);
    }
};

/// A structure for storing information for each `Stat` (cf. Pokémon Showdown's `StatTable`).
pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
    };
}

test "Stats" {
    try expectEqual(5, @sizeOf(Stats(u8)));
    const stats = Stats(u4){ .atk = 2, .spe = 3 };
    try expectEqual(2, stats.atk);
    try expectEqual(0, stats.def);
}

/// The name of each boost/mod (cf. Pokémon Showdown's `BoostName`).
///
/// *See:* https://pkmn.cc/pokered/constants/battle_constants.asm#L14-L23
///
pub const Boost = enum {
    atk,
    def,
    spe,
    spc,
    accuracy,
    evasion,

    comptime {
        assert(@sizeOf(Boost) == 1);
    }
};

/// A structure for storing information for each `Boost` (cf. Pokémon Showdown's `BoostTable`).
/// **NOTE**: `Boost(i4)` should likely always be used, as boosts should always range from -6...6.
pub fn Boosts(comptime T: type) type {
    return packed struct {
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };
}

test "Boosts" {
    try expectEqual(3, @sizeOf(Boosts(i4)));
    const boosts = Boosts(i4){ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

pub const Moves = moves.Moves;

/// *See:* https://pkmn.cc/pokered/data/moves/moves.asm
pub const Move = struct {
    id: Moves,
    bp: u8,
    type: Type,
    accuracy: u8,
    pp: u6,

    comptime {
        assert(@sizeOf(Move) == 5);
    }
};

test "Moves" {
    try expectEqual(2, @enumToInt(Moves.KarateChop));
    const move = Moves.get(.Pound);
    try expectEqual(@as(u8, 35), move.pp);
}

pub const Species = species.Species;

/// *See:* https://pkmn.cc/bulba/Pok%c3%a9mon_species_data_structure_%28Generation_I%29
pub const Specie = struct {
    id: Species,
    stats: Stats(u8),
    types: [2]Type,

    pub inline fn num(self: *const Specie) u8 {
        return self.id;
    }

    comptime {
        assert(@sizeOf(Specie) == 8);
    }
};

test "Species" {
    try expectEqual(2, @enumToInt(Species.Ivysaur));
    try expectEqual(@as(u8, 100), Species.get(.Mew).stats.def);
}

pub const Type = types.Type;
pub const Efffectiveness = types.Efffectiveness;

test "Types" {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Efffectiveness.Super));
    try expectEqual(Efffectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Efffectiveness.Super, Type.effectiveness(.Water, .Fire));
    try expectEqual(Efffectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Efffectiveness.Neutral, Type.effectiveness(.Normal, .Grass));
}
