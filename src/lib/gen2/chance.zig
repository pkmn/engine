const std = @import("std");

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const options = @import("../common/options.zig");
const rational = @import("../common/rational.zig");
const util = @import("../common/util.zig");

const Array = @import("../common/array.zig").Array;
const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const data = @import("data.zig");

const enabled = options.chance;
const showdown = options.showdown;

const PointerType = util.PointerType;
const isPointerTo = util.isPointerTo;

const Move = data.Move;
const Type = data.Type;
const Effectiveness = data.Effectiveness;
const TriAttack = data.TriAttack;

const Int = if (@hasField(std.builtin.Type, "int")) .int else .Int;
const Enum = if (@hasField(std.builtin.Type, "enum")) .@"enum" else .Enum;
const Struct = if (@hasField(std.builtin.Type, "struct")) .@"struct" else .Struct;

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
    pub fn get(self: anytype, player: Player) PointerType(@TypeOf(self), Action) {
        assert(isPointerTo(self, Actions));
        return if (player == .P1) &self.p1 else &self.p2;
    }

    /// Returns true if `a` is equal to `b`.
    pub fn eql(a: Actions, b: Actions) bool {
        return @as(u128, @bitCast(a.p1)) == @as(u128, @bitCast(b.p1)) and
            @as(u128, @bitCast(a.p2)) == @as(u128, @bitCast(b.p2));
    }

    /// Returns true if `a` has the same "shape" as `b`, where `Actions` are defined to have the
    /// same shape if they have the same fields set (though those fields need not necessarily be
    /// set to the same value).
    pub fn matches(a: Actions, b: Actions) bool {
        inline for (@field(@typeInfo(Actions), @tagName(Struct)).fields) |player| {
            inline for (@field(@typeInfo(Action), @tagName(Struct)).fields) |field| {
                const a_val = @field(@field(a, player.name), field.name);
                const b_val = @field(@field(b, player.name), field.name);

                switch (@typeInfo(@TypeOf(a_val))) {
                    Enum => if ((@intFromEnum(a_val) > 0) != (@intFromEnum(b_val) > 0))
                        return false,
                    Int => if ((a_val > 0) != (b_val > 0)) return false,
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

    pub const format = if (@hasDecl(std.fmt, "Options")) new else old;
    fn old(a: Actions, comptime f: []const u8, o: anytype, w: anytype) !void {
        _ = .{ f, o };
        try new(a, w);
    }
    fn new(a: Actions, w: anytype) !void {
        try fmt(a, w, false);
    }
};

test Actions {
    const a: Actions = .{ .p1 = .{ .hit = .true, .confused = .false, .damages = 245 } };
    const b: Actions = .{ .p1 = .{ .hit = .false, .confused = .true, .damages = 246 } };
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

/// Observation made about a duration - whether the duration has started, been continued, or ended.
pub const Observation = enum { started, continuing, ended };

pub const Damages = Array(5, u8);
pub const Criticals = Array(5, Optional(bool));

/// Information about the RNG that was observed during a Generation II battle `update` for a
/// single player.
pub const Action = packed struct(u128) {
    /// TODO
    damages: Damages.T = 0,
    // TODO
    critical_hits: Criticals.T = 0,

    /// If not None, the Player to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,
    /// If not None, the value to be returned for Rolls.quickClaw.
    quick_claw: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.hit.
    hit: Optional(bool) = .None,
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

    /// If not None, the value to be returned for Rolls.item (Focus Band / King's Rock).
    item: Optional(bool) = .None,
    /// If not None, the value to be returned for Rolls.protect.
    protect: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.triAttack.
    tri_attack: Optional(TriAttack) = .None,
    /// If not 0, the value to return for Rolls.tripleKick.
    triple_kick: u2 = 0,

    /// If not 0, (present - 1) * 40 should be returned as the base power for Rolls.present.
    present: u3 = 0,
    /// If not 0, magnitude + 3 should be returned as the number for Rolls.magnitude.
    magnitude: u3 = 0,
    /// If not 0, the amount of PP to deduct for Rolls.spite.
    spite: u3 = 0,
    /// If not 0, the move slot (1-4) to return in Rolls.moveSlot. If present as an override,
    /// invalid values (eg. due to empty move slots or 0 PP) will be ignored.
    move_slot: u3 = 0,
    /// If not 0, the party slot (1-6) to return in Rolls.forceSwitch. If present as an override,
    /// invalid values (eg. due to empty party slots or fainted members) will be ignored.
    force_switch: u3 = 0,
    /// If not 0, the value (2-5) to return for Rolls.distribution for multi hit.
    multi_hit: u3 = 0,

    sleep: Optional(Observation) = .None,
    /// TODO
    confusion: Optional(Observation) = .None,
    /// TODO
    disable: Optional(Observation) = .None,
    /// TODO
    attacking: Optional(Observation) = .None,
    /// TODO
    binding: Optional(Observation) = .None,
    /// TODO
    encore: Optional(Observation) = .None,

    /// If not 0, the value to by one of the Rolls.*Duration rolls.
    duration: u3 = 0,
    /// If not None, the value to return for Rolls.conversion2.
    conversion_2: Optional(Type) = .None,

    /// If not 0, psywave should be returned as the damage roll for Rolls.psywave.
    psywave: u8 = 0,

    /// If not None, the Move to return for Rolls.metronome.
    metronome: Move = .None,

    pub const Field = std.meta.FieldEnum(Action);

    pub const format = if (@hasDecl(std.fmt, "Options")) new else old;
    fn old(a: Action, comptime f: []const u8, o: anytype, w: anytype) !void {
        _ = .{ f, o };
        try new(a, w);
    }
    fn new(a: Action, w: anytype) !void {
        try fmt(a, w, false);
    }

    pub fn fmt(self: Action, writer: anytype, shape: bool) !void {
        try writer.writeByte('(');
        var printed = false;
        inline for (@field(@typeInfo(Action), @tagName(Struct)).fields) |field| {
            const val = @field(self, field.name);
            switch (@typeInfo(@TypeOf(val))) {
                Enum => if (val != .None) {
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
                Int => if (val != 0) {
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

        /// Possible error returned by operations tracking chance probability.
        pub const Error = Rational.Error;

        /// Convenience helper to clear fields which typically should be cleared between updates.
        pub fn reset(self: *Self) void {
            if (!enabled) return;

            self.probability.reset();
            self.actions = .{};
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

        pub fn criticalHit(self: *Self, player: Player, i: u3, crit: bool, rate: u8) Error!void {
            if (!enabled) return;

            const n = if (crit) rate else @as(u8, @intCast(256 - @as(u9, rate)));
            try self.probability.update(n, 256);
            var a = self.actions.get(player);
            a.critical_hits = Criticals.set(a.critical_hits, i, if (crit) .true else .false);
        }

        pub fn damage(self: *Self, player: Player, i: u3, roll: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 39);
            var a = self.actions.get(player);
            a.damages = Damages.set(a.damages, i, roll);
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

        pub fn item(self: *Self, player: Player, proc: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (proc) 30 else 226), 256);
            self.actions.get(player).item = if (proc) .true else .false;
        }

        pub fn protect(self: *Self, player: Player, num: u8, ok: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(@as(u8, if (ok) num + 1 else 255 - num - 1), 255);
            self.actions.get(player).protect = if (ok) .true else .false;
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

        pub fn moveSlot(self: *Self, player: Player, slot: u4, n: u4) Error!void {
            if (!enabled) return;

            if (n != 1) try self.probability.update(1, n);
            self.actions.get(player).move_slot = @intCast(slot);
        }

        pub fn forceSwitch(self: *Self, player: Player, slot: u4, n: u4) Error!void {
            if (!enabled) return;

            if (n != 1) try self.probability.update(1, n);
            self.actions.get(player).force_switch = @intCast(slot);
        }

        pub fn psywave(self: *Self, player: Player, power: u8, max: u8) Error!void {
            if (!enabled) return;

            try self.probability.update(1, max);
            self.actions.get(player).psywave = power;
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

        pub fn duration(self: *Self, player: Player, turns: u3) void {
            if (!enabled) return;

            self.actions.get(player).duration = if (options.key) 2 else turns;
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

    try chance.criticalHit(.P1, 0, true, 17);
    try expectValue(Optional(bool).true, Criticals.get(chance.actions.p1.critical_hits, 0));
    try expectProbability(&chance.probability, 17, 256);

    chance.reset();

    try chance.criticalHit(.P2, 1, false, 5);
    try expectProbability(&chance.probability, 251, 256);
    try expectValue(Optional(bool).false, Criticals.get(chance.actions.p2.critical_hits, 1));
}

test "Chance.damage" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.damage(.P1, 0, 219);
    try expectValue(@as(u8, 219), Damages.get(chance.actions.p1.damages, 0));
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

test "Chance.item" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.item(.P1, false);
    try expectProbability(&chance.probability, 113, 128);
    try expectValue(Optional(bool).false, chance.actions.p1.item);

    chance.reset();

    try chance.item(.P2, true);
    try expectProbability(&chance.probability, 15, 128);
    try expectValue(Optional(bool).true, chance.actions.p2.item);
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
    try expectValue(@as(u8, 100), chance.actions.p2.psywave);
}

test "Chance.metronome" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.metronome(.P1, Move.HornAttack, 1);
    try expectProbability(&chance.probability, 1, 238);
    try expectValue(Move.HornAttack, chance.actions.p1.metronome);
}

test "Chance.moveSlot" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.moveSlot(.P2, 2, 2);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(@as(u3, 2), chance.actions.p2.move_slot);

    chance.reset();

    try chance.moveSlot(.P1, 1, 3);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u3, 1), chance.actions.p1.move_slot);

    chance.reset();

    try chance.moveSlot(.P1, 4, 1);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(@as(u3, 4), chance.actions.p1.move_slot);
}

test "Chance.forceSwitch" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.forceSwitch(.P2, 2, 2);
    try expectProbability(&chance.probability, 1, 2);
    try expectValue(@as(u3, 2), chance.actions.p2.force_switch);

    chance.reset();

    try chance.forceSwitch(.P1, 1, 3);
    try expectProbability(&chance.probability, 1, 3);
    try expectValue(@as(u3, 1), chance.actions.p1.force_switch);

    chance.reset();

    try chance.forceSwitch(.P1, 4, 1);
    try expectProbability(&chance.probability, 1, 1);
    try expectValue(@as(u3, 4), chance.actions.p1.force_switch);
}

test "Chance.multiHit" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    try chance.multiHit(.P1, 3);
    try expectProbability(&chance.probability, 3, 8);
    try expectValue(@as(u3, 3), chance.actions.p1.multi_hit);

    chance.reset();

    try chance.multiHit(.P2, 5);
    try expectProbability(&chance.probability, 1, 8);
    try expectValue(@as(u3, 5), chance.actions.p2.multi_hit);
}

test "Chance.duration" {
    var chance: Chance(rational.Rational(u64)) = .{ .probability = .{} };

    chance.duration(.P1, 2);
    try expectValue(@as(u3, 2), chance.actions.p1.duration);
}

pub fn expectProbability(r: anytype, p: u64, q: u64) !void {
    if (!enabled) return;

    r.reduce();
    if (r.p != p or r.q != q) {
        print("expected {d}/{d}, found {f}\n", .{ p, q, r });
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

    pub fn criticalHit(self: Null, player: Player, i: u3, crit: bool, rate: u8) Error!void {
        _ = .{ self, player, i, crit, rate };
    }

    pub fn damage(self: Null, player: Player, i: u3, roll: u8) Error!void {
        _ = .{ self, player, i, roll };
    }

    pub fn confused(self: Null, player: Player, ok: bool) Error!void {
        _ = .{ self, player, ok };
    }

    pub fn attract(self: Null, player: Player, cant: bool) Error!void {
        _ = .{ self, player, cant };
    }

    pub fn paralyzed(self: Null, player: Player, par: bool) Error!void {
        _ = .{ self, player, par };
    }

    pub fn defrost(self: Null, player: Player, thaw: bool) Error!void {
        _ = .{ self, player, thaw };
    }

    pub fn secondaryChance(self: Null, player: Player, proc: bool, rate: u8) Error!void {
        _ = .{ self, player, proc, rate };
    }

    pub fn item(self: Null, player: Player, proc: bool) Error!void {
        _ = .{ self, player, proc };
    }

    pub fn protect(self: Null, player: Player, num: u8, ok: bool) Error!void {
        _ = .{ self, player, num, ok };
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

    pub fn moveSlot(self: Null, player: Player, slot: u4, n: u4) Error!void {
        _ = .{ self, player, slot, n };
    }

    pub fn forceSwitch(self: Null, player: Player, slot: u4, n: u4) Error!void {
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

    pub fn duration(self: Null, player: Player, turns: u3) void {
        _ = .{ self, player, turns };
    }
};
