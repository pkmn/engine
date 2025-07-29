const std = @import("std");
const wasm = @import("../wasm.zig");

const Strong = if (@hasField(std.builtin.GlobalLinkage, "strong")) .strong else .Strong;

pub fn exports() void {
    @export(wasm.options.showdown, .{ .name = "SHOWDOWN", .linkage = Strong });
    @export(wasm.options.log, .{ .name = "LOG", .linkage = Strong });
    @export(wasm.options.chance, .{ .name = "CHANCE", .linkage = Strong });
    @export(wasm.options.calc, .{ .name = "CALC", .linkage = Strong });

    @export(wasm.gen(1).CHOICES_SIZE, .{ .name = "GEN1_CHOICES_SIZE", .linkage = Strong });
    @export(wasm.gen(1).LOGS_SIZE, .{ .name = "GEN1_LOGS_SIZE", .linkage = Strong });

    @export(wasm.gen(1).update, .{ .name = "GEN1_update", .linkage = Strong });
    @export(wasm.gen(1).choices, .{ .name = "GEN1_choices", .linkage = Strong });
}
