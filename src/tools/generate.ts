import 'source-map-support/register';

import * as fs from 'fs';
import * as https from 'https';
import * as path from 'path';

import {
  Generation, GenerationNum, Generations, ItemName,
  MoveTarget, Specie, StatsTable, TypeName,
} from '@pkmn/data';
import {Dex, toID} from '@pkmn/sim';
import stringify from 'json-stringify-pretty-compact';
import * as mustache from 'mustache';

import type {IDs} from '../pkg/data';

const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATES = path.join(ROOT, 'src', 'lib', 'common', 'data');
const CACHE = path.join(ROOT, '.cache');

const IDS: IDs =
[{
  types: [
    'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost',
    'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon',
  ] as Exclude<TypeName, 'Dark' | 'Steel' | 'Fairy' | 'Stellar'>[],
}, {
  types: [
    'Ground', 'Rock', 'Steel', 'Normal', 'Fighting', 'Flying', 'Poison', 'Bug', 'Ghost',
    '???', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark',
  ] as Exclude<TypeName, 'Fairy' | 'Stellar'>[],
  items: [],
}];
const DATA: [{
  types: TypeName[];
  species: {
    [name: string]: {
      stats: Omit<StatsTable, 'spa' | 'spd'> & {spc: number};
      types: TypeName[];
    };
  };
  moves: {[name: string]: number};
}, {
  types: TypeName[];
  species: {
    [name: string]: {
      stats: StatsTable;
      types: TypeName[];
      gender: number;
    };
  };
  moves: {[name: string]: number};
  items: ItemName[];
}] = [
  {types: IDS[0].types, species: {}, moves: {}},
  {types: IDS[1].types, species: {}, moves: {}, items: []},
];

// https://pkmn.cc/pokecrystal/data/types/type_matchups.asm
const TYPE_PRECEDENCE = [
  '???', 'Normal', 'Fire', 'Water', 'Electric', 'Grass', 'Ice', 'Fighting', 'Poison',
  'Ground', 'Flying', 'Psychic', 'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel',
];

// https://pkmn.cc/pokecrystal/engine/battle/hidden_power.asm
const HIDDEN_POWER = [
  'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost', 'Steel',
  '???', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark',
];

// https://pkmn.cc/pokecrystal/constants/type_constants.asm
const TYPE_INDEXES = {
  Normal: 0, Fighting: 1, Flying: 2, Poison: 3, Ground: 4, Rock: 5, Bug: 7, Ghost: 8, Steel: 9,
  '???': 19, Fire: 20, Water: 21, Grass: 22, Electric: 23, Psychic: 24, Ice: 25, Dragon: 26,
  Dark: 27,
};

const NAMES: {[constant: string]: string} = {
  // Items
  BLACKBELT_I: 'BlackBelt', BLACKGLASSES: 'BlackGlasses', BLK_APRICORN: 'BlackApricorn',
  BLU_APRICORN: 'BlueApricorn', BLUESKY_MAIL: 'BlueSkyMail', BRIGHTPOWDER: 'BrightPowder',
  ELIXER: 'Elixir', ENERGYPOWDER: 'EnergyPowder', GRN_APRICORN: 'GreenApricorn',
  HP_UP: 'HPUp', LITEBLUEMAIL: 'LightBlueMail', MAX_ELIXER: 'MaxElixir',
  MIRACLEBERRY: 'MiracleBerry', MYSTERYBERRY: 'MysteryBerry', NEVERMELTICE: 'NeverMeltIce',
  PARLYZ_HEAL: 'ParylzeHeal', PNK_APRICORN: 'PinkApricorn', PORTRAITMAIL: 'PortrailMail',
  PP_UP: 'PPUp', PRZCUREBERRY: 'PRZCureBerry', PSNCUREBERRY: 'PSNCureBerry',
  RAGECANDYBAR: 'RageCandyBar', SILVERPOWDER: 'SilverPowder', SLOWPOKETAIL: 'SlowpokeTail',
  THUNDERSTONE: 'ThunderStone', TINYMUSHROOM: 'TinyMushroom', TWISTEDSPOON: 'TwistedSpoon',
  WHT_APRICORN: 'WhiteApricorn', YLW_APRICORN: 'YellowApricorn', RESTORE_PP: 'RestorePP',
  // Moves
  SMELLING_SALT: 'SmellingSalts',
  // Effects
  NO_ADDITIONAL_EFFECT: 'None', EFFECT_NORMAL_HIT: 'None', FLY_EFFECT: 'Charge',
  TWO_TO_FIVE_ATTACKS_EFFECT: 'MultiHit', ATTACK_TWICE_EFFECT: 'DoubleHit', OHKO_EFFECT: 'OHKO',
  TRAPPING_EFFECT: 'Binding', EFFECT_OHKO: 'OHKO', DRAIN_HP_EFFECT: 'DrainHP',
  EFFECT_LEECH_HIT: 'DrainHP', EFFECT_ACCURACY_DOWN_HIT: 'AccuracyDownChance',
  EFFECT_ACCURACY_DOWN: 'AccuracyDown1', EFFECT_ALL_UP_HIT: 'AllStatUpChance',
  EFFECT_ATTACK_DOWN_HIT: 'AttackDownChance', EFFECT_ATTACK_DOWN: 'AttackDown1',
  EFFECT_ATTACK_UP_HIT: 'AttackUpChance', EFFECT_ATTACK_UP: 'AttackUp1',
  EFFECT_BURN_HIT: 'BurnChance', EFFECT_CONFUSE_HIT: 'ConfusionChance', EFFECT_CONFUSE: 'Confusion',
  EFFECT_DEFENSE_DOWN_HIT: 'DefenseDownChance', EFFECT_DEFENSE_DOWN: 'DefenseDown1',
  EFFECT_DEFENSE_UP_HIT: 'DefenseUpChance', EFFECT_DEFENSE_UP: 'DefenseUp1',
  EFFECT_EVASION_DOWN: 'EvasionDown1', EFFECT_EVASION_UP: 'EvasionUp1',
  EFFECT_FLINCH_HIT: 'FlinchChance', EFFECT_FREEZE_HIT: 'FreezeChance',
  EFFECT_PARALYZE_HIT: 'ParalyzeChance', EFFECT_POISON_HIT: 'PoisonChance',
  EFFECT_POISON_MULTI_HIT: 'Twineedle', EFFECT_PRIORITY_HIT: 'Priority',
  EFFECT_RAMPAGE: 'Thrashing', EFFECT_RECOIL_HIT: 'Recoil', EFFECT_STATIC_DAMAGE: 'FixedDamage',
  THRASH_PETAL_DANCE_EFFECT: 'Thrashing', EFFECT_SELFDESTRUCT: 'Explode',
  EFFECT_SP_ATK_UP: 'SpAtkUp1', EFFECT_SP_DEF_DOWN_HIT: 'SpDefDownChance',
  EFFECT_SPEED_DOWN: 'SpeedDown1', EFFECT_SPEED_DOWN_HIT: 'SpeedDownChance',
  EFFECT_TRAP_TARGET: 'Binding', EFFECT_RESET_STATS: 'Haze', EFFECT_FLY: 'FlyDig',
  EFFECT_SOLARBEAM: 'SolarBeam',
};

const STAT_DOWN = [
  'AccuracyDown1', 'AttackDown1', 'DefenseDown1', 'DefenseDown2', 'SpeedDown1',
];

const STAT_DOWN_CHANCE = [
  'AttackDownChance', 'DefenseDownChance', 'SpeedDownChance', 'SpecialDownChance',
];

const SECONDARY_CHANCE = [
  'BurnChance1', 'BurnChance2', 'ConfusionChance', 'FlinchChance1', 'FlinchChance2',
  'FreezeChance', 'ParalyzeChance1', 'ParalyzeChance2', 'PoisonChance1', 'PoisonChance2',
];

