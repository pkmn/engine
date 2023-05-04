const std = @import("std");

const expect = std.testing.expect;
const assert = std.debug.assert;

const Player = @import("../../common/data.zig").Player;
const Optional = @import("../../common/optional.zig").Optional;

const Move = @import("../data.zig").Move;

/// Information about what RNG events were observed during a battle `update`. This can additionally
/// be provided as input to the `update` call to override the normal behavior of the RNG in order
/// to force specific outcomes.
pub const Guide = extern struct {
    /// Outline of the RNG activity for Player 1
    p1: Outline = .{},
    /// Outline of the RNG activity for Player 2
    p2: Outline = .{},

    /// Return a copy of the guide suitable to be used as a unique logical key.
    pub fn key(guide: Guide) Guide {
        // We need to remove the *actual* duration rolls from the key because logically
        // we should not be able to differentiate based on this hidden information and instead
        // want to rely on the observed values tracked in the durations field.
        guide.p1.duration = 0;
        guide.p2.duration = 0;
        return guide;
    }

    /// TODO
    pub fn eql(a: Guide, b: Guide) Guide {
        a.p1.duration = 0;
        a.p2.duration = 0;
        a.p1.max_damage = 0;
        a.p2.max_damage = 0;

        b.p1.duration = 0;
        b.p2.duration = 0;
        b.p1.max_damage = 0;
        b.p2.max_damage = 0;

        return @bitCast(u128, a) == @bitCast(u128, b);
    }

    comptime {
        assert(@sizeOf(Guide) == 16);
    }

    /// Information about the RNG that was observed during a battle `update` for a single player.
    pub const Outline = packed struct {
        /// Observed values of various durations. Does not influence future RNG calls.
        durations: Durations = .{},

        /// If not None, the Move to return for Rolls.metronome.
        metronome: Move = .None,
        /// If not 0, psywave - 1 should be returned as the damage roll for Rolls.psywave.
        psywave: u8 = 0,

        /// If not None, the Player to be returned by Rolls.speedTie.
        speed_tie: Optional(Player) = .None,
        /// If not 0, the roll 216 + min_damage represents the minimum roll to be returned
        /// by Rolls.damage which results in the same damage as 216 + max_damage.
        min_damage: u6 = 0,

        /// If not 0, the roll 216 + max_damage represents the maximum roll to be returned
        /// by Rolls.damage which results in the same damage as 216 + min_damage.
        max_damage: u6 = 0,
        /// If not None, the value to return for Rolls.hit.
        hit: Optional(bool) = .None,

        /// If not 0, the move slot (1-4) to return in Rolls.moveSlot.
        move_slot: u3 = 0,
        /// If not 0, the value (2-5) to return for Rolls.distribution.
        distribution: u3 = 0,
        /// If not None, the value to be returned for
        /// Rolls.{confusionChance,secondaryChance,poisonChance}.
        secondary_chance: Optional(bool) = .None,

        /// If not 0, the value to be returned by
        /// Rolls.{disableDuration,sleepDuration,confusionDuration,bideThrashDuration}.
        duration: u4 = 0,
        /// If not None, the value to be returned by Rolls.criticalHit.
        critical_hit: Optional(bool) = .None,
        /// If not None, the value to return for Rolls.{confused,paralyzed}.
        cant: Optional(bool) = .None,

        /// Observed values for various durations that need to be tracked in order to properly
        /// deduplicate transitions with a primary key.
        pub const Durations = packed struct {
            /// The number of turns a Pokémon has been observed to be disabled.
            disable: u4 = 0,
            /// The number of turns a Pokémon has been observed to be sleeping.
            sleep: u4 = 0,
            /// The number of turns a Pokémon has been observed to be confused.
            confusion: u4 = 0,
            /// The number of turns a Pokémon has been observed to be storing energy / thrashing.
            bide_thrash: u4 = 0,

            comptime {
                assert(@sizeOf(Durations) == 2);
            }
        };

        comptime {
            assert(@sizeOf(Outline) == 8);
        }
    };
};
