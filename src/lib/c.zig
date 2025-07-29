const c = @import("bindings/c.zig");

comptime {
    c.exports();
}
