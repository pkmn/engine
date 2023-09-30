const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const options = @import("../common/options.zig");
const rational = @import("../common/rational.zig");
const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig");

const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const data = @import("./data.zig");

const enabled = options.chance;
const showdown = options.showdown;

const Gen12 = rng.Gen12;

const Move = data.Move;
const Type = data.Type;
const Effectiveness = data.Effectiveness;
const TriAttack = data.TriAttack;

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
        return @as(u128, @bitCast(a.p1)) == @as(u128, @bitCast(b.p1)) and
            @as(u128, @bitCast(a.p2)) == @as(u128, @bitCast(b.p2));
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
                        const a_val_f = @field(a_val, f.name);
                        const b_val_f = @field(b_val, f.name);
                        switch (@typeInfo(@TypeOf(a_val_f))) {
                            .Int => if ((a_val_f > 0) != (b_val_f > 0)) return false,
                            .Bool => if (a_val_f != b_val_f) return false,
                            else => unreachable,
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
    const g: Actions = .{ .p1 = .{ .hit = .false, .durations = .{ .confusion = 1 } } };
    const h: Actions =
        .{ .p1 = .{ .hit = .false, .durations = .{ .confusion = 1, .thrash = true } } };

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
    try expect(d.matches(e));
    try expect(!d.matches(f));
    try expect(!g.matches(h));
    try expect(h.matches(h));
}

