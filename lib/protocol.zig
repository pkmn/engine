const std = @import("std");
const mem = std.mem;

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

pub const Protocol = union(ArgType) {
    Upkeep: Upkeep,
    Turn: Turn,
    Win: Win,
    Tie: Tie,
    Timestamp: Timestamp,
    Faint: Faint,
    NoTarget: NoTarget,
    Crit: Crit,
    SuperEffective: SuperEffective,
    Resisted: Resisted,
    Immune: Immune,
    Transform: Transform,
    Primal: Primal,
    ZPower: ZPower,
    ZBroken: ZBroken,
    Center: Center,
    Combine: Combine,
    Waiting: Waiting,
    MustRecharge: MustRecharge,
    HitCount: HitCount,
    OHKO: OHKO,
    CanDynamax: CanDynamax,

    pub fn log(p: *const Protocol, buf: ?*std.ArrayList(u8)) !void {
        if (buf) |b| try Protocol.write(p, b);
    }

    fn write(p: *const Protocol, buf: *std.ArrayList(u8)) !void {
        try buf.append(@enumToInt(@as(ArgType, p.*)));
        switch (p.*) {
            .Upkeep => undefined,
            .Turn => |*arg| try Protocol.writeBytes(u16, arg.val, buf),
            .Win => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Tie => undefined,
            .Timestamp => |*arg| try Protocol.writeBytes(u64, arg.val, buf),
            .Faint => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .NoTarget => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Crit => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .SuperEffective => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Resisted => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Immune => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Transform => |*arg| {
                try Protocol.writeBytes(u8, arg.val1, buf);
                try Protocol.writeBytes(u8, arg.val2, buf);
            },
            .Primal => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .ZPower => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .ZBroken => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .Center => undefined,
            .Combine => undefined,
            .Waiting => |*arg| {
                try Protocol.writeBytes(u8, arg.val1, buf);
                try Protocol.writeBytes(u8, arg.val2, buf);
            },
            .MustRecharge => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
            .HitCount => |*arg| {
                try Protocol.writeBytes(u8, arg.val1, buf);
                try Protocol.writeBytes(u8, arg.val2, buf);
            },
            .OHKO => undefined,
            .CanDynamax => |*arg| try Protocol.writeBytes(u8, arg.val, buf),
        }
    }

    fn writeBytes(comptime T: type, val: T, buf: *std.ArrayList(u8)) !void {
        const bits = @typeInfo(T).Int.bits;
        if (bits == 0 or bits % 8 != 0) @compileError("must be divisible by 8");

        comptime var i = bits >> 4;
        inline while (i >= 0) : (i -= 1) {
            try buf.append(@intCast(u8, (val >> (i * 8)) & 0xFF));
        }
    }
};

pub const ArgType = enum(u8) {
    Upkeep,
    Turn,
    Win,
    Tie,
    Timestamp,
    // Move,
    // Switch,
    // Drag,
    // DetailsChange,
    // Replace,
    // Swap,
    // Cant,
    Faint,
    // FormeChange,
    // Fail,
    // Block,
    NoTarget,
    // Miss,
    // Damage,
    // Heal,
    // SetHP,
    // Status,
    // CureStatus,
    // CureTeam,
    // Boost,
    // Unboost,
    // SetBoot,
    // SwapBoost,
    // InvertBoost,
    // ClearBoost,
    // ClearAllBoost,
    // ClearPositiveBoost,
    // ClearNegativeBoost,
    // Weather,
    // FieldStart,
    // FieldEnd,
    // SideStart,
    // SideEnd,
    // SwapSideConditions,
    // Start,
    // End,
    Crit,
    SuperEffective,
    Resisted,
    Immune,
    // Item,
    // EndItem,
    // Ability,
    // EndAbility,
    Transform,
    // Mega,
    Primal,
    // Burst,
    ZPower,
    ZBroken,
    // Activate,
    Center,
    Combine,
    Waiting,
    // Prepare,
    MustRecharge,
    HitCount,
    // SingleMove,
    // SingleTurn,
    OHKO,
    CanDynamax,
};

pub const KWArgType = enum(u8) {
    Ability,
    Ability2,
    Block,
    Broken,
    Consumed,
    Damaged,
    Eat,
    Fail,
    Fatigue,
    Forme,
    From,
    Heavy,
    Item,
    Miss,
    Move,
    Message,
    Name,
    NoTarget,
    Number,
    Of,
    OHKO,
    Silent,
    Spread,
    Still,
    Thaw,
    Upkeep,
    Weak,
    Weaken,
    Wisher,
    ZEffect,
};

fn Arg0() type {
    return packed struct {
        const Self = @This();
        pub inline fn init() Self {
            return Self{};
        }
    };
}

fn Arg1(comptime T: type) type {
    return packed struct {
        const Self = @This();

        val: T,

        pub inline fn init(val: T) Self {
            return Self{ .val = val };
        }
    };
}

fn Arg2(comptime T1: type, comptime T2: type) type {
    return packed struct {
        const Self = @This();

        val1: T1,
        val2: T2,

        pub inline fn init(val1: T1, val2: T2) Self {
            return Self{ .val1 = val1, .val2 = val2 };
        }
    };
}

const Player = u8;
const PokemonIdent = u8;

pub const Upkeep = Arg0();
pub const Turn = Arg1(u16);
pub const Win = Arg1(Player);
pub const Tie = Arg0();
pub const Timestamp = Arg1(u64);
pub const Faint = Arg1(PokemonIdent);
pub const NoTarget = Arg1(PokemonIdent);
pub const Crit = Arg1(PokemonIdent);
pub const SuperEffective = Arg1(PokemonIdent);
pub const Resisted = Arg1(PokemonIdent);
pub const Immune = Arg1(PokemonIdent);
pub const Transform = Arg2(PokemonIdent, PokemonIdent);
// pub const Mega = Arg3(PokemonIdent, Species, Items);
pub const Primal = Arg1(PokemonIdent);
// pub const Burst = Arg3(PokemonIdent, Species, Items);
pub const ZPower = Arg1(PokemonIdent);
pub const ZBroken = Arg1(PokemonIdent);
pub const Center = Arg0();
pub const Combine = Arg0();
pub const Waiting = Arg2(PokemonIdent, PokemonIdent);
pub const MustRecharge = Arg1(PokemonIdent);
pub const HitCount = Arg2(PokemonIdent, u8);
pub const OHKO = Arg0();
pub const CanDynamax = Arg1(Player);

test "Protocol" {
    const p = Protocol{ .Turn = Turn.init(5) };
    switch (p) {
        .Turn => |*arg| try expectEqual(@as(u16, 5), arg.val),
        else => unreachable,
    }

    var trace = std.ArrayList(u8).init(std.testing.allocator);
    defer trace.deinit();

    try Protocol.log(&p, &trace);
    try Protocol.log(&Protocol{ .Upkeep = Upkeep.init() }, &trace);
    try Protocol.log(&Protocol{ .Transform = Transform.init(3, 4) }, &trace);
    try expectEqualSlices(u8, trace.items, &[_]u8{ 0x01, 0x00, 0x05, 0x00, 0x0B, 0x03, 0x04 });
}
