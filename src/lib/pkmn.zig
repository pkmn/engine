pub const showdown = @import("build_options").showdown;
pub const trace = @import("build_options").trace;

pub const MAX_OPTIONS_SIZE = gen1.MAX_OPTIONS_SIZE;
pub const MAX_LOG_SIZE = gen1.MAX_LOG_SIZE;

pub const Player = @import("common/data.zig").Player;
pub const Choice = @import("common/data.zig").Choice;
pub const Result = @import("common/data.zig").Result;

pub const Log = @import("common/protocol.zig").Log;

pub const PRNG = @import("common/rng.zig").PRNG(6);

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
