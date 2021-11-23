const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub inline fn gb(seed: u8) u8 {
    return 5 *% seed +% 1;
}

test "GB" {
    const data = [_][3]u8{
        .{ 1, 1, 6 },   .{ 2, 3, 25 },
        .{ 3, 5, 172 }, .{ 4, 7, 255 },
        .{ 5, 9, 82 },  .{ 6, 11, 229 },
    };
    for (data) |d| {
        var seed = d[0];
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            seed = gb(seed);
        }
        try expectEqual(d[2], seed);
    }
}

pub inline fn gba(seed: u32) u32 {
    return 0x41C64E6D *% seed +% 0x00006073;
}

// https://github.com/Admiral-Fish/PokeFinder/blob/master/Source/Tests/RNG/LCRNGTest.cpp
test "GBA" {
    const data = [_][3]u32{
        .{ 0x00000000, 5, 0x8E425287 }, .{ 0x00000000, 10, 0xEF2CF4B2 },
        .{ 0x80000000, 5, 0x0E425287 }, .{ 0x80000000, 10, 0x6F2CF4B2 },
    };
    for (data) |d| {
        var seed = d[0];
        var i: usize = 0;
        while (i < d[1]) : (i += 1) {
            seed = gba(seed);
        }
        try expectEqual(d[2], seed);
    }
}
