const builtin = @import("builtin");
const std = @import("std");

const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Specialization of a rational number used by the engine to compute probabilties.
/// For performance reasons the rational is only reduced lazily and thus `reduce` must be invoked
/// explicitly before reading.
pub fn Rational(comptime T: type) type {
    return extern struct {
        const Self = @This();

        /// Numerator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        p: T = 1,
        /// Denominator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        q: T = 1,

        // With floats we can't rely on an overflow bit to let us know when to reduce, so we instead
        // start reducing when we get sufficiently close to the limit of the mantissa (in our domain
        // we expect updates to involve numbers < 2**10, so we should be safe not reducing before we
        // are 2**10 away from "overflowing" the mantissa)
        const REDUCE = if (@typeInfo(T) == .Float)
            std.math.pow(T, 2, std.math.floatMantissaBits(T) - 10)
        else
            0;

        /// Resets the rational back to 1.
        pub fn reset(r: *Self) void {
            r.p = 1;
            r.q = 1;
        }

        /// Update the rational by multiplying its numerator by p and its denominator by q.
        /// Both p and q must be >= 1, and if computable at comptime must have no common factors.
        pub fn update(r: *Self, p: anytype, q: anytype) (switch (@typeInfo(T)) {
            .Int => error{Overflow},
            .Float => error{},
            else => unreachable,
        })!void {
            assert(p >= 1);
            assert(q >= 1);

            // If our parameters are not fully reduced they may prematurely
            // cause overflow/loss of precision after the multiplication below
            assert(switch (@typeInfo(@TypeOf(p, q))) {
                .ComptimeInt, .ComptimeFloat => comptime gcd(p, q),
                else => 1,
            } == 1);

            switch (@typeInfo(T)) {
                .Int => {
                    // Greedily attempt to multiply and if it fails, reduce and try again
                    r.mul(p, q) catch |err| switch (err) {
                        error.Overflow => {
                            r.reduce();
                            try r.mul(p, q);
                        },
                        else => unreachable,
                    };
                },
                .Float => {
                    // Reduce in situations where we're likely to start losing precision
                    if (r.q > REDUCE or r.p > REDUCE) r.reduce();

                    r.p *= switch (@typeInfo(@TypeOf(p))) {
                        .Float, .ComptimeFloat => p,
                        else => @intToFloat(T, p),
                    };
                    r.q *= switch (@typeInfo(@TypeOf(q))) {
                        .Float, .ComptimeFloat => q,
                        else => @intToFloat(T, q),
                    };

                    // We should always be dealing with whole numbers
                    assert(std.math.modf(r.p).fpart == 0);
                    assert(std.math.modf(r.q).fpart == 0);
                },
                else => unreachable,
            }
        }

        /// Normalize the rational by reducing by the greatest common divisor.
        pub fn reduce(r: *Self) void {
            const d = gcd(r.p, r.q);

            assert(@mod(r.p, d) == 0);
            assert(@mod(r.q, d) == 0);

            r.p /= d;
            r.q /= d;

            assert(r.p >= 1);
            assert(r.q >= 1);
        }

        inline fn mul(r: *Self, p: anytype, q: anytype) !void {
            r.p = try std.math.mul(T, r.p, p);
            r.q = try std.math.mul(T, r.q, q);
        }
    };
}

// https://en.wikipedia.org/wiki/Euclidean_algorithm
inline fn gcd(p: anytype, q: anytype) @TypeOf(p, q) {
    assert(p >= 1);
    assert(q >= 1);

    var a = p;
    var b = q;
    var c: @TypeOf(p, q) = undefined;

    while (b != 0) {
        c = b;
        b = @mod(a, b);
        a = c;
    }

    assert(a > 0);
    return a;
}

fn doTurn(r: anytype) !void {
    try r.update(1, 163); // Metronome
    try r.update(33, 256); // Critical Hit (67 Speed)
    try r.update(1, 39); // Damage roll
    try r.update(89, 128); // Thunder accuracy (178/256)
    try r.update(77, 256); // Thunder secondary proc
}

test Rational {
    inline for (.{ u64, u128, f64 }) |t| {
        var r: Rational(t) = .{};

        var c: t = 128;
        try r.update(c, 256);
        try doTurn(&r);

        r.reduce();
        try expectEqual(Rational(t){ .p = 75383, .q = 35550920704 }, r);

        try r.update(1, 4);
        if (t == u64) {
            try expectError(error.Overflow, doTurn(&r));
        } else {
            try doTurn(&r);
            r.reduce();
            try expectEqual(Rational(t){ .p = 5682596689, .q = 2527735925804191711232 }, r);
        }
    }
}

/// Adapter of std.math.big.Rational to the engines Rational interface.
pub const BigRational = struct {
    /// The underlying rational number.
    val: std.math.big.Rational,

    /// Create a new BigRational wrapper.  A small amount of memory will be allocated on
    /// initialization. Not default initialized to 1 - you must explicitly `reset` first.
    pub fn init(alloc: std.mem.Allocator) !BigRational {
        return BigRational{ .val = try std.math.big.Rational.init(alloc) };
    }

    /// Frees all memory associated with a Rational.
    pub fn deinit(r: *BigRational) void {
        r.val.deinit();
    }

    /// Resets the rational back to 1.
    pub fn reset(r: *BigRational) !void {
        try r.val.setInt(1);
    }

    /// Update the rational by multiplying its numerator by p and its denominator by q.
    /// Both p and q must be >= 1.
    pub fn update(r: *BigRational, p: anytype, q: anytype) !void {
        assert(p >= 1);
        assert(q >= 1);

        var s = try std.math.big.Rational.init(r.val.p.allocator);
        defer s.deinit();
        try s.setRatio(p, q);
        try r.val.mul(r.val, s);
    }
};

test BigRational {
    var r = try BigRational.init(std.testing.allocator);
    defer r.deinit();
    var s = try std.math.big.Rational.init(std.testing.allocator);
    defer s.deinit();

    try r.reset();

    var c: u8 = 128;
    try r.update(c, 256);
    try doTurn(&r);

    try s.setRatio(75383, 35550920704);
    try expect((try s.order(r.val)) == .eq);

    try r.update(1, 4);
    try doTurn(&r);

    try s.setRatio(5682596689, 2527735925804191711232);
    try expect((try s.order(r.val)) == .eq);
}
