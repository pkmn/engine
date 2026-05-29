const common = @import("../common/data.zig");
const data = @import("data.zig");
const gen1 = @import("../gen1/data.zig");
const options = @import("../common/options.zig");
const rng = @import("../common/rng.zig");
const std = @import("std");

const assert = std.debug.assert;
const Choice = common.Choice;
const DVs = data.DVs;
const Item = data.Item;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const PSRNG = rng.PSRNG;
const showdown = options.showdown;
const Species = data.Species;
const Stats = data.Stats;

pub const Options = struct {
    cleric: bool = showdown,
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
    ) data.Battle(rng.FixedRNG(2, rolls.len)) {
        return .{
            .rng = .{ .rolls = rolls },
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    pub fn random(rand: *PSRNG, opt: Options) data.Battle(data.PRNG) {
        return .{
            .rng = prng(rand),
            .turn = 0,
            .sides = .{ Side.random(rand, opt), Side.random(rand, opt) },
        };
    }
};

pub fn prng(rand: *PSRNG) data.PRNG {
    return .{
        .src = .{
            .seed = if (showdown)
                rand.newSeed()
            else seed: {
                // GLITCH: The initial RNG seed in Gen II link battles is heavily constrained
                // https://www.smogon.com/forums/threads/rng-in-rby-link-battles.3746779
                var seed = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };

                // Bytes in seed can only range from 0-252, not 0-255
                const max: u8 = 253;
                // Instructions take multiples of 4 cycles to execute
                var timer: u16 = 4 * rand.range(u16, 0, 16384);
                var add: u8 = rand.range(u8, 0, 256);
                var sub: u8 = rand.range(u8, 0, 256);
                var carry: u8 = 0;
                var div: u8 = 0;

                var i: usize = 0;
                while (i < seed.len) {
                    div = @intCast(timer >> 8);
                    // This is effectively @addWithOverflow but with three operands
                    const result = @as(u16, add) + @as(u16, div) + @as(u16, carry);
                    add = @intCast(result & 255);
                    carry = @intFromBool(result > 255);
                    timer +%= 44;
                    div = @intCast(timer >> 8);
                    sub -%= div +% carry;

                    if (sub < max) {
                        seed[i] = sub;
                        i += 1;
                        timer +%= 152;
                        carry = 1;
                    } else {
                        timer +%= 132;
                        carry = 0;
                    }
                }
                break :seed seed;
            },
        },
    };
}

pub const Side = struct {
    pub fn init(ps: []const Pokemon) data.Side {
        assert(ps.len > 0 and ps.len <= 6);
        var side = data.Side{};

        for (0..ps.len) |i| {
            side.pokemon[i] = Pokemon.init(ps[i]);
            side.pokemon[i].position = @as(u4, @intCast(i)) + 1;
        }
        return side;
    }

    pub fn random(rand: *PSRNG, opt: Options) data.Side {
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 5 + 1) else 6;
        var side = data.Side{};

        for (0..n) |i| {
            side.pokemon[i] = Pokemon.random(rand, opt);
            side.pokemon[i].position = @as(u4, @intCast(i)) + 1;
        }

        return side;
    }
};

pub const EXP = 0xFFFF;

