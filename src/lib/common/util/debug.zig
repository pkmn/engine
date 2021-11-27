const std = @import("std");

const assert = std.debug.assert;

// https://en.wikipedia.org/wiki/ANSI_escape_code
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

const COMPACT = 8;
const Ais = AutoIndentingStream(std.fs.File.Writer);

// Limited and lazy version of NodeJS's util.inspect
pub fn inspectN(value: anytype, ais: *Ais, max_depth: usize) !void {
    const T = @TypeOf(value);
    const options = std.fmt.FormatOptions{ .alignment = .Left };
    switch (@typeInfo(T)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float, .Bool => {
            try ais.writer().writeAll(YELLOW);
            try std.fmt.formatType(value, "any", options, ais.writer(), max_depth);
            try ais.writer().writeAll(RESET);
        },
        .Optional => {
            if (value) |payload| {
                try inspectN(payload, ais, max_depth);
            } else {
                try ais.writer().writeAll(BOLD);
                try std.fmt.formatBuf("null", options, ais.writer());
                try ais.writer().writeAll(RESET);
            }
        },
        .ErrorUnion => {
            if (value) |payload| {
                try inspectN(payload, ais, max_depth);
            } else |err| {
                try inspectN(err, ais, max_depth);
            }
        },
        .Enum => |enumInfo| {
            try ais.writer().writeAll(GREEN);
            try ais.writer().writeAll(@typeName(T));
            if (enumInfo.is_exhaustive) {
                try ais.writer().writeAll(".");
                try ais.writer().writeAll(@tagName(value));
                try ais.writer().writeAll(RESET);
                return;
            }

            // Use @tagName only if value is one of known fields
            @setEvalBranchQuota(3 * enumInfo.fields.len);
            inline for (enumInfo.fields) |enumField| {
                if (@enumToInt(value) == enumField.value) {
                    try ais.writer().writeAll(".");
                    try ais.writer().writeAll(@tagName(value));
                    try ais.writer().writeAll(RESET);
                    return;
                }
            }

            try ais.writer().writeAll("(");
            try inspectN(@enumToInt(value), ais, max_depth);
            try ais.writer().writeAll(")");
            try ais.writer().writeAll(RESET);
        },
        .Union => |info| {
            try ais.writer().writeAll(DIM);
            try ais.writer().writeAll(@typeName(T));
            try ais.writer().writeAll(RESET);

            if (max_depth == 0) return ais.writer().writeAll("{ ... }");
            if (info.tag_type) |UnionTagType| {
                try ais.writer().writeAll("{ .");
                try ais.writer().writeAll(@tagName(@as(UnionTagType, value)));
                try ais.writer().writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try inspectN(@field(value, u_field.name), ais, max_depth - 1);
                    }
                }
                try ais.writer().writeAll(" }");
            } else {
                try std.fmt.format(ais.writer(), "@{x}", .{@ptrToInt(&value)});
            }
        },
        .Struct => |info| {
            if (info.is_tuple) {
                // Skip the type and field names when formatting tuples.
                if (max_depth == 0) return ais.writer().writeAll("{ ... }");
                try ais.writer().writeAll("{");
                inline for (info.fields) |f, i| {
                    if (i == 0) {
                        try ais.writer().writeAll(" ");
                    } else {
                        try ais.writer().writeAll(", ");
                    }
                    try inspectN(@field(value, f.name), ais, max_depth - 1);
                }
                return ais.writer().writeAll(" }");
            }

            try ais.writer().writeAll(DIM);
            try ais.writer().writeAll(@typeName(T));
            try ais.writer().writeAll(RESET);
            if (max_depth == 0) return ais.writer().writeAll("{ ... }");

            const compact = if (info.fields.len > COMPACT) false else inline for (info.fields) |f| {
                if (!isPrimitive(f.field_type)) break false;
            } else true;

            if (compact) {
                try ais.writer().writeAll("{ ");
            } else {
                try ais.writer().writeAll("{");
                try ais.insertNewline();
                ais.pushIndent();
            }
            inline for (info.fields) |f, i| {
                try ais.writer().writeAll(".");
                try ais.writer().writeAll(f.name);
                try ais.writer().writeAll(" = ");
                try inspectN(@field(value, f.name), ais, max_depth - 1);
                if (i < info.fields.len - 1) {
                    try ais.writer().writeAll(",");
                    if (compact) {
                        try ais.writer().writeAll(" ");
                    } else {
                        try ais.insertNewline();
                    }
                }
            }
            if (compact) {
                try ais.writer().writeAll(" }");
            } else {
                ais.popIndent();
                try ais.insertNewline();
                try ais.writer().writeAll("}");
            }
        },
        .Array => |info| {
            if (max_depth == 0) return ais.writer().writeAll("{ ... }");

            const compact = if (value.len > COMPACT) false else isPrimitive(info.child);

            if (compact) {
                try ais.writer().writeAll("{ ");
            } else {
                try ais.writer().writeAll("{");
                try ais.insertNewline();
                ais.pushIndent();
            }
            for (value) |elem, i| {
                try inspectN(elem, ais, max_depth - 1);
                if (i < value.len - 1) {
                    try ais.writer().writeAll(",");
                    if (compact) {
                        try ais.writer().writeAll(" ");
                    } else {
                        try ais.insertNewline();
                    }
                }
            }
            if (compact) {
                try ais.writer().writeAll(" }");
            } else {
                ais.popIndent();
                try ais.insertNewline();
                try ais.writer().writeAll("}");
            }
        },
        else => {
            try std.fmt.formatType(value, "any", options, ais.writer(), max_depth);
        },
    }
}

