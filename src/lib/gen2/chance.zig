const std = @import("std");

const assert = std.debug.assert;

const options = @import("../common/options.zig");
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
};

/// Information about the RNG that was observed during a Generation II battle `update` for a
/// single player.
pub const Action = packed struct {
    /// If not None, the value to be returned for TODO
    quick_claw: Optional(bool) = .None,
    /// If not None, the Player to be returned by Rolls.speedTie.
    speed_tie: Optional(Player) = .None,
    _: u4 = 0,

    pub const Field = std.meta.FieldEnum(Action);

    comptime {
        assert(@sizeOf(Action) == 1);
    }

    /// Perform a reset by clearing fields which should not persist across updates.
    pub inline fn reset(self: *Action) void {
        _ = self; // TODO
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
            self.probability.reset();
            self.actions.reset();
            // TODO: self.pending = .{};
        }

        pub fn switched(self: *Self, player: Player, in: u8, out: u8) void {
            if (!enabled) return;

            assert(in >= 1 and in <= 6);
            assert(out >= 1 and out <= 6);

            _ = self;
            _ = player;

            // var action = self.actions.get(player);

            // const slp = action.durations.sleep;
            // action.durations = .{};

            // self.sleeps[@intFromEnum(player)][out - 1] = slp;
            // action.durations.sleep = @intCast(self.sleeps[@intFromEnum(player)][in - 1]);

            // self.actions.get(player.foe()).durations.binding = 0;
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
    };
}

/// Null object pattern implementation of Generation II `Chance` which does nothing, though chance
/// tracking should additionally be turned off entirely via `options.chance`.
pub const NULL = Null{};

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
};
