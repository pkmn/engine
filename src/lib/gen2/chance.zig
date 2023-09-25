const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const options = @import("../common/options.zig");
const rational = @import("../common/rational.zig");
const util = @import("../common/util.zig");

const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const enabled = options.chance;

/// Actions taken by a hypothetical "chance player" that convey information about which RNG events
/// were observed during a Generation II battle `update`. This can additionally be provided as input
/// to the `update` call to override the normal behavior of the RNG in order to force specific
/// outcomes.
pub const Actions = extern struct {
    /// Information about the RNG activity for Player 1.
    p1: Action = .{},
    /// Information about the RNG activity for Player 2.
    p2: Action = .{},

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
        _ = .{ a, b };
        return false; // TODO
    }

    /// Returns true if `a` has the same "shape" as `b`, where `Actions` are defined to have the
    /// same shape if they have the same fields set (though those fields need not necessarily be
    /// set to the same value).
    pub fn matches(a: Actions, b: Actions) bool {
        inline for (@typeInfo(Actions).Struct.fields) |player| {
            inline for (@typeInfo(Action).Struct.fields) |field| {
                const a_val = @field(@field(a, player.name), field.name);
                const b_val = @field(@field(b, player.name), field.name);

                switch (@typeInfo(@TypeOf(a_val))) {
                    .Struct => inline for (@typeInfo(@TypeOf(a_val)).Struct.fields) |f| {
                        if ((@field(a_val, f.name) > 0) != (@field(b_val, f.name) > 0)) {
                            return false;
                        }
                    },
                    .Enum => if ((@intFromEnum(a_val) > 0) != (@intFromEnum(b_val) > 0))
                        return false,
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
    const d: Actions = .{ .p2 = .{ .hit = .true, .durations = .{ .sleep = 2 } } };
    const e: Actions = .{ .p2 = .{ .hit = .false, .durations = .{ .sleep = 4 } } };
    const f: Actions = .{ .p1 = .{ .hit = .false, .durations = .{ .sleep = 4 } } };

    // TODO
    // try expect(a.eql(a));
    // try expect(!a.eql(b));
    // try expect(!b.eql(a));
    // try expect(!a.eql(c));
    // try expect(!c.eql(a));

    try expect(a.matches(a));
    try expect(a.matches(b));
    try expect(b.matches(a));
    try expect(!a.matches(c));
    try expect(!c.matches(a));
    try expect(d.matches(e));
    try expect(!d.matches(f));
}

/// Information about the RNG that was observed during a Generation II battle `update` for a
/// single player.
pub const Action = packed struct(u64) {
    /// If not 0, the roll to be returned Rolls.damage.
    damage: u8 = 0,

    /// If not None, the value to return for Rolls.hit.
    hit: Optional(bool) = .None,
    /// If not None, the value to be returned for TODO
    quick_claw: Optional(bool) = .None,
    /// If not None, the Player to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,
    /// If not None, the value to be returned by Rolls.criticalHit.
    critical_hit: Optional(bool) = .None,

    /// If not None, the value to return for Rolls.confused.
    confused: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.attract.
    attract: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.paralyzed.
    paralyzed: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.defrost.
    defrost: Optional(bool) = .None,

    _: u24 = 0,

    /// Observed values of various durations. Does not influence future RNG calls. TODO
    durations: Duration = .{},

    pub const DURATIONS: u64 = 0xFFFF000000000000;

    pub const Field = std.meta.FieldEnum(Action);

    /// Perform a reset by clearing fields which should not persist across updates.
    pub inline fn reset(self: *Action) void {
        self.* = @bitCast(@as(u64, @bitCast(self.*)) & DURATIONS);
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
                .Struct => inline for (@typeInfo(@TypeOf(val)).Struct.fields) |f| {
                    const v = @field(val, f.name);
                    if (v != 0) {
                        if (printed) try writer.writeAll(", ");
                        if (shape) {
                            try writer.print("{s}:?", .{f.name});
                        } else {
                            try writer.print("{s}:{d}", .{ f.name, v });
                        }
                        printed = true;
                    }
                },
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
    var a: Action = .{ .hit = .true, .durations = .{ .sleep = 3 }, .damage = 225 };
    a.reset();

    try expectEqual(Action{ .hit = .None, .durations = .{ .sleep = 3 }, .damage = 0 }, a);
}

/// Observed values for various durations that need to be tracked in order to properly
/// deduplicate transitions with a primary key. TODO
pub const Duration = packed struct(u16) {
    /// The number of turns a Pokémon has been observed to be sleeping.
    sleep: u3 = 0,
    /// The number of turns a Pokémon has been observed to be confused.
    confusion: u3 = 0,
    /// Twole number of turns a Pokémon has been observed to be disabled.
    disable: u4 = 0,

    _: u6 = 0,

    pub const Field = std.meta.FieldEnum(Duration);
};

/// Tracks chance actions and their associated probability during a Generation II battle update when
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

        /// Possible error returned by operations tracking chance probability.
        pub const Error = Rational.Error;

        /// Convenience helper to clear fields which typically should be cleared between updates.
        pub fn reset(self: *Self) void {
            self.probability.reset();
            self.actions.reset();
            // TODO: self.pending = .{};
        }

        pub fn switched(self: *Self, player: Player, in: u8, out: u8) void {
            if (!enabled) return;

            assert(in >= 1 and in <= 6);
            assert(out >= 1 and out <= 6);

            var action = self.actions.get(player);

            const slp = action.durations.sleep;
            action.durations = .{};

            self.sleeps[@intFromEnum(player)][out - 1] = slp;
            action.durations.sleep = @intCast(self.sleeps[@intFromEnum(player)][in - 1]);
        }

        pub fn speedTie(self: *Self, p1: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.p1.speed_tie = if (p1) .P1 else .P2;
            self.actions.p2.speed_tie = self.actions.p1.speed_tie;
        }

        pub fn quickClaw(self: *Self, player: Player, proc: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (proc) 60 else 196), 256);
            self.actions.get(player).quick_claw = if (proc) .true else .false;
        }

        pub fn hit(self: *Self, player: Player, ok: bool, accuracy: u8) Error!void {
            if (!enabled) return;

            const p = if (ok) accuracy else @as(u8, @intCast(256 - @as(u9, accuracy)));
            try self.probability.update(p, 256);
            self.actions.get(player).hit = if (ok) .true else .false;
        }

        pub fn criticalHit(self: *Self, player: Player, crit: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (crit) rate else @as(u8, @intCast(256 - @as(u9, rate)));
            try self.probability.update(n, 256);
            self.actions.get(player).critical_hit = if (crit) .true else .false;
        }

        pub fn damage(self: *Self, player: Player, roll: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 39);
            self.actions.get(player).damage = roll;
        }

        pub fn confused(self: *Self, player: Player, cfz: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.get(player).confused = if (cfz) .true else .false;
        }

        pub fn attract(self: *Self, player: Player, cant: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.get(player).attract = if (cant) .true else .false;
        }

        pub fn paralyzed(self: *Self, player: Player, par: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (par) 1 else 3), 4);
            self.actions.get(player).paralyzed = if (par) .true else .false;
        }

        pub fn defrost(self: *Self, player: Player, thaw: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (thaw) 25 else 231), 256);
            self.actions.get(player).defrost = if (thaw) .true else .false;
        }

        pub fn sleep(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.sleep;
            if (turns == 0) {
                assert(n >= 1 and n <= 6);
                if (n != 6) try self.probability.update(1, 7 - @as(u4, n));
                durations.sleep = 0;
            } else {
                assert(n >= 1 and n < 6);
                try self.probability.update(7 - @as(u4, n) - 1, 7 - @as(u4, n));
                durations.sleep += 1;
            }
        }

        pub fn disable(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.disable;
            if (turns == 0) {
                assert(n >= 3 and n <= 9);
                if (n != 9) try self.probability.update(1, 10 - @as(u4, n));
                durations.disable = 0;
            } else {
                assert(n >= 1 and n < 9);
                try self.probability.update(10 - @as(u4, n) - 3, 10 - @as(u4, n));
                durations.disable += 1;
            }
        }

        pub fn confusion(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.confusion;
            if (turns == 0) {
                assert(n >= 2 and n <= 5);
                if (n != 5) try self.probability.update(1, 6 - @as(u4, n));
                durations.confusion = 0;
            } else {
                assert(n >= 1 and n < 5);
                if (n > 1) try self.probability.update(6 - @as(u4, n) - 1, 6 - @as(u4, n));
                durations.confusion += 1;
            }
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

test "Chance.quickClaw" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.quickClaw(.P1, false);
    try expectProbability(&chance.probability, 49, 64);
    try expectValue(Optional(bool).false, chance.actions.p1.quick_claw);

    chance.reset();

    try chance.quickClaw(.P2, true);
    try expectProbability(&chance.probability, 15, 64);
    try expectValue(Optional(bool).true, chance.actions.p2.quick_claw);
}

