import * as fs from 'fs';
import * as path from 'path';
import * as tty from 'tty';
import {strict as assert} from 'assert';

import * as mustache from 'mustache';
import {minify} from 'html-minifier';

import {Generations, Generation, GenerationNum, PokemonSet} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';
import {PRNG, PRNGSeed, BattleStreams, ID, Streams} from '@pkmn/sim';
import {
  AIOptions, ExhaustiveRunner, ExhaustiveRunnerOptions,
  ExhaustiveRunnerPossibilities, RunnerOptions,
} from '@pkmn/sim/tools';

import * as engine from '../../pkg';
import {Frame, display} from '../display';
import {PatchedBattleStream, patch, FILTER, formatFor} from '../showdown/common';

import blocklistJSON from '../blocklist.json';

const ROOT = path.resolve(__dirname, '..', '..', '..');
const TEMPLATE = path.join(ROOT, 'src', 'test', 'integration', 'showdown.html.tmpl');
const ANSI = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;

const CWD = process.env.INIT_CWD || process.env.CWD || process.cwd();

const BLOCKLIST = blocklistJSON as {[gen: number]: Partial<ExhaustiveRunnerPossibilities>};

// We first play out a normal battle with Pokémon Showdown, saving the raw input
// log and each of the chunks that are output. We then set up a battle with the
// @pkmn/engine (configured with -Dshowdown and -Dtrace) and confirm that the
// engine produces the same chunks of output given the same input.
//
// The are several challenges:
//
//   - we need to patch Pokémon Showdown to make its speed ties sane
//     (PatchedBattleStream/patch)
//   - we need to ensure the ExhaustiveRunner doesn't generate teams with moves
//     that are too broken for the engine to be able to match (possibilities)
//     and we need to massage the teams it produces to ensure they are legal for
//     the generation in question (fixTeams)
//   - Pokémon Showdown's output contains a bunch of protocol messages which are
//     redundant that need to filter out. Furthermore we also only want to
//     compare parsed output because the raw output produced by Pokémon Showdown
//     needs to get parsed first anyway (compare)
//   - the RandomPlayerAI can sometimes make "unavailable" choices because it
//     doesn't have perfect information, only we can't apply those choices to
//     the engine as that will result in undefined behavior (nextChoices)
//
// TODO: further documentation
//
// FIXME: deal with racy BattleStream issues!
class Runner {
  private readonly gen: Generation;
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options: AIOptions & {team: PokemonSet[]};
  private readonly p2options: AIOptions & {team: PokemonSet[]};

  constructor(gen: Generation, options: RunnerOptions) {
    this.gen = gen;
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);

    this.p1options = fixTeam(gen, options.p1options!);
    this.p2options = fixTeam(gen, options.p2options!);
  }

  async run() {
    return play(
      this.gen,
      {formatid: this.format, seed: this.prng.seed},
      {spec: {name: 'Bot 1', ...this.p1options}, start: s => this.p1options.createAI(s, {
        seed: newSeed(this.prng), move: 0.7, mega: 0.6, ...this.p1options,
      }).start()},
      {spec: {name: 'Bot 2', ...this.p2options}, start: s => this.p2options.createAI(s, {
        seed: newSeed(this.prng), move: 0.7, mega: 0.6, ...this.p2options,
      }).start()},
    );
  }
}

interface PlayerOptions {
  spec: {name: string; team: PokemonSet[]};
  start?: (s: Streams.ObjectReadWriteStream<string>) => Promise<void>;
}

