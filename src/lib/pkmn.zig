/// Configurated Options for the pkmn package.
pub const options = @import("common/options.zig");
/// Configures the behavior of the pkmn package.
pub const Options = options.Options;

/// The minimum size in bytes required to hold all choice options.
pub const MAX_CHOICES = gen1.MAX_CHOICES;
/// The optimal size in bytes required to hold all choice options.
/// At least as large as `MAX_CHOICES`.
pub const CHOICES_SIZE = gen1.CHOICES_SIZE;
/// The maximum number of bytes possibly logged by a single update.
pub const MAX_LOGS = gen1.MAX_LOGS;
/// The optimal size in bytes required to hold the largest amount of log data
/// possible from a single update. At least as large as `MAX_LOGS`.
pub const LOGS_SIZE = gen1.LOGS_SIZE;

/// Representation of one of the battle's participants.
pub const Player = @import("common/data.zig").Player;
/// A choice made by a player during battle.
pub const Choice = @import("common/data.zig").Choice;
/// The result of the battle - all results other than 'None' should be
/// considered terminal.
pub const Result = @import("common/data.zig").Result;

/// Pokémon Showdown's RNG (backed by a Generation V & VI RNG).
pub const PSRNG = @import("common/rng.zig").PSRNG;

/// Namespace for helpers related to protocol message logging.
pub const protocol = if (options.internal) struct {
    pub usingnamespace @import("common/protocol.zig");
} else struct {
    /// Logs protocol information to its `Writer` during a battle update when
    /// `options.log` is enabled.
    pub const Log = @import("common/protocol.zig").Log;
    /// Stripped down version of `std.io.FixedBufferStream` optimized for
    /// efficiently writing the individual protocol bytes. Note that the
    /// `ByteStream.Writer` is **not** a `std.io.Writer` and should not be
    /// used for general purpose writing.
    pub const ByteStream = @import("common/protocol.zig").ByteStream;
    /// `Log` type backed by the optimized `ByteStream.Writer`. Intended to be
    /// intialized with a `LOGS_SIZE`-sized buffer.
    pub const FixedLog = @import("common/protocol.zig").FixedLog;
    /// Null object pattern implementation of `Log` backed by a
    /// `std.io.null_writer`. Ignores anything sent to it, though protocol
    /// logging should additionally be turned off entirely with `options.log`.
    pub const NULL = @import("common/protocol.zig").NULL;
};

pub usingnamespace @import("common/rational.zig");

/// TODO
pub const battle = struct {
    pub fn Options(comptime Log: type, comptime Chance: type, comptime Calc: type) type {
        return struct {
            log: Log,
            chance: Chance,
            calc: Calc,
        };
    }
};

/// Namespace for Generation I Pokémon
pub const gen1 = struct {
    pub usingnamespace @import("gen1/data.zig");
    /// TODO
    pub const Chance = @import("gen1/chance.zig").Chance;
    /// TODO
    pub const chance = struct {
        /// TODO
        pub const Actions = @import("gen1/chance.zig").Actions;
        /// TODO
        pub const NULL = @import("gen1/chance.zig").NULL;
    };
    // TODO
    pub const Calc = @import("gen1/calc.zig").Calc;
    /// TODO
    pub const calc = struct {
        /// TODO
        pub const Summary = @import("gen1/calc.zig").Summary;
        /// TODO
        pub const NULL = @import("gen1/calc.zig").NULL;
    };
    /// Provides helpers for initializing Generation I Pokémon battles.
    pub const helpers = @import("gen1/helpers.zig");
};
