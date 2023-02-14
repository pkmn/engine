#ifndef LIBPKMN_H
#define LIBPKMN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * Defines an opaque pkmn type. These are given a size so that they may be statically allocated but
 * must either be initialized with an init() function or manually depending on the type in question.
 */
#define PKMN_OPAQUE(n) typedef struct { uint8_t bytes[n]; }

/** The size in bytes of the Pokémon Showdown RNG (backed by a Generation V & VI RNG). */
#define PKMN_PSRNG_SIZE 8
/** The size in bytes of a Generation I battle. */
#define PKMN_GEN1_BATTLE_SIZE 384

/** Compile time options acknowledged by libpkmn. */
typedef struct {
    bool showdown;
    bool trace;
} pkmn_options;
/** Compile time options set when libpkmn was built. */
extern const pkmn_options PKMN_OPTIONS;

/** The minimum size in bytes required to hold all choice options. */
extern const size_t PKMN_MAX_OPTIONS;
/**
 * The optimal size in bytes required to hold all choice options.
 * At least as large as PKMN_MAX_OPTIONS.
 */
extern const size_t PKMN_OPTIONS_SIZE;
/**
 * The minimum size in bytes required to hold the largest amount of log data possible
 * from a single update.
 */
extern const size_t PKMN_MAX_LOGS;
/**
 * The optimal size in bytes required to hold the largest amount of log data possible
 * from a single update. At least as large as PKMN_MAX_LOGS.
 */
extern const size_t PKMN_LOG_SIZE;

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
/** Returns a choice initialized for a specific type with the provided data. data must be <= 6. */
pkmn_choice pkmn_choice_init(pkmn_choice_kind type, uint8_t data);

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
 * Whether or not the update resulted in an error being thrown. This can only happen if libpkmn was
 * built with trace logging enabled and the buffer provided to the update function was not large
 * enough to hold all of the data (which is only possible if the buffer being used was smaller than
 * generation in question's MAX_LOGS bytes).
 */
bool pkmn_error(pkmn_result result);

/** Pokémon Showdown's RNG (backed by a Generation V & VI RNG). */
PKMN_OPAQUE(PKMN_PSRNG_SIZE) pkmn_psrng;
/** Initialize the Pokémon Showdown RNG with the given seed. */
void pkmn_psrng_init(pkmn_psrng *psrng, uint64_t seed);
/** Returns the next number produced by the Pokémon Showdown RNG and advances the seed. */
uint32_t pkmn_psrng_next(pkmn_psrng *psrng);

/** The minimum size in bytes required to hold the all Generation I choice options. */
extern const size_t PKMN_GEN1_MAX_OPTIONS;
/**
 * The optimal size in bytes required to hold the all Generation I choice options.
 *  At least as large as PKMN_GEN1_MAX_OPTIONS.
 */
extern const size_t PKMN_GEN1_OPTIONS_SIZE;
/**
 * The minimum size in bytes required to hold the largest amount of log data possible
 * from a single Generation I update.
 */
extern const size_t PKMN_GEN1_MAX_LOGS;
/**
 * The optimal size in bytes required to hold the largest amount of log data possible
 * from a single Generation I update. At least as large as PKMN_GEN1_MAX_LOGS.
 */
extern const size_t PKMN_GEN1_LOG_SIZE;

/** Generation I Pokémon Battle (see src/lib/gen1/README.md#layout for details). */
PKMN_OPAQUE(PKMN_GEN1_BATTLE_SIZE) pkmn_gen1_battle;
/**
 * Returns the result of applying Player 1's choice c1 and Player 2's choice c2 to the Generation I
 * battle. Writes up to len trace logs to buf if buf is not NULL and trace logging is enabled.
 */
pkmn_result pkmn_gen1_battle_update(
  pkmn_gen1_battle *battle,
  pkmn_choice c1,
  pkmn_choice c2,
  uint8_t *buf,
  size_t len);
/**
 * Fills in out with at most len possible choices for the player given the request and Generation I
 * battle state and returns the number of choices available.
 *
 * This function may return 0 due to how the Transform + Mirror Move/Metronome PP error interacts
 * with Disable, in which case there are no possible choices for the player to make (i.e. on the
 * cartridge a soft-lock occurs).
 *
 * This function will always return a number of choices > 0 if PKMN_OPTIONS.showdown is true.
 */
uint8_t pkmn_gen1_battle_choices(
  pkmn_gen1_battle *battle,
  pkmn_player player,
  pkmn_choice_kind request,
  pkmn_choice out[],
  size_t len);

#undef PKMN_OPAQUE

#ifdef __cplusplus
}
#endif

#endif // LIBPKMN_H
