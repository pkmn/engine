const std = @import("std");

const pkmn = @import("pkmn");
const helpers = @import("helpers");
const rng = @import("common").rng;

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // const args = try std.process.argsAlloc(allocator);

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    var battle = helpers.Battle.random(&rng.Random.init(0x31415926), false);
    try w.writeStruct(battle);
    try buf.flush();

    const serialized = std.mem.toBytes(battle);
    const deserialized = std.mem.bytesToValue(@TypeOf(battle), &serialized);
    try std.testing.expectEqual(battle, deserialized);
}
