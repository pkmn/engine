const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

// TODO: ziglang/zig#104
pub fn Optional(comptime T: type) type {
    const fields = std.meta.fields(switch (@typeInfo(T)) {
        .Bool => enum { false, true },
        else => T,
    });

    var enumFields: [fields.len + 1]std.builtin.Type.EnumField = undefined;
    var decls = [_]std.builtin.Type.Declaration{};

    enumFields[0] = .{ .name = "None", .value = 0 };
    inline for (fields, 1..) |field, i| {
        assert(!std.mem.eql(u8, field.name, "None"));
        enumFields[i] = .{
            .name = field.name,
            .value = i,
        };
    }

    return @Type(.{
        .Enum = .{
            .tag_type = std.math.IntFittingRange(0, fields.len + 1),
            .fields = &enumFields,
            .decls = &decls,
            .is_exhaustive = true,
        },
    });
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

    const Player = @import("./data.zig").Player;
    try expect(@bitSizeOf(Optional(Player)) == 2);

    const p: Optional(Player) = .P2;
    try expect(p != .None);
    try expect(p != .P1);
    try expect(p == .P2);

    const q: Optional(Player) = .None;
    try expect(q == .None);
    try expect(q != .P1);
    try expect(q != .P2);
}
