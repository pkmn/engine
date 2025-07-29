const builtin = @import("builtin");
const pkmn = @import("pkmn");
const std = @import("std");

const writergate = @hasDecl(std.fs.File, "stdout");

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
var buf: ?std.ArrayList(u8) = null;
var frames: ?std.ArrayList(Frame) = null;

const transitions = true; // DEBUG

const showdown = pkmn.options.showdown;
const chance = pkmn.options.chance;

const endian = builtin.cpu.arch.endian();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 1 and (args.len < 3 or args.len > 5)) usageAndExit(args[0]);

    if (args.len > 1) {
        gen = std.fmt.parseUnsigned(u8, args[1], 10) catch
            errorAndExit("gen", args[1], args[0]);
        if (gen < 1 or gen > 9) errorAndExit("gen", args[1], args[0]);

        const end = args[2].len - 1;
        const mod: usize = switch (args[2][end]) {
            's' => 1,
            'm' => std.time.s_per_min,
            'h' => std.time.s_per_hour,
            'd' => std.time.s_per_day,
            else => errorAndExit("duration", args[2], args[0]),
        };
        const duration = mod * (std.fmt.parseUnsigned(usize, args[2][0..end], 10) catch
            errorAndExit("duration", args[2], args[0])) * std.time.ns_per_s;

        const seed = if (args.len > 3) std.fmt.parseUnsigned(u64, args[3], 0) catch
            errorAndExit("seed", args[3], args[0]) else seed: {
            const Random = if (@hasDecl(std, "Random")) std.Random else std.rand;
            var secret: [Random.DefaultCsprng.secret_seed_length]u8 = undefined;
            std.crypto.random.bytes(&secret);
            var csprng = Random.DefaultCsprng.init(secret);
            const random = csprng.random();
            break :seed random.int(usize);
        };

        try fuzz(allocator, seed, duration);
    } else {
        var in: if (writergate) [4096]u8 else void = undefined;
        var stdin = if (writergate) std.fs.File.stdin().reader(&in) else std.io.getStdIn();
        const r = if (writergate) &stdin.interface else stdin.reader();

        if (try takeByte(r) != @intFromBool(showdown)) {
            var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
            var err = if (writergate) &stderr.interface else stderr.writer();
            err.print("Cannot process frame from -Dshowdown={}\n", .{!showdown}) catch {};
            usageAndExit(args[0]);
        }

        gen = try takeByte(r);
        if (gen < 1 or gen > 9) errorAndExit("gen", gen, args[0]);

        const size = try takeInt(r, i16, endian);
        if (size != -1 and size != 0) errorAndExit("log size", size, args[0]);

        _ = try takeInt(r, i32, endian);
        _ = try switch (gen) {
            1 => takeStruct(r, pkmn.gen1.Battle(pkmn.gen1.PRNG)),
            else => unreachable,
        };
        if (size != 0) _ = try takeByte(r);

        const durations = try switch (gen) {
            1 => takeStruct(r, pkmn.gen1.chance.Durations),
            else => unreachable,
        };
        var battle = try switch (gen) {
            1 => takeStruct(r, pkmn.gen1.Battle(pkmn.gen1.PRNG)),
            else => unreachable,
        };
        _ = try takeStruct(r, pkmn.Result);
        const c1 = try takeStruct(r, pkmn.Choice);
        const c2 = try takeStruct(r, pkmn.Choice);

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

pub fn fuzz(allocator: std.mem.Allocator, seed: u64, duration: usize) !void {
    std.debug.assert(gen >= 1 and gen <= 9);

    const save = pkmn.options.log and builtin.mode == .Debug;

    var random = pkmn.PSRNG.init(seed);

    var elapsed = try std.time.Timer.start();
    while (elapsed.read() < duration) {
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

        var log: ?pkmn.protocol.Log(std.ArrayList(u8).Writer) = null;
        if (save) {
            if (frames != null) deinit(allocator);
            initial = try allocator.dupe(u8, std.mem.toBytes(battle)[0..]);
            frames = std.ArrayList(Frame).init(allocator);
            buf = std.ArrayList(u8).init(allocator);
            log = pkmn.protocol.Log(std.ArrayList(u8).Writer){ .writer = buf.?.writer() };
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
            std.debug.assert(buf.?.items.len <= max);
            try frames.?.append(.{
                .result = result,
                .c1 = c1,
                .c2 = c2,
                .state = try allocator.dupe(u8, std.mem.toBytes(battle.*)[0..]),
                .log = try buf.?.toOwnedSlice(),
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
    const writer = std.io.null_writer;
    // var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
    // var writer = if (writergate) &stderr.interface else stderr.writer();
    return switch (gen) {
        1 => pkmn.gen1.calc.update(battle, c1, c2, options, allocator, writer, transitions),
        else => unreachable,
    } catch unreachable;
}

fn errorAndExit(msg: []const u8, arg: anytype, cmd: []const u8) noreturn {
    var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
    var err = if (writergate) &stderr.interface else stderr.writer();
    err.print("Invalid {s}: {any}\n", .{ msg, arg }) catch {};
    usageAndExit(cmd);
}

fn usageAndExit(cmd: []const u8) noreturn {
    var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
    var err = if (writergate) &stderr.interface else stderr.writer();
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
    frames.?.deinit();
    std.debug.assert(buf != null);
    buf.?.deinit();
}

fn dump(seed: u64) !void {
    var stdout = if (writergate) std.fs.File.stdout() else std.io.getStdOut();
    var out: if (writergate) [4096]u8 else void = undefined;
    var bw = if (writergate) stdout.writer(&out) else std.io.bufferedWriter(stdout.writer());
    var w = if (writergate) &bw.interface else bw.writer();

    if (stdout.isTty() or builtin.mode != .Debug) {
        try w.print("0x{X}\n", .{seed});
    } else {
        try w.writeInt(u64, seed, endian);
        try display(w, false);
    }
    try if (writergate) w.flush() else bw.flush();

    // Write the last state information to the logs/ directory if it
    // exists so that it can easily be turned into a regression testcase
    var n: [1024]u8 = undefined;
    const ext = if (showdown) "showdown" else "pkmn";
    const name = try std.fmt.bufPrint(&n, "logs/0x{X}.{s}.bin", .{ seed, ext });

    const dir = std.fs.cwd();
    const file = dir.createFile(name, .{}) catch return;
    defer file.close();
    if (writergate) {
        var f = file.writer(&.{});
        try display(&f.interface, true);
    } else {
        try display(&file.writer(), true);
    }

    var p: [1024]u8 = undefined;
    const path = try dir.realpath(name, &p);
    dir.deleteFile("logs/dump.bin") catch {};
    dir.symLink(path, "logs/dump.bin", .{}) catch return;
}

fn display(w: anytype, final: bool) !void {
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
            try writeStruct(w, f.result);
            try writeStruct(w, f.c1);
            try writeStruct(w, f.c2);
        } else {
            for (fs.items) |f| {
                try w.writeAll(f.log);
                try w.writeAll(f.state);
                try writeStruct(w, f.result);
                try writeStruct(w, f.c1);
                try writeStruct(w, f.c2);
            }
        }
    }
    if (buf) |b| try w.writeAll(b.items);
}

const takeByte = if (writergate) std.io.Reader.takeByte else std.fs.File.Reader.readByte;
const takeInt = if (writergate) std.io.Reader.takeInt else std.fs.File.Reader.readInt;
fn takeStruct(r: anytype, comptime T: type) !T {
    return if (writergate)
        std.io.Reader.takeStruct(r, T, endian)
    else
        std.fs.File.Reader.readStruct(r, T);
}

fn writeStruct(w: anytype, s: anytype) !void {
    try if (writergate) w.writeStruct(s, endian) else w.writeStruct(s);
}

pub const panic =
    if (@hasDecl(std.debug, "FullPanic")) std.debug.FullPanic(panicFn) else Panic.call;
fn panicFn(msg: []const u8, ra: ?usize) noreturn {
    if (last) |seed| dump(seed) catch unreachable;
    std.debug.defaultPanic(msg, ra);
}

pub const Panic = struct {
    pub fn call(msg: []const u8, ert: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
        if (last) |seed| dump(seed) catch unreachable;
        if (@hasDecl(std.builtin, "Panic")) {
            std.debug.FormattedPanic.call(msg, ert, ra);
        } else {
            std.builtin.default_panic(msg, ert, ra);
        }
    }

    pub fn sentinelMismatch(expected: anytype, _: @TypeOf(expected)) noreturn {
        call("sentinel mismatch", null, null);
    }

    pub fn unwrapError(_: ?*std.builtin.StackTrace, _: anyerror) noreturn {
        call("attempt to unwrap error", null, null);
    }

    pub fn outOfBounds(_: usize, _: usize) noreturn {
        call("index out of bounds", null, null);
    }

    pub fn startGreaterThanEnd(_: usize, _: usize) noreturn {
        call("start index is larger than end index", null, null);
    }

    pub fn inactiveUnionField(active: anytype, _: @TypeOf(active)) noreturn {
        call("access of inactive union field", null, null);
    }

    pub const messages = if (@hasDecl(std.builtin, "Panic"))
        std.debug.FormattedPanic.messages
    else {};
};
