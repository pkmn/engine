import {
  BoostsTable, Generation, ID, PokemonSet, StatsTable, StatusName, TypeName,
} from '@pkmn/data';

import * as addon from './addon';
import {Lookup} from './data';
import * as gen1 from './gen1';

/** Representation of one of a battle's participants. */
export type Player = 'p1' | 'p2';
/** The one-indexed location of a player's Pokémon in battle. */
export type Slot = 1 | 2 | 3 | 4 | 5 | 6;

/** Representation of the entire state of a Pokémon battle. */
export type Battle = Gen1.Battle;
/** Representation of one side of a Pokémon battle's state. */
export type Side = Gen1.Side;
/** Representation of the state for single Pokémon in a battle. */
export type Pokemon = Gen1.Pokemon;
/** Representation of a Pokémon's move slot in a battle. */
export type MoveSlot = Gen1.MoveSlot;

/** Methods supported by a Battle. */
export interface API {
  /**
  * Returns the result of applying Player 1's choice `c1` and Player 2's choice
  * `c2` to the battle.
  */
  update(c1: Choice, c2: Choice): Result;
  /**
   * Returns all possible choices for the `player` given the previous `result`
   * of an {@link update}.
   *
   * This function may return zero results in Generation I if Pokémon Showdown
   * compatibility move is not enabled due to how the Transform + Mirror
   * Move/Metronome PP error interacts with Disable (i.e. on the cartridge a
   * soft-lock occurs).
   */
  choices(player: Player, result: Result): Choice[];
  /**
   * Determines all possible choices for the `player` given the previous
   * `result` of an {@link update} and calls a selection function `fn` with the
   * number of possible choices `n`, returning the choice corresponding with the
   * index it returns. `fn` must return an index in the range `[0, n)`.
   *
   * This function helps speed up MCTS-based agents which wish to avoid
   * decoding/allocating `Choice` objects which they ignore. Most other use
   * cases will likely be better served by the choices method.
   *
   * Note that the number of possible choices n passed to `fn` may be 0 as
   * outlined above in {@link choices}.
   */
  choose(player: Player, result: Result, fn: (n: number) => number): Choice;
}

/** Helper type removing API methods from a data type `T`. */
export type Data<T extends API> = Omit<T, keyof API>;

/** Type definitions for Generation I Pokémon data relevant in a battle. */
export namespace Gen1 {
  /** Representation of the entire state of a Generation I Pokémon battle. */
  export interface Battle extends API {
    /** The sides involved in the battle. */
    sides: Iterable<Side>;
    /** The battle's current turn number. */
    turn: number;
    /** The last damage dealt by either side. */
    lastDamage: number;
    /**
     * The RNG state - a 4-tuple representing 16-bit big-endian chunks of a
     * 64-bit state if Pokémon Showdown compatibility mode is enabled, otherwise
     * a 10-tuple with each value representing one byte of the RNG's current
     * state.
     */
    prng: readonly number[];
  }

  /** Representation of one side of a Generation I Pokémon battle's state. */
  export interface Side {
    /**
     * The active Pokémon for the side, or undefined if the battle has yet to
     * start. Note that fainted Pokémon are still consider "active" until their
     * replacement switches in.
     */
    active: Pokemon | undefined;
    /**
     * The player's party in its current order (e.g. after taking into account
     * the effect switching would have on its original order).
     */
    pokemon: Iterable<Pokemon>;
    /** The last move the player used. */
    lastUsedMove: ID | undefined;
    /** The last move the player selected. */
    lastSelectedMove: ID | undefined;
    /** The move slot index of the last selected move. */
    lastSelectedIndex: 1 | 2 | 3 | 4 | undefined;
  }

  /**
   * Representation of the state for single Generation I Pokémon in a battle.
   */
  export interface Pokemon {
    /**
     * The Pokémon's current species (which may differ from its original stored
     * species).
     */
    species: ID;
    /**
     * The Pokémon's current typing (which may differ from its original stored
     * types).
     */
    types: readonly [TypeName, TypeName];
    /** The Pokémon's level. */
    level: number;
    /** The Pokémon's current level. */
    hp: number;
    /** The Pokémon's current status. */
    status: StatusName | undefined;
    /** Additional data related to the Pokémon's status. */
    statusData: {
      /** If status is slp, the number of sleep turns remaining. */
      sleep: number;
      /** If status is slp, whether or not it was self-inflicted. */
      self: boolean;
      /** The state of the Toxic counter. */
      toxic: number;
    };
    /**
     * The Pokémon's current stats, after accounting for modification from
     * boosts/status/etc (and which may differ from its original stored stats).
     */
    stats: StatsTable;
    /** The Pokémon's current boosts. */
    boosts: BoostsTable;
    /**
     * The Pokémon's move slots (which may differ from its original stored
     * moves).
     */
    moves: Iterable<MoveSlot>;
    /** The Pokémon's volatiles statuses. */
    volatiles: Volatiles;
    stored: {
      /** The Pokémon's original species. */
      species: ID;
      /** The Pokémon's original typing. */
      types: readonly [TypeName, TypeName];
      /** The Pokémon original unmodified stats.  */
      stats: StatsTable;
      /** The Pokémon's original move slots.  */
      moves: Iterable<Omit<MoveSlot, 'disabled'>>;
    };
    /** The current one-indexed position of this Pokémon in the party. */
    position: Slot;
  }

