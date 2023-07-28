// Forked from tigerbeetle/tigerbeetle's Apache-2 licensed src/copyhound.zig.
// The full license can be found at https://github.com/tigerbeetle/tigerbeetle/blob/main/LICENSE

const std = @import("std");
const assert = std.debug.assert;

const log = std.log;
pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var threshold: usize = 8;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) threshold = try std.fmt.parseUnsigned(usize, args[1], 10);

    var line_buffer = try allocator.alloc(u8, 1024 * 1024);
    var func_buf = try allocator.alloc(u8, 4096);

    const stdin = std.io.getStdIn();
    var buf_reader = std.io.bufferedReader(stdin.reader());
    var in_stream = buf_reader.reader();

    var func_current: ?[]const u8 = null;
    while (try in_stream.readUntilDelimiterOrEof(line_buffer, '\n')) |line| {
        if (std.mem.startsWith(u8, line, "define ")) {
            func_current = extractFuncName(line, func_buf) orelse {
                log.err("can't parse line={s}", .{line});
                return error.BadDefine;
            };
            continue;
        }

        if (func_current) |func| {
            if (std.mem.eql(u8, line, "}")) {
                func_current = null;
                continue;
            }
            if (cut(line, "@llvm.memcpy")) |c| {
                const size = extractMemcpySize(c[1]) orelse {
                    log.err("can't parse line={s}", .{line});
                    return error.BadMemcpy;
                };
                if (size > threshold) {
                    log.warn("{s}: {} bytes memcpy", .{ func, size });
                }
            }
        }
    }
}

fn cut(haystack: []const u8, needle: []const u8) ?struct { []const u8, []const u8 } {
    const index = std.mem.indexOf(u8, haystack, needle) orelse return null;
    return .{ haystack[0..index], haystack[index + needle.len ..] };
}

fn extractFuncName(define: []const u8, buf: []u8) ?[]const u8 {
    const func_name = (cut(define, "@") orelse return null)[1];
    var buf_count: usize = 0;
    var level: u32 = 0;
    for (func_name) |c| {
        switch (c) {
            '(' => level += 1,
            ')' => level -= 1,
            '"' => {},
            else => {
                if (level > 0) continue;
                if (c == ' ') return buf[0..buf_count];
                if (buf_count == buf.len) return null;
                buf[buf_count] = c;
                buf_count += 1;
            },
        }
    } else return null;
}

fn extractMemcpySize(memcpy_call: []const u8) ?u32 {
    const call_args = (cut(memcpy_call, "(") orelse return null)[1];
    var level: u32 = 0;
    var arg_count: u32 = 0;

    const args_after_size = for (call_args, 0..) |c, i| {
        switch (c) {
            '(' => level += 1,
            ')' => level -= 1,
            ',' => {
                if (level > 0) continue;
                arg_count += 1;
                if (!std.mem.startsWith(u8, call_args[i..], ", ")) return null;
                if (arg_count == 2) break call_args[i + 2 ..];
            },
            else => {},
        }
    } else return null;

    const size_arg = (cut(args_after_size, ",") orelse return null)[0];

    const size_value = (cut(size_arg, " ") orelse return null)[1];

    // Runtime-known memcpy size, assume that's OK.
    if (std.mem.startsWith(u8, size_value, "%")) return 0;

    return std.fmt.parseInt(u32, size_value, 10) catch null;
}
