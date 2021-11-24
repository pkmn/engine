const std = @import("std");

const expectEqual = std.testing.expectEqual;

// https://pkmn.cc/pokered/engine/math/random.asm
// https://pkmn.cc/pokecrystal/engine/math/random.asm
pub inline fn gen12(seed: u8) u8 {
    return 5 *% seed +% 1;
}

test "Generation I & II" {
    const data = [_][3]u8{
        .{ 1, 1, 6 },   .{ 2, 3, 25 },
        .{ 3, 5, 172 }, .{ 4, 7, 255 },
        .{ 5, 9, 82 },  .{ 6, 11, 229 },
    };
    for (data) |d| {
        var seed = d[0];
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            seed = gen12(seed);
        }
        try expectEqual(d[2], seed);
    }
}

// https://pkmn.cc/pokeemerald/src/random.c
// https://pkmn.cc/pokediamond/arm9/src/math_util.c#L624-L630
pub inline fn gen34(seed: u32) u32 {
    return 0x41C64E6D *% seed +% 0x00006073;
}

// https://pkmn.cc/PokeFinder/Source/Tests/RNG/LCRNGTest.cpp
test "Generation III & IV" {
    const data = [_][3]u32{
        .{ 0x00000000, 5, 0x8E425287 }, .{ 0x00000000, 10, 0xEF2CF4B2 },
        .{ 0x80000000, 5, 0x0E425287 }, .{ 0x80000000, 10, 0x6F2CF4B2 },
    };
    for (data) |d| {
        var seed = d[0];
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            seed = gen34(seed);
        }
        try expectEqual(d[2], seed);
    }
}

pub inline fn gen56(seed: u64) u64 {
    return 0x5D588B656C078965 *% seed +% 0x0000000000269EC3;
}

// https://pkmn.cc/PokeFinder/Source/Tests/RNG/LCRNG64Test.cpp
test "Generation V & VI" {
    const data = [_][3]u64{
        .{ 0x0000000000000000, 5, 0xC83FB970153A9227 },
        .{ 0x0000000000000000, 10, 0x67795501267F125A },
        .{ 0x8000000000000000, 5, 0x483FB970153A9227 },
        .{ 0x8000000000000000, 10, 0xE7795501267F125A },
    };
    for (data) |d| {
        var seed = d[0];
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            seed = gen56(seed);
        }
        try expectEqual(d[2], seed);
    }
}