test "Chance.hit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.hit(.P1, true, 229);
    try expectValue(Optional(bool).true, chance.actions.p1.hit);
    try expectProbability(&chance.probability, 229, 256);

    chance.reset();

    try chance.hit(.P2, false, 229);
    try expectValue(Optional(bool).false, chance.actions.p2.hit);
    try expectProbability(&chance.probability, 27, 256);
}

test "Chance.criticalHit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.criticalHit(.P1, true, 17);
    try expectValue(Optional(bool).true, chance.actions.p1.critical_hit);
    try expectProbability(&chance.probability, 17, 256);

    chance.reset();

    try chance.criticalHit(.P2, false, 5);
    try expectProbability(&chance.probability, 251, 256);
    try expectValue(Optional(bool).false, chance.actions.p2.critical_hit);
}

test "Chance.damage" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.damage(.P1, 217);
    try expectValue(@as(u8, 217), chance.actions.p1.damage);
    try expectProbability(&chance.probability, 1, 39);
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

test "Chance.attract" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.attract(.P1, false);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(bool).false, chance.actions.p1.attract);

    chance.reset();

    try chance.attract(.P2, true);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(Optional(bool).true, chance.actions.p2.attract);
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

test "Chance.defrost" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.defrost(.P1, false);
    try expectProbability(&chance.probability, 231, 256);
    try expectValue(Optional(bool).false, chance.actions.p1.defrost);

    chance.reset();

    try chance.defrost(.P2, true);
    try expectProbability(&chance.probability, 25, 256);
    try expectValue(Optional(bool).true, chance.actions.p2.defrost);
}

