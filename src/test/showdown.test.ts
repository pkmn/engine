import {Battle, Dex, ID, PRNG, PRNGSeed} from '@pkmn/sim';
import {Generations, PokemonSet} from '@pkmn/data';

const MIN = 0;
const MAX = 0xFFFFFFFF;

// const P1_FIRST = MIN;
// const P2_FIRST = MAX;
const NOP = MIN;
const HIT = MIN;
const MISS = MAX;
// const CRIT = MIN;
const NO_CRIT = MAX;
const MIN_DMG = MIN;
const MAX_DMG = MAX;
// const PROC = MIN;
// const NO_PROC = MAX;
// const CFZ = MAX;
// const NO_CFZ = MIN;

const MODS: {[gen: number]: string[]} = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;

  const createBattle = (rolls: number[]) => {
    const formatid = `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID;
    const battle = new Battle({formatid, strictChoices: true});
    (battle as any).debugMode = false;
    (battle as any).prng = new FixedRNG(rolls);
    return battle;
  };

  const startBattle = (rolls: number[], p1: Partial<PokemonSet>[], p2: Partial<PokemonSet>[]) => {
    const battle = createBattle(rolls);
    battle.setPlayer('p1', {team: p1 as PokemonSet[]});
    battle.setPlayer('p2', {team: p2 as PokemonSet[]});
    (battle as any).log = [];
    return battle;
  };

  const EVS = gen.num >= 3 ? 0 : 255;
  const evs = {hp: EVS, atk: EVS, def: EVS, spa: EVS, spd: EVS, spe: EVS};

  describe(`Gen ${gen.num}`, () => {
    test('turn order (priority)', () => {
      const battle = startBattle([
        NOP, NOP, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        NOP, NOP, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        NOP, NOP, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        NOP, NOP, NOP, HIT, NO_CRIT, MIN_DMG, HIT,
      ], [
        {species: 'Raticate', evs, moves: ['Tackle', 'Quick Attack', 'Counter']},
      ], [
        {species: 'Chansey', evs, moves: ['Tackle', 'Quick Attack', 'Counter']},
      ]);

      let p1hp = battle.p1.active[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      // Raticate > Chansey
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.active[0].hp).toBe(p1hp -= 20);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

      // Chansey > Raticate
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.active[0].hp).toBe(p1hp -= 22);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

      // Raticate > Chansey
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.active[0].hp).toBe(p1hp -= 22);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 104);

      // Chansey > Raticate
      battle.makeChoices('move 3', 'move 1');
      expect(battle.p1.active[0].hp).toBe(p1hp -= 20);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 40);

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Raticate|Tackle|p2a: Chansey',
        '|-damage|p2a: Chansey|612/703',
        '|move|p2a: Chansey|Tackle|p1a: Raticate',
        '|-damage|p1a: Raticate|293/313',
        '|turn|2',
        '|move|p2a: Chansey|Quick Attack|p1a: Raticate',
        '|-damage|p1a: Raticate|271/313',
        '|move|p1a: Raticate|Tackle|p2a: Chansey',
        '|-damage|p2a: Chansey|521/703',
        '|turn|3',
        '|move|p1a: Raticate|Quick Attack|p2a: Chansey',
        '|-damage|p2a: Chansey|417/703',
        '|move|p2a: Chansey|Quick Attack|p1a: Raticate',
        '|-damage|p1a: Raticate|249/313',
        '|turn|4',
        '|move|p2a: Chansey|Tackle|p1a: Raticate',
        '|-damage|p1a: Raticate|229/313',
        '|move|p1a: Raticate|Counter|p2a: Chansey',
        '|-damage|p2a: Chansey|377/703',
        '|turn|5',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Endless Battle Clause (initial)', () => {
      const battle = createBattle([]);
      battle.started = true;
      battle.setPlayer('p1', {team: [{species: 'Gengar', evs, moves: ['Lick']}] as PokemonSet[]});
      battle.setPlayer('p2', {team: [{species: 'Gengar', moves: ['Lick']}] as PokemonSet[]});

      battle.p1.pokemon[0].moveSlots[0].pp = 0;
      battle.p2.pokemon[0].moveSlots[0].pp = 0;

      battle.started = false;
      battle.start();

      expect(filter(battle.log)).toEqual([
        '|switch|p1a: Gengar|Gengar|323/323',
        '|switch|p2a: Gengar|Gengar|260/260',
        '|tie',
      ]);
    });

    test('OHKO', () => {
      const battle = startBattle([NOP, NOP, MISS, NOP, NOP, HIT], [
        {species: 'Kingler', evs, moves: ['Guillotine']},
        {species: 'Tauros', evs, moves: ['Horn Drill']},
      ], [
        {species: 'Dugtrio', evs, moves: ['Fissure']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].hp).toBe(0);

      expect(filter(battle.log)).toEqual([
        '|move|p2a: Dugtrio|Fissure|p1a: Kingler|[miss]',
        '|-miss|p2a: Dugtrio',
        '|move|p1a: Kingler|Guillotine|p2a: Dugtrio',
        '|-immune|p2a: Dugtrio|[ohko]',
        '|turn|2',
        '|move|p2a: Dugtrio|Fissure|p1a: Kingler',
        '|-damage|p1a: Kingler|0 fnt',
        '|-ohko',
        '|faint|p1a: Kingler',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SwitchAndTeleport', () => {
      const battle = startBattle([NOP, HIT, NOP, MISS], [
        {species: 'Abra', evs, moves: ['Teleport']},
      ], [
        {species: 'Pidgey', evs, moves: ['Whirlwind']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'move 1');

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Abra|Teleport|p1a: Abra',
        '|move|p2a: Pidgey|Whirlwind|p1a: Abra',
        '|turn|2',
        '|move|p1a: Abra|Teleport|p1a: Abra',
        '|move|p2a: Pidgey|Whirlwind|p1a: Abra|[miss]',
        '|-miss|p2a: Pidgey',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Splash', () => {
      const battle = startBattle([],
        [{species: 'Gyarados', evs, moves: ['Splash']}],
        [{species: 'Magikarp', evs, moves: ['Splash']}]);

      battle.makeChoices('move 1', 'move 1');

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Gyarados|Splash|p1a: Gyarados',
        '|-nothing',
        '|move|p2a: Magikarp|Splash|p2a: Magikarp',
        '|-nothing',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SpecialDamage (fixed)', () => {
      const battle = startBattle([NOP, NOP, HIT, HIT, NOP], [
        {species: 'Voltorb', evs, moves: ['Sonic Boom']},
      ], [
        {species: 'Dratini', evs, moves: ['Dragon Rage']},
        {species: 'Gastly', evs, moves: ['Night Shade']},
      ]);

      const p1hp = battle.p1.active[0].hp;
      const p2hp1 = battle.p2.pokemon[0].hp;
      const p2hp2 = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'switch 2');

      expect(battle.p1.active[0].hp).toEqual(p1hp - 40);
      expect(battle.p2.pokemon[0].hp).toEqual(p2hp2);
      expect(battle.p2.pokemon[1].hp).toEqual(p2hp1 - 20);

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Voltorb|Sonic Boom|p2a: Dratini',
        '|-damage|p2a: Dratini|265/285',
        '|move|p2a: Dratini|Dragon Rage|p1a: Voltorb',
        '|-damage|p1a: Voltorb|243/283',
        '|turn|2',
        '|switch|p2a: Gastly|Gastly|263/263',
        '|move|p1a: Voltorb|Sonic Boom|p2a: Gastly',
        '|-immune|p2a: Gastly',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SpecialDamage (level)', () => {
      const battle = startBattle([NOP, NOP, HIT, HIT], [
        {species: 'Gastly', evs, level: 22, moves: ['Night Shade']},
      ], [
        {species: 'Clefairy', evs, level: 16, moves: ['Seismic Toss']},
      ]);

      const p1hp = battle.p1.active[0].hp;
      const p2hp = battle.p2.active[0].hp;

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.active[0].hp).toEqual(p1hp - 16);
      expect(battle.p2.active[0].hp).toEqual(p2hp - 22);

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Gastly|Night Shade|p2a: Clefairy',
        '|-damage|p2a: Clefairy|41/63',
        '|move|p2a: Clefairy|Seismic Toss|p1a: Gastly',
        '|-damage|p1a: Gastly|49/65',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SpecialDamage (Psywave)', () => {
      const battle = startBattle([NOP, NOP, HIT, MAX_DMG, HIT, MIN_DMG], [
        {species: 'Gengar', evs, level: 59, moves: ['Psywave']},
      ], [
        {species: 'Clefable', evs, level: 42, moves: ['Psywave']},
      ]);

      const p2hp = battle.p2.active[0].hp;

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p2.active[0].hp).toEqual(p2hp - 87);

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Gengar|Psywave|p2a: Clefable',
        '|-damage|p2a: Clefable|83/170',
        '|move|p2a: Clefable|Psywave|p1a: Gengar',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SuperFang', () => {
      const battle = startBattle([NOP, NOP, HIT, HIT, NOP, NOP, HIT], [
        {species: 'Raticate', evs, moves: ['Super Fang']},
        {species: 'Haunter', evs, moves: ['Dream Eater']},
      ], [
        {species: 'Rattata', evs, moves: ['Super Fang']},
      ]);

      battle.p1.active[0].hp = 1;
      expect(battle.p2.active[0].hp).toBe(263);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.active[0].hp).toBe(0);
      expect(battle.p2.active[0].hp).toBe(132);

      battle.makeChoices('switch 2', '');
      expect(battle.p1.active[0].hp).toBe(293);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.active[0].hp).toBe(147);

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Raticate|Super Fang|p2a: Rattata',
        '|-damage|p2a: Rattata|132/263',
        '|move|p2a: Rattata|Super Fang|p1a: Raticate',
        '|-damage|p1a: Raticate|0 fnt',
        '|faint|p1a: Raticate',
        '|switch|p1a: Haunter|Haunter|293/293',
        '|turn|2',
        '|move|p1a: Haunter|Dream Eater|p2a: Rattata',
        '|-immune|p2a: Rattata',
        '|move|p2a: Rattata|Super Fang|p1a: Haunter',
        '|-damage|p1a: Haunter|147/293',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Conversion', () => {
      const battle = startBattle([NOP], [
        {species: 'Porygon', evs, moves: ['Conversion']},
      ], [
        {species: 'Slowbro', evs, moves: ['Teleport']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      expect(filter(battle.log)).toEqual([
        '|move|p1a: Porygon|Conversion|p2a: Slowbro',
        '|-start|p1a: Porygon|typechange|Water/Psychic|[from] move: Conversion|[of] p2a: Slowbro',
        '|move|p2a: Slowbro|Teleport|p2a: Slowbro',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });
  });

  if (gen.num === 1) {
    describe('Gen 1', () => {
      test.todo('0 damage glitch');
      test.todo('1/256 miss glitch');
      test.todo('Defrost move forcing');
      test.todo('Division by 0');
      test.todo('Invulnerability glitch');
      test.todo('Stat modification errors');
      test.todo('Struggle bypassing');
      test.todo('Trapping sleep glitch');
      test.todo('Partial trapping move Mirror Move glitch');
      test.todo('Rage and Thrash / Petal Dance accuracy bug');
      test.todo('Stat down modifier overflow glitch');
    });
  }
}

class FixedRNG extends PRNG {
  private readonly rolls: number[];
  private index: number;

  constructor(rolls: number[]) {
    super([0, 0, 0, 0]);
    this.rolls = rolls;
    this.index = 0;
  }

  next(from?: number, to?: number): number {
    if (this.index >= this.rolls.length) throw new Error('Insufficient number of rolls provided');
    let result = this.rolls[this.index++];
    if (from) from = Math.floor(from);
    if (to) to = Math.floor(to);
    if (from === undefined) {
      result = result / 0x100000000;
    } else if (!to) {
      result = Math.floor(result * from / 0x100000000);
    } else {
      result = Math.floor(result * (to - from) / 0x100000000) + from;
    }
    return result;
  }

  get startingSeed(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  clone(): PRNG {
    throw new Error('Unsupported operation');
  }

  nextFrame(): PRNGSeed {
    throw new Error('Unsupported operation');
  }

  exhausted(): boolean {
    return this.index === this.rolls.length;
  }
}

const SKIP = new Set([
  '', 't:', 'gametype', 'player', 'teamsize', 'gen',
  'tier', 'rule', 'start', 'upkeep', '-message', '-hint',
]);

function filter(raw: string[]) {
  const log = Battle.extractUpdateForSide(raw.join('\n'), 'omniscient').split('\n');
  const filtered = [];
  for (const line of log) {
    const i = line.indexOf('|', 1);
    const arg = line.slice(1, i > 0 ? i : line.length);
    if (SKIP.has(arg)) continue;
    filtered.push(line);
  }

  return filtered;
}
