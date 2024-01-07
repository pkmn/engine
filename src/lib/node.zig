const std = @import("std");

const pkmn = @import("pkmn.zig");

const js = @import("common/js.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("engine", .{ .value = register(env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}

pub fn register(env: c.napi_env) c.napi_value {
    const object = js.Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("options", .{ .value = options(env) }),
        js.Property.init("bindings", .{ .value = bindings(env) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn options(env: c.napi_env) c.napi_value {
    const object = js.Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("showdown", .{ .value = js.Boolean.init(env, pkmn.options.showdown) }),
        js.Property.init("log", .{ .value = js.Boolean.init(env, pkmn.options.log) }),
        js.Property.init("chance", .{ .value = js.Boolean.init(env, pkmn.options.chance) }),
        js.Property.init("calc", .{ .value = js.Boolean.init(env, pkmn.options.calc) }),
    };
    assert(c.napi_define_properties(env, object, properties.len, &properties) == c.napi_ok);
    return object;
}

fn bindings(env: c.napi_env) c.napi_value {
    const array = js.Array.init(env, .{ .length = 1 });
    js.Array.set(env, array, 0, bind(env, pkmn.gen1));
    return array;
}

fn bind(env: c.napi_env, gen: anytype) c.napi_value {
    const choices_size: u32 = @intCast(gen.CHOICES_SIZE);
    const logs_size: u32 = @intCast(gen.LOGS_SIZE);
    const object = js.Object.init(env);
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("CHOICES_SIZE", .{ .value = js.Number.init(env, choices_size) }),
        js.Property.init("LOGS_SIZE", .{ .value = js.Number.init(env, logs_size) }),
        js.Property.init("update", .{ .method = update(gen) }),
        js.Property.init("choices", .{ .method = choices(gen) }),
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

            var battle: *gen.Battle(gen.PRNG) = @alignCast(@ptrCast(data.?));
            const c1: pkmn.Choice = @bitCast(js.Number.get(env, argv[1], u8));
            const c2: pkmn.Choice = @bitCast(js.Number.get(env, argv[2], u8));

            var vtype: c.napi_valuetype = undefined;
            assert(c.napi_typeof(env, argv[3], &vtype) == c.napi_ok);
            const result = switch (vtype) {
                c.napi_undefined, c.napi_null => battle.update(c1, c2, &gen.NULL),
                else => result: {
                    assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
                    assert(len == gen.LOGS_SIZE);

                    const buf = @as([*]u8, @ptrCast(data.?))[0..gen.LOGS_SIZE];
                    var stream: pkmn.protocol.ByteStream = .{ .buffer = buf };
                    // TODO: extract out
                    var opts = pkmn.battle.options(
                        pkmn.protocol.FixedLog{ .writer = stream.writer() },
                        gen.chance.NULL,
                        gen.calc.NULL,
                    );
                    break :result battle.update(c1, c2, &opts);
                },
            } catch unreachable;

            return js.Number.init(env, @as(u8, @bitCast(result)));
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

            var battle: *gen.Battle(gen.PRNG) = @alignCast(@ptrCast(data.?));
            const player: pkmn.Player = @enumFromInt(js.Number.get(env, argv[1], u8));
            const request: pkmn.Choice.Type = @enumFromInt(js.Number.get(env, argv[2], u8));

            assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
            assert(len == gen.CHOICES_SIZE);

            const out = @as([*]pkmn.Choice, @ptrCast(data.?))[0..gen.CHOICES_SIZE];
            const n = battle.choices(player, request, out);
            return js.Number.init(env, @as(u8, @bitCast(n)));
        }
    }.call;
}
