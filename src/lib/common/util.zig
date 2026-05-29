const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub fn PointerType(comptime P: type, comptime C: type) type {
    const ptr_info = @typeInfo(P).pointer;
    const is_const = if (@hasField(@TypeOf(ptr_info), "attrs"))
        ptr_info.attrs.@"const"
    else
        ptr_info.is_const;
    return if (is_const) *const C else *C;
}

test PointerType {
    try expectEqual(*bool, PointerType(*u8, bool));
    try expectEqual(*const f64, PointerType(*const i32, f64));
}

pub fn EnumFieldsLen(comptime E: type) usize {
    const info = @typeInfo(E).@"enum";
    return if (@hasField(@TypeOf(info), "fields"))
        info.fields.len
    else
        info.field_names.len;
}

test EnumFieldsLen {
    const E1 = enum { A, B, C };
    const E2 = enum(u8) { A = 0, B = 10, C = 20, D = 30 };
    try expectEqual(3, EnumFieldsLen(E1));
    try expectEqual(4, EnumFieldsLen(E2));
}

pub fn isPointerTo(p: anytype, comptime P: type) bool {
    const info = @typeInfo(@TypeOf(p));
    return switch (info) {
        .pointer => info.pointer.child == P,
        else => false,
    };
}

test isPointerTo {
    const S = struct {};
    const s: S = .{};
    try expect(!isPointerTo(s, S));
    try expect(isPointerTo(&s, S));
}

pub fn repeat(comptime xs: anytype, comptime n: usize) [xs.len * n]@TypeOf(xs[0]) {
    comptime {
        const T = @TypeOf(xs[0]);
        var ts: [xs.len * n]T = undefined;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            for (xs, 0..) |v, j| {
                ts[i * xs.len + j] = v;
            }
        }

        return ts;
    }
}
