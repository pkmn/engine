pub const protocol = struct {
    usingnamespace @import("common/protocol.zig");
};
pub const rng = struct {
    usingnamespace @import("common/rng.zig");
};
pub const gen1 = struct {
    usingnamespace @import("gen1/data.zig");
    pub const helpers = @import("gen1/helpers.zig");
};
