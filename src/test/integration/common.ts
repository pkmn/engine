import {strict as assert} from 'assert';

import {Generations, Generation, GenerationNum} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';
import {PRNG, PRNGSeed, BattleStreams, ID} from '@pkmn/sim';
import {
  AIOptions, ExhaustiveRunner, ExhaustiveRunnerOptions,
  ExhaustiveRunnerPossibilites, RunnerOptions,
} from '@pkmn/sim/tools';

import * as engine from '../../pkg';
import {PatchedBattleStream, patch, FILTER} from '../showdown/common';

import blocklistJSON from '../blocklist.json';

const FORMATS = ['gen1customgame'];
const BLOCKLIST = blocklistJSON as {[gen: number]: Partial<ExhaustiveRunnerPossibilites>};

// We first play out a normal battle with Pokémon Showdown, saving the raw input log and each of the
// chunks that are output. We then set up a battle with the @pkmn/engine (configured with -Dshowdown
// and -Dtrace) and confirm that the engine produces the same chunks of output given the same input.
//
// The are several challenges:
//
//   - we need to patch Pokémon Showdown to make its speed ties sane (PatchedBattleStream/patch)
//   - we need to ensure the ExhaustiveRunner doesn't generate teams with moves that are too
//     broken for the engine to be able to match (possibilities) and we need to massage the
//     teams it produces to ensure they are legal for the generation in question (fixTeams)
//   - Pokémon Showdown's output contains a bunch of protocol messages which are redundant so
//     we need to filter these out, and we also only want to compare parsed output because
//     the raw output produced by Pokémon Showdown needs to get parsed first anyway (parse)
//   - the RandomPlayerAI can sometimes make "unavailable" choices because it doesn't have perfect
//     information, only we can't apply those choices to the engine as that will result in
//     undefined behavior (nextChoices)
class Runner {
  private readonly gen: Generation;
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options: AIOptions;
  private readonly p2options: AIOptions;

  constructor(gen: Generation, options: RunnerOptions) {
    this.gen = gen;
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);

    this.p1options = fixTeam(gen, options.p1options!);
    this.p2options = fixTeam(gen, options.p2options!);
  }

  async run() {
    const rawBattleStream = new RawBattleStream(this.format);
    const streams = BattleStreams.getPlayerStreams(rawBattleStream);

    const spec = {formatid: this.format, seed: this.prng.seed};
    const p1spec = {name: 'Bot 1', ...this.p1options};
    const p2spec = {name: 'Bot 2', ...this.p2options};

    const p1 = this.p1options.createAI(streams.p2, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p1options,
    }).start();
    const p2 = this.p2options.createAI(streams.p1, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p2options,
    }).start();

    const start = streams.omniscient.write(
      `>start ${JSON.stringify(spec)}\n` +
      `>player p1 ${JSON.stringify(p1spec)}\n` +
      `>player p2 ${JSON.stringify(p2spec)}`
    );

    const buf = [];
    for await (const chunk of streams.omniscient) {
      buf.push(chunk);
    }

    await Promise.all([streams.p2.writeEnd(), p1, p2, start]);

    const options = {
      p1: {name: 'Bot 1', team: this.p1options.team!},
      p2: {name: 'Bot 2', team: this.p2options.team!},
      seed: spec.seed,
      showdown: true,
      log: true,
    };
    const battle = engine.Battle.create(this.gen, options);
    const log = new engine.Log(this.gen, engine.Lookup.get(this.gen), options);

    let c1 = engine.Choice.pass();
    let c2 = engine.Choice.pass();

    let input = 0;

    let result: engine.Result = {type: undefined, p1: 'pass', p2: 'pass'};
    for (const chunk of buf) {
      assert.equal(result.type, undefined);
      result = battle.update(c1, c2);
      if (result.type === 'win') {
        assert.equal(rawBattleStream.battle!.winner, options.p1.name);
      } else if (result.type === 'lose') {
        assert.equal(rawBattleStream.battle!.winner, options.p2.name);
      } else if (result.type === 'tie') {
        assert.equal(rawBattleStream.battle!.winner, '');
      } else if (result.type) {
        throw new Error('Battle ended in error which should be impossible with -Dshowdown');
      } else {
        assert.deepStrictEqual(parse(chunk), Array.from(log.parse(battle.log!)));
      }
      [c1, c2, input] = nextChoices(battle, result, rawBattleStream.rawInputLog, input);
    }

    assert.equal(rawBattleStream.rawInputLog.length, input);
    assert.notEqual(result.type, undefined);
  }

  // Same as PRNG#generatedSeed, only deterministic.
  // NOTE: advances this.prng's seed by 4.
  newSeed(): PRNGSeed {
    return [
      this.prng.next(0x10000),
      this.prng.next(0x10000),
      this.prng.next(0x10000),
      this.prng.next(0x10000),
    ];
  }
}

class RawBattleStream extends PatchedBattleStream {
  readonly format: string;
  readonly rawInputLog: string[];

  constructor(format: string) {
    super();
    this.format = format;
    this.rawInputLog = [];
  }

  _write(message: string) {
    this.rawInputLog.push(message);
    super._write(message);
  }
}

// Filter out redundant messages and parse the protocol into its final form
// TODO: can we always infer done/start/upkeep?
function parse(chunk: string) {
  const buf: Array<{args: Protocol.ArgType; kwArgs: Protocol.KWArgType}> = [];
  for (const {args, kwArgs} of Protocol.parse(chunk)) {
    if (FILTER.has(args[0])) continue;
    buf.push({args, kwArgs});
  }
  return buf;
}

