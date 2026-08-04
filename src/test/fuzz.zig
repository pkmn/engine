const builtin = @import("builtin");
const pkmn = @import("pkmn");
const std = @import("std");

const Debug: std.builtin.OptimizeMode =
    if (@hasDecl(std.builtin.OptimizeMode, "Debug")) .debug else .Debug;

pub const pkmn_options = pkmn.Options{ .internal = true };

const Frame = struct {
    log: []u8 = &.{},
    state: []u8,
    result: pkmn.Result = pkmn.Result.Default,
    c1: pkmn.Choice = .{},
    c2: pkmn.Choice = .{},
    extra: []u8,
};

var gen: u8 = 0;
var last: ?u64 = null;
var initial: []u8 = &.{};
var writer: ?std.Io.Writer.Allocating = null;
var frames: ?std.array_list.Aligned(Frame, null) = null;

const transitions = true; // DEBUG

const showdown = pkmn.options.showdown;
const chance = pkmn.options.chance;

const endian = builtin.cpu.arch.endian();

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    var err = std.Io.File.stderr().writer(init.io, &.{});

    if (args.len != 1 and (args.len < 3 or args.len > 5)) usageAndExit(&err.interface, args[0]);

    if (args.len > 1) {
        gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
            errorAndExit(&err.interface, "gen", args[1], args[0]);
        if (gen < 1 or gen > 9) errorAndExit(&err.interface, "gen", args[1], args[0]);

        const end = args[2].len - 1;
        const mod: usize = switch (args[2][end]) {
            's' => 1,
            'm' => std.time.s_per_min,
            'h' => std.time.s_per_hour,
            'd' => std.time.s_per_day,
            else => errorAndExit(&err.interface, "duration", args[2], args[0]),
        };
        const duration = mod * (std.fmt.parseUnsigned(usize, args[2][0..end], 10) catch
            errorAndExit(&err.interface, "duration", args[2], args[0])) * std.time.ns_per_s;

        const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
            errorAndExit(&err.interface, "seed", args[3], args[0]) else seed: {
            var secret: [std.Random.DefaultCsprng.secret_seed_length]u8 = undefined;
            init.io.random(&secret);
            var csprng = std.Random.DefaultCsprng.init(secret);
            const random = csprng.random();
            break :seed random.int(usize);
        };

        try fuzz(init.io, allocator, seed, duration);
    } else {
        var in: [4096]u8 = undefined;
        var stdin = std.Io.File.stdin().reader(init.io, &in);
        var r = &stdin.interface;

        if (try r.takeByte() != @intFromBool(showdown)) {
            err.interface.print("Cannot process frame from -Dshowdown={}\n", .{!showdown}) catch {};
            usageAndExit(&err.interface, args[0]);
        }

        gen = try r.takeByte();
        if (gen < 1 or gen > 9) errorAndExit(&err.interface, "gen", gen, args[0]);

        const size = try r.takeInt(i16, endian);
        if (size != -1 and size != 0) errorAndExit(&err.interface, "log size", size, args[0]);

        _ = try r.takeInt(i32, endian);
        _ = try switch (gen) {
            1 => r.takeStruct(pkmn.gen1.Battle(pkmn.gen1.PRNG), endian),
            else => unreachable,
        };
        if (size != 0) _ = try r.takeByte();

        const durations = try switch (gen) {
            1 => r.takeStruct(pkmn.gen1.chance.Durations, endian),
            else => unreachable,
        };
        var battle = try switch (gen) {
            1 => r.takeStruct(pkmn.gen1.Battle(pkmn.gen1.PRNG), endian),
            else => unreachable,
        };
        _ = try r.takeStruct(pkmn.Result, endian);
        const c1 = try r.takeStruct(pkmn.Choice, endian);
        const c2 = try r.takeStruct(pkmn.Choice, endian);

        switch (gen) {
            1 => {
                var chance_ = if (chance) pkmn.gen1.Chance(pkmn.Rational(u128)){
                    .probability = .{},
                    .durations = durations,
                } else pkmn.gen1.chance.NULL;
                const options = pkmn.battle.options(
                    pkmn.protocol.NULL,
                    &chance_,
                    pkmn.gen1.calc.NULL,
                );
                const result = update(&battle, c1, c2, &options, allocator);
                std.debug.assert(!showdown or result.type != .Error);
            },
            else => unreachable,
        }
    }
}

