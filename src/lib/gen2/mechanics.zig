const std = @import("std");

const common = @import("../common/data.zig");
const DEBUG = @import("../common/debug.zig").print;
const options = @import("../common/options.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");

const data = @import("data.zig");

const assert = std.debug.assert;

const expectEqual = std.testing.expectEqual;

const Choice = common.Choice;
const ID = common.ID;
const Player = common.Player;
const Result = common.Result;

const showdown = options.showdown;

const Damage = protocol.Damage;
const Heal = protocol.Heal;

const Gen12 = rng.Gen12;

const ActivePokemon = data.ActivePokemon;
const Effectiveness = data.Effectiveness;
const Move = data.Move;
const MoveSlot = data.MoveSlot;
const Pokemon = data.Pokemon;
const Side = data.Side;
const Species = data.Species;
const Stats = data.Stats;
const Status = data.Status;

pub fn update(battle: anytype, c1: Choice, c2: Choice, options: anytype) !Result {
    _ = battle;
    _ = c1;
    _ = c2;
    _ = options;

    return Result.Default;
}

pub fn choices(battle: anytype, player: Player, request: Choice.Type, out: []Choice) u8 {
    _ = battle;
    _ = player;
    _ = request;
    _ = out;

    return 0;
}
