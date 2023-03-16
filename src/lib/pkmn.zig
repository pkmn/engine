/// Configurated Options for the pkmn package.
pub const options = @import("common/options.zig");
/// Configures the behavior of the pkmn package.
pub const Options = options.Options;

/// The minimum size in bytes required to hold all choice options.
pub const MAX_OPTIONS = gen1.MAX_OPTIONS;
/// The optimal size in bytes required to hold all choice options.
/// At least as large as MAX_OPTIONS.
pub const OPTIONS_SIZE = gen1.OPTIONS_SIZE;
/// The maximum number of bytes possibly logged by a single update.
pub const MAX_LOGS = gen1.MAX_LOGS;
/// The optimal size in bytes required to hold the largest amount of log data
/// possible from a single update. At least as large as MAX_LOGS.
pub const LOGS_SIZE = gen1.LOGS_SIZE;

/// Representation of one of the battle's participants.
pub const Player = @import("common/data.zig").Player;
/// A choice made by a player during battle.
pub const Choice = @import("common/data.zig").Choice;
/// The result of the battle - all results other than 'None' should be
/// considered terminal.
pub const Result = @import("common/data.zig").Result;

/// Logs protocol information to its Writer during a battle update when
/// options.trace is enabled.
pub const Log = @import("common/protocol.zig").Log;

/// Pokémon Showdown's RNG (backed by a Generation V & VI RNG).
pub const PSRNG = @import("common/rng.zig").PSRNG;

pub const protocol = if (options.internal) struct {
    pub usingnamespace @import("common/protocol.zig");
} else struct {
    pub const FixedLog = @import("common/protocol.zig").FixedLog;
    pub const NULL = @import("common/protocol.zig").NULL;
};

pub const gen1 = struct {
    pub usingnamespace @import("gen1/data.zig");
    pub const helpers = @import("gen1/helpers.zig");
};
