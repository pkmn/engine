const std = @import("std");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const showdown = options.showdown;

const Boost = protocol.Boost;
const Damage = protocol.Damage;
const Heal = protocol.Heal;

const Gen12 = rng.Gen12;

const ActivePokemon = data.ActivePokemon;
const Effectiveness = data.Effectiveness;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Pokemon = data.Pokemon;
const Side = data.Side;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;
const Type = data.Type;

// zig fmt: off
const BOOSTS = &[_][2]u8{
    .{ 25, 100 }, // -6
    .{ 28, 100 }, // -5
    .{ 33, 100 }, // -4
    .{ 40, 100 }, // -3
    .{ 50, 100 }, // -2
    .{ 66, 100 }, // -1
    .{   1,  1 }, //  0
    .{ 15,  10 }, // +1
    .{  2,   1 }, // +2
    .{ 25,  10 }, // +3
    .{  3,   1 }, // +4
    .{ 35,  10 }, // +5
    .{  4,   1 }, // +6
};
// zig fmt: on

const MAX_STAT_VALUE = 999;

pub fn Mechanics(comptime Battle: anytype, comptime Log: anytype) type {
    return struct {
        const Self = @This();

        log: Log,
        battle: Battle,

        pub fn update(self: Self, c1: Choice, c2: Choice) !Result {
            assert(c1.type != .Pass or c2.type != .Pass or self.battle.turn == 0);
            if (self.battle.turn == 0) return self.start();

            var f1: ?Move = null;
            var f2: ?Move = null;

            if (self.selectMove(.P1, c1, c2, &f1)) |r| return r;
            if (self.selectMove(.P2, c2, c1, &f2)) |r| return r;

            if (self.turnOrder(c1, c2) == .P1) {
                if (try self.doTurn(.P1, c1, f1, .P2, c2, f2)) |r| return r;
            } else {
                if (try self.doTurn(.P2, c2, f2, .P1, c1, f1)) |r| return r;
            }

            var p1 = self.battle.side(.P1);
            if (p1.active.volatiles.attacks == 0) {
                p1.active.volatiles.Binding = false;
            }
            var p2 = self.battle.side(.P2);
            if (p2.active.volatiles.attacks == 0) {
                p2.active.volatiles.Binding = false;
            }

            return self.endTurn();
        }

        fn start(self: Self) !Result {
            const p1 = self.battle.side(.P1);
            const p2 = self.battle.side(.P2);

            var p1_slot = findFirstAlive(p1);
            assert(!showdown or p1_slot == 1);
            if (p1_slot == 0) return if (findFirstAlive(p2) == 0) Result.Tie else Result.Lose;

            var p2_slot = findFirstAlive(p2);
            assert(!showdown or p2_slot == 1);
            if (p2_slot == 0) return Result.Win;

            try self.switchIn(.P1, p1_slot, true);
            try self.switchIn(.P2, p2_slot, true);

            return self.endTurn();
        }

        fn selectMove(
            self: Self,
            player: Player,
            choice: Choice,
            foe_choice: Choice,
            from: *?Move,
        ) ?Result {
            if (choice.type == .Pass) return null;

            var side = self.battle.side(player);
            var volatiles = &side.active.volatiles;
            const stored = side.stored();

            assert(!isForced(side.active) or
                (choice.type == .Move and choice.data == @boolToInt(showdown)));

            // pre-battle menu
            if (volatiles.Recharging) return null;
            if (volatiles.Rage) {
                from.* = side.last_used_move;
                if (showdown) self.saveMove(player, null);
                return null;
            }
            // Pokémon Showdown removes Flinch at the end-of-turn in its residual handler
            if (!showdown) volatiles.Flinch = false;
            if (volatiles.Thrashing or volatiles.Charging) {
                from.* = side.last_selected_move;
                if (showdown) self.saveMove(player, null);
                return null;
            }

            // battle menu
            if (choice.type == .Switch) return null;

            // pre-move select
            const skip =
                Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP) or volatiles.Bide;
            if (skip) {
                assert(showdown or choice.data == 0);
                if (showdown) self.saveMove(player, choice);
                return null;
            }
            if (volatiles.Binding) {
                from.* = side.last_used_move;
                if (showdown) {
                    if (foe_choice.type == .Switch) from.* = null;
                    // Pokémon Showdown overwrites Mirror Move with whatever was selected - really
                    // this should set side.last_selected_move = last.id to reuse Mirror Move and
                    // fail in order to satisfy the conditions of the Desync Clause Mod. However,
                    // because Binding is still set the selected move will not actually be used, it
                    // will just be reported as having been used (this differs from how Pokémon
                    // Showdown works, but its impossible to replicate the incorrect behavior with
                    // the correct mechanisms).
                    self.saveMove(player, choice);
                } else {
                    assert(choice.data == 0);
                    // GLITCH: Partial trapping move Mirror Move link battle glitch
                    if (foe_choice.type == .Switch) {
                        const slot = if (player == .P1)
                            self.battle.last_selected_indexes.p1
                        else
                            self.battle.last_selected_indexes.p2;
                        const last = side.active.move(@intCast(u4, slot));
                        if (last.id == .Metronome) side.last_selected_move = last.id;
                        if (last.id == .MirrorMove) return Result.Error;
                    }
                }
                return null;
            }

            if (self.battle.foe(player).active.volatiles.Binding) {
                if (showdown) {
                    self.saveMove(player, choice);
                } else {
                    assert(choice.data == 0);
                    side.last_selected_move = .SKIP_TURN;
                }
                return null;
            }

            // move select
            volatiles.state = 0;
            if (choice.data == 0) {
                const struggle = ok: {
                    for (side.active.moves, 0..) |move, i| {
                        if (move.pp > 0 and volatiles.disabled_move != i + 1) break :ok false;
                    }
                    break :ok true;
                };

                assert(struggle);
                self.saveMove(player, choice);
            } else {
                self.saveMove(player, choice);
            }

            return null;
        }

        fn saveMove(self: Self, player: Player, choice: ?Choice) void {
            var side = self.battle.side(player);

            if (choice) |c| {
                assert(c.type == .Move);
                if (c.data == 0) {
                    side.last_selected_move = .Struggle;
                } else {
                    assert(showdown or side.active.volatiles.disabled_move != c.data);
                    const move = side.active.move(c.data);
                    // You cannot *select* a move with 0 PP (except on Pokémon Showdown where that
                    // is sometimes required...), but a 0 PP move can be used automatically
                    assert(showdown or move.pp != 0);

                    side.last_selected_move = move.id;
                    if (player == .P1) {
                        self.battle.last_selected_indexes.p1 = @intCast(u4, c.data);
                    } else {
                        self.battle.last_selected_indexes.p2 = @intCast(u4, c.data);
                    }
                }
            }
        }

        fn switchIn(self: Self, player: Player, slot: u8, initial: bool) !void {
            var side = self.battle.side(player);
            var foe = self.battle.foe(player);
            var active = &side.active;
            const incoming = side.get(slot);

            assert(incoming.hp != 0);
            assert(slot != 1 or initial);

            const out = side.order[0];
            side.order[0] = side.order[slot - 1];
            side.order[slot - 1] = out;

            if (player == .P1) {
                self.battle.last_selected_indexes.p1 = 1;
            } else {
                self.battle.last_selected_indexes.p2 = 1;
            }

            side.last_used_move = .None;
            foe.last_used_move = .None;

            active.stats = incoming.stats;
            active.species = incoming.species;
            active.types = incoming.types;
            active.boosts = .{};
            active.volatiles = .{};
            active.moves = incoming.moves;

            statusModify(incoming.status, &active.stats);

            foe.active.volatiles.Binding = false;

            try self.log.switched(self.battle.active(player), incoming);

            if (showdown and incoming.status == Status.TOX) {
                incoming.status = Status.init(.PSN);
                // Technically, Pokémon Showdown adds these after *both* Pokémon have switched, but
                // we'd rather not clutter up turnOrder just for this (incorrect) log message
                try self.log.status(self.battle.active(player), incoming.status, .Silent);
            }
        }

        fn turnOrder(self: Self, c1: Choice, c2: Choice) Player {
            assert(c1.type != .Pass or c2.type != .Pass);

            if (c1.type == .Pass) return .P2;
            if (c2.type == .Pass) return .P1;

            if ((c1.type == .Switch) != (c2.type == .Switch)) {
                return if (c1.type == .Switch) .P1 else .P2;
            }

            // https://www.smogon.com/forums/threads/adv-switch-priority.3622189/
            // > In Gen 1 it's irrelevant [which player switches first] because switches happen
            // > instantly on your own screen without waiting for the other player's choice (and
            // > their choice will appear to happen first for them too, unless they attacked in
            // > which case your switch happens first)
            // A cartridge-compatible implemention must not advance the RNG so we default to P1
            const double_switch = c1.type == .Switch and c2.type == .Switch;
            if (!showdown and double_switch) return .P1;

            const m1 = self.battle.side(.P1).last_selected_move;
            const m2 = self.battle.side(.P2).last_selected_move;
            if (!showdown or !double_switch) {
                if ((m1 == .QuickAttack) != (m2 == .QuickAttack)) {
                    return if (m1 == .QuickAttack) .P1 else .P2;
                } else if ((m1 == .Counter) != (m2 == .Counter)) {
                    return if (m1 == .Counter) .P2 else .P1;
                }
            }

            const spe1 = self.battle.side(.P1).active.stats.spe;
            const spe2 = self.battle.side(.P2).active.stats.spe;
            if (spe1 == spe2) {
                // Pokémon Showdown's beforeTurnCallback shenanigans
                if (showdown and m1 == .Counter and m2 == .Counter) self.battle.rng.advance(1);

                const p1 = if (showdown)
                    self.battle.rng.range(u8, 0, 2) == 0
                else
                    self.battle.rng.next() < Gen12.percent(50) + 1;

                if (!showdown) return if (p1) .P1 else .P2;

                // Pokémon Showdown's "lockedmove" volatile's onBeforeTurn uses
                // self.battleQueue#changeAction, meaning that if a side is locked into a thrashing
                // move and wins the speed tie, it actually uses its priority to simply insert its
                // actual changed action into the queue, causing it to then execute *after* the side
                // which should go second...
                const t1 = self.battle.side(.P1).active.volatiles.Thrashing;
                const t2 = self.battle.side(.P2).active.volatiles.Thrashing;
                // If *both* sides are thrashing it really should be another speed tie, but we've
                // patched that out and enforce host ordering of events, so P1 just goes first
                // regardless of who won the original coin flip
                if (t1 and t2) return .P1;
                return if (p1) if (t1 and !t2) .P2 else .P1 else if (t2 and !t1) .P1 else .P2;
            }

            return if (spe1 > spe2) .P1 else .P2;
        }

        fn doTurn(
            self: Self,
            player: Player,
            player_choice: Choice,
            player_from: ?Move,
            foe_player: Player,
            foe_choice: Choice,
            foe_from: ?Move,
        ) !?Result {
            assert(player_choice.type != .Pass);

            var residual = true;
            var replace = self.battle.side(player).stored().hp == 0;
            if (try self.executeMove(player, player_choice, player_from, &residual)) |r| return r;
            if (!replace) {
                if (player_choice.type != .Switch) {
                    if (try self.checkFaint(foe_player)) |r| return r;
                }
                if (residual) try self.handleResidual(player);
                if (try self.checkFaint(player)) |r| return r;
            } else if (foe_choice.type == .Pass) return null;

            residual = true;
            replace = self.battle.side(foe_player).stored().hp == 0;
            if (try self.executeMove(foe_player, foe_choice, foe_from, &residual)) |r| return r;
            if (!replace) {
                if (foe_choice.type != .Switch) {
                    if (try self.checkFaint(player)) |r| return r;
                }
                if (residual) try self.handleResidual(foe_player);
                if (try self.checkFaint(foe_player)) |r| return r;
            }

            // Flinch is bugged on Pokémon Showdown because it gets implemented with a duration
            // which causes it to get removed in the non-existent "residual" phase instead of during
            // move selection
            if (showdown) {
                self.battle.side(.P1).active.volatiles.Flinch = false;
                self.battle.side(.P2).active.volatiles.Flinch = false;
            }

            return null;
        }

        fn executeMove(
            self: Self,
            player: Player,
            choice: Choice,
            from: ?Move,
            residual: *bool,
        ) !?Result {
            var side = self.battle.side(player);

            if (choice.type == .Switch) {
                try self.switchIn(player, @intCast(u4, choice.data), false);
                return null;
            }

            if (side.last_selected_move == .SKIP_TURN) {
                // Pokémon Showdown overwrites the SKIP_TURN sentinel with its botched move select,
                // Binding instead gets handled in beforeMove after sleep and freeze
                assert(!showdown);
                if (self.battle.foe(player).active.volatiles.Binding) {
                    try self.log.cant(self.battle.active(player), .Bound);
                }
                return null;
            }

            assert(choice.type == .Move);
            var mslot = @intCast(u4, choice.data);
            // Sadly, we can't even check `Move.get(last_selected_move).effect == .Binding` here
            // because Pokémon Showdown's Mirror Move implementation clobbers last_selected_move
            var auto = showdown and side.last_selected_move != .None;

            // GLITCH: Freeze top move selection desync & PP underflow shenanigans
            if (mslot == 0 and side.last_selected_move != .None and
                side.last_selected_move != .Struggle)
            {
                // choice.data == 0 only happens with Struggle on Pokémon Showdown
                assert(!showdown);
                mslot = @intCast(u4, if (player == .P1)
                    self.battle.last_selected_indexes.p1
                else
                    self.battle.last_selected_indexes.p2);
                const stored = side.stored();
                // GLITCH: Struggle bypass PP underflow via Hyper Beam / Trapping-switch auto select
                auto = side.last_selected_move == .HyperBeam or side.active.volatiles.Bide or
                    from != null or Status.is(stored.status, .FRZ) or
                    Status.is(stored.status, .SLP);
                // If it wasn't Hyper Beam or the continuation of a move effect then we must have
                // just thawed, in which case we will desync unless the last_selected_move happened
                // to be at index 1 and the current Pokémon has the same move in its first slot.
                if (!auto) {
                    // side.active.moves(slot) is safe to check even though the slot in question
                    // might not technically be from this Pokémon because it must be exactly 1 to
                    // not desync and every Pokémon must have at least one move
                    if (mslot != 1 or side.active.move(mslot).id != side.last_selected_move) {
                        return Result.Error;
                    } else {
                        auto = true;
                    }
                }
            } else if (showdown and side.active.volatiles.Charging) {
                // Incorrect mslot due to broken Pokémon Showdown choice semantics means we need to
                // recover the actual mslot from index
                assert(mslot == 1);
                mslot = @intCast(u4, if (player == .P1)
                    self.battle.last_selected_indexes.p1
                else
                    self.battle.last_selected_indexes.p2);
            }

            var skip_can = false;
            var skip_pp = false;
            switch (try self.beforeMove(player, from, residual)) {
                .done => return null,
                .skip_can => skip_can = true,
                .skip_pp => skip_pp = true,
                .ok => {},
                .err => return @as(?Result, Result.Error),
            }

            if (!skip_can and !try self.canMove(player, mslot, auto, skip_pp, from, residual)) {
                return null;
            }

            return self.doMove(player, mslot, auto, residual);
        }

        const BeforeMove = union(enum) { done, skip_can, skip_pp, ok, err };

        fn beforeMove(self: Self, player: Player, from: ?Move, residual: *bool) !BeforeMove {
            var side = self.battle.side(player);
            const foe = self.battle.foe(player);
            var active = &side.active;
            var stored = side.stored();
            const ident = self.battle.active(player);
            var volatiles = &active.volatiles;

            if (Status.is(stored.status, .SLP)) {
                const status = stored.status;
                // Even if the EXT bit is set this will still correctly modify the sleep duration
                stored.status -= 1;
                if (Status.duration(stored.status) == 0) {
                    try self.log.curestatus(ident, status, .Message);
                    stored.status = 0; // clears EXT if present
                } else {
                    try self.log.cant(ident, .Sleep);
                }
                side.last_used_move = .None;
                return .done;
            }

            if (Status.is(stored.status, .FRZ)) {
                try self.log.cant(ident, .Freeze);
                side.last_used_move = .None;
                return .done;
            }

            if (foe.active.volatiles.Binding) {
                try self.log.cant(ident, .Bound);
                return .done;
            }

            if (!showdown and volatiles.Flinch) {
                volatiles.Flinch = false;
                try self.log.cant(ident, .Flinch);
                return .done;
            }

            if (volatiles.Recharging) {
                volatiles.Recharging = false;
                try self.log.cant(ident, .Recharge);
                return .done;
            }

            if (volatiles.disabled_duration > 0) {
                volatiles.disabled_duration -= 1;
                if (volatiles.disabled_duration == 0) {
                    volatiles.disabled_move = 0;
                    try self.log.end(ident, .Disable);
                }
            }
            // Pokémon Showdown's disable condition has a single onBeforeMove handler
            if (showdown and try self.disabled(side, ident)) return .done;

            // Pokémon Showdown checks for Flinch *after* instead of before
            if (showdown and volatiles.Flinch) {
                volatiles.Flinch = false;
                try self.log.cant(ident, .Flinch);
                return .done;
            }

            // This can only happen if a Pokémon started the battle frozen/sleeping and was
            // thawed/woken before the side had a selected a move - we simply need to assume this
            // leads to a desync
            if (side.last_selected_move == .None) {
                assert(!showdown);
                return .err;
            }

            if (volatiles.Confusion) {
                assert(volatiles.confusion > 0);

                volatiles.confusion -= 1;
                if (volatiles.confusion == 0) {
                    volatiles.Confusion = false;
                    try self.log.end(ident, .Confusion);
                } else {
                    try self.log.activate(ident, .Confusion);

                    const confused = if (showdown)
                        !self.battle.rng.chance(u8, 128, 256)
                    else
                        self.battle.rng.next() >= Gen12.percent(50) + 1;

                    if (confused) {
                        assert(!volatiles.MultiHit);
                        if (!volatiles.Rage) volatiles.state = 0;
                        volatiles.Bide = false;
                        volatiles.Thrashing = false;
                        volatiles.MultiHit = false;
                        volatiles.Flinch = false;
                        volatiles.Charging = false;
                        volatiles.Binding = false;
                        volatiles.Invulnerable = false;
                        {
                            // This feels (and is) disgusting but the cartridge literally just
                            // overwrites the opponent's defense with the user's defense and resets
                            // it after. As a result of this the *opponent's* Reflect impacts
                            // confusion self-hit damage
                            const def = foe.active.stats.def;
                            foe.active.stats.def = active.stats.def;
                            defer foe.active.stats.def = def;
                            if (!self.calcDamage(player, player.foe(), null, false)) return .err;
                        }
                        // Pokémon Showdown incorrectly changes the "target" of the confusion
                        // self-hit based on the targeting behavior of the confused Pokémon's
                        // selected move which results in the wrong behavior with respect to the
                        // Substitute + Confusion glitch
                        const target = if (showdown and
                            Move.get(side.last_selected_move).target == .Self)
                            player
                        else
                            player.foe();

                        const uncapped = self.battle.last_damage;
                        // Skipping adjustDamage / randomizeDamage / checkHit
                        _ = try self.applyDamage(player, target, .Confusion);
                        // Pokémon Showdown thinks that Confusion damage is uncapped ¯\_(ツ)_/¯
                        if (showdown) self.battle.last_damage = uncapped;

                        return .done;
                    }
                }
            }

            if (!showdown and try self.disabled(side, ident)) return .done;

            if (Status.is(stored.status, .PAR)) {
                const paralyzed = if (showdown)
                    self.battle.rng.chance(u8, 63, 256)
                else
                    self.battle.rng.next() < Gen12.percent(25);

                if (paralyzed) {
                    if (!volatiles.Rage) volatiles.state = 0;
                    volatiles.Bide = false;
                    volatiles.Thrashing = false;
                    volatiles.Charging = false;
                    volatiles.Binding = false;
                    // GLITCH: Invulnerable is not cleared, resulting in permanent invulnerability
                    try self.log.cant(ident, .Paralysis);
                    return .done;
                }
            }

            if (volatiles.Bide) {
                assert(!volatiles.Thrashing and !volatiles.Rage);

                volatiles.state +%= self.battle.last_damage;

                assert(volatiles.attacks > 0);

                volatiles.attacks -= 1;
                if (volatiles.attacks != 0) {
                    try self.log.activate(ident, .Bide);
                    return .done;
                }

                volatiles.Bide = false;
                try self.log.end(ident, .Bide);

                self.battle.last_damage = volatiles.state *% 2;
                volatiles.state = 0;

                if (self.battle.last_damage == 0) {
                    try self.log.fail(ident, .None);
                    return .done;
                }

                const sub = showdown and foe.active.volatiles.Substitute;
                _ = try self.applyDamage(player.foe(), player.foe(), .None);
                if (foe.stored().hp > 0 and !sub) try self.buildRage(player.foe());

                // For reasons passing understanding, Pokémon Showdown still inflicts residual
                // damage to Bide's user even if the above damage has caused the foe to faint. It's
                // simpler to always run residual here regardless of whether the foe fainted and
                // opt-out of the default flow
                if (showdown) {
                    residual.* = false;
                    try self.handleResidual(player);
                }

                return .done;
            }

            if (volatiles.Thrashing) {
                assert(volatiles.attacks > 0);
                assert(from != null);
                volatiles.attacks -= 1;
                if (!showdown and self.handleThrashing(active)) {
                    try self.log.start(self.battle.active(player), .ConfusionSilent);
                }
                try self.log.move(
                    ident,
                    side.last_selected_move,
                    self.battle.active(player.foe()),
                    from,
                );
                if (showdown and self.handleThrashing(active)) {
                    try self.log.start(self.battle.active(player), .ConfusionSilent);
                }
                return .skip_can;
            }

            if (volatiles.Binding) {
                assert(volatiles.attacks > 0);
                volatiles.attacks -= 1;
                try self.log.move(
                    self.battle.active(player),
                    side.last_selected_move,
                    self.battle.active(player.foe()),
                    side.last_selected_move,
                );
                if (showdown or self.battle.last_damage != 0) {
                    _ = try self.applyDamage(player.foe(), player.foe(), .None);
                }
                return .done;
            }

            return if (volatiles.Rage) .skip_pp else .ok;
        }

        fn canMove(
            self: Self,
            player: Player,
            mslot: u4,
            auto: bool,
            skip_pp: bool,
            from: ?Move,
            residual: *bool,
        ) !bool {
            var side = self.battle.side(player);
            const player_ident = self.battle.active(player);
            const move = Move.get(side.last_selected_move);

            const foe_last = self.battle.foe(player).last_used_move;
            const special = from != null and (from.? == .Metronome and
                (from.? == .MirrorMove and !(foe_last == .None or foe_last == .MirrorMove)));

            var skip = skip_pp;
            if (side.active.volatiles.Charging) {
                side.active.volatiles.Charging = false;
                side.active.volatiles.Invulnerable = false;
            } else if (move.effect == .Charge) {
                try self.log.move(player_ident, side.last_selected_move, .{}, from);
                try Effects.charge(self, player);
                return false;
            }

            if (!showdown or !special) side.last_used_move = side.last_selected_move;
            if (!skip) decrementPP(side, mslot, auto);

            const target = if (move.target == .Self) player else player.foe();
            // Pokémon Showdown's protocol for Rage and Binding moves should come with a [from],
            // though we don't have space to be able to track it in all circumstances and thus
            // usually try to infer it from side.last_used_move. However, this gets reset by the
            // opponent switching or fainting, meaning sometimes we lose this information. from is
            // still set because it not being null is relevant for control flow, but we don't have
            // anything useful to put in the log. This is regrettable, but this information is more
            // "nice to have" than required
            const f = if (from != null and from.? == .None) null else from;
            try self.log.move(player_ident, side.last_selected_move, self.battle.active(target), f);

            if (move.effect.onBegin()) {
                try self.onBegin(player, move, mslot, residual);
                return false;
            }

            if (move.effect == .Thrashing) {
                Effects.thrashing(self, player);
            } else if (!showdown and move.effect == .Binding) {
                // Pokémon Showdown handles this after hit/miss checks and damage calculation
                Effects.binding(self, player);
            }

            return true;
        }

        fn decrementPP(side: *Side, mslot: u4, auto: bool) void {
            if (side.last_selected_move == .Struggle) return;

            var active = &side.active;
            const volatiles = &active.volatiles;

            assert(!volatiles.Rage and !volatiles.Thrashing and !volatiles.MultiHit);
            if (volatiles.Bide) return;

            assert(active.move(mslot).pp > 0 or auto);
            active.move(mslot).pp = @intCast(u6, active.move(mslot).pp) -% 1;
            if (volatiles.Transform) return;

            assert(side.stored().move(mslot).pp > 0 or auto);
            side.stored().move(mslot).pp = @intCast(u6, side.stored().move(mslot).pp) -% 1;
            assert(active.move(mslot).pp == side.stored().move(mslot).pp);
        }

        fn incrementPP(side: *Side, mslot: u4) void {
            var active = &side.active;
            const volatiles = &active.volatiles;

            active.move(mslot).pp = @intCast(u6, active.move(mslot).pp) +% 1;
            // GLITCH: No check for Transform means a bad stored slot can get incremented
            if (showdown and volatiles.Transform) return;

            assert(mslot > 0 and mslot <= 4);
            side.stored().moves[mslot - 1].pp =
                @intCast(u6, side.stored().moves[mslot - 1].pp) +% 1;
        }

        // Pokémon Showdown does hit/multi/crit/damage instead of crit/damage/hit/multi
        fn doMove(
            self: Self,
            player: Player,
            mslot: u4,
            auto: bool,
            residual: *bool,
        ) !?Result {
            var side = self.battle.side(player);
            const foe = self.battle.foe(player);

            var move = Move.get(side.last_selected_move);
            const counter = side.last_selected_move == .Counter;
            const status = move.bp == 0 and move.effect != .OHKO;

            var crit = false;
            var ohko = false;
            var immune = false;
            var mist = false;
            var hits: u4 = 1;
            var effectiveness = Effectiveness.neutral;

            // The cartridge handles set damage moves in applyDamage but we short circuit to
            // simplify things
            if (move.effect == .SuperFang or move.effect == .SpecialDamage) {
                return self.specialDamage(player, move);
            }

            // Pokémon Showdown runs invulnerability / immunity checks before checking accuracy -
            // simply calling moveHit early covers most of that but we also need to first check type
            // immunity / binding / OHKOs
            var miss = showdown and miss: {
                immune = move.target != .Self and !status and !counter and
                    (@enumToInt(move.type.effectiveness(foe.active.types.type1)) == 0 or
                    @enumToInt(move.type.effectiveness(foe.active.types.type2)) == 0);
                if (immune and move.effect != .Binding) break :miss true;
                if (move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe) {
                    self.battle.last_damage = 0;
                    break :miss true;
                }
                break :miss move.target != .Self and !self.moveHit(player, move, &immune, &mist);
            };
            assert(!immune or miss or (showdown and move.effect == .Binding));

            var late = showdown and move.effect != .Explode;
            const skip = status or immune;
            if ((!showdown or (!skip or counter)) and !miss) blk: {
                if (showdown and move.effect.isMulti()) {
                    Effects.multiHit(self, player, move);
                    hits = side.active.volatiles.attacks;
                    late = false;
                }

                // Cartridge rolls for crit even for moves that can't crit
                const check = !showdown or (!counter and move.effect != .OHKO);
                if (check) crit = self.checkCriticalHit(player, move);

                if (counter) return self.counterDamage(player, move);

                self.battle.last_damage = 0;

                // Disassembly does a check to allow 0 BP MultiHit moves but this isn't possible
                assert(move.effect != .MultiHit or move.bp > 0);
                if (!skip) {
                    if (move.effect == .OHKO) {
                        ohko =
                            if (!showdown) side.active.stats.spe >= foe.active.stats.spe else true;
                        // This can overflow after adjustDamage, but will still always OHKO
                        self.battle.last_damage = if (ohko) 65535 else 0;
                        if (showdown) break :blk; // skip adjustDamage / randomizeDamage
                    } else if (!self.calcDamage(player, player.foe(), move, crit)) {
                        return @as(?Result, Result.Error);
                    }
                    if (self.battle.last_damage == 0) {
                        immune = true;
                        effectiveness = 0;
                    } else {
                        effectiveness = self.adjustDamage(player);
                        immune = effectiveness == 0;
                    }
                    self.randomizeDamage();
                }
            }

            // Due to control flow shenanigans we need to clear last_damage for Pokémon Showdown
            if (showdown and skip) self.battle.last_damage = 0;

            miss = if (showdown or skip)
                miss
            else
                (!self.moveHit(player, move, &immune, &mist) or self.battle.last_damage == 0);

            assert(showdown or miss or self.battle.last_damage > 0 or skip);
            assert((!showdown and miss) or !(ohko and immune));
            assert(!immune or miss or move.effect == .Binding);

            if (!showdown or !miss) {
                if (move.effect == .MirrorMove) {
                    return self.mirrorMove(player, mslot, auto, residual);
                } else if (move.effect == .Metronome) {
                    return self.metronome(player, mslot, auto, residual);
                } else if (move.effect.onEnd()) {
                    try self.onEnd(player, move);
                    return null;
                }
            }

            if (miss) {
                const foe_ident = self.battle.active(player.foe());
                const invulnerable =
                    showdown and foe.active.volatiles.Invulnerable and move.effect != .Swift;
                ohko = (!showdown or (!immune and !invulnerable)) and
                    move.effect == .OHKO and side.active.stats.spe < foe.active.stats.spe;
                if (ohko) {
                    try self.log.immune(foe_ident, .OHKO);
                } else if (immune and !invulnerable) {
                    try self.log.immune(foe_ident, .None);
                } else if (mist) {
                    if (!foe.active.volatiles.Substitute) try self.log.activate(foe_ident, .Mist);
                    try self.log.fail(foe_ident, .None);
                } else {
                    try self.log.lastmiss();
                    try self.log.miss(self.battle.active(player));
                }
                if (move.effect == .JumpKick) {
                    // Recoil is supposed to be damage/8 but damage will always be 0 here
                    assert(self.battle.last_damage == 0);
                    self.battle.last_damage = 1;
                    _ = try self.applyDamage(player, player.foe(), .None);
                    if (showdown and side.stored().hp == 0) residual.* = false;
                } else if (move.effect == .Explode) {
                    try Effects.explode(self, player);
                    try self.buildRage(player.foe());
                } else if (showdown and move.effect == .Disable) {
                    try self.buildRage(player.foe());
                }
                return null;
            }

            // On the cartridge MultiHit doesn't get set up until after damage has been applied
            // for the first time but its more convenient and efficient to set it up here
            // (Pokémon Showdown sets it up above before damage calculation)
            if (!showdown and move.effect.isMulti()) {
                Effects.multiHit(self, player, move);
                hits = side.active.volatiles.attacks;
            }

            // Pokémon Showdown only builds Rage for Disable/Explosion (regardless of whether they
            // hit/miss) when attacking into a Substitute
            const sub = showdown and foe.active.volatiles.Substitute;

            var nullified = false;
            var hit: u4 = 0;
            while (hit < hits) {
                if (hit == 0) {
                    if (crit) try self.log.crit(self.battle.active(player.foe()));
                    if (effectiveness > Effectiveness.neutral) {
                        try self.log.supereffective(self.battle.active(player.foe()));
                    } else if (effectiveness < Effectiveness.neutral) {
                        try self.log.resisted(self.battle.active(player.foe()));
                    }
                }
                if (!skip) nullified = try self.applyDamage(player.foe(), player.foe(), .None);
                if (hit == 0 and ohko) try self.log.ohko();
                hit += 1;
                if (foe.stored().hp == 0) break;
                if (!late and (!sub or move.effect == .Explode)) try self.buildRage(player.foe());
                // If the substitute breaks during a multi-hit attack, the attack ends
                if (nullified) break;
            }

            if (side.active.volatiles.MultiHit) {
                side.active.volatiles.MultiHit = false;
                assert(nullified or foe.stored().hp == 0 or
                    side.active.volatiles.attacks - hit == 0);
                side.active.volatiles.attacks = 0;
                if (showdown and move.effect == .Twineedle and !nullified and foe.stored().hp > 0) {
                    try Effects.poison(self, player, Move.get(.PoisonSting));
                }
                try self.log.hitcount(self.battle.active(player.foe()), hit);
            } else if (showdown) {
                // This should be handled much earlier but Pokémon Showdown does it here... -_-
                if (move.effect == .Binding) {
                    Effects.binding(self, player);
                    if (immune) {
                        self.battle.last_damage = 0;
                        // Pokémon Showdown logs |-damage| here instead of |-immune| because logic
                        try self.log.damage(self.battle.active(player.foe()), foe.stored(), .None);
                        return null;
                    }
                }
            }

            // Substitute being broken nullifies the move's effect completely so even
            // if an effect was intended to "always happen" it will still get skipped
            if (nullified) return null;

            // On the cartridge, "always happen" effect handlers are called in the applyDamage loop
            // above, but this is only done to setup the MultiHit looping in the first place. Moving
            // the MultiHit setup before the loop means we can avoid having to waste time doing
            // no-op handler searches
            if (move.effect.alwaysHappens()) try self.alwaysHappens(player, move, residual);

            if (foe.stored().hp == 0) return null;

            // Pokémon Showdown builds Rage at the wrong time for non-MultiHit move
            if (late and !sub and move.effect != .Disable) try self.buildRage(player.foe());

            if (!move.effect.isSpecial()) {
                // On the cartridge Rage is not considered to be "special" and thus gets executed
                // for a second time here (after being executed in the "always happens" block above)
                // but that doesn't matter since its idempotent (on the cartridge, but not in the
                // implementation below). For Twineedle we change the data to that of one with
                // PoisonChance1 given its MultiHit behavior is complete after the loop above,
                // though Pokémon Showdown handles the Twineedle secondary effect in the MultiHit
                // cleanup block above because it incorrectly puts the |-status| message before
                // |-hitcount| instead of after
                if (move.effect == .Twineedle) {
                    if (!showdown) try Effects.poison(self, player, Move.get(.PoisonSting));
                } else if (move.effect == .Disable) {
                    const result = try Effects.disable(self, player, move);
                    if (showdown) try self.buildRage(player.foe());
                    return result;
                } else {
                    try self.moveEffect(player, move);
                }
            }

            return null;
        }

        fn checkCriticalHit(self: Self, player: Player, move: Move.Data) bool {
            const side = self.battle.side(player);

            // Base speed is used for the critical hit calculation, even when Transform-ed
            var chance = @as(u16, Species.chance(side.stored().species));
            // GLITCH: Focus Energy reduces critical hit chance instead of increasing it
            chance = if (side.active.volatiles.FocusEnergy) chance / 2 else @min(chance * 2, 255);
            chance = if (move.effect == .HighCritical) @min(chance * 4, 255) else chance / 2;

            if (showdown) return self.battle.rng.chance(u8, @intCast(u8, chance), 256);
            return std.math.rotl(u8, self.battle.rng.next(), 3) < chance;
        }

        fn calcDamage(
            self: Self,
            player: Player,
            target_player: Player,
            m: ?Move.Data,
            crit: bool,
        ) bool {
            // Confusion (indicated when m == null) just needs a 40 BP physical move
            const cfz = m == null;
            const move = m orelse Move.get(.Pound);
            assert(move.bp != 0);

            const side = self.battle.side(player);
            const target = self.battle.side(target_player);

            const special = move.type.special();

            // zig fmt: off
            var atk: u32 =
                if (crit)
                    if (special) side.stored().stats.spc
                    else side.stored().stats.atk
                else
                    if (special) side.active.stats.spc
                    else side.active.stats.atk;
            var def: u32 =
                if (crit)
                    if (special) target.stored().stats.spc
                    else target.stored().stats.def
                else
                    // GLITCH: not capped to MAX_STAT_VALUE, can be 999 * 2 = 1998
                    if (special)
                        target.active.stats.spc *
                            @as(u2, if (target.active.volatiles.LightScreen) 2 else 1)
                    // Pokémon Showdown doesn't apply the opponent's Reflect to confusion's self-hit
                    else
                        target.active.stats.def *
                            @as(u2, if ((!showdown or !cfz) and
                                target.active.volatiles.Reflect) 2 else 1);
            // zig fmt: on

            // Pokémon Showdown erroneously skips this for confusion's self-hit damage, but
            // thankfully we will not overflow because the hit is only 40 BP and unboosted (the
            // highest legal unboosted attack is 366 from a level 100 Dragonite which has a max
            // computed attack of 614,880 mid-calculation)
            if ((!showdown or !cfz) and (atk > 255 or def > 255)) {
                atk = @max((atk / 4) & 255, 1);
                // GLITCH: not adjusted to min of 1 on cartridge (can lead to division-by-zero)
                def = @max((def / 4) & 255, if (showdown) 1 else 0);
            }

            const lvl = @as(u32, side.stored().level * @as(u2, if (crit) 2 else 1));

            def = @as(u32, if (move.effect == .Explode) @max(def / 2, 1) else def);

            if (def == 0) return false;

            var d: u32 = (lvl * 2 / 5) + 2;
            d *%= @as(u32, move.bp);
            d *%= atk;
            d /= def;
            d /= 50;
            d = @min(997, d);
            d += 2;

            self.battle.last_damage = @intCast(u16, d);

            return true;
        }

        fn adjustDamage(self: Self, player: Player) u16 {
            const side = self.battle.side(player);
            const foe = self.battle.foe(player);
            const types = foe.active.types;
            const move = Move.get(side.last_selected_move);

            var d = self.battle.last_damage;
            if (side.active.types.includes(move.type)) d +%= d / 2;

            const neutral = @enumToInt(Effectiveness.Neutral);
            const eff1: u16 = @enumToInt(move.type.effectiveness(types.type1));
            const eff2: u16 = @enumToInt(move.type.effectiveness(types.type2));

            // Type effectiveness matchup precedence only matters with (NVE, SE)
            if (!showdown and (eff1 + eff2) == Effectiveness.mismatch and
                Type.precedence(move.type, types.type1) > Type.precedence(move.type, types.type2))
            {
                assert(eff2 != neutral);
                d = d *% eff2 / 10;
                assert(types.type1 != types.type2);
                assert(eff1 != neutral);
                d = d *% eff1 / 10;
            } else {
                if (eff1 != neutral) d = d *% eff1 / 10;
                if (types.type1 != types.type2 and eff2 != neutral) d = d *% eff2 / 10;
            }

            self.battle.last_damage = d;
            return if (types.type1 == types.type2) eff1 * neutral else eff1 * eff2;
        }

        fn randomizeDamage(self: Self) void {
            if (self.battle.last_damage <= 1) return;

            const random = if (showdown)
                self.battle.rng.range(u8, 217, 256)
            else loop: {
                while (true) {
                    const r = std.math.rotr(u8, self.battle.rng.next(), 1);
                    if (r >= 217) break :loop r;
                }
            };

            self.battle.last_damage =
                @intCast(u16, @as(u32, self.battle.last_damage) *% random / 255);
        }

        fn specialDamage(self: Self, player: Player, move: Move.Data) !?Result {
            const side = self.battle.side(player);
            const foe = self.battle.foe(player);

            if (!try self.checkHit(player, move)) return null;

            self.battle.last_damage = switch (side.last_selected_move) {
                .SuperFang => @max(foe.stored().hp / 2, 1),
                .SeismicToss, .NightShade => side.stored().level,
                .SonicBoom => 20,
                .DragonRage => 40,
                // GLITCH: if power = 0 then a desync occurs (or a miss on Pokémon Showdown)
                .Psywave => power: {
                    const max = @intCast(u8, @as(u16, side.stored().level) * 3 / 2);
                    if (showdown) {
                        break :power self.battle.rng.range(u8, 0, max);
                    } else {
                        // GLITCH: Psywave infinite glitch loop
                        if (max <= 1) return Result.Error;
                        while (true) {
                            const r = self.battle.rng.next();
                            if (r < max) break :power r;
                        }
                    }
                },
                else => unreachable,
            };

            if (self.battle.last_damage == 0) return if (showdown) null else Result.Error;

            const sub = showdown and foe.active.volatiles.Substitute;
            _ = try self.applyDamage(player.foe(), player.foe(), .None);
            if (self.battle.foe(player).stored().hp > 0 and !sub) try self.buildRage(player.foe());

            return null;
        }

        fn counterDamage(self: Self, player: Player, move: Move.Data) !?Result {
            const foe = self.battle.foe(player);

            if (self.battle.last_damage == 0) {
                try self.log.fail(self.battle.active(player), .None);
                return null;
            }

            // Pretend Counter was used as a stand-in to fail below due to 0 BP
            const foe_last_used_move =
                Move.get(if (foe.last_used_move == .None) .Counter else foe.last_used_move);
            const foe_last_selected_move =
                Move.get(if (foe.last_selected_move == .None or
                foe.last_selected_move == .SKIP_TURN)
                .Counter
            else
                foe.last_selected_move);

            const used = foe_last_used_move.bp > 0 and
                foe.last_used_move != .Counter and
                (foe_last_used_move.type == .Normal or
                foe_last_used_move.type == .Fighting);

            const selected = foe_last_selected_move.bp > 0 and
                foe.last_selected_move != .Counter and
                (foe_last_selected_move.type == .Normal or
                foe_last_selected_move.type == .Fighting);

            if (!used and !selected) {
                try self.log.fail(self.battle.active(player), .None);
                return null;
            }

            if (!used or !selected) {
                // GLITCH: Counter desync (covered by Desync Clause Mod on Pokémon Showdown)
                if (!showdown) return Result.Error;
                try self.log.fail(self.battle.active(player), .None);
                return null;
            }

            self.battle.last_damage =
                if (self.battle.last_damage > 0x7FFF) 0xFFFF else self.battle.last_damage * 2;

            // Pokémon Showdown calls checkHit before Counter
            if (!showdown and !try self.checkHit(player, move)) return null;

            _ = try self.applyDamage(player.foe(), player.foe(), .None);
            return null;
        }

        fn applyDamage(
            self: Self,
            target_player: Player,
            sub_player: Player,
            reason: Damage,
        ) !bool {
            assert(showdown or self.battle.last_damage != 0);

            var target = self.battle.side(target_player);
            // GLITCH: Substitute + Confusion glitch
            // We check if the target has a Substitute but then apply damage to the "sub player"
            // which isn't guaranteed to be the same (e.g. crash or confusion damage) or to even
            // have a Substitute
            if (target.active.volatiles.Substitute) {
                var subbed = self.battle.side(sub_player);
                if (!subbed.active.volatiles.Substitute) return false;
                if (self.battle.last_damage >= subbed.active.volatiles.substitute) {
                    subbed.active.volatiles.substitute = 0;
                    subbed.active.volatiles.Substitute = false;
                    // battle.last_damage is not updated with the amount of HP the Substitute had
                    try self.log.end(self.battle.active(sub_player), .Substitute);
                    return true;
                } else {
                    // Safe to truncate since less than subbed.volatiles.substitute which is a u8
                    subbed.active.volatiles.substitute -= @intCast(u8, self.battle.last_damage);
                    try self.log.activate(self.battle.active(sub_player), .Substitute);
                    return false;
                }
            }

            if (self.battle.last_damage > target.stored().hp) {
                self.battle.last_damage = target.stored().hp;
            }
            target.stored().hp -= self.battle.last_damage;
            try self.log.damage(self.battle.active(target_player), target.stored(), reason);
            return false;
        }

        fn mirrorMove(self: Self, player: Player, mslot: u4, auto: bool, residual: *bool) !?Result {
            var side = self.battle.side(player);
            const foe = self.battle.foe(player);

            side.last_selected_move = foe.last_used_move;

            if (foe.last_used_move == .None or foe.last_used_move == .MirrorMove) {
                try self.log.fail(self.battle.active(player), .None);
                return null;
            }

            incrementPP(side, mslot);

            if (!try self.canMove(player, mslot, auto, false, .MirrorMove, residual)) return null;
            return self.doMove(player, mslot, auto, residual);
        }

        fn metronome(self: Self, player: Player, mslot: u4, auto: bool, residual: *bool) !?Result {
            var side = self.battle.side(player);

            side.last_selected_move = if (showdown) blk: {
                const r = self.battle.rng.range(u8, 0, @enumToInt(Move.Struggle) - 2);
                const mod = @as(u2, (if (r < @enumToInt(Move.Metronome) - 1) 1 else 2));
                break :blk @intToEnum(Move, r + mod);
            } else loop: {
                while (true) {
                    const r = self.battle.rng.next();
                    if (r == 0 or r == @enumToInt(Move.Metronome)) continue;
                    if (r >= @enumToInt(Move.Struggle)) continue;
                    break :loop @intToEnum(Move, r);
                }
            };

            incrementPP(side, mslot);

            if (!try self.canMove(player, mslot, auto, false, .Metronome, residual)) return null;
            return self.doMove(player, mslot, auto, residual);
        }

        fn checkHit(self: Self, player: Player, move: Move.Data) !bool {
            var immune = false;
            var mist = false;
            if (self.moveHit(player, move, &immune, &mist)) return true;
            assert(!immune);
            if (mist) {
                assert(!showdown);
                const foe_ident = self.battle.active(player.foe());
                try self.log.activate(foe_ident, .Mist);
                try self.log.fail(foe_ident, .None);
            } else {
                try self.log.lastmiss();
                try self.log.miss(self.battle.active(player));
            }
            return false;
        }

        fn moveHit(self: Self, player: Player, move: Move.Data, immune: *bool, mist: *bool) bool {
            var side = self.battle.side(player);
            const foe = self.battle.foe(player);

            var miss = miss: {
                assert(!side.active.volatiles.Bide);

                // Invulnerability trumps everything on Pokémon Showdown
                if (showdown) {
                    if (move.effect == .Swift) return true;
                    if (foe.active.volatiles.Invulnerable) break :miss true;
                }
                if (move.effect == .DreamEater and (!Status.is(foe.stored().status, .SLP) or
                    (showdown and foe.active.volatiles.Substitute)))
                {
                    immune.* = true;
                    if (showdown) return false;
                    break :miss true;
                }
                if (!showdown) {
                    if (move.effect == .Swift) return true;
                    if (foe.active.volatiles.Invulnerable) break :miss true;
                }

                // Hyper Beam + Sleep glitch needs to be special cased here due to control flow
                if (showdown and move.effect == .Sleep and foe.active.volatiles.Recharging) {
                    return true;
                }

                // Conversion / Haze / Light Screen / Reflect qualify but do not call moveHit
                if (foe.active.volatiles.Mist and move.effect.isStatDown()) {
                    mist.* = true;
                    if (!showdown) break :miss true;
                }

                // GLITCH: Thrash / Petal Dance / Rage get their accuracy overwritten for later hits
                const state = side.active.volatiles.state;
                var overwrite = move.effect == .Rage or move.effect == .Thrashing;
                const overwritten = overwrite and state > 0;
                assert(!overwritten or
                    (0 < state and state <= 255 and !side.active.volatiles.Bide));

                var accuracy = if (overwritten) state else @as(u16, Gen12.percent(move.accuracy));
                var boost = BOOSTS[@intCast(u4, @as(i8, side.active.boosts.accuracy) + 6)];
                accuracy = accuracy * boost[0] / boost[1];
                boost = BOOSTS[@intCast(u4, @as(i8, -foe.active.boosts.evasion) + 6)];
                accuracy = accuracy * boost[0] / boost[1];
                accuracy = @min(255, @max(1, accuracy));

                // Pokémon Showdown only overwrites if the volatile is present
                if (showdown) {
                    overwrite = side.active.volatiles.Rage or side.active.volatiles.Thrashing;
                }
                if (overwrite) side.active.volatiles.state = accuracy;

                // GLITCH: max accuracy is 255 so 1/256 chance of miss
                break :miss if (showdown)
                    !self.battle.rng.chance(u8, @intCast(u8, accuracy), 256)
                else
                    self.battle.rng.next() >= accuracy;
            };

            // Pokémon Showdown reports miss instead of fail for moves Mist-blocked that 1/256 miss
            if (showdown and mist.*) {
                mist.* = !miss;
                miss = true;
            }

            if (!miss) return true;
            self.battle.last_damage = 0;
            side.active.volatiles.Binding = false;
            return false;
        }

        fn checkFaint(self: Self, player: Player) Log.Error!?Result {
            const side = self.battle.side(player);
            if (side.stored().hp > 0) return null;

            const foe = self.battle.foe(player);
            const foe_fainted = foe.stored().hp == 0;

            const player_out = findFirstAlive(side) == 0;
            const foe_out = findFirstAlive(foe) == 0;
            const tie = player_out and foe_out;
            const more = tie or player_out or foe_out;

            if (try self.faint(player, !(more or foe_fainted))) |r| return r;
            if (foe_fainted) if (try self.faint(player.foe(), !more)) |r| return r;

            assert(!side.active.volatiles.MultiHit);
            assert(!foe.active.volatiles.MultiHit);

            if (tie) {
                try self.log.tie();
                return Result.Tie;
            } else if (player_out) {
                try self.log.win(player.foe());
                return if (player == .P1) Result.Lose else Result.Win;
            } else if (foe_out) {
                try self.log.win(player);
                return if (player == .P1) Result.Win else Result.Lose;
            }

            const foe_choice: Choice.Type = if (foe_fainted) .Switch else .Pass;
            if (player == .P1) return Result{ .p1 = .Switch, .p2 = foe_choice };
            return Result{ .p1 = foe_choice, .p2 = .Switch };
        }

        fn faint(self: Self, player: Player, done: bool) !?Result {
            var side = self.battle.side(player);
            var foe = self.battle.foe(player);
            assert(side.stored().hp == 0);

            var foe_volatiles = &foe.active.volatiles;
            assert(!foe_volatiles.MultiHit);
            if (foe_volatiles.Bide) {
                assert(!foe_volatiles.Thrashing and !foe_volatiles.Rage);
                foe_volatiles.state = if (showdown) 0 else foe_volatiles.state & 255;
                if (foe_volatiles.state != 0) return Result.Error;
            }

            // Clearing these is not strictly necessary as provided the battle hasn't ended the side
            // that just fainted will need to switch in a replacement and all of this gets cleared
            // in switchIn anyway. However, we would like to ensure the battle state presented to
            // the players at each decision point is consistent so we avoid "optimizing" this out
            // (we do always need to clear status though for Pokémon Showdown's Sleep/Freeze Clause
            // Mod)
            side.active.volatiles = .{};
            side.last_used_move = .None;
            foe.last_used_move = .None;
            const status = side.stored().status;

            side.stored().status = 0;
            // Pokémon Showdown decides double switching priority based on speed, and resets a
            // Pokémon's stats when it faints... only it still factors in paralysis -_-
            if (showdown) {
                side.active.stats.spe = if (Status.is(status, .PAR))
                    @max(side.stored().stats.spe / 4, 1)
                else
                    side.stored().stats.spe;
            }

            try self.log.faint(self.battle.active(player), done);
            return null;
        }

        fn handleResidual(self: Self, player: Player) !void {
            var side = self.battle.side(player);
            var stored = side.stored();
            const ident = self.battle.active(player);
            var volatiles = &side.active.volatiles;

            const brn = Status.is(stored.status, .BRN);
            if (brn or Status.is(stored.status, .PSN)) blk: {
                var damage = @max(stored.stats.hp / 16, 1);

                if (volatiles.Toxic) {
                    volatiles.toxic += 1;
                    damage *= volatiles.toxic;
                }

                const amount = @min(damage, stored.hp);
                if (showdown and amount == 0) break :blk;

                stored.hp -= amount;

                // Pokémon Showdown uses damageOf here but its not relevant in Generation I
                try self.log.damage(ident, stored, if (brn) Damage.Burn else Damage.Poison);
            }

            if (volatiles.LeechSeed) {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();
                const foe_ident = self.battle.active(player.foe());

                if (foe_stored.hp == 0) {
                    assert(showdown);
                    return;
                }

                var damage = @max(stored.stats.hp / 16, 1);

                // GLITCH: Leech Seed + Toxic glitch
                if (volatiles.Toxic) {
                    volatiles.toxic += 1;
                    damage *= volatiles.toxic;
                }

                const amount = @min(damage, stored.hp);
                stored.hp -= amount;

                // As above, Pokémon Showdown uses damageOf but its not relevant
                if (amount > 0) {
                    try self.log.damage(ident, stored, .LeechSeed);
                    // Pokémon Showdown erroneously updates last damage with uncapped drain damage
                    if (showdown) self.battle.last_damage = damage;
                }

                const before = foe_stored.hp;
                // Uncapped damage is added back to the foe
                foe_stored.hp = @min(foe_stored.hp + damage, foe_stored.stats.hp);
                // Pokémon Showdown uses the less specific heal here instead of drain... ???
                if (foe_stored.hp > before) try self.log.heal(foe_ident, foe_stored, .Silent);
            }
        }

        fn endTurn(self: Self) Log.Error!Result {
            assert(!self.battle.side(.P1).active.volatiles.MultiHit);
            assert(!self.battle.side(.P2).active.volatiles.MultiHit);

            if (showdown and options.ebc and self.checkEBC()) {
                try self.log.tie();
                return Result.Tie;
            }

            self.battle.turn += 1;

            if (showdown and self.battle.turn >= 1000) {
                try self.log.tie();
                return Result.Tie;
            } else if (self.battle.turn >= 65535) {
                return Result.Error;
            }

            try self.log.turn(self.battle.turn);

            return Result.Default;
        }

        fn checkEBC(self: Self) bool {
            for (self.battle.sides, 0..) |side, i| {
                const foe = self.battle.sides[~@intCast(u1, i)];

                var foe_all_ghosts = true;
                var foe_all_transform = true;
                for (foe.order, 0..) |id, j| {
                    if (id == 0) break;
                    const active = j == 0;
                    const pokemon = foe.pokemon[id - 1];

                    const ghost = pokemon.hp == 0 or
                        (if (active) foe.active.types else pokemon.types).includes(.Ghost);
                    foe_all_ghosts = foe_all_ghosts and ghost;
                    foe_all_transform = foe_all_transform and pokemon.hp == 0 or transform: {
                        for (if (active) foe.active.moves else pokemon.moves) |m| {
                            if (m.id == .None) break :transform true;
                            if (m.id != .Transform) break :transform false;
                        }
                        break :transform true;
                    };
                }

                for (side.order, 0..) |id, j| {
                    if (id == 0) break;
                    const active = j == 0;
                    const pokemon = side.pokemon[id - 1];

                    if (pokemon.hp == 0 or Status.is(pokemon.status, .FRZ)) continue;
                    const transform = foe_all_transform and transform: {
                        for (if (active) side.active.moves else pokemon.moves) |m| {
                            if (m.id == .None) break :transform true;
                            if (m.id != .Transform) break :transform false;
                        }
                        break :transform true;
                    };
                    if (transform) continue;
                    const no_pp = foe_all_ghosts and no_pp: {
                        for (if (active) side.active.moves else pokemon.moves) |m| {
                            if (m.pp != 0) break :no_pp false;
                        }
                        break :no_pp true;
                    };
                    if (no_pp) continue;

                    return false;
                }

                if (i == 1) return true;
            }

            return false;
        }

        inline fn onBegin(
            self: Self,
            player: Player,
            move: Move.Data,
            mslot: u8,
            residual: *bool,
        ) !void {
            assert(move.effect.onBegin());
            return switch (move.effect) {
                .Confusion => Effects.confusion(self, player, move),
                .Conversion => Effects.conversion(self, player),
                .FocusEnergy => Effects.focusEnergy(self, player),
                .Haze => Effects.haze(self, player),
                .Heal => Effects.heal(self, player),
                .LeechSeed => Effects.leechSeed(self, player, move),
                .LightScreen => Effects.lightScreen(self, player),
                .Mimic => Effects.mimic(self, player, move, mslot),
                .Mist => Effects.mist(self, player),
                .Paralyze => Effects.paralyze(self, player, move),
                .Poison => Effects.poison(self, player, move),
                .Reflect => Effects.reflect(self, player),
                .Splash => Effects.splash(self, player),
                .Substitute => Effects.substitute(self, player, residual),
                .SwitchAndTeleport => Effects.switchAndTeleport(self, player, move),
                .Transform => Effects.transform(self, player),
                else => unreachable,
            };
        }

        inline fn onEnd(self: Self, player: Player, move: Move.Data) !void {
            assert(move.effect.onEnd());
            return switch (move.effect) {
                .Bide => Effects.bide(self, player),
                // zig fmt: off
                .AttackUp1, .AttackUp2, .DefenseUp1, .DefenseUp2,
                .EvasionUp1, .SpecialUp1, .SpecialUp2, .SpeedUp2 =>
                    Effects.boost(self, player, move),
                .AccuracyDown1, .AttackDown1, .DefenseDown1, .DefenseDown2, .SpeedDown1 =>
                    Effects.unboost(self, player, move),
                // zig fmt: on
                .Sleep => Effects.sleep(self, player, move),
                else => unreachable,
            };
        }

        inline fn alwaysHappens(
            self: Self,
            player: Player,
            move: Move.Data,
            residual: *bool,
        ) !void {
            assert(move.effect.alwaysHappens());
            return switch (move.effect) {
                .DrainHP, .DreamEater => Effects.drainHP(self, player),
                .Explode => Effects.explode(self, player),
                .PayDay => Effects.payDay(self, player),
                .Rage => Effects.rage(self, player),
                .Recoil => Effects.recoil(self, player, residual),
                .JumpKick, .Binding => {},
                else => unreachable,
            };
        }

        inline fn moveEffect(self: Self, player: Player, move: Move.Data) !void {
            return switch (move.effect) {
                .BurnChance1, .BurnChance2 => Effects.burnChance(self, player, move),
                .ConfusionChance => Effects.confusion(self, player, move),
                .FlinchChance1, .FlinchChance2 => Effects.flinchChance(self, player, move),
                .FreezeChance => Effects.freezeChance(self, player, move),
                .HyperBeam => Effects.hyperBeam(self, player),
                .MultiHit, .DoubleHit, .Twineedle => unreachable,
                .ParalyzeChance1, .ParalyzeChance2 => Effects.paralyzeChance(self, player, move),
                .PoisonChance1, .PoisonChance2 => Effects.poison(self, player, move),
                // zig fmt: off
                .AttackDownChance, .DefenseDownChance, .SpecialDownChance, .SpeedDownChance =>
                    Effects.unboost(self, player, move),
                // zig fmt: on
                else => {},
            };
        }

        pub const Effects = struct {
            fn bide(self: Self, player: Player) !void {
                var side = self.battle.side(player);

                side.active.volatiles.Bide = true;
                assert(!side.active.volatiles.Thrashing and !side.active.volatiles.Rage);
                side.active.volatiles.state = 0;
                side.active.volatiles.attacks = @intCast(u3, if (showdown)
                    self.battle.rng.range(u4, 2, 4)
                else
                    (self.battle.rng.next() & 1) + 2);

                try self.log.start(self.battle.active(player), .Bide);
            }

            fn burnChance(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();

                if (foe.active.volatiles.Substitute) return;

                if (Status.any(foe_stored.status)) {
                    if (showdown and !foe.active.types.includes(move.type)) {
                        self.battle.rng.advance(1);
                    }
                    // GLITCH: Freeze top move selection desync can occur if thawed player is slower
                    if (Status.is(foe_stored.status, .FRZ)) {
                        assert(move.type == .Fire);
                        try self.log.curestatus(
                            self.battle.active(player.foe()),
                            foe_stored.status,
                            .Message,
                        );
                        foe_stored.status = 0;
                    }
                    return;
                }

                if (foe.active.types.includes(move.type)) return;
                if (!self.secondaryChance(move.effect == .BurnChance1)) return;

                foe_stored.status = Status.init(.BRN);
                foe.active.stats.atk = @max(foe.active.stats.atk / 2, 1);

                try self.log.status(self.battle.active(player.foe()), foe_stored.status, .None);
            }

            fn charge(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                var volatiles = &side.active.volatiles;

                volatiles.Charging = true;
                const move = side.last_selected_move;
                if (move == .Fly or move == .Dig) volatiles.Invulnerable = true;
                try self.log.laststill();
                try self.log.prepare(self.battle.active(player), move);
            }

            fn confusion(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                const sub = foe.active.volatiles.Substitute;

                if (move.effect == .ConfusionChance) {
                    const chance = if (showdown)
                        self.battle.rng.chance(u8, 25, 256)
                    else
                        self.battle.rng.next() < Gen12.percent(10);
                    if (!chance) return;
                } else {
                    if (showdown) {
                        if (!try self.checkHit(player, move)) {
                            return;
                        } else if (sub) {
                            return self.log.fail(self.battle.active(player.foe()), .None);
                        }
                    } else {
                        if (sub) {
                            return self.log.fail(self.battle.active(player.foe()), .None);
                        } else if (!try self.checkHit(player, move)) {
                            return;
                        }
                    }
                }

                if (foe.active.volatiles.Confusion) return;
                foe.active.volatiles.Confusion = true;
                foe.active.volatiles.confusion = @intCast(u3, if (showdown)
                    self.battle.rng.range(u8, 2, 6)
                else
                    (self.battle.rng.next() & 3) + 2);

                try self.log.start(self.battle.active(player.foe()), .Confusion);
            }

            fn conversion(self: Self, player: Player) !void {
                const foe = self.battle.foe(player);

                if (foe.active.volatiles.Invulnerable) {
                    try self.log.lastmiss();
                    return self.log.miss(self.battle.active(player));
                }

                self.battle.side(player).active.types = foe.active.types;
                return self.log.typechange(
                    self.battle.active(player),
                    foe.active.types,
                    self.battle.active(player.foe()),
                );
            }

            fn disable(self: Self, player: Player, move: Move.Data) !?Result {
                var foe = self.battle.foe(player);
                var volatiles = &foe.active.volatiles;
                const foe_ident = self.battle.active(player.foe());

                // Pokémon Showdown handles hit/miss earlier in doMove
                if (!showdown and !try self.checkHit(player, move)) return null;

                if (volatiles.disabled_move != 0) {
                    try self.log.fail(foe_ident, .None);
                    return null;
                }

                var n: u4 = 0;
                var err = true;
                for (foe.active.moves) |m| {
                    if (m.pp > 0) {
                        n += 1;
                        if (m.id != .None) err = false;
                    }
                }

                // Technically this is still considered simply a "miss" on the cartridge,
                // but diverging from Pokémon Showdown here would mostly just be pedantic
                if (n == 0) {
                    try self.log.fail(foe_ident, .None);
                    return null;
                } else if (err) {
                    // GLITCH: Transform + Mirror Move / Metronome PP softlock
                    assert(!showdown);
                    return Result.Error;
                }

                volatiles.disabled_move = @intCast(u3, randomMoveSlot(self, &foe.active.moves, n));
                volatiles.disabled_duration = @intCast(u4, if (showdown)
                    self.battle.rng.range(u8, 1, 9)
                else
                    (self.battle.rng.next() & 7) + 1);

                try self.log.startEffect(
                    foe_ident,
                    .Disable,
                    foe.active.move(volatiles.disabled_move).id,
                );
                return null;
            }

            fn drainHP(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                var stored = side.stored();

                if (self.battle.last_damage == 0) {
                    assert(showdown);
                    if (!self.battle.foe(player).active.volatiles.Substitute) return;
                }

                const drain = @max(self.battle.last_damage / 2, 1);
                self.battle.last_damage = drain;

                if (stored.hp == stored.stats.hp) return;
                stored.hp = @min(stored.stats.hp, stored.hp + drain);

                try self.log.drain(
                    self.battle.active(player),
                    stored,
                    self.battle.active(player.foe()),
                );
            }

            fn explode(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                var stored = side.stored();

                stored.hp = 0;
                // Pokémon Showdown sets the status to 0 on faint(), and we need to do the same to
                // be able to correctly implement Pokémon Showdown's dumb speed-based switches
                if (!showdown) stored.status = 0;
                side.active.volatiles.LeechSeed = false;
            }

            fn flinchChance(self: Self, player: Player, move: Move.Data) void {
                var volatiles = &self.battle.foe(player).active.volatiles;

                if (volatiles.Substitute) return;
                if (!self.secondaryChance(move.effect == .FlinchChance1)) return;

                volatiles.Flinch = true;
                volatiles.Recharging = false;
            }

            fn focusEnergy(self: Self, player: Player) !void {
                var side = self.battle.side(player);

                if (side.active.volatiles.FocusEnergy) return;
                side.active.volatiles.FocusEnergy = true;

                try self.log.start(self.battle.active(player), .FocusEnergy);
            }

            fn freezeChance(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();
                const foe_ident = self.battle.active(player.foe());

                if (foe.active.volatiles.Substitute) return;

                if (Status.any(foe_stored.status)) {
                    return if (showdown and !foe.active.types.includes(move.type))
                        self.battle.rng.advance(1);
                }

                const chance = !foe.active.types.includes(move.type) and if (showdown)
                    self.battle.rng.chance(u8, 26, 256)
                else
                    self.battle.rng.next() < 1 + Gen12.percent(10);
                if (!chance) return;

                // Freeze Clause Mod
                if (showdown) for (foe.pokemon) |p| if (Status.is(p.status, .FRZ)) return;

                foe_stored.status = Status.init(.FRZ);
                // GLITCH: Hyper Beam recharging status is not cleared

                try self.log.status(foe_ident, foe_stored.status, .None);
            }

            fn haze(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                var foe = self.battle.foe(player);

                var side_stored = side.stored();
                var foe_stored = foe.stored();

                const player_ident = self.battle.active(player);
                const foe_ident = self.battle.active(player.foe());

                side.active.boosts = .{};
                foe.active.boosts = .{};

                side.active.stats = side_stored.stats;
                foe.active.stats = foe_stored.stats;

                try self.log.activate(player_ident, .Haze);
                try self.log.clearallboost();

                // Pokémon Showdown clears P1 then P2 instead of status -> side -> foe
                if (showdown) {
                    for (&self.battle.sides, 0..) |*s, i| {
                        const p = @intToEnum(Player, i);
                        // Pokémon Showdown incorrectly does not prevent sleep/freeze from moving
                        if (p != player and Status.any(s.stored().status)) {
                            try self.log.curestatus(foe_ident, foe_stored.status, .Silent);
                            s.stored().status = 0;
                        } else if (showdown and s.stored().status == Status.TOX) {
                            s.stored().status = Status.init(.PSN);
                            try self.log.status(self.battle.active(p), s.stored().status, .None);
                        }
                        try self.clearVolatiles(p);
                    }
                } else {
                    if (Status.any(foe_stored.status)) {
                        if (Status.is(foe_stored.status, .FRZ) or
                            Status.is(foe_stored.status, .SLP))
                        {
                            foe.last_selected_move = .SKIP_TURN;
                        }
                        try self.log.curestatus(foe_ident, foe_stored.status, .Silent);
                        foe_stored.status = 0;
                    }
                    try self.clearVolatiles(player);
                    try self.clearVolatiles(player.foe());
                }
            }

            fn heal(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                var stored = side.stored();
                const ident = self.battle.active(player);

                // GLITCH: HP recovery move failure glitches
                const delta = stored.stats.hp - stored.hp;
                if (delta == 0 or delta & 255 == 255) return try self.log.fail(ident, .None);

                const rest = side.last_selected_move == .Rest;
                if (rest) {
                    // Adding the sleep status runs the sleep condition handler to roll duration
                    if (showdown) self.battle.rng.advance(1);
                    stored.status = Status.slf(2);
                    try self.log.statusFrom(ident, stored.status, Move.Rest);
                    stored.hp = stored.stats.hp;
                } else {
                    stored.hp = @min(stored.stats.hp, stored.hp + (stored.stats.hp / 2));
                }
                try self.log.heal(ident, stored, if (rest) Heal.Silent else Heal.None);
            }

            fn hyperBeam(self: Self, player: Player) !void {
                self.battle.side(player).active.volatiles.Recharging = true;
                try self.log.mustrecharge(self.battle.active(player));
            }

            fn leechSeed(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);

                if (showdown) {
                    // Invulnerability trumps type immunity on Pokémon Showdown
                    if (!foe.active.volatiles.Invulnerable and foe.active.types.includes(.Grass)) {
                        return self.log.immune(self.battle.active(player.foe()), .None);
                    }
                    if (!try self.checkHit(player, move)) return;
                    if (foe.active.volatiles.LeechSeed) return;
                } else {
                    if (!try self.checkHit(player, move)) return;
                    if (foe.active.types.includes(.Grass) or foe.active.volatiles.LeechSeed) {
                        try self.log.lastmiss();
                        return self.log.miss(self.battle.active(player));
                    }
                }

                foe.active.volatiles.LeechSeed = true;

                try self.log.start(self.battle.active(player.foe()), .LeechSeed);
            }

            fn lightScreen(self: Self, player: Player) !void {
                var side = self.battle.side(player);

                if (side.active.volatiles.LightScreen) {
                    return self.log.fail(self.battle.active(player), .None);
                }
                side.active.volatiles.LightScreen = true;

                try self.log.start(self.battle.active(player), .LightScreen);
            }

            fn mimic(self: Self, player: Player, move: Move.Data, mslot: u8) !void {
                var side = self.battle.side(player);
                var foe = self.battle.foe(player);

                // Pokémon Showdown incorrectly requires the user to have Mimic (but not necessarily
                // at mslot). In reality, Mimic can also be called via Metronome or Mirror Move
                assert(showdown or side.active.move(mslot).id == .Mimic or
                    side.active.move(mslot).id == .Metronome or
                    side.active.move(mslot).id == .MirrorMove);

                // Pokémon Showdown incorrectly replaces the existing Mimic's slot instead of mslot
                var oslot = mslot;
                if (showdown) {
                    const has_mimic = has_mimic: {
                        for (side.active.moves, 0..) |m, i| {
                            if (m.id == .Mimic) {
                                oslot = @intCast(u8, i + 1);
                                break :has_mimic true;
                            }
                        }
                        break :has_mimic false;
                    };
                    // If the foe is Invulnerable we still want to fall through to checkHit to be
                    // able to trigger |-miss| instead of |-fail|
                    if (!has_mimic and !foe.active.volatiles.Invulnerable) {
                        return try self.log.fail(self.battle.active(player.foe()), .None);
                    }
                }
                if (!try self.checkHit(player, move)) return;

                const rslot = randomMoveSlot(self, &foe.active.moves, 0);
                side.active.move(oslot).id = foe.active.move(rslot).id;

                try self.log.startEffect(
                    self.battle.active(player),
                    .Mimic,
                    side.active.move(oslot).id,
                );
            }

            fn mist(self: Self, player: Player) !void {
                var side = self.battle.side(player);

                if (side.active.volatiles.Mist) return;
                side.active.volatiles.Mist = true;

                try self.log.start(self.battle.active(player), .Mist);
            }

            fn multiHit(self: Self, player: Player, move: Move.Data) void {
                var side = self.battle.side(player);

                assert(!side.active.volatiles.MultiHit);
                side.active.volatiles.MultiHit = true;

                side.active.volatiles.attacks =
                    if (move.effect == .MultiHit) distribution(self) else 2;
            }

            fn paralyze(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();
                const foe_ident = self.battle.active(player.foe());

                // Only Thunder Wave checks for type-immunity, not Glare
                const immune = move.type == .Electric and foe.active.types.immune(move.type);

                if (showdown) {
                    // Invulnerability trumps type immunity on Pokémon Showdown
                    if (immune and !foe.active.volatiles.Invulnerable) {
                        return self.log.immune(foe_ident, .None);
                    }
                    if (!try self.checkHit(player, move)) return;
                }
                if (Status.any(foe_stored.status)) {
                    return self.log.fail(
                        foe_ident,
                        if (Status.is(foe_stored.status, .PAR)) .Paralysis else .None,
                    );
                }
                if (!showdown) {
                    if (immune) return self.log.immune(foe_ident, .None);
                    if (!try self.checkHit(player, move)) return;
                }

                foe_stored.status = Status.init(.PAR);
                foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

                try self.log.status(foe_ident, foe_stored.status, .None);
            }

            fn paralyzeChance(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();

                if (foe.active.volatiles.Substitute) return;

                if (Status.any(foe_stored.status)) {
                    return if (showdown and !foe.active.types.includes(move.type))
                        self.battle.rng.advance(1);
                }

                // Body Slam can't paralyze a Normal type Pokémon
                if (foe.active.types.includes(move.type)) return;
                if (!self.secondaryChance(move.effect == .ParalyzeChance1)) return;

                foe_stored.status = Status.init(.PAR);
                foe.active.stats.spe = @max(foe.active.stats.spe / 4, 1);

                try self.log.status(self.battle.active(player.foe()), foe_stored.status, .None);
            }

            fn payDay(self: Self, player: Player) !void {
                if (!showdown or !self.battle.foe(player).active.volatiles.Substitute) {
                    try self.log.fieldactivate();
                }
            }

            fn poison(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();
                const foe_ident = self.battle.active(player.foe());
                const toxic = self.battle.side(player).last_selected_move == .Toxic;

                if (showdown and move.effect == .Poison and !try self.checkHit(player, move)) {
                    return;
                } else if (foe.active.volatiles.Substitute) {
                    if (move.effect != .Poison) return;
                    return self.log.fail(foe_ident, .None);
                } else if (Status.any(foe_stored.status)) {
                    if (move.effect != .Poison) return if (showdown) self.battle.rng.advance(1);
                    // Pokémon Showdown considers Toxic to be a status even in Generation I and so
                    // will not include a fail reason for Toxic vs. Poison or vice-versa...
                    return self.log.fail(foe_ident, if (Status.is(foe_stored.status, .PSN))
                        if (!showdown)
                            .Poison
                        else if (toxic == (foe_stored.status == Status.TOX))
                            if (toxic) .Toxic else .Poison
                        else
                            .None
                    else
                        .None);
                } else if (foe.active.types.includes(.Poison)) {
                    if (move.effect != .Poison) return if (showdown) self.battle.rng.advance(1);
                    return self.log.immune(foe_ident, .None);
                }

                if (move.effect == .Poison) {
                    if (!showdown and !try self.checkHit(player, move)) return;
                } else {
                    const chance = if (showdown)
                        self.battle.rng.chance(
                            u8,
                            @as(u8, if (move.effect == .PoisonChance1) 52 else 103),
                            256,
                        )
                    else
                        self.battle.rng.next() < 1 + (if (move.effect == .PoisonChance1)
                            Gen12.percent(20)
                        else
                            Gen12.percent(40));
                    if (!chance) return;
                }

                foe_stored.status = Status.init(.PSN);
                if (toxic) {
                    if (showdown) foe_stored.status = Status.TOX;
                    foe.active.volatiles.Toxic = true;
                    foe.active.volatiles.toxic = 0;
                }

                try self.log.status(foe_ident, foe_stored.status, .None);
            }

            fn rage(self: Self, player: Player) !void {
                var volatiles = &self.battle.side(player).active.volatiles;
                assert(!volatiles.Bide);
                volatiles.Rage = true;
            }

            fn recoil(self: Self, player: Player, residual: *bool) !void {
                var side = self.battle.side(player);
                var stored = side.stored();

                const damage = @intCast(i16, @max(self.battle.last_damage /
                    @as(u8, if (side.last_selected_move == .Struggle) 2 else 4), 1));
                stored.hp = @intCast(u16, @max(@intCast(i16, stored.hp) - damage, 0));

                try self.log.damageOf(
                    self.battle.active(player),
                    stored,
                    .RecoilOf,
                    self.battle.active(player.foe()),
                );
                if (showdown and stored.hp == 0) residual.* = false;
            }

            fn reflect(self: Self, player: Player) !void {
                var side = self.battle.side(player);

                if (side.active.volatiles.Reflect) {
                    return self.log.fail(self.battle.active(player), .None);
                }
                side.active.volatiles.Reflect = true;

                try self.log.start(self.battle.active(player), .Reflect);
            }

            fn sleep(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                var foe_stored = foe.stored();
                const foe_ident = self.battle.active(player.foe());

                if (foe.active.volatiles.Recharging) {
                    // Hit test not applied if the target is recharging (bypass)
                    // The volatile itself actually gets cleared below since on Pokémon Showdown
                    // the Sleep Clause Mod might activate, causing us to not actually bypass
                } else {
                    if (Status.any(foe_stored.status)) {
                        return self.log.fail(
                            foe_ident,
                            if (Status.is(foe_stored.status, .SLP)) .Sleep else .None,
                        );
                    }
                    // If checkHit in doMove didn't return true Pokémon Showdown wouldn't be in here
                    if (!showdown and !try self.checkHit(player, move)) return;
                }

                // Sleep Clause Mod
                if (showdown) {
                    for (foe.pokemon) |p| {
                        if (Status.is(p.status, .SLP) and !Status.is(p.status, .EXT)) return;
                    }
                }
                foe.active.volatiles.Recharging = false;

                const duration = @intCast(u3, if (showdown)
                    self.battle.rng.range(u8, 1, 8)
                else loop: {
                    while (true) {
                        const r = self.battle.rng.next() & 7;
                        if (r != 0) break :loop r;
                    }
                });

                foe_stored.status = Status.slp(duration);
                try self.log.statusFrom(
                    foe_ident,
                    foe_stored.status,
                    self.battle.side(player).last_selected_move,
                );
            }

            fn splash(self: Self, player: Player) !void {
                try self.log.activate(self.battle.active(player), .Splash);
            }

            fn substitute(self: Self, player: Player, residual: *bool) !void {
                var side = self.battle.side(player);
                if (side.active.volatiles.Substitute) {
                    try self.log.fail(self.battle.active(player), .Substitute);
                    return;
                }

                assert(side.stored().stats.hp <= 1023);
                // Will be 0 if HP is <= 3 meaning that the user gets a 1 HP Substitute for "free"
                const hp = @intCast(u8, side.stored().stats.hp / 4);
                // Pokénon Showdown incorrectly checks for 1/4 HP based on `target.maxhp / 4` which
                // returns a floating point value and thus only correctly implements the Substitute
                // 1/4 glitch when the target's HP is exactly divisible by 4 (here we're using an
                // inlined divCeil routine to avoid having to convert to floating point)
                const required_hp =
                    if (showdown) @divFloor(side.stored().stats.hp - 1, 4) + 1 else hp;
                if (side.stored().hp < required_hp) {
                    try self.log.fail(self.battle.active(player), .Weak);
                    return;
                }

                // GLITCH: can leave the user with 0 HP (faints later) because didn't check <= above
                side.stored().hp -= hp;
                side.active.volatiles.substitute = hp + 1;
                side.active.volatiles.Substitute = true;
                try self.log.start(self.battle.active(player), .Substitute);
                if (hp > 0) {
                    try self.log.damage(self.battle.active(player), side.stored(), .None);
                    if (showdown and side.stored().hp == 0) residual.* = false;
                }
            }

            fn switchAndTeleport(self: Self, player: Player, move: Move.Data) !void {
                if (!showdown or self.battle.side(player).last_selected_move == .Teleport) return;

                // Whirlwind/Roar should not roll to hit/reset damage but Pokémon Showdown does...
                _ = try self.checkHit(player, move);
                self.battle.last_damage = 0;
            }

            fn thrashing(self: Self, player: Player) void {
                var volatiles = &self.battle.side(player).active.volatiles;
                assert(!volatiles.Thrashing);
                assert(!volatiles.Bide);

                volatiles.Thrashing = true;
                volatiles.attacks = @intCast(u3, if (showdown)
                    self.battle.rng.range(u8, 2, 4)
                else
                    (self.battle.rng.next() & 1) + 2);
            }

            fn transform(self: Self, player: Player) !void {
                var side = self.battle.side(player);
                const foe = self.battle.foe(player);
                const foe_ident = self.battle.active(player.foe());

                side.active.volatiles.Transform = true;
                // foe could themselves be transformed
                side.active.volatiles.transform = if (foe.active.volatiles.transform != 0)
                    foe.active.volatiles.transform
                else
                    foe_ident.int();

                // HP is not copied by Transform
                side.active.stats.atk = foe.active.stats.atk;
                side.active.stats.def = foe.active.stats.def;
                side.active.stats.spe = foe.active.stats.spe;
                side.active.stats.spc = foe.active.stats.spc;

                side.active.species = foe.active.species;
                side.active.types = foe.active.types;
                side.active.boosts = foe.active.boosts;
                for (foe.active.moves, 0..) |m, i| {
                    side.active.moves[i].id = m.id;
                    side.active.moves[i].pp = if (m.id != .None) 5 else 0;
                }

                try self.log.transform(self.battle.active(player), foe_ident);
            }

            fn binding(self: Self, player: Player) void {
                var side = self.battle.side(player);
                var foe = self.battle.foe(player);

                if (side.active.volatiles.Binding) return;
                side.active.volatiles.Binding = true;
                // GLITCH: Hyper Beam automatic selection glitch if Recharging gets cleared on miss
                // (Pokémon Showdown unitentionally patches this, preventing automatic selection)
                if (!showdown) foe.active.volatiles.Recharging = false;

                side.active.volatiles.attacks = distribution(self) - 1;
            }

            fn boost(self: Self, player: Player, move: Move.Data) !void {
                var side = self.battle.side(player);
                const ident = self.battle.active(player);

                var stats = &side.active.stats;
                var boosts = &side.active.boosts;

                switch (move.effect) {
                    .AttackUp1, .AttackUp2, .Rage => {
                        assert(boosts.atk >= -6 and boosts.atk <= 6);
                        if (boosts.atk == 6) return try self.log.fail(ident, .None);
                        const n: u2 = if (move.effect == .AttackUp2) 2 else 1;
                        boosts.atk = @intCast(i4, @min(6, @as(i8, boosts.atk) + n));
                        const reason = if (move.effect == .Rage) Boost.Rage else Boost.Attack;
                        if (stats.atk == MAX_STAT_VALUE) {
                            boosts.atk -= 1;
                            if (showdown) {
                                try self.log.boost(ident, reason, n);
                                try self.log.boost(ident, Boost.Attack, -1);
                                if (move.effect == .Rage) return;
                            }
                            return try self.log.fail(ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.atk) + 6)];
                        const stat = self.unmodifiedStats(side).atk;
                        stats.atk = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                        try self.log.boost(ident, reason, n);
                        // Pokémon Showdown doesn't re-apply status modifiers after Rage boosts
                        if (showdown and move.effect == .Rage) return;
                    },
                    .DefenseUp1, .DefenseUp2 => {
                        assert(boosts.def >= -6 and boosts.def <= 6);
                        if (boosts.def == 6) return try self.log.fail(ident, .None);
                        const n: u2 = if (move.effect == .DefenseUp2) 2 else 1;
                        boosts.def = @intCast(i4, @min(6, @as(i8, boosts.def) + n));
                        if (stats.def == MAX_STAT_VALUE) {
                            boosts.def -= 1;
                            if (showdown) {
                                try self.log.boost(ident, .Defense, n);
                                try self.log.boost(ident, .Defense, -1);
                            }
                            return try self.log.fail(ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.def) + 6)];
                        const stat = self.unmodifiedStats(side).def;
                        stats.def = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                        try self.log.boost(ident, .Defense, n);
                    },
                    .SpeedUp2 => {
                        assert(boosts.spe >= -6 and boosts.spe <= 6);
                        if (boosts.spe == 6) return try self.log.fail(ident, .None);
                        boosts.spe = @intCast(i4, @min(6, @as(i8, boosts.spe) + 2));
                        if (stats.spe == MAX_STAT_VALUE) {
                            boosts.spe -= 1;
                            if (showdown) {
                                try self.log.boost(ident, .Speed, 2);
                                try self.log.boost(ident, .Speed, -1);
                            }
                            return try self.log.fail(ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spe) + 6)];
                        const stat = self.unmodifiedStats(side).spe;
                        stats.spe = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                        try self.log.boost(ident, .Speed, 2);
                    },
                    .SpecialUp1, .SpecialUp2 => {
                        assert(boosts.spc >= -6 and boosts.spc <= 6);
                        if (boosts.spc == 6) return try self.log.fail(ident, .None);
                        const n: u2 = if (move.effect == .SpecialUp2) 2 else 1;
                        boosts.spc = @intCast(i4, @min(6, @as(i8, boosts.spc) + n));
                        if (stats.spc == MAX_STAT_VALUE) {
                            boosts.spc -= 1;
                            if (showdown) {
                                try self.log.boost(ident, .SpecialAttack, n);
                                try self.log.boost(ident, .SpecialAttack, -1);
                                try self.log.boost(ident, .SpecialDefense, n);
                                try self.log.boost(ident, .SpecialDefense, -1);
                            }
                            return try self.log.fail(ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spc) + 6)];
                        const stat = self.unmodifiedStats(side).spc;
                        stats.spc = @min(MAX_STAT_VALUE, stat * mod[0] / mod[1]);
                        try self.log.boost(ident, .SpecialAttack, n);
                        try self.log.boost(ident, .SpecialDefense, n);
                    },
                    .EvasionUp1 => {
                        assert(boosts.evasion >= -6 and boosts.evasion <= 6);
                        if (boosts.evasion == 6) return try self.log.fail(ident, .None);
                        boosts.evasion = @intCast(i4, @min(6, @as(i8, boosts.evasion) + 1));
                        try self.log.boost(ident, .Evasion, 1);
                    },
                    else => unreachable,
                }

                // GLITCH: Stat modification errors glitch
                statusModify(
                    self.battle.foe(player).stored().status,
                    &self.battle.foe(player).active.stats,
                );
            }

            fn unboost(self: Self, player: Player, move: Move.Data) !void {
                var foe = self.battle.foe(player);
                const foe_ident = self.battle.active(player.foe());

                if (foe.active.volatiles.Substitute) {
                    return if (!move.effect.isStatDownChance()) self.log.fail(foe_ident, .None);
                }

                if (move.effect.isStatDownChance()) {
                    const chance = if (showdown)
                        self.battle.rng.chance(u8, 85, 256)
                    else
                        self.battle.rng.next() < Gen12.percent(33) + 1;
                    if (!chance or foe.active.volatiles.Invulnerable) return;
                } else if (!showdown and !try self.checkHit(player, move)) {
                    return; // checkHit already checks for Invulnerable
                }

                var stats = &foe.active.stats;
                var boosts = &foe.active.boosts;

                switch (move.effect) {
                    .AttackDown1, .AttackDownChance => {
                        assert(boosts.atk >= -6 and boosts.atk <= 6);
                        if (boosts.atk == -6) return try self.log.fail(foe_ident, .None);
                        boosts.atk = @intCast(i4, @max(-6, @as(i8, boosts.atk) - 1));
                        if (stats.atk == 1) {
                            boosts.atk += 1;
                            if (showdown) {
                                try self.log.boost(foe_ident, .Attack, -1);
                                try self.log.boost(foe_ident, .Attack, 1);
                            }
                            return try self.log.fail(foe_ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.atk) + 6)];
                        const stat = self.unmodifiedStats(foe).atk;
                        stats.atk = @max(1, stat * mod[0] / mod[1]);
                        try self.log.boost(foe_ident, .Attack, -1);
                    },
                    .DefenseDown1, .DefenseDown2, .DefenseDownChance => {
                        assert(boosts.def >= -6 and boosts.def <= 6);
                        if (boosts.def == -6) return try self.log.fail(foe_ident, .None);
                        const n: u2 = if (move.effect == .DefenseDown2) 2 else 1;
                        boosts.def = @intCast(i4, @max(-6, @as(i8, boosts.def) - n));
                        if (stats.def == 1) {
                            boosts.def += 1;
                            if (showdown) {
                                try self.log.boost(foe_ident, .Defense, -@as(i8, n));
                                try self.log.boost(foe_ident, .Defense, 1);
                            }
                            return try self.log.fail(foe_ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.def) + 6)];
                        const stat = self.unmodifiedStats(foe).def;
                        stats.def = @max(1, stat * mod[0] / mod[1]);
                        try self.log.boost(foe_ident, .Defense, -@as(i8, n));
                    },
                    .SpeedDown1, .SpeedDownChance => {
                        assert(boosts.spe >= -6 and boosts.spe <= 6);
                        if (boosts.spe == -6) return try self.log.fail(foe_ident, .None);
                        boosts.spe = @intCast(i4, @max(-6, @as(i8, boosts.spe) - 1));
                        if (stats.spe == 1) {
                            boosts.spe += 1;
                            if (showdown) {
                                try self.log.boost(foe_ident, .Speed, -1);
                                try self.log.boost(foe_ident, .Speed, 1);
                            }
                            return try self.log.fail(foe_ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spe) + 6)];
                        const stat = self.unmodifiedStats(foe).spe;
                        stats.spe = @max(1, stat * mod[0] / mod[1]);
                        try self.log.boost(foe_ident, .Speed, -1);
                        assert(boosts.spe >= -6);
                    },
                    .SpecialDownChance => {
                        assert(boosts.spc >= -6 and boosts.spc <= 6);
                        if (boosts.spc == -6) return try self.log.fail(foe_ident, .None);
                        boosts.spc = @intCast(i4, @max(-6, @as(i8, boosts.spc) - 1));
                        if (stats.spc == 1) {
                            boosts.spc += 1;
                            if (showdown) {
                                try self.log.boost(foe_ident, .SpecialAttack, -1);
                                try self.log.boost(foe_ident, .SpecialAttack, 1);
                                try self.log.boost(foe_ident, .SpecialDefense, -1);
                                try self.log.boost(foe_ident, .SpecialDefense, 1);
                            }
                            return try self.log.fail(foe_ident, .None);
                        }
                        var mod = BOOSTS[@intCast(u4, @as(i8, boosts.spc) + 6)];
                        const stat = self.unmodifiedStats(foe).spc;
                        stats.spc = @max(1, stat * mod[0] / mod[1]);
                        try self.log.boost(foe_ident, .SpecialAttack, -1);
                        try self.log.boost(foe_ident, .SpecialDefense, -1);
                    },
                    .AccuracyDown1 => {
                        assert(boosts.accuracy >= -6 and boosts.accuracy <= 6);
                        if (boosts.accuracy == -6) return try self.log.fail(foe_ident, .None);
                        boosts.accuracy = @intCast(i4, @max(-6, @as(i8, boosts.accuracy) - 1));
                        try self.log.boost(foe_ident, .Accuracy, -1);
                    },
                    else => unreachable,
                }

                // GLITCH: Stat modification errors glitch
                statusModify(foe.stored().status, stats);
            }
        };

        fn unmodifiedStats(self: Self, side: *Side) *Stats(u16) {
            if (!side.active.volatiles.Transform) return &side.stored().stats;
            const id = ID.from(side.active.volatiles.transform);
            return &self.battle.side(id.player).pokemon[id.id - 1].stats;
        }

        fn statusModify(status: u8, stats: *Stats(u16)) void {
            if (Status.is(status, .PAR)) {
                stats.spe = @max(stats.spe / 4, 1);
            } else if (Status.is(status, .BRN)) {
                stats.atk = @max(stats.atk / 2, 1);
            }
        }

        fn clearVolatiles(self: Self, who: Player) !void {
            var side = self.battle.side(who);
            var volatiles = &side.active.volatiles;
            const ident = self.battle.active(who);

            if (volatiles.disabled_move != 0) {
                volatiles.disabled_move = 0;
                volatiles.disabled_duration = 0;
                try self.log.end(ident, .DisableSilent);
            }
            if (volatiles.Confusion) {
                // volatiles.confusion is left unchanged
                volatiles.Confusion = false;
                try self.log.end(ident, .ConfusionSilent);
            }
            if (volatiles.Mist) {
                volatiles.Mist = false;
                try self.log.end(ident, .Mist);
            }
            if (volatiles.FocusEnergy) {
                volatiles.FocusEnergy = false;
                try self.log.end(ident, .FocusEnergy);
            }
            if (volatiles.LeechSeed) {
                volatiles.LeechSeed = false;
                try self.log.end(ident, .LeechSeed);
            }
            if (!showdown and volatiles.Toxic) {
                volatiles.Toxic = false;
                // volatiles.toxic is left unchanged, except on Pokémon Showdown which clears it
            }
            if (volatiles.LightScreen) {
                volatiles.LightScreen = false;
                try self.log.end(ident, .LightScreen);
            }
            if (volatiles.Reflect) {
                volatiles.Reflect = false;
                try self.log.end(ident, .Reflect);
            }
            if (showdown and volatiles.Toxic) {
                volatiles.Toxic = false;
                // Pokémon Showdown erroneously clears the toxic counter
                volatiles.toxic = 0;
                try self.log.end(ident, .Toxic);
            }
        }

        fn secondaryChance(self: Self, low: bool) bool {
            return if (showdown)
                self.battle.rng.chance(u8, @as(u8, if (low) 26 else 77), 256)
            else
                self.battle.rng.next() < 1 + (if (low) Gen12.percent(10) else Gen12.percent(30));
        }

        fn disabled(self: Self, side: *Side, ident: ID) !bool {
            if (side.active.volatiles.disabled_move != 0) {
                // A Pokémon that transforms after being disabled may end up with less move slots
                const m = side.active.moves[side.active.volatiles.disabled_move - 1].id;
                // side.last_selected_move can be Struggle here on Pokemon Showdown we need to check
                const last = if (showdown and m == .Bide and side.active.volatiles.Bide)
                    m
                else
                    side.last_selected_move;
                if (m != .None and m == last) {
                    side.active.volatiles.Charging = false;
                    try self.log.disabled(ident, last);
                    return true;
                }
            }
            return false;
        }

        inline fn buildRage(self: Self, who: Player) !void {
            const side = self.battle.side(who);
            if (side.active.volatiles.Rage and side.active.boosts.atk < 6) {
                try Effects.boost(self, who, Move.get(.Rage));
            }
        }

        fn handleThrashing(self: Self, active: *ActivePokemon) bool {
            var volatiles = &active.volatiles;
            assert(volatiles.Thrashing);
            if (volatiles.attacks > 0) return false;

            volatiles.Thrashing = false;
            volatiles.Confusion = true;
            volatiles.confusion = @intCast(u3, if (showdown)
                self.battle.rng.range(u8, 2, 6)
            else
                (self.battle.rng.next() & 3) + 2);

            return true;
        }

        const DISTRIBUTION = [_]u3{ 2, 2, 2, 3, 3, 3, 4, 5 };

        fn distribution(self: Self) u3 {
            if (showdown) return DISTRIBUTION[self.battle.rng.range(u8, 0, DISTRIBUTION.len)];
            const r = (self.battle.rng.next() & 3);
            return @intCast(u3, (if (r < 2) r else self.battle.rng.next() & 3) + 2);
        }

        fn randomMoveSlot(self: Self, moves: []MoveSlot, check_pp: u4) u4 {
            if (showdown) {
                if (check_pp == 0) {
                    var i: usize = moves.len;
                    while (i > 0) {
                        i -= 1;
                        if (moves[i].id != .None) {
                            return self.battle.rng.range(u4, 0, @intCast(u4, i + 1)) + 1;
                        }
                    }
                } else {
                    var r = self.battle.rng.range(u4, 0, @intCast(u4, check_pp)) + 1;
                    var i: usize = 0;
                    while (i < moves.len and r > 0) : (i += 1) {
                        if (moves[i].pp > 0) {
                            r -= 1;
                            if (r == 0) break;
                        }
                    }
                    return @intCast(u4, i + 1);
                }
            }

            while (true) {
                const r = @intCast(u4, self.battle.rng.next() & 3);
                if (moves[r].id != .None and (check_pp == 0 or moves[r].pp > 0)) return r + 1;
            }
        }
    };
}