// Technically DoubleHit and MultiHit belong here but they're handled subtly differently. Similarly,
// Rage is not considered to be "special" though is considered to "always happen", but simply
// considering it "special" is simpler and allows us to avoid redundantly calling Rage twice anyway
const ALWAYS_HAPPEN_SPECIAL = [
  'DrainHP', 'DreamEater', 'Explode', 'JumpKick', 'PayDay', 'Rage', 'Recoil',
];

const GROUPS: {[constant: string]: string[]} = {
  // data/battle/residual_effects_1.asm
  onBegin: [
    'Conversion', 'Haze', 'SwitchAndTeleport', 'Mist', 'FocusEnergy', 'Confusion', 'Heal',
    'Transform', 'LightScreen', 'Reflect', 'Poison', 'Paralyze', 'Substitute', 'Mimic',
    'LeechSeed', 'Splash',
  ],
  // data/battle/residual_effects_2.asm
  onEnd: [
    ...STAT_DOWN, 'AttackUp1', 'AttackUp2', 'Bide', 'DefenseUp1', 'DefenseUp2',
    'EvasionUp1', 'Sleep', 'SpecialUp1', 'SpecialUp2', 'SpeedUp2',
  ],
  // data/battle/special_effects.asm
  isSpecial: [
    ...ALWAYS_HAPPEN_SPECIAL, 'Swift', 'Charge',
    'SuperFang', 'SpecialDamage', 'Thrashing', 'Binding',
  ],
  // custom group used as an optimization/simplification by the engine
  isMulti: ['DoubleHit', 'MultiHit', 'Twineedle'],
};
const EFFECT_TO_GROUP: {[effect: string]: string} = {};
for (const group in GROUPS) {
  for (const effect of GROUPS[group]) {
    EFFECT_TO_GROUP[effect] = group;
  }
}

const TARGETS: {[target in MoveTarget]: string} = {
  adjacentAlly: 'Ally',
  adjacentAllyOrSelf: 'AllyOrSelf',
  adjacentFoe: 'Foe',
  all: 'All', // or 'Field'
  allAdjacent: 'AllOthers',
  allAdjacentFoes: 'Foes',
  allies: 'Allies',
  allySide: 'AllySide',
  allyTeam: 'Self',
  any: 'Any',
  foeSide: 'FoeSide',
  normal: 'Other',
  randomNormal: 'RandomFoe',
  scripted: 'Depends',
  self: 'Self',
};

const constToEffectEnum = (s: string) =>
  NAMES[s] || constToEnum(s).replace('SideEffect', 'Chance').replace('Effect', '');

const nameToEnum = (s: string) => s.replace(/[^A-Za-z0-9]+/g, '');
const constToEnum = (s: string) =>
  s.split('_').map(w => `${w[0]}${w.slice(1).toLowerCase()}`).join('');

const effectToGroup = (e: string) => EFFECT_TO_GROUP[e] || 'other';

const mkdir = (dir: string) => {
  try {
    fs.mkdirSync(dir);
    return true;
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
    return false;
  }
};

const template = (file: string, dir: string, data: any, tmpl?: string) => {
  fs.writeFileSync(
    path.join(dir, `${file}.zig`),
    mustache.render(
      fs.readFileSync(path.join(TEMPLATES, `${tmpl || file}.zig.tmpl`), 'utf8'),
      data
    )
  );
};

const fetch = (url: string): Promise<string> => new Promise((resolve, reject) => {
  let buf = '';
  const req = https.request(url, res => {
    if (res.statusCode === 301 || res.statusCode === 302) {
      return resolve(fetch(res.headers.location!));
    } else if (res.statusCode !== 200) {
      return reject(new Error(`HTTP ${res.statusCode!}`));
    }
    res.on('data', d => {
      buf += d;
    });
    res.on('end', () => resolve(buf));
  });
  req.on('error', reject);
  req.end();
});

const getTypeChart = (gen: Generation, types: TypeName[]) => {
  const chart = [];
  for (const t1 of types) {
    const type1 = gen.types.get(t1)!;
    const effectiveness = [];
    for (const t2 of types) {
      const e = type1.effectiveness[t2];
      if (e === 2) {
        effectiveness.push('S');
      } else if (e === 1) {
        effectiveness.push('N');
      } else if (e === 0.5) {
        effectiveness.push('R');
      } else {
        effectiveness.push('I');
      }
    }
    chart.push(`[_]Effectiveness{ ${effectiveness.join(', ')} }, // ${t1}`);
  }
  return chart;
};

const convertGenderRatio = (species: Specie) => {
  if (species.gender === 'N') return '0xFF, // N';
  switch (species.genderRatio.F) {
    case 0: return '0x00, // 0.00% F';
    case 0.125: return '0x1F, // 12.5% F';
    case 0.25: return '0x3F, // 25.0% F';
    case 0.5: return '0x7F, // 50.0% F';
    case 0.75: return '0xBF, // 75.0% F';
    case 1: return '0xFE, // 100% F';
    default:
      throw new Error(`Invalid gender ratio for ${species.name}`);
  }
};

const getOrUpdate = async (
  file: string, dir: string, url: string, update: boolean,
  fn: (line: string, last: string, i: number) => string | undefined
) => {
  const cache = path.resolve(dir, `${file}.txt`);
  const cached = (() => {
    try {
      return fs.readFileSync(cache, 'utf8');
    } catch (err: any) {
      if (err.code !== 'ENOENT') throw err;
      return undefined;
    }
  })();

  if (!cached || update) {
    const result: string[] = [];
    const text = await fetch(url);
    let last = '';
    for (const line of text.split('\n')) {
      const val = fn(line, last, result.length);
      if (val !== undefined) result.push(val);
      last = line;
    }
    fs.writeFileSync(cache, result.join('\n') + '\n');
    return result;
  }

  const result: string[] = [];
  for (const line of cached.split('\n')) {
    if (line) result.push(line.trimEnd());
  }
  return result;
};

const NO_EFFECT = 'No additional effect.';

const moveTests = (gen: Generation, moves: string[]) => {
  const effects: {[effect: string]: string[]} = {};
  const descs: {[effect: string]: string} = {};
  for (const m of moves) {
    const [name, effect] = m.split(' ');
    const move = gen.moves.get(name)!;
    if ([move.shortDesc, move.desc].includes(NO_EFFECT)) continue;
    effects[effect] = effects[effect] || [];
    effects[effect].push(name);
    descs[effect] = move.desc;
  }

  const buf = [];
  for (const effect in effects) {
    const key = effects[effect].length === 1
      ? effects[effect][0]
      : `{${effects[effect].join(',')}}`;
    const desc = descs[effect];
    buf.push(`// Move.${key}`);
    buf.push(`test "${effect} effect" {\n    // ${desc}\n    return error.SkipZigTest;\n}\n`);
  }
  console.log(buf.join('\n'));
};

const itemTests = (gen: Generation, items: string[]) => {
  const effects: {[effect: string]: string[]} = {};
  const descs: {[effect: string]: string} = {};
  for (const value of items) {
    const [name, held] = value.split(' ');
    const item = gen.items.get(name);
    if (name.endsWith('Mail')) {
      effects.Mail = effects.Mail || [];
      effects.Mail.push(name);
      continue;
    }
    if (!item || held === 'None') continue;
    effects[held] = effects[held] || [];
    effects[held].push(name);
    descs[held] = item.desc;
  }

  const buf = [];
  for (const effect in effects) {
    const key = effects[effect].length === 1
      ? effects[effect][0]
      : `{${effects[effect].join(',')}}`;
    const desc = descs[effect];
    buf.push(`// Item.${key}`);
    buf.push(`test "${effect} effect" {\n    // ${desc}\n    return error.SkipZigTest;\n}\n`);
  }
  console.log(buf.join('\n'));
};

