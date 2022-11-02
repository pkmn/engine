comptime {
    _ = @import("common/data.zig");
    _ = @import("common/rng.zig");
    _ = @import("common/protocol.zig");

    _ = @import("gen1/test.zig");
    // _ = @import("gen2/test.zig");
}
