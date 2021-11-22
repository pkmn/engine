const std = @import("std");

const gen1 = @import("../gen1/data.zig");
const gen2 = @import("../gen2/data.zig");

// const items = @import("data/items.zig");
// const moves = @import("data/moves.zig");
const species = @import("data/species.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

pub const GameType = enum {
    Singles,
    Doubles,
};

pub fn Battle(comptime game_type: GameType) type {
    return packed struct {
        sides: [2]Side,
        seed: u32,
        turn: u8 = 0,

        pub fn p1(self: *Battle) *Side {
            return &self.sides[0];
        }

        pub fn p2(self: *Battle) *Side {
            return &self.sides[1];
        }
    };
}

pub fn Side(comptime game_type: GameType) type {
    const N = @enumToInt(game_type);
    return packed struct {
        pokemon: [N]ActivePokemon,
        team: [6]Pokemon,
        active: [N]u8,
        // TODO
    };
}

// pub const Items = items.Items;

// test "Items" {
//     try expect(Items.boost(.MasterBall) == null);
//     try expectEqual(Type.Normal, Items.boost(.PinkBow).?);
//     try expectEqual(Type.Normal, Items.boost(.PolkadotBow).?);
//     try expectEqual(Type.Dark, Items.boost(.BlackGlasses).?);

//     try expect(!Items.berry(.TM50));
//     try expect(Items.berry(.PSNCureBerry));
//     try expect(Items.berry(.GoldBerry));
// }

pub const MoveTarget = enum(u8) { // u6 / u4
    Selected = 0, // normal
    Depends = (1 << 0), // scripted
    // UserOrSelected = (1 << 1),
    Random = (1 << 2), // randomNormal
    Both = (1 << 3), // allAdjacentFoes
    User = (1 << 4), // self
    FoesAndAlly = (1 << 5), // allAdjacent
    OpponentsField = (1 << 6), // foeSide
};

pub const Moves = moves.Moves;
pub const Move = packed struct {
    bp: u8,
    accuracy: u8,
    type: Type,
    pp: u4, // pp / 5
    chance: u4, // chance / 10
    target: MoveTarget,
    // FIXME flags

    comptime {
        assert(@sizeOf(Move) == 4);
    }
};

test "Moves" {
    try expectEqual(251, @enumToInt(Moves.BeatUp));
    const move = Moves.get(.LockOn);
    try expectEqual(@as(u8, 1), move.pp);
}

pub const Species = species.Species;

test "Species" {
    try expectEqual(386, @enumToInt(Species.Deoxys));
}

pub const Type = gen2.Type;
pub const Types = gen2.Types;
pub const Effectiveness = gen1.Effectiveness;

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
