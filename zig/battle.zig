const Side = @import("side").Side;
const Pokemon = @import("pokemon").Pokemon;

const Battle = struct {
  sides: [2]Side,
  seed: u8,
  turn: u8,

  pub inline fn init(seed: u8, p1: []?Pokemon, p2: []?Pokemon) Battle {
    return Battle {
      .sides = [_]Side{Side.init(p1), Side.init(p2)},
      .seed = seed,
      .turn = 0,
    };
  }

  pub inline fn p1(self: *Battle) *Side {
    return &self.sides[0];
  }

  pub inline fn p2(self: *Battle) *Side {
    return &self.sides[1];
  }
};