/// Information about the RNG that was observed during a Generation II battle `update` for a
/// single player.
pub const Action = packed struct(u128) {
    /// If not 0, the roll to be returned Rolls.damage.
    damage: u8 = 0,

    /// If not None, the Player to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,
    /// If not None, the value to be returned for Rolls.quickClaw.
    quick_claw: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.hit.
    hit: Optional(bool) = .None,
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

    /// If not None, the value to be returned for Rolls.secondaryChance.
    secondary_chance: Optional(bool) = .None,
    /// If not None, the value to be returned for Rolls.focusBand.
    focus_band: Optional(bool) = .None,
    /// If not None, the value to be returned for Rolls.kingsRock.
    kings_rock: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.triAttack.
    tri_attack: Optional(TriAttack) = .None,

    /// If not 0, (present - 1) * 40 should be returned as the base power for Rolls.present.
    present: u3 = 0,
    /// If not 0, magnitude + 3 should be returned as the number for Rolls.magnitude.
    magnitude: u3 = 0,
    /// If not 0, the value to return for Rolls.tripleKick.
    triple_kick: u2 = 0,

    /// If not 0,  the amount of PP to deduct for Rolls.spite.
    spite: u3 = 0,
    /// If not None, the value to return for Rolls.conversion2.
    conversion_2: Optional(Type) = .None,

    /// If not None, the value to be returned for Rolls.protect.
    protect: Optional(bool) = .None,
    /// If not 0, the move slot (1-4) to return in Rolls.moveSlot. If present as an override,
    /// invalid values (eg. due to empty move slots or 0 PP) will be ignored.
    move_slot: u3 = 0,
    /// If not 0, the party slot (1-6) to return in Rolls.forceSwitch. If present as an override,
    /// invalid values (eg. due to empty party slots or fainted members) will be ignored.
    force_switch: u3 = 0,

    /// If not 0, the value (2-5) to return for Rolls.distribution for multi hit.
    multi_hit: u4 = 0,
    /// If not 0, the value to by one of the Rolls.*Duration rolls.
    duration: u4 = 0,

    /// If not 0, psywave - 1 should be returned as the damage roll for Rolls.psywave.
    psywave: u8 = 0,

    /// If not None, the Move to return for Rolls.metronome.
    metronome: Move = .None,

    _: u16 = 0,

    /// Observed values of various durations. Does not influence future RNG calls. TODO
    durations: Duration = .{},

    pub const DURATIONS: u128 = 0xFFFFFFFF00000000_0000000000000000;

    pub const Field = std.meta.FieldEnum(Action);

    /// Perform a reset by clearing fields which should not persist across updates.
    pub inline fn reset(self: *Action) void {
        self.* = @bitCast(@as(u128, @bitCast(self.*)) & DURATIONS);
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
pub const Duration = packed struct(u32) {
    /// The number of turns a Pokémon has been observed to be sleeping.
    sleep: u3 = 0,
    /// The number of turns a Pokémon has been observed to be confused.
    confusion: u3 = 0,
    /// TODO
    thrash: bool = false,
    /// The number of turns a Pokémon has been observed to be disabled.
    disable: u4 = 0,
    /// The number of turns a Pokémon has been observed to be attacking.
    attacking: u3 = 0,
    /// The number of turns a Pokémon has been observed to be binding their opponent.
    binding: u3 = 0,
    /// The number of turns a Pokémon has been observed to be encored.
    encore: u3 = 0,

    _: u12 = 0,

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

        pub fn secondaryChance(self: *Self, player: Player, proc: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (proc) rate else @as(u8, @intCast(256 - @as(u9, rate)));
            try self.probability.update(n, 256);
            self.actions.get(player).secondary_chance = if (proc) .true else .false;
        }

        pub fn focusBand(self: *Self, player: Player, proc: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (proc) 30 else 226), 256);
            self.actions.get(player).focus_band = if (proc) .true else .false;
        }

        pub fn kingsRock(self: *Self, player: Player, proc: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (proc) 30 else 226), 256);
            self.actions.get(player).kings_rock = if (proc) .true else .false;
        }

        pub fn triAttack(self: *Self, player: Player, status: TriAttack) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 3);
            self.actions.get(player).tri_attack = @enumFromInt(@intFromEnum(status) + 1);
        }

        const PRESENT: [4]u8 = if (showdown) .{ 2, 4, 3, 1 } else .{ 51, 103, 77, 25 };

        pub fn present(self: *Self, player: Player, power: u8) Error!void {
            if (!enabled) return;

            const index = power / 40;
            try self.probability.update(PRESENT[index], if (showdown) 10 else 256);
            self.actions.get(player).present = @intCast(index + 1);
        }

        const MAGNITUDE: [7]u8 = if (showdown)
            .{ 5, 10, 20, 30, 20, 10, 5 }
        else
            .{ 14, 26, 50, 77, 51, 25, 13 };

        pub fn magnitude(self: *Self, player: Player, num: u8) Error!void {
            if (!enabled) return;

            const index = num - 4;
            try self.probability.update(MAGNITUDE[index], if (showdown) 100 else 256);
            self.actions.get(player).magnitude = @intCast(index + 1);
        }

        pub fn tripleKick(self: *Self, player: Player, hits: u2) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 3);
            self.actions.get(player).triple_kick = hits;
        }

        pub fn spite(self: *Self, player: Player, pp: u3) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 4);
            self.actions.get(player).spite = pp;
        }

        pub fn conversion2(self: *Self, player: Player, ty: Type, mtype: Type, num: u8) Error!void {
            if (!enabled) return;

            assert(showdown or num == 0);
            const n = if (num != 0)
                num
            else n: {
                const neutral = @intFromEnum(Effectiveness.Neutral);
                var i: u8 = 0;
                for (0..Type.size) |t| {
                    if (@intFromEnum(mtype.effectiveness(@enumFromInt(t))) < neutral) i += 1;
                }
                assert(i > 0 and i <= 7);
                break :n i;
            };

            try self.probability.update(1, n);
            self.actions.get(player).conversion_2 = @enumFromInt(@intFromEnum(ty) + 1);
        }

        pub fn protect(self: *Self, player: Player, num: u8, ok: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (ok) num + 1 else 255 - num - 1), 255);
            self.actions.get(player).protect = if (ok) .true else .false;
        }

        pub fn moveSlot(self: *Self, player: Player, slot: u3, n: u3) Error!void {
            if (!enabled) return;

            if (n != 1) try self.probability.update(1, n);
            self.actions.get(player).move_slot = @intCast(slot);
        }

        pub fn forceSwitch(self: *Self, player: Player, slot: u3, n: u3) Error!void {
            if (!enabled) return;

            if (n != 1) try self.probability.update(1, n);
            self.actions.get(player).force_switch = @intCast(slot);
        }

        pub fn psywave(self: *Self, player: Player, power: u8, max: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, max);
            self.actions.get(player).psywave = power + 1;
        }

        pub fn metronome(self: *Self, player: Player, move: Move, n: u2) Error!void {
            if (!enabled) return;

            try self.probability.update(1, Move.METRONOME.len - @as(u8, n));
            self.actions.get(player).metronome = move;
        }

        pub fn multiHit(self: *Self, player: Player, n: u3) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (n > 3) 1 else 3), 8);
            self.actions.get(player).multi_hit = n;
        }

        pub fn duration(
            self: *Self,
            comptime field: Duration.Field,
            player: Player,
            target: Player,
            turns: u4,
        ) void {
            if (!enabled) return;

            var durations = &self.actions.get(target).durations;
            assert(@field(durations, @tagName(field)) == 0 or
                (field == .confusion and player == target));
            @field(durations, @tagName(field)) = 1;
            if (field == .confusion) durations.thrash = player == target;
            self.actions.get(player).duration = if (options.key) 1 else turns;
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

        pub fn confusion(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.confusion;
            const hi: u8 = if (durations.thrash) 3 else 5;
            const p = hi + 1;
            if (turns == 0) {
                assert(n >= 2 and n <= hi);
                if (n != hi) try self.probability.update(1, p - @as(u4, n));
                durations.confusion = 0;
            } else {
                assert(n >= 1 and n < hi);
                if (n > 1) try self.probability.update(p - @as(u4, n) - 1, p - @as(u4, n));
                durations.confusion += 1;
            }
        }

        pub fn disable(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.disable;
            const hi = if (showdown) 5 else 8;
            const p = hi + 1;
            if (turns == 0) {
                assert(n >= 2 and n <= hi);
                if (n != hi) try self.probability.update(1, p - n);
                durations.disable = 0;
            } else {
                assert(n >= 1 and n < hi);
                if (n > 1) try self.probability.update(p - n - 1, p - n);
                durations.disable += 1;
            }
        }

        pub fn attacking(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.attacking;
            if (turns == 0) {
                assert(n >= 2 and n <= 3);
                if (n != 3) try self.probability.update(1, 4 - @as(u4, n));
                durations.attacking = 0;
            } else {
                assert(n >= 1 and n < 3);
                if (n > 1) try self.probability.update(4 - @as(u4, n) - 1, 4 - @as(u4, n));
                durations.attacking += 1;
            }
        }

        pub fn binding(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.binding;
            if (turns == 0) {
                assert(n >= 2 and n <= 5);
                if (n != 5) try self.probability.update(1, 6 - @as(u4, n));
                durations.binding = 0;
            } else {
                assert(n >= 1 and n < 5);
                if (n > 1) try self.probability.update(6 - @as(u4, n) - 1, 6 - @as(u4, n));
                durations.binding += 1;
            }
        }

        // TODO: consider sharing implementation with binding
        pub fn encore(self: *Self, player: Player, turns: u4) Error!void {
            if (!enabled) return;

            var durations = &self.actions.get(player).durations;
            const n = durations.encore;
            if (turns == 0) {
                assert(n >= 2 and n <= 5);
                if (n != 5) try self.probability.update(1, 6 - @as(u4, n));
                durations.encore = 0;
            } else {
                assert(n >= 1 and n < 5);
                if (n > 1) try self.probability.update(6 - @as(u4, n) - 1, 6 - @as(u4, n));
                durations.encore += 1;
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

test "Chance.focusBand" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.focusBand(.P1, false);
    try expectProbability(&chance.probability, 113, 128);
    try expectValue(Optional(bool).false, chance.actions.p1.focus_band);

    chance.reset();

    try chance.focusBand(.P2, true);
    try expectProbability(&chance.probability, 15, 128);
    try expectValue(Optional(bool).true, chance.actions.p2.focus_band);
}

test "Chance.kingsRock" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.kingsRock(.P1, false);
    try expectProbability(&chance.probability, 113, 128);
    try expectValue(Optional(bool).false, chance.actions.p1.kings_rock);

    chance.reset();

    try chance.kingsRock(.P2, true);
    try expectProbability(&chance.probability, 15, 128);
    try expectValue(Optional(bool).true, chance.actions.p2.kings_rock);
}

test "Chance.triAttack" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.triAttack(.P1, .BRN);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(Optional(TriAttack).BRN, chance.actions.p1.tri_attack);

    chance.reset();

    try chance.triAttack(.P2, .FRZ);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(Optional(TriAttack).FRZ, chance.actions.p2.tri_attack);
}

