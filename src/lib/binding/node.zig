const std = @import("std");
const pkmn = @import("../pkmn.zig");

const js = @import("../common/js.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cDefine("NAPI_VERSION", "8");
    @cInclude("node_api.h");
});

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("options", .{ .value = options(env) }),
        js.Property.init("bindings", .{ .value = bindings(env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}

fn options(env: c.napi_env) c.napi_value {
    var object = js.Object.init(env);
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
    var array = js.Array.init(env, .{ .length = 1 });
    js.Array.set(env, array, 0, bind(env, pkmn.gen1));
    return array;
}

fn bind(env: c.napi_env, gen: anytype) c.napi_value {
    const choices_size = @intCast(u32, gen.CHOICES_SIZE);
    const logs_size = @intCast(u32, gen.LOGS_SIZE);
    var object = js.Object.init(env);
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
            assert(data != null);

            var aligned = @alignCast(@alignOf(*gen.Battle(gen.PRNG)), data.?);
            var battle = @ptrCast(*gen.Battle(gen.PRNG), aligned);
            const c1 = @bitCast(pkmn.Choice, js.Number.get(env, argv[1], u8));
            const c2 = @bitCast(pkmn.Choice, js.Number.get(env, argv[2], u8));

            var vtype: c.napi_valuetype = undefined;
            assert(c.napi_typeof(env, argv[3], &vtype) == c.napi_ok);
            const result = switch (vtype) {
                c.napi_undefined, c.napi_null => battle.update(c1, c2, &gen.NULL),
                else => result: {
                    assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
                    assert(len == gen.LOGS_SIZE);
                    assert(data != null);

                    var buf = @ptrCast([*]u8, data.?)[0..gen.LOGS_SIZE];
                    var stream = pkmn.protocol.ByteStream{ .buffer = buf };
                    // TODO: extract out
                    var opts = pkmn.battle.Options(
                        pkmn.protocol.FixedLog,
                        @TypeOf(gen.chance.NULL),
                        @TypeOf(gen.calc.NULL),
                    ){
                        .log = .{ .writer = stream.writer() },
                        .chance = gen.chance.NULL,
                        .calc = gen.calc.NULL,
                    };
                    break :result battle.update(c1, c2, &opts);
                },
            } catch unreachable;

            return js.Number.init(env, @bitCast(u8, result));
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

            const player = @enumFromInt(pkmn.Player, js.Number.get(env, argv[1], u8));
            const request = @enumFromInt(pkmn.Choice.Type, js.Number.get(env, argv[2], u8));

            assert(c.napi_get_arraybuffer_info(env, argv[3], &data, &len) == c.napi_ok);
            assert(len == gen.CHOICES_SIZE);
            assert(data != null);

            var out = @ptrCast([*]pkmn.Choice, data.?)[0..gen.CHOICES_SIZE];
            const n = battle.choices(player, request, out);
            return js.Number.init(env, @bitCast(u8, n));
        }
    }.call;
}
