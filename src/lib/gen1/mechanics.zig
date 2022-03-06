const std = @import("std");
const build_options = @import("build_options");

const rng = @import("../common/rng.zig");

const data = @import("./data.zig");
const protocol = @import("./protocol.zig");

const assert = std.debug.assert;

const showdown = build_options.showdown;

const Gen12 = rng.Gen12;

const ActivePokemon = data.ActivePokemon;
const Choice = data.Choice;
const Move = data.Move;
const Player = data.Player;
const Result = data.Result;
const Side = data.Side;
const Stats = data.Stats;
const Status = data.Status;

// FIXME: https://www.smogon.com/forums/threads/self-ko-clause-gens-1-4.3653037/
// FIXME need to prompt c1 and c2 for new choices...? = should be able to tell choice from state?
pub fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    _ = c1;
    _ = c2;

    if (battle.turn == 0) {
        var p1 = battle.side(.P1);
        var p2 = battle.side(.P2);

        var slot = findFirstAlive(p1);
        if (slot == 0) return if (findFirstAlive(p2) == 0) .Tie else .Lose;
        try switchIn(p1, .P1, slot, true, log);

        slot = findFirstAlive(p2);
        if (slot == 0) return .Win;
        try switchIn(p2, .P2, slot, true, log);

        return try endTurn(battle, log);
    }

    // FIXME
    assert(c1.type == .Switch);
    try switchIn(battle.side(.P1), .P1, c1.data, false, log);

    assert(c2.type == .Switch);
    try switchIn(battle.side(.P2), .P2, c2.data, false, log);

    // XXX
    // if (active.volatiles.Recharging or active.volatiles.Rage) {}
    // p1.active.volatiles.Flinch = false;
    // p2.active.volatiles.Flinch = false;
    // if (active.volatiles.Locked or active.volatiles.Charging) {}
    // if (Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP)) {}
    // if (active.volatiles.Bide or active.volatiles.PartialTrap) {}
    // if (foe.active.volatiles.PartialTrap) {}
    // if (active.volatiles.PartialTrap) {}
    // XXX

    return .None;
}

pub fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon) |pokemon, i| {
        if (pokemon.hp > 0) return side.order[i];
    }
    return 0;
}

pub fn switchIn(side: *Side, player: Player, slot: u8, initial: bool, log: anytype) !void {
    var active = &side.active;
    const incoming = side.get(slot);
    assert(incoming.hp != 0);

    assert(slot != 1 or initial);
    const out = side.order[0];
    side.order[0] = side.order[slot - 1];
    side.order[slot - 1] = out;

    active.stats = incoming.stats;
    active.volatiles = .{};
    for (incoming.moves) |move, j| {
        active.moves[j] = move;
    }
    active.boosts = .{};
    active.species = incoming.species;
    active.types = incoming.types;

    if (Status.is(incoming.status, .PAR)) {
        active.stats.spe = @maximum(active.stats.spe / 4, 1);
    } else if (Status.is(incoming.status, .BRN)) {
        active.stats.atk = @maximum(active.stats.atk / 2, 1);
    }
    // TODO: ld hl, wEnemyBattleStatus1; res USING_TRAPPING_MOVE, [hl]

    try log.switched(active.ident(side, player), incoming);
}

pub fn endTurn(battle: anytype, log: anytype) !Result {
    battle.turn += 1;
    try log.turn(battle.turn);
    return .None;
}

pub fn determineTurnOrder(battle: anytype, c1: Choice, c2: Choice) Player {
    if ((c1.type == .Switch) != (c2.type == .Switch)) return if (c1.type == .Switch) .P1 else .P2;
    const m1 = getMove(battle, .P1, c1);
    const m2 = getMove(battle, .P2, c2);
    if ((m1 == .QuickAttack) != (m2 == .QuickAttack)) return if (m1 == .QuickAttack) .P1 else .P2;
    if ((m1 == .Counter) != (m2 == .Counter)) return if (m1 == .Counter) .P2 else .P1;
    // NB: https://www.smogon.com/forums/threads/adv-switch-priority.3622189/
    if (!showdown and c1.type == .Switch and c2.type == .Switch) return .P1;

    const spe1 = battle.side(.P1).active.stats.spe;
    const spe2 = battle.side(.P2).active.stats.spe;
    if (spe1 == spe2) {
        const p1 = if (showdown) {
            battle.rng.range(0, 2) == 0;
        } else {
            battle.rng.next() < Gen12.percent(50) + 1;
        };
        return if (p1) .P1 else .P2;
    }
    return if (spe1 > spe2) .P1 else .P2;
}