test "RNG agreement" {
    if (!showdown) return;
    var expected: [256]u32 = undefined;
    for (0..expected.len) |i| {
        expected[i] = @intCast(u32, i * 0x1000000);
    }

    var spe = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var cfz = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var par = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var brn = rng.FixedRNG(1, expected.len){ .rolls = expected };
    var eff = rng.FixedRNG(1, expected.len){ .rolls = expected };

    for (0..expected.len) |i| {
        try expectEqual(spe.range(u8, 0, 2) == 0, i < Gen12.percent(50) + 1);
        try expectEqual(!cfz.chance(u8, 128, 256), i >= Gen12.percent(50) + 1);
        try expectEqual(par.chance(u8, 63, 256), i < Gen12.percent(25));
        try expectEqual(brn.chance(u8, 26, 256), i < Gen12.percent(10) + 1);
        try expectEqual(eff.chance(u8, 85, 256), i < Gen12.percent(33) + 1);
    }
}

fn findFirstAlive(side: *const Side) u8 {
    for (side.pokemon, 0..) |pokemon, i| if (pokemon.hp > 0) return side.order[i];
    return 0;
}

inline fn isForced(active: ActivePokemon) bool {
    return active.volatiles.Recharging or active.volatiles.Rage or
        active.volatiles.Thrashing or active.volatiles.Charging;
}

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
                const id = side.order[slot - 1];
                if (id == 0 or side.pokemon[id - 1].hp == 0) continue;
                out[n] = .{ .type = .Switch, .data = slot };
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
            const stored = side.stored();

            // While players are not given any input options on the cartridge in these cases,
            // Pokémon Showdown instead produces a list with a single move that must be chosen.
            //
            // Given that no input is allowed on the cartridge 'Pass' seems like it would be logical
            // here when not in compatibility mode, but the engine needs to be able to differentiate
            // between passing while waiting for an opponent's forced switch after fainting and
            // passing due to being forced into using a move. Instead of introducing another option
            // we simply repurpose Move with no move slot, even though pedantically this is not
            // strictly correct as the player would not have been presented the option to move or
            // switch at all.
            if (isForced(active)) {
                out[n] = .{ .type = .Move, .data = @boolToInt(showdown) };
                n += 1;
                return n;
            }

            var slot: u4 = 2;
            while (slot <= 6) : (slot += 1) {
                const id = side.order[slot - 1];
                if (id == 0 or side.pokemon[id - 1].hp == 0) continue;
                out[n] = .{ .type = .Switch, .data = slot };
                n += 1;
            }

            const limited = active.volatiles.Bide or active.volatiles.Binding;
            // On the cartridge, all of these happen after "FIGHT" (indicating you are not
            // switching) but before you are allowed to select a move. Pokémon Showdown instead
            // either disables all other moves in the case of limited or requires you to select a
            // move normally if sleeping/frozen/bound.
            if (!showdown and (limited or foe.active.volatiles.Binding or
                Status.is(stored.status, .FRZ) or Status.is(stored.status, .SLP)))
            {
                out[n] = .{ .type = .Move, .data = 0 };
                n += 1;
                return n;
            }

            slot = 1;
            // Pokémon Showdown handles Bide and Binding moves by checking if the move in question
            // is present in the Pokémon's moveset (which means moves called via Metronome / Mirror
            // Move will not result in forcing the subsequent use unless the user also had the
            // proc-ed move in their moveset) and disabling all other moves.
            if (limited) {
                assert(showdown);
                assert(side.last_selected_move != .None);
                while (slot <= 4) : (slot += 1) {
                    const m = active.moves[slot - 1];
                    if (m.id == .None) break;
                    if (m.id == if (active.volatiles.Bide) .Bide else side.last_selected_move) {
                        // Pokémon Showdown displays Struggle if limited to Bide but unable to pick
                        const struggle =
                            m.id == .Bide and (m.pp == 0 or active.volatiles.disabled_move == slot);
                        const s = if (struggle) 0 else slot;
                        out[n] = .{ .type = .Move, .data = s };
                        n += 1;
                        return n;
                    }
                }
            }

            const before = n;
            slot = 1;
            while (slot <= 4) : (slot += 1) {
                const m = active.moves[slot - 1];
                if (m.id == .None) break;
                if (m.pp == 0) continue;
                if (active.volatiles.disabled_move == slot) continue;
                out[n] = .{ .type = .Move, .data = slot };
                n += 1;
            }
            // Struggle (Pokémon Showdown would use 'move 1' here)
            if (n == before) {
                // GLITCH: Transform + Mirror Move / Metronome PP softlock
                if (!showdown) {
                    while (slot <= 4) : (slot += 1) {
                        if (active.moves[slot - 1].pp != 0) return n;
                    }
                }
                out[n] = .{ .type = .Move, .data = 0 };
                n += 1;
            }
        },
    }
    return n;
}
