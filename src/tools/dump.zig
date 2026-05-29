const pkmn = @import("pkmn");
const std = @import("std");

const protocol = pkmn.protocol;

pub const pkmn_options = pkmn.Options{ .internal = true };

const Tool = enum {
    markdown,
    protocol,
    layout,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len != 2) usageAndExit(init.io, args[0]);

    var tool: Tool = undefined;
    if (std.mem.eql(u8, args[1], "markdown")) {
        tool = .markdown;
    } else if (std.mem.eql(u8, args[1], "protocol")) {
        tool = .protocol;
    } else if (std.mem.eql(u8, args[1], "layout")) {
        tool = .layout;
    } else {
        usageAndExit(init.io, args[0]);
    }

    var stdout = std.Io.File.stdout().writer(init.io, try allocator.alloc(u8, 4096));
    var w = &stdout.interface;

    switch (tool) {
        .markdown => {
            inline for (if (@hasField(@TypeOf(@typeInfo(protocol).@"struct"), "decls"))
                @typeInfo(protocol).@"struct".decls
            else
                @typeInfo(protocol).@"struct".decl_names) |decl|
            {
                const decl_name = if (@hasField(@TypeOf(decl), "name")) decl.name else decl;
                if (@TypeOf(@field(protocol, decl_name)) == type) {
                    switch (@typeInfo(@field(protocol, decl_name))) {
                        .@"enum" => |e| {
                            try w.print(
                                "## {s}\n\n<details><summary>Reason</summary>\n",
                                .{decl_name},
                            );
                            try w.writeAll("\n|Raw|Description|\n|--|--|\n");
                            if (@hasField(@TypeOf(e), "fields")) {
                                inline for (e.fields) |field| {
                                    try w.print(
                                        "|`0x{X:0>2}`|`{s}`|\n",
                                        .{ field.value, field.name },
                                    );
                                }
                            } else {
                                inline for (e.field_names, 0..) |name, i| {
                                    try w.print(
                                        "|`0x{X:0>2}`|`{s}`|\n",
                                        .{ e.field_values[i], name },
                                    );
                                }
                            }
                            try w.writeAll("</details>\n\n");
                        },
                        else => {},
                    }
                }
            }
        },
        .protocol => {
            var outer = false;
            try w.writeAll("{\n");
            inline for (if (@hasField(@TypeOf(@typeInfo(protocol).@"struct"), "decls"))
                @typeInfo(protocol).@"struct".decls
            else
                @typeInfo(protocol).@"struct".decl_names) |decl|
            {
                const decl_name = if (@hasField(@TypeOf(decl), "name")) decl.name else decl;
                if (@TypeOf(@field(protocol, decl_name)) == type) {
                    if (comptime std.mem.eql(u8, decl_name, "Kind")) continue;
                    switch (@typeInfo(@field(protocol, decl_name))) {
                        .@"enum" => |e| {
                            if (outer) try w.writeAll(",\n");
                            try w.print("  \"{s}\": [\n", .{decl_name});
                            var inner = false;
                            if (@hasField(@TypeOf(e), "fields")) {
                                inline for (e.fields) |field| {
                                    if (inner) try w.writeAll(",\n");
                                    // TODO: ziglang/zig#18888
                                    @setEvalBranchQuota(2018);
                                    try w.print("    {{\"val\": {d}, \"name\": \"{s}\"}}", .{
                                        field.value,
                                        field.name,
                                    });
                                    inner = true;
                                }
                            } else {
                                inline for (e.field_names, 0..) |name, i| {
                                    if (inner) try w.writeAll(",\n");
                                    // TODO: ziglang/zig#18888
                                    @setEvalBranchQuota(2018);
                                    try w.print("    {{\"val\": {d}, \"name\": \"{s}\"}}", .{
                                        e.field_values[i],
                                        name,
                                    });
                                    inner = true;
                                }
                            }

                            try w.writeAll("\n  ]");
                            outer = true;
                        },
                        else => {},
                    }
                }
            }
            try w.writeAll("\n}\n");
        },
        .layout => {
            try w.writeAll("[\n");
            {
                try w.writeAll("  {\n    \"sizes\": {\n");
                {
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "Battle", @sizeOf(pkmn.gen1.Battle(pkmn.gen1.PRNG)) },
                    );
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "Side", @sizeOf(pkmn.gen1.Side) },
                    );
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "Pokemon", @sizeOf(pkmn.gen1.Pokemon) },
                    );
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "ActivePokemon", @sizeOf(pkmn.gen1.ActivePokemon) },
                    );
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "Actions", @sizeOf(pkmn.gen1.chance.Actions) },
                    );
                    try w.print(
                        "      \"{s}\": {d},\n",
                        .{ "Durations", @sizeOf(pkmn.gen1.chance.Durations) },
                    );
                    try w.print(
                        "      \"{s}\": {d}\n",
                        .{ "Summaries", @sizeOf(pkmn.gen1.calc.Summaries) },
                    );
                }
                try w.writeAll("    },\n");
                try w.writeAll("    \"offsets\": {\n");
                {
                    try print(w, "Battle", pkmn.gen1.Battle(pkmn.gen1.PRNG), false);
                    try w.writeAll(",\n");
                    try print(w, "Side", pkmn.gen1.Side, false);
                    try w.writeAll(",\n");
                    try print(w, "Pokemon", pkmn.gen1.Pokemon, false);
                    try w.writeAll(",\n");
                    try print(w, "ActivePokemon", pkmn.gen1.ActivePokemon, false);
                    try w.writeAll(",\n");
                    try print(w, "Stats", pkmn.gen1.Stats(u16), false);
                    try w.writeAll(",\n");
                    try print(w, "Boosts", pkmn.gen1.Boosts, true);
                    try w.writeAll(",\n");
                    try print(w, "Volatiles", pkmn.gen1.Volatiles, true);
                    try w.writeAll(",\n");
                    try print(w, "Action", pkmn.gen1.chance.Action, true);
                    try w.writeAll(",\n");
                    try print(w, "Duration", pkmn.gen1.chance.Duration, true);
                    try w.writeAll(",\n");
                    try print(w, "Damage", pkmn.gen1.calc.Summary.Damage, false);
                    try w.writeAll("\n    }\n");
                }
                try w.writeAll("  }\n");
            }
            try w.writeAll("]\n");
        },
    }

    try w.flush();
}

fn print(w: anytype, name: []const u8, comptime T: type, comptime bits: bool) !void {
    try w.print("      \"{s}\": {{\n", .{name});
    var inner = false;
    inline for (if (@hasField(@TypeOf(@typeInfo(T).@"struct"), "fields"))
        @typeInfo(T).@"struct".fields
    else
        @typeInfo(T).@"struct".field_names) |field|
    {
        const field_name = if (@hasField(@TypeOf(field), "name")) field.name else field;
        if (field_name[0] != '_') {
            if (inner) try w.writeAll(",\n");
            const offset = @bitOffsetOf(T, field_name);
            try w.print("        \"{s}\": {d}", .{ field_name, if (bits) offset else offset / 8 });
            inner = true;
        }
    }
    try w.writeAll("\n      }");
}

fn usageAndExit(io: std.Io, cmd: []const u8) noreturn {
    var err = std.Io.File.stderr().writer(io, &.{});
    err.interface.print("Usage: {s} <markdown|protocol|layout>\n", .{cmd}) catch {};
    std.process.exit(1);
}
