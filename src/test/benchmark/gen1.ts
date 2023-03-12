import * as sim from '@pkmn/sim';
import {Generation, PokemonSet, StatsTable, ID} from '@pkmn/data';

import * as engine from '../../pkg';
import * as gen1 from '../../pkg/gen1';
import {Lookup} from '../../pkg/data';
import {newSeed} from '../integration/common';

import blocklistJSON from '../blocklist.json';

const BLOCKLIST = blocklistJSON[1].moves as ID[];

export const Battle = new class {
  random(gen: Generation, prng: sim.PRNG): engine.Battle {
    return engine.Battle.create(gen, this.options(gen, prng));
  }

  options(gen: Generation, prng: sim.PRNG): engine.CreateOptions {
    return {
      seed: newSeed(prng),
      p1: Player.options(gen, prng),
      p2: Player.options(gen, prng),
      showdown: true,
      log: false,
    };
  }
};

const Player = new class {
  options(gen: Generation, prng: sim.PRNG): Omit<engine.PlayerOptions, 'name'> {
    const lookup = Lookup.get(gen);

    const team: Partial<PokemonSet>[] = [];
    const n = prng.randomChance(1, 100) ? prng.next(1, 5 + 1) : 6;
    for (let i = 0; i < n; i++) {
      const species = lookup.speciesByNum(prng.next(1, 151 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;

      const ivs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'hp' || stat === 'spd') continue;
        ivs[stat] = gen.stats.toIV(prng.randomChance(1, 5) ? prng.next(1, 15 + 1) : 15);
      }
      ivs.hp = gen.stats.toIV(gen.stats.getHPDV(ivs));
      ivs.spd = ivs.spa;

      const evs = {} as StatsTable;
      for (const stat of gen.stats) {
        if (stat === 'spd') break;
        const exp = prng.randomChance(1, 20) ? prng.next(0, 0xFFFF + 1) : 0xFFFF;
        evs[stat] = Math.floor(Math.min(255, Math.ceil(Math.sqrt(exp))) / 4);
      }
      evs.spd = evs.spa;

      const moves: ID[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move: ID;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 164 + 1)))) ||
          BLOCKLIST.includes(move));
        moves.push(move);
      }

      team.push({species, level, ivs, evs, moves});
    }

    return {team};
  }
};

export const Choices = new class {
  engine(battle: gen1.Battle, id: engine.Player, result: engine.Result): engine.Choice[] {
    switch (result[id]) {
    case 'pass': {
      return [{type: 'pass', data: 0}];
    }
    case 'switch': {
      const options: engine.Choice[] = [];
      const side = battle.side(id);
      for (let slot = 2; slot <= 6; slot++) {
        const pokemon = side.get(slot as engine.Slot);
        if (!pokemon || pokemon.hp === 0) continue;
        options.push({type: 'switch', data: slot});
      }
      return options.length === 0 ? [{type: 'pass', data: 0}] : options;
    }
    case 'move': {
      const options: engine.Choice[] = [];

      const side = battle.side(id);
      const active = side.active!;

      if (active.forced) {
        return [{type: 'move', data: 0}];
      }

      for (let slot = 2; slot <= 6; slot++) {
        const pokemon = side.get(slot as engine.Slot);
        if (!pokemon || pokemon.hp === 0) continue;
        options.push({type: 'switch', data: slot});
      }

      let slot = 0;
      if (active.limited) {
        const last = side.lastSelectedMove!;
        for (const move of active.moves) {
          if (move.id === last) {
            options.push({type: 'move', data: move.pp === 0 && move.id === 'bide' ? 0 : slot});
            return options;
          }
        }
      }

      slot = 0;
      const before = options.length;
      for (const move of active.moves) {
        slot++;
        if (move.pp === 0 || move.disabled) continue;
        options.push({type: 'move', data: slot});
      }
      if (options.length === before) {
        // Struggle (Pokémon Showdown would use `move 1` here)
        options.push({type: 'move', data: 0});
      }

      return options;
    }
    }
  }

  sim(this: void, battle: sim.Battle, id: engine.Player): string[] {
    const request = battle[id]!.activeRequest;
    if (!request || request.wait) return [];

    if (request.forceSwitch) {
      const options: string[] = [];
      const side = battle[id]!;
      for (let slot = 2; slot <= 6; slot++) {
        const pokemon = side.pokemon[slot - 1];
        if (!pokemon || pokemon.hp === 0) continue;
        options.push(`switch ${slot}`);
      }
      return options.length === 0 ? ['pass'] : options;
    } else if (request.active) {
      const options: string[] = [];

      const side = battle[id]!;
      const active = side.active[0];

      // Being "forced" on Pokémon Showdown sets "trapped"
      if (active.trapped) {
        const forced = active.trapped && request.active[0].moves.length === 1;
        if (forced) return ['move 1'];
      } else {
        for (let slot = 2; slot <= 6; slot++) {
          const pokemon = side.pokemon[slot - 1];
          if (!pokemon || pokemon.hp === 0) continue;
          options.push(`switch ${slot}`);
        }
      }

      const binding = active.volatiles['partialtrappinglock'];
      const before = options.length;
      let slot = 0;
      for (const move of active.moveSlots) {
        slot++;
        // Pokémon Showdown expect us to select 0 PP moves when binding as it disables
        // everything but the move we are to use (and forced trapping moves underflow)
        if ((move.pp === 0 && !binding) || move.disabled) continue;
        options.push(`move ${slot}`);
      }
      if (options.length === before) {
        // Struggle
        options.push('move 1');
      }

      return options;
    } else {
      throw new Error(`Unsupported request: ${JSON.stringify(request)}`);
    }
  }
};
