const builtin = @import("builtin");
const std = @import("std");

const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const Int = if (@hasField(std.builtin.Type, "int")) .int else .Int;
const Float = if (@hasField(std.builtin.Type, "float")) .float else .Float;
const ComptimeInt =
    if (@hasField(std.builtin.Type, "comptime_int")) .comptime_int else .ComptimeInt;
const ComptimeFloat =
    if (@hasField(std.builtin.Type, "comptime_float")) .comptime_float else .ComptimeFloat;

/// Specialization of a rational number used by the engine to compute probabilties.
/// For performance reasons the rational is only reduced lazily and thus `reduce` must be
/// invoked explicitly before reading. Note that this laziness means that this implementation
/// sometimes overflows in places where an eager reduced implementation would not - to achieve
/// the same behavior as an eager implementation simply call `reduce` after each operation.
pub fn Rational(comptime T: type) type {
    // With floats we can't rely on an overflow bit to let us know when to reduce, so we
    // instead start reducing when we get sufficiently close to the limit of the mantissa
    // (in our domain we expect updates to involve numbers < 2**10, so we should be safe
    // not reducing before we are 2**10 away from "overflowing" the mantissa)
    const o = if (@typeInfo(T) == Float)
        std.math.pow(T, 2, std.math.floatMantissaBits(T) - 10)
    else
        0;

    const Err = switch (@typeInfo(T)) {
        Int => error{Overflow},
        Float => error{},
        else => unreachable,
    };

    // Zig doesn't allow integers > u128 in an extern struct...
    return if (@sizeOf(T) <= 16) extern struct {
        const Self = @This();

        /// Numerator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        p: T = 1,
        /// Denominator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        q: T = 1,

        /// Possible error returned by operations on the Rational.
        pub const Error = Err;

        /// Resets the rational back to 1.
        pub fn reset(r: *Self) void {
            r.p = 1;
            r.q = 1;
        }

        /// Update the rational by multiplying its numerator by p and its denominator by q.
        /// Both p and q must be >= 1, and if computable at comptime must have no common factors.
        pub fn update(r: *Self, p: anytype, q: anytype) Error!void {
            return update_(T, o, r, p, q);
        }

        /// Add two rationals using the identity (a/b) + (c/d) = (ad+bc)/(bd).
        pub fn add(r: *Self, s: anytype) Error!void {
            return add_(T, o, r, s);
        }

        /// Multiplies two rationals.
        pub fn mul(r: *Self, s: anytype) Error!void {
            return mul_(T, o, r, s);
        }

        /// Compares two rationals using the identity (a/b) > (c/d) => ad > bc
        pub fn cmp(r: *Self, s: anytype) Error!std.math.Order {
            return cmp_(T, o, r, s);
        }

        /// Normalize the rational by reducing by the greatest common divisor.
        pub fn reduce(r: *Self) void {
            reduce_(r);
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            opts: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = .{ fmt, opts };
            try writer.print("{d}/{d}", .{ self.p, self.q });
        }
    } else struct {
        const Self = @This();

        /// Numerator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        p: T = 1,
        /// Denominator. Must always be >= 1. Not guaranteed to be reduced in all cases.
        q: T = 1,

        /// Possible error returned by operations on the Rational.
        pub const Error = Err;

        /// Resets the rational back to 1.
        pub fn reset(r: *Self) void {
            r.p = 1;
            r.q = 1;
        }

        /// Update the rational by multiplying its numerator by p and its denominator by q.
        /// Both p and q must be >= 1, and if computable at comptime must have no common factors.
        pub fn update(r: *Self, p: anytype, q: anytype) Error!void {
            return update_(T, o, r, p, q);
        }

        /// Add two rationals using the identity (a/b) + (c/d) = (ad+bc)/(bd).
        pub fn add(r: *Self, s: anytype) Error!void {
            return add_(T, o, r, s);
        }

        /// Multiplies two rationals.
        pub fn mul(r: *Self, s: anytype) Error!void {
            return mul_(T, o, r, s);
        }

        /// Compares two rationals using the identity (a/b) > (c/d) => ad > bc
        pub fn cmp(r: *Self, s: anytype) Error!std.math.Order {
            return cmp_(T, o, r, s);
        }

        /// Normalize the rational by reducing by the greatest common divisor.
        pub fn reduce(r: *Self) void {
            reduce_(r);
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            opts: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = .{ fmt, opts };
            try writer.print("{d}/{d}", .{ self.p, self.q });
        }
    };
}

