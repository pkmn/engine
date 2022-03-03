const std = @import("std");
const build_options = @import("build_options");

const expectEqualSlices = std.testing.expectEqualSlices;

const trace = build_options.trace;

pub fn expectTrace(expected: []const u8, actual: []const u8) !void {
    if (trace) try expectEqualSlices(u8, expected, actual);
}

pub const ArgType = enum(u8) {
    // Gen 1
    Move,
    Switch,
    Cant,
    Faint,
    Turn,
    Upkeep,
    Win,
    Tie,
    Damage,
    Heal,
    Status,
    CureStatus,
    Boost,
    Unboost,
    ClearAllBoost,
    Fail,
    Block,
    Miss,
    HitCount,
    Prepare,
    MustRecharge,
    Activate,
    FieldActivate,
    Start,
    End,
    OHKO,
    Crit,
    SuperEffective,
    Resisted,
    Immune,
    Transform,

    // Gen 2
    Drag,
    Item,
    EndItem,
    CureTeam,
    SetHP,
    SetBoost,
    CopyBoost,
    SideStart,
    SideEnd,
    SingleMove,
    SingleTurn,
    Weather,

    // Gen 3
    Ability,
    EndAbility,
    ClearNegativeBoost,
    FormeChange,
    NoTarget,

    // Gen 4
    SwapBoost,
    FieldStart,
    FieldEnd,
    DetailsChange,

    // Gen 5
    ClearPoke,
    Poke,
    TeamPreview,
    Center,
    Swap,
    Combine,
    Waiting,
    Replace,
    ClearBoost,

    // Gen 6
    Mega,
    Primal,
    InvertBoost,

    // Gen 7
    ZBroken,
    ZPower,
    Burst,
    ClearPositiveBoost,

    // Gen 8
    CanDynamax,
    SwapSideConditions,
};

pub const KWArgType = enum(u8) {
    // Gen 1
    From,
    Of,
    Damage,
    Silent,
    Message,
    Weak,
    OHKO,
    Miss,
    Still,

    // Gen 2
    Move,
    Name,
    Number,
    PartiallyTrapped,
    Upkeep,
    Block,

    // Gen 3
    Ability,
    Ability2,
    Consumed,
    Eat,
    Fatigue,
    Wisher,
    NoTarget,
    Spread,

    // Gen 4
    Weaken,
    Broken,

    // Gen 5
    Interrupt,
    Heavy,

    // Gen 6
    Fail,
    Forme,
    Item,

    // Gen 7
    ZEffect,
};

pub const Cant = enum(u8) {
    Sleep,
    Freeze,
    Paralysis,
    PartialTrap,
    Flinch,
    Disable,
    Recharging,
    PP,
};

pub const Activate = enum(u8) {
    Confusion,
    Bide,
};

pub const Start = enum(u8) {
    Confusion,
    Bide,
};

pub const End = enum(u8) {
    Disable,
    Confusion,
    Bide,
};
