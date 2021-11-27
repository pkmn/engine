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
        self.seed = rng.gen12(self.seed);
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

    // FIXME: move to mechanics (need to also apply burn/paralyze etc)
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
        self.pokemon.volatiles.zero();
        inline for (std.meta.fieldNames(Boosts(i4))) |boost| {
            @field(self.pokemon.boosts, boost) = @field(active.boosts, boost);
        }
        self.pokemon.level = active.level;
        self.pokemon.hp = active.hp;
        self.pokemon.status = active.status;
        self.pokemon.types = active.types;
        self.active = slot;
    }
};

const ActivePokemon = packed struct {
    stats: Stats(u16),
    moves: [4]MoveSlot,
    volatiles: Volatile = Volatile{},
    boosts: Boosts(i4) = Boosts(i4){},
    level: u8 = 100,
    hp: u16,
    status: u8 = 0,
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
    status: u8 = 0,
    species: Species,
    types: Types,
    level: u8 = 100,

    comptime {
        assert(@sizeOf(Pokemon) == 22);
    }

    // @test-only
    pub fn init(s: Species, ms: []const Moves) Pokemon {
        assert(ms.len > 0 and ms.len <= 4);
        const specie = Species.get(s);
        const stats = Stats(u12){
            .hp = Stats(u12).calc(.hp, specie.stats.hp, 0xF, 0xFFFF, 100),
            .atk = Stats(u12).calc(.atk, specie.stats.atk, 0xF, 0xFFFF, 100),
            .def = Stats(u12).calc(.def, specie.stats.def, 0xF, 0xFFFF, 100),
            .spe = Stats(u12).calc(.spe, specie.stats.spe, 0xF, 0xFFFF, 100),
            .spc = Stats(u12).calc(.spc, specie.stats.spc, 0xF, 0xFFFF, 100),
        };

        var slots = [_]MoveSlot{MoveSlot{}} ** 4;
        var i: usize = 0;
        while (i < ms.len) : (i += 1) {
            slots[i].id = ms[i];
            slots[i].pp = @truncate(u6, Moves.pp(ms[i]) / 5 * 8);
        }

        return Pokemon{
            .stats = stats,
            .position = 1,
            .moves = slots,
            .hp = stats.hp,
            .species = s,
            .types = specie.types,
        };
    }

    // @test-only
    pub fn format(self: Pokemon, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        // 1. Gengar (LV 100) 323/OK (323/228/218/358/318): Absorb (32/32), Pound (56/56), DreamEater (24/24), Psychic (16/16)
        try writer.print("{d}. {s} (LV {d}) {d}/{s}", .{ self.position, @tagName(self.species), self.level, self.hp, Status.name(self.status) });
        try writer.print(" ({d}/{d}/{d}/{d}/{d}):", .{ self.stats.hp, self.stats.atk, self.stats.def, self.stats.spc, self.stats.spe });
        for (self.moves) |m, i| {
            const max = Moves.pp(m.id) / 5 * (5 + @as(u8, m.pp_ups));
            try writer.print(" {s} ({d}/{d})", .{ @tagName(m.id), m.pp, max });
            if (i < self.moves.len - 1) try writer.print(",", .{});
        }
    }
};

test "Pokemon" {
    const pokemon = Pokemon.init(Species.Gengar, &[_]Moves{ .Absorb, .Pound, .DreamEater, .Psychic });
    try expect(!Status.any(pokemon.status));
}

const MoveSlot = packed struct {
    id: Moves = .None,
    pp: u6 = 0,
    pp_ups: u2 = 3,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }
};

pub const Status = enum(u8) {
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

    // @test-only
    pub fn name(num: u8) []const u8 {
        if (Status.is(num, .SLP)) return "SLP";
        if (Status.is(num, .PSN)) return "PSN";
        if (Status.is(num, .BRN)) return "BRN";
        if (Status.is(num, .FRZ)) return "FRZ";
        if (Status.is(num, .PAR)) return "PAR";
        if (Status.is(num, .TOX)) return "TOX";
        return "OK";
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
    data: VolatileData = VolatileData{},
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

// @test-only
pub const Stat = enum { hp, atk, def, spe, spc };

pub fn Stats(comptime T: type) type {
    return packed struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,

        // @test-only
        pub fn calc(stat: Stat, base: T, dv: u4, exp: u16, level: u8) T {
            assert(level > 0 and level <= 100);
            const factor = if (stat == .hp) level + 10 else 5;
            return @truncate(T, (@as(u16, base) + dv) * 2 + @as(u16, (std.math.sqrt(exp) / 4)) * level / 100 + factor);
        }
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
// @test-only
pub const Specie = struct {
    stats: Stats(u8),
    types: Types,
};

test "Species" {
    try expectEqual(2, @enumToInt(Species.Ivysaur));
    try expectEqual(@as(u8, 100), Species.get(.Mew).stats.def);
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
