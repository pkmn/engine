const std = @import("std");
const data = @import("../data.zig");

const assert = std.debug.assert;

const Specie = data.Specie;
const Stats = data.Stats;
const Type = data.Type;

// https://pkmn.cc/pokered/constants/pokedex_constants.asm
pub const Species = enum(u8) {
    None,
    Bulbasaur,
    Ivysaur,
    // ...
    Mew,

    comptime {
        assert(@sizeOf(Species) == 1);
    }

     pub inline fn get(id: Species) *const Specie {
        assert(id != .None);
        return &SPECIES[@enumToInt(id) - 1];
    }
};

// https://pkmn.cc/pokered/data/pokemon/base_stats
const SPECIES = [_]Specie{
    Specie{
        .id = Species.Bulbasaur,
        .stats = Stats(u8){
            .hp = 45,
            .atk = 49,
            .def = 49,
            .spe = 45,
            .spc = 65,
        },
        .types = [_]Type{ Type.Grass, Type.Poison },
    },
    Specie{
        .id = Species.Ivysaur,
        .stats = Stats(u8){
            .hp = 60,
            .atk = 62,
            .def = 63,
            .spe = 60,
            .spc = 80,
        },
        .types = [_]Type{ Type.Grass, Type.Poison },
    },
    // ...
    Specie{
        .id = Species.Mew,
        .stats = Stats(u8){
            .hp = 100,
            .atk = 100,
            .def = 100,
            .spe = 100,
            .spc = 100,
        },
        .types = [_]Type{ Type.Psychic, Type.Psychic },
    },
};
