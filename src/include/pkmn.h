/**
 * This file is part of the https://pkmn.cc/engine distribution.
 *
 * Copyright (c) 2021-2024 pkmn contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef LIBPKMN_H
#define LIBPKMN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#include <assert.h>
#include <limits.h>
static_assert(sizeof(double) * CHAR_BIT == 64, "libpkmn requires IEEE 754 64-bit doubles");
#endif
typedef double float64_t;

/**
 * Defines an opaque pkmn type. These are given a size so that they may be
 * statically allocated but must either be initialized with an init() function
 * or manually depending on the type in question.
 */
#define PKMN_OPAQUE(n) typedef struct { uint8_t bytes[n]; }

/** Compile time options acknowledged by libpkmn. */
typedef struct {
    bool showdown;
    bool log;
    bool chance;
    bool calc;
} pkmn_options;
/** Compile time options set when libpkmn was built. */
extern const pkmn_options PKMN_OPTIONS;

/** The minimum size in bytes required to hold all choice options. */
extern const size_t PKMN_MAX_CHOICES;
/**
 * The optimal size in bytes required to hold all choice options. At least as
 * large as PKMN_MAX_CHOICES.
 */
extern const size_t PKMN_CHOICES_SIZE;
/** The maximum number of bytes possibly logged by a single update. */
extern const size_t PKMN_MAX_LOGS;
/**
 * The optimal size in bytes required to hold the largest amount of log data
 * possible from a single update. At least as large as PKMN_MAX_LOGS.
 */
extern const size_t PKMN_LOGS_SIZE;

/** Identifier for a single player. */
typedef enum pkmn_player {
  PKMN_PLAYER_P1 = 0,
  PKMN_PLAYER_P2 = 1,
} pkmn_player;

/** A choice made by a player. */
typedef uint8_t pkmn_choice;
/** The type of choice. */
typedef enum pkmn_choice_kind {
  PKMN_CHOICE_PASS = 0,
  PKMN_CHOICE_MOVE = 1,
  PKMN_CHOICE_SWITCH = 2,
} pkmn_choice_kind;
/** Returns a choice initialized for a specific type with the provided data.
 * data must be <= 6. */
pkmn_choice pkmn_choice_init(pkmn_choice_kind type, uint8_t data);
/** The choice type of the choice. */
pkmn_choice_kind pkmn_choice_type(pkmn_choice choice);
/** The choice data of the choice. */
uint8_t pkmn_choice_data(pkmn_choice choice);

/** The result of updating a battle. */
typedef uint8_t pkmn_result;
/** The type of result. */
typedef enum pkmn_result_kind {
  PKMN_RESULT_NONE = 0,
  PKMN_RESULT_WIN = 1,
  PKMN_RESULT_LOSE = 2,
  PKMN_RESULT_TIE = 3,
  PKMN_RESULT_ERROR = 4,
} pkmn_result_kind;
/** The result type of the result. */
pkmn_result_kind pkmn_result_type(pkmn_result result);
/** The choice type of the result for Player 1. */
pkmn_choice_kind pkmn_result_p1(pkmn_result result);
/** The choice type of the result for Player 2. */
pkmn_choice_kind pkmn_result_p2(pkmn_result result);
/**
 * Whether or not the update resulted in an error being thrown. This can only
 * happen if libpkmn was built with protocol message logging enabled and the
 * buffer provided to the update function was not large enough to hold all of
 * the data (which is only possible if the buffer being used was smaller than
 * generation in question's MAX_LOGS bytes).
 */
bool pkmn_error(pkmn_result result);

/** The size in bytes of the Pokémon Showdown RNG (backed by a Generation V & VI RNG). */
#define PKMN_PSRNG_SIZE 8
/** The size in bytes of the rational number type exposed by libpkmn. */
#define PKMN_RATIONAL_SIZE 16

/** Pokémon Showdown's RNG (backed by a Generation V & VI RNG). */
PKMN_OPAQUE(PKMN_PSRNG_SIZE) pkmn_psrng;
/** Initialize the Pokémon Showdown RNG with the given seed. */
void pkmn_psrng_init(pkmn_psrng *psrng, uint64_t seed);
/** Returns the next number produced by the Pokémon Showdown RNG and advances the seed. */
uint32_t pkmn_psrng_next(pkmn_psrng *psrng);

/**
 * Specialization of a rational number used by the engine to compute probabilties.
 * For performance reasons the rational is only reduced lazily and thus reduce
 * must be invoked explicitly before reading.
 */
PKMN_OPAQUE(PKMN_RATIONAL_SIZE) pkmn_rational;
/** Initializes (or resets) the rational to 1. */
void pkmn_rational_init(pkmn_rational *rational);
/** Normalize the rational by reducing by the greatest common divisor. */
void pkmn_rational_reduce(pkmn_rational *rational);
/** Returns the numerator of the rational. */
float64_t pkmn_rational_numerator(const pkmn_rational *rational);
/** Returns the denominator of the rational. */
float64_t pkmn_rational_denominator(const pkmn_rational *rational);

/** The size in bytes of a Generation I battle. */
#define PKMN_GEN1_BATTLE_SIZE 384
/** The size in bytes of Generation I battle options. */
#define PKMN_GEN1_BATTLE_OPTIONS_SIZE 128
/** The size in bytes of Generation I chance actions. */
#define PKMN_GEN1_CHANCE_ACTIONS_SIZE 16
/** The size in bytes of a Generation I calc overrides. */
#define PKMN_GEN1_CALC_OVERRIDES_SIZE 24
/** The size in bytes of a Generation I calc summaries. */
#define PKMN_GEN1_CALC_SUMMARIES_SIZE 8

