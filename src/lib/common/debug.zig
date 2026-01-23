const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;

pub fn print(value: anytype) void {
    if (builtin.target.os.tag == .freestanding) return;

    var buffer: [4096]u8 = undefined;
    const stderr = debug.lockStderr(&buffer);
    defer debug.unlockStderr();
    var fw = stderr.file_writer;

    nosuspend {
        fw.interface.writeAll("\x1b[41m") catch return;
        if (@TypeOf(@src()) == @TypeOf(value)) {
            fw.interface.print("{s} ({s}:{d}:{d})", .{
                value.fn_name,
                value.file,
                value.line,
                value.column,
            }) catch return;
        } else {
            switch (@typeInfo(@TypeOf(value))) {
                .@"struct" => |info| {
                    if (info.is_tuple) {
                        inline for (info.fields, 0..) |f, i| {
                            inspect(fw, @field(value, f.name));
                            if (i < info.fields.len - 1) fw.interface.writeAll(" ") catch return;
                        }
                    } else {
                        inspect(fw, value);
                    }
                },
                else => inspect(fw, value),
            }
        }
        fw.interface.writeAll("\x1b[K\x1b[0m\n") catch return;
    }
}

fn inspect(w: anytype, value: anytype) void {
    nosuspend {
        const err = "Unable to format type '" ++ @typeName(@TypeOf(value)) ++ "'";
        switch (@typeInfo(@TypeOf(value))) {
            .array => |info| {
                if (info.child == u8) return w.interface.print("{s}", .{value}) catch return;
                @compileError(err);
            },
            .pointer => |ptr_info| switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => |info| {
                        if (info.child == u8) {
                            return w.interface.print("{s}", .{value}) catch return;
                        }
                        @compileError(err);
                    },
                    .@"enum", .@"union", .@"struct" => return inspect(value.*),
                    else => @compileError(err),
                },
                .many, .c => {
                    if (ptr_info.sentinel) |_| return inspect(std.mem.span(value));
                    if (ptr_info.child == u8) {
                        return w.interface.print("{s}", .{std.mem.span(value)}) catch return;
                    }
                    @compileError(err);
                },
                .slice => {
                    if (ptr_info.child == u8) {
                        return w.interface.print("{s}", .{value}) catch return;
                    }
                    @compileError(err);
                },
            },
            .optional => w.interface.print("{?}", .{value}) catch return,
            else => w.interface.print("{}", .{value}) catch return,
        }
    }
}