const EFFECT_MAPPING: {[name: string]: string} = {
  NormalHit: 'None', DoSleep: 'Sleep', PoisonHit: 'PoisonChance', LeechHit: 'DrainHP',
  BurnHit: 'BurnChance', FreezeHit: 'FreezeChance', ParalyzeHit: 'ParalyzeChance', Fly: 'FlyDig',
  Selfdestruct: 'Explode', ResetStats: 'Haze', Rampage: 'Thrashing', StaticDamage: 'FixedDamage',
  PoisonMultiHit: 'Twineedle', FlinchHit: 'FlinchChance', OHKOHit: 'OHKO', TrapTarget: 'Binding',
  RecoilHit: 'Recoil', DoConfuse: 'Confusion', ConfuseHit: 'ConfusionChance', DoPoison: 'Poison',
  DoParalyze: 'Paralyze', AllUpHit: 'AllStatUpChance',
};

function* chunks(xs: string[], n: number) {
  for (let i = 0; i * n < xs.length; i++) {
    const limit = Math.min((i + 1) * n, xs.length);
    yield {chunk: xs.slice(i * n, limit), done: limit === xs.length};
  }
}

const levenshtein = (s: string[], t: string[]) => {
  if (!s.length) return t.length;
  if (!t.length) return s.length;
  const arr = [];
  for (let i = 0; i <= t.length; i++) {
    arr[i] = [i];
    for (let j = 1; j <= s.length; j++) {
      arr[i][j] = i === 0 ? j : Math.min(
        arr[i - 1][j] + 1,
        arr[i][j - 1] + 1,
        arr[i - 1][j - 1] + (s[j - 1] === t[i - 1] ? 0 : 1)
      );
    }
  }
  return arr[t.length][s.length];
};

