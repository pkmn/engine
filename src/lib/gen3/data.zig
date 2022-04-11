const std = @import("std");

const rng = @import("../common/rng.zig");

const gen1 = @import("../gen1/data.zig");
const gen2 = @import("../gen2/data.zig");

// const items = @import("data/items.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

pub const GameType = enum {
    Singles,
    Doubles,
};

pub const Random = rng.Random(3);

pub fn Battle(comptime RNG: anytype, comptime game_type: GameType) type {
    return extern struct {
        sides: [2]Side(game_type),
        rng: RNG,
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
    const N = @enumToInt(game_type) + 1;
    return extern struct {
        pokemon: [N]ActivePokemon,
        team: [6]Pokemon,
        active: [N]u8,
        // TODO
    };
}

pub const ActivePokemon = extern struct {};

pub const Pokemon = extern struct {};

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

pub const MoveTarget = packed struct {
    Depends: bool = false,
    Random: bool = false,
    Both: bool = false,
    User: bool = false,
    FoesAndAlly: bool = false,
    OpponentsField: bool = false,
    _: u2 = 0,
};

const a = MoveTarget{ .Depends = true };
const b = MoveFlags{ .Snatch = true, .Contact = true };

pub const MoveFlags = packed struct {
    Contact: bool = false, // contact
    Protect: bool = false, // protect
    MagicCoat: bool = false, // reflectable
    Snatch: bool = false, // snatch
    MirrorMove: bool = false, // mirror
    KingsRock: bool = false, // TODO
    _: u2 = 0,
};

pub const Move = moves.Move;

const MoveSlot = extern struct {
    id: Move = .None,
    pp: u8 = 0,
    max_pp: u8 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u32));
    }
};

// test "Moves" {
//     try expectEqual(251, @enumToInt(Move.BeatUp));
//     const move = Move.get(.LockOn);
//     try expectEqual(@as(u8, 1), move.pp);
// }

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
