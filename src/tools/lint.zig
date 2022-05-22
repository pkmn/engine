const std = @import("std");
const fs = std.fs;

const assert = std.debug.assert;

const PATH = "src";
const LINE_LENGTH = 100;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    const format = try checkFormat(PATH);
    const lint = try lintDir(PATH, fs.cwd(), PATH);
    std.process.exit(@boolToInt(format or lint));
}

fn checkFormat(file_path: []const u8) !bool {
    const argv = &.{ "zig", "fmt", "--check", file_path };

    assert(std.process.can_spawn);
    var child = std.ChildProcess.init(argv, allocator);

    const term = child.spawnAndWait() catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Unable to spawn 'zig fmt': {s}\n", .{@errorName(err)});
        return true;
    };

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("'zig fmt' exited with error code {}:\n", .{code});
                return true;
            }
        },
        else => {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("'zig fmt' exited unexpectedly\n", .{});
            return true;
        },
    }
    return false;
}

const Ignored = union(enum) {
    lines: []const u32,
    all,
};

const ignore = std.ComptimeStringMap(Ignored, .{
    .{ "src/tools/serde.zig", .{ .lines = &.{ 404, 514 } } },
    .{ "src/examples/zig/example.zig", .all },
    .{ "src/lib/gen2/test.zig", .all },
    .{ "src/lib/gen1/test.zig", .{ .lines = &.{599} } },
});

fn ignored(path: []const u8, line: u32) bool {
    const value = ignore.get(path) orelse return false;
    switch (value) {
        .lines => |lines| return std.mem.indexOfScalar(u32, lines, line) != null,
        .all => return true,
    }
}

var seen = std.AutoArrayHashMapUnmanaged(fs.File.INode, void){};

const LintError =
    error{ OutOfMemory, NotUtf8 } || fs.File.OpenError || fs.File.ReadError || fs.File.WriteError;

fn lintDir(file_path: []const u8, parent_dir: fs.Dir, parent_sub_path: []const u8) LintError!bool {
    var err = false;

    var dir = try parent_dir.openDir(parent_sub_path, .{ .iterate = true });
    defer dir.close();

    const stat = try dir.stat();
    if (try seen.fetchPut(allocator, stat.inode, {})) |_| return err;

    var dir_it = dir.iterate();
    while (try dir_it.next()) |entry| {
        const is_dir = entry.kind == .Directory;
        if (is_dir and std.mem.eql(u8, entry.name, "zig-cache")) continue;
        if (is_dir or std.mem.endsWith(u8, entry.name, ".zig")) {
            const full_path = try fs.path.join(allocator, &[_][]const u8{ file_path, entry.name });
            defer allocator.free(full_path);

            var e = false;
            if (is_dir) {
                e = try lintDir(full_path, dir, entry.name);
            } else {
                e = try lintFile(full_path, dir, entry.name);
            }
            err = err or e;
        }
    }

    return err;
}

fn lintFile(file_path: []const u8, dir: fs.Dir, sub_path: []const u8) !bool {
    const source_file = try dir.openFile(sub_path, .{});
    defer source_file.close();

    const source = try source_file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(usize),
        null,
        @alignOf(u8),
        0,
    );

    return lintLineLength(source, file_path);
}

fn lintLineLength(source: []const u8, path: []const u8) !bool {
    var err = false;
    var i: usize = 0;
    var line: u32 = 1;
    while (std.mem.indexOfScalar(u8, source[i..], '\n')) |newline| : (line += 1) {
        const line_length =
            std.unicode.utf8CountCodepoints(source[i..][0..newline]) catch return error.NotUtf8;
        if (line_length > LINE_LENGTH and !ignored(path, line)) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print(
                "{s}:{d} has a length of {d}. Maximum allowed is 100\n",
                .{ path, line, line_length },
            );
            err = true;
        }
        i += newline + 1;
    }
    return err;
}