test "Chance.sleep" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 6, 5, 4, 3, 2, 1 }, 1..7) |d, i| {
        chance.actions.p1.durations.sleep = @intCast(i);
        try chance.sleep(.P1, 0);
        try expectProbability(&chance.probability, 1, d);
        try expectValue(@as(u3, 0), chance.actions.p1.durations.sleep);

        chance.reset();

        if (i < 6) {
            chance.actions.p1.durations.sleep = @intCast(i);
            try chance.sleep(.P1, 1);
            try expectProbability(&chance.probability, d - 1, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p1.durations.sleep);

            chance.reset();
        }
    }
}

test "Chance.disable" {
    return error.SkipZigTest; // TODO
}

test "Chance.confusion" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.confusion);

            chance.reset();
        }

        if (i < 5) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.confusion);

            chance.reset();
        }
    }
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

/// Null object pattern implementation of Generation II `Chance` which does nothing, though chance
/// tracking should additionally be turned off entirely via `options.chance`.
pub const NULL: Null = .{};

const Null = struct {
    pub const Error = error{};

    pub fn switched(self: Null, player: Player, in: u8, out: u8) void {
        _ = .{ self, player, in, out };
    }

    pub fn speedTie(self: Null, p1: bool) Error!void {
        _ = .{ self, p1 };
    }

    pub fn quickClaw(self: Null, player: Player, proc: bool) Error!void {
        _ = .{ self, player, proc };
    }

    pub fn hit(self: Null, player: Player, ok: bool, accuracy: u8) Error!void {
        _ = .{ self, player, ok, accuracy };
    }

    pub fn criticalHit(self: Null, player: Player, crit: bool, rate: u8) Error!void {
        _ = .{ self, player, crit, rate };
    }

    pub fn damage(self: Null, player: Player, roll: u8) Error!void {
        _ = .{ self, player, roll };
    }

    pub fn confused(self: Null, player: Player, ok: bool) Error!void {
        _ = .{ self, player, ok };
    }

    pub fn attract(self: Null, player: Player, cant: bool) Error!void {
        _ = .{ self, player, cant };
    }

    pub fn defrost(self: Null, player: Player, thaw: bool) Error!void {
        _ = .{ self, player, thaw };
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
};
