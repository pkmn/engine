const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");

const chance = @import("chance.zig");

const enabled = pkmn.options.calc;

const Player = common.Player;

const Actions = chance.Actions;
const Action = chance.Action;

/// Information relevant to damage calculation that occured during a Generation II battle `update`.
pub const Summaries = extern struct {};

/// TODO
pub const Overrides = extern struct {
    /// TODO
    actions: Actions = .{},
};

/// Allows for forcing the value of specific RNG events during a Generation II battle `update` via
/// `overrides` and tracks `summaries` of information relevant to damage calculation.
pub const Calc = struct {
    /// Overrides the normal behavior of the RNG during an `update` to force specific outcomes.
    overrides: Overrides = .{},
    /// Information relevant to damage calculation.
    summaries: Summaries = .{},

    pub fn overridden(
        self: Calc,
        player: Player,
        comptime field: Action.Field,
    ) ?std.meta.FieldType(Action, field) {
        if (!enabled) return null;

        const overrides =
            if (player == .P1) self.overrides.actions.p1 else self.overrides.actions.p2;
        const val = @field(overrides, @tagName(field));
        return if (switch (@typeInfo(@TypeOf(val))) {
            .Enum => val != .None,
            .Int => val != 0,
            else => unreachable,
        }) val else null;
    }
};

/// Null object pattern implementation of Generation II `Calc` which does nothing, though damage
/// calculator support should additionally be turned off entirely via `options.calc`.
pub const NULL = Null{};

const Null = struct {
    pub fn overridden(
        self: Null,
        player: Player,
        comptime field: Action.Field,
    ) ?std.meta.FieldType(Action, field) {
        _ = .{ self, player };
        return null;
    }
};
