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
        Property.init("bindings", .{ .value = bindings(env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}

fn options(env: c.napi_env) c.napi_value {
    var object = Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("showdown", .{ .value = Boolean.init(env, pkmn.options.showdown) }),
        Property.init("trace", .{ .value = Boolean.init(env, pkmn.options.trace) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn bindings(env: c.napi_env) c.napi_value {
    var array = Array.init(env, .{ .length = 1 });
    Array.set(env, array, 0, bind(env, pkmn.gen1));
    return array;
}

fn bind(env: c.napi_env, gen: anytype) c.napi_value {
    const options_size = @intCast(u32, gen.CHOICES_SIZE);
    const logs_size = @intCast(u32, gen.LOGS_SIZE);
    var object = Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        Property.init("CHOICES_SIZE", .{ .value = Number.init(env, options_size) }),
        Property.init("LOGS_SIZE", .{ .value = Number.init(env, logs_size) }),
        Property.init("update", .{ .method = update(gen) }),
        Property.init("choices", .{ .method = choices(gen) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn update(gen: anytype) c.napi_callback {
    return struct {
        fn call(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            var argc: usize = 4;
            var argv: [4]c.napi_value = undefined;
            assert(c.napi_get_cb_info(env, info, &argc, &argv, null, null) == c.napi_ok);
            assert(argc == 4);

            var data: ?*anyopaque = undefined;
            var len: usize = 0;
            assert(c.napi_get_arraybuffer_info(env, argv[0], &data, &len) == c.napi_ok);
            assert(len == @sizeOf(gen.Battle(gen.PRNG)));
            assert(data != null);

            var aligned = @alignCast(@alignOf(*gen.Battle(gen.PRNG)), data.?);
            var battle = @ptrCast(*gen.Battle(gen.PRNG), aligned);
            const c1 = @bitCast(pkmn.Choice, Number.get(env, argv[1], u8));
            const c2 = @bitCast(pkmn.Choice, Number.get(env, argv[2], u8));

            var vtype: c.napi_valuetype = undefined;
            assert(c.napi_typeof(env, argv[3], &vtype) == c.napi_ok);
            const result = switch (vtype) {
                c.napi_undefined, c.napi_null => battle.update(c1, c2, pkmn.protocol.NULL),
                else => result: {
                    assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
                    assert(len == gen.LOGS_SIZE);
                    assert(data != null);

                    var buf = @ptrCast([*]u8, data.?)[0..gen.LOGS_SIZE];
                    var stream = pkmn.protocol.ByteStream{ .buffer = buf };
                    var log = pkmn.protocol.FixedLog{ .writer = stream.writer() };
                    break :result battle.update(c1, c2, log);
                },
            } catch unreachable;

            return Number.init(env, @bitCast(u8, result));
        }
    }.call;
}

fn choices(gen: anytype) c.napi_callback {
    return struct {
        fn call(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            var argc: usize = 4;
            var argv: [4]c.napi_value = undefined;
            assert(c.napi_get_cb_info(env, info, &argc, &argv, null, null) == c.napi_ok);
            assert(argc == 4);

            var data: ?*anyopaque = undefined;
            var len: usize = 0;
            assert(c.napi_get_arraybuffer_info(env, argv[0], &data, &len) == c.napi_ok);
            assert(len == @sizeOf(gen.Battle(gen.PRNG)));
            assert(data != null);

            var aligned = @alignCast(@alignOf(*gen.Battle(gen.PRNG)), data.?);
            var battle = @ptrCast(*gen.Battle(gen.PRNG), aligned);

            const player = @intToEnum(pkmn.Player, Number.get(env, argv[1], u8));
            const request = @intToEnum(pkmn.Choice.Type, Number.get(env, argv[2], u8));

            assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
            assert(len == gen.CHOICES_SIZE);
            assert(data != null);

            var out = @ptrCast([*]pkmn.Choice, data.?)[0..gen.CHOICES_SIZE];
            const n = battle.choices(player, request, out);
            return Number.init(env, @bitCast(u8, n));
        }
    }.call;
}

const Array = struct {
    fn init(env: c.napi_env, o: struct { length: ?usize }) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_ok == if (o.length) |n|
            c.napi_create_array_with_length(env, n, &result)
        else
            c.napi_create_array(env, &result));
        return result;
    }

    fn set(env: c.napi_env, array: c.napi_value, index: u32, value: c.napi_value) void {
        assert(c.napi_set_element(env, array, index, value) == c.napi_ok);
    }
};

const Boolean = struct {
    fn init(env: c.napi_env, value: bool) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_get_boolean(env, value, &result) == c.napi_ok);
        return result;
    }
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

    fn get(env: c.napi_env, value: c.napi_value, comptime T: type) T {
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

const Object = struct {
    fn init(env: c.napi_env) c.napi_value {
        var result: c.napi_value = undefined;
        assert(c.napi_create_object(env, &result) == c.napi_ok);
        return result;
    }
};

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
