const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rational = @import("../common/rational.zig");
const util = @import("../common/util.zig");

const chance = @import("chance.zig");
const data = @import("data.zig");
const helpers = @import("helpers.zig");

const assert = std.debug.assert;
const print = std.debug.print;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const enabled = pkmn.options.calc;

const Player = common.Player;
const Result = common.Result;
const Choice = common.Choice;

const Rational = rational.Rational;

const PointerType = util.PointerType;
const FieldType = util.FieldType;

const Actions = chance.Actions;
const Action = chance.Action;
const Chance = chance.Chance;

const Rolls = helpers.Rolls;

/// Information relevant to damage calculation that occured during a Generation I battle `update`.
pub const Summaries = extern struct {
    /// Relevant information for Player 1.
    p1: Summary = .{},
    /// Relevant information for Player 2.
    p2: Summary = .{},

    comptime {
        assert(@sizeOf(Summaries) == 12);
    }

    /// Returns the `Summary` for the given `player`.
    pub inline fn get(self: anytype, player: Player) PointerType(@TypeOf(self), Summary) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == Summaries);
        return if (player == .P1) &self.p1 else &self.p2;
    }
};

/// Information relevant to damage calculation that occured during a Generation I battle `update`
/// for a single player.
pub const Summary = extern struct {
    /// The computed raw damage values.
    damage: Damage = .{},

    /// Intermediate raw damage values computed during a calculation.
    pub const Damage = extern struct {
        /// The base computed damage before the damage roll is applied.
        base: u16 = 0,
        /// The final computed damage that gets applied to the Pokémon. May exceed the target's HP
        // (to determine the *actual* damage done compare the target's stored HP before and after).
        final: u16 = 0,
        /// Whether higher damage will saturate / result in the same outcome (e.g. additional damage
        /// gets ignored due to it already breaking a Substitute or causing the target to faint).
        capped: bool = false,

        _: u8 = 0,

        comptime {
            assert(@sizeOf(Damage) == 6);
        }
    };

    comptime {
        assert(@sizeOf(Summary) == 6);
    }
};

/// Allows for forcing the value of specific RNG events during a Generation I battle `update` via
/// `overrides` and tracks `summaries` of information relevant to damage calculation.
pub const Calc = struct {
    /// Overrides the normal behavior of the RNG during an `update` to force specific outcomes.
    overrides: Actions = .{},
    /// Information relevant to damage calculation.
    summaries: Summaries = .{},

    pub fn overridden(
        self: Calc,
        player: Player,
        comptime field: Action.Field,
    ) ?std.meta.FieldType(Action, field) {
        if (!enabled) return null;

        const overrides = if (player == .P1) self.overrides.p1 else self.overrides.p2;
        const val = @field(overrides, @tagName(field));
        return if (switch (@typeInfo(@TypeOf(val))) {
            .Enum => val != .None,
            .Int => val != 0,
            else => unreachable,
        }) val else null;
    }

    pub fn base(self: *Calc, player: Player, val: u16) void {
        if (!enabled) return;

        self.summaries.get(player).damage.base = val;
    }

    pub fn final(self: *Calc, player: Player, val: u16) void {
        if (!enabled) return;

        self.summaries.get(player).damage.final = val;
    }

    pub fn capped(self: *Calc, player: Player) void {
        if (!enabled) return;

        self.summaries.get(player).damage.capped = true;
    }
};

/// Null object pattern implementation of Generation I `Calc` which does nothing, though damage
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

    pub fn base(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }

    pub fn final(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }

    pub fn capped(self: Null, player: Player) void {
        _ = .{ self, player };
    }
};

pub const Stats = struct {
    frontier: usize = 0,
    updates: usize = 0,
    seen: usize = 0,
    saved: usize = 0,
};

