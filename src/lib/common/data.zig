const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

/// Representation of one of the battle's participants.
pub const Player = enum(u1) {
    P1,
    P2,

    /// Returns a player's opponent.
    pub inline fn foe(self: Player) Player {
        return @enumFromInt(~@intFromEnum(self));
    }

    /// Return's an identifier for the player's Pokémon at the one-indexed `id`.
    pub inline fn ident(self: Player, id: u3) ID {
        assert(id > 0 and id <= 6);
        return .{ .id = id, .player = self };
    }
};

test Player {
    try expectEqual(Player.P2, Player.P1.foe());
    try expectEqual(@as(u8, 0b0001), @as(u8, @bitCast(Player.P1.ident(1))));
    try expectEqual(@as(u8, 0b1101), @as(u8, @bitCast(Player.P2.ident(5))));
}

/// An identifier for a specific Pokémon in battle.
pub const ID = packed struct(u8) {
    /// The one-indexed team slot of the Pokémon
    id: u3 = 0,
    /// The Pokémon's trainer.
    player: Player = .P1,
    _: u4 = 0,

    /// Converts the identifier into a number.
    pub inline fn int(self: ID) u4 {
        return @intCast(@as(u8, @bitCast(self)));
    }

    /// Decodes the identifier from a number.
    pub inline fn from(id: u4) ID {
        return @bitCast(@as(u8, id));
    }
};

test ID {
    try expectEqual(@as(u8, 0b0001), @as(u8, @bitCast(ID{ .player = .P1, .id = 1 })));
    try expectEqual(@as(u8, 0b1101), @as(u8, @bitCast(ID{ .player = .P2, .id = 5 })));
    const id: ID = .{ .player = .P2, .id = 4 };
    try expectEqual(id, ID.from(id.int()));
}

/// A choice made by a player during battle.
pub const Choice = packed struct(u8) {
    /// The choice type.
    type: Choice.Type = .Pass,
    /// The choice data:
    ///
    ///  - 0 for 'pass'
    ///  - 0-4 for 'move'
    ///  - 2-6 for 'switch'
    data: u6 = 0,

    /// All valid choice types.
    pub const Type = enum(u2) {
        Pass,
        Move,
        Switch,
    };
};

test Choice {
    const p1: Choice = .{ .type = .Move, .data = 4 };
    const p2: Choice = .{ .type = .Switch, .data = 5 };
    try expectEqual(5, p2.data);
    try expectEqual(Choice.Type.Move, p1.type);
    try expectEqual(0b0001_0001, @as(u8, @bitCast(p1)));
    try expectEqual(0b0001_0110, @as(u8, @bitCast(p2)));
}

/// The result of the battle - all results other than 'None' should be considered terminal.
pub const Result = packed struct(u8) {
    /// The type of result from the perspective of Player 1.
    /// `Error` is not possible when in Pokémon Showdown compatibility mode.
    type: Result.Type = .None,
    /// The choice type of the result for Player 1.
    p1: Choice.Type = .Pass,
    /// The choice type of the result for Player 2.
    p2: Choice.Type = .Pass,

    /// All valid result types.
    pub const Type = enum(u4) {
        None,
        Win,
        Lose,
        Tie,
        Error, // Desync, EBC, etc.
    };

    /// The Tie result.
    pub const Tie: Result = .{ .type = .Tie };
    /// The Win result.
    pub const Win: Result = .{ .type = .Win };
    /// The Lost result.
    pub const Lose: Result = .{ .type = .Lose };
    /// The Error result.
    pub const Error: Result = .{ .type = .Error };
    /// The default result.
    pub const Default: Result = .{ .p1 = .Move, .p2 = .Move };
};

test Result {
    try expectEqual(0b0101_0000, @as(u8, @bitCast(Result.Default)));
    try expectEqual(0b1000_0000, @as(u8, @bitCast(Result{ .p2 = .Switch })));
}
