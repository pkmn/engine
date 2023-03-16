const std = @import("std");
const builtin = @import("builtin");

const data = @import("../common/data.zig");
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const mechanics = @import("mechanics.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

/// TODO: doc
pub const MAX_OPTIONS: usize = 9; // move 1..4, switch 2..6
/// TODO: doc
pub const MAX_LOGS: usize = 180;

/// TODO: doc
pub const OPTIONS_SIZE = if (builtin.mode == .ReleaseSmall)
    MAX_OPTIONS
else
    std.math.ceilPowerOfTwo(usize, MAX_OPTIONS) catch unreachable;
/// TODO: doc
pub const LOGS_SIZE = if (builtin.mode == .ReleaseSmall)
    MAX_LOGS
else
    std.math.ceilPowerOfTwo(usize, MAX_LOGS) catch unreachable;

const Choice = data.Choice;
const ID = data.ID;
const Player = data.Player;
const Result = data.Result;

const showdown = options.showdown;

/// TODO: doc
pub const PRNG = rng.PRNG(1);

/// TODO: doc
pub fn Battle(comptime RNG: anytype) type {
    return extern struct {
        const Self = @This();

        /// TODO: doc
        sides: [2]Side,
        /// TODO: doc
        turn: u16 = 0,
        /// TODO: doc
        last_damage: u16 = 0,
        /// TODO: doc
        last_selected_indexes: MoveIndexes = .{},
        /// TODO: doc
        rng: RNG,

        /// TODO: doc
        pub inline fn side(self: *Self, player: Player) *Side {
            return &self.sides[@enumToInt(player)];
        }

        /// TODO: doc
        pub inline fn foe(self: *Self, player: Player) *Side {
            return &self.sides[@enumToInt(player.foe())];
        }

        /// TODO: doc
        pub inline fn active(self: *Self, player: Player) ID {
            return player.ident(@intCast(u3, self.side(player).order[0]));
        }

        /// TODO: doc
        pub fn update(self: *Self, c1: Choice, c2: Choice, log: anytype) !Result {
            return mechanics.update(self, c1, c2, log);
        }

        /// TODO: doc
        pub fn choices(self: *Self, player: Player, request: Choice.Type, out: []Choice) u8 {
            return mechanics.choices(self, player, request, out);
        }
    };
}

test Battle {
    try expectEqual(384, @sizeOf(Battle(PRNG)));
}

/// TODO: doc
pub const Side = extern struct {
    /// TODO: doc
    pokemon: [6]Pokemon = [_]Pokemon{.{}} ** 6,
    /// TODO: doc
    active: ActivePokemon = .{},
    /// TODO: doc
    order: [6]u8 = [_]u8{0} ** 6,
    /// TODO: doc
    last_selected_move: Move = .None,
    /// TODO: doc
    last_used_move: Move = .None,

    comptime {
        assert(@sizeOf(Side) == 184);
    }

    /// TODO: doc
    pub inline fn get(self: *Side, slot: u8) *Pokemon {
        assert(slot > 0 and slot <= 6);
        const id = self.order[slot - 1];
        assert(id > 0 and id <= 6);
        return &self.pokemon[id - 1];
    }

    /// TODO: doc
    pub inline fn stored(self: *Side) *Pokemon {
        return self.get(1);
    }
};

/// TODO: doc
pub const ActivePokemon = extern struct {
    /// TODO: doc
    stats: Stats(u16) = .{},
    /// TODO: doc
    species: Species = .None,
    /// TODO: doc
    types: Types = .{},
    /// TODO: doc
    boosts: Boosts = .{},
    /// TODO: doc
    volatiles: Volatiles = .{},
    /// TODO: doc
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,

    comptime {
        assert(@sizeOf(ActivePokemon) == 32);
    }

    /// TODO: doc
    pub inline fn move(self: *ActivePokemon, mslot: u8) *MoveSlot {
        assert(mslot > 0 and mslot <= 4);
        assert(self.moves[mslot - 1].id != .None);
        return &self.moves[mslot - 1];
    }
};

/// TODO: doc
pub const Pokemon = extern struct {
    /// TODO: doc
    stats: Stats(u16) = .{},
    /// TODO: doc
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    /// TODO: doc
    hp: u16 = 0,
    /// TODO: doc
    status: u8 = 0,
    /// TODO: doc
    species: Species = .None,
    /// TODO: doc
    types: Types = .{},
    /// TODO: doc
    level: u8 = 100,

    comptime {
        assert(@sizeOf(Pokemon) == 24);
    }

    /// TODO: doc
    pub inline fn move(self: *Pokemon, mslot: u8) *MoveSlot {
        assert(mslot > 0 and mslot <= 4);
        assert(self.moves[mslot - 1].id != .None);
        return &self.moves[mslot - 1];
    }
};

/// TODO: doc
pub const MoveSlot = extern struct {
    /// TODO: doc
    id: Move = .None,
    /// TODO: doc
    pp: u8 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
    }
};

