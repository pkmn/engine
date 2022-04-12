const std = @import("std");
const pkmn = @import("pkmn");

const Timer = std.time.Timer;

pub fn benchmark(gen: u8, battles: usize, playouts: usize, seed: u64) !void {
    std.debug.assert(gen >= 1 and gen <= 8);

    var random = pkmn.PRNG.init(seed);
    var options: [pkmn.MAX_OPTIONS_SIZE]pkmn.Choice = undefined;

    var duration: u64 = 0;
    var turns: usize = 0;

    var i: usize = 0;
    while (i <= battles) : (i += 1) {
        var original = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, true),
            // TODO: support additional generations
            else => unreachable,
        };

        var j: usize = 0;
        while (j <= playouts) : (j += 1) {
            var battle = original;

            var c1 = pkmn.Choice{};
            var c2 = pkmn.Choice{};

            var timer = Timer.start();
            var result = try battle.update(c1, c2, null);
            while (result.type == .None) : (result = try battle.update(c1, c2, null)) {
                c1 = options[random.range(u8, 0, battle.choices(.P1, result.p1, options))];
                c2 = options[random.range(u8, 0, battle.choices(.P2, result.p2, options))];
            }
            duration += timer.read();
            turns += battle.turn;
        }
    }

    std.io.getStdout().print("{d},{d},{d}\n", .{ duration, turns, random.src.seed });
}
