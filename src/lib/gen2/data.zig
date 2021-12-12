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

const Battle = extern struct {
    turn: u16 = 0,
    rng: rng.Gen12,
    field: Field = .{},
    sides: [2]Side,

    comptime {
        assert(@sizeOf(Battle) == 432);
    }

    pub fn p1(self: *Battle) *Side {
        return &self.sides[0];
    }

    pub fn p2(self: *Battle) *Side {
        return &self.sides[1];
    }
};

const Field = packed struct {
    weather: Weather = .{},

    comptime {
        assert(@sizeOf(Field) == 1);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Field) == @sizeOf(Field) * 8);
    }
};

const Weathers = enum(u2) {
    None,
    Rain,
    Sun,
    Sandstorm,
};

const Weather = packed struct {
    id: Weathers = .None,
    _: u2 = 0,
    duration: u4 = 0,

    comptime {
        assert(@sizeOf(Weather) == 1);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Weather) == @sizeOf(Weather) * 8);
    }
};

const Side = extern struct {
    team: [6]Pokemon = [_]Pokemon{.{}} ** 6,
    pokemon: ActivePokemon = .{},
    conditions: SideConditions,
    active: u8 = 0,
    _: u8 = 0,

    comptime {
        assert(@sizeOf(Side) == 214);
    }

    pub fn get(self: *const Side, slot: u8) *Pokemon {
        assert(slot > 0 and slot < 7);
        return self.pokemon[slot - 1];
    }
};

// // BUG: ziglang/zig#2627
const SideConditions = packed struct {
    data: Data = .{},
    Spikes: bool = false,
    Safeguard: bool = false,
    LightScreen: bool = false,
    Reflect: bool = false,

    const Data = packed struct {
        safeguard: u4 = 0,
        light_screen: u4 = 0,
        reflect: u4 = 0,

        comptime {
            assert(@bitSizeOf(Data) == 12);
        }
    };

    comptime {
        assert(@sizeOf(SideConditions) == 2);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(SideConditions) == @sizeOf(SideConditions) * 8);
    }
};

const ActivePokemon = extern struct {
    volatiles: Volatile = .{},
    stats: Stats(u16) = .{},
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    boosts: Boosts(i4) = .{},
    hp: u16 = 0,
    types: Types = .{},
    level: u8 = 100,
    status: u8 = 0,
    species: Species = .None,
    item: Item = .None,
    // NOTE: IVs (Gender & Hidden Power) and Happiness are stored only in Pokemon

    // FIXME move to volatiles?
    // trapped: bool = false,
    // switching: bool = false,

    // FIXME store on Side or Volatiles.Data
    // last_move: Move = .None,

    comptime {
        assert(@sizeOf(ActivePokemon) == 48);
    }
};

const Pokemon = packed struct {
    stats: Stats(u10) = .{},
    position: u4 = 0,
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    hp: u16 = 0,
    status: u8 = 0,
    species: Species = .None,
    types: Types = .{},
    level: u8 = 100,
    item: Item = .None,
    ivs: IVs = .{},
    happiness: u8 = 255,

    comptime {
        assert(@sizeOf(Pokemon) == 27);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Pokemon) == @sizeOf(Pokemon) * 8);
    }
};

pub const Gender = enum(u1) {
    Male,
    Female,
};

const IVs = packed struct {
    gender: Gender = .Male,
    power: u7 = 70,
    type: Type = .Dark,

    pub fn init(g: Gender, p: u7, t: Type) IVs {
        assert(p >= 31 and p <= 70);
        assert(t != .Normal and t != .@"???");
        return IVs{ .gender = g, .power = p, .type = t };
    }

    comptime {
        assert(@sizeOf(IVs) == 2);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(IVs) == @sizeOf(IVs) * 8);
    }
};

const MoveSlot = packed struct {
    id: Move = .None,
    pp: u6 = 0,
    pp_ups: u2 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(MoveSlot) == @sizeOf(MoveSlot) * 8);
    }

    pub fn init(id: Move) MoveSlot {
        if (id == .None) return MoveSlot{};
        const move = Move.get(id);
        return MoveSlot{
            .id = id,
            .pp = move.pp,
            .pp_ups = 3,
        };
    }

    pub fn maxpp(self: *const MoveSlot) u8 {
        const pp = Move.get(self.id).pp;
        return self.pp_ups * @as(u8, @maximum(pp, 7)) + (@as(u8, pp) * 5);
    }
};

test "MoveSlot" {
    const ms = MoveSlot.init(.Pound);
    try expectEqual(@as(u6, 35 / 5), ms.pp);
    try expectEqual(@as(u8, 56), ms.maxpp());
    try expectEqual(Move.Pound, ms.id);
    try expectEqual(@as(u16, 0), @bitCast(u16, MoveSlot.init(.None)));
}

pub const Status = gen1.Status;

const Volatile = packed struct {
    data: Data,
    Bide: bool = false,
    Locked: bool = false,
    Flinch: bool = false,
    Charging: bool = false,
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
    _: u4 = 0,

    const Data = packed struct {
        future_sight: FutureSight = .{},
        bide: u16 = 0,
        disabled: Disabled = .{},
        rage: u8 = 0,
        substitute: u8 = 0,
        confusion: u4 = 0,
        encore: u4 = 0,
        fury_cutter: u4 = 0,
        perish_song: u4 = 0,
        protect: u4 = 0,
        rollout: u4 = 0,
        toxic: u4 = 0,
        wrap: u4 = 0,
        _: u8 = 0,

        const Disabled = packed struct {
            move: u4 = 0,
            duration: u4 = 0,
        };

        const FutureSight = packed struct {
            damage: u12 = 0,
            count: u4 = 0,
        };

        comptime {
            assert(@sizeOf(Data) == 12);
            // TODO: Safety check workaround for ziglang/zig#2627
            assert(@bitSizeOf(Data) == @sizeOf(Data) * 8);
        }
    };

    comptime {
        assert(@sizeOf(Volatile) == 16);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Volatile) == @sizeOf(Volatile) * 8);
    }
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

pub const Item = items.Item;

test "Item" {
    try expect(Item.boost(.MasterBall) == null);
    try expectEqual(Type.Normal, Item.boost(.PinkBow).?);
    try expectEqual(Type.Normal, Item.boost(.PolkadotBow).?);
    try expectEqual(Type.Dark, Item.boost(.BlackGlasses).?);

    try expect(!Item.mail(.TM50));
    try expect(Item.mail(.FlowerMail));
    try expect(Item.mail(.MirageMail));

    try expect(!Item.berry(.MirageMail));
    try expect(Item.berry(.PSNCureBerry));
    try expect(Item.berry(.GoldBerry));
}

pub const Move = moves.Move;

test "Moves" {
    try expectEqual(251, @enumToInt(Move.BeatUp));
    const move = Move.get(.DynamicPunch);
    try expectEqual(@as(u8, 50), move.accuracy);
    try expectEqual(@as(u8, 5), move.pp * 5);
}

pub const Species = species.Species;

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
