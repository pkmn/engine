const std = @import("std");

const assert = std.debug.assert;

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

pub const Array = struct {
    pub fn init(env: c.napi_env, o: struct { length: ?usize }) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_ok == if (o.length) |n|
            c.napi_create_array_with_length(env, n, &result)
        else
            c.napi_create_array(env, &result));
        return result;
    }

    pub fn set(env: c.napi_env, array: c.napi_value, index: u32, value: c.napi_value) void {
        assert(c.napi_set_element(env, array, index, value) == c.napi_ok);
    }
};

pub const Boolean = struct {
    pub fn init(env: c.napi_env, value: bool) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_get_boolean(env, value, &result) == c.napi_ok);
        return result;
    }
};

pub const Number = struct {
    pub fn init(env: c.napi_env, value: anytype) c.napi_value {
        const T = @TypeOf(value);
        var result: c.napi_value = undefined;
        assert(c.napi_ok == switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => c.napi_create_int32(env, @as(i32, value), &result),
                    .unsigned => c.napi_create_uint32(env, @as(u32, value), &result),
                },
                33...52 => c.napi_create_int64(env, @as(i64, value), &result),
                else => @compileError("int can't be represented as JS number"),
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        });
        return result;
    }

    pub fn get(env: c.napi_env, value: c.napi_value, comptime T: type) T {
        switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...32 => switch (info.signedness) {
                    .signed => {
                        var result: i32 = undefined;
                        assert(c.napi_get_value_int32(env, value, &result) == c.napi_ok);
                        return if (info.bits == 32) result else @intCast(T, result);
                    },
                    .unsigned => {
                        var result: u32 = undefined;
                        assert(c.napi_get_value_uint32(env, value, &result) == c.napi_ok);
                        return if (info.bits == 32) result else @intCast(T, result);
                    },
                },
                33...63 => {
                    var result: i64 = undefined;
                    assert(c.napi_get_value_int64(env, value, &result) == c.napi_ok);
                    return @intCast(T, result);
                },
                else => {
                    var result: i64 = undefined;
                    assert(c.napi_get_value_int64(env, value, &result) == c.napi_ok);
                    return switch (info.signedness) {
                        .signed => @as(T, value),
                        .unsigned => if (0 <= value) @intCast(T, value) else unreachable,
                    };
                },
            },
            else => @compileError("expected number, got: " ++ @typeName(T)),
        }
    }
};

pub const Object = struct {
    pub fn init(env: c.napi_env) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_create_object(env, &result) == c.napi_ok);
        return result;
    }
};

pub const Property = union(enum) {
    method: c.napi_callback,
    value: c.napi_value,

    pub fn init(comptime name: [:0]const u8, property: Property) c.napi_property_descriptor {
        return .{
            .utf8name = name,
            .name = null,
            .method = switch (property) {
                .method => |m| m,
                .value => null,
            },
            .getter = null,
            .setter = null,
            .value = switch (property) {
                .method => null,
                .value => |v| v,
            },
            .attributes = switch (property) {
                .method => c.napi_default,
                .value => c.napi_enumerable,
            },
            .data = null,
        };
    }
};
