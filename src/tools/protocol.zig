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
                if (comptime std.ascii.isUpper((decl.name[0]))) {
                    try w.print("<details><summary><b><code>{s}</code><b></summary>\n", .{decl.name});
                    try w.writeAll("\nRaw|Data|\n|--|--|\n");
                    inline for (@typeInfo(@field(protocol, decl.name)).Enum.fields) |field| {
                        try w.print("|`0x{X:0>2}`|`{s}`|\n", .{ field.value, field.name });
                    }
                    try w.writeAll("</details>\n\n");
                }
            }
        },
        .protocol => {
            var outer = false;
            try w.writeAll("{");
            inline for (@typeInfo(protocol).Struct.decls) |decl| {
                if (comptime std.ascii.isUpper((decl.name[0]))) {
                    if (outer) try w.writeAll(",");
                    try w.print("\"{s}\":[", .{decl.name});
                    var inner = false;
                    inline for (@typeInfo(@field(protocol, decl.name)).Enum.fields) |field| {
                        if (inner) try w.writeAll(",");
                        try w.print("\"{s}\"", .{field.name});
                        inner = true;
                    }
                    try w.writeAll("]");
                    outer = true;
                }
            }
            try w.writeAll("}");
        },
        .layout => {
            try w.writeAll("[");
            {
                try w.writeAll("{\"sizes\":{");
                {
                    try w.print("\"{s}\":{d},", .{ "Battle", @sizeOf(pkmn.gen1.Battle(pkmn.gen1.RNG)) });
                    try w.print("\"{s}\":{d},", .{ "Side", @sizeOf(pkmn.gen1.Side) });
                    try w.print("\"{s}\":{d},", .{ "Pokemon", @sizeOf(pkmn.gen1.Pokemon) });
                    try w.print("\"{s}\":{d}", .{ "ActivePokemon", @sizeOf(pkmn.gen1.ActivePokemon) });
                }
                try w.writeAll("},");
                try w.writeAll("\"offsets\":{");
                {
                    try print(w, "Battle", pkmn.gen1.Battle(pkmn.gen1.RNG), false);
                    try w.writeAll(",");
                    try print(w, "Side", pkmn.gen1.Side, false);
                    try w.writeAll(",");
                    try print(w, "Pokemon", pkmn.gen1.Pokemon, false);
                    try w.writeAll(",");
                    try print(w, "ActivePokemon", pkmn.gen1.ActivePokemon, false);
                    try w.writeAll(",");
                    try print(w, "Stats", pkmn.gen1.Stats(u16), false);
                    try w.writeAll(",");
                    try print(w, "Boosts", pkmn.gen1.Boosts, true);
                    try w.writeAll(",");
                    try print(w, "Volatiles", pkmn.gen1.Volatiles, true);
                    try w.writeAll(",");
                    try print(w, "VolatilesData", pkmn.gen1.Volatiles.Data, true);
                    try w.writeAll("}");
                }
                try w.writeAll("}");
            }
            try w.writeAll("]");
        },
    }

    try buf.flush();
}

pub fn print(w: anytype, name: []const u8, comptime T: type, comptime bits: bool) !void {
    try w.print("\"{s}\":{{", .{name});
    var inner = false;
    inline for (std.meta.fields(T)) |field| {
        if (inner) try w.writeAll(",");
        const offset = @bitOffsetOf(T, field.name);
        try w.print("\"{s}\":{d}", .{ field.name, if (bits) offset else offset / 8 });
        inner = true;
    }
    try w.writeAll("}");
}
