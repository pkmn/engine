const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");
const rational = @import("../common/rational.zig");
const util = @import("../common/util.zig");

const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const Move = @import("data.zig").Move;
const MoveSlot = @import("data.zig").MoveSlot;

const enabled = options.chance;
const showdown = options.showdown;

/// Actions taken by a hypothetical "chance player" that convey information about which RNG events
/// were observed during a Generation I battle `update`. This can additionally be provided as input
/// to the `update` call to override the normal behavior of the RNG in order to force specific
/// outcomes.
pub const Actions = extern struct {
    /// Information about the RNG activity for Player 1.
    p1: Action = .{},
    /// Information about the RNG activity for Player 2.
    p2: Action = .{},

    comptime {
        assert(@sizeOf(Actions) == 16);
    }

    /// Returns the `Action` for the given `player`.
    pub inline fn get(self: anytype, player: Player) util.PointerType(@TypeOf(self), Action) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == Actions);
        return if (player == .P1) &self.p1 else &self.p2;
    }

    /// Perform a reset by clearing fields which should not persist across updates.
    pub inline fn reset(self: *Actions) void {
        self.p1.reset();
        self.p2.reset();
    }

    /// Returns true if `a` is equal to `b`.
    pub inline fn eql(a: Actions, b: Actions) bool {
        return @bitCast(u128, a) == @bitCast(u128, b);
    }

    /// Returns true if `a` has the same "shape" as `b`, where `Actions` are defined to have the
    /// same shape if they have the same fields set (though those fields need not necessarily be set
    /// to the same value).
    pub fn matches(a: Actions, b: Actions) bool {
        inline for (@typeInfo(Actions).Struct.fields) |player| {
            inline for (@typeInfo(Action).Struct.fields) |field| {
                const a_val = @field(@field(a, player.name), field.name);
                const b_val = @field(@field(b, player.name), field.name);

                switch (@typeInfo(@TypeOf(a_val))) {
                    .Enum => if ((@enumToInt(a_val) > 0) != (@enumToInt(b_val) > 0)) return false,
                    .Int => if ((a_val > 0) != (b_val > 0)) return false,
                    else => unreachable,
                }
            }
        }
        return true;
    }

    pub fn fmt(self: Actions, writer: anytype, shape: bool) !void {
        try writer.writeAll("<P1 = ");
        try self.p1.fmt(writer, shape);
        try writer.writeAll(", P2 = ");
        try self.p2.fmt(writer, shape);
        try writer.writeAll(">");
    }

    pub fn format(a: Actions, comptime f: []const u8, o: std.fmt.FormatOptions, w: anytype) !void {
        _ = .{ f, o };
        try fmt(a, w, false);
    }
};

test Actions {
    const a: Actions = .{ .p1 = .{ .hit = .true, .critical_hit = .false, .damage = 245 } };
    const b: Actions = .{ .p1 = .{ .hit = .false, .critical_hit = .true, .damage = 246 } };
    const c: Actions = .{ .p1 = .{ .hit = .true } };

    try expect(a.eql(a));
    try expect(!a.eql(b));
    try expect(!b.eql(a));
    try expect(!a.eql(c));
    try expect(!c.eql(a));

    try expect(a.matches(a));
    try expect(a.matches(b));
    try expect(b.matches(a));
    try expect(!a.matches(c));
    try expect(!c.matches(a));
}

