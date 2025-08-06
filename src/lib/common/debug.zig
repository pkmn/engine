const std = @import("std");

const debug = std.debug;
const io = std.io;

const Array = if (@hasField(std.builtin.Type, "array")) .array else .Array;
const Enum = if (@hasField(std.builtin.Type, "enum")) .@"enum" else .Enum;
const Optional = if (@hasField(std.builtin.Type, "optional")) .optional else .Optional;
const Pointer = if (@hasField(std.builtin.Type, "pointer")) .pointer else .Pointer;
const Struct = if (@hasField(std.builtin.Type, "struct")) .@"struct" else .Struct;
const Union = if (@hasField(std.builtin.Type, "union")) .@"union" else .Union;

const writergate = @hasDecl(std.fs.File, "stdout");

pub fn print(value: anytype) void {
    if (@hasDecl(debug, "lockStdErr")) debug.lockStdErr() else debug.getStderrMutex().lock();
    defer if (@hasDecl(debug, "unlockStdErr"))
        debug.unlockStdErr()
    else
        debug.getStderrMutex().unlock();
    var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
    var err = if (writergate) &stderr.interface else stderr.writer();

    nosuspend {
        err.writeAll("\x1b[41m") catch return;
        if (@TypeOf(@src()) == @TypeOf(value)) {
            err.print("{s} ({s}:{d}:{d})", .{
                value.fn_name,
                value.file,
                value.line,
                value.column,
            }) catch return;
        } else {
            switch (@typeInfo(@TypeOf(value))) {
                Struct => |info| {
                    if (info.is_tuple) {
                        inline for (info.fields, 0..) |f, i| {
                            inspect(@field(value, f.name));
                            if (i < info.fields.len - 1) err.writeAll(" ") catch return;
                        }
                    } else {
                        inspect(value);
                    }
                },
                else => inspect(value),
            }
        }
        err.writeAll("\x1b[K\x1b[0m\n") catch return;
    }
}

fn inspect(value: anytype) void {
    var stderr = if (writergate) std.fs.File.stderr().writer(&.{}) else std.io.getStdErr();
    var err = if (writergate) &stderr.interface else stderr.writer();

    nosuspend {
        const msg = "Unable to format type '" ++ @typeName(@TypeOf(value)) ++ "'";
        switch (@typeInfo(@TypeOf(value))) {
            Array => |info| {
                if (info.child == u8) return err.print("{s}", .{value}) catch return;
                @compileError(msg);
            },
            Pointer => |ptr_info| switch (ptr_info.size) {
                .One => switch (@typeInfo(ptr_info.child)) {
                    Array => |info| {
                        if (info.child == u8) return err.print("{s}", .{value}) catch return;
                        @compileError(msg);
                    },
                    Enum, Union, Struct => return inspect(value.*),
                    else => @compileError(msg),
                },
                .Many, .C => {
                    if (ptr_info.sentinel) |_| return inspect(std.mem.span(value));
                    if (ptr_info.child == u8) {
                        return err.print("{s}", .{std.mem.span(value)}) catch return;
                    }
                    @compileError(msg);
                },
                .Slice => {
                    if (ptr_info.child == u8) return err.print("{s}", .{value}) catch return;
                    @compileError(msg);
                },
            },
            Optional => err.print("{?}", .{value}) catch return,
            else => err.print("{}", .{value}) catch return,
        }
    }
}

const showdown = @import("./options.zig").showdown;
const Result = @import("./data.zig").Result;
const Choice = @import("./data.zig").Choice;

pub fn dump(gen: u8, battle: anytype, frame: ?struct { Result, Choice, Choice }) void {
    const file = std.fs.cwd().createFile("logs/dump.bin", .{}) catch return;
    defer file.close();
    var w = file.writer();
    w.writeByte(@intFromBool(showdown)) catch return;
    w.writeByte(gen) catch return;
    w.writeInt(i16, 0, .little) catch return;
    w.writeInt(i32, 0, .little) catch return;
    w.writeStruct(battle) catch return;
    w.writeStruct(battle) catch return;
    if (frame) |f| {
        w.writeStruct(f[0]) catch return;
        w.writeStruct(f[1]) catch return;
        w.writeStruct(f[2]) catch return;
    }
}
