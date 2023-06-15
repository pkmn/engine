const std = @import("std");

const pkmn = @import("../pkmn.zig");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const protocol = @import("../common/protocol.zig");
const rational = @import("../common/rational.zig");

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

const Actions = chance.Actions;
const Action = chance.Action;
const Chance = chance.Chance;

const Rolls = helpers.Rolls;

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
    damage: Damage = .{},

    pub const Damage = extern struct {
        base: u16 = 0,
        final: u16 = 0,

        comptime {
            assert(@sizeOf(Damage) == 4);
        }
    };

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

        self.summaries.get(player).damage.base = val;
    }

    pub fn final(self: *Calc, player: Player, val: u16) void {
        if (!enabled) return;

        self.summaries.get(player).damage.final = val;
    }
};

/// Null object pattern implementation of `Calc` which does nothing, though damage calculator
/// support should additionally be turned off entirely via `options.calc`.
pub const NULL = Null{};

const Null = struct {
    pub fn overridden(self: Null, player: Player, comptime field: []const u8) ?TypeOf(field) {
        _ = .{ self, player };
        return null;
    }

    pub fn base(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }

    pub fn final(self: Null, player: Player, val: u16) void {
        _ = .{ self, player, val };
    }
};

fn TypeOf(comptime field: []const u8) type {
    for (@typeInfo(Action).Struct.fields) |f| if (std.mem.eql(u8, f.name, field)) return f.type;
    unreachable;
}

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
    seed: u64,
    allocator: std.mem.Allocator,
) !Stats {
    var stats: Stats = .{};

    const Set = std.AutoHashMap(Actions, void);
    var seen = Set.init(allocator);
    defer seen.deinit();
    var frontier = std.ArrayList(Actions).init(allocator);
    defer frontier.deinit();

    var opts = pkmn.battle.options(
        protocol.NULL,
        Chance(Rational(u128)){ .probability = .{}, .actions = actions },
        Calc{},
    );

    var b = battle;
    _ = try b.update(c1, c2, &opts);

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
        var a = Actions{ .p1 = .{ .metronome = p1_move }, .p2 = .{ .metronome = p2_move } };

        for (Rolls.speedTie(template.p1)) |tie| { a.p1.speed_tie = tie; a.p2.speed_tie = tie;
        for (Rolls.confused(template.p1)) |p1_cfz| { a.p1.confused = p1_cfz;
        for (Rolls.confused(template.p2)) |p2_cfz| { a.p2.confused = p2_cfz;
        for (Rolls.paralyzed(template.p1, p1_cfz)) |p1_par| { a.p1.paralyzed = p1_par;
        for (Rolls.paralyzed(template.p2, p2_cfz)) |p2_par| { a.p2.paralyzed = p2_par;
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
                opts.chance = .{ .probability = .{} };
                const q = &opts.chance.probability;

                b = battle;
                _ = try b.update(c1, c2, &opts);
                stats.updates += 1;

                // const p1_max = @intCast(u8, p1_dmg.min);
                // const p2_max = @intCast(u8, p2_dmg.min);
                const p1_max = if (p1_min != 0) p1_min
                    else try Rolls.coalesce(.P1, @intCast(u8, p1_dmg.min), &opts.calc.summaries);
                const p2_max =
                    try Rolls.coalesce(.P2, @intCast(u8, p2_dmg.min), &opts.calc.summaries);

                if (opts.chance.actions.matches(template)) {
                    if (!opts.chance.actions.eql(a)) continue;

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
                } else if (!matches(opts.chance.actions, i, frontier.items)) {
                    try frontier.append(opts.chance.actions);
                }

                p1_min = p1_max;
                p2_dmg.min = p2_max;
            }

            assert(p1_min > 0 or p1_dmg.min == 0);
            p1_dmg.min = p1_min;

        }}}}}}}}}}}}}}}}}}
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

fn matches(actions: Actions, i: usize, frontier: []Actions) bool {
    for (frontier, 0..) |f, j| {
        // TODO: is skipping this redundant check worth it?
        if (i == j) continue;
        if (f.matches(actions)) return true;
    }
    return false;
}
