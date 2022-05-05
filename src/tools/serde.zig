const std = @import("std");

const pkmn = @import("pkmn");

const gen1 = pkmn.gen1.helpers;
const rng = pkmn.rng;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) usageAndExit(args[0]);

    const gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
        errorAndExit("gen", args[1], args[0]);
    if (gen < 1 or gen > 8) errorAndExit("gen", args[1], args[0]);
    const seed = if (args.len > 2) std.fmt.parseUnsigned(u64, args[2], 10) catch
        errorAndExit("seed", args[2], args[0]) else null;

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    var battle = switch (gen) {
        1 => if (seed) |s| gen1.Battle.random(&rng.PRNG(6).init(s), false) else GEN1,
        else => unreachable,
    };

    try w.writeStruct(battle);
    try buf.flush();

    // print(battle);

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

const GEN1: pkmn.gen1.Battle(rng.Random(1)) = .{
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
                .disabled = .{ .move = 2, .duration = 4 },
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
                .transform = 0b0101,
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
    .rng = .{ .src = if (pkmn.showdown) .{ .seed = 0x31415926 } else .{
        .seed = .{ 114, 155, 42, 78, 253, 19, 117, 37, 253, 105 },
        .index = 8,
    } },
};

// DEBUG

const assert = std.debug.assert;

// https://en.wikipedia.org/wiki/ANSI_escape_code
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

const COMPACT = 8;
const Ais = AutoIndentingStream(std.fs.File.Writer);

pub fn elide(value: anytype) bool {
    return switch (@TypeOf(value)) {
        pkmn.gen1.MoveSlot => value.id != .None,
        pkmn.gen1.Pokemon => value.species != .None,
        else => return true,
    };
}

