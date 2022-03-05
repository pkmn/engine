comptime {
    _ = @import("common/rng.zig");
    _ = @import("common/protocol.zig");

    _ = @import("gen1/test.zig");
    _ = @import("gen2/test.zig");
    // _ = @import("gen3/test.zig");
}
