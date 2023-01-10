const std = @import("std");

const common = @import("../common/data.zig");
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

// TODO: switch to @min when min Zig version >= 0.10.0
const minimum = std.math.min;

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

pub const Options = struct {
    cleric: bool = showdown,
    block: bool = showdown,
};

pub const Battle = struct {
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

    pub fn random(rand: *PSRNG, opt: Options) data.Battle(data.PRNG) {
        var p1: u4 = 0;
        var p2: u4 = 0;
        var battle: data.Battle(data.PRNG) = .{
            .rng = prng(rand),
            .turn = 0,
            .last_damage = 0,
            .sides = .{ Side.random(rand, opt), Side.random(rand, opt) },
        };
        battle.last_selected_indexes.p1 = p1;
        battle.last_selected_indexes.p2 = p2;
        return battle;
    }
};

pub fn prng(rand: *PSRNG) data.PRNG {
    // GLITCH: initial bytes in seed can only range from 0-252, not 0-255
    const max: u8 = 253;
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

    pub fn random(rand: *PSRNG, opt: Options) data.Side {
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 5 + 1) else 6;
        var side = data.Side{};

        var i: u4 = 0;
        while (i < n) : (i += 1) {
            side.pokemon[i] = Pokemon.random(rand, opt);
            side.order[i] = i + 1;
        }

        return side;
    }
};

pub const EXP = 0xFFFF;

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
            pokemon.moves[j].pp = @truncate(u8, minimum(Move.pp(m) / 5 * 8, 61));
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

    pub fn random(rand: *PSRNG, opt: Options) data.Pokemon {
        const s = @intToEnum(Species, rand.range(u8, 1, Species.size + 1));
        const species = Species.get(s);
        const lvl = if (rand.chance(u8, 1, 20)) rand.range(u8, 1, 99 + 1) else 100;
        var stats: Stats(u16) = .{};
        const dvs = DVs.random(rand);
        inline for (std.meta.fields(@TypeOf(stats))) |field| {
            @field(stats, field.name) = Stats(u16).calc(
                field.name,
                @field(species.stats, field.name),
                if (comptime std.mem.eql(u8, field.name, "hp"))
                    dvs.hp()
                else
                    @field(dvs, field.name),
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
                m = @intToEnum(Move, rand.range(u8, 1, Move.size - 1 + 1));
                if (opt.block and blocked(m)) continue :sample;
                var j: u4 = 0;
                while (j < i) : (j += 1) {
                    if (ms[j].id == m) continue :sample;
                }
                break;
            }
            const pp_ups =
                if (!opt.cleric and rand.chance(u8, 1, 10)) rand.range(u2, 0, 2 + 1) else 3;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            const max_pp = @truncate(u8, minimum(Move.pp(m) / 5 * (5 + @as(u8, pp_ups)), 61));
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

// cat src/test/blocklist.json | jq '."1".moves'
fn blocked(m: Move) bool {
    if (Move.get(m).effect == .Trapping) return true;
    return switch (m) {
        .Bind,
        .Counter,
        .Mimic,
        .Metronome,
        .MirrorMove,
        .Transform,
        => true,
        else => false,
    };
}

pub fn move(slot: u4) Choice {
    return .{ .type = .Move, .data = slot };
}

pub fn swtch(slot: u4) Choice {
    return .{ .type = .Switch, .data = slot };
}