// Figure out the next valid choices for the players given the input log
const IGNORE = /^>(version|start|player)/;
const MATCH = /^>(p1|p2) (?:(pass)|((move) ([1-4]))|((switch) ([2-6])))/;
function nextChoices(battle: engine.Battle, result: engine.Result, input: string[], index: number) {
  // The RandomPlayerAI doesn't sent "pass" on wait requests so we need to figure out when it would
  // be forced to pass and fill those in. Otherwise we set the choice to undefined and determine
  // the choice from the input log
  const initial = (player: engine.Player) => {
    const options = battle.choices(player, result);
    return (options.length === 1 && options[0].type === 'pass') ? engine.Choice.pass() : undefined;
  };

  const choices: {p1: engine.Choice | undefined; p2: engine.Choice | undefined} =
    {p1: initial('p1'), p2: initial('p2')};

  // Until we don't have choices for both players we iterate over the input log since our last index
  // and try to parse out choices from the raw input. If we find an choice for a player that already
  // has one assigned then the engine and Pokémon Showdown disagree on the possible options (the
  // engine either thought the player is forced to "pass" and assigned a choice above, or we
  // received two inputs for one player and zero for the other meaning the other player should have
  // passed but didn't *or* the player made an unavailable choice which we didn't skip as invalid)
  while (index < input.length && !(choices.p1 && choices.p2)) {
    const m = MATCH.exec(input[index]);
    if (!m) {
      if (!IGNORE.test(input[index])) {
        throw new Error(`Unexpected input ${index}: '${input[index]}'`);
      } else {
        index++;
        continue;
      }
    }
    const player = m[1] as engine.Player;
    const type = (m[2] ?? m[4] ?? m[7]) as engine.Choice['type'];
    const data = +(m[5] ?? m[8] ?? 0);

    const choice = choices[player];
    if (choice) {
      throw new Error(`Already have choice for ${player}: ` +
      `'${choice.type === 'pass' ? choice.type : `${choice.type} ${choice.data}`}' vs. ` +
      `'${type === 'pass' ? type : `${type} ${data}`}' `);
    }

    // Ensure the choice we parsed from the input log is actually valid for the player - its
    // possible that the RandomPlayerAI made an "unavailable" choice, in which case we simply
    // continue to the next input to determine what the *actual* choice should be
    for (const choice of battle.choices(player, result)) {
      if (choice.type === type && choice.data === data) {
        choices[player] = choice;
        break;
      }
    }

    index++;
  }

  // If we iterated through the entire input log and still don't have a choice for
  //  both players then we screwed up somehow
  const unresolved = [];
  if (!choices.p1) unresolved.push('p1');
  if (!choices.p2) unresolved.push('p2');
  if (unresolved.length) {
    throw new Error(`Unable to resolve choices for ${unresolved.join(', ')}`);
  }

  return [choices.p1!, choices.p2!, index] as const;
}

// The ExhaustiveRunner does not do a good job at ensuring the sets it generates are legal for
// old generations - these usually get corrected for formats which run through the TeamValidator,
// but custom games bypass this so we need to massage the fault set data ourselves
function fixTeam(gen: Generation, options: AIOptions) {
  for (const pokemon of options.team!) {
    if (gen.num === 1) {
      pokemon.ivs.spd = pokemon.ivs.spa;
      pokemon.evs.spd = pokemon.evs.spa;
      pokemon.nature = '';
    }
  }
  return options;
}

// This is a fork of the possibilities function upstream that has been extended to also enforce the
// BLOCKLIST - this is used to build up the various "pools" of effects to proc during testing
function possibilities(gen: Generation) {
  const blocked = BLOCKLIST[gen.num] || {};
  const pokemon = Array.from(gen.species).filter(p => !blocked.pokemon?.includes(p.id as ID) &&
    (p.name !== 'Pichu-Spiky-eared' && p.name.slice(0, 8) !== 'Pikachu-'));
  const items = gen.num < 2
    ? [] : Array.from(gen.items).filter(i => !blocked.items?.includes(i.id as ID));
  const abilities = gen.num < 3
    ? [] : Array.from(gen.abilities).filter(a => !blocked.abilities?.includes(a.id as ID));
  const moves = Array.from(gen.moves).filter(m => !blocked.moves?.includes(m.id as ID) &&
    (!['struggle', 'revivalblessing'].includes(m.id) &&
      (m.id === 'hiddenpower' || m.id.slice(0, 11) !== 'hiddenpower')));
  return {
    pokemon: pokemon.map(p => p.id as ID),
    items: items.map(i => i.id as ID),
    abilities: abilities.map(a => a.id as ID),
    moves: moves.map(m => m.id as ID),
  };
}

type Options = Pick<ExhaustiveRunnerOptions, 'log' | 'maxFailures' | 'cycles'> & {
  prng: PRNG | PRNGSeed;
  gen?: GenerationNum;
  duration?: number;
};

export async function run(gens: Generations, options: Options) {
  const opts: ExhaustiveRunnerOptions = {
    cycles: 1, maxFailures: 1, log: false, ...options, format: '',
  };

  let failures = 0;
  const start = Date.now();
  do {
    for (const format of FORMATS) {
      const gen = gens.get(format.charAt(3));
      if (options.gen && gen.num !== options.gen) continue;
      patch.generation(gen);
      opts.format = format;
      opts.possible = possibilities(gen);
      failures +=
        await (new ExhaustiveRunner({...opts, runner: o => new Runner(gen, o).run()}).run());
      if (opts.log) process.stdout.write('\n');
      if (failures >= opts.maxFailures!) return failures;
    }
  } while (Date.now() - start < (options.duration || 0));

  return failures;
}