/// Information about the RNG that was observed during a Generation I battle `update` for a
/// single player.
pub const Action = packed struct {
    /// If not 0, the roll to be returned Rolls.damage.
    damage: u8 = 0,

    /// If not None, the value to return for Rolls.hit.
    hit: Optional(bool) = .None,
    /// If not None, the value to be returned by Rolls.criticalHit.
    critical_hit: Optional(bool) = .None,
    /// If not None, the value to be returned for
    /// Rolls.{confusionChance,secondaryChance,poisonChance}.
    secondary_chance: Optional(bool) = .None,
    /// If not None, the Playr to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,

    /// If not None, the value to return for Rolls.confused.
    confused: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.paralyzed.
    paralyzed: Optional(bool) = .None,
    /// If not 0, the value to be returned by Rolls.distribution in the case of binding moves
    /// or Rolls.{sleepDuration,disableDuration,confusionDuration,attackingDuration} otherwise.
    duration: u4 = 0,

    /// The number of turns a Pokémon has been observed to be sleeping.
    /// When present as an override, 0 will force sleep to end and non-zero will extend.
    sleep: u3 = 0,
    /// The number of turns a Pokémon has been observed to be confused.
    /// When present as an override, 0 will force confusion to end and non-zero will extend.
    confusion: u3 = 0,
    /// The number of turns a Pokémon has been observed to be disabled.
    //// When present as an override, 0 will force disable to end and non-zero will extend.
    disable: u4 = 0,
    /// The number of turns a Pokémon has been observed to be attacking.
    //// When present as an override, 0 will force attracking to end and non-zero will extend.
    attacking: u3 = 0,
    /// The number of turns a Pokémon has been observed to be binding their opponent.
    /// When present as an override, 0 will force binding to end and non-zero will extend.
    binding: u3 = 0,

    /// If not 0, the move slot (1-4) to return in Rolls.moveSlot.
    move_slot: u4 = 0,
    /// If not 0, the value (2-5) to return for Rolls.distribution for multi hit.
    multi_hit: u4 = 0,

    /// If not 0, psywave - 1 should be returned as the damage roll for Rolls.psywave.
    psywave: u8 = 0,

    /// If not None, the Move to return for Rolls.metronome.
    metronome: Move = .None,

    pub const Field = std.meta.FieldEnum(Action);

    comptime {
        assert(@sizeOf(Action) == 8);
    }

    /// Perform a reset by clearing fields which should not persist across updates.
    pub inline fn reset(self: *Action) void {
        self.* = @bitCast(Action, @bitCast(u64, self.*) & 0x000000FFFF000000);
    }

    pub fn format(a: Action, comptime f: []const u8, o: std.fmt.FormatOptions, w: anytype) !void {
        _ = .{ f, o };
        try fmt(a, w, false);
    }

    pub fn fmt(self: Action, writer: anytype, shape: bool) !void {
        try writer.writeByte('(');
        var printed = false;
        inline for (@typeInfo(Action).Struct.fields) |field| {
            const val = @field(self, field.name);
            switch (@typeInfo(@TypeOf(val))) {
                .Enum => if (val != .None) {
                    if (printed) try writer.writeAll(", ");
                    if (shape) {
                        try writer.print("{s}:?", .{field.name});
                    } else if (@TypeOf(val) == Optional(bool)) {
                        try writer.print("{s}{s}", .{
                            if (val == .false) "!" else "",
                            field.name,
                        });
                    } else {
                        try writer.print("{s}:{s}", .{ field.name, @tagName(val) });
                    }
                    printed = true;
                },
                .Int => if (val != 0) {
                    if (printed) try writer.writeAll(", ");
                    if (shape) {
                        try writer.print("{s}:?", .{field.name});
                    } else {
                        try writer.print("{s}:{d}", .{ field.name, val });
                    }
                    printed = true;
                },
                else => unreachable,
            }
        }
        try writer.writeByte(')');
    }
};

test Action {
    var a = Action{ .hit = .true, .sleep = 3, .damage = 225 };
    a.reset();

    try expectEqual(Action{ .hit = .None, .sleep = 3, .damage = 0 }, a);
}

pub const Commit = enum { hit, miss, binding };

