import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import * as https from 'https';

import * as mustache from 'mustache';

import {Generations, Generation, GenerationNum, TypeName, Specie, MoveTarget} from '@pkmn/data';
import {Dex, toID} from '@pkmn/sim';

import type {IDs} from '../pkg/data';

const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATES = path.join(ROOT, 'src', 'lib', 'common', 'data');
const CACHE = path.join(ROOT, '.cache');

const IDS: IDs = [
  {
    types: [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost',
      'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon',
    ] as TypeName[],
  },
  {
    types: [
      'Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost', 'Steel',
      '???', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark',
    ] as TypeName[],
    items: [],
  },
];

const NAMES: { [constant: string]: string } = {
  // Items
  BLACKBELT_I: 'BlackBelt',
  BLACKGLASSES: 'BlackGlasses',
  BLK_APRICORN: 'BlackApricorn',
  BLU_APRICORN: 'BlueApricorn',
  BLUESKY_MAIL: 'BlueSkyMail',
  BRIGHTPOWDER: 'BrightPowder',
  ELIXER: 'Elixir',
  ENERGYPOWDER: 'EnergyPowder',
  GRN_APRICORN: 'GreenApricorn',
  HP_UP: 'HPUp',
  LITEBLUEMAIL: 'LightBlueMail',
  MAX_ELIXER: 'MaxElixir',
  MIRACLEBERRY: 'MiracleBerry',
  MYSTERYBERRY: 'MysteryBerry',
  NEVERMELTICE: 'NeverMeltIce',
  PARLYZ_HEAL: 'ParylzeHeal',
  PNK_APRICORN: 'PinkApricorn',
  PORTRAITMAIL: 'PortrailMail',
  PP_UP: 'PPUp',
  PRZCUREBERRY: 'PRZCureBerry',
  PSNCUREBERRY: 'PSNCureBerry',
  RAGECANDYBAR: 'RageCandyBar',
  SILVERPOWDER: 'SilverPowder',
  SLOWPOKETAIL: 'SlowpokeTail',
  THUNDERSTONE: 'ThunderStone',
  TINYMUSHROOM: 'TinyMushroom',
  TWISTEDSPOON: 'TwistedSpoon',
  WHT_APRICORN: 'WhiteApricorn',
  YLW_APRICORN: 'YellowApricorn',
  // Moves
  SMELLING_SALT: 'SmellingSalts',
  // Effects
  NO_ADDITIONAL_EFFECT: 'None',
  EFFECT_NORMAL_HIT: 'None',
  FLY_EFFECT: 'Charge',
  TWO_TO_FIVE_ATTACKS_EFFECT: 'MultiHit',
  ATTACK_TWICE_EFFECT: 'DoubleHit',
  OHKO_EFFECT: 'OHKO',
  EFFECT_OHKO: 'OHKO',
  DRAIN_HP_EFFECT: 'DrainHP',
  EFFECT_LEECH_HIT: 'DrainHP',
  EFFECT_ACCURACY_DOWN_HIT: 'AccuracyDownChance',
  EFFECT_ACCURACY_DOWN: 'AccuracyDown1',
  EFFECT_ALL_UP_HIT: 'BoostAllChance',
  EFFECT_ATTACK_DOWN_HIT: 'AttackDownChance',
  EFFECT_ATTACK_DOWN: 'AttackDown1',
  EFFECT_ATTACK_UP_HIT: 'AttackDownChance',
  EFFECT_ATTACK_UP: 'AttackUp1',
  EFFECT_BURN_HIT: 'BurnChance',
  EFFECT_CONFUSE_HIT: 'ConfusionChance',
  EFFECT_CONFUSE: 'Confusion',
  EFFECT_DEFENSE_DOWN_HIT: 'DefenseDownChance',
  EFFECT_DEFENSE_DOWN: 'DefenseDown1',
  EFFECT_DEFENSE_UP_HIT: 'DefenseUpChance',
  EFFECT_DEFENSE_UP: 'DefenseUp1',
  EFFECT_EVASION_DOWN: 'EvasionDown1',
  EFFECT_EVASION_UP: 'EvasionUp1',
  EFFECT_FLINCH_HIT: 'FlinchChance',
  EFFECT_FREEZE_HIT: 'FreezeChance',
  EFFECT_PARALYZE_HIT: 'ParalyzeChance',
  EFFECT_POISON_HIT: 'PoisonChance',
  EFFECT_POISON_MULTI_HIT: 'Twineedle',
  EFFECT_PRIORITY_HIT: 'Priority',
  EFFECT_RAMPAGE: 'Thrashing',
  EFFECT_RECOILD_HIT: 'Recoil',
  THRASH_PETAL_DANCE_EFFECT: 'Thrashing',
  EFFECT_SELF_DESTRUCT: 'Explode',
  EFFECT_SP_ATK_UP: 'SpAtkUp1',
  EFFECT_SP_DEF_DOWN_HIT: 'SpDefDownChance',
  EFFECT_SPEED_DOWN: 'SpeedDown1',
  EFFECT_SPEED_DOWN_HIT: 'SpeedDownChance',
  EFFECT_TRAP_TARGET: 'Trapping',
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

const GROUPS: { [constant: string]: string[] } = {
  // data/battle/residual_effects_1.asm
  onBeginMove: [
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
    'SuperFang', 'SpecialDamage', 'Thrashing', 'Trapping',
  ],
  // custom group used as an optimization/simplification by the engine
  isMulti: ['DoubleHit', 'MultiHit', 'Twineedle'],
};
const EFFECT_TO_GROUP: { [effect: string]: string } = {};
for (const group in GROUPS) {
  for (const effect of GROUPS[group]) {
    EFFECT_TO_GROUP[effect] = group;
  }
}

// NB:  all/allySide/allyTeam/self  = All/Field/AllySide/Self dont advance frames
// TODO: determine frames for adjacentAlly/adjacentAllyOrSelf/adjacentFoe/allies
// NB: beforeTurnCallback = extra advance (Counter, Mirror Coat, Pursuit)
// NB: validTargetLoc: allAdjacentFoes/FoeSide (allies)= Foes (Allies) = advance
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
  any: 'Other',
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
    if (line) result.push(line.trim());
  }
  return result;
};

