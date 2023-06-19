const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub fn PointerType(comptime P: type, comptime C: type) type {
    return if (@typeInfo(P).Pointer.is_const) *const C else *C;
}

test PointerType {
    try expectEqual(*bool, PointerType(*u8, bool));
    try expectEqual(*const f64, PointerType(*const i32, f64));
}

pub fn FieldType(comptime T: type, comptime field: []const u8) type {
    for (@typeInfo(T).Struct.fields) |f| if (std.mem.eql(u8, f.name, field)) return f.type;
    unreachable;
}

test FieldType {
    const Foo = struct {
        bar: bool,
        baz: u8,
    };

    try expectEqual(bool, FieldType(Foo, "bar"));
    try expectEqual(u8, FieldType(Foo, "baz"));
}
