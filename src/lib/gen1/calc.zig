const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

const options = @import("../common/options.zig");

const Player = @import("../common/data.zig").Player;

const chance = @import("chance.zig");

const enabled = options.calc;

const Actions = chance.Actions;
const Action = chance.Action;

/// TODO
pub const Summary = extern struct {};

/// TODO
pub const Calc = struct {
    /// TODO
    overrides: Actions = .{},
    /// TODO
    summary: Summary = .{},

    pub fn overridden(self: Calc, player: Player, comptime field: []const u8) ?TypeOf(field) {
        if (!enabled) return null;

        const val = @field(if (player == .P1) self.overrides.p1 else self.overrides.p2, field);
        return if (switch (@typeInfo(@TypeOf(val))) {
            .Enum => val != .None,
            .Int => val != 0,
            else => unreachable,
        }) val else null;
    }
};

pub const NULL = Null{};

const Null = struct {
    pub fn overridden(self: Null, player: Player, comptime field: []const u8) ?TypeOf(field) {
        _ = self;
        _ = player;
        return null;
    }
};

fn TypeOf(comptime field: []const u8) type {
    for (@typeInfo(Action).Struct.fields) |f| if (std.mem.eql(u8, f.name, field)) return f.type;
    unreachable;
}
