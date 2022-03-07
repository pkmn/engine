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
pub fn update(battle: anytype, c1: Choice, c2: Choice, log: anytype) !Result {
    if (battle.turn == 0) return start(battle, log);

    // FIXME monFainted

    const choice1 = selectMove(battle, .P1, c1);
    const choice2 = selectMove(battle, .P2, c2);

    // TODO: https://glitchcity.wiki/Partial_trapping_move_Mirror_Move_link_battle_glitch

    if (turnOrder(battle, choice1, choice2) == .P1) {
        try doTurn(battle, .P1, choice1, .P2, choice2, log);
    } else {
        try doTurn(battle, .P2, choice2, .P1, choice1, log);
    }

    var p1 = battle.side(.P1);
    if (p1.active.volatiles.data.attacks == 0) {
        p1.active.volatiles.Trapping = false;
    }
    var p2 = battle.side(.P2);
    if (p2.active.volatiles.data.attacks == 0) {
        p2.active.volatiles.Trapping = false;
    }

    return try endTurn(battle, log);
}

fn start(battle: anytype, log: anytype) !Result {
    const p1 = battle.side(.P1);
    const p2 = battle.side(.P2);

    var slot = findFirstAlive(p1);
    if (slot == 0) return if (findFirstAlive(p2) == 0) Result.Tie else Result.Lose;
    try switchIn(battle, .P1, slot, true, log);

    slot = findFirstAlive(p2);
    if (slot == 0) return Result.Win;
    try switchIn(battle, .P2, slot, true, log);

    return try endTurn(battle, log);
}

fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon) |pokemon, i| {
        if (pokemon.hp > 0) return side.order[i];
    }
    return 0;
}

fn selectMove(battle: anytype, player: Player, choice: Choice) Choice {
    var side = battle.side(player);
    var volatiles = &side.active.volatiles;
    const stored = side.stored();

    if (volatiles.Recharging or volatiles.Rage) return .{};
    volatiles.Flinch = false;
    if (volatiles.Locked or volatiles.Charging) return .{};

    if (choice.type == .Switch) return choice;

    if (Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP)) return .{};
    if (volatiles.Bide or volatiles.Trapping) return .{};

    assert(choice.data != 0xF);
    return if (battle.foe(player).active.volatiles.Trapping) .{ .data = 0xF } else choice;
}

fn switchIn(battle: anytype, player: Player, slot: u8, initial: bool, log: anytype) !void {
    var side = battle.side(player);
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
    battle.foe(player).active.volatiles.Trapping = false;

    try log.switched(active.ident(side, player), incoming);
}

fn turnOrder(battle: anytype, c1: Choice, c2: Choice) Player {
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
        const p1 = if (showdown)
            battle.rng.range(0, 2) == 0
        else
            battle.rng.next() < Gen12.percent(50) + 1;
        return if (p1) .P1 else .P2;
    }
    return if (spe1 > spe2) .P1 else .P2;
}

fn doTurn(battle: anytype, p: Player, pc: Choice, f: Player, fc: Choice, log: anytype) !void {
    try executeMove(battle, p, pc, log);
    try checkFaint(battle, f, log);
    try handleResidual(battle, p, log);
    try checkFaint(battle, p, log);

    try executeMove(battle, f, fc, log);
    try checkFaint(battle, p, log);
    try handleResidual(battle, f, log);
    try checkFaint(battle, f, log);
}

fn endTurn(battle: anytype, log: anytype) !Result {
    battle.turn += 1;
    try log.turn(battle.turn);
    return Result.Default;
}

fn getMove(battle: anytype, player: Player, choice: Choice) Move {
    if (choice.type != .Move or choice.data == 0) return .None;

    assert(choice.data <= 4);
    const side = battle.side(player);
    const move = side.active.moves[choice.data - 1];
    assert(move.pp != 0); // FIXME: wrap underflow?

    return move.id;
}

