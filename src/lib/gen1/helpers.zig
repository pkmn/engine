const std = @import("std");
const build_options = @import("build_options");

const common = @import("../common/data.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const showdown = build_options.showdown;

const Choice = common.Choice;

const Random = rng.Random;

const DVs = data.DVs;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;

const ArgType = protocol.ArgType;
const Log = protocol.Log(std.io.FixedBufferStream([]u8).Writer);

pub const Battle = struct {
    pub fn init(
        comptime rolls: anytype,
        p1: []const Pokemon,
        p2: []const Pokemon,
    ) data.Battle(rng.FixedRNG(1, rolls.len)) {
        return .{
            .rng = .{ .rolls = rolls },
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    pub fn random(rand: *Random, initial: bool) data.Battle(rng.PRNG(1)) {
        return .{
            .rng = prng(rand),
            .turn = if (initial) 0 else rand.range(u16, 1, 1000),
            .last_damage = if (initial) 0 else rand.range(u16, 1, 704),
            .sides = .{ Side.random(rand, initial), Side.random(rand, initial) },
        };
    }
};

fn prng(rand: *Random) rng.PRNG(1) {
    return .{ .src = .{ .seed = if (build_options.showdown) rand.int(u64) else .{
        rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8),
        rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8), rand.int(u8),
    } } };
}

pub const Side = struct {
    pub fn init(ps: []const Pokemon) data.Side {
        assert(ps.len > 0 and ps.len <= 6);
        var side = data.Side{};

        var i: u4 = 0;
        while (i < ps.len) : (i += 1) {
            side.pokemon[i] = Pokemon.init(ps[i]);
            side.order[i] = i + 1;
        }
        return side;
    }

    pub fn random(rand: *Random, initial: bool) data.Side {
        const n = if (rand.chance(1, 100)) rand.range(u4, 1, 5) else 6;
        var side = data.Side{};

        var i: u4 = 0;
        while (i < n) : (i += 1) {
            side.pokemon[i] = Pokemon.random(rand, initial);
            side.order[i] = i + 1;
            var pokemon = &side.pokemon[i];
            var j: u4 = 0;
            while (j < 4) : (j += 1) {
                if (!initial and rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_selected_move = pokemon.moves[j].id;
                }
                if (!initial and rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_used_move = pokemon.moves[j].id;
                }
            }
            if (!initial and i == 0) {
                var active = &side.active;
                active.stats = pokemon.stats;
                inline for (std.meta.fields(@TypeOf(active.boosts))) |field| {
                    if (rand.chance(1, 10)) {
                        @field(active.boosts, field.name) = rand.range(i4, -6, 6);
                    }
                }
                active.species = pokemon.species;
                for (pokemon.moves) |m, k| {
                    active.moves[k] = m;
                }
                active.types = pokemon.types;
                var volatiles = &active.volatiles;
                inline for (std.meta.fields(@TypeOf(active.volatiles))) |field| {
                    if (field.field_type != bool) continue;
                    if (rand.chance(1, 18)) {
                        @field(volatiles, field.name) = true;
                        if (std.mem.eql(u8, field.name, "Bide")) {
                            volatiles.data.state = rand.range(u16, 1, active.stats.hp - 1);
                        } else if (std.mem.eql(u8, field.name, "Trapping")) {
                            volatiles.data.attacks = rand.range(u4, 0, 4);
                        } else if (std.mem.eql(u8, field.name, "Thrashing")) {
                            volatiles.data.attacks = rand.range(u4, 0, 4);
                            volatiles.data.state = if (rand.chance(1, 10)) rand.range(u8, 1, 255) else 0;
                        } else if (std.mem.eql(u8, field.name, "Rage")) {
                            volatiles.data.attacks = 0; // TODO
                            volatiles.data.state = if (rand.chance(1, 10)) rand.range(u8, 1, 255) else 0;
                        } else if (std.mem.eql(u8, field.name, "Confusion")) {
                            volatiles.data.confusion = rand.range(u4, 1, 5);
                        } else if (std.mem.eql(u8, field.name, "Toxic")) {
                            pokemon.status = Status.init(Status.PSN);
                            volatiles.data.toxic = rand.range(u4, 1, 15);
                        } else if (std.mem.eql(u8, field.name, "Substitute")) {
                            volatiles.data.substitute =
                                rand.range(u8, 1, @truncate(u8, active.stats.hp / 4));
                        }
                    }
                }
                if (rand.chance(1, 20)) {
                    const m = rand.range(u4, 1, 4);
                    if (active.moves[m].id != .None) {
                        volatiles.data.disabled = .{
                            .move = m,
                            .duration = rand.range(u4, 1, 5),
                        };
                    }
                }
            }
        }

        return side;
    }
};

pub const Pokemon = struct {
    species: Species,
    moves: []const Move,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,

    pub fn init(p: Pokemon) data.Pokemon {
        var pokemon = data.Pokemon{};
        pokemon.species = p.species;
        const specie = Species.get(p.species);
        inline for (std.meta.fields(@TypeOf(pokemon.stats))) |field| {
            @field(pokemon.stats, field.name) = Stats(u16).calc(
                field.name,
                @field(specie.stats, field.name),
                0xF,
                0xFFFF,
                p.level,
            );
        }
        assert(p.moves.len > 0 and p.moves.len <= 4);
        for (p.moves) |m, j| {
            pokemon.moves[j].id = m;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            pokemon.moves[j].pp = @truncate(u8, @minimum(Move.pp(m) / 5 * 8, 61));
        }
        if (p.hp) |hp| {
            pokemon.hp = hp;
        } else {
            pokemon.hp = pokemon.stats.hp;
        }
        pokemon.status = p.status;
        pokemon.types = specie.types;
        pokemon.level = p.level;
        return pokemon;
    }

    pub fn random(rand: *Random, initial: bool) data.Pokemon {
        const s = @intToEnum(Species, rand.range(u8, 1, 151));
        const specie = Species.get(s);
        const lvl = if (rand.chance(1, 20)) rand.range(u8, 1, 99) else 100;
        var stats: Stats(u16) = .{};
        const dvs = DVs.random(rand);
        inline for (std.meta.fields(@TypeOf(stats))) |field| {
            @field(stats, field.name) = Stats(u16).calc(
                field.name,
                @field(specie.stats, field.name),
                if (field.field_type != u4) dvs.hp() else @field(dvs, field.name),
                if (rand.chance(1, 20)) rand.range(u8, 0, 255) else 255,
                lvl,
            );
        }

        var ms = [_]MoveSlot{.{}} ** 4;
        var i: u4 = 0;
        const n = if (rand.chance(1, 100)) rand.range(u4, 1, 3) else 4;
        while (i < n) : (i += 1) {
            var m: Move = .None;
            sample: while (true) {
                m = @intToEnum(Move, rand.range(u8, 1, 165));
                var j: u4 = 0;
                while (j < i) : (j += 1) {
                    if (ms[j].id == m) continue :sample;
                }
                break;
            }
            const pp_ups = if (!initial and rand.chance(1, 10)) rand.range(u2, 0, 2) else 3;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            const max_pp = @truncate(u8, @minimum(Move.pp(m) / 5 * (5 + @as(u8, pp_ups)), 61));
            ms[i] = .{
                .id = m,
                .pp = if (initial) max_pp else rand.range(u8, 0, max_pp),
            };
        }

        return .{
            .species = s,
            .types = specie.types,
            .level = lvl,
            .stats = stats,
            .hp = if (initial) stats.hp else rand.range(u16, 0, stats.hp),
            .status = if (!initial and rand.chance(1, 6))
                0 | (@as(u8, 1) << rand.range(u3, 1, 6))
            else
                0,
            .moves = ms,
        };
    }
};

pub fn move(slot: u4) Choice {
    return .{ .type = .Move, .data = slot };
}

pub fn swtch(slot: u4) Choice {
    return .{ .type = .Switch, .data = slot };
}