const moveFns = async (
  gen: Generation, dirs: {out: string; cache: string},
  update: boolean, pret: string, names: Set<string>,
) => {
  if (gen.num !== 2) throw new Error(`Unexpected generation ${gen.num}`);

  const url = `${pret}/data/moves/effects.asm`;
  const MATCH = /^(?:(?:([A-Z][A-Za-z]+\d?):)|(?:(\t[a-z\d]+)(?: ;.*)?))$/;
  const raw = await getOrUpdate('effects', dirs.cache, url, update, (line, last) => {
    if (!last) return undefined;
    const m = MATCH.exec(last);
    if (m && (!last.endsWith(':') || !(MATCH.test(line) && line.endsWith(':')))) {
      return m[1] ?? m[2];
    }
    return undefined;
  });

  const SKIP = new Set([
    'checkobedience', 'lowersub', 'raisesub', 'moveanim', 'moveanimnosub', 'endmove',
    'statupanim', 'statupmessage', 'statupfailtext', 'movedelay', 'cleartext',
    'thunderaccuracy',
  ]);

  const effects = new Map<string, string[]>();
  let last = '';
  for (const line of raw) {
    if (line.startsWith('\t')) {
      const command = line.trimStart();
      if (SKIP.has(command)) continue;
      effects.get(last)?.push(command);
    } else {
      last = EFFECT_MAPPING[line] || line;
      effects.set(last, []);
    }
  }

  const BASE_POWER_CALLBACK = ['Return', 'Frustration', 'Present', 'Magnitude'];
  const SPECIAL_FAILURE = ['Rage', 'Swagger', 'FakeOut'];

  const OPTIMIZATIONS: Array<(commands: string[], effect: string) => void> = [
    commands => {
      const index = commands.indexOf('usedmovetext');
      // (usedmovetext, doturn) -> canMove
      if (commands[index + 1] === 'doturn') {
        commands.splice(index, 1);
        commands[index] = 'canmove';
      // (..., charge, doturn) -> canCharge
      } else if (commands[index - 1] === 'charge') {
        commands.splice(0, index);
        commands[0] = 'cancharge';
      }
    },
    // (failuretext, applydamage) -> applydamage
    (commands, effect) => {
      const index = commands.indexOf('failuretext');
      if (index !== -1) {
        if (commands[index + 1] !== 'applydamage') {
          if (!SPECIAL_FAILURE.includes(effect)) {
            throw new Error(`Unexpected ordering of failure commands found in ${effect}`);
          }
        } else {
          commands.splice(index, 1);
        }
      }
    },
    // (damagestats, damagecalc) -> damagecalc
    (commands, effect) => {
      let index = commands.indexOf('damagestats');
      if (index === -1) {
        index = commands.indexOf('damagecalc');
        if (index !== -1) {
          if (effect === 'BeatUp') {
            commands.splice(index, 1);
          } else if (effect !== 'HiddenPower') {
            throw new Error(`Unexpected damagecalc command found in ${effect}`);
          }
        }
      } else {
        // NB: move to include base power callback *before* damagestats if we pass in BP to calc
        if (commands[index + 1] !== 'damagecalc' && !BASE_POWER_CALLBACK.includes(effect)) {
          throw new Error(`Unexpected ordering of damage calc commands found in ${effect}`);
        } else {
          commands.splice(index, 1);
        }
      }
    },
    // (crittext, supereffectivetext) -> reportoutcome
    (commands, effect) => {
      // Reversal is special and needs to be rewritten
      if (effect === 'Reversal') {
        let index = commands.indexOf('constantdamage');
        commands[index] = 'reversal';
        index = commands.indexOf('supereffectivetext');
        commands[index] = 'reversalsupereffectivetext';
        return;
      }

      const index = commands.indexOf('criticaltext');
      if (index === -1) {
        if (commands.includes('supereffectivetext')) {
          throw new Error(`Unexpected supereffectivetext command found in ${effect}`);
        }
      } else {
        if (!/supereffective(?:loop)?text/.test(commands[index + 1])) {
          throw new Error(`Unexpected ordering of post-hit commands found in ${effect}`);
        } else {
          commands.splice(index, 1);
          // (crittext, supereffectivelooptext) -> critsupereffectivelooptext
          commands[index] = commands[index].includes('loop')
            ? 'critsupereffectivelooptext'
            : 'reportoutcome';
        }
      }
    },
    // (critical, damagecalc, stab, damagevariation, checkhit, applydamage, checkhit) -> domove*
    commands => {
      const index = commands.indexOf('critical');
      if (index === -1) return;
      let i = index;
      for (const command of ['critical', 'damagecalc', 'stab', 'damagevariation', 'checkhit']) {
        if (commands[i++] !== command) return;
      }
      // effectchance is optionally included as well
      if (commands[i] === 'effectchance') i++;
      if (commands[i++] !== 'applydamage') return;
      if (commands[i] !== 'reportoutcome') return;
      commands.splice(index, i - 1);
      commands[index] = `domove${i === 7 ? '' : 'secondary'}`;
    },
    // (checkfaint, buildopponentrage, kingsrock?) -> aftermove*
    commands => {
      const index = commands.indexOf('checkfaint');
      if (index === -1) return;
      if (commands[index + 1] !== 'buildopponentrage') return;
      const replacement = commands[index + 2] === 'kingsrock' ? 'aftermovekings' : 'aftermove';
      commands.splice(index, replacement === 'aftermove' ? 1 : 2);
      commands[index] = `${index === commands.length - 1 ? '' : 'if'}${replacement}`;
    },
    // (switchturn, ..., switchturn) -> swagger
    commands => {
      const index = commands.indexOf('switchturn');
      if (index === -1) return;
      commands.splice(index, commands.lastIndexOf('switchturn') - index);
      commands[index] = 'swagger';
    },
  ];

  for (const [effect, commands] of effects.entries()) {
    for (const optimization of OPTIMIZATIONS) {
      optimization(commands, effect);
    }
  }

  let indent = 0;
  const buf: string[] = [];
  const write = (...lines: string[]) => {
    for (const line of lines) {
      if (line) {
        buf.push(' '.repeat(indent * 4) + line);
      } else {
        buf.push('');
      }
    }
  };
  const block = (...lines: string[]) => write('', ...lines, '');

  write('//! Code generated by `tools/generate` - manual edits will be overwritten.\n');
  write('const std = @import("std");\n');
  write('const common = @import("../common/data.zig");\n');
  write('const data = @import("data.zig");');
  write('const mechanics = @import("mechanics.zig");\n');
  write('const Player = common.Player;\nconst Result = common.Result;\n');
  write('const Effectiveness = data.Effectiveness;\nconst Move = data.Move;\n');
  write('const Effects = mechanics.Effects;\nconst State = mechanics.State;\n');

  const IMPORTS = [
    'canMove', 'canCharge', 'decrementPP', 'doMove', 'checkHit', 'checkCriticalHit', 'calcDamage',
    'adjustDamage', 'randomizeDamage', 'applyDamage', 'reportOutcome', 'effectChance', 'afterMove',
    'buildRage', 'kingsRock', 'destinyBond',
  ];
  for (const command of IMPORTS) {
    write(`const ${command} = mechanics.${command};`);
  }

  write('\nconst SECONDARY = true;\nconst KINGS = true;\n');
  write('pub fn runMove(battle: anytype, player: Player, state: *State, options: anytype) !void {');
  indent++;
  write('var log = options.log;\n');
  write('var side = battle.side(player);');
  write('const volatiles = &side.active.volatiles;\n');
  write('const ident = battle.active(player);');
  write('const foe_ident = battle.active(player.foe());\n');
  write('const move = Move.get(state.move);');
  write('switch (move.effect) {');
  indent++;

  const GROUPED = [
    ['Frustration', 'Return'],
    ['Endure', 'Protect'],
    ['Toxic', 'Poison'],
    ['AlwaysHit', 'HighCritical', 'Priority', 'JumpKick', 'None'],
    ['SuperFang', 'LevelDamage', 'Psywave', 'FixedDamage'],
    ['MirrorCoat', 'Counter'],
    ['DoubleHit', 'MultiHit'],
    ['MorningSun', 'Synthesis', 'Moonlight'],
    ['DreamEater', 'DrainHP'],
    ['FlameWheel', 'SacredFire'],
    ['RazorWind', 'SolarBeam', 'FlyDig'],
  ];

  const SNIPPETS: {[command: string]: (effect?: string) => void} = {
    canmove: () => write('if (!try canMove(battle, player, state, options)) return;'),
    cancharge: () => write('if (!try canCharge(battle, player, state, options)) return;'),
    usedmovetext: () => write(
      '// usedmovetext',
      'try log.move(.{ ident, state.move, foe_ident }); // FIXME self? from?',
    ),
    doturn: () => write(
      '// doturn',
      'const charging = false; // TODO',
      'const skip_pp = charging or state.move == .Struggle or',
      '    (volatiles.BeatUp or volatiles.Thrashing or volatiles.Bide);',
      'if (!skip_pp) _ = decrementPP(side, state.move, state.mslot); // TODO if no pp return',
    ),
    domove: () => write('if (!try doMove(!SECONDARY, battle, player, state, options)) return;'),
    stab: effect => effect === 'OHKO'
      ? write('try Effects.ohko.immune(battle, player, state, options);')
      : write('try adjustDamage(battle, player, state, options);'),
    domovesecondary: () =>
      write('if (!try doMove(SECONDARY, battle, player, state, options)) return;'),
    checkfaint: () => write('if (try destinyBond(battle, player, state, options)) return;'),
    kingsrock: effect => effect === 'DrainHP'
      ? write('if (state.move != .DreamEater) try kingsRock(battle, player, state, options);')
      : write('try kingsRock(battle, player, state, options);'),
    aftermove: () => write('_ = try afterMove(!KINGS, battle, player, state, options);'),
    ifaftermove: () => write('if (!try afterMove(!KINGS, battle, player, state, options)) return;'),
    aftermovekings: () => write('_ = try afterMove(KINGS, battle, player, state, options);'),
    ifaftermovekings: () =>
      write('if (!try afterMove(KINGS, battle, player, state, options)) return;'),
    clearmissdamage: () =>
      block('if (state.miss) state.damage = 0;'),
    resettypematchup: () =>
      block('if (state.immune()) {',
        '    state.damage = 0;',
        '    state.miss = true;',
        '}',
        'state.effectiveness = Effectiveness.neutral;'),
    snore: () => write('if (!try Effects.snore(battle, player, state, options)) return;'),
    swagger: () => write('try Effects.boost(battle, player.foe(), state, options);'),
    screen: effect => effect === 'LightScreen'
      ? write('try Effects.lightScreen(battle, player, state, options);')
      : write('try Effects.reflect(battle, player, state, options);'),
  };

  const FNS: {[command: string]: string} = {
    checkhit: 'checkHit', critical: 'checkCriticalHit',
    damagecalc: 'calcDamage', damagevariation: 'randomizeDamage', applydamage: 'applyDamage',
    effectchance: 'effectChance', reportoutcome: 'reportOutcome',
    buildopponentrage: 'buildRage', burntarget: 'Effects.burnChance',
    freezetarget: 'Effects.freezeChance', ohko: 'Effects.ohko.damage', startsun: 'Effects.sunnyDay',
    startsandstorm: 'Effects.sandstorm', paralyzetarget: 'Effects.paralyzeChance',
    arenatrap: 'Effects.meanLook', traptarget: 'Effects.binding',
    flinchtarget: 'Effects.flinchChance', poisontarget: 'Effects.poisonChance',
    sleeptarget: 'Effects.sleep', resetstats: 'Effects.haze', confuse: 'Effects.confusion',
    constantdamage: 'Effects.fixedDamage', confusetarget: 'Effects.confusionChance',
    selfdestruct: 'Effects.explode', rechargenextturn: 'Effects.hyperBeam',
    draintarget: 'Effects.drainHP', skipsuncharge: 'Effects.solarBeam',
    defenseup: 'Effects.boost', tristatuschance: 'Effects.triAttack',
    allstatsup: 'Effects.allStatUpChance', defrost: 'Effects.defrost',
    happinesspower: 'Effects.happiness', startrain: 'Effects.rainDance',
    clearhazards: 'Effects.rapidSpin', healnite: 'Effects.weatherHeal', rage: 'Effects.rage.start',
    ragedamage: 'Effects.rage.damage', storeenergy: 'Effects.bide.store',
    unleashenergy: 'Effects.bide.unleash', doubleflyingdamage: 'Effects.double.flying',
    doubleundergrounddamage: 'Effects.double.underground',
    doubleminimizedamage: 'Effects.double.minimize', getmagnitude: 'Effects.magnitude',
    checkcurl: 'Effects.rollout.check', rolloutpower: 'Effects.rollout.power',
  };

  const BOOST = /[^th]Up[12]?(?:Chance)?$/;
  const UNBOOST = /Down[12]?(?:Chance)?$/;

  const writeCommands = (name: string) => {
    indent++;
    for (const command of effects.get(name === 'LightScreen' ? 'Reflect' : name)!) {
      const fn = FNS[command] ?? (command === name.toLowerCase()
        ? `Effects.${name[0].toLowerCase()}${name.slice(1)}`
        : undefined);
      if (SNIPPETS[command]) {
        SNIPPETS[command](name);
      } else if (fn) {
        write(`try ${fn}(battle, player, state, options);`);
      } else {
        write(`// TODO ${command}`);
      }
    }
    indent--;
  };

  const boosts: string[] = [];
  const boostChances: string[] = [];
  const unboosts: string[] = [];
  const unboostChances: string[] = [];
  outer: for (const name of ['None', ...names]) {
    for (const group of GROUPED) {
      if (group.includes(name)) {
        const canonical = group[group.length - 1];
        if (canonical !== name) {
          const commands = effects.get(name);
          // DreamEater can't proc King's Rock
          const n = name === 'DreamEater' ? 2 : 1;
          if (commands && levenshtein(commands, effects.get(canonical)!) > n) {
            throw new Error(`Invalid grouping of effects: '${name}' and '${canonical}'`);
          }
          continue outer;
        }
        write(`${group.map(e => `.${e}`).join(', ')} => {`);
        writeCommands(name);
        write('},');
        continue outer;
      }
    }
    if (BOOST.test(name) || name === 'DefenseCurl') {
      (name.endsWith('Chance') ? boostChances : boosts).push(name);
      continue;
    } else if (UNBOOST.test(name)) {
      (name.endsWith('Chance') ? unboostChances : unboosts).push(name);
      continue;
    }

    write(`.${name} => {`);
    writeCommands(name);
    write('},');
  }

  for (const array of [boosts, boostChances, unboosts, unboostChances]) {
    const enums = array.sort().map(e => `.${e}`);
    const k = array === boostChances ? 1 : 2;
    if (k > 1) write('// zig fmt: off');
    for (const {chunk, done} of chunks(enums, Math.ceil(enums.length / k))) {
      const end = done ? ' => {' : ',';
      write(`${chunk.join(', ')}${end}`);
    }
    if (k > 1) write('// zig fmt: on');
    indent++;
    write('_ = try canMove(battle, player, state, options);');
    if (array === unboosts) {
      write('try checkHit(battle, player, state, options);');
    } else if (array === boostChances || array === unboostChances) {
      write('if (!try doMove(SECONDARY, battle, player, state, options)) return;');
      write('if (!try afterMove(!KINGS, battle, player, state, options)) return;');
      if (array === unboostChances) {
        write(
          '// GLITCH: moves that lower Defense can do so after breaking a Substitute',
          'if (move.effect == .DefenseDownChance) {',
          '    try effectChance(battle, player, state, options);',
          '}',
        );
      }
    }
    const fn = array === boosts || array === boostChances ? 'boost' : 'unboost';
    write(`try Effects.${fn}(battle, player, state, options);`);
    if (array === boosts) {
      write(
        'if (move.effect == .DefenseCurl) {',
        '    try Effects.defenseCurl(battle, player, state, options);',
        '}',
      );
    }
    indent--;
    write('},');
  }

  indent--;
  write('}');
  indent--;
  write('}');

  fs.writeFileSync(path.join(path.dirname(dirs.out), 'generated.zig'), buf.join('\n') + '\n');
};

