const std = @import("std");

const rng = @import("../common/rng.zig");

const data = @import("data.zig");
const helpers = @import("helpers.zig");

const assert = std.debug.assert;
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

            var active = side.active;

            if (active.volatiles.Recharging) {
                out[n] = move(0); // recharge
                n += 1;
                return n;
            }

            if (!foe.active.volatiles.Trapping) {
                var slot: u4 = 2;
                while (slot <= 6) : (slot += 1) {
                    const pokemon = side.get(slot);
                    if (pokemon.hp == 0) continue;
                    out[n] = swtch(slot);
                    n += 1;
                }
            }

            const before = n;
            var slot: u4 = 1;
            while (slot <= 4) : (slot += 1) {
                const m = active.move(slot);
                if (m.id == .None) break;
                // TODO: Wrap at 0 PP
                if (m.pp == 0 or active.volatiles.data.disabled.move == slot) continue;
                out[n] = move(slot);
                n += 1;
            }
            if (n == before) {
                out[n] = move(0); // Struggle
                n += 1;
            }
        },
    }
    return n;
}

test "choices" {
    var random = Random.init(0x31415926);
    var battle = Battle.random(&random, false);
    var options: [10]Choice = undefined;
    const n = choices(&battle, .P1, .Move, &options);
    try expectEqualSlices(Choice, &[_]Choice{
        swtch(2),
        swtch(3),
        swtch(4),
        swtch(5),
        swtch(6),
        move(1),
        move(2),
        move(3),
        move(4),
    }, options[0..n]);
}
