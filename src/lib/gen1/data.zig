const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");

const rng = @import("../common/rng.zig");

const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const mechanics = @import("./mechanics.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

pub fn Battle(comptime PRNG: anytype) type {
    return extern struct {
        const Self = @This();

        rng: PRNG,
        turn: u16 = 0,
        last_damage: u16 = 0,
        sides: [2]Side,

        pub fn get(self: *Self, player: Player) *Side {
            return &self.sides[@enumToInt(player)];
        }

        pub fn foe(self: *Self, player: Player) *Side {
            return &self.sides[player.foe()];
        }

        pub fn update(self: *Self, c1: Choice, c2: Choice, log: anytype) !Result {
            return mechanics.update(self, c1, c2, log);
        }
    };
}

test "Battle" {
    try expectEqual(if (build_options.showdown) 368 else 372, @sizeOf(Battle(rng.PRNG(1))));
}

pub const Player = enum(u1) {
    P1,
    P2,

    pub fn foe(self: Player) Player {
        return @intToEnum(Player, ~@enumToInt(self));
    }

    pub fn ident(self: Player, slot: u8) u8 {
        assert(slot > 0 and slot <= 6);
        return (@as(u8, @enumToInt(self)) << 3) | slot;
    }
};

test "Player" {
    try expectEqual(Player.P2, Player.P1.foe());
    try expectEqual(@as(u8, 0b0000_0001), Player.P1.ident(1));
    try expectEqual(@as(u8, 0b0000_1101), Player.P2.ident(5));
}

pub const Side = extern struct {
    pokemon: [6]Pokemon = [_]Pokemon{.{}} ** 6,
    active: ActivePokemon = .{},
    last_used_move: Move = .None,
    last_selected_move: Move = .None,

    comptime {
        assert(@sizeOf(Side) == 178);
    }

    pub fn get(self: *Side, slot: u8) *Pokemon {
        assert(slot > 0 and slot <= 6);
        return &self.pokemon[slot - 1];
    }
};

pub const ActivePokemon = extern struct {
    volatiles: Volatiles = .{},
    stats: Stats(u12) = .{},
    // 4 bit trailling
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    boosts: Boosts = .{},
    species: Species = .None,
    types: Types = .{}, // TODO document required
    position: u8 = 0,
    _: u8 = 0,

    comptime {
        assert(@sizeOf(ActivePokemon) == 32);
    }
};

pub const Pokemon = extern struct {
    stats: Stats(u12) = .{},
    // 4 bits trailing
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    hp: u16 = 0,
    status: u8 = 0,
    species: Species = .None,
    types: Types = .{},
    level: u8 = 100,
    position: u8 = 0,
    id: u8 = 0,

    comptime {
        assert(@sizeOf(Pokemon) == 24);
    }
};

pub const MoveSlot = packed struct {
    id: Move = .None,
    pp: u6 = 0,
    pp_ups: u2 = 3,

    comptime {
        assert(@sizeOf(MoveSlot) == @sizeOf(u16));
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(MoveSlot) == @sizeOf(MoveSlot) * 8);
    }
};

pub const Status = enum(u8) {
    // 0 and 1 bits are also used for SLP
    SLP = 2,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,
    // NB: Gen 1 uses Volatiles.Toxic instead
    TOX = 7,

    const SLP = 0b111;
    const PSN = 0b10001000;

    pub fn is(num: u8, status: Status) bool {
        if (status == .SLP) return Status.duration(num) > 0;
        return ((num >> @intCast(u3, @enumToInt(status))) & 1) != 0;
    }

    pub fn init(status: Status) u8 {
        assert(status != .SLP);
        return @as(u8, 1) << @intCast(u3, @enumToInt(status));
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
        assert(builtin.is_test);
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

pub const Volatiles = packed struct {
    data: Data = Data{},

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
    Transform: bool = false,

    _: u6 = 0,

    pub const Data = packed struct {
        bide: u16 = 0,
        substitute: u8 = 0,
        disabled: Disabled = .{},
        confusion: u4 = 0,
        toxic: u4 = 0,
        attacks: u4 = 0,

        _: u4 = 0,

        const Disabled = packed struct {
            move: u4 = 0,
            duration: u4 = 0,
        };

        comptime {
            assert(@sizeOf(Data) == 6);
            // TODO: Safety check workaround for ziglang/zig#2627
            assert(@bitSizeOf(Data) == @sizeOf(Data) * 8);
        }
    };

    comptime {
        assert(@sizeOf(Volatiles) == 9);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Volatiles) == @sizeOf(Volatiles) * 8);
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
        pub fn calc(comptime stat: []const u8, base: T, dv: u4, exp: u16, level: u8) T {
            assert(builtin.is_test);
            assert(level > 0 and level <= 100);
            const factor = if (std.mem.eql(u8, stat, "hp")) level + 10 else 5;
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

pub const Boosts = packed struct {
    atk: i4 = 0,
    def: i4 = 0,
    spe: i4 = 0,
    spc: i4 = 0,
    accuracy: i4 = 0,
    evasion: i4 = 0,

    comptime {
        assert(@sizeOf(Boosts) == 3);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Boosts) == @sizeOf(Boosts) * 8);
    }
};

test "Boosts" {
    const boosts = Boosts{ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

pub const Move = moves.Move;

test "Move" {
    try expectEqual(2, @enumToInt(Move.KarateChop));
    const move = Move.get(.Fissure);
    try expectEqual(Move.Effect.OHKO, move.effect);
    try expectEqual(@as(u8, 30), move.accuracy());
    try expectEqual(Type.Ground, move.type);
}

pub const Species = species.Species;

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
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Effectiveness) == @sizeOf(Effectiveness) * 8);
    }
};

test "Types" {
    try expectEqual(14, @enumToInt(Type.Dragon));
    try expectEqual(20, @enumToInt(Effectiveness.Super));

    try expectEqual(Effectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Effectiveness.Super, Type.Water.effectiveness(.Fire));
    try expectEqual(Effectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Effectiveness.Neutral, Type.effectiveness(.Normal, .Grass));

    const t: Types = .{ .type1 = .Rock, .type2 = .Ground };
    try expect(!t.immune(.Grass));
    try expect(t.immune(.Electric));
}

// @test-only
pub const DVs = struct {
    atk: u4 = 15,
    def: u4 = 15,
    spe: u4 = 15,
    spc: u4 = 15,

    pub fn hp(self: *const DVs) u4 {
        assert(builtin.is_test);
        return (self.atk & 1) << 3 | (self.def & 1) << 2 | (self.spe & 1) << 1 | (self.spc & 1);
    }

    pub fn random(rand: *rng.Random) DVs {
        assert(builtin.is_test);
        return .{
            .atk = if (rand.chance(1, 5)) rand.range(u4, 1, 15) else 15,
            .def = if (rand.chance(1, 5)) rand.range(u4, 1, 15) else 15,
            .spe = if (rand.chance(1, 5)) rand.range(u4, 1, 15) else 15,
            .spc = if (rand.chance(1, 5)) rand.range(u4, 1, 15) else 15,
        };
    }
};

test "DVs" {
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

pub const Choice = packed struct {
    type: Choice.Type = .Pass,
    data: u4 = 0,

    const Type = enum(u4) {
        Pass,
        Move,
        Switch,
    };

    comptime {
        assert(@sizeOf(Choice) == 1);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Choice) == @sizeOf(Choice) * 8);
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

pub const Result = enum(u3) {
    None,
    Win,
    Lose,
    Tie,
    Error, // Desync, EBC, etc.
};

// TODO DEBUG
comptime {
    std.testing.refAllDecls(@This());
}