pub fn getMove(battle: anytype, player: Player, choice: Choice) Move {
    if (choice.type != .Move or choice.data == 0) return .None;

    assert(choice.data <= 4);
    const side = battle.side(player);
    const move = side.active.moves[choice.data - 1];
    assert(move.pp != 0); // FIXME: wrap underflow?

    return move.id;
}

// TODO return an enum instead of bool to handle multiple cases
pub fn beforeMove(battle: anytype, player: Player, mslot: u8, log: anytype) !bool {
    var side = battle.side(player);
    const foe = battle.foe(player);
    var active = &side.active;
    var stored = side.stored();
    const ident = active.ident(side, player);
    var volatiles = &active.volatiles;

    assert(active.move(mslot).id != .None);

    if (Status.is(stored.status, .SLP)) {
        stored.status -= 1;
        if (!Status.any(stored.status)) try log.cant(ident, .Sleep);
        return false;
    }
    if (Status.is(stored.status, .FRZ)) {
        try log.cant(ident, .Freeze);
        return false;
    }
    if (foe.active.volatiles.PartialTrap) {
        try log.cant(ident, .PartialTrap);
        return false;
    }
    if (volatiles.Flinch) {
        volatiles.Flinch = false;
        try log.cant(ident, .Flinch);
        return false;
    }
    if (volatiles.Recharging) {
        volatiles.Recharging = false;
        try log.cant(ident, .Recharging);
        return false;
    }
    if (volatiles.data.disabled.duration > 0) {
        volatiles.data.disabled.duration -= 1;
        if (volatiles.data.disabled.duration == 0) {
            volatiles.data.disabled.move = 0;
            try log.end(ident, .Disable);
        }
    }
    if (volatiles.Confusion) {
        assert(volatiles.data.confusion > 0);
        volatiles.data.confusion -= 1;
        if (volatiles.data.confusion == 0) {
            volatiles.Confusion = false;
            try log.end(ident, .Confusion);
        } else {
            try log.activate(ident, .Confusion);
            const confused = if (showdown) {
                !battle.rng.chance(128, 256);
            } else {
                battle.rng.next() >= Gen12.percent(50) + 1;
            };
            if (confused) {
                // FIXME: implement self hit
                volatiles.Bide = false;
                volatiles.Locked = false;
                volatiles.MultiHit = false;
                volatiles.Flinch = false;
                volatiles.Charging = false;
                volatiles.PartialTrap = false;
                volatiles.Invulnerable = false;
                return false;
            }
        }
    }
    if (volatiles.data.disabled.move == mslot) {
        volatiles.Charging = false;
        try log.disabled(ident, volatiles.data.disabled.move);
        return false;
    }
    if (Status.is(stored.status, .PAR)) {
        const paralyzed = if (showdown) {
            battle.rng.chance(63, 256);
        } else {
            battle.rng.next() < Gen12.percent(25);
        };
        if (paralyzed) {
            volatiles.Bide = false;
            volatiles.Locked = false;
            volatiles.Charging = false;
            volatiles.PartialTrap = false;
            // NB: Invulnerable is not cleared, resulting in the Fly/Dig glitch
            try log.cant(ident, .Paralysis);
            return false;
        }
    }
    if (volatiles.Bide) {
        // TODO accumulate? overflow?
        volatiles.data.bide += battle.last_damage;
        try log.activate(ident, .Bide);

        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        if (volatiles.data.attacks != 0) return false;

        volatiles.Bide = false;
        try log.end(ident, .Bide);
        if (volatiles.data.bide > 0) {
            try log.fail(ident, .None);
            return false;
        }
        // TODO unleash energy
    }
    if (volatiles.Locked) {
        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        // TODO PlayerMoveNum = THRASH
        if (volatiles.data.attacks == 0) {
            volatiles.Locked = false;
            volatiles.Confusion = true;
            // NB: these values will diverge
            volatiles.data.confusion = if (showdown) {
                battle.rng.range(3, 5);
            } else {
                (battle.rng.next() & 3) + 2;
            };
            try log.start(ident, .Confusion, true);
        }
        // TODO: skip DecrementPP, call PlayerCalcMoveDamage directly
    }
    if (volatiles.PartialTrap) {
        assert(volatiles.data.attacks > 0);
        volatiles.data.attacks -= 1;
        if (volatiles.data.attacks == 0) {
            // TODO skip DamageCalc/DecrementPP/MoveHitTest
        }
    }
    if (volatiles.Rage) {
        // TODO skip DecrementPP, go to PlayerCanExecuteMove
    }

    return true;
}

// TODO: struggle bypass/wrap underflow
pub fn decrementPP(side: *Side, choice: Choice) void {
    assert(choice.type == .Move);
    assert(choice.data <= 4);

    if (choice.data == 0) return; // Struggle

    var active = &side.active;

    const volatiles = active.volatiles;
    if (volatiles.Bide or volatiles.Locked or volatiles.MultiHit or volatiles.Rage) return;

    active.move(choice.data).pp -= 1;
    if (volatiles.Transform) return;

    side.stored().move(choice.data).pp -= 1;
}

