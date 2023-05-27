const builtin = @import("builtin");
const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");

const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const Move = @import("data.zig").Move;

const enabled = options.chance;
const showdown = options.showdown;

/// Actions taken by a hypothetical "chance player" that convey information about which RNG events
/// were observed during a battle `update`. This can additionally be provided as input to the
/// `update` call to override the normal behavior of the RNG in order to force specific outcomes.
pub const Actions = extern struct {
    /// Information about the RNG activity for Player 1
    p1: Action = .{},
    /// Information about the RNG activity for Player 2
    p2: Action = .{},

    comptime {
        assert(@sizeOf(Actions) == 16);
    }

    /// Returns the `Action` for the given `player`.
    pub inline fn get(self: *Actions, player: Player) *Action {
        return if (player == .P1) &self.p1 else &self.p2;
    }
};

/// Information about the RNG that was observed during a battle `update` for a single player.
pub const Action = packed struct {
    /// Observed values of various durations. Does not influence future RNG calls.
    durations: Durations = .{},

    /// If not None, the Move to return for Rolls.metronome.
    metronome: Move = .None,
    /// If not 0, psywave - 1 should be returned as the damage roll for Rolls.psywave.
    psywave: u8 = 0,

    /// If not None, the Player to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,
    /// If not 0, the roll 216 + damage represents the roll to be returned Rolls.damage.
    damage: u6 = 0,

    /// If not None, the value to return for Rolls.hit.
    hit: Optional(bool) = .None,
    /// If not 0, the move slot (1-4) to return in Rolls.moveSlot.
    move_slot: u3 = 0,
    /// If not 0, the value (2-5) to return for Rolls.distribution.
    distribution: u3 = 0,

    /// If not None, the value to be returned for
    /// Rolls.{confusionChance,secondaryChance,poisonChance}.
    secondary_chance: Optional(bool) = .None,
    /// If not 0, the value to be returned by
    /// Rolls.{sleepDuration,disableDuration,confusionDuration,attackingDuration}.
    duration: u4 = 0,
    /// If not None, the value to be returned by Rolls.criticalHit.
    critical_hit: Optional(bool) = .None,

    /// If not None, the value to return for Rolls.confused.
    confused: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.paralyzed.
    paralyzed: Optional(bool) = .None,

    _: u4 = 0,

    comptime {
        assert(@sizeOf(Action) == 8);
    }
};

/// Observed values for various durations that need to be tracked in order to properly
/// deduplicate transitions with a primary key.
pub const Durations = packed struct {
    /// The number of turns a Pokémon has been observed to be sleeping.
    sleep: u4 = 0,
    /// The number of turns a Pokémon has been observed to be disabled.
    disable: u4 = 0,
    /// The number of turns a Pokémon has been observed to be confused.
    confusion: u4 = 0,
    /// The number of turns a Pokémon has been observed to be attacking.
    attacking: u4 = 0,

    comptime {
        assert(@sizeOf(Durations) == 2);
    }
};