const NO_EFFECT = 'No additional effect.';

const moveTests = (gen: Generation, moves: string[]) => {
  const effects: {[name: string]: string[]} = {};
  for (const m of moves) {
    const name = m.split(' ')[0];
    const move = gen.moves.get(name)!;
    if ([move.shortDesc, move.desc].includes(NO_EFFECT)) continue;
    effects[move.desc] = effects[move.desc] || [];
    effects[move.desc].push(name);
  }

  const buf = [];
  for (const desc in effects) {
    const key = effects[desc].length === 1 ? effects[desc][0] : `{${effects[desc].join(',')}}`;
    buf.push(`test "Move.${key}" {\n    // ${desc}\n    return error.SkipZigTest;\n}\n`);
  }
  console.log(buf.join('\n'));
};

const itemTests = (gen: Generation, items: string[]) => {
  const effects: {[name: string]: string[]} = {};
  for (const value of items) {
    const [name, held] = value.split(' ');
    const item = gen.items.get(name);
    if (name.endsWith('Mail')) {
      effects.Mail = effects.Mail || [];
      effects.Mail.push(name);
      continue;
    }
    if (!item || held === 'NONE') continue;
    effects[item.desc] = effects[item.desc] || [];
    effects[item.desc].push(name);
  }

  const buf = [];
  for (const desc in effects) {
    const key = effects[desc].length === 1 ? effects[desc][0] : `{${effects[desc].join(',')}}`;
    buf.push(`test "Item.${key}" {\n    // ${desc}\n    return error.SkipZigTest;\n}\n`);
  }
  console.log(buf.join('\n'));
};