/// Tracks chance actions and their associated probability during a Generation I battle update when
/// `options.chance` is enabled.
pub fn Chance(comptime Rational: type) type {
    return struct {
        const Self = @This();

        /// The probability of the actions taken by a hypothetical "chance player" occurring.
        probability: Rational,
        /// The actions taken by a hypothetical "chance player" that convey information about which
        /// RNG events were observed during a battle `update`.
        actions: Actions = .{},

        // Tracks the observed sleep durations for the Pokémon in both player's parties. Unlike
        // other durations which are all tied to volatiles, sleep's counter persists through
        // switching and so we must store it here. The indices of these arrays correspond to the
        // `order` field of a Side. This information could be stored in actions but size is a
        // concern so this is tracked separately as actions only purports to track RNG events
        // observed during a single `update` (not across updates).
        sleeps: [2][6]u3 = .{ .{0} ** 6, .{0} ** 6 },

        // In many cases on both the cartridge and on Pokémon Showdown rolls are made even though
        // later checks render their result irrelevant (missing when the target is actually immune,
        // rolling for damage when the move is later revealed to have missed, etc). We can't reorder
        // the logic to ensure we only ever make rolls when required due to our desire to maintain
        // RNG frame accuracy, so instead we save these "pending" updates to the probability and
        // only commit them once we know they are relevant (a naive solution would be to instead
        // update the probability eagerly and later "undo" the update by multiplying by the inverse
        // but this would be more costly and also error prone in the presence of
        // overflow/normalization).
        //
        // This design deliberately make use of the fact that recursive moves on the cartridge may
        // overwrite critical hit information multiple times as only the last update actually
        // matters for the purposes of the logical results.
        //
        // Finally, because each player's actions are processed sequentially we only need a single
        // shared structure to track this information (though it needs to be cleared appropriately)
        pending: if (showdown) struct {
            hit: bool = false,
            hit_probablity: u8 = 0,
        } else struct {
            crit: bool = false,
            crit_probablity: u8 = 0,
            damage_roll: u8 = 0,
            hit: bool = false,
            hit_probablity: u8 = 0,
            binding: u8 = 0,
        } = .{},

        /// Possible error returned by operations tracking chance probability.
        pub const Error = Rational.Error;

        /// Convenience helper to clear fields which typically should be cleared between updates.
        pub fn reset(self: *Self) void {
            self.probability.reset();
            self.actions.reset();
            self.pending = .{};
        }

        pub fn commit(self: *Self, player: Player, kind: Commit) Error!void {
            var action = self.actions.get(player);

            // We need to handle binding specially because we still need to commit it when attacking
            // into a Pokémon that is immune
            if (!showdown) {
                if (kind != .miss and self.pending.binding != 0) {
                    assert(action.duration == 0);
                    action.duration = @intCast(u4, self.pending.binding);
                    assert(action.binding == 0);
                    action.binding = 1;
                }
                if (kind == .binding) return;
            } else {
                assert(kind != .binding);
            }

            // Always commit the hit result if we make it here (commit won't be called at all if the
            // target is immune/behind a sub/etc)
            if (self.pending.hit_probablity != 0) {
                try self.probability.update(self.pending.hit_probablity, 256);
                action.hit = if (self.pending.hit) .true else .false;
            }

            if (showdown) return;

            // If the move actually lands we can commit any past critical hit / damage rolls. We
            // avoid updating anything if there wasn't a damage roll as any "critical hit" not tied
            // to a damage roll is actually a no-op
            if (kind == .hit and self.pending.damage_roll > 0) {
                assert(!self.pending.crit or self.pending.crit_probablity > 0);

                if (self.pending.crit_probablity != 0) {
                    try self.probability.update(self.pending.crit_probablity, 256);
                    action.critical_hit = if (self.pending.crit) .true else .false;
                }

                try self.probability.update(1, 39);
                action.damage = self.pending.damage_roll;
            }
        }

        pub fn clearPending(self: *Self) void {
            if (!enabled) return;

            self.pending = .{};
        }

        pub fn clearDurations(self: *Self, player: Player, haze: ?bool) void {
            if (!enabled) return;

            var action = self.actions.get(player);
            if (haze) |status| {
                if (status) action.sleep = 0;
                action.confusion = 0;
                action.disable = 0;
            } else {
                action.attacking = 0;
                action.binding = 0;
            }
        }

        pub fn switched(self: *Self, player: Player, in: u8, out: u8) void {
            if (!enabled) return;

            assert(in >= 1 and in <= 6);
            assert(out >= 1 and out <= 6);

            var action = self.actions.get(player);
            self.sleeps[@enumToInt(player)][out - 1] = action.sleep;
            action.sleep = @intCast(u3, self.sleeps[@enumToInt(player)][in - 1]);

            action.confusion = 0;
            action.disable = 0;
            action.attacking = 0;
            action.binding = 0;

            self.actions.get(player.foe()).binding = 0;
        }

        pub fn speedTie(self: *Self, p1: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.p1.speed_tie = if (p1) .P1 else .P2;
            self.actions.p2.speed_tie = self.actions.p1.speed_tie;
        }

        pub fn hit(self: *Self, ok: bool, accuracy: u8) void {
            if (!enabled) return;

            const p = if (ok) accuracy else @intCast(u8, 256 - @as(u9, accuracy));
            self.pending.hit = ok;
            self.pending.hit_probablity = p;
        }

        pub fn criticalHit(self: *Self, player: Player, crit: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (crit) rate else @intCast(u8, 256 - @as(u9, rate));
            if (showdown) {
                try self.probability.update(n, 256);
                self.actions.get(player).critical_hit = if (crit) .true else .false;
            } else {
                self.pending.crit = crit;
                self.pending.crit_probablity = n;
            }
        }

        pub fn damage(self: *Self, player: Player, roll: u8) Error!void {
            if (!enabled) return;

            if (showdown) {
                try self.probability.update(1, 39);
                self.actions.get(player).damage = roll;
            } else {
                self.pending.damage_roll = roll;
            }
        }

        pub fn secondaryChance(self: *Self, player: Player, proc: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (proc) rate else @intCast(u8, 256 - @as(u9, rate));
            try self.probability.update(n, 256);
            self.actions.get(player).secondary_chance = if (proc) .true else .false;
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

        pub fn moveSlot(
            self: *Self,
            player: Player,
            slot: u4,
            ms: []const MoveSlot,
            n: u4,
        ) Error!void {
            if (!enabled) return;

            const denominator = if (n != 0) n else denominator: {
                var i: usize = ms.len;
                while (i > 0) {
                    i -= 1;
                    if (ms[i].id != .None) break :denominator i + 1;
                }
                unreachable;
            };

            if (denominator != 1) try self.probability.update(1, denominator);
            self.actions.get(player).move_slot = @intCast(u3, slot);
        }

        pub fn multiHit(self: *Self, player: Player, n: u3) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (n > 3) 1 else 3), 8);
            self.actions.get(player).multi_hit = n;
        }

        pub fn duration(
            self: *Self,
            comptime field: Action.Field,
            player: Player,
            target: Player,
            turns: u4,
        ) void {
            if (!enabled) return;

            if (!showdown and field == .binding) {
                self.pending.binding = if (options.key) 1 else turns;
            } else {
                var action = self.actions.get(target);
                assert(@field(action, @tagName(field)) == 0 or
                    (field == .confusion and player == target));
                @field(action, @tagName(field)) = 1;
                self.actions.get(player).duration = if (options.key) 1 else turns;
            }
        }

        pub fn sleep(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var action = self.actions.get(player);
            const n = action.sleep;
            if (turns == 0) {
                assert(n >= 1 and n <= 7);
                if (n != 7) try self.probability.update(1, 8 - @as(u4, n));
                action.sleep = 0;
            } else {
                assert(n >= 1 and n < 7);
                try self.probability.update(8 - @as(u4, n) - 1, 8 - @as(u4, n));
                action.sleep += 1;
            }
        }

        pub fn disable(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var action = self.actions.get(player);
            const n = action.disable;
            if (turns == 0) {
                assert(n >= 1 and n <= 8);
                if (n != 8) try self.probability.update(1, 9 - @as(u4, n));
                action.disable = 0;
            } else {
                assert(n >= 1 and n < 8);
                try self.probability.update(9 - @as(u4, n) - 1, 9 - @as(u4, n));
                action.disable += 1;
            }
        }

        pub fn confusion(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var action = self.actions.get(player);
            const n = action.confusion;
            if (turns == 0) {
                assert(n >= 2 and n <= 5);
                if (n != 5) try self.probability.update(1, 6 - @as(u4, n));
                action.confusion = 0;
            } else {
                assert(n >= 1 and n < 5);
                if (n > 1) try self.probability.update(6 - @as(u4, n) - 1, 6 - @as(u4, n));
                action.confusion += 1;
            }
        }

        pub fn attacking(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var action = self.actions.get(player);
            const n = action.attacking;
            if (turns == 0) {
                assert(n >= 2 and n <= 3);
                if (n != 3) try self.probability.update(1, 4 - @as(u4, n));
                action.attacking = 0;
            } else {
                assert(n >= 1 and n < 3);
                if (n > 1) try self.probability.update(4 - @as(u4, n) - 1, 4 - @as(u4, n));
                action.attacking += 1;
            }
        }

        pub fn binding(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var action = self.actions.get(player);
            const n = action.binding;

            assert(n > 0);
            const p: u4 = if (n < 3) 3 else 1;
            const q: u4 = if (n < 3) 8 - ((n - 1) * p) else 2;

            if (turns == 0) {
                assert(n >= 1 and n <= 4);
                if (n != 4) try self.probability.update(p, q);
                action.binding = 0;
            } else {
                assert(n >= 1 and n < 4);
                try self.probability.update(q - p, q);
                action.binding += 1;
            }
        }

        pub fn psywave(self: *Self, player: Player, power: u8, max: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, max);
            self.actions.get(player).psywave = power + 1;
        }

        pub fn metronome(self: *Self, player: Player, move: Move) Error!void {
            if (!enabled) return;

            try self.probability.update(1, Move.size - 2);
            self.actions.get(player).metronome = move;
        }
    };
}