pub fn moveEffect(battle: anytype, player: Player, move: Move, log: anytype) !void {
    return switch (move.effect) {
        .Conversion => Effects.conversion(battle, player, log),
        .Haze => Effects.haze(battle, player, log),
        .Heal => Effects.heal(battle, player, log),
        .LightScreen => Effects.lightScreen(battle, player, log),
        .PayDay => Effects.payDay(log),
        .Paralyze => Effects.paralyze(battle, player, move, log),
        .Reflect => Effects.reflect(battle, player, log),
        else => unreachable,
    };
}

pub const Effects = struct {
    pub fn conversion(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const foe = battle.foe(player);

        const ident = side.active.ident(side, player);
        if (foe.active.volatiles.Invulnerability) {
            return try log.miss(ident, foe.active.ident(foe, player.foe()));
        }
        side.active.types = foe.active.types;
        try log.typechange(ident, @bitCast(u8, foe.active.types));
    }

    pub fn haze(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        var foe = battle.foe(player);

        var side_stored = side.stored();
        var foe_stored = foe.stored();

        const player_ident = side.active.ident(side, player);
        const foe_ident = foe.active.ident(foe, player.foe());

        side.active.boosts = .{};
        foe.active.boosts = .{};

        side.active.stats = side_stored.stats;
        foe.active.stats = foe_stored.stats;
        try log.activate(player_ident, .Haze);
        try log.clearallboost();

        if (Status.any(foe_stored.status)) {
            if (Status.is(foe_stored.status, .FRZ) or Status.is(foe_stored.status, .SLP)) {
                // TODO prevent from executing a move by using special case move $FF!!!
            }
            try log.curestatus(foe_ident, foe_stored.status, true);
            foe_stored.status = 0;
        }

        try clearVolatiles(&side.active, player_ident, log);
        try clearVolatiles(&foe.active, foe_ident, log);
    }

    pub fn heal(battle: anytype, player: Player, log: anytype) !void {
        _ = battle;
        _ = player;
        _ = log;
        // TODO
    }

    pub fn lightScreen(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (side.active.volatiles.LightScreen) {
            try log.fail(ident, .None);
            return;
        }
        side.active.volatiles.LightScreen = true;
        try log.start(ident, .LightScreen);
    }

    pub fn mist(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (side.active.volatiles.Mist) {
            try log.fail(ident, .None);
            return;
        }
        try log.start(ident, .Mist);
    }

    pub fn paralyze(battle: anytype, player: Player, move: Move, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (Status.any(side.stored().status)) {
            try log.fail(ident, .Paralysis); // FIXME: ???
            return;
        }
        const m = Move.get(move.id);
        if (side.active.types.immune(m.type)) {
            try log.immune(ident, .None);
            return;
        }
        // TODO MoveHitTest, log
        side.active.stats.spe = @maximum(side.active.stats.spe / 4, 1);
    }

    pub fn payDay(log: anytype) !void {
        try log.fieldactivate();
    }

    pub fn reflect(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (side.active.volatiles.Reflect) {
            try log.fail(ident, .None);
            return;
        }
        side.active.volatiles.Reflect = true;
        try log.start(ident, .Reflect);
    }
};

pub fn clearVolatiles(active: *ActivePokemon, ident: u8, log: anytype) !void {
    var volatiles = &active.volatiles;
    if (volatiles.data.disabled.move != 0) {
        volatiles.data.disabled = .{};
        try log.end(ident, .DisableSilent);
    }
    if (volatiles.Confusion) {
        // NB: leave volatiles.data.confusion unchanged
        volatiles.Confusion = false;
        try log.end(ident, .ConfusionSilent);
    }
    if (volatiles.Mist) {
        volatiles.Mist = false;
        try log.end(ident, .Mist);
    }
    if (volatiles.FocusEnergy) {
        volatiles.FocusEnergy = false;
        try log.end(ident, .FocusEnergy);
    }
    if (volatiles.LeechSeed) {
        volatiles.LeechSeed = false;
        try log.end(ident, .LeechSeed);
    }
    if (volatiles.Toxic) {
        // NB: volatiles.data.toxic is left unchanged
        volatiles.Toxic = false;
        try log.end(ident, .Toxic);
    }
    if (volatiles.LightScreen) {
        volatiles.LightScreen = false;
        try log.end(ident, .LightScreen);
    }
    if (volatiles.Reflect) {
        volatiles.Reflect = false;
        try log.end(ident, .Reflect);
    }
}

// TODO DEBUG audit pub usage
comptime {
    std.testing.refAllDecls(@This());
}