async function play(
  gen: Generation,
  spec: {formatid: string; seed: PRNGSeed},
  p1options: PlayerOptions,
  p2options: PlayerOptions,
  input?: string[],
) {
  const buf = [];
  const frames: Frame[] = [];
  const rawBattleStream = new RawBattleStream();
  const seed = spec.seed;
  let partial: Partial<Frame> = {};
  try {
    const streams = BattleStreams.getPlayerStreams(rawBattleStream);

    const start = streams.omniscient.write(
      `>start ${JSON.stringify(spec)}\n` +
      `>player p1 ${JSON.stringify(p1options.spec)}\n` +
      `>player p2 ${JSON.stringify(p2options.spec)}`
    );

    const p1 = input ? replay(streams.p1, '>p1', input) : p1options.start!(streams.p1);
    const p2 = input ? replay(streams.p2, '>p2', input) : p2options.start!(streams.p2);

    for await (const chunk of streams.omniscient) {
      buf.push(chunk);
    }

    await Promise.all([start, p1, p2, streams.omniscient.writeEnd()]);

    const options =
      {p1: p1options.spec, p2: p2options.spec, seed: spec.seed, showdown: true, log: true};
    const battle = engine.Battle.create(gen, options);
    const log = new engine.Log(gen, engine.Lookup.get(gen), options);

    let c1 = engine.Choice.pass();
    let c2 = engine.Choice.pass();

    let index = 0;

    let result: engine.Result = {type: undefined, p1: 'pass', p2: 'pass'};
    for (const chunk of buf) {
      assert.equal(result.type, undefined);
      result = battle.update(c1, c2);

      partial.result = result;
      partial.battle = battle.toJSON();
      const parsed = Array.from(log.parse(battle.log!));
      partial.parsed = parsed;

      if (result.type === 'win') {
        assert.equal(rawBattleStream.battle!.winner, options.p1.name);
      } else if (result.type === 'lose') {
        assert.equal(rawBattleStream.battle!.winner, options.p2.name);
      } else if (result.type === 'tie') {
        assert.equal(rawBattleStream.battle!.winner, '');
      } else if (result.type) {
        throw new Error('Battle ended in error with -Dshowdown');
      }

      [c1, c2, index] =
        nextChoices(battle, result, rawBattleStream.rawInputLog, index);
      frames.push({c1, c2, ...partial} as Frame);
      partial = {};

      compare(gen, chunk, parsed);
    }

    assert.equal(rawBattleStream.rawInputLog.length, index);
    assert.notEqual(result.type, undefined);
  } catch (err: any) {
    try {
      if (!input) console.error('');
      dump(
        gen,
        err.stack.replace(ANSI, ''),
        toBigInt(seed),
        rawBattleStream.rawInputLog,
        buf.join('\n'),
        frames,
        partial,
      );
    } catch (e) {
      console.error(e);
    }
    throw err;
  }
}

async function replay(
  stream: Streams.ObjectReadWriteStream<string>,
  prefix: string,
  log: string[]
) {
  let index = 0;
  let chunk;
  while ((chunk = await stream.read())) {
    if (!chunk.startsWith('|request|')) continue;
    const request = JSON.parse(chunk.substring(9));
    if (request.wait) continue;
    while (index < log.length) {
      if (log[index].startsWith(prefix)) {
        // Pokémon Showdown is literally designed to be broken
        // eslint-disable-next-line @typescript-eslint/no-floating-promises
        stream.write(log[index++].slice(4));
        break;
      }
      index++;
    }
  }
}

function dump(
  gen: Generation,
  error: string,
  seed: bigint,
  input: string[],
  output: string,
  frames: Frame[],
  partial: Partial<Frame>,
) {
  const color = (s: string) => tty.isatty(2) ? `\x1b[36m${s}\x1b[0m` : s;
  const box = (s: string) =>
    `╭${'─'.repeat(s.length + 2)}╮\n│\u00A0${s}\u00A0│\n╰${'─'.repeat(s.length + 2)}╯`;
  const pretty = (file: string) => color(path.relative(CWD, file));

  const dir = path.join(ROOT, 'logs');
  try {
    fs.mkdirSync(dir, {recursive: true});
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
  }

  const hex = `0x${seed.toString(16).toUpperCase()}`;
  let file = path.join(dir, `${hex}.input.log`);
  let link = path.join(dir, 'input.log');
  fs.writeFileSync(file, input.join('\n'));
  symlink(file, link);
  console.error(box(`npm run integration ${path.relative(CWD, file)}`));

  file = path.join(dir, `${hex}.pkmn.html`);
  link = path.join(dir, 'pkmn.html');
  fs.writeFileSync(file, display(gen, true, error, seed, frames, partial));
  console.error(' ◦ @pkmn/engine:', pretty(symlink(file, link)), '->', pretty(file));

  file = path.join(dir, `${hex}.showdown.html`);
  link = path.join(dir, 'showdown.html');
  fs.writeFileSync(file, minify(
    mustache.render(fs.readFileSync(TEMPLATE, 'utf8'), {
      seed: hex,
      input: input.slice(3).join('\n'),
      output,
    }), {minifyCSS: true, minifyJS: true}
  ));

  console.error(' ◦ Pokémon Showdown:', pretty(symlink(file, link)), '->', pretty(file), '\n');
}

function symlink(from: string, to: string) {
  fs.rmSync(to, {force: true});
  fs.symlinkSync(from, to);
  return to;
}

