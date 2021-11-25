const std = @import("std");

const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig");

const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const bit = util.bit;

const Battle = packed struct {
    seed: u8,
    turn: u8 = 0,
    last_damage: u16 = 0,
    sides: [2]Side,

    comptime {
        assert(@sizeOf(Battle) == 348);
    }

    pub fn p1(self: *Battle) *Side {
        return &self.sides[0];
    }

    pub fn p2(self: *Battle) *Side {
        return &self.sides[1];
    }

    pub fn random(self: *Battle) u32 {
        self.seed = rng.gb(self.seed);
        return self.seed;
    }
};

const Side = packed struct {
    team: [6]Pokemon,
    pokemon: ActivePokemon,
    active: u8 = 0,
    last_used_move: Moves = .None,
    last_selected_move: Moves = .None,
    _: u8 = 0,

    comptime {
        assert(@sizeOf(Side) == 172);
    }

    pub fn get(self: *const Side, slot: u8) *Pokemon {
        assert(slot > 0 and slot < 7);
        return self.pokemon[slot - 1];
    }

    pub fn switchIn(self: *Side, slot: u8) void {
        assert(slot != self.active);
        assert(self.team[self.active - 1].position == 1);

        const active = self.get(slot);
        self.team[self.active - 1].position = active.position;
        active.position = 1;

        inline for (std.meta.fieldNames(Stats(u16))) |stat| {
            @field(self.pokemon.stats, stat) = @field(active.stats, stat);
        }
        var i = 0;
        while (i < 4) : (i += 1) {
            self.pokemon.moves[i] = active.pokemon.moves[i];
        }
        self.pokemon.volatiles = Volatile{};
        self.pokemon.volatiles_data = VolatileData{};
        inline for (std.meta.fieldNames(Boosts(i4))) |boost| {
            @field(self.pokemon.boosts, boost) = @field(active.boosts, boost);
        }
        self.pokemon.level = active.level;
        self.pokemon.hp = active.hp;
        self.pokemon.status = active.status;
        self.pokemon.types = active.types;
        self.pokemon.disabled = .{ .moves = 0, .duration = 0 };
        self.active = slot;
    }
};

const ActivePokemon = packed struct {
    stats: Stats(u16),
    moves: [4]MoveSlot,
    volatiles: Volatile,
    boosts: Boosts(i4),
    level: u8 = 100,
    hp: u16,
    status: Status = .Healthy,
    species: Species,
    types: Types,
     _: u8 = 0,

    comptime {
        assert(@sizeOf(ActivePokemon) == 36);
    }
};

const Pokemon = packed struct {
    stats: Stats(u12),
    position: u4,
    moves: [4]MoveSlot,
    hp: u16,
    status: Status = .Healthy,
    species: Species,
    types: Types,
    level: u8 = 100,

    comptime {
        assert(@sizeOf(Pokemon) == 22);
    }
};

const MoveSlot = packed struct {
    id: Moves = .None,
    pp: u6 = 0,
    pp_ups: u2 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }
};

pub const Status = enum(u8) {
    Healthy = 0,
    // 0 and 1 bits are also used for SLP
    SLP = 2,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,
    TOX = 7,

    const SLP = 0b111;
    const PSN = 0b10001000;

    pub fn is(num: u8, status: Status) bool {
        if (status == .SLP) return Status.duration(num) > 0;
        return bit.isSet(u8, num, @intCast(u3, @enumToInt(status)));
    }

    pub fn init(status: Status) u8 {
        assert(status != .SLP);
        return bit.set(u8, 0, @intCast(u3, @enumToInt(status)));
    }

    pub fn slp(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    pub fn duration(num: u8) u3 {
        return @intCast(u3, num & SLP);
    }

    pub fn psn(num: u8) bool {
        return num & PSN != 0;
    }

    pub fn any(num: u8) bool {
        return num > 0;
    }
};

test "Status" {
    try expect(Status.is(Status.init(.PSN), .PSN));
    try expect(!Status.is(Status.init(.PSN), .PAR));
    try expect(Status.is(Status.init(.BRN), .BRN));
    try expect(!Status.is(Status.init(.FRZ), .SLP));
    try expect(Status.is(Status.init(.FRZ), .FRZ));
    try expect(Status.is(Status.init(.TOX), .TOX));

    try expect(!Status.is(0, .SLP));
    try expect(Status.is(Status.slp(5), .SLP));
    try expect(!Status.is(Status.slp(7), .PSN));
    try expectEqual(@as(u3, 5), Status.duration(Status.slp(5)));

    try expect(!Status.psn(Status.init(.BRN)));
    try expect(Status.psn(Status.init(.PSN)));
    try expect(Status.psn(Status.init(.TOX)));

    try expect(!Status.any(0));
    try expect(Status.any(Status.init(.TOX)));
}

const Volatile = packed struct {
    data: VolatileData,
    _: u6 = 0,
    Bide: bool = false,
    Locked: bool = false,
    MultiHit: bool = false,
    Flinch: bool = false,
    Charging: bool = false,
    PartialTrap: bool = false,
    Invulnerable: bool = false,
    Confusion: bool = false,
    Mist: bool = false,
    FocusEnergy: bool = false,
    Substitute: bool = false,
    Recharging: bool = false,
    Rage: bool = false,
    LeechSeed: bool = false,
    Toxic: bool = false,
    LightScreen: bool = false,
    Reflect: bool = false,
    Transform: bool,

    comptime {
        assert(@sizeOf(Volatile) == 8);
    }
};

const VolatileData = packed struct {
    bide: u16 = 0,
    substitute: u8 = 0,
    confusion: u4 = 0,
    toxic: u4 = 0,
    disabled: packed struct {
        move: u4 = .None,
        duration: u4 = 0,
    },

    comptime {
        assert(@sizeOf(VolatileData) == 5);
    }
};

pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
    };
}

test "Stats" {
    try expectEqual(5, @sizeOf(Stats(u8)));
    const stats = Stats(u4){ .atk = 2, .spe = 3 };
    try expectEqual(2, stats.atk);
    try expectEqual(0, stats.def);
}

pub fn Boosts(comptime T: type) type {
    return packed struct {
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,
        accuracy: T = 0,
        evasion: T = 0,
    };
}

test "Boosts" {
    try expectEqual(3, @sizeOf(Boosts(i4)));
    const boosts = Boosts(i4){ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

pub const Moves = moves.Moves;
pub const Move = packed struct {
    bp: u8,
    acc: u4,
    type: Type,

    comptime {
        assert(@sizeOf(Move) == 2);
    }

    pub fn accuracy(self: *const Move) u8 {
        return (@as(u8, self.acc) + 6) * 5;
    }
};

test "Moves" {
    try expectEqual(2, @enumToInt(Moves.KarateChop));
    const move = Moves.get(.Fissure);
    try expectEqual(@as(u8, 30), move.accuracy());
    try expectEqual(Type.Ground, move.type);
}

pub const Species = species.Species;

test "Species" {
    try expectEqual(2, @enumToInt(Species.Ivysaur));
}

pub const Type = types.Type;
pub const Types = types.Types;

pub const Effectiveness = enum(u8) {
    Immune = 0,
    Resisted = 5,
    Neutral = 10,
    Super = 20,

    comptime {
        assert(@bitSizeOf(Effectiveness) == 8);
    }
};

test "Types" {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Effectiveness.Super));
    try expectEqual(Effectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Effectiveness.Super, Type.effectiveness(.Water, .Fire));
    try expectEqual(Effectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Effectiveness.Neutral, Type.effectiveness(.Normal, .Grass));
}

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