test "Chance.speedTie" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.speedTie(true);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(Player).P1, chance.actions.p1.speed_tie);
    try expectValue(chance.actions.p1.speed_tie, chance.actions.p2.speed_tie);

    chance.reset();

    try chance.speedTie(false);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(Player).P2, chance.actions.p1.speed_tie);
    try expectValue(chance.actions.p1.speed_tie, chance.actions.p2.speed_tie);
}

test "Chance.hit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    chance.hit(true, 229);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(Optional(bool).None, chance.actions.p1.hit);
    try chance.commit(.P1, .hit);
    try expectValue(Optional(bool).true, chance.actions.p1.hit);
    try expectProbability(&chance.probability, 229, 256);

    chance.reset();

    chance.hit(false, 255);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(Optional(bool).None, chance.actions.p2.hit);
    try chance.commit(.P2, .miss);
    try expectValue(Optional(bool).false, chance.actions.p2.hit);
    try expectProbability(&chance.probability, 1, 256);
}

test "Chance.criticalHit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.criticalHit(.P1, true, 17);
    if (showdown) {
        try expectValue(Optional(bool).true, chance.actions.p1.critical_hit);
        try expectProbability(&chance.probability, 17, 256);
    } else {
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        chance.hit(true, 128);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 1, 2);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        chance.probability.reset();
        try chance.damage(.P1, 217);

        try chance.commit(.P1, .miss);
        try expectProbability(&chance.probability, 1, 2);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        chance.probability.reset();

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 17, 19968); // (1/2) * (17/256) * (1/39)
        try expectValue(Optional(bool).true, chance.actions.p1.critical_hit);
    }

    chance.reset();

    try chance.criticalHit(.P2, false, 5);
    if (showdown) {
        try expectProbability(&chance.probability, 251, 256);
        try expectValue(Optional(bool).false, chance.actions.p2.critical_hit);
    } else {
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        chance.hit(true, 128);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 1, 2);
        try expectValue(Optional(bool).None, chance.actions.p1.critical_hit);

        chance.probability.reset();
        try chance.damage(.P1, 217);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 251, 19968); // (1/2) * (251/256) * (1/39)
        try expectValue(Optional(bool).false, chance.actions.p1.critical_hit);
    }
}

