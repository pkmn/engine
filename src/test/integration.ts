import 'source-map-support/register';

import * as assert from 'assert/strict';
import * as fs from 'fs';
import * as path from 'path';
import * as tty from 'tty';

import {Generation, GenerationNum, Generations} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';
import {Battle, BattleStreams, Dex, ID, PRNG, PRNGSeed, Streams, Teams, toID} from '@pkmn/sim';
import * as sim from '@pkmn/sim/tools';
import minimist from 'minimist';

import * as engine from '../pkg';
import * as addon from '../pkg/addon';

import {Frame, render, toText} from './display';
import {Choices, FILTER, formatFor, patch} from './showdown';

const ROOT = path.resolve(__dirname, '..', '..');
const ANSI = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;

const CWD = process.env.INIT_CWD || process.env.CWD || process.cwd();

type RunnerOptions = sim.RunnerOptions & {usage: sim.ExhaustiveRunnerUsageTracker; errors?: Errors};
class Runner {
  private readonly gen: Generation;
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options: sim.AIOptions & {team: string};
  private readonly p2options: sim.AIOptions & {team: string};
  private readonly errors?: Errors;

  private readonly skip: boolean;
  private readonly debug: boolean;

  constructor(gen: Generation, options: RunnerOptions, debug?: boolean) {
    this.gen = gen;
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);

    const moves = new Set<ID>();
    this.p1options = fixTeam(gen, options.p1options!, moves);
    this.p2options = fixTeam(gen, options.p2options!, moves);
    this.errors = options.errors;
    this.skip = gen.num === 1 && validate(this.prng, moves, options.usage);

    this.debug = !!debug;
  }

  run() {
    // Generated a team which could result in a problematic scenario = skip &
    // try again! (note that validate marks used to ensure progress)
    if (this.skip) return Promise.resolve();

    const seed = this.prng.seed.slice() as PRNGSeed;
    const create = (o: sim.AIOptions) => (s: Streams.ObjectReadWriteStream<string>) =>
      o.createAI(s, {seed: newSeed(this.prng), move: 0.7, mega: 0.6, ...o});

    return Promise.resolve(play(
      this.gen,
      {formatid: this.format, seed},
      {spec: {name: 'Bot 1', ...this.p1options}, create: create(this.p1options)},
      {spec: {name: 'Bot 2', ...this.p2options}, create: create(this.p2options)},
      undefined,
      this.debug,
      this.errors,
    ));
  }
}

interface PlayerOptions {
  spec: {name: string; team: string};
  create?: (s: Streams.ObjectReadWriteStream<string>) => BattleStreams.BattlePlayer;
}

