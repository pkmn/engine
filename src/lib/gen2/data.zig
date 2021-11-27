const std = @import("std");

const rng = @import("../common/rng.zig");
const gen1 = @import("../gen1/data.zig");

const items = @import("data/items.zig");
const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const Battle = packed struct {
    rng: rng.Gen12,
    // weather
    // weather duration

    // wWhichMonFaintedFirst:: db
};

const Field = packed struct {
    weather: Weather,
};

const Weather = enum(u2) {
    None,
    Rain,
    Sun,
    Sandstorm,
};

const Side = packed struct {
    condition: SideCondition,
    // wPlayerDamageTaken:: dw
    // wPlayerTurnsTaken:: db???
    // wLastPlayerCounterMove

    // wPlayerSafeguardCount:: db
    // wPlayerLightScreenCount:: db
    // wPlayerReflectCount:: db
    // wPlayerIsSwitching:: db
};

const SideCondition = packed struct {
    Spikes: bool = false,
    Safeguard: bool = false,
    LightScreen: bool = false,
    Reflect: bool = false,
};

const ActivePokemon = packed struct {
    // TODO item Items
    // TODO extra 2*Stats+1 Boosts byte = 24
    // TODO happiness u8
    // TODO volatile size change + 8
    // = total 48, 16 padding left

};

// TODO
const Pokemon = packed struct {};

pub const Gender = enum(u1) {
    Male,
    Female,
};

const IVs = packed struct {
    gender: Gender,
    power: u7,
    type: Type,

    pub fn init(g: Gender, p: u7, t: Type) IVs {
        assert(p >= 31 and p <= 70);
        assert(t != .Normal and t != .@"???");
        return IVs{ .gender = g, .power = p, .type = t };
    }

    comptime {
        assert(@sizeOf(IVs) == 2);
    }
};

const MoveSlot = packed struct {
    id: Moves = .None,
    pp: u6 = 0,
    pp_ups: u2 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }

    pub fn init(id: Moves) MoveSlot {
        if (id == .None) return MoveSlot{};
        const move = Moves.get(id);
        return MoveSlot{
            .id = id,
            .pp = move.pp,
            .pp_ups = 3,
        };
    }

    pub fn maxpp(self: *const MoveSlot) u8 {
        const pp = Moves.get(self.id).pp;
        return self.pp_ups * @as(u8, @maximum(pp, 7)) + (@as(u8, pp) * 5);
    }
};

test "MoveSlot" {
    const ms = MoveSlot.init(.Pound);
    try expectEqual(@as(u6, 35 / 5), ms.pp);
    try expectEqual(@as(u8, 56), ms.maxpp());
    try expectEqual(Moves.Pound, ms.id);
    try expectEqual(@as(u16, 0), @bitCast(u16, MoveSlot.init(.None)));
}

pub const Status = gen1.Status;

// TODO
const Volatile = packed struct {
    Bide: bool = false,
    Locked: bool = false,
    // MultiHit
    Flinch: bool = false,
    Charging: bool = false,
    // PartialTrap
    Underground: bool = false,
    Flying: bool = false,
    Confusion: bool = false,
    Mist: bool = false,
    FocusEnergy: bool = false,
    Substitute: bool = false,
    Recharging: bool = false,
    Rage: bool = false,
    LeechSeed: bool = false,
    Toxic: bool = false,
    Transform: bool = false,

    Nightmare: bool = false,
    Cure: bool = false,
    Protect: bool = false,
    Foresight: bool = false,
    PerishSong: bool = false,
    Endure: bool = false,
    Rollout: bool = false,
    Attract: bool = false,
    DefenseCurl: bool = false,
    Encore: bool = false,
    LockOn: bool = false,
    DestinyBond: bool = false,
    BeatUp: bool = false,

    _pad: u4 = 0,

    data: VolatileData,

    // comptime {
    //     assert(@sizeOf(Volatile) == 4);
    // }
};

const VolatileData = packed struct {
    // bide: u16 = 0,
    // substitute: u8 = 0,

    confusion: u4 = 0,
    toxic: u4 = 0,
    disabled: packed struct {
        move: u4 = .None,
        duration: u4 = 0,
    },
    encore: u4 = 0,
    perish_song: u4 = 0,
    rollout: u4 = 0,
    fury_cutter: u4 = 0,
    protect: u4 = 0,
    future_sight: u4 = 0,
    wrap: u4 = 0,
    _: u4 = 0, // TODO 7 bytes
    rage: u8 = 0,

    // wPlayerCharging:: db
    // wPlayerJustGotFrozen:: db
};

pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spa: T = 0,
        spd: T = 0,
    };
}

test "Stats" {
    try expectEqual(12, @sizeOf(Stats(u16)));
    const stats = Stats(u4){ .spd = 2, .spe = 3 };
    try expectEqual(2, stats.spd);
    try expectEqual(0, stats.def);
}

pub fn Boosts(comptime T: type) type {
    return packed struct {
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spa: T = 0,
        spd: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };
}

test "Boosts" {
    try expectEqual(3 * 8 + 4, @bitSizeOf(Boosts(i4)));
    const boosts = Boosts(i4){ .spd = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spd);
}

pub const Items = items.Items;

test "Items" {
    try expect(Items.boost(.MasterBall) == null);
    try expectEqual(Type.Normal, Items.boost(.PinkBow).?);
    try expectEqual(Type.Normal, Items.boost(.PolkadotBow).?);
    try expectEqual(Type.Dark, Items.boost(.BlackGlasses).?);

    try expect(!Items.mail(.TM50));
    try expect(Items.mail(.FlowerMail));
    try expect(Items.mail(.MirageMail));

    try expect(!Items.berry(.MirageMail));
    try expect(Items.berry(.PSNCureBerry));
    try expect(Items.berry(.GoldBerry));
}

pub const Moves = moves.Moves;
pub const Move = packed struct {
    bp: u8,
    accuracy: u8,
    type: Type,
    pp: u4, // pp / 5
    chance: u4 = 0, // chance / 10
    // TODO effect and parameter?

    comptime {
        assert(@sizeOf(Move) == 4);
    }
};

test "Moves" {
    try expectEqual(251, @enumToInt(Moves.BeatUp));
    const move = Moves.get(.DynamicPunch);
    try expectEqual(@as(u8, 50), move.accuracy);
    try expectEqual(@as(u8, 5), move.pp * 5);
}

pub const Species = species.Species;
// @test-only
pub const Specie = struct {
    stats: Stats(u8),
    types: Types,
    ratio: u8,
};

test "Species" {
    try expectEqual(152, @enumToInt(Species.Chikorita));
    try expectEqual(@as(u8, 100), Species.get(.Celebi).stats.spd);
}

pub const Type = types.Type;
pub const Types = types.Types;
pub const Effectiveness = gen1.Effectiveness;

test "Types" {
    try expectEqual(13, @enumToInt(Type.Electric));
    try expectEqual(Effectiveness.Super, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Effectiveness.Super, Type.effectiveness(.Water, .Fire));
    try expectEqual(Effectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Effectiveness.Neutral, Type.effectiveness(.Normal, .Grass));
    try expectEqual(Effectiveness.Immune, Type.effectiveness(.Poison, .Steel));
}

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
