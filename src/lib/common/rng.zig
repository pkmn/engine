const std = @import("std");
const build_options = @import("build_options");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const showdown = build_options.showdown;

pub fn Random(comptime gen: comptime_int) type {
    if (showdown) return PRNG(gen);

    const Source = switch (gen) {
        1, 2 => Gen12,
        3, 4 => Gen34,
        5, 6 => Gen56,
        else => unreachable,
    };

    return extern struct {
        const Self = @This();

        src: Source,

        pub fn next(self: *Self) Output(gen) {
            return @truncate(Output(gen), self.src.next());
        }
    };
}

pub fn PRNG(comptime gen: comptime_int) type {
    const divisor = getRangeDivisor(gen);
    return extern struct {
        const Self = @This();

        src: Gen56,

        pub fn init(seed: u64) Self {
            return .{ .src = .{ .seed = seed } };
        }

        pub fn next(self: *Self) Output(gen) {
            return @truncate(Output(gen), self.src.next());
        }

        pub fn advance(self: *Self, n: usize) void {
            var i: usize = 0;
            while (i < n) : (i += 1) _ = self.src.next();
        }

        pub fn range(self: *Self, comptime T: type, from: T, to: Bound(T)) T {
            return @truncate(T, @as(u64, self.src.next()) * (to - from) / divisor + from);
        }

        pub fn chance(
            self: *Self,
            comptime T: type,
            numerator: T,
            denominator: Bound(T),
        ) bool {
            assert(denominator > 0);
            return self.range(T, 0, denominator) < numerator;
        }

        pub fn newSeed(self: *Self) u64 {
            return (@as(u64, self.range(u16, 0, 0x10000)) << 48) |
                (@as(u64, self.range(u16, 0, 0x10000)) << 32) |
                (@as(u64, self.range(u16, 0, 0x10000)) << 16) |
                (@as(u64, self.range(u16, 0, 0x10000)));
        }
    };
}

test "PRNG" {
    var prng = PRNG(1){ .src = .{ .seed = 0x1234 } };
    try expectEqual(@as(u8, 50), prng.range(u8, 0, 256));
    try expectEqual(true, prng.chance(u8, 128, 256)); // 76 < 128
}

// https://pkmn.cc/pokered/engine/battle/core.asm#L6644-L6693
// https://pkmn.cc/pokecrystal/engine/battle/core.asm#L6922-L6938
pub const Gen12 = extern struct {
    seed: [10]u8,
    index: u8 = 0,

    comptime {
        assert(@sizeOf(Gen12) == 11);
    }

    pub fn percent(comptime p: comptime_int) u8 {
        return (p * 0xFF) / 100;
    }

    pub fn next(self: *Gen12) u8 {
        const val = 5 *% self.seed[self.index] +% 1;
        self.seed[self.index] = val;
        self.index = (self.index + 1) % 10;
        return val;
    }
};

test "Generation I & II" {
    const expected = [_]u8{ 6, 11, 16, 21, 26, 31, 36, 41, 46, 51, 31, 56, 81 };
    var rng = Gen12{ .seed = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } };
    for (expected) |e| {
        try expectEqual(e, rng.next());
    }

    try expectEqual(@as(u8, 16), Gen12.percent(6) + 1);
    try expectEqual(@as(u8, 16), Gen12.percent(7) - 1);
    try expectEqual(@as(u8, 128), Gen12.percent(50) + 1);
}

// https://pkmn.cc/pokeemerald/src/random.c
// https://pkmn.cc/pokediamond/arm9/src/math_util.c#L624-L630
pub const Gen34 = extern struct {
    seed: u32,

    comptime {
        assert(@sizeOf(Gen34) == 4);
    }

    pub fn next(self: *Gen34) u16 {
        self.advance();
        return @truncate(u16, self.seed >> 16);
    }

    fn advance(self: *Gen34) void {
        self.seed = 0x41C64E6D *% self.seed +% 0x00006073;
    }
};

// https://pkmn.cc/PokeFinder/Source/Tests/RNG/LCRNGTest.cpp
test "Generation III & IV" {
    const data = [_][3]u32{
        .{ 0x00000000, 5, 0x8E425287 }, .{ 0x00000000, 10, 0xEF2CF4B2 },
        .{ 0x80000000, 5, 0x0E425287 }, .{ 0x80000000, 10, 0x6F2CF4B2 },
    };
    for (data) |d| {
        var rng = Gen34{ .seed = d[0] };
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            _ = rng.next();
        }
        try expectEqual(d[2], rng.seed);
    }
}

pub const Gen56 = extern struct {
    seed: u64,

    comptime {
        assert(@sizeOf(Gen56) == 8);
    }

    pub fn next(self: *Gen56) u32 {
        self.advance();
        return @truncate(u32, self.seed >> 32);
    }

    fn advance(self: *Gen56) void {
        self.seed = 0x5D588B656C078965 *% self.seed +% 0x0000000000269EC3;
    }
};

// https://pkmn.cc/PokeFinder/Source/Tests/RNG/LCRNG64Test.cpp
test "Generation V & VI" {
    const data = [_][3]u64{
        .{ 0x0000000000000000, 5, 0xC83FB970153A9227 },
        .{ 0x0000000000000000, 10, 0x67795501267F125A },
        .{ 0x8000000000000000, 5, 0x483FB970153A9227 },
        .{ 0x8000000000000000, 10, 0xE7795501267F125A },
    };
    for (data) |d| {
        var rng = Gen56{ .seed = d[0] };
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            _ = rng.next();
        }
        try expectEqual(d[2], rng.seed);
    }
}

fn Output(comptime gen: comptime_int) type {
    return switch (gen) {
        1, 2 => u8,
        3, 4 => u16,
        5, 6 => u32,
        else => unreachable,
    };
}

fn Bound(comptime T: type) type {
    return std.math.IntFittingRange(0, std.math.maxInt(T) + 1);
}

fn getRangeDivisor(comptime gen: comptime_int) comptime_int {
    return switch (gen) {
        1, 2 => 0x100,
        3, 4 => 0x10000,
        5, 6 => 0x100000000,
        else => unreachable,
    };
}

pub fn FixedRNG(comptime gen: comptime_int, comptime len: usize) type {
    const divisor = getRangeDivisor(gen);

    return extern struct {
        const Self = @This();

        rolls: [len]Output(gen),
        index: usize = 0,

        pub fn next(self: *Self) Output(gen) {
            if (self.index >= self.rolls.len) @panic("Insufficient number of rolls provided");
            const roll = @truncate(Output(gen), self.rolls[self.index]);
            self.index += 1;
            return roll;
        }

        pub fn advance(self: *Self, n: usize) void {
            var i: usize = 0;
            while (i < n) : (i += 1) _ = self.next();
        }

        pub fn range(self: *Self, comptime T: type, from: T, to: Bound(T)) T {
            return @truncate(T, @as(u64, self.next()) * (to - from) / divisor + from);
        }

        pub fn chance(
            self: *Self,
            comptime T: type,
            numerator: T,
            denominator: Bound(T),
        ) bool {
            assert(denominator > 0);
            return self.range(T, 0, denominator) < numerator;
        }

        pub fn exhausted(self: Self) bool {
            return self.index == self.rolls.len;
        }
    };
}

test "FixedRNG" {
    const expected = [_]u8{ 42, 255, 0 };
    var rng = FixedRNG(1, expected.len){ .rolls = expected };
    for (expected) |e| {
        try expectEqual(e, rng.next());
    }
}
