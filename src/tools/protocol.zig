const std = @import("std");

const pkmn = @import("pkmn");

const protocol = pkmn.protocol;

const Tool = enum {
    markdown,
    protocol,
    layout,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) std.process.exit(1);

    var tool: Tool = undefined;
    if (std.mem.eql(u8, args[1], "markdown")) {
        tool = .markdown;
    } else if (std.mem.eql(u8, args[1], "protocol")) {
        tool = .protocol;
    } else if (std.mem.eql(u8, args[1], "layout")) {
        tool = .layout;
    } else {
        std.process.exit(1);
    }

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    switch (tool) {
        .markdown => {
            inline for (@typeInfo(protocol).Struct.decls) |decl| {
                if (comptime std.ascii.isUpper(decl.name[0]) and
                    decl.is_pub and
                    !std.mem.eql(u8, decl.name, "Log"))
                {
                    try w.print(
                        "## {s}\n\n<details><summary>Reason</summary>\n",
                        .{decl.name},
                    );
                    try w.writeAll("\n|Raw|Description|\n|--|--|\n");
                    inline for (@typeInfo(@field(protocol, decl.name)).Enum.fields) |field| {
                        try w.print("|`0x{X:0>2}`|`{s}`|\n", .{ field.value, field.name });
                    }
                    try w.writeAll("</details>\n\n");
                }
            }
        },
        .protocol => {
            var outer = false;
            try w.writeAll("{\n");
            inline for (@typeInfo(protocol).Struct.decls) |decl| {
                if (comptime std.ascii.isUpper(decl.name[0]) and
                    decl.is_pub and
                    !std.mem.eql(u8, decl.name, "Log"))
                {
                    if (outer) try w.writeAll(",\n");
                    try w.print("  \"{s}\": [\n", .{decl.name});
                    var inner = false;
                    inline for (@typeInfo(@field(protocol, decl.name)).Enum.fields) |field| {
                        if (inner) try w.writeAll(",\n");
                        try w.print("    \"{s}\"", .{field.name});
                        inner = true;
                    }
                    try w.writeAll("\n  ]");
                    outer = true;
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
                        .{ "Battle", @sizeOf(pkmn.gen1.Battle(pkmn.gen1.RNG)) },
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
                        "      \"{s}\": {d}\n",
                        .{ "ActivePokemon", @sizeOf(pkmn.gen1.ActivePokemon) },
                    );
                }
                try w.writeAll("    },\n");
                try w.writeAll("    \"offsets\": {\n");
                {
                    try print(w, "Battle", pkmn.gen1.Battle(pkmn.gen1.RNG), false);
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
                    try print(w, "VolatilesData", pkmn.gen1.Volatiles.Data, true);
                    try w.writeAll("\n    }\n");
                }
                try w.writeAll("  }\n");
            }
            try w.writeAll("]\n");
        },
    }

    try buf.flush();
}

fn print(w: anytype, name: []const u8, comptime T: type, comptime bits: bool) !void {
    try w.print("      \"{s}\": {{\n", .{name});
    var inner = false;
    inline for (std.meta.fields(T)) |field| {
        if (field.name[0] != '_') {
            if (inner) try w.writeAll(",\n");
            const offset = @bitOffsetOf(T, field.name);
            try w.print("        \"{s}\": {d}", .{ field.name, if (bits) offset else offset / 8 });
            inner = true;
        }
    }
    try w.writeAll("\n      }");
}
