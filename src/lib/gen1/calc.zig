const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

const options = @import("../common/options.zig");

const Player = @import("../common/data.zig").Player;

const chance = @import("chance.zig");

const enabled = options.calc;

const Actions = chance.Actions;
const Action = chance.Action;

pub const Summaries = extern struct {
    p1: Summary = .{},
    p2: Summary = .{},

    comptime {
        assert(@sizeOf(Summaries) == 8);
    }

    /// Returns the `Sumamary` for the given `player`.
    pub inline fn get(self: *Summaries, player: Player) *Summary {
        return if (player == .P1) &self.p1 else &self.p2;
    }
};

pub const Summary = extern struct {
    base: u16 = 0,
    damage: u16 = 0,

    comptime {
        assert(@sizeOf(Summary) == 4);
    }
};

/// TODO
pub const Calc = struct {
    /// TODO
    overrides: Actions = .{},
    /// TODO
    summaries: Summaries = .{},

    pub fn overridden(self: Calc, player: Player, comptime field: []const u8) ?TypeOf(field) {
        if (!enabled) return null;

        const val = @field(if (player == .P1) self.overrides.p1 else self.overrides.p2, field);
        return if (switch (@typeInfo(@TypeOf(val))) {
            .Enum => val != .None,
            .Int => val != 0,
            else => unreachable,
        }) val else null;
    }

    pub fn base(self: *Calc, player: Player, val: u16) void {
        if (!enabled) return;

        self.summaries.get(player).base = val;
    }

    pub fn damage(self: *Calc, player: Player, val: u16) void {
        if (!enabled) return;

        self.summaries.get(player).damage = val;
    }
};

pub const NULL = Null{};

const Null = struct {
    pub fn overridden(self: Null, player: Player, comptime field: []const u8) ?TypeOf(field) {
        _ = .{ self, player };
        return null;
    }

    pub fn base(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }

    pub fn damage(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }
};

fn TypeOf(comptime field: []const u8) type {
    for (@typeInfo(Action).Struct.fields) |f| if (std.mem.eql(u8, f.name, field)) return f.type;
    unreachable;
}
