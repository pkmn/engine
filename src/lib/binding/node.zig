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

    fn get(env: c.napi_env, value: c.napi_value) !bool {
        var result: u32 = undefined;
        assert(c.napi_get_value_bool(env, value, &result) == c.napi_ok);
        return result;
    }
};