// THIS PLACE IS NOT A PLACE OF HONOR... NO HIGHLY ESTEEMED DEED IS COMMEMORATED
// HERE... NOTHING VALUED IS HERE. WHAT IS HERE IS DANGEROUS AND REPULSIVE TO
// US. THIS MESSAGE IS A WARNING ABOUT DANGER.
//
// Attempts to play out a Pokémon Showdown battle in lockstep with a
// @pkmn/engine (-Dshowdown -Dlog) battle via the ExhaustiveRunner and
// confirms that the engine produces the same chunks of output given the same
// input... only a lot of black magic and subterfuge is required to make this
// happen. First, we support both replaying from a past input log (which
// necessitates a fromInputLog function that can deal with Pokémon Showdown
// mutating the raw input by eliding "pass" choices and turning move slot
// indexes into IDs) as well as playing out a battle from a seed. To get the
// latter to work we have to jump through a number of hoops:
//
//   - we need to patch Pokémon Showdown to make its speed ties sane (patch)
//   - we need to ensure the ExhaustiveRunner doesn't generate teams with moves
//     that are too broken for the engine to be able to match (validate) and we
//     need to massage the teams it produces to ensure they are legal for the
//     generation in question (fixTeam)
//   - we can't use the ExhaustiveRunner/CoordinatedPlayerAI as Pokémon Showdown
//     intended because its BattleStream abstract is broken by design and the
//     data races will cause our test fail. Instead, we manually call the AI
//     player directly and spy on its choices (which is guaranteed not to race
//     because all calls involved are synchronous) to be able to actually commit
//     them at the same time with Battle.makeChoices
//   - we need to check if any problematic interactions have occured which
//     unimplementable by the engine and simply abort if so
//   - the CoordinatedPlayerAI can make "unavailable" choices, so we need to
//     first check whether the choice it chose was valid or not before saving it
//     (if its invalid we need to call Side.choose knowing that it will fail in
//     order for the activeRequest to be updated)
//   - Pokémon Showdown's output contains a bunch of protocol messages which are
//     redundant that need to filter out. Furthermore, we also only want to
//     compare parsed output because the raw output produced by Pokémon Showdown
//     needs to get parsed first anyway (compare)
//
// Along the way we keep track of all the relevant information to be able to
// display the full history of the battle in case of failure, writing the output
// to the logs/ directory for ease of debugging
function play(
  gen: Generation,
  {seed, formatid}: {formatid: string; seed: PRNGSeed},
  p1options: PlayerOptions,
  p2options: PlayerOptions,
  replay?: string[],
  debug?: boolean,
  errors?: Errors,
) {
  let c1 = engine.Choice.pass();
  let c2 = engine.Choice.pass();

  const frames: {pkmn: Frame[]; showdown: Frame[]} = {pkmn: [], showdown: []};
  const partial: {
    pkmn: Partial<Frame> & {battle?: engine.Data<engine.Battle>; parsed?: engine.ParsedLine[]};
    showdown: Partial<Frame> & {seed?: number[]; chunk?: string};
  } = {pkmn: {c1, c2}, showdown: {c1, c2}};

  // We can't pass p1/p2 via BattleOptions because that would cause the battle to
  // start before we could patch it, desyncing the PRNG due to spurious advances
  const control = new Battle({formatid: formatid as ID, seed, strictChoices: false, debug});
  patch.battle(control, true, debug);

  const players = replay ? undefined : {
    p1: p1options.create!(null! as any),
    p2: p2options.create!(null! as any),
  };

  // The engine requires we use the choice 'move 0' for Struggle but Pokémon
  // Showdown requires 'move 1'. We work with 'move 0' everywhere because it
  // contains more information than 'move 1', but we need to remember to map
  // back to 'move 1' when actual making a choice in a Pokémon Showodwn battle
  const adjust = (c: string) => c === 'move 0' ? 'move 1' : c;

  const choices = Choices.get(gen);
  const chose = {p1: c1, p2: c2};
  if (players) {
    players.p1.choose = c => {
      const struggle = control.p1.activeRequest!.active?.[0].moves?.[0].id === 'struggle';
      chose.p1 = struggle ? {type: 'move', data: 0} : engine.Choice.parse(c);
    };
    players.p2.choose = c => {
      const struggle = control.p2.activeRequest!.active?.[0].moves?.[0].id === 'struggle';
      chose.p2 = struggle ? {type: 'move', data: 0} : engine.Choice.parse(c);
    };
  }

  let index = 0;
  const getChoices = (): [engine.Choice, engine.Choice] => {
    if (replay) {
      [chose.p1, chose.p2, index] = fromInputLog(replay, index, {
        p1: choices(control, 'p1', 'move 0').map(engine.Choice.parse),
        p2: choices(control, 'p2', 'move 0').map(engine.Choice.parse),
      }, {
        p1: control.p1.active[0].moves.map(toID),
        p2: control.p2.active[0].moves.map(toID),
      });
    } else {
      for (const id of ['p1', 'p2'] as const) {
        const player = players![id];
        const request = control[id].activeRequest;
        if (!request || request.wait) {
          chose[id] = engine.Choice.pass();
        } else {
          player.receiveRequest(request);
          const c = engine.Choice.format(chose[id]);
          while (!choices(control, id, 'move 0').includes(c)) {
            // making the unavailable request forces activeRequest to get updated
            assert.ok(!control[id].choose(adjust(c)));
            player.receiveRequest(control[id].activeRequest!);
          }
        }
      }
    }
    return [chose.p1, chose.p2];
  };

  try {
    const valid = (result: engine.Result, id: engine.Player, choice: engine.Choice) => {
      const buf = [];
      for (const c of battle.choices(id, result)) {
        if (c.type === choice.type && c.data === choice.data) return '';
        buf.push(`'${engine.Choice.format(c)}'`);
      }
      const c = engine.Choice.format(choice);
      return `'${c}' is not one of ${id.toUpperCase()}'s choices: [${buf.join(', ')}]`;
    };

    const options = {
      p1: {name: p1options.spec.name, team: Teams.unpack(p1options.spec.team)!},
      p2: {name: p2options.spec.name, team: Teams.unpack(p2options.spec.team)!},
      seed, showdown: true, log: true,
    };
    const battle = engine.Battle.create(gen, options);
    const log = new engine.Log(gen, engine.Lookup.get(gen), options);

    let start = true;
    let result = engine.Result.decode(0);
    do {
      if (start) {
        control.setPlayer('p1', p1options.spec);
        control.setPlayer('p2', p2options.spec);
        start = false;
      } else {
        control.makeChoices(adjust(engine.Choice.format(c1)), adjust(engine.Choice.format(c2)));
        if (gen.num === 1 && problematic(control)) return;
      }

      const request = partial.showdown.result = toResult(control, p1options.spec.name);
      partial.showdown.seed = control.prng.seed.slice();

      const chunk = control.getDebugLog();
      partial.showdown.chunk = chunk;
      control.log.length = 0;

      result = battle.update(c1, c2);
      partial.pkmn.result = result;
      partial.pkmn.battle = battle.toJSON();

      const parsed = Array.from(log.parse(battle.log!));
      partial.pkmn.parsed = parsed;

      compare(chunk, parsed);
      assert.deepEqual(result, request);
      assert.deepEqual(battle.prng, control.prng.seed);

      if (replay && index >= replay.length) break;
      [c1, c2] = getChoices();
      partial.pkmn.c1 = partial.showdown.c1 = c1;
      partial.pkmn.c2 = partial.showdown.c2 = c2;

      let invalid = valid(result, 'p1', c1);
      assert.ok(!invalid, invalid);
      invalid = valid(result, 'p2', c2);
      assert.ok(!invalid, invalid);

      frames.showdown.push(partial.showdown as Frame);
      partial.showdown = {};
      frames.pkmn.push(partial.pkmn as Frame);
      partial.pkmn = {};
    } while (!control.ended);

    if (control.ended) assert.notEqual(result.type, undefined);
    assert.deepEqual(battle.prng, control.prng.seed);
  } catch (err: any) {
    if (!replay) {
      const num = toBigInt(seed);
      const stack = err.stack.replace(ANSI, '');
      errors?.seeds.push(num);
      errors?.stacks.push(stack);
      try {
        console.error('');
        dump(
          gen,
          stack,
          num,
          control.inputLog,
          frames,
          partial,
        );
      } catch (e) {
        console.error(e);
      }
    }
    throw err;
  }
}

