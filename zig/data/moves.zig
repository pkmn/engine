const TypeID = @import("types").TypeID;

/// https://github.com/pret/pokered/blob/master/constants/move_constants.asm
pub const MoveID = enum {
  None,
  Pound,
  KarateChop,
  // ...
  Struggle,
};

// https://github.com/pret/pokered/blob/master/data/moves/moves.asm
pub const Move = struct {
  id: MoveID,
  bp: u8,
  type: TypeID,
  accuracy: u8,
  pp: u8,
};

pub const Moves = struct {
  pub fn get(id: MoveID) *Move {
    return &MOVES[id - 1];
  }
};

// https://github.com/pret/pokered/blob/master/data/moves/moves.asm
const MOVES = [_]Move{
  Move {
    .id = MoveID.Pound,
    .bp = 40,
    .type = TypeID.Normal,
    .accuracy = 100,
    .pp = 35,
  },
  Move {
    .id = MoveID.KarateChop,
    .bp = 50,
    .type = TypeID.Normal,
    .accuracy = 100,
    .pp = 25,
  },
  // ...
  Move {
    .id = MoveID.Struggle,
    .bp = 50,
    .type = TypeID.Normal,
    .accuracy = 100,
    .pp = 10,
  },
};