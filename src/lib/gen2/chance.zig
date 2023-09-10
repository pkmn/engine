const std = @import("std");

const assert = std.debug.assert;

const util = @import("../common/util.zig");

const Player = @import("../common/data.zig").Player;

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
    };
}

/// Null object pattern implementation of Generation II `Chance` which does nothing, though chance
/// tracking should additionally be turned off entirely via `options.chance`.
pub const NULL = Null{};

const Null = struct {
    pub const Error = error{};
};
