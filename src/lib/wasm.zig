const wasm = @import("bindings/wasm.zig");

comptime {
    wasm.exports();
}