function toResult(battle: Battle, name: string) {
  return {
    type: battle.ended
      ? battle.winner === '' ? 'tie' : battle.winner === name ? 'win' : 'lose'
      : undefined,
    p1: battle.p1.requestState || 'pass',
    p2: battle.p2.requestState || 'pass',
  } as engine.Result;
}

function dump(
  gen: Generation,
  error: string,
  seed: bigint,
  input: string[],
  frames: {pkmn: Frame[]; showdown: Frame[]},
  partial: {pkmn: Partial<Frame>; showdown: Partial<Frame>}
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
  fs.writeFileSync(file, render(gen, true, error, seed, frames.pkmn, partial.pkmn));
  console.error(' ◦ @pkmn/engine:', pretty(symlink(file, link)), '->', pretty(file));

  file = path.join(dir, `${hex}.showdown.html`);
  link = path.join(dir, 'showdown.html');
  fs.writeFileSync(file, render(gen, true, error, seed, frames.showdown, partial.showdown));
  console.error(' ◦ Pokémon Showdown:', pretty(symlink(file, link)), '->', pretty(file), '\n');
}

function symlink(from: string, to: string) {
  fs.rmSync(to, {force: true});
  fs.symlinkSync(from, to);
  return to;
}

type Writeable<T> = { -readonly [P in keyof T]: T[P] };

