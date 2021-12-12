const std = @import("std");

const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig"); // DEBUG

const data = @import("data.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const Random = rng.Random;

const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;
const Moves = data.Moves;
const MoveSlot = data.MoveSlot;

pub const Battle = struct {
    pub fn init(seed: u8, p1: []const Pokemon, p2: []const Pokemon) data.Battle {
        return .{
            .rng = rng.Gen12{ .seed = seed },
            .sides = .{ Side.init(p1), Side.init(p2) },
        };
    }

    pub fn random(rand: *Random) data.Battle {
        return .{
            .rng = .{ .seed = rand.int(u8) },
            .turn = rand.range(u16, 1, 1000),
            .last_damage = rand.range(u16, 1, 704),
            .sides = .{ Side.random(rand), Side.random(rand) },
        };
    }
};

pub const Side = struct {
    pub fn init(ps: []const Pokemon) data.Side {
        assert(ps.len > 0 and ps.len <= 6);
        var side = data.Side{};

        var i: u4 = 0;
        while (i < ps.len) : (i += 1) {
            const p = ps[i];
            var pokemon = &side.team[i];
            pokemon.species = p.species;
            const specie = Species.get(p.species);
            inline for (std.meta.fields(@TypeOf(pokemon.stats))) |field| {
                @field(pokemon.stats, field.name) = Stats(u12).calc(
                    field.name,
                    @field(specie.stats, field.name),
                    0xF,
                    0xFFFF,
                    p.level,
                );
            }
            pokemon.position = i + 1;
            assert(p.moves.len > 0 and p.moves.len <= 4);
            for (p.moves) |move, j| {
                pokemon.moves[j].id = move;
                pokemon.moves[j].pp = @truncate(u6, Moves.pp(move) / 5 * 8);
            }
            if (p.hp) |hp| {
                pokemon.hp = hp;
            } else {
                pokemon.hp = pokemon.stats.hp;
            }
            pokemon.status = p.status;
            pokemon.types = specie.types;
            pokemon.level = p.level;
            if (i == 0) {
                var active = &side.pokemon;
                inline for (std.meta.fields(@TypeOf(active.stats))) |field| {
                    @field(active.stats, field.name) = @field(pokemon.stats, field.name);
                }
                active.level = pokemon.level;
                active.hp = pokemon.hp;
                active.status = pokemon.status;
                active.species = pokemon.species;
                active.types = pokemon.types;
                for (pokemon.moves) |move, j| {
                    active.moves[j] = move;
                }
            }
        }
        return side;
    }

    pub fn random(rand: *Random) data.Side {
        const n = if (rand.chance(1, 100)) rand.range(u4, 1, 5) else 6;
        var side = data.Side{ .active = 1 };

        var i: u4 = 0;
        while (i < n) : (i += 1) {
            side.team[i] = Pokemon.random(rand);
            const pokemon = &side.team[i];
            pokemon.position = i + 1;
            var j: u4 = 0;
            while (j < 4) : (j += 1) {
                if (rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_selected_move = side.team[i].moves[j].id;
                }
                if (rand.chance(1, 5 + (@as(u8, i) * 2))) {
                    side.last_used_move = side.team[i].moves[j].id;
                }
            }
            if (i == 0) {
                side.active = 1;
                var active = &side.pokemon;
                inline for (std.meta.fields(@TypeOf(active.stats))) |field| {
                    @field(active.stats, field.name) = @field(pokemon.stats, field.name);
                }
                inline for (std.meta.fields(@TypeOf(active.boosts))) |field| {
                    if (rand.chance(1, 10)) {
                        @field(active.boosts, field.name) = rand.range(i4, -6, 6);
                    }
                }
                active.level = pokemon.level;
                active.hp = pokemon.hp;
                active.status = pokemon.status;
                active.species = pokemon.species;
                active.types = pokemon.types;
                for (pokemon.moves) |move, k| {
                    active.moves[k] = move;
                }
                inline for (std.meta.fields(@TypeOf(active.volatiles))) |field| {
                    if (field.field_type != bool) continue;
                    if (rand.chance(1, 18)) {
                        @field(active.volatiles, field.name) = true;
                        switch (field.name[0]) {
                            'B' => {
                                active.volatiles.data.bide =
                                    rand.range(u16, 1, active.stats.hp - 1);
                            },
                            'C' => {
                                if (std.mem.eql(u8, field.name, "Confusion")) {
                                    active.volatiles.data.confusion = rand.range(u4, 1, 5);
                                }
                            },
                            'T' => {
                                if (std.mem.eql(u8, field.name, "Toxic")) {
                                    active.status = Status.init(Status.PSN);
                                    pokemon.status = active.status;
                                    active.volatiles.data.toxic = rand.range(u4, 1, 15);
                                }
                            },
                            'S' => {
                                active.volatiles.data.substitute =
                                    rand.range(u8, 1, @truncate(u8, active.stats.hp / 4));
                            },
                            else => {},
                        }
                    }
                }
                if (rand.chance(1, 20)) {
                    const m = rand.range(u4, 1, 4);
                    if (active.moves[m].id != .None) {
                        active.volatiles.data.disabled = .{
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
    moves: []const Moves,
    hp: ?u16 = null,
    status: u8 = 0,
    level: u8 = 100,

    pub fn random(rand: *Random) data.Pokemon {
        const s = @intToEnum(Species, rand.range(u8, 1, 151));
        const specie = Species.get(s);
        const lvl = if (rand.chance(1, 20)) rand.range(u8, 1, 99) else 100;
        var stats: Stats(u12) = .{};
        const dvs = DVs.random(rand);
        inline for (std.meta.fields(@TypeOf(stats))) |field| {
            @field(stats, field.name) = Stats(u12).calc(
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
            var move: Moves = .None;
            sample: while (true) {
                move = @intToEnum(Moves, rand.range(u8, 1, 165));
                var j: u4 = 0;
                while (j < i) : (j += 1) {
                    if (ms[j].id == move) continue :sample;
                }
                break;
            }
            const pp_ups = if (rand.chance(1, 10)) rand.range(u2, 0, 2) else 3;
            const max_pp = @truncate(u6, Moves.pp(move) / 5 * (5 + @as(u8, pp_ups)));
            ms[i] = .{
                .id = move,
                .pp = rand.range(u6, 0, max_pp),
                .pp_ups = pp_ups,
            };
        }

        return .{
            .species = s,
            .types = specie.types,
            .level = lvl,
            .stats = stats,
            .hp = rand.range(u16, 0, stats.hp),
            .status = if (rand.chance(1, 6)) 0 | (@as(u8, 1) << rand.range(u3, 1, 6)) else 0,
            .moves = ms,
        };
    }
};

const DVs = struct {
    atk: u4 = 15,
    def: u4 = 15,
    spe: u4 = 15,
    spc: u4 = 15,

    pub fn hp(self: *const DVs) u4 {
        return (self.atk & 1) << 3 | (self.def & 1) << 2 | (self.spe & 1) << 1 | (self.spc & 1);
    }

    pub fn random(rand: *Random) DVs {
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

test "Battle" {
    // const p1 = .{ .species = .Gengar, .moves = &.{ .Absorb, .Pound, .DreamEater, .Psychic } };
    // const p2 = .{ .species = .Mew, .moves = &.{ .HydroPump, .Surf, .Bubble, .WaterGun } };
    // const battle = Battle.init(0, &.{p1}, &.{p2});
    // util.debug.print(battle);
    // var r = std.rand.DefaultPrng.init(5);
    // util.debug.print(Battle.random(Random.init(r.random())));
    util.debug.print(Battle.random(&Random.init(5)));
}

comptime {
    _ = @import("data.zig");
}
