const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const types = @import("data/types.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");

pub const Stat = enum {
    HP,
    atk,
    def,
    spe,
    spc,

    comptime {
        assert(@sizeOf(Stat) == 1);
    }
};

// https://pkmn.cc/pokered/constants/battle_constants.asm#L5-L12
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

// https://pkmn.cc/pokered/constants/battle_constants.asm#L14-L23
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

// https://pkmn.cc/pokered/data/moves/moves.asm
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
    const move = Moves.get(Moves.Pound);
    try expectEqual(@as(u8, 35), move.pp);
}

pub const Species = species.Species;

// https://pkmn.cc/bulba/Pokémon_species_data_structure_(Generation_I)
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
    try expectEqual(@as(u8, 100), Species.get(Species.Mew).stats.def);
}

pub const Type = types.Type;
pub const Efffectiveness = types.Efffectiveness;
pub const TypeChart = types.TypeChart;

test "Types" {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Efffectiveness.Super));
}