fn update_(comptime T: type, comptime o: comptime_int, r: anytype, p: anytype, q: anytype) !void {
    // std.debug.print("({d}/{d}) * ", .{ p, q }); // DEBUG
    assert(p >= 1);
    assert(q >= 1);

    // If our parameters are not fully reduced they may prematurely
    // cause overflow/loss of precision after the multiplication below
    assert(switch (@typeInfo(@TypeOf(p, q))) {
        ComptimeInt, ComptimeFloat => comptime gcd(p, q),
        else => 1,
    } == 1);

    switch (@typeInfo(T)) {
        Int => {
            // Greedily attempt to multiply and if it fails, reduce and try again
            multiplication(T, r, p, q) catch |err| switch (err) {
                error.Overflow => {
                    r.reduce();
                    try multiplication(T, r, p, q);
                },
                else => unreachable,
            };
        },
        Float => {
            // Reduce in situations where we're likely to start losing precision
            if (r.q > o or r.p > o) r.reduce();

            r.p *= switch (@typeInfo(@TypeOf(p))) {
                Float, ComptimeFloat => p,
                else => @floatFromInt(p),
            };
            r.q *= switch (@typeInfo(@TypeOf(q))) {
                Float, ComptimeFloat => q,
                else => @floatFromInt(q),
            };

            // We should always be dealing with whole numbers
            assert(std.math.modf(r.p).fpart == 0);
            assert(std.math.modf(r.q).fpart == 0);
        },
        else => unreachable,
    }
}

fn add_(comptime T: type, comptime o: comptime_int, r: anytype, s: anytype) !void {
    switch (@typeInfo(T)) {
        Int => {
            if (r.q == s.q) {
                r.p = std.math.add(T, r.p, s.p) catch |err| switch (err) {
                    error.Overflow => val: {
                        r.reduce();
                        s.reduce();
                        break :val try std.math.add(T, r.p, s.p);
                    },
                    else => unreachable,
                };
            } else {
                addition(T, r, s.p, s.q) catch |err| switch (err) {
                    error.Overflow => {
                        r.reduce();
                        s.reduce();
                        try addition(T, r, s.p, s.q);
                    },
                    else => unreachable,
                };
            }
        },
        Float => {
            if (r.q == s.q) {
                if (r.p > o) r.reduce();
                if (s.p > o) s.reduce();

                r.p += s.p;
            } else {
                // Always reduce to minimize loss of precision from the multiplications
                r.reduce();
                s.reduce();

                r.p = (r.p * s.q) + (r.q * s.p);
                r.q *= s.q;
            }

            assert(std.math.modf(r.p).fpart == 0);
            assert(std.math.modf(r.q).fpart == 0);
        },
        else => unreachable,
    }
}

fn mul_(comptime T: type, comptime o: comptime_int, r: anytype, s: anytype) !void {
    switch (@typeInfo(T)) {
        Int => {
            multiplication(T, r, s.p, s.q) catch |err| switch (err) {
                error.Overflow => {
                    r.reduce();
                    s.reduce();
                    try multiplication(T, r, s.p, s.q);
                },
                else => unreachable,
            };
        },
        Float => {
            if (r.q > o or r.p > o) r.reduce();
            if (s.q > o or s.p > o) s.reduce();

            r.p *= s.p;
            r.q *= s.q;

            assert(std.math.modf(r.p).fpart == 0);
            assert(std.math.modf(r.q).fpart == 0);
        },
        else => unreachable,
    }
}

fn cmp_(comptime T: type, comptime o: comptime_int, r: anytype, s: anytype) !std.math.Order {
    switch (@typeInfo(T)) {
        Int => {
            r.reduce();
            s.reduce();

            const ad = std.math.mul(T, r.p, s.q) catch |err| switch (err) {
                error.Overflow => reduce: {
                    r.reduce();
                    s.reduce();
                    break :reduce try std.math.mul(T, r.p, s.q);
                },
                else => unreachable,
            };
            const bc = std.math.mul(T, r.q, s.p) catch |err| switch (err) {
                error.Overflow => reduce: {
                    r.reduce();
                    s.reduce();
                    break :reduce try std.math.mul(T, r.q, s.p);
                },
                else => unreachable,
            };

            return std.math.order(ad, bc);
        },
        Float => {
            if (r.q > o or r.p > o) r.reduce();
            if (s.q > o or s.p > o) s.reduce();

            const ad: T = r.p * s.q;
            const bc: T = r.q * s.p;

            return std.math.order(ad, bc);
        },
        else => unreachable,
    }
}

