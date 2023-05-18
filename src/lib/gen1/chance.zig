const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

const enabled = @import("../common/options.zig").chance;

const Player = @import("../common/data.zig").Player;
const Optional = @import("../common/optional.zig").Optional;

const Move = @import("data.zig").Move;

/// TODO
pub fn Chance(comptime Rational: type) type {
    return struct {
        const Self = @This();

        /// TODO
        probability: Rational,
        /// TODO
        actions: Actions = .{},

        /// TODO
        pub const Error = Rational.Error;

        pub fn overridden(self: Self, player: Player, comptime field: []const u8) ?TypeOf(field) {
            if (!enabled) return null;

            const val = @field(if (player == .P1) self.actions.p1 else self.actions.p2, field);
            return if (switch (@typeInfo(@TypeOf(val))) {
                .Enum => val != .None,
                .Int => val != 0,
                else => unreachable,
            }) val else null;
        }

        pub fn speedTie(self: Self, p1: bool) Error!void {
            if (!enabled) return;

            try self.probability.update(1, 2);
            self.actions.p1.speed_tie = if (p1) .P1 else .P2;
            self.actions.p2.speed_tie = self.actions.p1.speed_tie;
        }

        pub fn criticalHit(self: Self, player: Player, crit: bool, rate: u8) Error!void {
            if (!enabled) return;

            // FIXME: need to ensure we don't update if crit is a nop
            try self.probability.update(if (crit) rate else 256 - rate, 256);
            self.actions.get(player).critical_hit = if (crit) .true else .false;
        }

        pub fn damage(self: Self, player: Player, base: u32, roll: u8) Error!void {
            if (!enabled) return;

            var dmg = @intCast(u16, base *% roll / 255);

            var min = roll;
            while (min > 217) {
                if (@intCast(u16, base *% (min - 1) / 255) == dmg) {
                    min -= 1;
                } else break;
            }
            var max = roll;
            while (max < 255) {
                if (@intCast(u16, base *% (max + 1) / 255) == dmg) {
                    max += 1;
                } else break;
            }
            assert(max >= min);
            assert(min >= 217);

            try self.probability.update(max - min + 1, 39);
            var action = self.actions.get(player);
            action.min_damage = @intCast(u6, min - 216);
            action.max_damage = @intCast(u6, max - 216);
        }
    };
}

pub const NULL = struct {
    const Self = @This();

    pub const Error = error{};

    pub fn overridden(self: Self, player: Player, comptime field: []const u8) ?TypeOf(field) {
        _ = self;
        _ = player;
        return null;
    }

    pub fn speedTie(self: Self, p1: bool) Error!void {
        _ = self;
        _ = p1;
    }

    pub fn criticalHit(self: Self, player: Player, crit: bool, rate: u8) Error!void {
        _ = self;
        _ = player;
        _ = crit;
        _ = rate;
    }

    pub fn damage(self: Self, player: Player, base: u32, roll: u8) Error!void {
        _ = self;
        _ = player;
        _ = base;
        _ = roll;
    }
}{};

fn TypeOf(comptime field: []const u8) type {
    return switch (@typeInfo(Action)) {
        .Struct => |info| blk: {
            for (info.fields) |f| if (std.mem.eql(u8, f.name, field)) break :blk f.type;
        },
        else => unreachable,
    };
}

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

    /// TODO
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
    /// If not 0, the roll 216 + min_damage represents the minimum roll to be returned
    /// by Rolls.damage which results in the same damage as 216 + max_damage.
    min_damage: u6 = 0,

    /// If not 0, the roll 216 + max_damage represents the maximum roll to be returned
    /// by Rolls.damage which results in the same damage as 216 + min_damage.
    max_damage: u6 = 0,
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
    /// Rolls.{disableDuration,sleepDuration,confusionDuration,bideThrashDuration}.
    duration: u4 = 0,
    /// If not None, the value to be returned by Rolls.criticalHit.
    critical_hit: Optional(bool) = .None,
    /// If not None, the value to return for Rolls.{confused,paralyzed}.
    cant: Optional(bool) = .None,

    comptime {
        assert(@sizeOf(Action) == 8);
    }
};

/// Observed values for various durations that need to be tracked in order to properly
/// deduplicate transitions with a primary key.
pub const Durations = packed struct {
    /// The number of turns a Pokémon has been observed to be disabled.
    disable: u4 = 0,
    /// The number of turns a Pokémon has been observed to be sleeping.
    sleep: u4 = 0,
    /// The number of turns a Pokémon has been observed to be confused.
    confusion: u4 = 0,
    /// The number of turns a Pokémon has been observed to be storing energy / thrashing.
    bide_thrash: u4 = 0,

    comptime {
        assert(@sizeOf(Durations) == 2);
    }
};