  /** Representation of a Generation I Pokémon's move slot in a battle. */
  export interface MoveSlot {
    /** The identifier for the move. */
    id: ID;
    /** The remaining PP of the move. */
    pp: number;
    /** If present, the remaining number of turns this move slot is disabled. */
    disabled?: number;
  }

  /**
   * Representation of an active Generation I Pokémon's volatile status state in
   * a battle.
   */
  export interface Volatiles {
    /** Whether the "Bide" volatile status is present. */
    bide?: {
      /** The number of turns before energy is unleashed. */
      duration: number;
      /** The total damage accumulated by Bide. */
      damage: number;
    };
    /** Whether the "Thrashing" volatile status is present. */
    thrashing?: {
      /** The number of attacks remaining. */
      duration: number;
      /** The thrashing move's current accuracy as a number from 0-255. */
      accuracy: number;
    };
    /** Whether the "MultiHit" volatile status is present. */
    multihit?: unknown;
    /** Whether the "Flinch" volatile status is present. */
    flinch?: unknown;
    /** Whether the "Charging" volatile status is present. */
    charging?: unknown;
    /** Whether the "Binding" volatile status is present. */
    binding?: {
      /** The number of attacks remaining. */
      duration: number;
    };
    /** Whether the "Invulnerable" volatile status is present. */
    invulnerable?: unknown;
    /** Whether the "Confusion" volatile status is present. */
    confusion?: {
      /** The number of confusion turns remaining. */
      duration: number;
    };
    /** Whether the "Mist" volatile status is present. */
    mist?: unknown;
    /** Whether the "FocusEnergy" volatile status is present. */
    focusenergy?: unknown;
    /** Whether the "Substitute" volatile status is present. */
    substitute?: {
      /** The Substitute's current HP. */
      hp: number;
    };
    /** Whether the "Recharging" volatile status is present. */
    recharging?: unknown;
    /** Whether the "Rage" volatile status is present. */
    rage?: {
      /** Rage's current accuracy as a number from 0-255. */
      accuracy: number;
    };
    /** Whether the "LeechSeed" volatile status is present. */
    leechseed?: unknown;
    /** Whether the "LightScreen" volatile status is present. */
    lightscreen?: unknown;
    /** Whether the "Reflect" volatile status is present. */
    reflect?: unknown;
    /** Whether the "Transform" volatile status is present. */
    transform?: {
      /** Which player's Pokémon this Pokémon is transformed into. */
      player: 'p1' | 'p2';
      /** The slot number of the player's Pokémon. */
      slot: number;
    };
  }
}

/** Options for creating a battle via Battle.create. */
export type CreateOptions = {
  /**
   * The seed for the Battle's RNG - the expected format of this value depends
   * on the generation of the Battle being created.
   */
  seed: number[];
  /**
   * Whether or not create a Pokémon Showdown compatible battle or not (requires
   * that the engine be built in a specific compatibility mode).
   */
  showdown?: boolean;
} & ({
  /** Player 1's options. */
  p1: PlayerOptions;
  /** Player 2's options. */
  p2: PlayerOptions;
  /**
   * Whether to capture protocol trace logs. Note that if the engine itself was
   * not build with trace logging enabled then enabling this will have no
   * effect.
   */
  log: true;
} | {
  /** Player 1's options. */
  p1: Omit<PlayerOptions, 'name'>;
  /** Player 2's options. */
  p2: Omit<PlayerOptions, 'name'>;
  /**
   * Whether to capture protocol trace logs. Note that if the engine itself was
   * not build with trace logging enabled then enabling this will have no
   * effect.
   */
  log?: false;
});