pub fn inspect(value: anytype, writer: anytype) @TypeOf(writer).Error!void {
    const ais = &Ais{
        .indent_delta = 4,
        .underlying_writer = writer,
    };
    try inspectN(value, ais, 10);
}

pub fn debug(value: anytype) void {
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeByte('\n') catch return;
    nosuspend inspect(value, stderr) catch return;
    // nosuspend stderr.writeByte('\n') catch return;
}

fn isPrimitive(comptime t: type) bool {
    return switch (@typeInfo(t)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float, .Bool, .Optional, .ErrorUnion, .Enum => true,
        else => false,
    };
}

// Stripped down version oflin/ std/zig/render.zig's AutoIndentingStream
fn AutoIndentingStream(comptime UnderlyingWriter: type) type {
    return struct {
        const Self = @This();
        pub const WriteError = UnderlyingWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriteError, write);

        underlying_writer: UnderlyingWriter,

        indent_count: usize = 0,
        indent_delta: usize,
        current_line_empty: bool = true,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return @as(usize, 0);
            try self.applyIndent();
            return self.writeNoIndent(bytes);
        }

        fn writeNoIndent(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return @as(usize, 0);
            try self.underlying_writer.writeAll(bytes);
            if (bytes[bytes.len - 1] == '\n') self.resetLine();
            return bytes.len;
        }

        pub fn insertNewline(self: *Self) WriteError!void {
            _ = try self.writeNoIndent("\n");
        }

        fn resetLine(self: *Self) void {
            self.current_line_empty = true;
        }

        pub fn pushIndent(self: *Self) void {
            self.indent_count += 1;
        }

        pub fn popIndent(self: *Self) void {
            assert(self.indent_count != 0);
            self.indent_count -= 1;
        }

        fn applyIndent(self: *Self) WriteError!void {
            const current_indent = self.currentIndent();
            if (self.current_line_empty and current_indent > 0) {
                try self.underlying_writer.writeByteNTimes(' ', current_indent);
            }

            self.current_line_empty = false;
        }

        fn currentIndent(self: *Self) usize {
            var indent_current: usize = 0;
            if (self.indent_count > 0) indent_current = self.indent_count * self.indent_delta;
            return indent_current;
        }
    };
}
