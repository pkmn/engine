const std = @import("std");

const common = @import("../common/data.zig");
const options = @import("../common/options.zig").options;
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const Choice = common.Choice;

const showdown = options.showdown;

const PSRNG = rng.PSRNG;

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
        seed: u64,
        p1: []const Pokemon,
        p2: []const Pokemon,
    ) data.Battle(data.PRNG) {
        return .{
            .rng = prng(&PSRNG.init(seed), true),
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

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

    pub fn random(rand: *PSRNG, initial: bool) data.Battle(data.PRNG) {
        var p1: u4 = 0;
        var p2: u4 = 0;
        var battle: data.Battle(data.PRNG) = .{
            .rng = prng(rand, initial),
            .turn = if (initial) 0 else rand.range(u16, 1, 1000 + 1),
            .last_damage = if (initial) 0 else rand.range(u16, 1, 704 + 1),
            .sides = .{ Side.random(rand, &p1, initial), Side.random(rand, &p2, initial) },
        };
        battle.last_selected_indexes.p1 = p1;
        battle.last_selected_indexes.p2 = p2;
        return battle;
    }
};

fn prng(rand: *PSRNG, initial: bool) data.PRNG {
    // GLITCH: initial bytes in seed can only range from 0-252, not 0-255
    const max: u9 = if (initial) 253 else 256;
    return .{
        .src = .{
            .seed = if (showdown)
                rand.newSeed()
            else .{
                rand.range(u8, 0, max), rand.range(u8, 0, max),
                rand.range(u8, 0, max), rand.range(u8, 0, max),
                rand.range(u8, 0, max), rand.range(u8, 0, max),
                rand.range(u8, 0, max), rand.range(u8, 0, max),
                rand.range(u8, 0, max), rand.range(u8, 0, max),
            },
        },
    };
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

    pub fn random(rand: *PSRNG, index: *u4, initial: bool) data.Side {
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 5 + 1) else 6;
        var side = data.Side{};

        var i: u4 = 0;
        while (i < n) : (i += 1) {
            side.pokemon[i] = Pokemon.random(rand, initial);
            side.order[i] = i + 1;
            var pokemon = &side.pokemon[i];
            if (initial) continue;

            var j: u4 = 0;
            while (j < 4) : (j += 1) {
                if (rand.chance(u8, 1, 5 + (@as(u8, i) * 2))) {
                    side.last_selected_move = pokemon.moves[j].id;
                    index.* = j;
                }
                if (rand.chance(u8, 1, 5 + (@as(u8, i) * 2))) {
                    side.last_used_move = pokemon.moves[j].id;
                }
            }
            if (i == 0) {
                var active = &side.active;
                active.stats = pokemon.stats;
                inline for (std.meta.fields(@TypeOf(active.boosts))) |field| {
                    if (field.field_type != u4) continue;
                    if (rand.chance(u8, 1, 10)) {
                        @field(active.boosts, field.name) =
                            @truncate(i4, @as(i5, rand.range(u4, 0, 12 + 1)) - 6);
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
                    if (comptime std.mem.eql(u8, field.name, "Transform")) continue;
                    if (rand.chance(u8, 1, 18)) {
                        @field(volatiles, field.name) = true;
                        if (std.mem.eql(u8, field.name, "Bide")) {
                            volatiles.state = rand.range(u16, 1, active.stats.hp);
                        } else if (std.mem.eql(u8, field.name, "Trapping")) {
                            volatiles.attacks = rand.range(u3, 0, 4 + 1);
                        } else if (std.mem.eql(u8, field.name, "Thrashing")) {
                            volatiles.attacks = rand.range(u3, 0, 4 + 1);
                            volatiles.state =
                                if (rand.chance(u8, 1, 10)) rand.range(u8, 1, 255 + 1) else 0;
                        } else if (std.mem.eql(u8, field.name, "Rage")) {
                            volatiles.state =
                                if (rand.chance(u8, 1, 10)) rand.range(u8, 1, 255 + 1) else 0;
                        } else if (std.mem.eql(u8, field.name, "Confusion")) {
                            volatiles.confusion = rand.range(u3, 1, 5 + 1);
                        } else if (std.mem.eql(u8, field.name, "Toxic")) {
                            pokemon.status = Status.init(Status.PSN);
                            volatiles.toxic = rand.range(u4, 1, 15 + 1);
                        } else if (std.mem.eql(u8, field.name, "Substitute")) {
                            volatiles.substitute =
                                rand.range(u8, 1, @truncate(u8, active.stats.hp / 4) + 1);
                        }
                    }
                }
                if (rand.chance(u8, 1, 20)) {
                    const m = rand.range(u4, 0, 4);
                    if (active.moves[m].id != .None) {
                        volatiles.disabled = .{
                            .move = m,
                            .duration = rand.range(u4, 1, 5 + 1),
                        };
                    }
                }
            }
        }

        return side;
    }
};

const EXP = 0xFFFF;

pub const Pokemon = struct {
    species: Species,
    moves: []const Move,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,
    stats: Stats(u16) = .{ .hp = EXP, .atk = EXP, .def = EXP, .spe = EXP, .spc = EXP },

    pub fn init(p: Pokemon) data.Pokemon {
        var pokemon = data.Pokemon{};
        pokemon.species = p.species;
        const species = Species.get(p.species);
        inline for (std.meta.fields(@TypeOf(pokemon.stats))) |field| {
            @field(pokemon.stats, field.name) = Stats(u16).calc(
                field.name,
                @field(species.stats, field.name),
                0xF,
                @field(p.stats, field.name),
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
        pokemon.types = species.types;
        pokemon.level = p.level;
        return pokemon;
    }

    pub fn random(rand: *PSRNG, initial: bool) data.Pokemon {
        const s = @intToEnum(Species, rand.range(u8, 1, 151 + 1));
        const species = Species.get(s);
        const lvl = if (rand.chance(u8, 1, 20)) rand.range(u8, 1, 99 + 1) else 100;
        var stats: Stats(u16) = .{};
        const dvs = DVs.random(rand);
        inline for (std.meta.fields(@TypeOf(stats))) |field| {
            @field(stats, field.name) = Stats(u16).calc(
                field.name,
                @field(species.stats, field.name),
                if (field.field_type != u4) dvs.hp() else @field(dvs, field.name),
                if (rand.chance(u8, 1, 20)) rand.range(u8, 0, 255 + 1) else 255,
                lvl,
            );
        }

        var ms = [_]MoveSlot{.{}} ** 4;
        var i: u4 = 0;
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 3 + 1) else 4;
        while (i < n) : (i += 1) {
            var m: Move = .None;
            sample: while (true) {
                m = @intToEnum(Move, rand.range(u8, 1, 165 + 1));
                var j: u4 = 0;
                while (j < i) : (j += 1) {
                    if (ms[j].id == m) continue :sample;
                    if (showdown and blocked(m)) continue :sample;
                }
                break;
            }
            const pp_ups =
                if (!initial and rand.chance(u8, 1, 10)) rand.range(u2, 0, 2 + 1) else 3;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            const max_pp = @truncate(u8, @minimum(Move.pp(m) / 5 * (5 + @as(u8, pp_ups)), 61));
            ms[i] = .{
                .id = m,
                .pp = if (initial) max_pp else rand.range(u8, 0, max_pp + 1),
            };
        }

        return .{
            .species = s,
            .types = species.types,
            .level = lvl,
            .stats = stats,
            .hp = if (initial) stats.hp else rand.range(u16, 0, stats.hp + 1),
            // TODO: SLF
            .status = if (!initial and rand.chance(u8, 1, 6 + 1))
                0 | (@as(u8, 1) << rand.range(u3, 1, 6 + 1))
            else
                0,
            .moves = ms,
        };
    }
};

// cat src/test/blocklist.json | jq '."1".moves'
fn blocked(m: Move) bool {
    if (Move.get(m).effect == .Trapping) return true;
    return switch (m) {
        .Bind, .Counter, .Mimic, .Haze, .Bide, .Metronome, .MirrorMove => true,
        else => false,
    };
}

pub fn move(slot: u4) Choice {
    return .{ .type = .Move, .data = slot };
}

pub fn swtch(slot: u4) Choice {
    return .{ .type = .Switch, .data = slot };
}