type GenerateFn = (
  gen: Generation, dirs: { out: string; cache: string }, update: boolean, tests: boolean
) => Promise<void>;
const GEN: { [gen in GenerationNum]?: GenerateFn } = {
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
    const EFFECTS: { [key: string]: Set<string>} = {
      onBeginMove: new Set(),
      onEnd: new Set(),
      isSpecial: new Set(),
      isMulti: new Set(),
      other: new Set(),
    };
    for (const m of moves) {
      const [name, effect] = m.split(' ');
      if (effect !== 'None') EFFECTS[effectToGroup(effect)].add(effect);
      const move = gen.moves.get(name)!;
      const accuracy = move.accuracy === true ? 100 : move.accuracy;
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .effect = .${effect},\n` +
        `            .bp = ${move.basePower},\n` +
        `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `            .accuracy = ${accuracy},\n` +
        `            .target = .${TARGETS[move.target]},\n` +
        '        }');
      PP.push(`${move.pp}, // ${name}`);
    }
    let Data = `pub const Data = packed struct {
        effect: Effect,
        bp: u8,
        accuracy: u8,
        type: Type,
        target: Target,

        comptime {
            assert(@sizeOf(Data) == 4);
        }
    };`;

    const begin = EFFECTS.onBeginMove.size;
    const end = begin + EFFECTS.onEnd.size;
    const special = end + EFFECTS.isSpecial.size;
    const multi = special + EFFECTS.isMulti.size;
    const effects: string[] = [];
    // Sort STAT_DOWN/ALWAYS_HAPPEN_* specially so that they can be sub-range checked
    for (const group in EFFECTS) {
      effects.push(`${group === 'onBeginMove' ? '' : '        '}// ${group}`);
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
    pub const Effect = enum(u8) {
        None,
        ${effects.join('\n')}

        comptime {
            assert(@sizeOf(Effect) == 1);
        }

        pub inline fn onBegin(effect: Effect) bool {
            return @enumToInt(effect) > 0 and @enumToInt(effect) <= ${begin};
        }

        pub inline fn isStatDown(effect: Effect) bool {
            return @enumToInt(effect) > ${begin} and @enumToInt(effect) <= ${sd};
        }

        pub inline fn onEnd(effect: Effect) bool {
            return @enumToInt(effect) > ${begin} and @enumToInt(effect) <= ${end};
        }

        pub inline fn alwaysHappens(effect: Effect) bool {
            return @enumToInt(effect) > ${end} and @enumToInt(effect) <= ${ahs};
        }

        pub inline fn isSpecial(effect: Effect) bool {
            // NB: isSpecial includes isMulti up to Twineedle
            return @enumToInt(effect) > ${end} and @enumToInt(effect) <= ${multi - 1};
        }

        pub inline fn isMulti(effect: Effect) bool {
            return @enumToInt(effect) > ${special} and @enumToInt(effect) <= ${multi};
        }

        pub inline fn isStatDownChance(effect: Effect) bool {
            return @enumToInt(effect) > ${multi} and @enumToInt(effect) <= ${sdc};
        }

        pub inline fn isSecondaryChance(effect: Effect) bool {
            // NB: isSecondaryChance includes isStatDownChance as well as Twineedle
            return (@enumToInt(effect) > ${multi - 1} and @enumToInt(effect) <= ${sec});
        }
    };\n`;

    const ppData = `
    // @test-only
    const PP = [_]u8{
        ${PP.join('\n        ')},
    };\n`;
    const ppFn = `pub fn pp(id: Move) u8 {
        assert(id != .None);
        return PP[@enumToInt(id) - 1];
    }`;
    const SENTINEL =
      ',\n\n    // Sentinel used when Pokémon\'s turn should be skipped (eg. trapped)\n' +
      '    SKIP_TURN = 0xFF';

    const frames = `if (id == .Counter and event == .resolve) return 2;
        return @as(u8, @boolToInt(switch (event) {
            .resolve => get(id).target.resolves(),
            .run => get(id).target.runs(),
        }));`;

    template('moves', dirs.out, {
      gen: gen.num,
      Move: {
        type: 'u8',
        values: moves.map(m => m.split(' ')[0]).join(',\n    ') + SENTINEL,
        size: 1,
        Data,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 4,
        Effect,
        frames,
        ppData,
        ppFn,
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
    }
    Data = `// @test-only
    pub const Data = struct {
        stats: Stats(u8),
        types: Types,
    };`;
    const chances = `const CHANCES = [_]u8{
        ${CHANCES.join('\n        ')}
    };\n
    `;
    const chanceFn = `\n
    pub inline fn chance(id: Species) u8 {
        assert(id != .None);
        return CHANCES[@enumToInt(id) - 1];
    }`;
    template('species', dirs.out, {
      gen: gen.num,
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
        size: 1,
        chances,
        Data,
        data: SPECIES.join(',\n        '),
        chanceFn,
      },
    });

    // Types
    const types = IDS[0].types;
    template('types', dirs.out, {
      Type: {
        type: 'u4',
        values: types.join(',\n    '),
        bitSize: 4,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
      },
      Types: {
        qualifier: 'packed',
        bitSize: 8,
      },
    });
  },
  2: async (gen, dirs, update, tests) => {
    const pret = 'https://raw.githubusercontent.com/pret/pokecrystal/master';

    // Types
    const types = IDS[1].types;
    template('types', dirs.out, {
      Type: {
        type: 'u8',
        values: types.map(t => t === '???' ? '@"???"' : t).join(',\n    '),
        bitSize: 8,
        num: types.length,
        chart: getTypeChart(gen, types).join('\n        '),
        chartSize: types.length * types.length,
      },
      Types: {
        qualifier: 'extern',
        bitSize: 16,
      },
    });

    // Items
    let url = `${pret}/data/items/attributes.asm`;
    const items = await getOrUpdate('items', dirs.cache, url, update, (line, last) => {
      const match = /^; ([A-Z]\w+)/.exec(last);
      if (!match || match[1].startsWith('HM') || match[1].startsWith('ITEM_')) return undefined;
      if (line.includes('KEY_ITEM')) return undefined;

      const held = /HELD_(\w+),/.exec(line)![1];
      const name = match[1].startsWith('TM')
        ? `${match[1]}`
        : (NAMES[match[1]] || constToEnum(match[1]));
      return `${name} ${held}`;
    });
    const values: string[] = [];
    const mail: string[] = [];
    const berries: string[] = [];
    const boosts: [string, TypeName][] = [];
    for (const item of items) {
      const [name, held] = item.split(' ');
      if (held === 'NONE') {
        if (name.endsWith('Mail')) {
          mail.push(`${name},`);
        } else {
          values.push(`${name},`);
        }
        continue;
      }
      const s = `${name}, // ${held}`;
      if (name.endsWith('Berry')) {
        berries.push(s);
      } else if (held.endsWith('_BOOST')) {
        boosts.push([name, gen.types.get(held.slice(0, held.indexOf('_')))!.name]);
      } else {
        values.push(s);
      }
    }
    for (const type of types.reverse()) {
      if (type === '???') {
        values.unshift('PolkadotBow, // ??? (Normal)');
      } else {
        for (const [n, t] of boosts) {
          if (t === type) {
            values.unshift(`${n}, // ${t}`);
            break;
          }
        }
      }
    }
    const offset = {mail: 0, berries: 0};
    offset.mail = values.length;
    for (const s of mail) {
      values.push(s);
    }
    offset.berries = values.length;
    for (const s of berries) {
      values.push(s);
    }
    for (const value of values) {
      IDS[1].items.push(toID(value.split(' ')[0]));
    }
    template('items', dirs.out, {
      gen: gen.num,
      Item: {
        type: 'u8',
        values: values.join('\n    '),
        size: 1,
        boosts: boosts.length,
        mail: offset.mail,
        berry: offset.berries,
      },
    });

    if (tests) itemTests(gen, items);

    // Moves
    const HIGH_CRIT = // NOTE: RAZOR_WIND is also high critical hit ratio...
      ['KARATE_CHOP', 'RAZOR_LEAF', 'CRABHAMMER', 'SLASH', 'AEROBLAST', 'CROSS_CHOP'];
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
    const EFFECTS = new Set<string>();
    for (const m of moves) {
      const [name, effect] = m.split(' ');
      if (effect !== 'None') EFFECTS.add(effect);
      const move = gen.moves.get(name)!;
      const pp = move.pp === 1 ? '0, // = 1' : `${move.pp / 5}, // * 5 = ${move.pp}`;
      const chance = move.secondary?.chance
        ? `${move.secondary.chance / 10}, // * 10 = ${move.secondary.chance}`
        : '';
      const acc = move.accuracy === true ? 100 : move.accuracy;
      MOVES.push(`// ${name}\n` +
        '        .{\n' +
        `            .effect = .${effect},\n` +
        `            .bp = ${move.basePower},\n` +
        `            .type = .${move.type === '???' ? 'Normal' : move.type},\n` +
        `            .pp = ${pp}\n` +
        `            .acc = ${acc / 5 - 6}, // ${acc}%\n` +
        `            .target = .${TARGETS[move.target]},\n` +
        (chance ? `            .chance = ${chance}\n` : '') +
        '        }');
    }
    let Data = `pub const Data = packed struct {
        effect: Effect,
        bp: u8,
        type: Type,
        pp: u4, // pp / 5
        acc: u4, // accuracy / 5 - 6
        target: Target,
        chance: u4 = 0, // chance / 10

        comptime {
            assert(@sizeOf(Data) == 5);
        }

        pub inline fn accuracy(self: Data) u8 {
            return (@as(u8, self.acc) + 6) * 5;
        }
    };`;

    const Effect = `\n    pub const Effect = enum(u8) {
        None,
        ${Array.from(EFFECTS).sort().join(',\n        ')},

        comptime {
            assert(@sizeOf(Effect) == 1);
        }\n` + '    };\n';

    const ppFn = `pub fn pp(id: Move) u8 {
        return Move.get(id).pp * 5;
    }`;

    const frames = `return @as(u8, @boolToInt(switch (event) {
            .resolve => switch (id) {
                .Counter, .MirrorCoat, .Pursuit => 2,
                else => get(id).target.resolves(),
            },
            .run => get(id).target.runs(),
        }));`;

    template('moves', dirs.out, {
      gen: gen.num,
      Move: {
        type: 'u8',
        values: moves.map(m => m.split(' ')[0]).join(',\n    '),
        size: 1,
        Data,
        data: MOVES.join(',\n        '),
        dataSize: MOVES.length * 5,
        Effect,
        frames,
        ppFn,
      },
    });

    if (tests) moveTests(gen, moves);

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
        `            .ratio = ${convertGenderRatio(s)}\n` +
        '        }');
    }
    Data = `// @test-only
    pub const Data = struct {
        stats: Stats(u8),
        types: Types,
        ratio: u8,
    };`;
    template('species', dirs.out, {
      gen: gen.num,
      Species: {
        type: 'u8',
        values: species.join(',\n    '),
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
    const gen = gens.get(+n as GenerationNum);

    const out = path.join(ROOT, 'src', 'lib', `gen${gen.num}`, 'data');
    const cache = path.join(CACHE, `gen${gen.num}`);

    let update = UPDATE;
    if (mkdir(out)) update = true;
    if (mkdir(cache)) update = true;

    await GEN[gen.num]!(gen, {out, cache}, update, tests === gen.num);
  }

  const idsJSON = path.join(ROOT, 'src', 'pkg', 'data', 'ids.json');
  fs.writeFileSync(idsJSON, JSON.stringify(IDS, null, 2));
})().catch((err: any) => {
  console.error(err);
  process.exit(1);
});
