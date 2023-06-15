const std = @import("std");

const common = @import("../common/data.zig");
const optional = @import("../common/optional.zig");
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rational = @import("../common/rational.zig");
const rng = @import("../common/rng.zig");

const calc = @import("calc.zig");
const chance = @import("chance.zig");
const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Choice = common.Choice;
const Player = common.Player;

const Optional = optional.Optional;

const showdown = options.showdown;

const PSRNG = rng.PSRNG;

const DVs = data.DVs;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;

/// Options which determine the range of various values TODO
pub const Options = struct {
    cleric: bool = showdown,
    block: bool = showdown,
};

/// TODO
pub const Battle = struct {
    /// TODO
    pub fn init(
        seed: u64,
        p1: []const Pokemon,
        p2: []const Pokemon,
    ) data.Battle(data.PRNG) {
        var rand = PSRNG.init(seed);
        return .{
            .rng = prng(&rand),
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    /// TODO
    pub fn fixed(
        comptime rolls: anytype,
        p1: []const Pokemon,
        p2: []const Pokemon,
    ) data.Battle(rng.FixedRNG(1, rolls.len)) {
        return .{
            .rng = .{ .rolls = rolls },
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    /// TODO
    pub fn random(rand: *PSRNG, opt: Options) data.Battle(data.PRNG) {
        return .{
            .rng = prng(rand),
            .turn = 0,
            .last_damage = 0,
            .sides = .{ Side.random(rand, opt), Side.random(rand, opt) },
        };
    }
};

fn prng(rand: *PSRNG) data.PRNG {
    // GLITCH: initial bytes in seed can only range from 0-252, not 0-255
    const max: u8 = 253;
    return .{
        .src = .{
            .seed = if (showdown)
                rand.newSeed()
            else
                .{
                    rand.range(u8, 0, max), rand.range(u8, 0, max),
                    rand.range(u8, 0, max), rand.range(u8, 0, max),
                    rand.range(u8, 0, max), rand.range(u8, 0, max),
                    rand.range(u8, 0, max), rand.range(u8, 0, max),
                    rand.range(u8, 0, max), rand.range(u8, 0, max),
                },
        },
    };
}

/// TODO
pub const Side = struct {
    /// TODO
    pub fn init(ps: []const Pokemon) data.Side {
        assert(ps.len > 0 and ps.len <= 6);
        var side = data.Side{};

        for (0..ps.len) |i| {
            side.pokemon[i] = Pokemon.init(ps[i]);
            side.order[i] = @intCast(u4, i) + 1;
        }
        return side;
    }

    /// TODO
    pub fn random(rand: *PSRNG, opt: Options) data.Side {
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 5 + 1) else 6;
        var side = data.Side{};

        for (0..n) |i| {
            side.pokemon[i] = Pokemon.random(rand, opt);
            side.order[i] = @intCast(u4, i) + 1;
        }

        return side;
    }
};

/// TODO
pub const EXP = 0xFFFF;

/// TODO
pub const Pokemon = struct {
    species: Species,
    moves: []const Move,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,
    dvs: DVs = .{},
    stats: Stats(u16) = .{ .hp = EXP, .atk = EXP, .def = EXP, .spe = EXP, .spc = EXP },

    /// TODO
    pub fn init(p: Pokemon) data.Pokemon {
        var pokemon = data.Pokemon{};
        pokemon.species = p.species;
        const species = Species.get(p.species);
        inline for (@typeInfo(@TypeOf(pokemon.stats)).Struct.fields) |field| {
            const hp = comptime std.mem.eql(u8, field.name, "hp");
            const spc =
                comptime std.mem.eql(u8, field.name, "spa") or std.mem.eql(u8, field.name, "spd");
            @field(pokemon.stats, field.name) = Stats(u16).calc(
                field.name,
                @field(species.stats, field.name),
                if (hp) p.dvs.hp() else if (spc) p.dvs.spc else @field(p.dvs, field.name),
                @field(p.stats, field.name),
                p.level,
            );
        }
        assert(p.moves.len > 0 and p.moves.len <= 4);
        for (p.moves, 0..) |m, j| {
            pokemon.moves[j].id = m;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            pokemon.moves[j].pp = @intCast(u8, @min(Move.pp(m) / 5 * 8, 61));
        }
        if (p.hp) |hp| {
            pokemon.hp = hp;
        } else {
            pokemon.hp = pokemon.stats.hp;
        }
        pokemon.status = p.status;
        pokemon.types = species.types;
        pokemon.level = p.level;
        return pokemon;
    }

    /// TODO
    pub fn random(rand: *PSRNG, opt: Options) data.Pokemon {
        const s = @enumFromInt(Species, rand.range(u8, 1, Species.size + 1));
        const species = Species.get(s);
        const lvl = if (rand.chance(u8, 1, 20)) rand.range(u8, 1, 99 + 1) else 100;
        var stats: Stats(u16) = .{};
        const dvs = DVs.random(rand);
        inline for (@typeInfo(@TypeOf(stats)).Struct.fields) |field| {
            @field(stats, field.name) = Stats(u16).calc(
                field.name,
                @field(species.stats, field.name),
                if (comptime std.mem.eql(u8, field.name, "hp"))
                    dvs.hp()
                else
                    @field(dvs, field.name),
                if (rand.chance(u8, 1, 20)) rand.range(u16, 0, EXP + 1) else EXP,
                lvl,
            );
        }

        var ms = [_]MoveSlot{.{}} ** 4;
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 3 + 1) else 4;
        for (0..n) |i| {
            var m: Move = .None;
            sample: while (true) {
                m = @enumFromInt(Move, rand.range(u8, 1, Move.size - 1 + 1));
                if (opt.block and blocked(m)) continue :sample;
                for (0..i) |j| if (ms[j].id == m) continue :sample;
                break;
            }
            const pp_ups =
                if (!opt.cleric and rand.chance(u8, 1, 10)) rand.range(u2, 0, 2 + 1) else 3;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            const max_pp = @intCast(u8, Move.pp(m) + @as(u8, pp_ups) * @min(Move.pp(m) / 5, 7));
            ms[i] = .{
                .id = m,
                .pp = if (opt.cleric) max_pp else rand.range(u8, 0, max_pp + 1),
            };
        }

        return .{
            .species = s,
            .types = species.types,
            .level = lvl,
            .stats = stats,
            .hp = if (opt.cleric) stats.hp else rand.range(u16, 0, stats.hp + 1),
            .status = if (!opt.cleric and rand.chance(u8, 1, 6 + 1))
                0 | (@as(u8, 1) << rand.range(u3, 1, 6 + 1))
            else
                0,
            .moves = ms,
        };
    }
};

fn blocked(m: Move) bool {
    // Binding moves are borked but only via Mirror Move / Metronome which are already blocked
    return switch (m) {
        .Mimic, .Metronome, .MirrorMove, .Transform => true,
        else => false,
    };
}

/// TODO
pub fn move(slot: u4) Choice {
    return .{ .type = .Move, .data = slot };
}

/// TODO
pub fn swtch(slot: u4) Choice {
    return .{ .type = .Switch, .data = slot };
}

/// TODO
pub const Rolls = struct {
    const PLAYER_NONE = [_]Optional(Player){.None};
    const PLAYERS = [_]Optional(Player){ .P1, .P2 };

    /// TODO call on correct player
    pub inline fn speedTie(action: chance.Action) []const Optional(Player) {
        return if (@field(action, "speed_tie") == .None) &PLAYER_NONE else &PLAYERS;
    }

    const BOOL_NONE = [_]Optional(bool){.None};
    const BOOLS = [_]Optional(bool){ .false, .true };

    /// TODO
    pub inline fn hit(action: chance.Action, parent: Optional(bool)) []const Optional(bool) {
        if (parent == .true) return &BOOL_NONE;
        return if (@field(action, "hit") == .None) &BOOL_NONE else &BOOLS;
    }

    /// TODO
    pub inline fn criticalHit(
        action: chance.Action,
        parent: Optional(bool),
    ) []const Optional(bool) {
        if (parent == .false) return &BOOL_NONE;
        return if (@field(action, "critical_hit") == .None) &BOOL_NONE else &BOOLS;
    }

    /// TODO
    pub inline fn secondaryChance(
        action: chance.Action,
        parent: Optional(bool),
    ) []const Optional(bool) {
        if (parent == .false) return &BOOL_NONE;
        return if (@field(action, "secondary_chance") == .None) &BOOL_NONE else &BOOLS;
    }

    pub const Range = struct { min: u9, max: u9 };
    pub inline fn damage(action: chance.Action, parent: Optional(bool)) Range {
        return if (parent == .false or @field(action, "damage") == 0)
            .{ .min = 0, .max = 1 }
        else
            .{ .min = 217, .max = 256 };
    }

    pub inline fn coalesce(player: Player, roll: u8, summaries: *calc.Summaries) !u8 {
        if (roll == 0) return roll;

        const base = summaries.get(player).damage.base;
        if (base == 0) return 255;

        // Closed form solution for max damage roll provided by Orion Taylor (orion#8038)!
        return @min(255, roll + ((254 - ((@as(u32, base) * roll) % 255)) / base));
    }

    /// TODO
    pub inline fn confused(action: chance.Action) []const Optional(bool) {
        return if (@field(action, "confused") == .None) &BOOL_NONE else &BOOLS;
    }

    /// TODO
    pub inline fn paralyzed(action: chance.Action, parent: Optional(bool)) []const Optional(bool) {
        if (parent == .true) return &BOOL_NONE;
        return if (@field(action, "paralyzed") == .None) &BOOL_NONE else &BOOLS;
    }

    const DURATION_NONE = [_]u1{0};
    const DURATION = [_]u1{ 0, 1 };

    pub inline fn duration(action: chance.Action, parent: Optional(bool)) []const u1 {
        if (parent == .false) return &DURATION_NONE;
        return if (@field(action, "duration") == 0) &DURATION_NONE else &DURATION;
    }

    const SLEEP_NONE = [_]u3{0};

    pub inline fn sleep(action: chance.Action) []const u3 {
        const turns = @field(action, "sleep");
        return if (turns < 1 or turns >= 7) &SLEEP_NONE else &[_]u3{ 0, turns + 1 };
    }

    const DISABLE_NONE = [_]u4{0};

    pub inline fn disable(action: chance.Action, parent: u4) []const u4 {
        const turns = @field(action, "disable");
        return if (parent > 0 or turns < 1 or turns >= 8) &DISABLE_NONE else &[_]u4{ 0, turns + 1 };
    }

    const CONFUSION_NONE = [_]u3{0};
    const CONFUSION_FORCED = [_]u3{1};

    pub inline fn confusion(action: chance.Action, parent: u4) []const u3 {
        const turns = @field(action, "confusion");
        if (parent > 0 or turns < 1 or turns >= 5) return &CONFUSION_NONE;
        return if (turns < 2) &CONFUSION_FORCED else &[_]u3{ 0, turns + 1 };
    }

    const SLOT_NONE = [_]u4{0};
    // FIXME: depends on possible slots...
    const SLOT = [_]u4{ 1, 2, 3, 4 };

    /// TODO
    pub inline fn moveSlot(action: chance.Action, parent: Optional(bool)) []const u4 {
        if (parent == .false) return &SLOT_NONE;
        return if (@field(action, "move_slot") == 0) &SLOT_NONE else &SLOT;
    }

    const MULTI_NONE = [_]u4{0};
    const MULTI = [_]u4{ 2, 3, 4, 5 };

    /// TODO
    pub inline fn multiHit(action: chance.Action, parent: Optional(bool)) []const u4 {
        if (parent == .false) return &MULTI_NONE;
        return if (@field(action, "multi_hit") == 0) &MULTI_NONE else &MULTI;
    }

    const PSYWAVE_NONE = [_]u8{0};
    const PSYWAVE = init: {
        var rolls: [150]u8 = undefined;
        for (0..150) |i| rolls[i] = i + 1;
        break :init rolls;
    };

    /// TODO use break base on level
    pub inline fn psywave(action: chance.Action, parent: Optional(bool)) []const u8 {
        if (parent == .false) return &PSYWAVE_NONE;
        return if (@field(action, "psywave") == 0) &PSYWAVE_NONE else &PSYWAVE;
    }

    const MOVE_NONE = [_]Move{.None};
    const MOVES = init: {
        var moves: [Move.size - 2]Move = undefined;
        var i: usize = 0;
        for (@typeInfo(Move).Enum.fields) |f| {
            if (!(std.mem.eql(u8, f.name, "None") or
                std.mem.eql(u8, f.name, "Metronome") or
                std.mem.eql(u8, f.name, "Struggle") or
                std.mem.eql(u8, f.name, "SKIP_TURN")))
            {
                moves[i] = @field(Move, f.name);
                i += 1;
            }
        }
        break :init moves;
    };

    /// TODO
    pub inline fn metronome(action: chance.Action) []const Move {
        return if (@field(action, "metronome") == .None) &MOVE_NONE else &MOVES;
    }
};

test Rolls {
    var actions = chance.Actions{ .p1 = .{ .speed_tie = .P2 } };
    try expectEqualSlices(Optional(Player), &.{ .P1, .P2 }, Rolls.speedTie(actions.p1));
    try expectEqualSlices(Optional(Player), &.{.None}, Rolls.speedTie(actions.p2));

    actions = chance.Actions{ .p2 = .{ .damage = 5 } };
    try expectEqual(Rolls.Range{ .min = 0, .max = 1 }, Rolls.damage(actions.p1, .None));
    try expectEqual(Rolls.Range{ .min = 1, .max = 40 }, Rolls.damage(actions.p2, .None));
    try expectEqual(Rolls.Range{ .min = 0, .max = 1 }, Rolls.damage(actions.p2, .false));

    var summaries = calc.Summaries{ .p1 = .{ .damage = .{ .base = 74, .final = 69 } } };
    try expectEqual(@as(u8, 0), try Rolls.coalesce(.P1, 0, &summaries));
    try expectEqual(@as(u8, 25), try Rolls.coalesce(.P1, 22, &summaries));
    summaries.p1.damage.final = 74;
    try expectEqual(@as(u8, 1), try Rolls.coalesce(.P1, 1, &summaries));

    actions = chance.Actions{ .p2 = .{ .hit = .true } };
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.hit(actions.p1, .None));
    try expectEqualSlices(Optional(bool), &.{ .false, .true }, Rolls.hit(actions.p2, .None));
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.hit(actions.p2, .true));
    try expectEqualSlices(Optional(bool), &.{ .false, .true }, Rolls.hit(actions.p2, .false));

    actions = chance.Actions{ .p1 = .{ .secondary_chance = .true } };
    try expectEqualSlices(
        Optional(bool),
        &.{ .false, .true },
        Rolls.secondaryChance(actions.p1, .None),
    );
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.secondaryChance(actions.p1, .false));
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.secondaryChance(actions.p2, .None));

    actions = chance.Actions{ .p1 = .{ .critical_hit = .true } };
    try expectEqualSlices(
        Optional(bool),
        &.{ .false, .true },
        Rolls.criticalHit(actions.p1, .None),
    );
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.criticalHit(actions.p1, .false));
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.criticalHit(actions.p2, .None));

    actions = chance.Actions{ .p2 = .{ .confused = .true } };
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.confused(actions.p1));
    try expectEqualSlices(Optional(bool), &.{ .false, .true }, Rolls.confused(actions.p2));

    actions = chance.Actions{ .p2 = .{ .paralyzed = .true } };
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.paralyzed(actions.p1, .None));
    try expectEqualSlices(Optional(bool), &.{ .false, .true }, Rolls.paralyzed(actions.p2, .None));
    try expectEqualSlices(Optional(bool), &.{ .false, .true }, Rolls.paralyzed(actions.p2, .false));
    try expectEqualSlices(Optional(bool), &.{.None}, Rolls.paralyzed(actions.p2, .true));

    actions = chance.Actions{ .p2 = .{ .duration = 3 } };
    try expectEqualSlices(u1, &.{0}, Rolls.duration(actions.p1, .None));
    try expectEqualSlices(u1, &.{ 0, 1 }, Rolls.duration(actions.p2, .None));
    try expectEqualSlices(u1, &.{0}, Rolls.duration(actions.p2, .false));

    try expectEqualSlices(u3, &.{0}, Rolls.sleep(.{ .sleep = 0 }));
    try expectEqualSlices(u3, &.{0}, Rolls.sleep(.{ .sleep = 7 }));
    try expectEqualSlices(u3, &.{ 0, 5 }, Rolls.sleep(.{ .sleep = 4 }));

    try expectEqualSlices(u4, &.{0}, Rolls.disable(.{ .disable = 0 }, 0));
    try expectEqualSlices(u4, &.{0}, Rolls.disable(.{ .disable = 8 }, 0));
    try expectEqualSlices(u4, &.{0}, Rolls.disable(.{ .disable = 4 }, 1));
    try expectEqualSlices(u4, &.{ 0, 5 }, Rolls.disable(.{ .disable = 4 }, 0));

    try expectEqualSlices(u3, &.{0}, Rolls.confusion(.{ .confusion = 0 }, 0));
    try expectEqualSlices(u3, &.{0}, Rolls.confusion(.{ .confusion = 5 }, 0));
    try expectEqualSlices(u3, &.{0}, Rolls.confusion(.{ .confusion = 3 }, 1));
    try expectEqualSlices(u3, &.{1}, Rolls.confusion(.{ .confusion = 1 }, 0));
    try expectEqualSlices(u3, &.{ 0, 4 }, Rolls.confusion(.{ .confusion = 3 }, 0));

    actions = chance.Actions{ .p2 = .{ .move_slot = 3 } };
    try expectEqualSlices(u4, &.{0}, Rolls.moveSlot(actions.p1, .None));
    try expectEqualSlices(u4, &.{ 1, 2, 3, 4 }, Rolls.moveSlot(actions.p2, .None));
    try expectEqualSlices(u4, &.{0}, Rolls.moveSlot(actions.p2, .false));

    actions = chance.Actions{ .p2 = .{ .multi_hit = 3 } };
    try expectEqualSlices(u4, &.{0}, Rolls.multiHit(actions.p1, .None));
    try expectEqualSlices(u4, &.{ 2, 3, 4, 5 }, Rolls.multiHit(actions.p2, .None));
    try expectEqualSlices(u4, &.{0}, Rolls.multiHit(actions.p2, .false));

    actions = chance.Actions{ .p2 = .{ .metronome = .Surf } };
    try expectEqualSlices(Move, &.{.None}, Rolls.metronome(actions.p1));
    try expectEqual(@intToEnum(Move, 24), Rolls.metronome(actions.p2)[23]);

    actions = chance.Actions{ .p2 = .{ .psywave = 79 } };
    try expectEqualSlices(u8, &.{0}, Rolls.psywave(actions.p1, .None));
    try expectEqual(
        @as(u8, 150),
        Rolls.psywave(actions.p2, .None)[Rolls.psywave(actions.p2, .None).len - 1],
    );
    try expectEqualSlices(u8, &.{0}, Rolls.psywave(actions.p2, .false));
}
