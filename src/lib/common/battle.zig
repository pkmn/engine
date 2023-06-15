/// Stores state required by optional features to the engine that can be passed to a generation's
/// `Battle.update` function. All generations generically support protocol logging (enabled via
/// `-Dlog`), chance actions and probability tracking (enabled via `-Dchance`), and damage computation
/// and chance overrides (`-Dcalc`), though the concrete types for these features are generation
/// dependent.
pub fn Options(comptime Log: type, comptime Chance: type, comptime Calc: type) type {
    return struct { log: Log, chance: Chance, calc: Calc };
}

/// Helper to create a battle `Options` object with the provided `log`, `chance`, and `calc`.
pub fn options(
    log: anytype,
    chance: anytype,
    calc: anytype,
) Options(@TypeOf(log), @TypeOf(chance), @TypeOf(calc)) {
    return .{ .log = log, .chance = chance, .calc = calc };
}