class RawBattleStream extends PatchedBattleStream {
  readonly rawInputLog: string[] = [];

  override _write(message: string) {
    this.rawInputLog.push(message);
    super._write(message);
  }
}

type Writeable<T> = { -readonly [P in keyof T]: T[P] };

// Compare Pokémon Showdown vs. @pkmn/engine output, after parsing the protocol
// and filtering out redundant messages / smoothing over any differences
//
//   - Pokémon Showdown includes `[of]` on `|-damage|` messages for status
//     damage but the engine doesn't keep track of this as its redundant
//     information that requires additional state to support
//   - Pokémon Showdown protocol includes the `tox` status even in generations
//     where Toxic is not actually a status. This is only relevant in the
//     initial `|-status|` message as the text formatter uses this to decide
//     whether to output "poisoned" vs. "badly poisoned", though this is
//     possible to accomplish by simply tracking the prior `|move|` message so
//     isn't necessary
//   - Similarly, when a Pokémon which was previously badly poisoned switches
//     back in, a `|-status|IDENT|psn|[silent]` message will be logged. This is
//     incorrect as Toxic is not actually a status in Gen 1 and the Toxic
//     volatile gets removed on switch *out* not switch *in*, and as such the
//     engine does not attempt to reproduce this. If we receive one of these
//     messages we just verify that its for the scenario we expect and ignore it
//   - The engine cannot always infer `[from]` on `|move|` and so if we see that
//     the engine's output is missing it we also need to remove it from Pokémon
//     Showdown's (we can't just always indiscriminately remove it because we
//     want to ensure that it matches when present)
//
// TODO: can we always infer done/start/upkeep?
function compare(gen: Generation, chunk: string, actual: engine.ParsedLine[]) {
  const buf: engine.ParsedLine[] = [];
  let i = 0;
  for (const {args, kwArgs} of Protocol.parse(chunk)) {
    if (FILTER.has(args[0])) continue;
    const a = args.slice() as Writeable<Protocol.ArgType>;
    const kw = {...kwArgs} as Protocol.KWArgType;
    switch (args[0]) {
    case 'move': {
      const keys = kwArgs as Protocol.KWArgs['|move|'];
      if (keys.from && !(actual[i].kwArgs as Protocol.KWArgs['|move|']).from) {
        delete (kw as any).from;
      }
      break;
    }
    case 'switch': {
      a[3] = fixHPStatus(gen, args[3]);
      break;
    }
    case '-heal':
    case '-damage': {
      a[2] = fixHPStatus(gen, args[2]);
      const keys = kwArgs as Protocol.KWArgs['|-heal|' | '|-damage|'];
      if (keys.from && !['drain', 'Recoil'].includes(keys.from)) {
        delete (kw as any).of;
      }
      break;
    }
    case '-status':
    case '-curestatus': {
      if (args[0] === '-status') {
        const keys = kwArgs as Protocol.KWArgs['|-status|'];
        if (keys.silent) {
          assert.strictEqual(args[2], 'psn');
          continue;
        }
      }
      a[2] = args[2] === 'tox' ? 'psn' : args[2];
      break;
    }
    }
    assert.deepStrictEqual(actual[i], {args: a, kwArgs: kw});
    i++;
  }
  return buf;
}

function fixHPStatus(gen: Generation, hpStatus: Protocol.PokemonHPStatus) {
  return (gen.num < 3 && hpStatus.endsWith('tox')
    ? `${hpStatus.slice(0, -3)}psn` as Protocol.PokemonHPStatus
    : hpStatus);
}

const IGNORE = /^>(version|start|player)/;
const MATCH = /^>(p1|p2) (?:(pass)|((move) ([1-4]))|((switch) ([2-6])))/;

