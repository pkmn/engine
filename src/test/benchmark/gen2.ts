import * as sim from '@pkmn/sim';
import {Generation, PokemonSet, SideID, StatsTable, ID} from '@pkmn/data';

import * as engine from '../../pkg';
// import * as gen2 from '../../pkg/gen2';
import {Lookup} from '../../pkg/data';
import {newSeed} from './common';

// import blocklistJSON from '../blocklist.json';

// const BLOCKLIST = blocklistJSON[2].moves as ID[];

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
    // const lookup = Lookup.get(gen);
    const team: Partial<PokemonSet>[] = [];
    // TODO
    return {team};
  }
};

export const Choices = new class {
  sim(this: void, battle: sim.Battle, id: SideID): string[] {
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
  readonly id: SideID;
  readonly prng: sim.PRNG;

  constructor(
    playerStream: sim.Streams.ObjectReadWriteStream<string>,
    battleStream: sim.BattleStreams.BattleStream,
    id: SideID,
    prng: sim.PRNG
  ) {
    super(playerStream);
    this.battleStream = battleStream;
    this.id = id;
    this.prng = prng;
  }

  receiveRequest(_: sim.AnyObject) {
    const options = Choices.sim(this.battleStream.battle!, this.id);
    const choice = options[this.prng.next(options.length)];
    if (choice) this.choose(choice);
  }
}
