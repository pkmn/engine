const std = @import("std");
const pkmn = @import("../pkmn.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const properties = [_]c.napi_property_descriptor{
        Property.init("options", .{ .value = options(env) }),
        Property.init("gen1", .{ .value = bind(pkmn.gen1, env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}

fn options(env: c.napi_env) c.napi_value {
    var object = try Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("showdown", .{ .value = try Boolean.init(env, pkmn.options.showdown) }),
        Property.init("trace", .{ .value = try Boolean.init(env, pkmn.options.trace) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn bind(gen: anytype, env: c.napi_env) c.napi_value {
    const options_size = @truncate(u32, gen.OPTIONS_SIZE);
    const log_size = @truncate(u32, gen.LOG_SIZE);
    var object = try Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("OPTIONS_SIZE", .{ .value = Number.init(env, options_size) }),
        Property.init("LOG_SIZE", .{ .value = Number.init(env, log_size) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

const Property = union(enum) {
    method: c.napi_callback,
    value: c.napi_value,

    fn init(comptime name: [:0]const u8, property: Property) c.napi_property_descriptor {
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

const Object = struct {
    fn init(env: c.napi_env) !c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_create_object(env, &result) == c.napi_ok);
        return result;
    }
};

const Boolean = struct {
    fn init(env: c.napi_env, value: bool) !c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_get_boolean(env, value, &result) == c.napi_ok);
        return result;
    }

    // fn get(env: c.napi_env, value: c.napi_value) !bool {
    //     var result: u32 = undefined;
    //     assert(c.napi_get_value_bool(env, value, &result) == c.napi_ok);
    //     return result;
    // }
};

const Number = struct {
    fn init(env: c.napi_env, value: anytype) c.napi_value {
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

    // fn get(env: c.napi_env, value: c.napi_value, comptime T: type) !T {
    //     switch (@typeInfo(T)) {
    //         .Int => |info| switch (info.bits) {
    //             0...32 => switch (info.signedness) {
    //                 .signed => {
    //                     var result: i32 = undefined;
    //                     return switch (c.napi_get_value_int32(env, value, &result)) {
    //                         c.napi_ok => if (info.bits == 32) result else @intCast(T, result),
    //                         else => unreachable,
    //                     };
    //                 },
    //                 .unsigned => {
    //                     var result: u32 = undefined;
    //                     return switch (c.napi_get_value_uint32(env, value, &result)) {
    //                         c.napi_ok => if (info.bits == 32) result else @intCast(T, result),
    //                         else => unreachable,
    //                     };
    //                 },
    //             },
    //             33...63 => {
    //                 var result: i64 = undefined;
    //                 return switch (c.napi_get_value_int64(env, value, &result)) {
    //                     c.napi_ok => @intCast(T, result),
    //                     else => unreachable,
    //                 };
    //             },
    //             else => {
    //                 var result: i64 = undefined;
    //                 return switch (c.napi_get_value_int64(env, value, &result)) {
    //                     c.napi_ok => switch (info.signedness) {
    //                         .signed => return @as(T, value),
    //                         .unsigned => return if (0 <= value)
    //                             @intCast(T, value)
    //                         else
    //                             unreachable,
    //                     },
    //                     else => unreachable,
    //                 };
    //             },
    //         },
    //         else => @compileError("expected number, got: " ++ @typeName(T)),
    //     }
    // }
};