// Figure out the next valid choices for the players given the input log
function nextChoices(battle: engine.Battle, result: engine.Result, input: string[], index: number) {
  // The RandomPlayerAI doesn't send "pass" on wait requests (it just does
  // waits...) so we need to determine when the AI would have been forced to
  // pass and fill that in. Otherwise we set the choice to undefined and
  // determine what the choice was by processing the input log
  const initial = (player: engine.Player) => {
    const options = battle.choices(player, result);
    return (options.length === 1 && options[0].type === 'pass') ? engine.Choice.pass() : undefined;
  };

  const choices: {p1: engine.Choice | undefined; p2: engine.Choice | undefined} =
    {p1: initial('p1'), p2: initial('p2')};

  // Iterate over the input log from where we last stopped while at least one
  // player still needs a choice and try to parse out choices from the raw
  // input. If we find a choice for a player that already has one assigned then
  // the engine and Pokémon Showdown disagree on the possible options (the
  // engine either thought the player was forced to "pass" and assigned a choice
  // above, or we received two inputs for one player and zero for the other
  // meaning the other player should have passed but didn't, or the player made
  // an unavailable choice which we didn't skip as invalid)
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

    // Ensure the choice we parsed from the input log is actually valid for the
    // player - its possible that the RandomPlayerAI made an "unavailable"
    // choice, in which case we simply continue to the next input to determine
    // what the *actual* choice should be
    for (const choice of battle.choices(player, result)) {
      if (choice.type === type && choice.data === data) {
        choices[player] = choice;
        break;
      }
    }

    index++;
  }

  // If we iterated through the entire input log and still don't have a choice
  // for both players then we screwed up somehow
  const unresolved = [];
  if (!choices.p1) unresolved.push('p1');
  if (!choices.p2) unresolved.push('p2');
  if (unresolved.length) {
    throw new Error(`Unable to resolve choices for ${unresolved.join(', ')}`);
  }

  return [choices.p1!, choices.p2!, index] as const;
}

// The ExhaustiveRunner does not do a good job at ensuring the sets it generates
// are legal for old generations - these would usually be corrected by the
// TeamValidator but custom games bypass this so we need to massage the faulty
// set data ourselves
function fixTeam(gen: Generation, options: AIOptions) {
  for (const pokemon of options.team!) {
    const species = gen.species.get(pokemon.species)!;
    if (gen.num <= 1) {
      pokemon.ivs.hp = gen.stats.getHPDV(pokemon.ivs);
      pokemon.ivs.spd = pokemon.ivs.spa;
      pokemon.evs.spd = pokemon.evs.spa;
    }
    if (gen.num <= 2) {
      delete pokemon.shiny;
      pokemon.nature = '';
      if (gen.num > 1) {
        pokemon.gender = species.gender ??
          gen.stats.toDV(pokemon.ivs.atk) >= species.genderRatio.F * 16 ? 'M' : 'F';
      }
    }
  }
  return options as AIOptions & {team: PokemonSet[]};
}

// This is a fork of the possibilities function (which is used to build up the
// various "pools" of effects to proc during testing) from @pkmn/sim that has
// been extended to also enforce the engine's BLOCKLIST
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

export async function run(gens: Generations, options: string | Options) {
  if (typeof options === 'string') {
    const file = path.join(ROOT, 'logs', `${options}.input.log`);
    if (fs.existsSync(file)) options = file;
    const log = fs.readFileSync(path.resolve(CWD, options), 'utf8');
    const gen = gens.get(log.charAt(23));
    patch.generation(gen);

    const lines = log.split('\n');
    const spec = JSON.parse(lines[0].slice(7)) as {formatid: string; seed: PRNGSeed};
    const p1 = {spec: JSON.parse(lines[1].slice(10)) as {name: string; team: PokemonSet[]}};
    const p2 = {spec: JSON.parse(lines[2].slice(10)) as {name: string; team: PokemonSet[]}};
    await play(gen, spec, p1, p2, lines.slice(3));
    return 0;
  }

  const opts: ExhaustiveRunnerOptions = {
    cycles: 1, maxFailures: 1, log: false, ...options, format: '',
    cmd: (cycles: number, format: string, seed: string) =>
      `npm run integration -- --cycles=${cycles} --gen=${format[3]} --seed=${seed}`,
  };

  let failures = 0;
  const start = Date.now();
  do {
    for (const gen of gens) {
      if (gen.num > 1) break;
      if (options.gen && gen.num !== options.gen) continue;
      patch.generation(gen);
      opts.format = formatFor(gen);
      opts.possible = possibilities(gen);
      failures +=
        await (new ExhaustiveRunner({...opts, runner: o => new Runner(gen, o).run()}).run());
      if (failures >= opts.maxFailures!) return failures;
    }
  } while (Date.now() - start < (options.duration || 0));

  return failures;
}

export const newSeed = (prng: PRNG) => [
  prng.next(0x10000), prng.next(0x10000), prng.next(0x10000), prng.next(0x10000),
] as PRNGSeed;

export const toBigInt = (seed: PRNGSeed) =>
  ((BigInt(seed[0]) << 48n) | (BigInt(seed[1]) << 32n) |
   (BigInt(seed[2]) << 16n) | BigInt(seed[3]));
