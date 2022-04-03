const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

pub const Player = enum(u1) {
    P1,
    P2,

    pub inline fn foe(self: Player) Player {
        return @intToEnum(Player, ~@enumToInt(self));
    }

    pub inline fn ident(self: Player, id: u8) u8 {
        assert(id > 0 and id <= 6);
        return (@as(u8, @enumToInt(self)) << 3) | id;
    }
};

test "Player" {
    try expectEqual(Player.P2, Player.P1.foe());
    try expectEqual(@as(u8, 0b0001), Player.P1.ident(1));
    try expectEqual(@as(u8, 0b1101), Player.P2.ident(5));
}

pub const Choice = packed struct {
    type: Choice.Type = .Pass,
    _: u2 = 0,
    data: u4 = 0,

    pub const Type = enum(u2) {
        Pass,
        Move,
        Switch,
    };

    comptime {
        assert(@sizeOf(Choice) == 1);
    }
};

test "Choice" {
    const p1: Choice = .{ .type = .Move, .data = 4 };
    const p2: Choice = .{ .type = .Switch, .data = 5 };
    try expectEqual(5, p2.data);
    try expectEqual(Choice.Type.Move, p1.type);
    try expectEqual(0b0100_0001, @bitCast(u8, p1));
    try expectEqual(0b0101_0010, @bitCast(u8, p2));
}

pub const Result = packed struct {
    type: Result.Type = .None,
    p1: Choice.Type = .Pass,
    p2: Choice.Type = .Pass,

    pub const Type = enum(u4) {
        None,
        Win,
        Lose,
        Tie,
        Error, // Desync, EBC, etc.
    };

    pub const Tie: Result = .{ .type = .Tie };
    pub const Win: Result = .{ .type = .Win };
    pub const Lose: Result = .{ .type = .Lose };
    pub const Error: Result = .{ .type = .Error };
    pub const Default: Result = .{ .p1 = .Move, .p2 = .Move };

    comptime {
        assert(@sizeOf(Result) == 1);
    }
};

test "Result" {
    try expectEqual(0b0101_0000, @bitCast(u8, Result.Default));
    try expectEqual(0b1000_0000, @bitCast(u8, Result{ .p2 = .Switch }));
}
