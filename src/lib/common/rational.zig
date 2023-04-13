const builtin = @import("builtin");
const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const safe = switch (builtin.mode) {
    .ReleaseFast, .ReleaseSmall => true,
    else => false,
};

/// Specialization of a rational number used by the engine to compute probabilties.
pub fn Rational(comptime T: type) type {
    return extern struct {
        const Self = @This();

        /// Numerator. Must always be >= 1.
        p: T = 1,
        /// Denominator. Must always be >= 1.
        q: T = 1,

        /// Resets the rational back to 1.
        pub fn reset(r: *Self) void {
            r.p = 1;
            r.q = 1;
        }

        /// Update the rational by multiplying its numerator by p and its denominator by q.
        /// Both p and q must be >= 1, and if computable at comptime must have no common factors.
        pub fn update(r: *Self, p: anytype, q: anytype) (switch (@typeInfo(T)) {
            .Int => if (safe) error{Overflow} else error{},
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
                    if (safe) {
                        r.p = try std.math.mul(T, r.p, p);
                        r.q = try std.math.mul(T, r.q, q);
                    } else {
                        r.p *= p;
                        r.q *= q;
                    }
                },
                .Float => {
                    r.p *= p;
                    r.q *= q;

                    // We should always be dealing with whole numbers
                    assert(std.math.modf(r.p).fpart == 0);
                    assert(std.math.modf(r.q).fpart == 0);
                },
                else => unreachable,
            }
            r.reduce();
        }

        fn reduce(r: *Self) void {
            const d = gcd(r.p, r.q);

            assert(@mod(r.p, d) == 0);
            assert(@mod(r.q, d) == 0);

            r.p /= d;
            r.q /= d;

            assert(r.p >= 1);
            assert(r.q >= 1);
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

test Rational {
    inline for (.{ u64, u128, f64 }) |t| {
        var r: Rational(t) = .{};
        var acc: t = 178;

        try r.update(1, 2); // Speed Tie (128/256)
        {
            try r.update(1, 163); // Metronome
            try r.update(33, 256); // Critical Hit (67 Speed)
            try r.update(1, 39); // Damage roll
            try r.update(acc, 256); // Thunder accuracy (178/256)
            try r.update(77, 256); // Thunder secondary proc
        }

        try expectEqual(Rational(t){ .p = 75383, .q = 35550920704 }, r);
        if (!safe and t == u64) continue;

        try r.update(1, 4); // Paralysis check (1 - 192/256)
        {
            try r.update(1, 163); // Metronome
            try r.update(33, 256); // Critical Hit (67 Speed)
            try r.update(1, 39); // Damage roll
            if (t == u64) {
                try expectError(error.Overflow, r.update(acc, 256));
                continue;
            } else {
                try r.update(acc, 256); // Thunder accuracy (178/256)
            }

            try r.update(77, 256); // Thunder secondary proc
        }
        try expectEqual(Rational(t){ .p = 5682596689, .q = 2527735925804191711232 }, r);
    }
}
