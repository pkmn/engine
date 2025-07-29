const std = @import("std");
const c = @import("../c.zig");

const Strong = if (@hasField(std.builtin.GlobalLinkage, "strong")) .strong else .Strong;

pub fn exports() void {
    @export(c.OPTIONS, .{ .name = "PKMN_OPTIONS", .linkage = Strong });

    @export(c.MAX_CHOICES, .{ .name = "PKMN_MAX_CHOICES", .linkage = Strong });
    @export(c.CHOICES_SIZE, .{ .name = "PKMN_CHOICES_SIZE", .linkage = Strong });
    @export(c.MAX_LOGS, .{ .name = "PKMN_MAX_LOGS", .linkage = Strong });
    @export(c.LOGS_SIZE, .{ .name = "PKMN_LOGS_SIZE", .linkage = Strong });

    @export(c.gen(1).MAX_CHOICES, .{ .name = "PKMN_GEN1_MAX_CHOICES", .linkage = Strong });
    @export(c.gen(1).CHOICES_SIZE, .{ .name = "PKMN_GEN1_CHOICES_SIZE", .linkage = Strong });
    @export(c.gen(1).MAX_LOGS, .{ .name = "PKMN_GEN1_MAX_LOGS", .linkage = Strong });
    @export(c.gen(1).LOGS_SIZE, .{ .name = "PKMN_GEN1_LOGS_SIZE", .linkage = Strong });

    @export(c.choice_init, .{ .name = "pkmn_choice_init", .linkage = Strong });
    @export(c.choice_type, .{ .name = "pkmn_choice_type", .linkage = Strong });
    @export(c.choice_data, .{ .name = "pkmn_choice_data", .linkage = Strong });

    @export(c.result_type, .{ .name = "pkmn_result_type", .linkage = Strong });
    @export(c.result_p1, .{ .name = "pkmn_result_p1", .linkage = Strong });
    @export(c.result_p2, .{ .name = "pkmn_result_p2", .linkage = Strong });

    @export(c.err, .{ .name = "pkmn_error", .linkage = Strong });

    @export(c.psrng_init, .{ .name = "pkmn_psrng_init", .linkage = Strong });
    @export(c.psrng_next, .{ .name = "pkmn_psrng_next", .linkage = Strong });

    @export(c.rational_init, .{ .name = "pkmn_rational_init", .linkage = Strong });
    @export(c.rational_reduce, .{ .name = "pkmn_rational_reduce", .linkage = Strong });
    @export(c.rational_numerator, .{ .name = "pkmn_rational_numerator", .linkage = Strong });
    @export(c.rational_denominator, .{ .name = "pkmn_rational_denominator", .linkage = Strong });

    @export(
        c.gen(1).battle_options_set,
        .{ .name = "pkmn_gen1_battle_options_set", .linkage = Strong },
    );
    @export(
        c.gen(1).battle_options_chance_probability,
        .{ .name = "pkmn_gen1_battle_options_chance_probability", .linkage = Strong },
    );
    @export(
        c.gen(1).battle_options_chance_actions,
        .{ .name = "pkmn_gen1_battle_options_chance_actions", .linkage = Strong },
    );
    @export(
        c.gen(1).battle_options_chance_durations,
        .{ .name = "pkmn_gen1_battle_options_chance_durations", .linkage = Strong },
    );
    @export(
        c.gen(1).battle_options_calc_summaries,
        .{ .name = "pkmn_gen1_battle_options_calc_summaries", .linkage = Strong },
    );

    @export(
        c.gen(1).battle_update,
        .{ .name = "pkmn_gen1_battle_update", .linkage = Strong },
    );
    @export(
        c.gen(1).battle_choices,
        .{ .name = "pkmn_gen1_battle_choices", .linkage = Strong },
    );
}