// Limited and lazy version of NodeJS's util.inspect
pub fn inspectN(value: anytype, ais: *Ais, max_depth: usize) !void {
    const T = @TypeOf(value);
    const options = std.fmt.FormatOptions{ .alignment = .Left };

    switch (@typeInfo(T)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float, .Bool => {
            try ais.writer().writeAll(YELLOW);
            try std.fmt.formatType(value, "any", options, ais.writer(), max_depth);
            try ais.writer().writeAll(RESET);
        },
        .Optional => {
            if (value) |payload| {
                try inspectN(payload, ais, max_depth);
            } else {
                try ais.writer().writeAll(BOLD);
                try std.fmt.formatBuf("null", options, ais.writer());
                try ais.writer().writeAll(RESET);
            }
        },
        .EnumLiteral => {
            const buffer = [_]u8{'.'} ++ @tagName(value);
            try ais.writer().writeAll(GREEN);
            try std.fmt.formatBuf(buffer, options, ais.writer());
            try ais.writer().writeAll(RESET);
        },
        .Null => {
            try ais.writer().writeAll(BOLD);
            try std.fmt.formatBuf("null", options, ais.writer());
            try ais.writer().writeAll(RESET);
        },
        .ErrorUnion => {
            if (value) |payload| {
                try inspectN(payload, ais, max_depth);
            } else |err| {
                try inspectN(err, ais, max_depth);
            }
        },
        .Type => {
            try ais.writer().writeAll(DIM);
            try std.fmt.formatBuf(@typeName(value), options, ais.writer());
            try ais.writer().writeAll(RESET);
        },
        .Enum => |enumInfo| {
            try ais.writer().writeAll(GREEN);
            // try ais.writer().writeAll(@typeName(T));
            if (enumInfo.is_exhaustive) {
                try ais.writer().writeAll(".");
                try ais.writer().writeAll(@tagName(value));
                try ais.writer().writeAll(RESET);
                return;
            }

            // Use @tagName only if value is one of known fields
            @setEvalBranchQuota(3 * enumInfo.fields.len);
            inline for (enumInfo.fields) |enumField| {
                if (@enumToInt(value) == enumField.value) {
                    try ais.writer().writeAll(".");
                    try ais.writer().writeAll(@tagName(value));
                    try ais.writer().writeAll(RESET);
                    return;
                }
            }

            try ais.writer().writeAll("(");
            try inspectN(@enumToInt(value), ais, max_depth);
            try ais.writer().writeAll(")");
            try ais.writer().writeAll(RESET);
        },
        .Union => |info| {
            try ais.writer().writeAll(DIM);
            try ais.writer().writeAll(@typeName(T));
            try ais.writer().writeAll(RESET);

            if (max_depth == 0) return ais.writer().writeAll(".{ ... }");
            if (info.tag_type) |UnionTagType| {
                try ais.writer().writeAll(".{ .");
                try ais.writer().writeAll(@tagName(@as(UnionTagType, value)));
                try ais.writer().writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try inspectN(@field(value, u_field.name), ais, max_depth - 1);
                    }
                }
                try ais.writer().writeAll(" }");
            } else {
                try std.fmt.format(ais.writer(), "@{x}", .{@ptrToInt(&value)});
            }
        },
        .Struct => |info| {
            if (info.is_tuple) {
                // Skip the type and field names when formatting tuples.
                if (max_depth == 0) return ais.writer().writeAll(".{ ... }");
                try ais.writer().writeAll(".{");
                inline for (info.fields) |f, i| {
                    if (i == 0) {
                        try ais.writer().writeAll(" ");
                    } else {
                        try ais.writer().writeAll(", ");
                    }
                    try inspectN(@field(value, f.name), ais, max_depth - 1);
                }
                return ais.writer().writeAll(" }");
            }

            try ais.writer().writeAll(DIM);
            try ais.writer().writeAll(@typeName(T));
            try ais.writer().writeAll(RESET);
            if (max_depth == 0) return ais.writer().writeAll(".{ ... }");

            const compact = if (info.fields.len > COMPACT) false else inline for (info.fields) |f| {
                if (!isPrimitive(f.field_type)) break false;
            } else true;

            if (compact) {
                try ais.writer().writeAll(".{ ");
            } else {
                try ais.writer().writeAll(".{");
                try ais.insertNewline();
                ais.pushIndent();
            }
            inline for (info.fields) |f, i| {
                if (f.default_value) |dv| {
                    // TODO: workaround for ziglang/zig#10766 removing anytype fields
                    const default_value = if (@hasField(@import("std").zig.Ast.Node.Tag, "anytype"))
                        dv
                    else
                        @ptrCast(*const f.field_type, @alignCast(@alignOf(f.field_type), dv)).*;
                    switch (@typeInfo(f.field_type)) {
                        .ComptimeInt, .Int, .ComptimeFloat, .Float, .Bool, .Optional, .ErrorUnion, .Enum => {
                            if (@field(value, f.name) != default_value) {
                                try ais.writer().writeAll(".");
                                try ais.writer().writeAll(f.name);
                                try ais.writer().writeAll(" = ");

                                try inspectN(@field(value, f.name), ais, max_depth - 1);
                                if (i < info.fields.len - 1) {
                                    try ais.writer().writeAll(",");
                                    if (compact) {
                                        try ais.writer().writeAll(" ");
                                    } else {
                                        try ais.insertNewline();
                                    }
                                }
                            }
                        },
                        else => {
                            try ais.writer().writeAll(".");
                            try ais.writer().writeAll(f.name);
                            try ais.writer().writeAll(" = ");

                            try inspectN(@field(value, f.name), ais, max_depth - 1);
                            if (i < info.fields.len - 1) {
                                try ais.writer().writeAll(",");
                                if (compact) {
                                    try ais.writer().writeAll(" ");
                                } else {
                                    try ais.insertNewline();
                                }
                            }
                        },
                    }
                } else {
                    try ais.writer().writeAll(".");
                    try ais.writer().writeAll(f.name);
                    try ais.writer().writeAll(" = ");

                    try inspectN(@field(value, f.name), ais, max_depth - 1);
                    if (i < info.fields.len - 1) {
                        try ais.writer().writeAll(",");
                        if (compact) {
                            try ais.writer().writeAll(" ");
                        } else {
                            try ais.insertNewline();
                        }
                    }
                }
            }
            if (compact) {
                try ais.writer().writeAll(" }");
            } else {
                ais.popIndent();
                try ais.insertNewline();
                try ais.writer().writeAll("}");
            }
        },
        .Array => |info| {
            if (max_depth == 0) return ais.writer().writeAll(".{ ... }");

            const compact = if (value.len > COMPACT) false else isPrimitive(info.child);

            if (compact) {
                try ais.writer().writeAll(".{ ");
            } else {
                try ais.writer().writeAll(".{");
                try ais.insertNewline();
                ais.pushIndent();
            }
            for (value) |elem, i| {
                if (!elide(elem)) continue;
                try inspectN(elem, ais, max_depth - 1);
                if (i < value.len - 1) {
                    try ais.writer().writeAll(",");
                    if (compact) {
                        try ais.writer().writeAll(" ");
                    } else {
                        try ais.insertNewline();
                    }
                }
            }
            if (compact) {
                try ais.writer().writeAll(" }");
            } else {
                ais.popIndent();
                try ais.insertNewline();
                try ais.writer().writeAll("}");
            }
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => |info| {
                    if (info.child == u8) {
                        try ais.writer().writeAll(GREEN);
                        try std.fmt.formatText(value, "s", options, ais.writer());
                        try ais.writer().writeAll(RESET);
                        return;
                    }
                    if (comptime std.meta.trait.isZigString(info.child)) {
                        for (value) |item, i| {
                            if (i != 0) try std.fmt.formatText(", ", "s", options, ais.writer());
                            try std.fmt.formatText(item, "s", options, ais.writer());
                        }
                        return;
                    }
                    @compileError("Unable to format '" ++ @typeName(T) ++ "'");
                },
                .Enum, .Union, .Struct => {
                    return inspectN(value.*, ais, max_depth);
                },
                else => return std.fmt.format(ais.writer(), "{s}@{x}", .{ @typeName(ptr_info.child), @ptrToInt(value) }),
            },
            .Many, .C => {
                if (ptr_info.sentinel) |_| {
                    return inspectN(std.mem.span(value), ais, max_depth);
                }
                if (ptr_info.child == u8) {
                    try ais.writer().writeAll(GREEN);
                    try std.fmt.formatText(std.mem.span(value), "s", options, ais.writer());
                    try ais.writer().writeAll(RESET);
                    return;
                }
                @compileError("Unable to format '" ++ @typeName(T) ++ "'");
            },
            .Slice => {
                if (max_depth == 0) return ais.writer().writeAll(".{ ... }");
                if (ptr_info.child == u8) {
                    try ais.writer().writeAll(GREEN);
                    try std.fmt.formatText(value, "s", options, ais.writer());
                    try ais.writer().writeAll(RESET);
                    return;
                }
                // TODO compact
                try ais.writer().writeAll(".{ ");
                for (value) |elem, i| {
                    try inspectN(elem, ais, max_depth - 1);
                    if (i != value.len - 1) {
                        try ais.writer().writeAll(", ");
                    }
                }
                try ais.writer().writeAll(" }");
            },
        },
        else => @compileError("Unable to format type '" ++ @typeName(T) ++ "'"),
        // else => {
        //     try std.fmt.formatType(value, "any", options, ais.writer(), max_depth);
        // },
    }
}