/** The minimum size in bytes required to hold the all Generation I choice options. */
extern const size_t PKMN_GEN1_MAX_CHOICES;
/**
 * The optimal size in bytes required to hold the all Generation I choice
 * options. At least as large as PKMN_GEN1_MAX_CHOICES.
 */
extern const size_t PKMN_GEN1_CHOICES_SIZE;
/** The maximum number of bytes possibly logged by a single Generation I update. */
extern const size_t PKMN_GEN1_MAX_LOGS;
/**
 * The optimal size in bytes required to hold the largest amount of log data
 * possible from a single Generation I update. At least as large as
 * PKMN_GEN1_MAX_LOGS.
 */
extern const size_t PKMN_GEN1_LOGS_SIZE;

/** Generation I Pokémon Battle (see src/lib/gen1/README.md#layout for details). */
PKMN_OPAQUE(PKMN_GEN1_BATTLE_SIZE) pkmn_gen1_battle;
/** Generation I Pokémon Battle options (fully opaque - uses getters to access). */
PKMN_OPAQUE(PKMN_GEN1_BATTLE_OPTIONS_SIZE) pkmn_gen1_battle_options;
/** Generation I Pokémon chance actions (see src/lib/gen1/README.md#layout for details). */
PKMN_OPAQUE(PKMN_GEN1_CHANCE_ACTIONS_SIZE) pkmn_gen1_chance_actions;
/** Generation I Pokémon calc overrides (see src/lib/gen1/README.md#layout for details). */
PKMN_OPAQUE(PKMN_GEN1_CALC_OVERRIDES_SIZE) pkmn_gen1_calc_overrides;
/** Generation I Pokémon calc summaries (see src/lib/gen1/README.md#layout for details). */
PKMN_OPAQUE(PKMN_GEN1_CALC_SUMMARIES_SIZE) pkmn_gen1_calc_summaries;

/**
 * Provides a buffer buf of length len to store protocol message logs if
 * protocol logging is enabled (see docs/PROTOCOL.md). This buffer should be
 * reset by calling pkmn_gen1_battle_options_set with NULL provided as the
 * second argument after each update.
 */
typedef struct {
  uint8_t *buf;
  size_t len;
} pkmn_gen1_log_options;
/**
 * Provides the probability and chance actions necessary for tracking chance
 * outcomes during a Generation I battle update if chance tracking is enabled.
 */
typedef struct {
  pkmn_rational probability;
  pkmn_gen1_chance_actions actions;
} pkmn_gen1_chance_options;
/**
 * Overrides to apply to the normal behavior of the RNG during a Generation I
 * battle `update` if damage calculation support is enabled.
 */
typedef struct {
  pkmn_gen1_calc_overrides overrides;
} pkmn_gen1_calc_options;
/**
 * Set or reset the Generation I battle options struct based on the log, chance,
 * and calc options provided. This function should usually be called before each
 * battle update first to initialize the battle options and then on subsequent
 * calls to "reset" the same struct so that it can be reused. Resets are
 * accomplished by passing NULL for any argument after the first.
 */
void pkmn_gen1_battle_options_set(
  pkmn_gen1_battle_options *options,
  const pkmn_gen1_log_options *log,
  const pkmn_gen1_chance_options *chance,
  const pkmn_gen1_calc_options *calc);
/**
 * Returns a pointer to a pkmn_rational containing the probability of the
 * actions taken by a hypothetical "chance player" occuring during a Generation
 * I battle update.
 */
pkmn_rational* pkmn_gen1_battle_options_chance_probability(
  const pkmn_gen1_battle_options *options);
/**
 * Returns a pointer to the actions taken by a hypothetical "chance player"
 * that convey information about which RNG events were observed during a
 * Generation I battle update.
 */
pkmn_gen1_chance_actions* pkmn_gen1_battle_options_chance_actions(
  const pkmn_gen1_battle_options *options);
/**
 * Returns a pointer to information relevant to damage calculation that occured
 * during a Generation I battle update.
 */
pkmn_gen1_calc_summaries* pkmn_gen1_battle_options_calc_summaries(
  const pkmn_gen1_battle_options *options);

/**
 * Returns the result of applying Player 1's choice c1 and Player 2's choice c2
 * to the Generation I battle. If the options argument is not NULL and the
 * relevant additional features are enabled it will be used to track additional
 * information about what happened during the update.
 */
pkmn_result pkmn_gen1_battle_update(
  pkmn_gen1_battle *battle,
  pkmn_choice c1,
  pkmn_choice c2,
  pkmn_gen1_battle_options *options);
/**
 * Fills in out with at most len possible choices for the player given the
 * request and Generation I battle state and returns the number of choices
 * available. Note that reading values in out which occur at indexes > the
 * return value of this function could result in reading potentially garbage
 * data.
 *
 * This function may return 0 due to how the Transform + Mirror Move/Metronome
 * PP error interacts with Disable, in which case there are no possible choices
 * for the player to make (i.e. on the cartridge a soft-lock occurs).
 *
 * This function will always return a number of choices > 0 if
 * PKMN_CHOICES.showdown is true.
 */
uint8_t pkmn_gen1_battle_choices(
  const pkmn_gen1_battle *battle,
  pkmn_player player,
  pkmn_choice_kind request,
  pkmn_choice out[],
  size_t len);

#undef PKMN_OPAQUE

#ifdef __cplusplus
}
#endif

#endif // LIBPKMN_H