// Compare Pokémon Showdown vs. @pkmn/engine output, after parsing the protocol
// and filtering out redundant messages / smoothing over any differences
//
//   - The engine sometimes sends out the `|-status|...|psn|[silent]` message in
//     the wrong order relative to the `|switch|` message - we can detect those
//     situations and simply swap the messages
//   - The engine only adds `[from]` on `|move|` for Metronome/Mirror Move and
//     so we also need to remove it from Pokémon Showdown's (we can't just
//     always indiscriminately remove it because we want to ensure that it
//     matches when present)
//   - Pokémon Showdown includes `[of]` on `|-damage|` and `|heal|` messages for
//     status damage but the engine doesn't keep track of this as its redundant
//     information that requires additional state to support
//
function compare(chunk: string, actual: engine.ParsedLine[]) {
  const diff = `\n\n${toText(actual)}\n\nvs. expected:\n\n${chunk}\n`;
  const buf: engine.ParsedLine[] = [];
  let i = 0;
  for (const {args, kwArgs} of Protocol.parse(chunk)) {
    if (FILTER.has(args[0])) continue;
    if (i > actual.length) throw new Error(`Actual logs are missing messages: ${diff}`);
    if (actual[i].args[0] === '-status' && actual[i].args[2] === 'psn' &&
      (actual[i].kwArgs as Protocol.KWArgs['|-status|']).silent && actual[i + 1] &&
      actual[i + 1].args[0] === 'switch') {
      [actual[i], actual[i + 1]] = [actual[i + 1], actual[i]];
    }
    const a = args.slice() as Writeable<Protocol.ArgType>;
    const kw = {...kwArgs} as Protocol.KWArgType;
    switch (args[0]) {
      case 'move': {
        const keys = kwArgs as Protocol.KWArgs['|move|'];
        if (keys.from && !(actual[i].kwArgs as Protocol.KWArgs['|move|']).from &&
        !['Metronome', 'Mirror Move'].includes(args[2])) {
          delete (kw as any).from;
        }
        break;
      }
      case '-heal':
      case '-damage': {
        const keys = kwArgs as Protocol.KWArgs['|-heal|' | '|-damage|'];
        if (keys.from && !['drain', 'Recoil'].includes(keys.from)) {
          delete (kw as any).of;
        }
        break;
      }
    }
    try {
      assert.deepEqual(actual[i], {args: a, kwArgs: kw});
    } catch (err) {
      // If both Pokémon that switched in have TOX degrading into PSN we may
      // need to perform yet another swap because the `|switch|` order is based
      // on the switched *out* Pokémon's speed and the ``|-status|` message is
      // based off of the switched *in* Pokémon's speed.
      if (actual[i].args[0] === '-status' && actual[i].args[2] === 'psn' &&
      (actual[i].kwArgs as Protocol.KWArgs['|-status|']).silent && actual[i + 1] &&
      actual[i + 1].args[0] === '-status') {
        [actual[i], actual[i + 1]] = [actual[i + 1], actual[i]];
        assert.deepEqual(actual[i], {args: a, kwArgs: kw});
      } else {
        throw err;
      }
    }
    i++;
  }
  if (i < actual.length) throw new Error(`Actual logs have additional messages: ${diff}`);
  return buf;
}

