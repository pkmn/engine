const std = @import("std");
const pkmn = @import("pkmn");

pub fn main() !void {
    // Set up required to be able to parse command line arguments
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Expect that we have been given a decimal seed as our only argument
    // (error handling left as an exercise for the reader...)
    const seed = try std.fmt.parseUnsigned(u64, args[2], 10);

    // Use Zig's system PRNG (pkmn.PRNG is another option with a slightly different API)
    var random = std.rand.DefaultPrng.init(seed).random();
    // Preallocate a small buffer for the choice options throughout the battle
    var options: [pkmn.MAX_OPTIONS_SIZE]pkmn.Choice = undefined;

    // pkmn.gen1.Battle can be tedious to initialize - the helper constructor used here
    // fills in missing fields with intelligent defaults to cut down on boilerplate.
    var battle = pkmn.gen1.helpers.Battle.init(
        random.int(u64),
        &.{
            .{ .species = .Bulbasaur, .moves = &.{ .SleepPowder, .SwordsDance, .RazorLeaf, .BodySlam } },
            .{ .species = .Charmander, .moves = &.{ .FireBlast, .FireSpin, .Slash, .Counter } },
            .{ .species = .Squirtle, .moves = &.{ .Surf, .Blizzard, .BodySlam, .Rest } },
            .{ .species = .Pikachu, .moves = &.{ .Thunderbolt, .ThunderWave, .Surf, .SeismicToss } },
            .{ .species = .Rattata, .moves = &.{ .SuperFang, .BodySlam, .Blizzard, .Thunderbolt } },
            .{ .species = .Pidgey, .moves = &.{ .DoubleEdge, .QuickAttack, .WingAttack, .MirrorMove } },
        },
        &.{
            .{ .species = .Tauros, .moves = &.{ .BodySlam, .HyperBeam, .Blizzard, .Earthquake } },
            .{ .species = .Chansey, .moves = &.{ .Reflect, .SeismicToss, .SoftBoiled, .ThunderWave } },
            .{ .species = .Snorlax, .moves = &.{ .BodySlam, .Reflect, .Rest, .IceBeam } },
            .{ .species = .Exeggutor, .moves = &.{ .SleepPowder, .Psychic, .Explosion, .DoubleEdge } },
            .{ .species = .Starmie, .moves = &.{ .Recover, .ThunderWave, .Blizzard, .Thunderbolt } },
            .{ .species = .Alakazam, .moves = &.{ .Psychic, .SeismicToss, .ThunderWave, .Recover } },
        },
    );

    // This example doesn't demonstrate trace log handling (which requires -Dtrace), but to use
    // it you need to create a protocol.Log implementation with a preallocated buffer
    // (pkmn.MAX_LOG_SIZE is guaranteed to be large enough for a single update) and then do
    // something with the data in the buffer after each update.
    const log = null;
    // var buf: [pkmn.MAX_LOG_SIZE]u8 = undefined;
    // var log = pkmn.protocol.FixedLog{ .writer = std.io.fixedBufferStream(&buf).writer() };

    var c1 = pkmn.Choice{};
    var c2 = pkmn.Choice{};

    var result = try battle.update(c1, c2, log);
    while (result.type == .None) : (result = try battle.update(c1, c2, log)) {
        // Here we would do something with the log data in buffer if -Dtrace were enabled

        // battle.choices determines what the possible options are - the simplest way to
        // choose and option here is to just use system PRNG to pick one at random
        c1 = options[random.uintLessThan(u8, battle.choices(.P1, result.p1, &options))];
        c2 = options[random.uintLessThan(u8, battle.choices(.P2, result.p2, &options))];
    }

    // The result is from the perspective of P1
    const msg = switch (result.type) {
        .Win => "won by Player A",
        .Lose => "won by Player B",
        .Tie => "ended in a tie",
        .Error => "encountered an error",
        else => unreachable,
    };

    std.debug.print("Battle {s} after {d} turns", .{ msg, battle.turn });
}