const uindex = if (showdown) u16 else u4;

/// TODO: doc
pub const MoveIndexes = packed struct {
    /// TODO: doc
    p1: uindex = 0,
    /// TODO: doc
    p2: uindex = 0,

    comptime {
        assert(@sizeOf(MoveIndexes) == if (showdown) 4 else 1);
    }
};

/// TODO: doc
pub const Status = enum(u8) {
    // 0 and 1 bits are also used for SLP
    SLP = 2,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,
    // Gen 1/2 uses Volatiles.Toxic instead of TOX, so the top Status bit is
    // repurposed to track whether the SLP status was self-inflicted or not
    // in order to implement Pokémon Showdown's "Sleep Clause Mod"
    SLF = 7,

    const SLP = 0b111;

    /// TODO: doc
    pub inline fn is(num: u8, status: Status) bool {
        if (status == .SLP) return Status.duration(num) > 0;
        return ((num >> @intCast(u3, @enumToInt(status))) & 1) != 0;
    }

    /// TODO: doc
    pub inline fn init(status: Status) u8 {
        assert(status != .SLP and status != .SLF);
        return @as(u8, 1) << @intCast(u3, @enumToInt(status));
    }

    /// TODO: doc
    pub inline fn slp(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    /// TODO: doc
    pub inline fn slf(dur: u3) u8 {
        assert(dur > 0);
        return 0x80 | slp(dur);
    }

    /// TODO: doc
    pub inline fn duration(num: u8) u3 {
        return @intCast(u3, num & SLP);
    }

    /// TODO: doc
    pub inline fn any(num: u8) bool {
        return num > 0;
    }

    /// TODO: doc
    pub fn name(num: u8) []const u8 {
        if (Status.is(num, .SLF)) return "SLF";
        if (Status.is(num, .SLP)) return "SLP";
        if (Status.is(num, .PSN)) return "PSN";
        if (Status.is(num, .BRN)) return "BRN";
        if (Status.is(num, .FRZ)) return "FRZ";
        if (Status.is(num, .PAR)) return "PAR";
        return "OK";
    }
};

test Status {
    try expect(!Status.any(0));

    try expect(Status.is(Status.init(.PSN), .PSN));
    try expect(!Status.is(Status.init(.PSN), .PAR));
    try expect(Status.is(Status.init(.BRN), .BRN));
    try expect(!Status.is(Status.init(.FRZ), .SLP));
    try expect(Status.is(Status.init(.FRZ), .FRZ));

    try expect(!Status.is(0, .SLP));
    try expect(Status.is(Status.slp(5), .SLP));
    try expect(!Status.is(Status.slp(5), .SLF));
    try expect(!Status.is(Status.slp(7), .PSN));
    try expectEqual(@as(u3, 5), Status.duration(Status.slp(5)));
    try expect(Status.is(Status.slf(2), .SLP));
    try expect(Status.is(Status.slf(2), .SLF));
    try expectEqual(@as(u3, 1), Status.duration(Status.slp(1)));
}

/// TODO: doc
pub const Volatiles = packed struct {
    /// TODO: doc
    Bide: bool = false,
    /// TODO: doc
    Thrashing: bool = false,
    /// TODO: doc
    MultiHit: bool = false,
    /// TODO: doc
    Flinch: bool = false,
    /// TODO: doc
    Charging: bool = false,
    /// TODO: doc
    Binding: bool = false,
    /// TODO: doc
    Invulnerable: bool = false,
    /// TODO: doc
    Confusion: bool = false,

    /// TODO: doc
    Mist: bool = false,
    /// TODO: doc
    FocusEnergy: bool = false,
    /// TODO: doc
    Substitute: bool = false,
    /// TODO: doc
    Recharging: bool = false,
    /// TODO: doc
    Rage: bool = false,
    /// TODO: doc
    LeechSeed: bool = false,
    /// TODO: doc
    Toxic: bool = false,
    /// TODO: doc
    LightScreen: bool = false,

    /// TODO: doc
    Reflect: bool = false,
    /// TODO: doc
    Transform: bool = false,
    /// TODO: doc
    confusion: u3 = 0,
    /// TODO: doc
    attacks: u3 = 0,

    /// TODO: doc
    // NB: used for both bide and accuracy overwriting!
    state: u16 = 0,
    /// TODO: doc
    substitute: u8 = 0,
    /// TODO: doc
    transform: u4 = 0,
    /// TODO: doc
    disabled_duration: u4 = 0,
    /// TODO: doc
    disabled_move: u3 = 0,
    /// TODO: doc
    toxic: u5 = 0,

    comptime {
        assert(@sizeOf(Volatiles) == 8);
    }
};

test Volatiles {
    var volatiles = Volatiles{};
    volatiles.Confusion = true;
    volatiles.confusion = 2;
    volatiles.Thrashing = true;
    volatiles.state = 235;
    volatiles.attacks = 3;
    volatiles.Substitute = true;
    volatiles.substitute = 42;
    volatiles.toxic = 4;
    volatiles.disabled_move = 2;
    volatiles.disabled_duration = 4;

    try expect(volatiles.Confusion);
    try expect(volatiles.Thrashing);
    try expect(volatiles.Substitute);
    try expect(!volatiles.Recharging);
    try expect(!volatiles.Transform);
    try expect(!volatiles.MultiHit);

    try expectEqual(@as(u16, 235), volatiles.state);
    try expectEqual(@as(u8, 42), volatiles.substitute);
    try expectEqual(@as(u4, 2), volatiles.disabled_move);
    try expectEqual(@as(u4, 4), volatiles.disabled_duration);
    try expectEqual(@as(u4, 2), volatiles.confusion);
    try expectEqual(@as(u5, 4), volatiles.toxic);
    try expectEqual(@as(u4, 3), volatiles.attacks);
}

/// TODO: doc
pub const Stat = enum { hp, atk, def, spe, spc };

/// TODO: doc
pub fn Stats(comptime T: type) type {
    return extern struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,

        /// TODO: doc
        pub fn calc(comptime stat: []const u8, base: T, dv: u4, exp: u16, level: u8) T {
            assert(level > 0 and level <= 100);
            const core: u32 = (2 *% (@as(u32, base) +% dv)) +% @as(u32, (std.math.sqrt(exp) / 4));
            const factor: u32 = if (std.mem.eql(u8, stat, "hp")) level + 10 else 5;
            return @intCast(T, core *% @as(u32, level) / 100 +% factor);
        }
    };
}

