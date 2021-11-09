const std = @import("std");
const data = @import("../data.zig");

const assert = std.debug.assert;

const Move = data.Move;
const Type = data.Type;

/// https://pkmn.cc/pokered/constants/move_constants.asm
pub const Moves = enum(u8) {
    None,
    Pound,
    KarateChop,
    // ...
    Struggle,

    comptime {
        assert(@sizeOf(Moves) == 1);
    }

    pub fn get(id: Moves) *const Move {
        assert(id != .None);
        return &MOVES[@enumToInt(id) - 1];
    }
};

// https://pkmn.cc/pokered/data/moves/moves.asm
const MOVES = [_]Move{
    Move{
        .id = Moves.Pound,
        .bp = 40,
        .type = Type.Normal,
        .accuracy = 100,
        .pp = 35,
    },
    Move{
        .id = Moves.KarateChop,
        .bp = 50,
        .type = Type.Normal,
        .accuracy = 100,
        .pp = 25,
    },
    // ...
    Move{
        .id = Moves.Struggle,
        .bp = 50,
        .type = Type.Normal,
        .accuracy = 100,
        .pp = 10,
    },
};

