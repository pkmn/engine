import * as sim from '@pkmn/sim';
import {Generation, PokemonSet, SideID, StatsTable} from '@pkmn/data';

import * as engine from '../../pkg';
import * as gen1 from '../../pkg/gen1';
import {Lookup} from '../../pkg/data';
import {newSeed} from './common';

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
      const species = lookup.specieByNum(prng.next(1, 151 + 1));
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
        ivs[stat] = prng.randomChance(1, 20) ? prng.next(0, 255 + 1) : 255;
      }
      evs.spd = evs.spa;

      const moves: string[] = [];
      const m = prng.randomChance(1, 100) ? prng.next(1, 3 + 1) : 4;
      for (let j = 0; j < m; j++) {
        let move;
        while (moves.includes((move = lookup.moveByNum(prng.next(1, 165 + 1)))));
        moves.push(move);
      }

      team.push({species, level, ivs, evs, moves});
    }

    return {team};
  }
};

export const Choices = new class {
  engine(battle: gen1.Battle, id: SideID, request: engine.Choice['type']): engine.Choice[] {
    switch (request) {
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
      const foe = battle.foe(id);

      const active = side.active!;

      if (foe.active!.volatile(gen1.Pokemon.Volatiles.Trapping)) {
        const locked =
          active.volatile(gen1.Pokemon.Volatiles.Recharging) ||
          active.volatile(gen1.Pokemon.Volatiles.Rage) ||
          active.volatile(gen1.Pokemon.Volatiles.Thrashing) ||
          active.volatile(gen1.Pokemon.Volatiles.Charging) ||
          active.volatile(gen1.Pokemon.Volatiles.Bide) ||
          active.volatile(gen1.Pokemon.Volatiles.Trapping);
        if (locked) return [{type: 'move', data: 0}];
      } else {
        for (let slot = 2; slot <= 6; slot++) {
          const pokemon = side.get(slot as engine.Slot);
          if (!pokemon || pokemon.hp === 0) continue;
          options.push({type: 'switch', data: slot});
        }
      }

      const before = options.length;
      let slot = 0;
      for (const move of active.moves) {
        slot++;
        if (move.pp === 0 || move.disabled) continue;
        options.push({type: 'move', data: slot});
      }
      if (options.length === before) {
        options.push({type: 'move', data: 0}); // Struggle
      }

      return options;
    }
    }
  }

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

      const trapped = active.volatiles['partialtrappinglock'];
      if (trapped) {
        const locked = active.trapped && request.active[0].moves.length === 1;
        if (locked) return ['move 1'];
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
        // Pokémon Showdown expect us to select 0 PP moves when trapped
        if ((move.pp === 0 && !trapped) || move.disabled) continue;
        options.push(`move ${slot}`);
      }
      if (options.length === before) {
        options.push('move 1'); // Struggle
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