test "Chance.present" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.present(.P2, 120);
    if (showdown) {
        try expectProbability(&chance.probability, 1, 10);
    } else {
        try expectProbability(&chance.probability, 25, 256);
    }
    try expectValue(@as(u3, 4), chance.actions.p2.present);

    chance.reset();

    try chance.present(.P1, 0);
    if (showdown) {
        try expectProbability(&chance.probability, 1, 5);
    } else {
        try expectProbability(&chance.probability, 51, 256);
    }
    try expectValue(@as(u3, 1), chance.actions.p1.present);
}

test "Chance.magnitude" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.magnitude(.P2, 10);
    if (showdown) {
        try expectProbability(&chance.probability, 1, 20);
    } else {
        try expectProbability(&chance.probability, 13, 256);
    }
    try expectValue(@as(u3, 7), chance.actions.p2.magnitude);

    chance.reset();

    try chance.magnitude(.P1, 8);
    if (showdown) {
        try expectProbability(&chance.probability, 1, 5);
    } else {
        try expectProbability(&chance.probability, 51, 256);
    }
    try expectValue(@as(u3, 5), chance.actions.p1.magnitude);
}

test "Chance.tripleKick" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.tripleKick(.P1, 2);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u2, 2), chance.actions.p1.triple_kick);
}

