const std = @import("std");

const pkmn = @import("pkmn");

const gen1 = pkmn.gen1.helpers;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) usageAndExit(args[0]);

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0]);
    if (gen < 1 or gen > 9) errorAndExit("gen", args[1], args[0]);
    const seed = if (args.len > 2) std.fmt.parseUnsigned(u64, args[2], 10) catch
        errorAndExit("seed", args[2], args[0]) else null;

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    var prng = if (seed) |s| pkmn.PSRNG.init(s) else null;
    var battle = switch (gen) {
        1 => if (prng) |*p| gen1.Battle.random(p, .{}) else GEN1,
        else => unreachable,
    };

    try w.writeStruct(battle);
    try buf.flush();

    const serialized = std.mem.toBytes(battle);
    const deserialized = std.mem.bytesToValue(@TypeOf(battle), &serialized);
    try std.testing.expectEqual(battle, deserialized);
}

fn errorAndExit(msg: []const u8, arg: []const u8, cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Invalid {s}: {s}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd);
}

fn usageAndExit(cmd: []const u8) noreturn {
    const err = std.io.getStdErr().writer();
    err.print("Usage: {s} <GEN> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}

const GEN1: pkmn.gen1.Battle(pkmn.gen1.PRNG) = .{
    .sides = .{ .{
        .pokemon = .{ .{
            .stats = .{ .hp = 233, .atk = 98, .def = 108, .spe = 128, .spc = 76 },
            .moves = .{
                .{ .id = .SonicBoom, .pp = 10 },
                .{ .id = .Constrict, .pp = 24 },
                .{ .id = .Clamp, .pp = 10 },
                .{ .id = .HornDrill, .pp = 7 },
            },
            .hp = 208,
            .status = 8,
            .species = .Caterpie,
            .types = .{ .type1 = .Bug, .type2 = .Bug },
        }, .{
            .stats = .{ .hp = 217, .atk = 252, .def = 118, .spe = 186, .spc = 82 },
            .moves = .{
                .{ .id = .Stomp, .pp = 9 },
                .{ .id = .PoisonSting, .pp = 55 },
                .{ .id = .Bite, .pp = 22 },
                .{ .id = .Bind, .pp = 10 },
            },
            .hp = 68,
            .species = .Hitmonlee,
            .types = .{ .type1 = .Fighting, .type2 = .Fighting },
        }, .{
            .stats = .{ .hp = 231, .atk = 134, .def = 168, .spe = 124, .spc = 138 },
            .moves = .{
                .{ .id = .Flamethrower, .pp = 0 },
                .{ .id = .Disable, .pp = 2 },
                .{ .id = .SpikeCannon, .pp = 4 },
                .{ .id = .SuperFang, .pp = 0 },
            },
            .hp = 21,
            .status = 133,
            .species = .Squirtle,
            .types = .{ .type1 = .Water, .type2 = .Water },
        }, .{
            .stats = .{ .hp = 273, .atk = 158, .def = 178, .spe = 118, .spc = 188 },
            .moves = .{
                .{ .id = .PinMissile, .pp = 16 },
                .{ .id = .Growl, .pp = 40 },
                .{ .id = .MirrorMove, .pp = 22 },
                .{ .id = .BoneClub, .pp = 4 },
            },
            .hp = 81,
            .species = .Porygon,
            .types = .{ .type1 = .Normal, .type2 = .Normal },
        }, .{
            .stats = .{ .hp = 335, .atk = 230, .def = 230, .spe = 230, .spc = 230 },
            .moves = .{
                .{ .id = .TriAttack, .pp = 9 },
                .{ .id = .Kinesis, .pp = 0 },
                .{ .id = .JumpKick, .pp = 15 },
                .{ .id = .PoisonSting, .pp = 13 },
            },
            .hp = 114,
            .species = .Mew,
            .types = .{ .type1 = .Psychic, .type2 = .Psychic },
        }, .{
            .stats = .{ .hp = 462, .atk = 258, .def = 168, .spe = 98, .spc = 168 },
            .moves = .{
                .{ .id = .SonicBoom, .pp = 5 },
                .{ .id = .PoisonPowder, .pp = 3 },
                .{ .id = .Bide, .pp = 2 },
                .{ .id = .Headbutt, .pp = 8 },
            },
            .hp = 135,
            .status = 2,
            .species = .Snorlax,
            .types = .{ .type1 = .Normal, .type2 = .Normal },
        } },
        .active = .{
            .stats = .{ .hp = 233, .atk = 98, .def = 108, .spe = 128, .spc = 76 },
            .species = .Caterpie,
            .types = .{ .type1 = .Bug, .type2 = .Bug },
            .boosts = .{ .spc = -2 },
            .volatiles = .{
                .Thrashing = true,
                .Confusion = true,
                .Substitute = true,
                .LightScreen = true,
                .attacks = 3,
                .state = 235,
                .substitute = 42,
                .disabled_duration = 4,
                .disabled_move = 2,
                .confusion = 2,
                .toxic = 4,
            },
            .moves = .{
                .{ .id = .SonicBoom, .pp = 10 },
                .{ .id = .Constrict, .pp = 24 },
                .{ .id = .Clamp, .pp = 10 },
                .{ .id = .HornDrill, .pp = 7 },
            },
        },
        .order = .{ 1, 3, 2, 4, 5, 6 },
        .last_selected_move = .JumpKick,
        .last_used_move = .SpikeCannon,
    }, .{
        .pokemon = .{ .{
            .stats = .{ .hp = 281, .atk = 256, .def = 196, .spe = 246, .spc = 146 },
            .moves = .{
                .{ .id = .Blizzard, .pp = 1 },
                .{ .id = .Bind, .pp = 26 },
                .{ .id = .DoubleEdge, .pp = 5 },
                .{ .id = .Strength, .pp = 9 },
            },
            .hp = 230,
            .species = .Scyther,
            .types = .{ .type1 = .Bug, .type2 = .Flying },
        }, .{
            .stats = .{ .hp = 289, .atk = 190, .def = 188, .spe = 238, .spc = 238 },
            .moves = .{
                .{ .id = .HighJumpKick, .pp = 9 },
                .{ .id = .NightShade, .pp = 5 },
                .{ .id = .HyperFang, .pp = 4 },
                .{ .id = .TakeDown, .pp = 26 },
            },
            .hp = 125,
            .species = .Ninetales,
            .types = .{ .type1 = .Fire, .type2 = .Fire },
        }, .{
            .stats = .{ .hp = 277, .atk = 222, .def = 242, .spe = 152, .spc = 132 },
            .moves = .{
                .{ .id = .ThunderWave, .pp = 1 },
                .{ .id = .FuryAttack, .pp = 17 },
                .{ .id = .StringShot, .pp = 52 },
                .{ .id = .WingAttack, .pp = 30 },
            },
            .hp = 23,
            .species = .Sandslash,
            .types = .{ .type1 = .Ground, .type2 = .Ground },
        }, .{
            .stats = .{ .hp = 261, .atk = 146, .def = 136, .spe = 126, .spc = 116 },
            .moves = .{
                .{ .id = .DefenseCurl, .pp = 45 },
                .{ .id = .PoisonGas, .pp = 39 },
                .{ .id = .DrillPeck, .pp = 26 },
                .{ .id = .Thunderbolt, .pp = 22 },
            },
            .hp = 133,
            .species = .Venonat,
            .types = .{ .type1 = .Bug, .type2 = .Poison },
        }, .{
            .stats = .{ .hp = 233, .atk = 138, .def = 148, .spe = 98, .spc = 188 },
            .moves = .{
                .{ .id = .SeismicToss, .pp = 11 },
                .{ .id = .DragonRage, .pp = 1 },
                .{ .id = .HornAttack, .pp = 6 },
                .{ .id = .FirePunch, .pp = 11 },
            },
            .hp = 193,
            .status = 2,
            .species = .Oddish,
            .types = .{ .type1 = .Grass, .type2 = .Poison },
        }, .{
            .stats = .{ .hp = 223, .atk = 140, .def = 106, .spe = 126, .spc = 106 },
            .moves = .{
                .{ .id = .EggBomb, .pp = 6 },
                .{ .id = .VineWhip, .pp = 0 },
                .{ .id = .Struggle, .pp = 5 },
                .{ .id = .IcePunch, .pp = 10 },
            },
            .hp = 130,
            .species = .NidoranM,
            .types = .{ .type1 = .Poison, .type2 = .Poison },
        } },
        .active = .{
            .stats = .{ .hp = 281, .atk = 134, .def = 168, .spe = 124, .spc = 138 },
            .species = .Squirtle,
            .types = .{ .type1 = .Water, .type2 = .Water },
            .volatiles = .{
                .Bide = true,
                .Trapping = true,
                .Transform = true,
                .attacks = 2,
                .state = 100,
                .transform = 0b0011,
            },
            .moves = .{
                .{ .id = .Flamethrower, .pp = 5 },
                .{ .id = .Disable, .pp = 5 },
                .{ .id = .SpikeCannon, .pp = 5 },
                .{ .id = .SuperFang, .pp = 5 },
            },
        },
        .order = .{ 1, 2, 3, 4, 5, 6 },
        .last_selected_move = .DrillPeck,
        .last_used_move = .EggBomb,
    } },
    .turn = 609,
    .last_damage = 84,
    .last_selected_indexes = .{ .p1 = 2, .p2 = 1 },
    .rng = .{ .src = if (pkmn.options.showdown) .{ .seed = 0x31415926 } else .{
        .seed = .{ 114, 155, 42, 78, 253, 19, 117, 37, 253, 105 },
        .index = 8,
    } },
};
