pub const options = @import("common/options.zig");
pub const Options = options.Options;

pub const MAX_OPTIONS = gen1.MAX_OPTIONS;
pub const OPTIONS_SIZE = gen1.OPTIONS_SIZE;
pub const MAX_LOGS = gen1.MAX_LOGS;
pub const LOGS_SIZE = gen1.LOGS_SIZE;

pub const Player = @import("common/data.zig").Player;
pub const Choice = @import("common/data.zig").Choice;
pub const Result = @import("common/data.zig").Result;

pub const Log = @import("common/protocol.zig").Log;

pub const PSRNG = @import("common/rng.zig").PSRNG;

pub const protocol = struct {
    pub usingnamespace @import("common/protocol.zig");
};
pub const rng = struct {
    pub usingnamespace @import("common/rng.zig");
};

pub const gen1 = struct {
    pub usingnamespace @import("gen1/data.zig");
    pub const helpers = @import("gen1/helpers.zig");
};