test "Chance.damage" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.damage(.P1, 217);
    if (showdown) {
        try expectValue(@as(u8, 217), chance.actions.p1.damage);
        try expectProbability(&chance.probability, 1, 39);
    } else {
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(@as(u8, 0), chance.actions.p1.damage);

        try chance.commit(.P1, .miss);
        try expectProbability(&chance.probability, 1, 1);
        try expectValue(@as(u8, 0), chance.actions.p1.damage);

        try chance.commit(.P1, .hit);
        try expectProbability(&chance.probability, 1, 39);
        try expectValue(@as(u8, 217), chance.actions.p1.damage);
    }
}

test "Chance.secondaryChance" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.secondaryChance(.P1, true, 25);
    try expectProbability(&chance.probability, 25, 256);
    try expectValue(Optional(bool).true, chance.actions.p1.secondary_chance);

    chance.reset();

    try chance.secondaryChance(.P2, false, 77);
    try expectProbability(&chance.probability, 179, 256);
    try expectValue(Optional(bool).false, chance.actions.p2.secondary_chance);
}

test "Chance.confused" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.confused(.P1, false);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(bool).false, chance.actions.p1.confused);

    chance.reset();

    try chance.confused(.P2, true);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(bool).true, chance.actions.p2.confused);
}

test "Chance.paralyzed" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.paralyzed(.P1, false);
    try expectProbability(&chance.probability, 3, 4);
    try expectValue(Optional(bool).false, chance.actions.p1.paralyzed);

    chance.reset();

    try chance.paralyzed(.P2, true);
    try expectProbability(&chance.probability, 1, 4);
    try expectValue(Optional(bool).true, chance.actions.p2.paralyzed);
}