pub fn fuzz(io: std.Io, allocator: std.mem.Allocator, seed: u64, duration: usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    const save = pkmn.options.log and builtin.mode == Debug;

    var random = pkmn.PSRNG.init(seed);

    var elapsed = std.Io.Clock.awake.now(io);
    while (elapsed.untilNow(io, .awake).toNanoseconds() < duration) {
        last = random.src.seed;

        const cleric = showdown;
        var battle = switch (gen) {
            1 => pkmn.gen1.helpers.Battle.random(&random, .{
                .cleric = cleric,
                .block = false,
                .durations = true,
            }),
            else => unreachable,
        };
        const max = switch (gen) {
            1 => pkmn.gen1.MAX_LOGS,
            else => unreachable,
        };

        var log: ?pkmn.protocol.Log(*std.Io.Writer) = null;
        if (save) {
            if (frames != null) deinit(allocator);
            initial = try allocator.dupe(u8, std.mem.toBytes(battle)[0..]);
            frames = std.array_list.Aligned(Frame, null).empty;
            writer = std.Io.Writer.Allocating.init(allocator);
            log = pkmn.protocol.Log(*std.Io.Writer){ .writer = &writer.?.writer };
        }

        std.debug.assert(!showdown or battle.side(.P1).get(1).hp > 0);
        std.debug.assert(!showdown or battle.side(.P2).get(1).hp > 0);

        switch (gen) {
            1 => {
                var chance_ = if (chance) chance: {
                    var durations = pkmn.gen1.chance.Durations{};
                    // Pokémon which start the battle sleeping must seen prior .started or
                    // .continuing observations which would have set their counter >= 1
                    if (!cleric) {
                        inline for (.{ .P1, .P2 }) |player| {
                            var d = durations.get(player);
                            for (battle.side(player).pokemon, 0..) |p, i| {
                                if (pkmn.gen1.Status.is(p.status, .SLP)) {
                                    d.sleeps = pkmn.Array(6, u3).set(d.sleeps, i, 1);
                                }
                            }
                        }
                    }
                    break :chance pkmn.gen1.Chance(pkmn.Rational(u128)){
                        .probability = .{},
                        .durations = durations,
                    };
                } else pkmn.gen1.chance.NULL;
                const options = pkmn.battle.options(
                    if (save) log.? else pkmn.protocol.NULL,
                    &chance_,
                    pkmn.gen1.calc.NULL,
                );
                try run(&battle, &random, save, max, allocator, options);
            },
            else => unreachable,
        }
    }
    if (frames != null) deinit(allocator);
}

fn run(
    battle: anytype,
    random: *pkmn.PSRNG,
    save: bool,
    max: usize,
    allocator: std.mem.Allocator,
    options: anytype,
) !void {
    var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;

    var c1 = pkmn.Choice{};
    var c2 = pkmn.Choice{};

    var p1 = pkmn.PSRNG.init(random.newSeed());
    var p2 = pkmn.PSRNG.init(random.newSeed());

    var result = update(battle, c1, c2, &options, allocator);
    while (result.type == .None) : (result = update(battle, c1, c2, &options, allocator)) {
        var n = battle.choices(.P1, result.p1, &choices);
        if (n == 0) break;
        c1 = choices[p1.range(u8, 0, n)];
        n = battle.choices(.P2, result.p2, &choices);
        if (n == 0) break;
        c2 = choices[p2.range(u8, 0, n)];

        if (save) {
            std.debug.assert(writer.?.written().len <= max);
            try frames.?.append(allocator, .{
                .result = result,
                .c1 = c1,
                .c2 = c2,
                .state = try allocator.dupe(u8, std.mem.toBytes(battle.*)[0..]),
                .log = try writer.?.toOwnedSlice(),
                .extra = if (chance)
                    try allocator.dupe(u8, std.mem.toBytes(options.chance.durations)[0..])
                else
                    &.{},
            });
        }
    }

    std.debug.assert(!showdown or result.type != .Error);
}