test Stats {
    try expectEqual(5, @sizeOf(Stats(u8)));
    const stats = Stats(u16){ .atk = 2, .spe = 3 };
    try expectEqual(2, stats.atk);
    try expectEqual(0, stats.def);
}

/// TODO: doc
pub const Boosts = packed struct {
    /// TODO: doc
    atk: i4 = 0,
    /// TODO: doc
    def: i4 = 0,
    /// TODO: doc
    spe: i4 = 0,
    /// TODO: doc
    spc: i4 = 0,
    /// TODO: doc
    accuracy: i4 = 0,
    /// TODO: doc
    evasion: i4 = 0,

    _: u8 = 0,

    comptime {
        assert(@sizeOf(Boosts) == 4);
    }
};

test Boosts {
    const boosts = Boosts{ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

/// TODO: doc
pub const Move = moves.Move;

test Move {
    try expectEqual(2, @enumToInt(Move.KarateChop));
    const move = Move.get(.Fissure);
    try expectEqual(Move.Effect.OHKO, move.effect);
    try expectEqual(@as(u8, 30), move.accuracy);
    try expectEqual(Type.Ground, move.type);

    try expect(!Move.Effect.onBegin(.None));
    try expect(Move.Effect.onBegin(.Confusion));
    try expect(Move.Effect.onBegin(.Transform));
    try expect(!Move.Effect.onBegin(.AccuracyDown1));

    try expect(!Move.Effect.isStatDown(.Transform));
    try expect(Move.Effect.isStatDown(.AccuracyDown1));
    try expect(Move.Effect.isStatDown(.SpeedDown1));
    try expect(!Move.Effect.isStatDown(.AttackUp1));

    try expect(!Move.Effect.onEnd(.Transform));
    try expect(Move.Effect.onEnd(.AccuracyDown1));
    try expect(Move.Effect.onEnd(.SpeedUp2));
    try expect(!Move.Effect.onEnd(.Charge));

    try expect(!Move.Effect.alwaysHappens(.SpeedUp2));
    try expect(Move.Effect.alwaysHappens(.DrainHP));
    try expect(Move.Effect.alwaysHappens(.Recoil));
    try expect(!Move.Effect.alwaysHappens(.Charge));
    try expect(!Move.Effect.alwaysHappens(.SpeedDownChance));
    try expect(Move.Effect.alwaysHappens(.Rage));

    // all considered "always happens" on cartridge
    try expect(!Move.Effect.alwaysHappens(.DoubleHit));
    try expect(!Move.Effect.alwaysHappens(.MultiHit));
    try expect(!Move.Effect.alwaysHappens(.Twineedle));

    try expect(!Move.Effect.isSpecial(.SpeedUp2));
    try expect(Move.Effect.isSpecial(.DrainHP));
    try expect(Move.Effect.isSpecial(.Rage)); // other on cartridge
    try expect(Move.Effect.isSpecial(.DoubleHit));
    try expect(Move.Effect.isSpecial(.MultiHit));
    try expect(!Move.Effect.isSpecial(.Twineedle));

    try expect(!Move.Effect.isMulti(.Thrashing));
    try expect(Move.Effect.isMulti(.DoubleHit));
    try expect(Move.Effect.isMulti(.MultiHit));
    try expect(Move.Effect.isMulti(.Twineedle));
    try expect(!Move.Effect.isMulti(.AttackDownChance));

    try expect(!Move.Effect.isStatDownChance(.Thrashing));
    try expect(Move.Effect.isStatDownChance(.AttackDownChance));
    try expect(Move.Effect.isStatDownChance(.SpecialDownChance));
    try expect(!Move.Effect.isStatDownChance(.BurnChance1));

    try expect(!Move.Effect.isSecondaryChance(.MultiHit));
    try expect(Move.Effect.isSecondaryChance(.Twineedle));
    try expect(Move.Effect.isSecondaryChance(.PoisonChance2));
    try expect(!Move.Effect.isSecondaryChance(.Disable));
}

/// TODO: doc
pub const Species = species.Species;

test Species {
    try expectEqual(2, @enumToInt(Species.Ivysaur));
    try expectEqual(@as(u8, 100), Species.get(.Mew).stats.def);
}

/// TODO: doc
pub const Type = types.Type;
/// TODO: doc
pub const Types = types.Types;

/// TODO: doc
pub const Effectiveness = enum(u8) {
    /// TODO: doc
    Immune = 0,
    /// TODO: doc
    Resisted = 5,
    /// TODO: doc
    Neutral = 10,
    /// TODO: doc
    Super = 20,

    /// TODO: doc
    pub const neutral: u16 = @enumToInt(Effectiveness.Neutral) * @enumToInt(Effectiveness.Neutral);
    /// TODO: doc
    pub const mismatch: u16 = @enumToInt(Effectiveness.Resisted) + @enumToInt(Effectiveness.Super);

    comptime {
        assert(@sizeOf(Effectiveness) == 1);
    }
};

test Types {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Effectiveness.Super));

    try expect(!Type.Ghost.special());
    try expect(Type.Dragon.special());

    try expectEqual(Effectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Effectiveness.Super, Type.Water.effectiveness(.Fire));
    try expectEqual(Effectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Effectiveness.Neutral, Type.effectiveness(.Normal, .Grass));

    try expectEqual(@as(u8, 3), Type.precedence(.Water, .Water));
    try expectEqual(@as(u8, 26), Type.precedence(.Bug, .Ghost));
    try expect(Type.precedence(.Poison, .Bug) > Type.precedence(.Poison, .Poison));

    const t: Types = .{ .type1 = .Rock, .type2 = .Ground };
    try expect(!t.immune(.Grass));
    try expect(t.immune(.Electric));

    try expect(!t.includes(.Fire));
    try expect(t.includes(.Rock));
}

/// TODO: doc
pub const DVs = struct {
    /// TODO: doc
    atk: u4 = 15,
    /// TODO: doc
    def: u4 = 15,
    /// TODO: doc
    spe: u4 = 15,
    /// TODO: doc
    spc: u4 = 15,

    /// TODO: doc
    pub fn hp(self: DVs) u4 {
        return (self.atk & 1) << 3 | (self.def & 1) << 2 | (self.spe & 1) << 1 | (self.spc & 1);
    }

    /// TODO: doc
    pub fn random(rand: *rng.PSRNG) DVs {
        return .{
            .atk = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .def = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .spe = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .spc = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
        };
    }
};

test DVs {
    var dvs = DVs{ .spc = 15, .spe = 15 };
    try expectEqual(@as(u4, 15), dvs.hp());
    dvs = DVs{
        .atk = 5,
        .def = 15,
        .spe = 13,
        .spc = 13,
    };
    try expectEqual(@as(u4, 15), dvs.hp());
    dvs = DVs{
        .def = 3,
        .spe = 10,
        .spc = 11,
    };
    try expectEqual(@as(u4, 13), dvs.hp());
}
