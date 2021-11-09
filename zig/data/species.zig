const Stats = @import("data").Stats;
const TypeID = @import("types").TypeID;

// https://github.com/pret/pokered/blob/master/constants/pokedex_constants.asm
pub const SpeciesID = enum {
  None,
  Bulbasaur,
  Ivysaur,
  // ...
  Mew,
};

// https://bulbapedia.bulbagarden.net/wiki/Pokémon_species_data_structure_(Generation_I)
pub const Specie = struct {
  id: SpeciesID,
  stats: Stats(u8),
  types: [2]TypeID,

  pub inline fn num(self: Specie) u8 {
    return self.id;
  }
};

pub const Species = struct {
  pub inline fn get(id: SpeciesID) *Specie {
    return &SPECIES[id - 1];
  }
};

// https://github.com/pret/pokered/tree/master/data/pokemon/base_stats
const SPECIES = [_]Specie {
  Specie {
    .id = SpeciesID.Bulbasaur,
    .stats = Stats(u8) {
      .hp = 45,
      .atk = 49,
      .def = 49,
      .spe = 45,
      .spc = 65,
    },
    .types = [_]TypeId{ TypeID.Grass, TypeID.Poison},
  },
  Specie {
    .id = SpeciesID.Ivysaur,
    .stats = Stats(u8) {
      .hp = 60,
      .atk = 62,
      .def = 63,
      .spe = 60,
      .spc = 80,
    },
    .types = [_]TypeId{ TypeID.Grass, TypeID.Poison},
  },
  // ...
  Specie {
    .id = SpeciesID.Mew,
    .stats = Stats(u8) {
      .hp = 100,
      .atk = 100,
      .def = 100,
      .spe = 100,
      .spc = 100,
    },
    .types = [_]TypeId{ TypeID.Psychic, TypeID.Psychic},
  },
};