fn reduce_(r: anytype) void {
    const d = gcd(r.p, r.q);
    if (d == 1) return;

    assert(@mod(r.p, d) == 0);
    assert(@mod(r.q, d) == 0);

    r.p /= d;
    r.q /= d;

    assert(r.p >= 1);
    assert(r.q >= 1);
}

fn multiplication(comptime T: type, r: anytype, p: anytype, q: anytype) !void {
    r.p = try std.math.mul(T, r.p, p);
    r.q = try std.math.mul(T, r.q, q);
}

fn addition(comptime T: type, r: anytype, p: anytype, q: anytype) !void {
    // (a/b) + (c/d) = (ad+bc)/(bd)
    const d = try std.math.mul(T, r.q, q);
    const n1 = try std.math.mul(T, r.p, q);
    const n2 = try std.math.mul(T, r.q, p);

    r.p = try std.math.add(T, n1, n2);
    r.q = d;
}

fn gcd(p: anytype, q: anytype) @TypeOf(p, q) {
    assert(p >= 1);
    assert(q >= 1);

    // convert comptime_int to a sized integer within this function so that @ctz will work
    const T = switch (@TypeOf(p, q)) {
        comptime_int => std.math.IntFittingRange(@min(p, q), @max(p, q)),
        else => |U| U,
    };

    switch (@typeInfo(T)) {
        Int => {
            // std.math.gcd but without some checks because we have a stricter range
            var x: T = @intCast(p);
            var y: T = @intCast(q);

            const xz = @ctz(x);
            const yz = @ctz(y);
            const shift = @min(xz, yz);
            x >>= @intCast(xz);
            y >>= @intCast(yz);

            var diff = y -% x;
            while (diff != 0) : (diff = y -% x) {
                const zeros = @ctz(diff);
                if (x > y) diff = -%diff;
                y = @min(x, y);
                x = diff >> @intCast(zeros);
            }

            const result = y << @intCast(shift);
            assert(result > 0);
            return result;
        },
        else => {
            var a = p;
            var b = q;
            var c: T = undefined;

            while (b != 0) {
                c = b;
                b = @mod(a, b);
                a = c;
            }

            assert(a > 0);
            return a;
        },
    }
}

test gcd {
    const seed = if (@hasDecl(std.testing, "random_seed")) std.testing.random_seed else 0x12345678;
    var prng = (if (@hasDecl(std, "Random")) std.Random else std.rand).DefaultPrng.init(seed);
    var random = prng.random();

    for (0..1000) |_| {
        const a = random.int(u32);
        const b = random.int(u32);
        if (a == 0 or b == 0) continue;

        try expectEqual(
            gcd(a, b),
            @as(u32, @intFromFloat(gcd(@as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))))),
        );
    }

    try expectEqual(gcd(300_000, @as(u32, 2_300_000)), 100_000); // NB: @ctz requires an @intCast
}

fn doTurn(r: anytype) !void {
    try r.update(1, 163); // Metronome
    try r.update(33, 256); // Critical Hit (67 Speed)
    try r.update(1, 39); // Damage roll
    try r.update(89, 128); // Thunder accuracy (178/256)
    try r.update(77, 256); // Thunder secondary proc
}

test Rational {
    inline for (.{ u64, u128, u256, f64 }) |t| {
        const R = Rational(t);
        var r: R = .{};

        var c: t = 128;
        _ = &c;

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

        r.reset();

        var s = R{ .p = 10, .q = 13 };
        try r.mul(&s);
        s = R{ .p = 3, .q = 4 };
        try r.mul(&s);
        try expectEqual(Rational(t){ .p = 30, .q = 52 }, r);

        s = R{ .p = 1, .q = 3 };
        try r.add(&s);
        r.reduce();
        try expectEqual(Rational(t){ .p = 71, .q = 78 }, r);

        var h = Rational(t){ .p = 3, .q = 5 };
        // Same Denominator
        var cmptr = Rational(t){ .p = 2, .q = 5 };
        try expectEqual(h.cmp(&cmptr), .gt);
        cmptr = R{ .p = 4, .q = 5 };
        try expectEqual(h.cmp(&cmptr), .lt);

        // Same Numerator
        cmptr = R{ .p = 3, .q = 6 };
        try expectEqual(h.cmp(&cmptr), .gt);
        cmptr = R{ .p = 3, .q = 4 };
        try expectEqual(h.cmp(&cmptr), .lt);

        cmptr = R{ .p = 3, .q = 5 };
        try expectEqual(h.cmp(&cmptr), .eq);

        try doTurn(&h);
        cmptr = R{ .p = 4567216874, .q = 89124781931235 };
        if (t == u64) {
            try expectEqual(h.cmp(&cmptr), error.Overflow);
        } else {
            try expectEqual(h.cmp(&cmptr), .lt);
        }
    }
}

