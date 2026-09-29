const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

/// Optimized optional representation which stores the empty None value as a sentinel.
/// NOTE: ziglang/zig#104
pub fn Optional(comptime T: type) type {
    const info = @typeInfo(switch (@typeInfo(T)) {
        .bool => enum { false, true },
        else => T,
    }).@"enum";
    const names = if (@hasField(@TypeOf(info), "fields")) blk: {
        var ns: [info.fields.len][:0]const u8 = undefined;
        inline for (info.fields, 0..) |f, i| ns[i] = f.name;
        break :blk &ns;
    } else info.field_names;

    const TagType = std.math.IntFittingRange(0, names.len);
    var fieldNames: [names.len + 1][]const u8 = undefined;
    var fieldValues: [names.len + 1]TagType = undefined;

    fieldNames[0] = "None";
    fieldValues[0] = 0;

    inline for (names, 1..) |name, i| {
        assert(!std.mem.eql(u8, name, "None"));
        fieldNames[i] = name;
        fieldValues[i] = i;
    }

    return @Enum(TagType, .exhaustive, &fieldNames, &fieldValues);
}

test Optional {
    try expect(@bitSizeOf(Optional(bool)) == 2);

    const a: Optional(bool) = .true;
    try expect(a != .None);
    try expect(a == .true);
    try expect(a != .false);

    const b: Optional(bool) = .None;
    try expect(b == .None);
    try expect(b != .true);
    try expect(b != .false);

    const Player = @import("data.zig").Player;
    try expect(@bitSizeOf(Optional(Player)) == 2);

    const p: Optional(Player) = .P2;
    try expect(p != .None);
    try expect(p != .P1);
    try expect(p == .P2);

    const q: Optional(Player) = .None;
    try expect(q == .None);
    try expect(q != .P1);
    try expect(q != .P2);

    const Three = enum(u2) { A, B, C };
    try expect(@bitSizeOf(Optional(Three)) == 2);

    const Four = enum(u2) { A, B, C, D };
    try expect(@bitSizeOf(Optional(Four)) == 3);
}