test "Chance.spite" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.spite(.P1, 3);
    try expectProbability(&chance.probability, 1, 4);
    try expectValue(@as(u3, 3), chance.actions.p1.spite);
}

test "Chance.conversion2" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    if (showdown) {
        try chance.conversion2(.P1, .Normal, .Ghost, 3);
        try expectProbability(&chance.probability, 1, 3);
        try expectValue(Optional(Type).Normal, chance.actions.p1.conversion_2);
    } else {
        try chance.conversion2(.P2, .Normal, .Ghost, 0);
        try expectProbability(&chance.probability, 1, 3);
        try expectValue(Optional(Type).Normal, chance.actions.p2.conversion_2);
    }
    chance.reset();

    try chance.conversion2(.P2, .Fire, .Bug, 0);
    try expectProbability(&chance.probability, 1, 6);
    try expectValue(Optional(Type).Fire, chance.actions.p2.conversion_2);
}

test "Chance.psywave" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.psywave(.P2, 100, 150);
    try expectProbability(&chance.probability, 1, 150);
    try expectValue(@as(u8, 101), chance.actions.p2.psywave);
}

test "Chance.metronome" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.metronome(.P1, Move.HornAttack, 1);
    try expectProbability(&chance.probability, 1, 238);
    try expectValue(Move.HornAttack, chance.actions.p1.metronome);
}

test "Chance.protect" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.protect(.P1, 15, false);
    try expectProbability(&chance.probability, 239, 255);
    try expectValue(Optional(bool).false, chance.actions.p1.protect);

    chance.reset();

    try chance.protect(.P2, 63, true);
    try expectProbability(&chance.probability, 64, 255);
    try expectValue(Optional(bool).true, chance.actions.p2.protect);
}

test "Chance.moveSlot" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.moveSlot(.P2, 2, 2);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(@as(u4, 2), chance.actions.p2.move_slot);

    chance.reset();

    try chance.moveSlot(.P1, 1, 3);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u4, 1), chance.actions.p1.move_slot);

    chance.reset();

    try chance.moveSlot(.P1, 4, 1);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(@as(u4, 4), chance.actions.p1.move_slot);
}

test "Chance.forceSwitch" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.forceSwitch(.P2, 2, 2);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(@as(u4, 2), chance.actions.p2.force_switch);

    chance.reset();

    try chance.forceSwitch(.P1, 1, 3);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u4, 1), chance.actions.p1.force_switch);

    chance.reset();

    try chance.forceSwitch(.P1, 4, 1);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(@as(u4, 4), chance.actions.p1.force_switch);
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
    try expectValue(@as(u3, 1), chance.actions.p2.durations.sleep);
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

test "Chance.confusion" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    chance.actions.p2.durations.thrash = false;
    for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.confusion);
            try expectValue(false, chance.actions.p2.durations.thrash);

            chance.reset();
        }

        if (i < 5) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.confusion);
            try expectValue(false, chance.actions.p2.durations.thrash);

            chance.reset();
        }
    }

    chance.reset();

    chance.actions.p2.durations.thrash = true;
    for ([_]u8{ 1, 2, 1 }, 1..4) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.confusion);
            try expectValue(true, chance.actions.p2.durations.thrash);

            chance.reset();
        }

        if (i < 3) {
            chance.actions.p2.durations.confusion = @intCast(i);
            try chance.confusion(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.confusion);
            try expectValue(true, chance.actions.p2.durations.thrash);

            chance.reset();
        }
    }
}