/// TODO
pub fn Chance(comptime Rational: type) type {
    return struct {
        const Self = @This();

        /// The probability of the actions taken by a hypothetical "chance player" occuring.
        probability: Rational,
        /// The actions taken by a hypothetical "chance player" that convey information about which
        /// RNG events were observed during a battle `update`.
        actions: Actions = .{},

        // Many of the rolls of the cartridge are potentially no-ops due to a move eventually
        // missing or the target being immune etc. Instead, we cache information about the rolls and
        // only actually use it to update probability/actions if the move in question actually
        // lands. We deliberately make use of the fact that recursive moves may overwrite critical
        // hit information multiple times as only the last update actually matters for the purposes
        // of the logical results.
        pending: if (showdown) void else struct {
            p1: Pending = .{},
            p2: Pending = .{},

            pub inline fn get(self: *@This(), player: Player) *Pending {
                return if (player == .P1) &self.p1 else &self.p2;
            }
        } = if (showdown) {} else .{},

        const Pending = struct {
            crit: bool = false,
            crit_probablity: u8 = 0,
            damage_roll: u6 = 0,
            hit: bool = false,
            hit_probablity: u8 = 0,
        };

        /// Possible error returned by operations tracking chance probability.
        pub const Error = Rational.Error;

        pub fn reset(self: *Self) void {
            self.probability.reset();
            self.actions = .{}; // FIXME: don't clear durations
            self.pending = .{};
        }

        pub fn commit(self: *Self, player: Player) Error!void {
            assert(!showdown);

            var action = self.actions.get(player);
            // Always commit the hit result if we make it here (commit won't be called at all if the
            // target is immune/behind a sub/etc)
            if (self.pending.get(player).hit_probablity != 0) {
                try self.probability.update(self.pending.get(player).hit_probablity, 256);
                action.hit = if (self.pending.get(player).hit) .true else .false;
            }

            // If the move actually lands we can commit any past critical hit / damage rolls. We
            // avoid updating anything if there wasn't a damage roll as any "critical hit" not tied
            // to a damage roll is actually a no-op
            if (self.pending.get(player).hit and self.pending.get(player).damage_roll > 0) {
                assert(!self.pending.get(player).crit or
                    self.pending.get(player).crit_probablity > 0);

                if (self.pending.get(player).crit_probablity != 0) {
                    try self.probability.update(self.pending.get(player).crit_probablity, 256);
                    action.critical_hit = if (self.pending.get(player).crit) .true else .false;
                }

                try self.probability.update(1, 39);
                action.damage = self.pending.get(player).damage_roll;
            }
        }

        pub fn speedTie(self: *Self, p1: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.p1.speed_tie = if (p1) .P1 else .P2;
            self.actions.p2.speed_tie = self.actions.p1.speed_tie;
        }

        pub fn criticalHit(self: *Self, player: Player, crit: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (crit) rate else @intCast(u8, 256 - @as(u9, rate));
            if (showdown) {
                try self.probability.update(n, 256);
                self.actions.get(player).critical_hit = if (crit) .true else .false;
            } else {
                self.pending.get(player).crit = crit;
                self.pending.get(player).crit_probablity = n;
            }
        }

        pub fn damage(self: *Self, player: Player, roll: u8) Error!void {
            if (!enabled) return;

            if (showdown) {
                try self.probability.update(1, 39);
                self.actions.get(player).damage = @intCast(u6, roll - 216);
            } else {
                self.pending.get(player).damage_roll = @intCast(u6, roll - 216);
            }
        }

        pub fn hit(self: *Self, player: Player, ok: bool, accuracy: u8) Error!void {
            if (!enabled) return;

            const p = if (ok) accuracy else @intCast(u8, 256 - @as(u9, accuracy));
            if (showdown) {
                try self.probability.update(p, 256);
                self.actions.get(player).hit = if (ok) .true else .false;
            } else {
                self.pending.get(player).hit = ok;
                self.pending.get(player).hit_probablity = p;
            }
        }

        pub fn confused(self: *Self, player: Player, cfz: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.get(player).confused = if (cfz) .true else .false;
        }

        pub fn paralyzed(self: *Self, player: Player, par: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (par) 1 else 3), 4);
            self.actions.get(player).paralyzed = if (par) .true else .false;
        }

        pub fn secondaryChance(self: *Self, player: Player, proc: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (proc) rate else @intCast(u8, 256 - @as(u9, rate));
            try self.probability.update(n, 256);
            self.actions.get(player).secondary_chance = if (proc) .true else .false;
        }

        pub fn metronome(self: *Self, player: Player, move: Move) Error!void {
            if (!enabled) return;

            try self.probability.update(1, Move.size - 2);
            self.actions.get(player).metronome = move;
        }

        pub fn psywave(self: *Self, player: Player, power: u8, max: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, max);
            self.actions.get(player).psywave = power + 1;
        }
    };
}

pub const NULL = Null{};

const Null = struct {
    pub const Error = error{};

    pub fn commit(self: Null, player: Player) Error!void {
        _ = self;
        _ = player;
    }

    pub fn speedTie(self: Null, p1: bool) Error!void {
        _ = self;
        _ = p1;
    }

    pub fn criticalHit(self: Null, player: Player, crit: bool, rate: u8) Error!void {
        _ = self;
        _ = player;
        _ = crit;
        _ = rate;
    }

    pub fn damage(self: Null, player: Player, roll: u8) Error!void {
        _ = self;
        _ = player;
        _ = roll;
    }

    pub fn hit(self: Null, player: Player, ok: bool, accuracy: u8) Error!void {
        _ = self;
        _ = player;
        _ = ok;
        _ = accuracy;
    }

    pub fn confused(self: Null, player: Player, ok: bool) Error!void {
        _ = self;
        _ = player;
        _ = ok;
    }

    pub fn paralyzed(self: Null, player: Player, ok: bool) Error!void {
        _ = self;
        _ = player;
        _ = ok;
    }

    pub fn secondaryChance(self: Null, player: Player, proc: bool, rate: u8) Error!void {
        _ = self;
        _ = player;
        _ = proc;
        _ = rate;
    }

    pub fn metronome(self: Null, player: Player, move: Move) Error!void {
        _ = self;
        _ = player;
        _ = move;
    }

    pub fn psywave(self: Null, player: Player, power: u8, max: u8) Error!void {
        _ = self;
        _ = player;
        _ = power;
        _ = max;
    }
};

fn TypeOf(comptime field: []const u8) type {
    for (@typeInfo(Action).Struct.fields) |f| if (std.mem.eql(u8, f.name, field)) return f.type;
    unreachable;
}
