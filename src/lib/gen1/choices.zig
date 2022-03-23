const std = @import("std");

const rng = @import("common").rng;

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const expectEqualSlices = std.testing.expectEqualSlices;

const Random = rng.Random;

const Choice = data.Choice;
const Player = data.Player;

const Battle = helpers.Battle;
const move = helpers.move;
const swtch = helpers.swtch;

pub fn choices(battle: anytype, player: Player, request: Choice.Type, out: []Choice) u8 {
    var n: u8 = 0;
    switch (request) {
        .Pass => {
            out[n] = .{};
            n += 1;
        },
        .Switch => {
            const side = battle.side(player);
            var slot: u4 = 2;
            while (slot <= 6) : (slot += 1) {
                const pokemon = side.get(slot);
                if (pokemon.hp == 0) continue;
                out[n] = swtch(slot);
                n += 1;
            }
            if (n == 0) {
                out[n] = .{};
                n += 1;
            }
        },
        .Move => {
            const side = battle.side(player);
            const foe = battle.foe(player);
            const active = side.active;

            if (!foe.active.volatiles.Trapping) {
                var slot: u4 = 2;
                while (slot <= 6) : (slot += 1) {
                    const pokemon = side.get(slot);
                    if (pokemon.hp == 0) continue;
                    out[n] = swtch(slot);
                    n += 1;
                }
            }

            _ = active;
        },
    }
    return n;
}

test "choices" {
    var random = Random.init(0x31415926);
    var battle = Battle.random(&random, false);
    var options = [_]Choice{.{}} ** 10;
    const n = choices(&battle, .P1, .Move, &options);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2),
        swtch(3),
        swtch(4),
        swtch(5),
        swtch(6),
        // TODO
        // move(1),
        // move(2),
        // move(3),
        // move(4),
    }, options[0..n]);
}
