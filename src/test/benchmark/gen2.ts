import * as sim from '@pkmn/sim';
import {Generation, PokemonSet, StatsTable, ID} from '@pkmn/data';

import * as engine from '../../pkg';
// import * as gen2 from '../../pkg/gen2';
import {Lookup} from '../../pkg/data';
import {newSeed} from '../integration/common';

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
      const species = lookup.speciesByNum(prng.next(1, 251 + 1));
      const level = prng.randomChance(1, 20) ? prng.next(1, 99 + 1) : 100;
      const item = prng.randomChance(1, 10) ? undefined
        : lookup.itemByNum(prng.next(1, 62 + 1));

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
        evs[stat] = prng.randomChance(1, 20) ? prng.next(0, 255 + 1) : 255;
      }

      const moves: ID[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move: ID;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 250 + 1)))));
        moves.push(move);
      }

      const happiness = prng.randomChance(1, 10 + 1) ? prng.next(0, 255) : 255;
      team.push({species, level, item, ivs, evs, moves, happiness});
    }

    return {team};
  }
};

export const Choices = new class {
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

      const before = options.length;
      let slot = 0;
      for (const move of active.moveSlots) {
        slot++;
        if (move.pp === 0 || move.disabled) continue;
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

export class RandomPlayerAI extends sim.BattleStreams.BattlePlayer {
  readonly battleStream: sim.BattleStreams.BattleStream;
  readonly id: engine.Player;
  readonly prng: sim.PRNG;

  constructor(
    playerStream: sim.Streams.ObjectReadWriteStream<string>,
    battleStream: sim.BattleStreams.BattleStream,
    id: engine.Player,
    prng: sim.PRNG
  ) {
    super(playerStream);
    this.battleStream = battleStream;
    this.id = id;
    this.prng = prng;
  }

  override receiveRequest(_: sim.AnyObject) {
    const options = Choices.sim(this.battleStream.battle!, this.id);
    const choice = options[this.prng.next(options.length)];
    if (choice) this.choose(choice);
  }
}
