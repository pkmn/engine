const std = @import("std");
const pkmn = @import("pkmn");

/// .pkmn.gen1.Pokemon{
///    .species = .Moltres,
///    .types = .{ .type1 = .Fire, .type2 = .Flying },
///    .stats = .{ .hp = 323, .atk = 238, .def = 217, .spe = 218, .spc = 288 },
///    .moves = {
///        .{ .id = .Flamethrower, .pp = 24 },
///        .{ .id = .Scratch, .pp = 56 },
///        .{ .id = .SwordsDance, .pp = 48 },
///        .{ .id = .Clamp, .pp = 16 }
///    },
///    .hp = 323,
///    .status = 16,
///}
pub fn simulate(gen: u8, num: usize, seed: u64) !void {
    std.debug.assert(gen >= 1 and gen <= 8);

    var random = pkmn.rng.Random.init(seed);

    var options: [pkmn.MAX_OPTIONS_SIZE]pkmn.Choice = undefined;

    var i: usize = 0;
    while (i <= num) : (i += 1) {
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, true),
            else => unreachable, // TODO
        };

        var c1 = pkmn.Choice{};
        var c2 = pkmn.Choice{};

        var result = try battle.update(c1, c2, null);
        while (result.type == .None) : (result = try battle.update(c1, c2, null)) {
            c1 = options[random.range(0, battle.choices(.P1, result.p1, options))];
            c2 = options[random.range(0, battle.choices(.P2, result.p2, options))];
        }

        const msg = switch (result.type) {
            .Win => "won by Player A",
            .Lose => "won by Player B",
            .Tie => "ended in a tie",
            .Error => "encountered an error",
            else => unreachable,
        };

        try std.debug.print("Battle {d} {s} after {d} turns", .{ i + 1, msg, battle.turn });
    }
}