/// Adapter of std.math.big.Rational to the engines Rational interface.
pub const BigRational = struct {
    /// The underlying rational number.
    val: std.math.big.Rational,

    /// Possible error returned by operations on the rational.
    pub const Error = error{OutOfMemory};

    /// Create a new BigRational wrapper.  A small amount of memory will be allocated on
    /// initialization. Not default initialized to 1 - you must explicitly `reset` first.
    pub fn init(alloc: std.mem.Allocator) !BigRational {
        return .{ .val = try std.math.big.Rational.init(alloc) };
    }

    /// Frees all memory associated with a rational.
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

    /// Adds two rationals.
    pub fn add(r: *BigRational, s: anytype) !void {
        if (@hasField(@TypeOf(s.*), "val")) {
            try r.val.add(r.val, s.val);
        } else {
            var t = try std.math.big.Rational.init(r.val.p.allocator);
            defer t.deinit();
            try t.setRatio(s.p, s.q);
            try r.val.add(r.val, t);
        }
    }

    /// Multiplies two rationals.
    pub fn mul(r: *BigRational, s: *const BigRational) !void {
        try r.val.mul(r.val, s.val);
    }

    pub fn cmp(r: *BigRational, s: *const BigRational) Error!std.math.Order {
        return std.math.big.Rational.order(r.val, s.val);
    }
};

test BigRational {
    var r = try BigRational.init(std.testing.allocator);
    defer r.deinit();
    var s = try std.math.big.Rational.init(std.testing.allocator);
    defer s.deinit();

    try r.reset();

    var c: u8 = 128;
    _ = &c;

    try r.update(c, 256);
    try doTurn(&r);

    try s.setRatio(75383, 35550920704);
    try expect((try s.order(r.val)) == .eq);

    try r.update(1, 4);
    try doTurn(&r);

    try s.setRatio(5682596689, 2527735925804191711232);
    try expect((try s.order(r.val)) == .eq);

    try r.reset();

    var t = try BigRational.init(std.testing.allocator);
    defer t.deinit();

    try t.val.setRatio(10, 13);
    try r.mul(&t);
    try t.val.setRatio(3, 4);
    try r.mul(&t);

    try s.setRatio(15, 26);
    try expect((try s.order(r.val)) == .eq);

    try t.val.setRatio(1, 3);
    try r.add(&t);

    try s.setRatio(71, 78);
    try expect((try s.order(r.val)) == .eq);

    try expectEqual(t.cmp(&r), .lt);
    try expectEqual(r.cmp(&t), .gt);
}

test "minimum" {
    // TODO: ziglang/zig#21069
    if (builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall) {
        return error.SkipZigTest;
    }
    var r = try BigRational.init(std.testing.allocator);
    defer r.deinit();
    var s = try std.math.big.Rational.init(std.testing.allocator);
    defer s.deinit();

    try r.reset();

    try r.update(1, 2); // Speed Tie
    for (0..2) |_| {
        try r.update(1, 2); // Confusion
        try r.update(1, 2); // Infatuation
        try r.update(3, 4); // Paralysis
        // Population Bomb
        for (0..10) |_| {
            try r.update(9, 10); // Accuracy
            try r.update(1, 15); // Damage roll
            try r.update(1, 24); // Critical Hit
            try r.update(9, 10); // King's Rock non-proc
        }
    }

    const ZEROS = std.math.pow(u310, 10, 31);
    const n = 36472996377170786403;
    const d: u310 = 146267071761884981524886149560653378220687632500762654519853056 * ZEROS;
    try s.setRatio(n, d);
    try expect((try s.order(r.val)) == .eq);
}