/** Options for restoring a battle via Battle.restore. */
export type RestoreOptions = {
  /** Player 1's options. */
  p1: PlayerOptions;
  /** Player 2's options. */
  p2: PlayerOptions;
  /**
   * Whether or not create a Pokémon Showdown compatible battle or not (requires
   * that the engine be built in a specific compatibility mode).
   */
  showdown?: boolean;
  /**
   * Whether to capture protocol trace logs. Note that if the engine itself was
   * not build with trace logging enabled then enabling this will have no
   * effect.
   */
  log: true;
} | {
  /**
   * Whether or not create a Pokémon Showdown compatible battle or not (requires
   * that the engine be built in a specific compatibility mode).
   */
  showdown?: boolean;
  /**
   * Whether to capture protocol trace logs. Note that if the engine itself was
   * not build with trace logging enabled then enabling this will have no
   * effect.
   */
  log?: false;
};

/** Options about a particular player. */
export interface PlayerOptions {
  /** The player's name. */
  name: string;
  /** The player's team. */
  team: Partial<PokemonSet>[];
}

/** A choice made by a player during battle. */
export interface Choice {
  /** The choice type. */
  type: 'pass' | 'move' | 'switch';
  /**
   * The choice data:
   *
   *    - 0 for 'pass'
   *    - 0-4 for 'move'
   *    - 2-6 for 'switch'
   */
  data: number;
}

/**
 * The result of the battle - all defined results should be considered terminal.
 */
export interface Result {
  /**
   * The type of result from the perspective of Player 1:
   *
   *   - undefined: no result, battle is non-terminal
   *   - win: Player 1 wins
   *   - lose: Player 2 wins
   *   - tie: Player 1 & 2 tie
   *   - error: the battle has terminated in error (e.g. due to a desync)
   *
   * 'error' is not possible when in Pokémon Showdown compatibility mode.
   */
  type: undefined | 'win' | 'lose' | 'tie' | 'error';
  /** The choice type of the result for Player 1. */
  p1: Choice['type'];
  /** The choice type of the result for Player 2. */
  p2: Choice['type'];
}

/** Factory for creating Battle objects. */
export const Battle = new class {
  /** Create a `Battle` in the given generation with the provided options. */
  create(gen: Generation, options: CreateOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.create(gen, lookup, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }

  /**
   * Restore a (possibly in-progress) `Battle` in the given generation with the
   * provided options.
   */
  restore(gen: Generation, battle: Battle, options: RestoreOptions) {
    addon.check(!!options.showdown);
    const lookup = Lookup.get(gen);
    switch (gen.num) {
    case 1: return gen1.Battle.restore(gen, lookup, battle, options);
    default: throw new Error(`Unsupported gen ${gen.num}`);
    }
  }
};

/** Utilities for working with `Choice` objects. */
export class Choice {
  /** All valid choices types. */
  static Types = ['pass', 'move', 'switch'] as const;

  protected static PASS = {type: 'pass', data: 0} as const;
  protected static MATCH = /^(?:(pass)|((move) ([0-4]))|((switch) ([2-6])))$/;

  private constructor() {}

  /** Decode a choice from its binary representation. */
  static decode(byte: number): Choice {
    return {type: Choice.Types[byte & 0b11], data: byte >> 4};
  }

  /** Encode a choice to its binary representation. */
  static encode(choice?: Choice): number {
    return (choice
      ? (choice.data << 4 | (choice.type === 'pass' ? 0 : choice.type === 'move' ? 1 : 2))
      : 0);
  }

  /**
   * Parse a Pokémon Showdown choice string into a `Choice`.
   * Only numeric choice data is supported.
   */
  static parse(choice: string): Choice {
    const m = Choice.MATCH.exec(choice);
    if (!m) throw new Error(`Invalid choice: '${choice}'`);
    const type = (m[1] ?? m[3] ?? m[6]) as Choice['type'];
    const data = +(m[4] ?? m[7] ?? 0);
    return {type, data};
  }

  /** Formats a `Choice` ino a Pokémon Showdown compatible choice string. */
  static format(choice: Choice): string {
    return choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`;
  }

  /** Returns the "pass" `Choice`. */
  static pass(): Choice {
    return Choice.PASS;
  }

  /** Returns a "move" `Choice` with the provided data. */
  static move(data: 0 | 1 | 2 | 3 | 4): Choice {
    return {type: 'move', data};
  }

  /** Returns a "switch" `Choice` with the provided data. */
  static switch(data: 2 | 3 | 4 | 5 | 6): Choice {
    return {type: 'switch', data};
  }
}

/** Utilities for working with `Result` objects */
export class Result {
  /** All valid result types. */
  static Types = [undefined, 'win', 'lose', 'tie', 'error'] as const;

  private constructor() {}

  /** Decode a `Result` from its binary representation. */
  static decode(byte: number): Result {
    return {
      type: Result.Types[byte & 0b1111],
      p1: Choice.Types[(byte >> 4) & 0b11],
      p2: Choice.Types[byte >> 6],
    };
  }
}

export {ParsedLine, Info, SideInfo, PokemonInfo, Log} from './protocol';
export {Lookup} from './data';
