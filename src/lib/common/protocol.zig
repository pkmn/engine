const std = @import("std");
const build_options = @import("build_options");

const expectEqualSlices = std.testing.expectEqualSlices;

const trace = build_options.trace;

pub fn expectLog(expected: []const u8, actual: []const u8) !void {
    if (trace) try expectEqualSlices(u8, expected, actual);
}

pub const ArgType = enum(u8) {
    None,

    // Special
    LastStill,
    LastMiss,

    // Gen 1
    Move,
    Switch,
    Cant,
    Faint,
    Turn,
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
    Block,
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
    None,

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
    Trapped,
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

pub const Move = enum(u8) {
    None,
    Recharge,
    From,
};

pub const Cant = enum(u8) {
    None,

    Sleep,
    Freeze,
    Paralysis,
    Trapped,
    Flinch,
    Disable,
    Recharging,
    PP,
};

pub const Heal = enum(u8) {
    None,
    Silent,
    Drain,
};

pub const Damage = enum(u8) {
    None,

    Poison,
    Burn,
    Confusion,
    PoisonOf,
    BurnOf,
    RecoilOf,
    LeechSeedOf,
};

const Status = enum(u8) {
    None,
    Silent,
    From,
};

const CureStatus = enum(u8) {
    None,
    Silent,
};

const Boost = enum(u8) {
    None,

    Rage,
    Attack,
    Defense,
    Speed,
    Special,
    Accuracy,
    Evasion,
    SpecialAttack,
    SpecialDefense,
};

pub const Fail = enum(u8) {
    None,

    Sleep,
    Poison,
    Burn,
    Freeze,
    Paralysis,
    Toxic,
    Substitute,
    Weak,
};

pub const Activate = enum(u8) {
    None,

    Confusion,
    Bide,
    Haze,
    Struggle,
    Substitute,
};

pub const Start = enum(u8) {
    None,

    Bide,
    Confusion,
    ConfusionSilent,
    FocusEnergy,
    LeechSeed,
    LightScreen,
    Mist,
    Reflect,
    Substitute,

    TypeChange,

    Disable,
    Mimic,
};

// BUG: PS Haze has silent bide,substitute,parspeeddrop,brnattackdrop
pub const End = enum(u8) {
    None,

    Disable,
    Confusion,
    Bide,
    Substitute,

    // Silent
    DisableSilent,
    ConfusionSilent,

    Charging,
    Conversion,
    DefenseCurl,
    Dig,
    Fly,
    FocusEnergy,
    LeechSeed,
    LightScreen,
    Locked,
    Minimize,
    Mist,
    Rage,
    RazorWind,
    Reflect,
    SkullBash,
    SkyAttack,
    SolarBeam,
};

pub const Immune = enum(u8) {
    None,
    OHKO,
};

// test {
//     const print = std.debug.print;
//     const types = .{ArgType, KWArgType, Move, Cant, Heal, Damage, Status, CureStatus, Boost, Fail, Activate, Start, End, Immune};
//     inline for (types) |T| {
//         print("\n## {}\n\n", .{T});
//         print("<details><summary>Data</summary>\n\nRaw|Data|\n|--|--|\n", .{});
//         inline for (@typeInfo(T).Enum.fields) |field| {
//             print("|0x{X:0>2}|{s}|\n", .{field.value, field.name});
//         }
//         print("</details>\n", .{});
//     }
// }
