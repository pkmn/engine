/// Information relevant to damage calculation that occured during a Generation II battle `update`.
pub const Summaries = extern struct {};

/// TODO
pub const Overrides = extern struct {};

/// Allows for forcing the value of specific RNG events during a Generation II battle `update` via
/// `overrides` and tracks `summaries` of information relevant to damage calculation.
pub const Calc = struct {
    /// Overrides the normal behavior of the RNG during an `update` to force specific outcomes.
    overrides: Overrides = .{},
    /// Information relevant to damage calculation.
    summaries: Summaries = .{},
};

/// Null object pattern implementation of Generation II `Calc` which does nothing, though damage
/// calculator support should additionally be turned off entirely via `options.calc`.
pub const NULL = Null{};

const Null = struct {};