pub fn transitions(
    battle: anytype,
    c1: Choice,
    c2: Choice,
    actions: Actions,
    cap: bool,
    seed: u64,
    allocator: std.mem.Allocator,
    writer: anytype,
) !Stats {
    var stats: Stats = .{};

    var seen = std.AutoHashMap(Actions, void).init(allocator);
    defer seen.deinit();
    var frontier = std.ArrayList(Actions).init(allocator);
    defer frontier.deinit();

    var opts = pkmn.battle.options(
        protocol.NULL,
        Chance(Rational(u128)){ .probability = .{}, .actions = actions },
        Calc{ .overrides = actions },
    );

    var b = battle;
    _ = try b.update(c1, c2, &opts);
    stats.updates += 1;

    var p1 = b.side(.P1);
    var p2 = b.side(.P2);

    var p: Rational(u128) = .{ .p = 0, .q = 1 };
    try frontier.append(opts.chance.actions);

    // zig fmt: off
    for (Rolls.metronome(frontier.items[0].p1)) |p1_move| {
    for (Rolls.metronome(frontier.items[0].p2)) |p2_move| {

    var i: usize = 0;
    assert(frontier.items.len == 1);
    while (i < frontier.items.len) : (i += 1) {
        var template = frontier.items[i];

        try debug(writer, template, true, .{ .color = i, .bold = true, .background = true });

        var a = Actions{ .p1 = .{ .metronome = p1_move }, .p2 = .{ .metronome = p2_move } };

        for (Rolls.speedTie(template.p1)) |tie| { a.p1.speed_tie = tie; a.p2.speed_tie = tie;
        for (Rolls.sleep(template.p1)) |p1_slp| { a.p1.sleep = p1_slp;
        for (Rolls.sleep(template.p2)) |p2_slp| { a.p2.sleep = p2_slp;
        for (Rolls.disable(template.p1, p1_slp)) |p1_dis| { a.p1.disable = p1_dis;
        for (Rolls.disable(template.p2, p2_slp)) |p2_dis| { a.p2.disable = p2_dis;
        for (Rolls.confusion(template.p1, p1_slp)) |p1_cfz| { a.p1.confusion = p1_cfz;
        for (Rolls.confusion(template.p2, p1_slp)) |p2_cfz| { a.p2.confusion = p2_cfz;
        for (Rolls.confused(template.p1, p1_cfz)) |p1_cfzd| { a.p1.confused = p1_cfzd;
        for (Rolls.confused(template.p2, p2_cfz)) |p2_cfzd| { a.p2.confused = p2_cfzd;
        for (Rolls.paralyzed(template.p1, p1_cfzd)) |p1_par| { a.p1.paralyzed = p1_par;
        for (Rolls.paralyzed(template.p2, p2_cfzd)) |p2_par| { a.p2.paralyzed = p2_par;
        for (Rolls.attacking(template.p1, p1_par)) |p1_atk| { a.p1.attacking = p1_atk;
        for (Rolls.attacking(template.p2, p2_par)) |p2_atk| { a.p2.attacking = p2_atk;
        for (Rolls.binding(template.p1, p1_par)) |p1_bind| { a.p1.binding = p1_bind;
        for (Rolls.binding(template.p2, p2_par)) |p2_bind| { a.p2.binding = p2_bind;
        for (Rolls.duration(template.p1, p1_par)) |p1_dur| { a.p1.duration = p1_dur;
        for (Rolls.duration(template.p2, p2_par)) |p2_dur| { a.p2.duration = p2_dur;
        for (Rolls.hit(template.p1, p1_par)) |p1_hit| { a.p1.hit = p1_hit;
        for (Rolls.hit(template.p2, p2_par)) |p2_hit| { a.p2.hit = p2_hit;
        for (Rolls.psywave(template.p1, p1, p1_hit)) |p1_psywave| { a.p1.psywave = p1_psywave;
        for (Rolls.psywave(template.p2, p2, p2_hit)) |p2_psywave| { a.p2.psywave = p2_psywave;
        for (Rolls.moveSlot(template.p1, p1_hit)) |p1_slot| { a.p1.move_slot = p1_slot;
        for (Rolls.moveSlot(template.p2, p2_hit)) |p2_slot| { a.p2.move_slot = p2_slot;
        for (Rolls.multiHit(template.p1, p1_hit)) |p1_multi| { a.p1.multi_hit = p1_multi;
        for (Rolls.multiHit(template.p2, p1_hit)) |p2_multi| { a.p2.multi_hit = p2_multi;
        for (Rolls.secondaryChance(template.p1, p1_hit)) |p1_sec| { a.p1.secondary_chance = p1_sec;
        for (Rolls.secondaryChance(template.p2, p2_hit)) |p2_sec| { a.p2.secondary_chance = p2_sec;
        for (Rolls.criticalHit(template.p1, p1_hit)) |p1_crit| { a.p1.critical_hit = p1_crit;
        for (Rolls.criticalHit(template.p2, p2_hit)) |p2_crit| { a.p2.critical_hit = p2_crit;

        var p1_dmg = Rolls.damage(template.p1, p1_hit);
        while (p1_dmg.min < p1_dmg.max) : (p1_dmg.min += 1) {
            a.p1.damage = @intCast(u8, p1_dmg.min);
            var p1_min: u8 = 0;

            var p2_dmg = Rolls.damage(template.p2, p2_hit);
            while (p2_dmg.min < p2_dmg.max) : (p2_dmg.min += 1) {
                a.p2.damage = @intCast(u8, p2_dmg.min);

                opts.calc = .{ .overrides = a };
                opts.chance = .{ .probability = .{}, .actions = actions };
                const q = &opts.chance.probability;

                b = battle;
                _ = try b.update(c1, c2, &opts);
                stats.updates += 1;

                // const p1_max = @intCast(u8, p1_dmg.min);
                // const p2_max = @intCast(u8, p2_dmg.min);
                // _ = cap;

                var p1_max = if (p1_min != 0) p1_min else
                    try Rolls.coalesce(.P1, @intCast(u8, p1_dmg.min), &opts.calc.summaries, cap);
                var p2_max =
                    try Rolls.coalesce(.P2, @intCast(u8, p2_dmg.min), &opts.calc.summaries, cap);

                if (opts.chance.actions.matches(template)) {
                    if (!opts.chance.actions.eql(a)) {
                        try debug(writer, opts.chance.actions, false, .{ .color = i, .dim = true });

                        p1_min = p1_max;
                        p2_dmg.min = p2_max;
                        continue;
                    }

                    try debug(writer, opts.chance.actions, false, .{ .color = i });

                    for (p1_dmg.min..@as(u9, p1_max) + 1) |p1d| {
                        for (p2_dmg.min..@as(u9, p2_max) + 1) |p2d| {
                            var acts = opts.chance.actions;
                            acts.p1.damage = @intCast(u8, p1d);
                            acts.p2.damage = @intCast(u8, p2d);
                            if ((try seen.getOrPut(acts)).found_existing) {
                                print("already seen {} (seed: {d})\n", .{ acts, seed });
                                return error.TestUnexpectedResult;
                            }
                        }
                    }

                    if (p1_max != p1_dmg.min) try q.update(p1_max - p1_dmg.min + 1, 1);
                    if (p2_max != p2_dmg.min) try q.update(p2_max - p2_dmg.min + 1, 1);
                    try p.add(q);
                    stats.saved += 1;

                    if (p.q < p.p) {
                        print("improper fraction {} (seed: {d})\n", .{ p, seed });
                        return error.TestUnexpectedResult;
                    }

                    p1_min = p1_max;
                    p2_dmg.min = p2_max;
                    continue;
                }

                try debug(writer, opts.chance.actions, false, .{ .dim = true });

                if (!matches(opts.chance.actions, i, frontier.items)) {
                    try frontier.append(opts.chance.actions);

                    try debug(writer, opts.chance.actions, true, .{
                        .color = frontier.items.len,
                        .dim = true,
                        .background = true
                    });
                }

                p1_min = p1_max;
                p2_dmg.min = p2_max;
            }

            assert(p1_min > 0 or p1_dmg.min == 0);
            p1_dmg.min = p1_min;

        }}}}}}}}}}}}}}}}}}}}}}}}}}}}}}
    }

    assert(frontier.items.len == i);
    stats.frontier = @max(stats.frontier, i);
    frontier.shrinkRetainingCapacity(1);

    }}
    // zig fmt: on

    stats.seen = seen.count();

    p.reduce();
    if (p.p != 1 or p.q != 1) {
        print("expected 1, found {} (seed: {d})\n", .{ p, seed });
        return error.TestExpectedEqual;
    }

    return stats;
}

inline fn matches(actions: Actions, i: usize, frontier: []Actions) bool {
    for (frontier, 0..) |f, j| {
        // TODO: is skipping this redundant check worth it?
        if (i == j) continue;
        if (f.matches(actions)) return true;
    }
    return false;
}

const Style = struct {
    color: ?usize = null,
    bold: bool = false,
    background: bool = false,
    dim: bool = false,
};

fn debug(writer: anytype, actions: Actions, shape: bool, style: Style) !void {
    _ = .{ writer, actions, shape, style };
    // const mod: usize = if (style.dim) 2 else 1;
    // const background: usize = if (style.background) 4 else 3;
    // const color: usize = if (style.color) |c| (c % 6) + 1 else 7;
    // if (style.dim or style.bold) try writer.print("\x1b[{d}m", .{mod});
    // try writer.print("\x1b[{d}{d}m", .{ background, color });
    // try actions.fmt(writer, shape);
    // try writer.writeAll("\x1b[0m\n");
    // DEBUG
    // if (style.dim) try writer.writeAll("    ");
    // try actions.fmt(writer, shape);
    // try writer.writeByte('\n');
}