fn executeMove(battle: anytype, player: Player, choice: Choice, log: anytype) !void {
    _ = battle;
    _ = player;
    _ = choice;
    _ = log;

    // FIXME
    assert(choice.type == .Switch);
    try switchIn(battle, player, choice.data, false, log);
}

fn checkFaint(battle: anytype, player: Player, log: anytype) !void {
    _ = battle;
    _ = player;
    _ = log;

    // TODO: if player is fainted, enemy faint check, and turn is over
}

fn handleResidual(battle: anytype, player: Player, log: anytype) !void {
    _ = battle;
    _ = player;
    _ = log;

    // TODO: Substract health from player if poisoned/seeded/burned**
}

fn monFainted(wInHandlePlayerMonFainted: bool) !void {
    // set wInHandlePlayerMonFainted to avoid recursive
    // remove fainted mon
    //  - reset ENEMY attacking multiple times
    // - 0 enemy ENEMY accumulated damage BUG: POSSIBLY A DESYNC
    if (wInHandlePlayerMonFainted) return;
    // test if any more PLAYER mons are alive
    //
    // if enemy pokemon hp = 0, monFainted(enmery, true)
    // test if any more enemy mons alive
    //

    // need to return none to force end turn?
}

// TODO return an enum instead of bool to handle multiple cases
fn beforeMove(battle: anytype, player: Player, mslot: u8, log: anytype) !bool {
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
    if (foe.active.volatiles.Trapping) {
        try log.cant(ident, .Trapping);
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
            const confused = if (showdown)
                !battle.rng.chance(128, 256)
            else
                battle.rng.next() >= Gen12.percent(50) + 1;
            if (confused) {
                // FIXME: implement self hit
                volatiles.Bide = false;
                volatiles.Locked = false;
                volatiles.MultiHit = false;
                volatiles.Flinch = false;
                volatiles.Charging = false;
                volatiles.Trapping = false;
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
        const paralyzed = if (showdown)
            battle.rng.chance(63, 256)
        else
            battle.rng.next() < Gen12.percent(25);
        if (paralyzed) {
            volatiles.Bide = false;
            volatiles.Locked = false;
            volatiles.Charging = false;
            volatiles.Trapping = false;
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
            volatiles.data.confusion = if (showdown)
                battle.rng.range(3, 5)
            else
                (battle.rng.next() & 3) + 2;
            try log.start(ident, .Confusion, true);
        }
        // TODO: skip DecrementPP, call PlayerCalcMoveDamage directly
    }
    if (volatiles.Trapping) {
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
fn decrementPP(side: *Side, choice: Choice) void {
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

fn moveEffect(battle: anytype, player: Player, move: Move, log: anytype) !void {
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
    fn conversion(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const foe = battle.foe(player);

        const ident = side.active.ident(side, player);
        if (foe.active.volatiles.Invulnerability) {
            return try log.miss(ident, foe.active.ident(foe, player.foe()));
        }
        side.active.types = foe.active.types;
        try log.typechange(ident, @bitCast(u8, foe.active.types));
    }

    fn haze(battle: anytype, player: Player, log: anytype) !void {
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

    fn heal(battle: anytype, player: Player, log: anytype) !void {
        _ = battle;
        _ = player;
        _ = log;
        // TODO
    }

    fn lightScreen(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (side.active.volatiles.LightScreen) {
            try log.fail(ident, .None);
            return;
        }
        side.active.volatiles.LightScreen = true;
        try log.start(ident, .LightScreen);
    }

    fn mist(battle: anytype, player: Player, log: anytype) !void {
        var side = battle.side(player);
        const ident = side.active.ident(side, player);
        if (side.active.volatiles.Mist) {
            try log.fail(ident, .None);
            return;
        }
        try log.start(ident, .Mist);
    }

    fn paralyze(battle: anytype, player: Player, move: Move, log: anytype) !void {
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

    fn payDay(log: anytype) !void {
        try log.fieldactivate();
    }

    fn reflect(battle: anytype, player: Player, log: anytype) !void {
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

fn clearVolatiles(active: *ActivePokemon, ident: u8, log: anytype) !void {
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
