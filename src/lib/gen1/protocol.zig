const std = @import("std");
const build_options = @import("build_options");

const protocol = @import("../common/protocol.zig");

const data = @import("./data.zig");

const assert = std.debug.assert;

const trace = build_options.trace;

pub const Activate = protocol.Activate;
pub const ArgType = protocol.ArgType;
pub const Boost = protocol.Boost;
pub const Cant = protocol.Cant;
pub const CureStatus = protocol.CureStatus;
pub const Damage = protocol.Damage;
pub const End = protocol.End;
pub const Fail = protocol.Fail;
pub const Heal = protocol.Heal;
pub const Immune = protocol.Immune;
pub const Start = protocol.Start;
pub const Status = protocol.Status;
pub const expectLog = protocol.expectLog;

const Move = data.Move;
const Player = data.Player;
const Pokemon = data.Pokemon;

pub fn Log(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn move(self: Self, source: u8, m: Move, target: u8, reason: protocol.Move) !void {
            if (!trace) return;
            assert(reason != .From);
            assert(m != .None or reason == .Recharge);
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Move),
                source,
                @enumToInt(m),
                target,
                @enumToInt(reason),
            });
        }

        pub fn moveFrom(self: Self, source: u8, m: Move, target: u8, from: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Move),
                source,
                @enumToInt(m),
                target,
                @enumToInt(protocol.Move.From),
                @enumToInt(from),
            });
        }

        pub fn switched(self: Self, ident: u8, pokemon: *const Pokemon) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Switch), ident });
            try self.writer.writeAll(&[_]u8{ @enumToInt(pokemon.species), pokemon.level });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{pokemon.status});
        }

        pub fn cant(self: Self, ident: u8, reason: Cant) !void {
            if (!trace) return;
            assert(reason != .Disable);
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Cant), ident, @enumToInt(reason) });
        }

        pub fn disabled(self: Self, ident: u8, mslot: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Cant),
                ident,
                @enumToInt(Cant.Disable),
                mslot,
            });
        }

        pub fn faint(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Faint), ident });
        }

        pub fn turn(self: Self, num: u16) !void {
            if (!trace) return;
            try self.writer.writeByte(@enumToInt(ArgType.Turn));
            try self.writer.writeIntNative(u16, num);
        }

        pub fn win(self: Self, player: Player) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Win), @enumToInt(player) });
        }

        pub fn tie(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.Tie)});
        }

        pub fn damage(self: Self, ident: u8, pokemon: *const Pokemon, reason: Damage) !void {
            if (!trace) return;
            assert(@enumToInt(reason) <= @enumToInt(Damage.Confusion));
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Damage), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason) });
        }

        pub fn damageOf(
            self: Self,
            ident: u8,
            pokemon: *const Pokemon,
            reason: Damage,
            source: u8,
        ) !void {
            if (!trace) return;
            assert(@enumToInt(reason) >= @enumToInt(Damage.PoisonOf));
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Damage), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason), source });
        }

        pub fn heal(self: Self, ident: u8, pokemon: *const Pokemon, reason: Heal) !void {
            if (!trace) return;
            assert(reason != .Drain);
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Heal), ident });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(reason) });
        }

        pub fn drain(self: Self, source: u8, pokemon: *const Pokemon, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Heal), source });
            try self.writer.writeIntNative(u16, pokemon.hp);
            try self.writer.writeIntNative(u16, pokemon.stats.hp);
            try self.writer.writeAll(&[_]u8{ pokemon.status, @enumToInt(Heal.Drain), target });
        }

        pub fn status(self: Self, ident: u8, value: u8, reason: Status) !void {
            if (!trace) return;
            assert(reason != .From);
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Status),
                ident,
                value,
                @enumToInt(reason),
            });
        }

        pub fn statusFrom(self: Self, ident: u8, value: u8, m: Move) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Status),
                ident,
                value,
                @enumToInt(Status.From),
                @enumToInt(m),
            });
        }

        pub fn curestatus(self: Self, ident: u8, value: u8, reason: CureStatus) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.CureStatus),
                ident,
                value,
                @enumToInt(reason),
            });
        }

        pub fn boost(self: Self, ident: u8, reason: Boost, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Boost),
                ident,
                @enumToInt(reason),
                num,
            });
        }

        pub fn unboost(self: Self, ident: u8, reason: Boost, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Unboost),
                ident,
                @enumToInt(reason),
                num,
            });
        }

        pub fn clearallboost(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.ClearAllBoost)});
        }

        pub fn fail(self: Self, ident: u8, reason: Fail) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Fail), ident, @enumToInt(reason) });
        }

        pub fn miss(self: Self, source: u8, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Miss), source, target });
        }

        pub fn hitcount(self: Self, ident: u8, num: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.HitCount), ident, num });
        }

        pub fn prepare(self: Self, source: u8, m: Move, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Prepare),
                source,
                @enumToInt(m),
                target,
            });
        }

        pub fn mustrecharge(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.MustRecharge), ident });
        }

        pub fn activate(self: Self, ident: u8, reason: Activate) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Activate),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn fieldactivate(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.FieldActivate)});
        }

        pub fn start(self: Self, ident: u8, reason: Start) !void {
            if (!trace) return;
            assert(@enumToInt(reason) < @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn typechange(self: Self, ident: u8, types: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(Start.TypeChange),
                types,
            });
        }

        pub fn startEffect(self: Self, ident: u8, reason: Start, m: Move) !void {
            if (!trace) return;
            assert(@enumToInt(reason) > @enumToInt(Start.TypeChange));
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Start),
                ident,
                @enumToInt(reason),
                @enumToInt(m),
            });
        }

        pub fn end(self: Self, ident: u8, reason: End) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.End), ident, @enumToInt(reason) });
        }

        pub fn ohko(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.OHKO)});
        }

        pub fn crit(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Crit), ident });
        }

        pub fn supereffective(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.SuperEffective), ident });
        }

        pub fn resisted(self: Self, ident: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Resisted), ident });
        }

        pub fn immune(self: Self, ident: u8, reason: Immune) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{
                @enumToInt(ArgType.Immune),
                ident,
                @enumToInt(reason),
            });
        }

        pub fn transform(self: Self, source: u8, target: u8) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{ @enumToInt(ArgType.Transform), source, target });
        }

        pub fn laststill(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.LastStill)});
        }

        pub fn lastmiss(self: Self) !void {
            if (!trace) return;
            try self.writer.writeAll(&[_]u8{@enumToInt(ArgType.LastMiss)});
        }
    };
}

test "Log" {
    var buf = [_]u8{0} ** 3;
    var log: Log(std.io.FixedBufferStream([]u8).Writer) = .{
        .writer = std.io.fixedBufferStream(&buf).writer(),
    };

    try log.cant(1, .Trapped);

    try expectLog(
        &[_]u8{ @enumToInt(ArgType.Cant), 1, @enumToInt(Cant.Trapped) },
        &buf,
    );
}
