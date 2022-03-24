const std = @import("std");

const pkmn = @import("pkmn");

const protocol = pkmn.protocol;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const json = args.len > 1 and std.mem.eql(u8, args[1], "json");

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    if (json) {
        unreachable; //

    } else {
        inline for (@typeInfo(protocol).Struct.decls) |decl| {
            if (comptime std.ascii.isUpper((decl.name[0]))) {
                try w.print("\n## {s}\n\n", .{decl.name});
                try w.writeAll("<details><summary>Data</summary>\n\nRaw|Data|\n|--|--|\n");
                inline for (@typeInfo(@field(protocol, decl.name)).Enum.fields) |field| {
                    try w.print("|0x{X:0>2}|{s}|\n", .{ field.value, field.name });
                }
                try w.writeAll("</details>\n");
            }
        }
    }

    try buf.flush();
}