pub const Pokemon = struct {
    species: Species,
    moves: []const Move,
    item: Item = .None,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,
    dvs: gen1.DVs = .{},
    stats: Stats(u16) = .{ .hp = EXP, .atk = EXP, .def = EXP, .spe = EXP, .spa = EXP, .spd = EXP },

    pub fn init(p: Pokemon) data.Pokemon {
        var pokemon = data.Pokemon{};
        pokemon.species = p.species;
        const species = Species.get(p.species);
        inline for (if (@hasField(@TypeOf(@typeInfo(@TypeOf(pokemon.stats)).@"struct"), "fields"))
            @typeInfo(@TypeOf(pokemon.stats)).@"struct".fields
        else
            @typeInfo(@TypeOf(pokemon.stats)).@"struct".field_names) |field|
        {
            const field_name = if (@hasField(@TypeOf(field), "name")) field.name else field;
            const hp = comptime std.mem.eql(u8, field_name, "hp");
            const spc =
                comptime std.mem.eql(u8, field_name, "spa") or std.mem.eql(u8, field_name, "spd");
            @field(pokemon.stats, field_name) = Stats(u16).calc(
                field_name,
                @field(species.stats, field_name),
                if (hp) p.dvs.hp() else if (spc) p.dvs.spc else @field(p.dvs, field_name),
                @field(p.stats, field_name),
                p.level,
            );
        }
        assert(p.moves.len > 0 and p.moves.len <= 4);
        for (p.moves, 0..) |m, j| {
            pokemon.moves[j].id = m;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            pokemon.moves[j].pp = @intCast(@min(Move.pp(m) / 5 * 8, 61));
        }
        pokemon.item = p.item;
        if (p.hp) |hp| {
            pokemon.hp = hp;
        } else {
            pokemon.hp = pokemon.stats.hp;
        }
        pokemon.status = p.status;
        pokemon.types = species.types;
        pokemon.level = p.level;
        pokemon.dvs = DVs.from(p.species, p.dvs);
        return pokemon;
    }

    pub fn random(rand: *PSRNG, opt: Options) data.Pokemon {
        const s: Species = @enumFromInt(rand.range(u8, 1, Species.size + 1));
        const species = Species.get(s);
        const lvl = if (rand.chance(u8, 1, 20)) rand.range(u8, 1, 99 + 1) else 100;
        // Pokémon Showdown does not support most items without in-battle held item effects
        const max_item = @intFromEnum(if (showdown) Item.FlowerMail else Item.TM50);
        const item = if (rand.chance(u8, 1, 10)) 0 else rand.range(u8, 1, max_item + 1);

        var stats: Stats(u16) = .{};
        const dvs = gen1.DVs.random(rand);
        inline for (if (@hasField(@TypeOf(@typeInfo(@TypeOf(stats)).@"struct"), "fields"))
            @typeInfo(@TypeOf(stats)).@"struct".fields
        else
            @typeInfo(@TypeOf(stats)).@"struct".field_names) |field|
        {
            const field_name = if (@hasField(@TypeOf(field), "name")) field.name else field;
            const hp = std.mem.eql(u8, field_name, "hp");
            const spc = std.mem.eql(u8, field_name, "spa") or std.mem.eql(u8, field_name, "spd");
            @field(stats, field_name) = Stats(u16).calc(
                field_name,
                @field(species.stats, field_name),
                if (hp) dvs.hp() else if (spc) dvs.spc else @field(dvs, field_name),
                if (rand.chance(u8, 1, 20)) rand.range(u8, 0, 255 + 1) else 255,
                lvl,
            );
        }

        var ms: [4]MoveSlot = @splat(.{});
        const n = if (rand.chance(u8, 1, 100)) rand.range(u4, 1, 3 + 1) else 4;
        for (0..n) |i| {
            var m: Move = .None;
            sample: while (true) {
                m = @enumFromInt(rand.range(u8, 1, 164 + 1));
                for (0..i) |j| if (ms[j].id == m) continue :sample;
                break;
            }
            const pp_ups: u8 =
                if (!opt.cleric and rand.chance(u8, 1, 10)) rand.range(u2, 0, 2 + 1) else 3;
            // NB: PP can be at most 61 legally (though can overflow to 63)
            const max_pp: u8 = @intCast(Move.pp(m) + pp_ups * @min(Move.pp(m) / 5, 7));
            ms[i] = .{
                .id = m,
                .pp = if (opt.cleric) max_pp else rand.range(u8, 0, max_pp + 1),
            };
        }
        return .{
            .species = s,
            .types = species.types,
            .dvs = DVs.from(s, dvs),
            .level = lvl,
            .stats = stats,
            .hp = if (opt.cleric) stats.hp else rand.range(u16, 0, stats.hp + 1),
            .status = if (!opt.cleric and rand.chance(u8, 1, 6 + 1))
                0 | (@as(u8, 1) << rand.range(u3, 1, 6 + 1))
            else
                0,
            .happiness = if (rand.chance(u8, 1, 10 + 1)) rand.range(u8, 0, 255) else 255,
            .item = item,
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
