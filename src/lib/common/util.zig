const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Pointer = if (@hasField(std.builtin.Type, "pointer")) .pointer else .Pointer;
const One = if (@hasField(std.builtin.Type.Pointer.Size, "one")) .one else .One;

pub fn PointerType(comptime P: type, comptime C: type) type {
    return if (@field(@typeInfo(P), @tagName(Pointer)).is_const) *const C else *C;
}

test PointerType {
    try expectEqual(*bool, PointerType(*u8, bool));
    try expectEqual(*const f64, PointerType(*const i32, f64));
}

pub fn isPointerTo(p: anytype, comptime P: type) bool {
    const info = @typeInfo(@TypeOf(p));
    return switch (info) {
        Pointer => @field(info, @tagName(Pointer)).child == P,
        else => false,
    };
}

test isPointerTo {
    const S = struct {};
    const s: S = .{};
    try expect(!isPointerTo(s, S));
    try expect(isPointerTo(&s, S));
}

// NOTE: std.mem.bytesAsValue backported from ziglang/zig#18061
pub fn bytesAsValue(comptime T: type, bytes: anytype) BytesAsValueReturnType(T, @TypeOf(bytes)) {
    return @as(BytesAsValueReturnType(T, @TypeOf(bytes)), @ptrCast(bytes));
}

fn BytesAsValueReturnType(comptime T: type, comptime B: type) type {
    return CopyPtrAttrs(B, One, T);
}

fn CopyPtrAttrs(
    comptime source: type,
    comptime size: std.builtin.Type.Pointer.Size,
    comptime child: type,
) type {
    const info = @field(@typeInfo(source), @tagName(Pointer));
    const args: std.builtin.Type.Pointer = if (@hasField(std.builtin.Type.Pointer, "sentinel")) .{
        .size = size,
        .is_const = info.is_const,
        .is_volatile = info.is_volatile,
        .is_allowzero = info.is_allowzero,
        .alignment = info.alignment,
        .address_space = info.address_space,
        .child = child,
        .sentinel = null,
    } else .{
        .size = size,
        .is_const = info.is_const,
        .is_volatile = info.is_volatile,
        .is_allowzero = info.is_allowzero,
        .alignment = info.alignment,
        .address_space = info.address_space,
        .child = child,
        .sentinel_ptr = null,
    };
    return @Type(if (@hasField(std.builtin.Type, "pointer"))
        .{ .pointer = args }
    else
        .{ .Pointer = args });
}

// NOTE: std.meta.FieldType replaced by @FieldType in 0.14.0
pub fn FieldType(comptime T: type, comptime field: std.meta.FieldEnum(T)) type {
    return std.meta.fieldInfo(T, field).type;
}

// Replacement for array multiplication after ziglang/zig#24738 (@splat only works after 0.14.0)
pub fn repeat(comptime T: type, t: T, comptime n: usize) [n]T {
    var ts: [n]T = undefined;
    inline for (0..n) |i| {
        ts[i] = t;
    }
    return ts;
}
