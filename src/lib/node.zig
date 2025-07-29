const c = @import("napi");
const js = @import("common/js.zig");
const node = @import("bindings/node.zig");
const std = @import("std");

const assert = std.debug.assert;

export fn napi_register_module_v1(env: c.napi_env, exports: c.napi_value) c.napi_value {
    const properties = [_]c.napi_property_descriptor{
        js.Property.init("engine", .{ .value = node.register(env) }),
    };
    assert(c.napi_define_properties(env, exports, properties.len, &properties) == c.napi_ok);
    return exports;
}