type GenerateFn = (
  gen: Generation, dirs: {out: string; cache: string}, update: boolean, tests: boolean
) => Promise<void>;
const GEN: {[gen in GenerationNum]?: GenerateFn} = {
  1: async (gen, dirs, update, tests) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokered/master';
    // Moves
    const HIGH_CRIT = ['KARATE_CHOP', 'RAZOR_LEAF', 'CRABHAMMER', 'SLASH'];
    let url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, (line, _, i) => {
      const match = /move (\w+),\W+(\w+),/.exec(line);
      if (!match) return undefined;
      const move = gen.moves.get(match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1])!;
      const effect = HIGH_CRIT.includes(match[1]) ? 'HIGH_CRITICAL_EFFECT' : match[2];
      if (move.num !== i + 1) {
        throw new Error(`Expected ${move.num} for ${move.name} and received ${i + 1}`);
      }
      return `${nameToEnum(move.name)} ${constToEffectEnum(effect)}`;
    });

    const MOVES: string[] = [];
    const PP: string[] = [];
    const EFFECTS: {[key: string]: Set<string>} = {
      onBegin: new Set(),
      onEnd: new Set(),
      isSpecial: new Set(),
      isMulti: new Set(),
      other: new Set(),
    };
    for (const m of moves) {
      const [name, effect] = m.split(' ');
      if (effect !== 'None') EFFECTS[effectToGroup(effect)].add(effect);
      const move = gen.moves.get(name)!;
      const bp = move.basePower;
      const accuracy = move.accuracy === true ? 100 : move.accuracy;
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .effect = .${effect},\n` +
        `            .bp = ${bp},\n` +
        `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `            .accuracy = percent(${accuracy}),\n` +
        `            .target = .${TARGETS[move.target]},\n` +
        '        }');
      PP.push(`${move.pp}, // ${name}`);
      DATA[0].moves[move.name] = move.pp;
    }
    let Data = `/// Data associated with a Pokémon move.
    pub const Data = packed struct(u32) {
        effect: Effect,
        /// The move's base PP.
        bp: u8,
        /// The move's accuracy percentage.
        accuracy: u8,
        /// The move's type.
        type: Type,
        /// The move's targeting behavior.
        target: Target,
    };`;

    const begin = EFFECTS.onBegin.size;
    const end = begin + EFFECTS.onEnd.size;
    const special = end + EFFECTS.isSpecial.size;
    const multi = special + EFFECTS.isMulti.size;
    const effects: string[] = [];
    // Sort STAT_DOWN/ALWAYS_HAPPEN_* specially so that they can be sub-range checked
    for (const group in EFFECTS) {
      effects.push(`${group === 'onBegin' ? '' : '        '}// ${group}`);
      const sorted = group === 'onEnd'
        ? [...STAT_DOWN, ...Array.from(EFFECTS[group]).filter(e => !STAT_DOWN.includes(e)).sort()]
        : group === 'isSpecial'
          ? [...ALWAYS_HAPPEN_SPECIAL,
            ...Array.from(EFFECTS[group]).filter(e => !ALWAYS_HAPPEN_SPECIAL.includes(e)).sort()]
          : group === 'other'
            ? [...STAT_DOWN_CHANCE, ...SECONDARY_CHANCE,
              ...Array.from(EFFECTS[group]).filter(e =>
                !STAT_DOWN_CHANCE.includes(e) && !SECONDARY_CHANCE.includes(e)).sort()]
            : Array.from(EFFECTS[group]).sort();
      effects.push(`        ${sorted.join(',\n        ')},`);
    }
    const sd = begin + STAT_DOWN.length;
    const ahs = end + ALWAYS_HAPPEN_SPECIAL.length;
    const sdc = multi + STAT_DOWN_CHANCE.length;
    const sec = sdc + SECONDARY_CHANCE.length;
    const Effect = `
    /// Representation of a move's effect.
    pub const Effect = enum(u8) {
        None,
        ${effects.join('\n')}

        comptime {
            assert(@sizeOf(Effect) == 1);
        }

        /// Whether this effect activates during the "begin" step of move execution.
        pub fn onBegin(effect: Effect) bool {
            return @intFromEnum(effect) > 0 and @intFromEnum(effect) <= ${begin};
        }

        /// Whether this effect lowers stats.
        pub fn isStatDown(effect: Effect) bool {
            return @intFromEnum(effect) > ${begin} and @intFromEnum(effect) <= ${sd};
        }

        /// Whether this effect activates during the "end" step of move execution.
        pub fn onEnd(effect: Effect) bool {
            return @intFromEnum(effect) > ${begin} and @intFromEnum(effect) <= ${end};
        }

        /// Whether this effect is considered to "always happen".
        pub fn alwaysHappens(effect: Effect) bool {
            return @intFromEnum(effect) > ${end} and @intFromEnum(effect) <= ${ahs};
        }

        /// Whether this effect is handled specially by the engine.
        pub fn isSpecial(effect: Effect) bool {
            // NB: isSpecial includes isMulti up to Twineedle
            return @intFromEnum(effect) > ${end} and @intFromEnum(effect) <= ${multi - 1};
        }

        /// Whether this effect is a multi-hit effect.
        pub fn isMulti(effect: Effect) bool {
            return @intFromEnum(effect) > ${special} and @intFromEnum(effect) <= ${multi};
        }

        /// Whether this effect is has chance of lowering stats.
        pub fn isStatDownChance(effect: Effect) bool {
            return @intFromEnum(effect) > ${multi} and @intFromEnum(effect) <= ${sdc};
        }

        /// Whether this effect has a secondary chance.
        pub fn isSecondaryChance(effect: Effect) bool {
            // NB: isSecondaryChance includes isStatDownChance as well as Twineedle
            return (@intFromEnum(effect) > ${multi - 1} and @intFromEnum(effect) <= ${sec});
        }
    };\n`;

    const SENTINEL =
      ',\n\n    // Sentinel used when Pokémon\'s turn should be skipped (e.g. bound)\n' +
      '    SKIP_TURN = 0xFF';

    const metronome = `init: {
        var num = 0;
        var moves: [${moves.length - 2}]Move = undefined;
        for (1..Move.size) |i| {
            if (i != @intFromEnum(Move.Metronome)) {
                moves[num] = @enumFromInt(i);
                num += 1;
            }
        }
        assert(num == moves.len);
        break :init moves;
    };`;

    template('moves', dirs.out, {
      gen: gen.num,
      roman: 'I',
      import: '\nconst rng = @import("../../common/rng.zig");',
      percent: '\nconst percent = rng.Gen12.percent;',
      Move: {
        type: 'u8',
        values: moves.map(m => m.split(' ')[0]).join(',\n    ') + SENTINEL,
        num: moves.length,
        metronome,
        size: 1,
        Data,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 4,
        Effect,
        targetType: 'u4',
        assert: 'assert(id != .None and id != .SKIP_TURN);',
        ppData: PP.join('\n        '),
      },
    });

    if (tests) moveTests(gen, moves);

    // Species
    url = `${pret}/constants/pokedex_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, (line, _, i) => {
      const match = /const DEX_(\w+)/.exec(line);
      if (!match) return undefined;
      const specie = gen.species.get(match[1])!;
      if (specie.num !== i + 1) {
        throw new Error(`Expected ${specie.num} for ${specie.name} and received ${i + 1}`);
      }
      return nameToEnum(specie.name);
    });
    const SPECIES = [];
    const CHANCES = [];
    for (const name of species) {
      const s = gen.species.get(name)!;
      const types = s.types.length === 1
        ? [s.types[0], s.types[0]] : s.types;
      SPECIES.push(`// ${name}\n` +
        '        .{\n' +
        '            .stats = .{ ' +
                        `.hp = ${s.baseStats.hp}, ` +
                        `.atk = ${s.baseStats.atk}, ` +
                        `.def = ${s.baseStats.def}, ` +
                        `.spe = ${s.baseStats.spe}, ` +
                        `.spc = ${s.baseStats.spa}` +
                      ' },\n' +
        `            .types = .{ .type1 = .${types[0]}, .type2 = .${types[1]} },\n` +
        '        }');
      CHANCES.push(`${Math.floor(s.baseStats.spe / 2)}, // ${name}`);
      DATA[0].species[s.name] = {
        stats: {
          hp: s.baseStats.hp,
          atk: s.baseStats.atk,
          def: s.baseStats.def,
          spe: s.baseStats.spe,
          spc: s.baseStats.spa,
        },
        types: s.types,
      };
    }
    Data = `/// Data associated with a Pokémon species.
    pub const Data = struct {
        /// The base stats of the Pokémon species.
        stats: Stats(u8),
        /// The typing of the Pokémon species.
        types: Types,
    };`;
    const chances = `const CHANCES = [_]u8{
        ${CHANCES.join('\n        ')}
    };\n
    `;
    const chanceFn = `

    /// The Pokémon's critical hit rate=io out of 256.
    pub fn chance(id: Species) u8 {
        assert(id != .None);
        return CHANCES[@intFromEnum(id) - 1];
    }`;
    template('species', dirs.out, {
      gen: gen.num,
      roman: 'I',
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        num: species.length,
        size: 1,
        chances,
        Data,
        data: SPECIES.join(',\n        '),
        chanceFn,
      },
    });

    // Types
    url = `${pret}/data/types/type_matchups.asm`;
    const matchups = await getOrUpdate('types', dirs.cache, url, update, line => {
      const match = /db ([A-Z_]+),\s+([A-Z_]+),\s+[A-Z_]+/.exec(line);
      if (!match) return undefined;
      const attacker = gen.types.get(match[1] === 'PSYCHIC_TYPE' ? 'PSYCHIC' : match[1])!;
      const defender = gen.types.get(match[2] === 'PSYCHIC_TYPE' ? 'PSYCHIC' : match[2])!;
      return [attacker.name, defender.name].join(' ');
    });

    const relevant = new Set();
    for (const s of gen.species) {
      if (s.types.length < 2) continue;
      for (const type of gen.types) {
        const e1 = type.effectiveness[s.types[0]];
        const e2 = type.effectiveness[s.types[1]!];
        if (e1 + e2 === 2.5) {
          relevant.add([type.name, s.types[0]].join(' '));
          relevant.add([type.name, s.types[1]].join(' '));
        }
      }
    }

    const precedence = [];
    for (const matchup of matchups) {
      if (relevant.has(matchup)) {
        const [t1, t2] = matchup.split(' ');
        precedence.push(`        .{ .type1 = .${t1}, .type2 = .${t2} },`);
      }
    }

    const precedenceFn =
    `/// The precedence order of Type \`t2\` vs. Type \`t1\`.
    pub fn precedence(t1: Type, t2: Type) u8 {
        for (PRECEDENCE, 0..) |matchup, i| {
            if (matchup.type1 == t1 and matchup.type2 == t2) return @intCast(i);
        }
        unreachable;
    }`;

    const types = IDS[0].types;
    template('types', dirs.out, {
      roman: 'I',
      Type: {
        type: 'u4',
        values: types.join(',\n    '),
        bitSize: 4,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
        precedence: `const PRECEDENCE = [_]Types{\n${precedence.join('\n')}\n    };`,
        precedenceSize: precedence.length,
        precedenceFn,
      },
      Types: {
        qualifier: 'packed',
        size: 1,
      },
    });
  },
  2: async (gen, dirs, update, tests) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokecrystal/master';

    // Types
    const types = IDS[1].types;

    const precedence = [];
    const indexes = [];
    for (const type of types) {
      precedence.push(`        ${TYPE_PRECEDENCE.indexOf(type)}, // ${type}`);
      indexes.push(`        ${TYPE_INDEXES[type]}, // ${type}`);
    }
    const conversion2 = [];
    for (const type in TYPE_INDEXES) {
      if (TYPE_INDEXES[type as keyof typeof TYPE_INDEXES] > 10) break;
      if (conversion2.length === 6) conversion2.push('        .@"???", // placeholder');
      conversion2.push(`        .${type},`);
    }
    const hiddenPower = [];
    for (const type of HIDDEN_POWER) {
      if (type === 'Normal' || type === '???') continue;
      hiddenPower.push(`        .${type},`);
    }
    const showdown = [];
    for (const type of gen.types) {
      showdown.push(`        .${type.name === '???' ? '@"???"' : type.name},`);
    }

    const precedenceFn =
    `/// The precedence order of Type \`type\`.
    pub fn precedence(self: Type) u8 {
        return PRECEDENCE[@intFromEnum(self)];
    }`;

    const extraFns = `

    /// The internal index of this Type used by Present.
    pub fn present(self: Type) u8 {
        return INDEXES[@intFromEnum(self)];
    }

    /// The Type corresponding to a random roll of \`num\` for Conversion 2.
    pub fn conversion2(num: u8) Type {
        assert(num != 6);
        assert(num < 10 or num >= 20);
        assert(num <= 27);
        return if (num < 10) CONVERSION_2[num] else @enumFromInt(num - 10);
    }

    /// The Type corresponding to a Hidden Power \`index\`.
    pub fn hiddenPower(index: u8) Type {
        return HIDDEN_POWER[index];
    }`;

    const sandstormFn = `\n
    /// Whether this typing is immune to damage from Sandstorm.
    pub fn sandstormImmune(self: Types) bool {
        return @intFromEnum(self.type1) <= @intFromEnum(Type.Steel) or
            @intFromEnum(self.type2) <= @intFromEnum(Type.Steel);
    }`;

    template('types', dirs.out, {
      roman: 'II',
      Type: {
        type: 'u8',
        values: types.map(t => t === '???' ? '@"???"' : t).join(',\n    '),
        bitSize: 8,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
        precedence: `const PRECEDENCE = [_]u8{\n${precedence.join('\n')}\n    };`,
        precedenceSize: precedence.length,
        precedenceFn,
        extra: `\n\n    const INDEXES = [_]u8{\n${indexes.join('\n')}\n    };` +
        `\n\n    const CONVERSION_2 = [_]Type{\n${conversion2.join('\n')}\n    };` +
        `\n\n    const HIDDEN_POWER = [_]Type{\n${hiddenPower.join('\n')}\n    };` +
        '\n\n    /// Order of Pokémon Showdown\'s types.\n' +
        `    pub const SHOWDOWN = [_]Type{\n${showdown.join('\n')}\n    };`,
        extraSizes: `\n        assert(@sizeOf(@TypeOf(INDEXES)) == ${indexes.length});` +
        `\n        assert(@sizeOf(@TypeOf(CONVERSION_2)) == ${conversion2.length});` +
          `\n        assert(@sizeOf(@TypeOf(HIDDEN_POWER)) == ${hiddenPower.length});` +
          `\n        assert(@sizeOf(@TypeOf(SHOWDOWN)) == ${showdown.length});`,
        extraFns,
      },
      Types: {
        qualifier: 'extern',
        size: 2,
        extraFns: sandstormFn,
      },
    });

    // Items
    let url = `${pret}/data/items/attributes.asm`;
    const items = await getOrUpdate('items', dirs.cache, url, update, (line, last) => {
      const match = /^; ([A-Z]\w+)/.exec(last);
      if (!match || match[1].startsWith('HM') || match[1].startsWith('ITEM_')) return undefined;
      if (line.includes('KEY_ITEM')) return undefined;
      if (last.startsWith('; BUG:')) return undefined;

      const m = /HELD_(\w+),/.exec(line)!;
      const held = NAMES[m[1]] || constToEnum(m[1]);
      const name = match[1].startsWith('TM')
        ? `${match[1]}`
        : (NAMES[match[1]] || constToEnum(match[1]));
      return `${name} ${held}`;
    });
    const SPECIAL = ['ThickClub', 'LightBall', 'BerserkGene', 'Stick'];
    const NO_EFFECTS = ['AmuletCoin', 'CleanseTag', 'SmokeBall'];
    const nothing: {present: string[]; missing: string[]} = {present: [], missing: []};
    const effects: string[] = [];
    const mail: string[] = [];
    const berries: string[] = [];
    const boosts: [string, TypeName][] = [];
    for (const item of items) {
      const [name, held] = item.split(' ');
      if (held === 'None' || NO_EFFECTS.includes(name)) {
        if (SPECIAL.includes(name)) {
          effects.push(`${name},`);
        } else if (name.endsWith('Mail')) {
          mail.push(`${name},`);
        } else {
          nothing[gen.items.get(name) ? 'present' : 'missing'].push(`${name},`);
        }
        continue;
      }
      const s = `${name}, // ${held}`;
      if (name.endsWith('Berry') || held === 'Berry') {
        berries.push(s);
      } else if (held.endsWith('Boost')) {
        boosts.push([name, gen.types.get(held.slice(0, -5))!.name]);
      } else {
        effects.push(s);
      }
    }
    const values: string[] = [];
    for (const type of types) {
      if (type === '???') {
        values.push('PolkadotBow, // ??? (Normal)');
      } else {
        for (const [n, t] of boosts) {
          if (t === type) {
            values.push(`${n}, // ${t}`);
            break;
          }
        }
      }
    }
    const offset = {effect: 0, present: 0, mail: 0};
    for (const s of effects) {
      values.push(s);
    }
    offset.effect = values.length;
    const ORDER = [
      'Berry', 'BerryJuice', 'GoldBerry', 'MintBerry', 'PSNCureBerry', 'PRZCureBerry',
      'IceBerry', 'BurntBerry', 'MiracleBerry', 'BitterBerry', 'MysteryBerry',
    ];
    if (berries.length !== ORDER.length) {
      throw new Error(`Berries: ${berries.length} != ${ORDER.length}`);
    }
    for (const s of ORDER) {
      values.push(berries.find(b => b.startsWith(`${s},`))!);
    }
    for (const s of nothing.present) {
      values.push(s);
    }
    offset.present = values.length;
    values.push('// Pokémon Showdown excludes the following items (minus "Mail")');
    for (const s of mail) {
      values.push(s);
    }
    offset.mail = values.length - 1; // account for comment
    for (const s of nothing.missing) {
      values.push(s);
    }
    for (const value of values) {
      const symbol = value.split(' ')[0];
      const id = toID(symbol);
      if (id) {
        IDS[1].items.push(id);
        const name = symbol.replace(/(?<!^)([A-Z])([a-z])/g, ' $1$2').slice(0, -1);
        DATA[1].items.push(name as ItemName);
      }
    }
    template('items', dirs.out, {
      gen: gen.num,
      roman: 'II',
      Item: {
        type: 'u8',
        values: values.join('\n    '),
        num: values.length,
        size: 1,
        boosts: boosts.length,
        ...offset,
      },
    });

    if (tests) itemTests(gen, items);

    // Moves
    const HIGH_CRIT = // NOTE: RAZOR_WIND is also high critical hit ratio...
      ['KARATE_CHOP', 'RAZOR_LEAF', 'CRABHAMMER', 'SLASH', 'AEROBLAST', 'CROSS_CHOP'];
    const CONTINUOUS = [
      'razorwind', 'skyattack', 'skullbash', 'solarbeam', 'fly',
      'rollout', 'bide', 'thrash', 'petaldance', 'outrage',
    ];
    const NO_METRONOME = [
      'metronome', 'struggle', 'sketch', 'mimic', 'counter', 'mirrorcoat',
      'protect', 'detect', 'endure', 'destinybond', 'sleeptalk', 'thief',
    ];
    const NO_SLEEP_TALK =
      ['skullbash', 'razorwind', 'skyattack', 'solarbeam', 'fly', 'dig', 'bide'];
    const FLYING = ['gust', 'whirlwind', 'thunder', 'twister'];
    const UNDERGROUND = ['earthquake', 'fissure', 'magnitude'];
    const BINDING = ['bind', 'wrap', 'firespin', 'clamp', 'whirlpool'];
    url = `${pret}/data/moves/moves.asm`;
    const moves = await getOrUpdate('moves', dirs.cache, url, update, (line, _, i) => {
      const match = /move (\w+),\W+(\w+),/.exec(line);
      if (!match) return undefined;
      const move = gen.moves.get(match[1] === 'PSYCHIC_M' ? 'PSYCHIC' : match[1])!;
      const effect = HIGH_CRIT.includes(match[1]) ? 'HIGH_CRITICAL_EFFECT' : match[2];
      if (move.num !== i + 1) {
        throw new Error(`Expected ${move.num} for ${move.name} and received ${i + 1}`);
      }
      return `${nameToEnum(move.name)} ${constToEffectEnum(effect)}`;
    });
    const MOVES: string[] = [];
    const PP: string[] = [];
    const EFFECTS = new Set<string>();
    for (const m of moves) {
      const [name, effect] = m.split(' ');
      if (effect !== 'None') EFFECTS.add(effect);
      const move = gen.moves.get(name)!;
      const chance = move.secondary?.chance ? `percent(${move.secondary.chance}),` : '';
      const acc = move.accuracy === true ? 100 : move.accuracy;
      const extra =
        NO_METRONOME.includes(move.id) ? '.{ .metronome = false }'
        : CONTINUOUS.includes(move.id) &&
          NO_SLEEP_TALK.includes(move.id) ? '.{ .sleep_talk = false, .continuous = true }'
        : CONTINUOUS.includes(move.id) ? '.{ .continuous = true }'
        : NO_SLEEP_TALK.includes(move.id) ? '.{ .sleep_talk = false }'
        : FLYING.includes(move.id) ? '.{ .flying = true }'
        : UNDERGROUND.includes(move.id) ? '.{ .underground = true }'
        : BINDING.includes(move.id) ? `.{ .protocol = ${BINDING.indexOf(move.id) + 1} }` : '';
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .effect = .${effect},\n` +
        `            .bp = ${move.basePower},\n` +
        `            .type = .${move.type === '???' ? '@"???"' : move.type},\n` +
        `            .accuracy = percent(${acc}),\n` +
        `            .target = .${TARGETS[move.target]},\n` +
        (chance ? `            .chance = ${chance}\n` : '') +
        (move.priority ? `            .priority = ${move.priority},\n` : '') +
        (extra ? `            .extra = ${extra},\n` : '') +
        '        }');
      PP.push(`${move.pp}, // ${name}`);
      DATA[1].moves[move.name] = move.pp;
    }
    // accuracy/target/chance/priority could all be u4, but packed struct needs to be power of 2
    let Data = `/// Data associated with a Pokémon move.
    pub const Data = extern struct {
        /// The move's effect.
        effect: Effect,
        /// The move's base power.
        bp: u8,
        /// The move's type.
        type: Type,
        /// The move's accuracy percentage.
        accuracy: u8,
        /// The move's targeting behavior.
        target: Target,
        /// The chance of the move's secondary effect occurring.
        chance: u8 = 0,
        /// The priority of the move.
        priority: i8 = 0,
        /// Miscellaneous extra data/flags.
        extra: Extra = .{},

        /// Miscellaneous extra move related data/flags.
        const Extra = packed struct(u8) {
            /// Whether this move can be called via Metronome.
            metronome: bool = true,
            /// Whether this move can be called via Sleep Talk.
            sleep_talk: bool = true,
            /// Whether this move is considered to be "continuous".
            continuous: bool = false,
            /// Whether this move can hit a flying target.
            flying: bool = false,
            /// Whether this move can hit an underground target.
            underground: bool = false,
            /// Protocol reason offset associated with this move.
            protocol: u3 = 0,
        };

        comptime {
            assert(@sizeOf(Data) == 8);
        }
    };`;

    const Effect = `
    /// Representation of a move's effect.
    pub const Effect = enum(u8) {
        None,
        ${Array.from(EFFECTS).sort().join(',\n        ')},

        comptime {
            assert(@sizeOf(Effect) == 1);
        }

        /// Whether this effect has a high critical rate.
        pub fn isHighCritical(effect: Effect) bool {
            return effect == .HighCritical or effect == .RazorWind;
        }
    };\n`;

    const metronome = `init: {
        var num = 0;
        var moves: [${moves.length - NO_METRONOME.length}]Move = undefined;
        for (1..Move.size + 1) |i| {
            if (Move.get(@enumFromInt(i)).extra.metronome) {
                moves[num] = @enumFromInt(i);
                num += 1;
            }
        }
        assert(num == moves.len);
        break :init moves;
    };`;

    template('moves', dirs.out, {
      gen: gen.num,
      roman: 'II',
      import: '\nconst rng = @import("../../common/rng.zig");',
      percent: '\nconst percent = rng.Gen12.percent;',
      Move: {
        type: 'u8',
        values: moves.map(m => m.split(' ')[0]).join(',\n    '),
        num: moves.length,
        metronome,
        size: 1,
        Data,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 8,
        assert: 'assert(id != .None);',
        Effect,
        targetType: 'u8',
        ppData: PP.join('\n        '),
      },
    });

    if (tests) moveTests(gen, moves);
    await moveFns(gen, dirs, update, pret, EFFECTS);

    // Species
    url = `${pret}/constants/pokemon_constants.asm`;
    const species = await getOrUpdate('species', dirs.cache, url, update, (line, _, i) => {
      const match = /const (\w+)/.exec(line);
      if (!match || match[1] === 'EGG' || match[1].startsWith('UNOWN_')) return undefined;
      const specie = gen.species.get(match[1])!;
      if (specie.num !== i + 1) {
        throw new Error(`Expected ${specie.num} for ${specie.name} and received ${i + 1}`);
      }
      return nameToEnum(specie.name);
    });
    const SPECIES = [];
    for (const name of species) {
      const s = gen.species.get(name)!;
      const t = s.types.length === 1
        ? [s.types[0], s.types[0]] : s.types;
      const ratio = convertGenderRatio(s);
      SPECIES.push(`// ${name}\n` +
        '        .{\n' +
        '            .stats = .{ ' +
                        `.hp = ${s.baseStats.hp}, ` +
                        `.atk = ${s.baseStats.atk}, ` +
                        `.def = ${s.baseStats.def}, ` +
                        `.spe = ${s.baseStats.spe}, ` +
                        `.spa = ${s.baseStats.spa}, ` +
                        `.spd = ${s.baseStats.spd}` +
                      ' },\n' +
        `            .types = .{ .type1 = .${t[0]}, .type2 = .${t[1]} },\n` +
        `            .ratio = ${ratio}\n` +
        '        }');
      DATA[1].species[s.name] = {
        stats: {
          hp: s.baseStats.hp,
          atk: s.baseStats.atk,
          def: s.baseStats.def,
          spe: s.baseStats.spe,
          spa: s.baseStats.spa,
          spd: s.baseStats.spa,
        },
        types: s.types,
        gender: Number(ratio.split(',')[0]),
      };
    }
    Data = `/// Data associated with a Pokémon species.
    pub const Data = struct {
        /// The base stats of the Pokémon species.
        stats: Stats(u8),
        /// The typing of the Pokémon species.
        types: Types,
        /// The gender ratio of the Pokémon species.
        ratio: u8,
    };`;
    template('species', dirs.out, {
      gen: gen.num,
      roman: 'II',
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        num: species.length,
        size: 1,
        Data,
        data: SPECIES.join(',\n        '),
      },
    });
  },
};

(async () => {
  const gens = new Generations(Dex as any);

  const tests = process.argv[2] === 'tests' && +process.argv[3];

  let UPDATE = process.argv.includes('--force');
  if (mkdir(CACHE)) UPDATE = true;

  for (const n in GEN) {
    const gen = gens.get(n);

    const out = path.join(ROOT, 'src', 'lib', `gen${gen.num}`, 'data');
    const cache = path.join(CACHE, `gen${gen.num}`);

    let update = UPDATE;
    if (mkdir(out)) update = true;
    if (mkdir(cache)) update = true;

    await GEN[gen.num]!(gen, {out, cache}, update, tests === gen.num);
  }

  const idsJSON = path.join(ROOT, 'src', 'pkg', 'data', 'ids.json');
  fs.writeFileSync(idsJSON, JSON.stringify(IDS, null, 2));
  const dataJSON = path.join(ROOT, 'src', 'data', 'data.json');
  fs.writeFileSync(dataJSON, stringify(DATA, {maxLength: 100}));
})().catch((err: any) => {
  console.error(err);
  process.exit(1);
});