// The ExhaustiveRunner does not do a good job at ensuring the sets it generates
// are legal for old generations - these would usually be corrected by the
// TeamValidator but custom games bypass this so we need to massage the faulty
// set data ourselves
function fixTeam(gen: Generation, options: sim.AIOptions, moves: Set<ID>) {
  for (const pokemon of options.team!) {
    const species = gen.species.get(pokemon.species)!;
    // The generator sometimes returns sets with duplicate moves... >_<
    const deduped = [...new Set(pokemon.moves)];
    // Pokémon Showdown's Gen 1 Mimic decrements PP from completely the wrong
    // slot in edge cases if Mimic doesn't come first in the moveset
    pokemon.moves = gen.num === 1 && deduped.includes('mimic')
      ? ['mimic', ...deduped.filter(m => m !== 'mimic')]
      : deduped;
    // how do you really not have an addAll by now? ffs
    for (const move of pokemon.moves) moves.add(toID(move));
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
  return {...options, team: Teams.pack(options.team!)} as sim.AIOptions & {team: string};
}

const BINDING = ['bind', 'wrap', 'firespin', 'clamp'] as ID[];

// Due to Pokémon Showdown having some bugs which are unimplementable by correct
// engines, we need to get creative... The easiest solution is to simply never
// generate sets that include unimplementable moves at the cost of reduced
// coverage, however, a better approach is to attempt to generate teams and
// simply skip them if they contain problematic combinations of effects that
// could lead to issues. We're simplifying things slightly (which will result in
// false positives) by not considering P1 and P2 moves separately to be able to
// more precisely determine whether the interactions we're trying to avoid are
// actually possible, but the added complexity (especially after considering
// recursion) is definitely not worth the slight increase in coverage it would
// provide.
//
// The crucial part here is that we mark one of the problematic moves as "used"
// before retrying so that we can make progress and the team generator doesn't
// get stuck in a loop continually generating teams with the same issues.
function validate(prng: PRNG, moves: Set<ID>, used: RunnerOptions['usage']) {
  const transform = moves.has('transform' as ID);
  const substitute = moves.has('substitute' as ID);
  // Transform + Disable and Transform + Haze cannot be used together, so if
  // teams have been generated where both moves are present we simply choose one
  // at random to consider having been "used" and return true to retry
  if (transform) {
    const disable = moves.has('disable' as ID);
    const haze = moves.has('haze' as ID);
    if (disable && haze) {
      used.move('transform' as ID);
      return true;
    } else if (disable) {
      used.move(prng.sample(['transform', 'disable']) as ID);
      return true;
    } else if (haze) {
      used.move(prng.sample(['transform', 'haze']) as ID);
      return true;
    }
  }
  // Pokémon Showdown separately saves Binding move damage instead of using the
  // battle's last damage, which only matters because Leech Seed erroneously
  // overwrites last damage on Pokémon Showdown (which also tramples the damage
  // in the engine).
  const binding = BINDING.filter(m => moves.has(m));
  if (moves.has('leechseed' as ID) && binding.length) {
    if (prng.randomChance(1, binding.length + 1)) {
      for (const m of binding) used.move(m);
    } else {
      used.move('leechseed' as ID);
    }
    return true;
  }
  // Mirror Move is problematic in battles involving Transform/Substitute/binding moves
  // - we try to avoid always simply punting on Mirror Move and being fair
  // about which move gets a chance to be tested
  if (moves.has('mirrormove' as ID)) {
    if (+substitute + +transform + +!!binding.length > 1) {
      used.move('mirrormove' as ID);
      return true;
    } else if (substitute) {
      used.move(prng.sample(['mirrormove', 'substitute']) as ID);
      return true;
    } else if (transform) {
      used.move(prng.sample(['mirrormove', 'transform']) as ID);
      return true;
    } else if (binding.length) {
      if (prng.randomChance(1, binding.length + 1)) {
        for (const m of binding) used.move(m);
      } else {
        used.move('mirrormove' as ID);
      }
      return true;
    }
  }
  if (substitute && moves.has('metronome' as ID)) {
    used.move(prng.sample(['metronome', 'substitute']) as ID);
    return true;
  }
  return false;
}

const METRONOME = [
  ...BINDING, 'mirrormove', 'transform', 'disable', 'mimic', 'substitute', 'haze', 'bide',
];

// Mimic is so borked that we need to both ensure that if it appears in a move
// set it always is in the lowest index (above) *and* that if the infinite PP
// glitch occurs we simply abort immediately. Metronome also need special
// treatment because it can theoretically proc any other problematic move. Note
// that unlike above we don't need to explicitly mark the moves as used because
// at this point the internal accounting will have already taken care of that,
// so after retrying the generator should not attempt to use either move again.
//
// (Technically we can do away with validate above and always attempt to detect
// problems here, but we once again avoid doing that to minimize complexity)
function problematic(battle: Battle) {
  // PP can go negative on Pokémon Showdown due to Mimic
  for (const side of battle.sides) {
    for (const pokemon of side.active) {
      if (new Set(pokemon.moves).size !== pokemon.moves.length) return true;
    }
  }

  for (const {args, kwArgs} of Protocol.parse(battle.getDebugLog())) {
    if (args[0] === 'move') {
      // Metronome calling any move that contains issues is a problem because it
      // bypasses the validation logic above which would otherwise disallow it
      const from = toID((kwArgs as Protocol.KWArgs['|move|']).from);
      if (from === 'metronome' && METRONOME.includes(toID(args[2]))) return true;
    } else if (args[0] === '-start') {
      // Pokémon Showdown doesn't properly handle PP deduction if Transform was
      // copied by Mimic
      if (toID(args[2]) === 'mimic' && toID(args[3]) === 'transform') return true;
    }
  }

  return false;
}

const IGNORE = /^>(version(?:-origin)|start|player)/;
const MATCH = /^>(p1|p2) (?:(pass)|((move) (.*))|((switch) ([2-6])))/;

function fromInputLog(
  input: string[],
  index: number,
  options: {p1: engine.Choice[]; p2: engine.Choice[]},
  moves: {p1: ID[]; p2: ID[]},
) {
  // Players don't usually send "pass" on wait requests (they just wait) so we
  // need to determine when the player would have been forced to pass and fill
  // that in. Otherwise we set the choice to undefined and determine what the
  // choice was by processing the input log
  const initial = (player: engine.Player) =>
    (!options[player].length || options[player].length === 1 && options[player][0].type === 'pass')
      ? engine.Choice.pass() : undefined;

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
    if (IGNORE.test(input[index])) {
      index++;
      continue;
    }

    // We can't simply call engine.Choice.parse on the choice because Pokémon
    // Showdown oh so helpfully mutates the raw input and replaces move slot
    // indexes with move IDs :/
    const m = MATCH.exec(input[index]);
    if (!m) throw new Error(`Unexpected input ${index}: '${input[index]}'`);

    const player = m[1] as engine.Player;
    const type = (m[2] ?? m[4] ?? m[7]) as engine.Choice['type'];
    const d = m[5] ?? m[8] ?? '0';
    const struggle = d === 'struggle';

    const data = d === 'recharge' ? 1 : !isNaN(+d) ? +d : moves[player].indexOf(d as ID) + 1;
    // BUG: a move could be [from] Metronome and wouldn't be possible to reverse
    if (type === 'move' && !data && !struggle) throw new Error(`Invalid choice data: '${d}'`);

    const choice = {type, data};
    if (choices[player]) {
      throw new Error(`Already have choice for ${player}: ` +
        `'${engine.Choice.format(choices[player]!)}' vs. '${engine.Choice.format(choice)}'`);
    }

    // Ensure the choice we parsed from the input log is actually valid for the
    // player - its possible that the RandomPlayerAI made an "unavailable"
    // choice, in which case we simply continue to the next input to determine
    // what the *actual* choice should be. We also need to handle Pokémon Showdown's
    // broken forced choice semantics where the move index in the input log gets
    // translated to an illegal index
    if (options[player].length === 1 && options[player][0].type === 'move') {
      if (type !== 'move') {
        throw new Error(`Invalid choice when move is forced: '${engine.Choice.format(choice)}'`);
      }
      choices[player] = options[player][0];
    } else {
      for (const option of options[player]) {
        if (option.type === choice.type && option.data === choice.data) {
          choices[player] = choice;
          break;
        }
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

type Flags = Partial<Pick<sim.ExhaustiveRunnerOptions, 'log' | 'maxFailures' | 'cycles'>> & {
  prng: PRNG | PRNGSeed;
  gen?: GenerationNum;
  duration?: number;
  debug?: boolean;
};

export async function run(gens: Generations, options: string | Flags, errors?: Errors) {
  if (!addon.supports(true, true)) throw new Error('engine must be built with -Dshowdown -Dlog');
  if (typeof options === 'string') {
    const log = fs.readFileSync(path.resolve(CWD, options), 'utf8');
    const gen = gens.get(log.charAt(23));
    patch.generation(gen);

    const lines = log.split('\n');
    const spec = JSON.parse(lines[0].slice(7)) as {formatid: string; seed: PRNGSeed};
    const p1 = {spec: JSON.parse(lines[1].slice(10)) as {name: string; team: string}};
    const p2 = {spec: JSON.parse(lines[2].slice(10)) as {name: string; team: string}};
    play(gen, spec, p1, p2, lines, true);
    return 0;
  }

  const opts: sim.ExhaustiveRunnerOptions = {
    cycles: 1, maxFailures: 1, log: false, ...options, format: '',
    cmd: (cycles: number, format: string, seed: string) => {
      const c = `npm run integration -- --cycles=${cycles} --gen=${format[3]} --seed=${seed}`;
      errors?.commands.push(c);
      return c;
    }};

  let failures = 0;
  const start = Date.now();
  do {
    for (const gen of gens) {
      if (gen.num > 1) break;
      if (options.gen && gen.num !== options.gen) continue;
      patch.generation(gen);
      opts.format = formatFor(gen);
      const d = (options).debug;
      failures += await (new sim.ExhaustiveRunner({...opts, runner: o =>
        new Runner(gen, {...o, errors} as RunnerOptions, d).run(),
      }).run());
      if (failures >= opts.maxFailures!) return failures;
    }
  } while (Date.now() - start < (options.duration || 0));

  return failures;
}

export function newSeed(prng: PRNG): PRNGSeed {
  return [prng.next(0x10000), prng.next(0x10000), prng.next(0x10000), prng.next(0x10000)];
}

export function toBigInt(seed: PRNGSeed): bigint {
  return ((BigInt(seed[0]) << 48n) | (BigInt(seed[1]) << 32n) |
   (BigInt(seed[2]) << 16n) | BigInt(seed[3]));
}

class Errors {
  seeds: bigint[];
  stacks: string[];
  commands: string[];

  constructor() {
    this.seeds = [];
    this.stacks = [];
    this.commands = [];
  }

  toString() {
    const buf = ['<link rel="icon" href="https://pkmn.cc/favicon.ico"><div id="content"></div>'];
    buf.push('<link href="https://cdn.jsdelivr.net/npm/prismjs/themes/prism.min.css" rel="stylesheet" />');
    buf.push('<style>');
    buf.push('#content { font-family: Roboto, Helvetica; margin: 2em auto; max-width: 1300px; }');
    buf.push('ul { font-size: 1.1em; line-height: 1.5em; }');
    buf.push('</style>');
    buf.push('<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script><script>');
    buf.push('document.getElementById("content").innerHTML = marked.parse(`');
    for (let i = 0; i < this.commands.length; i++) {
      buf.push('- **TODO**');
      const seed = `0x${this.seeds[i].toString(16).toUpperCase()}`;
      buf.push(`  - ${seed} (\\\`${this.commands[i]}\\\`)`);
      buf.push(`    - [pkmn](${seed}.pkmn.html)`);
      buf.push(`    - [showdown](${seed}.showdown.html)`);
      buf.push('\\`\\`\\`diff');
      buf.push(this.stacks[i].replaceAll(ROOT + path.sep, ''));
      buf.push('\\`\\`\\`');
    }
    buf.push('`);</script>');
    buf.push('<script src="https://cdn.jsdelivr.net/npm/prismjs/prism.min.js"></script>');
    buf.push('<script src="https://cdn.jsdelivr.net/npm/prismjs/plugins/autoloader/prism-autoloader.min.js"></script>');
    return buf.join('\n');
  }
}

if (require.main === module) {
  (async () => {
    const gens = new Generations(Dex as any);
    // minimist tries to parse all number-like things into numbers which doesn't work because the
    // seed is actually a bigint, meaning we need to special case this without calling minimist
    if (process.argv.length === 3 && process.argv[2][0] !== '-') {
      const file = path.join(ROOT, 'logs', `${process.argv[2]}.input.log`);
      process.exit(await run(gens, fs.existsSync(file) ? file : process.argv[2]));
    }
    const argv = minimist(process.argv.slice(2), {
      boolean: ['debug', 'summary'],
      default: {maxFailures: 1, debug: true},
    });

    const unit =
      typeof argv.duration === 'string' ? argv.duration[argv.duration.length - 1] : undefined;
    const duration =
      unit ? +argv.duration.slice(0, -1) * {s: 1e3, m: 6e4, h: 3.6e6}[unit]! : argv.duration;
    argv.cycles = argv.cycles ?? (duration ? 1 : 10);
    const prng = new PRNG(argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : null);
    if (!argv.seed) console.error('Seed:', prng.seed.join(','));
    const options = {prng, log: process.stdout.isTTY, ...argv, duration};

    const errors = argv.summary ? new Errors() : undefined;
    const code = await run(gens, options, errors);
    if (code && errors) {
      const file = path.join(ROOT, 'logs', `${prng.seed.join('-')}.html`);
      const link = path.join(ROOT, 'logs', 'summary.html');
      fs.writeFileSync(file, errors.toString());
      symlink(file, link);
    }

    process.exit(code);
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