test "Chance.disable" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };
    if (showdown) {
        for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
            if (i > 1) {
                chance.actions.p2.durations.disable = @intCast(i);
                try chance.disable(.P2, 0);
                try expectProbability(&chance.probability, 1, d);
                try expectValue(@as(u4, 0), chance.actions.p2.durations.disable);

                chance.reset();
            }

            if (i < 5) {
                chance.actions.p2.durations.disable = @intCast(i);
                try chance.disable(.P2, 1);
                try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
                try expectValue(@as(u4, @intCast(i)) + 1, chance.actions.p2.durations.disable);

                chance.reset();
            }
        }
    } else {
        for ([_]u8{ 1, 7, 6, 5, 4, 3, 2, 1 }, 1..9) |d, i| {
            if (i > 1) {
                chance.actions.p2.durations.disable = @intCast(i);
                try chance.disable(.P2, 0);
                try expectProbability(&chance.probability, 1, d);
                try expectValue(@as(u4, 0), chance.actions.p2.durations.disable);

                chance.reset();
            }

            if (i < 8) {
                chance.actions.p2.durations.disable = @intCast(i);
                try chance.disable(.P2, 1);
                try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
                try expectValue(@as(u4, @intCast(i)) + 1, chance.actions.p2.durations.disable);

                chance.reset();
            }
        }
    }
}

test "Chance.attacking" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 2, 1 }, 1..4) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.attacking = @intCast(i);
            try chance.attacking(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.attacking);

            chance.reset();
        }

        if (i < 3) {
            chance.actions.p2.durations.attacking = @intCast(i);
            try chance.attacking(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.attacking);

            chance.reset();
        }
    }
}

test "Chance.binding" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.binding = @intCast(i);
            try chance.binding(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.binding);

            chance.reset();
        }

        if (i < 5) {
            chance.actions.p2.durations.binding = @intCast(i);
            try chance.binding(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.binding);

            chance.reset();
        }
    }
}

test "Chance.encore" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    for ([_]u8{ 1, 4, 3, 2, 1 }, 1..6) |d, i| {
        if (i > 1) {
            chance.actions.p2.durations.encore = @intCast(i);
            try chance.encore(.P2, 0);
            try expectProbability(&chance.probability, 1, d);
            try expectValue(@as(u3, 0), chance.actions.p2.durations.encore);

            chance.reset();
        }

        if (i < 5) {
            chance.actions.p2.durations.encore = @intCast(i);
            try chance.encore(.P2, 1);
            try expectProbability(&chance.probability, if (d > 1) d - 1 else d, d);
            try expectValue(@as(u3, @intCast(i)) + 1, chance.actions.p2.durations.encore);

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

    pub fn secondaryChance(self: Null, player: Player, proc: bool, rate: u8) Error!void {
        _ = .{ self, player, proc, rate };
    }

    pub fn focusBand(self: Null, player: Player, proc: bool) Error!void {
        _ = .{ self, player, proc };
    }

    pub fn triAttack(self: Null, player: Player, status: TriAttack) Error!void {
        _ = .{ self, player, status };
    }

    pub fn present(self: Null, player: Player, power: u8) Error!void {
        _ = .{ self, player, power };
    }

    pub fn magnitude(self: Null, player: Player, num: u8) Error!void {
        _ = .{ self, player, num };
    }

    pub fn spite(self: Null, player: Player, pp: u3) Error!void {
        _ = .{ self, player, pp };
    }

    pub fn conversion2(self: Null, player: Player, ty: Type, mtype: Type, num: u8) Error!void {
        _ = .{ self, player, ty, mtype, num };
    }

    pub fn protect(self: Null, player: Player, num: u8, ok: bool) Error!void {
        _ = .{ self, player, num, ok };
    }

    pub fn moveSlot(self: Null, player: Player, slot: u3, n: u3) Error!void {
        _ = .{ self, player, slot, n };
    }

    pub fn forceSwitch(self: Null, player: Player, slot: u3, n: u3) Error!void {
        _ = .{ self, player, slot, n };
    }

    pub fn multiHit(self: Null, player: Player, n: u3) Error!void {
        _ = .{ self, player, n };
    }

    pub fn psywave(self: Null, player: Player, power: u8, max: u8) Error!void {
        _ = .{ self, player, power, max };
    }

    pub fn metronome(self: Null, player: Player, move: Move, n: u2) Error!void {
        _ = .{ self, player, move, n };
    }

    pub fn duration(
        self: Null,
        comptime field: Duration.Field,
        player: Player,
        target: Player,
        turns: u4,
    ) void {
        _ = .{ self, field, player, target, turns };
    }

    pub fn sleep(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn confusion(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn disable(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn attacking(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn binding(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }

    pub fn encore(self: Null, player: Player, turns: u4) Error!void {
        _ = .{ self, player, turns };
    }
};
