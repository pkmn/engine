const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

// https://pkmn.cc/pokered/engine/battle/core.asm#L6644-L6693
// https://pkmn.cc/pokecrystal/engine/battle/core.asm#L6922-L6938
pub const Gen12 = packed struct {
    seed: u8,

    comptime {
        assert(@sizeOf(Gen12) == 1);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Gen12) == @sizeOf(Gen12) * 8);
    }

    pub fn next(self: *Gen12) u8 {
        self.advance();
        return self.seed;
    }

    fn advance(self: *Gen12) void {
        self.seed = 5 *% self.seed +% 1;
    }
};

test "Generation I & II" {
    const data = [_][3]u8{
        .{ 1, 1, 6 },   .{ 2, 3, 25 },
        .{ 3, 5, 172 }, .{ 4, 7, 255 },
        .{ 5, 9, 82 },  .{ 6, 11, 229 },
    };
    for (data) |d| {
        var rng = Gen12{ .seed = d[0] };
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            _ = rng.next();
        }
        try expectEqual(d[2], rng.seed);
    }
}

// https://pkmn.cc/pokeemerald/src/random.c
// https://pkmn.cc/pokediamond/arm9/src/math_util.c#L624-L630
pub const Gen34 = packed struct {
    seed: u32,

    comptime {
        assert(@sizeOf(Gen34) == 4);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Gen34) == @sizeOf(Gen34) * 8);
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

pub const Gen56 = packed struct {
    seed: u64,

    comptime {
        assert(@sizeOf(Gen56) == 8);
        // TODO: Safety check workaround for ziglang/zig#2627
        assert(@bitSizeOf(Gen56) == @sizeOf(Gen56) * 8);
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

// @test-only
pub const Random = struct {
    prng: std.rand.DefaultPrng,

    pub fn init(seed: u64) Random {
        return .{ .prng = std.rand.DefaultPrng.init(seed) };
    }

    pub fn int(self: *Random, comptime T: type) T {
        return self.prng.random().int(T);
    }

    pub fn chance(self: *Random, numerator: u16, denominator: u16) bool {
        assert(denominator > 0);
        return self.prng.random().uintLessThan(u16, denominator) < numerator;
    }

    pub fn range(self: *Random, comptime T: type, min: T, max: T) T {
        return self.prng.random().intRangeAtMostBiased(T, min, max);
    }
};
