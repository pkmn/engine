import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import * as assert from 'assert/strict';

import {Generations, Generation, PokemonSet} from '@pkmn/data';
import {
  Dex, Battle, BattleStreams, ID, PRNG, PRNGSeed, Pokemon, Side, SideID, Streams, Teams,
} from '@pkmn/sim';

import {PatchedBattleStream, patch, formatFor} from '../showdown/common';
import {newSeed} from '../integration/common';

import * as engine from '../../pkg';
import * as gen1 from './gen1';

const ROOT = path.resolve(__dirname, '..', '..', '..');

class DirectBattle extends Battle {
  // Drop logs to minimize overhead
  override hint(hint: string, once?: boolean, side?: Side) { }
  override addSplit(side: SideID, secret: any[], shared?: any[]) { }
  override add(...parts: (any | (() => { side: SideID; secret: string; shared: string }))[]) { }
  override addMove(...args: any[]) { }
  override retargetLastMove(newTarget: Pokemon) { }

  // Override to avoid wasted |update| and |end| work
  override sendUpdates() {
    this.sentLogPos = this.log.length;
    if (!this.sentEnd && this.ended) {
      this.sentEnd = true;
    }
  }

  // Override to not call Side#emitRequest to avoid wasted |sideupdate| work
  override makeRequest(type?: 'teampreview' | 'move' | 'switch' | '') {
    if (type) {
      this.requestState = type;
      for (const side of this.sides) {
        side.clearChoice();
      }
    } else {
      type = this.requestState;
    }

    for (const side of this.sides) {
      side.activeRequest = null;
    }

    if (type === 'teampreview') {
      const pickedTeamSize = this.ruleTable.pickedTeamSize;
      this.add('teampreview' + (pickedTeamSize ? '|' + pickedTeamSize : ''));
    }

    const requests = this.getRequests(type);
    for (let i = 0; i < this.sides.length; i++) {
      // NOTE: avoiding needlessly stringify-ing the |sideupdate|
      this.sides[i].activeRequest = requests[i];
    }

    if (this.sides.every(side => side.isChoiceDone())) {
      throw new Error('Choices are done immediately after a request');
    }
  }
}

async function compare(gen: Generation, format: ID, original: PRNG, battles: number) {
  patch.generation(gen);
  const begin = +new Date();

  let choices: (battle: Battle, id: engine.Player) => string[];
  switch (gen.num) {
  case 1: choices = gen1.Choices.sim; break;
  default: throw new Error(`Unsupported gen: ${gen.num}`);
  }

  const choose = (battle: Battle, id: engine.Player, rand: PRNG) => {
    const options = choices(battle, id);
    const choice = options[rand.next(options.length)];
    if (choice) battle.choose(id, choice);
  };

  const newAI = (
    playerStream: Streams.ObjectReadWriteStream<string>,
    battleStream: BattleStreams.BattleStream,
    id: engine.Player,
    rand: PRNG
  ): BattleStreams.BattlePlayer => {
    switch (gen.num) {
    case 1: return new gen1.RandomPlayerAI(playerStream, battleStream, id, rand);
    default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const prngs = {stream: original.clone(), direct: original.clone()};
  let seeds: any = undefined;
  for (let i = 0; i < battles; i++) {
    seeds = {stream: prngs.stream.seed.slice(), direct: prngs.direct.seed.slice()};
    const battleStream = new PatchedBattleStream(false);
    {
      const options = gen1.Battle.options(gen, prngs.stream);
      const streams = BattleStreams.getPlayerStreams(battleStream);

      const spec = {formatid: format, seed: options.seed as PRNGSeed};
      const p1spec = {name: 'Player A', team: Teams.pack(options.p1.team as PokemonSet[])};
      const p2spec = {name: 'Player B', team: Teams.pack(options.p2.team as PokemonSet[])};
      const start = `>start ${JSON.stringify(spec)}\n` +
        `>player p1 ${JSON.stringify(p1spec)}\n` +
        `>player p2 ${JSON.stringify(p2spec)}`;

      const p1ai = newAI(streams.p1, battleStream, 'p1', new PRNG(newSeed(prngs.stream))).start();
      const p2ai = newAI(streams.p2, battleStream, 'p2', new PRNG(newSeed(prngs.stream))).start();

      await streams.omniscient.write(start);
      await streams.omniscient.readAll();
      await Promise.all([streams.omniscient.writeEnd(), p1ai, p2ai]);
      if (!battleStream.battle!.ended) throw new Error(`Unfinished ${format} battle ${i}`);
    }

    const options = gen1.Battle.options(gen, prngs.direct);
    const config = {formatid: format, seed: options.seed as PRNGSeed};
    const battle = new DirectBattle(config);
    patch.battle(battle);

    const p1rng = new PRNG(newSeed(prngs.direct));
    const p2rng = new PRNG(newSeed(prngs.direct));

    const team1 = Teams.pack(options.p1.team as PokemonSet[]);
    const team2 = Teams.pack(options.p2.team as PokemonSet[]);

    battle.setPlayer('p1', {name: 'Player A', team: team1});
    battle.setPlayer('p2', {name: 'Player B', team: team2});
    while (!battle.ended) {
      choose(battle, 'p1', p1rng);
      choose(battle, 'p2', p2rng);
    }

    try {
      assert.deepStrictEqual(battle.inputLog, battleStream.battle!.inputLog);
      assert.deepStrictEqual(prngs.direct.seed, prngs.stream.seed);
      assert.deepStrictEqual(battle.turn, battleStream.battle!.turn);
      assert.deepStrictEqual(battle.prng.seed, battleStream.battle!.prng.seed);
    } catch (err) {
      const dir = path.join(ROOT, 'logs');
      console.error(seeds);
      fs.writeFileSync(path.join(dir, 'BattleStream.input.log'), battleStream.battle!.inputLog.join('\n'));
      fs.writeFileSync(path.join(dir, 'DirectBattle.input.log'), battle.inputLog.join('\n'));
      throw err;
    }
    if (i && i % 100 === 0) console.log(i, `(${(+(new Date()) - begin) / 1000}s)`);
  }
}

(async () => {
  const gens = new Generations(Dex as any);
  const gen = gens.get(1);
  patch.generation(gen);
  const format = formatFor(gen);
  await compare(gen, format, new PRNG([54074, 50433, 44308, 15191]), +(process.argv[2] || 1e6));
})().catch(err => {
  console.error(err);
  process.exit(1);
});
