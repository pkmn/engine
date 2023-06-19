const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub fn PointerType(comptime P: type, comptime C: type) type {
    return if (@typeInfo(P).Pointer.is_const) *const C else *C;
}

test PointerType {
    try expectEqual(*bool, PointerType(*u8, bool));
    try expectEqual(*const f64, PointerType(*const i32, f64));
}
