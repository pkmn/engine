const std = @import("std");

pub fn print(comptime T: type) !void {
    const stdout = std.io.getStdOut().writer();
    comptime var last = 0;
    try stdout.print("{s} = ({d} bytes / {d} bits)\n", .{ @typeName(T), @sizeOf(T), @bitSizeOf(T) });
    try stdout.writeAll("-" ** 30 ++ "\n");
    inline for (std.meta.fields(T)) |field| {
        const size = @bitSizeOf(field.field_type);
        const offset = @bitOffsetOf(T, field.name);
        if (offset > last) {
            try stdout.print("*** PADDING *** ({d} bits)\n", .{offset - last});
        }
        const aligned = offset % @alignOf(field.field_type) * 8 == 0;
        try stdout.print("{s}.{s}: {s} = {d}-{d} ({d} bits, {s}aligned to {d} bytes)\n", .{ @typeName(T), field.name, field.field_type, offset, offset + size, size, if (aligned) "" else "NOT ", @alignOf(field.field_type) });
        last = offset + size;
    }
    if (last < @sizeOf(T) * 8) {
        try stdout.print("*** PADDING *** ({d} bits)\n", .{@sizeOf(T) * 8 - last});
    }
}
