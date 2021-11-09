pub const Stat = enum {
  HP,
  Attack,
  Defense,
  Speed,
  Special,
};

// https://github.com/pret/pokered/blob/master/constants/battle_constants.asm#L5-L12
pub fn Stats(comptime T: type) type {
  return struct {
    hp: T,
    atk: T,
    def: T,
    spe: T,
    spc: T,
  };
}

pub const Boost = enum {
  Attack,
  Defense,
  Speed,
  Special,
  Accuracy,
  Evasion,
};

// https://github.com/pret/pokered/blob/master/constants/battle_constants.asm#L14-L23
pub fn Boosts(comptime T: type) type {
  return struct {
    atk: T,
    def: T,
    spe: T,
    spc: T,
    accuracy: T,
    evasion: T,
  };
}