test "Chance.moveSlot" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };
    var ms = [_]MoveSlot{ .{ .id = Move.Surf }, .{ .id = Move.Psychic }, .{ .id = Move.Recover } };

    try chance.moveSlot(.P2, 2, &ms, 2);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(@as(u4, 2), chance.actions.p2.move_slot);

    chance.reset();

    try chance.moveSlot(.P1, 1, &ms, 0);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u4, 1), chance.actions.p1.move_slot);
}

test "Chance.multiHit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.multiHit(.P1, 3);
    try expectProbability(&chance.probability, 3, 8);
    try expectValue(@as(u4, 3), chance.actions.p1.multi_hit);

    chance.reset();

    try chance.multiHit(.P2, 5);
    try expectProbability(&chance.probability, 1, 8);
    try expectValue(@as(u4, 5), chance.actions.p2.multi_hit);
}

test "Chance.duration" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    chance.duration(.sleep, .P1, .P2, 2);
    try expectValue(@as(u4, 2), chance.actions.p1.duration);
    try expectValue(@as(u3, 1), chance.actions.p2.sleep);

    chance.reset();

    chance.duration(.binding, .P2, .P2, 4);
    if (!showdown) {
        try expectValue(@as(u4, 0), chance.actions.p2.duration);
        try expectValue(@as(u3, 0), chance.actions.p2.binding);
        try chance.commit(.P2, .hit);
    }
    try expectValue(@as(u4, 4), chance.actions.p2.duration);
    try expectValue(@as(u3, 1), chance.actions.p2.binding);
}

test "Chance.sleep" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 7, 6, 5, 4, 3, 2, 1 }, 1..8) |d, i| {
        chance.actions.p1.sleep = @intCast(u3, i);
        try chance.sleep(.P1, 0);
        try expectProbability(&chance.probability, 1, d);
        try expectValue(@as(u3, 0), chance.actions.p1.sleep);

        chance.reset();

        if (i < 7) {
            chance.actions.p1.sleep = @intCast(u3, i);
            try chance.sleep(.P1, 1);
            try expectProbability(&chance.probability, d - 1, d);
            try expectValue(@intCast(u3, i) + 1, chance.actions.p1.sleep);

            chance.reset();
        }
    }
}

test "Chance.confusion" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
        if (i > 1) {
            chance.actions.p2.confusion = @intCast(u3, i);
            try chance.confusion(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.confusion);

            chance.reset();
        }

        if (i < 5) {
            chance.actions.p2.confusion = @intCast(u3, i);
            try chance.confusion(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@intCast(u3, i) + 1, chance.actions.p2.confusion);

            chance.reset();
        }
    }
}

test "Chance.attacking" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 2, 1 }, 1..4) |d, i| {
        if (i > 1) {
            chance.actions.p2.attacking = @intCast(u3, i);
            try chance.attacking(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.attacking);

            chance.reset();
        }

        if (i < 3) {
            chance.actions.p2.attacking = @intCast(u3, i);
            try chance.attacking(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@intCast(u3, i) + 1, chance.actions.p2.attacking);

            chance.reset();
        }
    }
}