pub fn inspect(value: anytype, writer: anytype) @TypeOf(writer).Error!void {
    const ais = &Ais{
        .indent_delta = 4,
        .underlying_writer = writer,
    };
    try inspectN(value, ais, 10);
}

pub fn print(value: anytype) void {
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeByte('\n') catch return;
    nosuspend inspect(value, stderr) catch return;
    // nosuspend stderr.writeByte('\n') catch return;
}

fn isPrimitive(comptime t: type) bool {
    return switch (@typeInfo(t)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float, .Bool, .Optional, .ErrorUnion, .Enum => true,
        else => false,
    };
}

// Stripped down version oflin/ std/zig/render.zig's AutoIndentingStream
fn AutoIndentingStream(comptime UnderlyingWriter: type) type {
    return struct {
        const Self = @This();
        pub const WriteError = UnderlyingWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriteError, write);

        underlying_writer: UnderlyingWriter,

        indent_count: usize = 0,
        indent_delta: usize,
        current_line_empty: bool = true,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return @as(usize, 0);
            try self.applyIndent();
            return self.writeNoIndent(bytes);
        }

        fn writeNoIndent(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return @as(usize, 0);
            try self.underlying_writer.writeAll(bytes);
            if (bytes[bytes.len - 1] == '\n') self.resetLine();
            return bytes.len;
        }

        pub fn insertNewline(self: *Self) WriteError!void {
            _ = try self.writeNoIndent("\n");
        }

        fn resetLine(self: *Self) void {
            self.current_line_empty = true;
        }

        pub fn pushIndent(self: *Self) void {
            self.indent_count += 1;
        }

        pub fn popIndent(self: *Self) void {
            assert(self.indent_count != 0);
            self.indent_count -= 1;
        }

        fn applyIndent(self: *Self) WriteError!void {
            const current_indent = self.currentIndent();
            if (self.current_line_empty and current_indent > 0) {
                try self.underlying_writer.writeByteNTimes(' ', current_indent);
            }

            self.current_line_empty = false;
        }

        fn currentIndent(self: *Self) usize {
            var indent_current: usize = 0;
            if (self.indent_count > 0) indent_current = self.indent_count * self.indent_delta;
            return indent_current;
        }
    };
}