pub fn update(
    battle: anytype,
    c1: pkmn.Choice,
    c2: pkmn.Choice,
    options: anytype,
    allocator: std.mem.Allocator,
) pkmn.Result {
    if (!chance) return battle.update(c1, c2, options) catch unreachable;
    var discarding: std.Io.Writer.Discarding = .init(&.{});
    const drop = &discarding.writer;
    // DEBUG
    // const stderr = std.Io.File.stderr().writer(std.testing.io, &.{});
    // const writer = &stderr.interface;
    return switch (gen) {
        1 => pkmn.gen1.calc.update(battle, c1, c2, options, allocator, drop, drop, transitions),
        else => unreachable,
    } catch unreachable;
}

fn errorAndExit(err: *std.Io.Writer, msg: []const u8, arg: anytype, cmd: []const u8) noreturn {
    err.print("Invalid {s}: {any}\n", .{ msg, arg }) catch {};
    usageAndExit(err, cmd);
}

fn usageAndExit(err: *std.Io.Writer, cmd: []const u8) noreturn {
    err.print("Usage: {s} <GEN> <DURATION> <SEED?>\n", .{cmd}) catch {};
    std.process.exit(1);
}

fn deinit(allocator: std.mem.Allocator) void {
    std.debug.assert(initial.len > 0);
    allocator.free(initial);
    for (frames.?.items) |frame| {
        allocator.free(frame.state);
        allocator.free(frame.log);
        allocator.free(frame.extra);
    }
    frames.?.deinit(allocator);
    std.debug.assert(writer != null);
    writer.?.deinit();
}

fn dump(seed: u64) !void {
    const io = std.Options.debug_io;
    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);

    if (try std.Io.File.stdout().isTty(io) or builtin.mode != Debug) {
        try stdout.interface.print("0x{X}\n", .{seed});
    } else {
        try stdout.interface.writeInt(u64, seed, endian);
        try display(&stdout.interface, false);
    }
    try stdout.interface.flush();

    // Write the last state information to the logs/ directory
    // so that it can easily be turned into a regression testcase
    var n: [1024]u8 = undefined;
    const ext = if (showdown) "showdown" else "pkmn";
    const name = try std.fmt.bufPrint(&n, "logs/0x{X}.{s}.bin", .{ seed, ext });

    const dir = std.Io.Dir.cwd();
    dir.createDir(io, "logs", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const file = dir.createFile(io, name, .{}) catch |err| switch (err) {
        error.PathAlreadyExists => try dir.openFile(io, name, .{}),
        else => return err,
    };
    defer file.close(io);
    var w = file.writer(io, &buf);
    try display(&w.interface, true);
    try w.flush();

    var p: [1024]u8 = undefined;
    const size = try file.realPath(io, &p);
    dir.deleteFile(io, "logs/dump.bin") catch {};
    dir.symLink(io, p[0..size], "logs/dump.bin", .{}) catch return;
}

fn display(w: *std.Io.Writer, final: bool) !void {
    try w.writeByte(@intFromBool(showdown));
    try w.writeByte(gen);
    try w.writeInt(i16, -1, endian);
    try w.writeInt(i32, if (final) switch (gen) {
        1 => @as(i32, @intCast(@sizeOf(pkmn.gen1.chance.Durations))),
        else => unreachable,
    } else @as(i32, 0), endian);
    try w.writeAll(initial);

    if (frames) |fs| {
        if (final) {
            if (fs.items.len == 0) return;
            const f = fs.items[fs.items.len - 1];
            try w.writeByte(0);
            try w.writeAll(f.extra);
            try w.writeAll(f.state);
            try w.writeStruct(f.result, endian);
            try w.writeStruct(f.c1, endian);
            try w.writeStruct(f.c2, endian);
        } else {
            for (fs.items) |f| {
                try w.writeAll(f.log);
                try w.writeAll(f.state);
                try w.writeStruct(f.result, endian);
                try w.writeStruct(f.c1, endian);
                try w.writeStruct(f.c2, endian);
            }
        }
    }
    if (writer) |*b| try w.writeAll(b.written());
}

pub const panic = std.debug.FullPanic(panicFn);

fn panicFn(msg: []const u8, ra: ?usize) noreturn {
    @branchHint(.cold);
    if (last) |seed| dump(seed) catch unreachable;
    std.debug.defaultPanic(msg, ra);
}