test "Chance.binding" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    const ps = [_]u8{ 3, 3, 1, 1 };
    const qs = [_]u8{ 8, 5, 2, 1 };

    for (ps, qs, 1..5) |p, q, i| {
        chance.actions.p1.binding = @intCast(u3, i);
        try chance.binding(.P1, 0);
        try expectProbability(&chance.probability, p, q);
        try expectValue(@as(u3, 0), chance.actions.p1.binding);

        chance.reset();

        if (i < 4) {
            chance.actions.p1.binding = @intCast(u3, i);
            try chance.binding(.P1, 1);
            try expectProbability(&chance.probability, q - p, q);
            try expectValue(@intCast(u3, i) + 1, chance.actions.p1.binding);

            chance.reset();
        }
    }
}

test "Chance.psywave" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.psywave(.P2, 100, 150);
    try expectProbability(&chance.probability, 1, 150);
    try expectValue(@as(u8, 101), chance.actions.p2.psywave);
}

test "Chance.metronome" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.metronome(.P1, Move.HornAttack);
    try expectProbability(&chance.probability, 1, 163);
    try expectValue(Move.HornAttack, chance.actions.p1.metronome);
}

pub fn expectProbability(r: anytype, p: u64, q: u64) !void {
    if (!enabled) return;

    r.reduce();
    if (r.p != p or r.q != q) {
        print("expected {d}/{d}, found {}\n", .{ p, q, r });
        return error.TestExpectedEqual;
    }
}

pub fn expectValue(a: anytype, b: anytype) !void {
    if (!enabled) return;

    try expectEqual(a, b);
}

/// Null object pattern implementation of Generation I `Chance` which does nothing, though chance
/// tracking should additionally be turned off entirely via `options.chance`.
pub const NULL = Null{};

const Null = struct {
    pub const Error = error{};

    pub fn commit(self: Null, player: Player, kind: Commit) Error!void {
        _ = .{ self, player, kind };
    }

    pub fn clearPending(self: Null) void {
        _ = .{self};
    }

    pub fn clearDurations(self: Null, player: Player, haze: ?bool) void {
        _ = .{ self, player, haze };
    }

    pub fn switched(self: Null, player: Player, in: u8, out: u8) void {
        _ = .{ self, player, in, out };
    }

    pub fn speedTie(self: Null, p1: bool) Error!void {
        _ = .{ self, p1 };
    }

    pub fn hit(self: Null, ok: bool, accuracy: u8) void {
        _ = .{ self, ok, accuracy };
    }

    pub fn criticalHit(self: Null, player: Player, crit: bool, rate: u8) Error!void {
        _ = .{ self, player, crit, rate };
    }

    pub fn damage(self: Null, player: Player, roll: u8) Error!void {
        _ = .{ self, player, roll };
    }

    pub fn secondaryChance(self: Null, player: Player, proc: bool, rate: u8) Error!void {
        _ = .{ self, player, proc, rate };
    }

    pub fn confused(self: Null, player: Player, ok: bool) Error!void {
        _ = .{ self, player, ok };
    }

    pub fn paralyzed(self: Null, player: Player, ok: bool) Error!void {
        _ = .{ self, player, ok };
    }

    pub fn moveSlot(self: Null, player: Player, slot: u4, ms: []const MoveSlot, n: u4) Error!void {
        _ = .{ self, player, slot, ms, n };
    }

    pub fn multiHit(self: Null, player: Player, n: u3) Error!void {
        _ = .{ self, player, n };
    }

    pub fn duration(
        self: Null,
        comptime field: Action.Field,
        player: Player,
        target: Player,
        turns: u4,
    ) void {
        _ = .{ self, field, player, target, turns };
    }

    pub fn sleep(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn disable(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn confusion(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn attacking(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn binding(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn psywave(self: Null, player: Player, power: u8, max: u8) Error!void {
        _ = .{ self, player, power, max };
    }

    pub fn metronome(self: Null, player: Player, move: Move) Error!void {
        _ = .{ self, player, move };
    }
};
