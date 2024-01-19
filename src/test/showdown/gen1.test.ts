import {Generations} from '@pkmn/data';
import {Battle, Dex, PRNG} from '@pkmn/sim';

import {Options} from '../benchmark';
import {
  Choices, FixedRNG, MAX, MIN, ROLLS, createStartBattle, formatFor, ranged, verify,
} from '../showdown';

const gens = new Generations(Dex as any);
const gen = gens.get(1);
const choices = Choices.get(gen);
const startBattle = createStartBattle(gen);

const {HIT, MISS, CRIT, NO_CRIT, MIN_DMG, MAX_DMG, TIE} = ROLLS.basic({
  hit: 'data/mods/gen1/scripts.ts:413:42',
  crit: 'data/mods/gen1/scripts.ts:812:27',
  dmg: 'data/mods/gen1/scripts.ts:933:27',
});

const SECONDARY = (value: number) => ({key: 'data/mods/gen1/scripts.ts:701:25', value});
const SLP = (n: number) =>
  ({key: 'data/mods/gen1/conditions.ts:63:38', value: ranged(n, 8 - 1)});
const DISABLE_MOVE = (m: number, n = 4) =>
  ({key: 'data/mods/gen1/moves.ts:250:27', value: ranged(m, n) - 1});
const DISABLE_DURATION = (n: number) =>
  ({key: 'data/mods/gen1/moves.ts:254:34', value: ranged(n, 9 - 1) - 1});
const MIMIC = (m: number, n = 4) =>
  ({key: 'data/mods/gen1/moves.ts:495:24', value: ranged(m, n) - 1});
const BIDE = (n: 2 | 3) =>
  ({key: 'data/mods/gen1/moves.ts:40:34', value: ranged(n - 2, 4 - 2)});
const NO_PAR = SECONDARY(MAX);
const PAR_CANT = {key: 'data/mods/gen1/conditions.ts:38:13', value: ranged(63, 256) - 1};
const PAR_CAN = {...PAR_CANT, value: PAR_CANT.value + 1};
const FRZ = SECONDARY(ranged(26, 256) - 1);
const CFZ = (n: number) =>
  ({key: 'data/mods/gen1/conditions.ts:133:33', value: ranged(n - 1, 6 - 2) - 1});
const CFZ_CAN = {key: 'data/mods/gen1/conditions.ts:146:14', value: ranged(128, 256) - 1};
const CFZ_CANT = {...CFZ_CAN, value: CFZ_CAN.value + 1};
const THRASH = (n: 3 | 4) =>
  ({key: 'data/mods/gen1/conditions.ts:227:33', value: ranged(n - 2, 4 - 2) - 1});
const MIN_WRAP = {key: 'data/mods/gen1/conditions.ts:199:26', value: MIN};
const MAX_WRAP = {...MIN_WRAP, value: MAX};
const REWRAP = {key: 'data/mods/gen1/scripts.ts:229:38', value: MIN};
const METRONOME = ROLLS.metronome(gen, ['Metronome', 'Struggle']);

const evs = {hp: 255, atk: 255, def: 255, spa: 255, spd: 255, spe: 255};

describe('Gen 1', () => {
  // General

  test('start (first fainted)', () => {
    const battle = startBattle([], [
      {species: 'Pikachu', evs, moves: ['Thunder Shock']},
      {species: 'Bulbasaur', evs, moves: ['Tackle']},
    ], [
      {species: 'Charmander', evs, moves: ['Scratch']},
      {species: 'Squirtle', evs, moves: ['Tackle']},
    ], b => {
      b.p1.pokemon[0].hp = 0;
      b.p2.pokemon[0].hp = 0;
    });

    // lol...
    verify(battle, [
      '|switch|p1a: Pikachu|Pikachu|0 fnt',
      '|switch|p2a: Charmander|Charmander|0 fnt',
      '|turn|1',
    ]);
  });

  test('start (all fainted)', () => {
    // Win
    {
      const battle = startBattle([], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p2.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur|293/293',
        '|switch|p2a: Charmander|Charmander|0 fnt',
        '|turn|1',
      ]);
    }
    // Lose
    {
      const battle = startBattle([], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p1.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur|0 fnt',
        '|switch|p2a: Charmander|Charmander|281/281',
        '|turn|1',
      ]);
    }
    // Tie
    {
      const battle = startBattle([], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p1.pokemon[0].hp = 0;
        b.p2.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur|0 fnt',
        '|switch|p2a: Charmander|Charmander|0 fnt',
        '|turn|1',
      ]);
    }
  });

  test('switching (order)', () => {
    const battle = startBattle([],
      Array(6).fill({species: 'Abra', moves: ['Teleport']})
        .map((p, i) => ({...p, level: (i + 1) * 10})),
      Array(6).fill({species: 'Gastly', moves: ['Lick']})
        .map((p, i) => ({...p, level: (i + 1)})));

    const expectOrder = (p1: number[], p2: number[]) => {
      for (let i = 0; i < 6; i++) {
        expect(battle.p1.pokemon[i].level).toBe(p1[i] * 10);
        expect(battle.p2.pokemon[i].level).toBe(p2[i]);
      }
    };

    battle.makeChoices('switch 3', 'switch 2');
    expectOrder([3, 2, 1, 4, 5, 6], [2, 1, 3, 4, 5, 6]);
    battle.makeChoices('switch 5', 'switch 5');
    expectOrder([5, 2, 1, 4, 3, 6], [5, 1, 3, 4, 2, 6]);
    battle.makeChoices('switch 6', 'switch 3');
    expectOrder([6, 2, 1, 4, 3, 5], [3, 1, 5, 4, 2, 6]);
    battle.makeChoices('switch 3', 'switch 3');
    expectOrder([1, 2, 6, 4, 3, 5], [5, 1, 3, 4, 2, 6]);
    battle.makeChoices('switch 2', 'switch 4');
    expectOrder([2, 1, 6, 4, 3, 5], [4, 1, 3, 5, 2, 6]);

    (battle as any).log = [];
    battle.makeChoices('switch 5', 'switch 5');
    expectOrder([3, 1, 6, 4, 2, 5], [2, 1, 3, 5, 4, 6]);

    verify(battle, [
      '|switch|p1a: Abra|Abra, L30|64/64',
      '|switch|p2a: Gastly|Gastly, L2|13/13',
      '|turn|7',
    ]);
  });

  test('turn order (priority)', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT,
    ], [
      {species: 'Raticate', evs, moves: ['Tackle', 'Quick Attack', 'Counter']},
    ], [
      {species: 'Chansey', evs, moves: ['Tackle', 'Quick Attack', 'Counter']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Raticate > Chansey
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

    // Chansey > Raticate
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

    // Raticate > Chansey
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 104);

    // Chansey > Raticate
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 40);

    verify(battle, [
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
  });

  test('turn order (basic speed tie)', () => {
    // Move vs. Move
    {
      const battle = startBattle([TIE(1), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
      ], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 196);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 166);

      verify(battle, [
        '|move|p1a: Tauros|Hyper Beam|p2a: Tauros',
        '|-damage|p2a: Tauros|187/353',
        '|-mustrecharge|p1a: Tauros',
        '|move|p2a: Tauros|Hyper Beam|p1a: Tauros',
        '|-damage|p1a: Tauros|157/353',
        '|-mustrecharge|p2a: Tauros',
        '|turn|2',
      ]);
    }
    // Faint vs. Pass
    {
      const battle = startBattle([TIE(1), HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
      ], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
      ]);

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 166);

      battle.makeChoices('switch 2', '');

      verify(battle, [
        '|move|p1a: Tauros|Hyper Beam|p2a: Tauros',
        '|-damage|p2a: Tauros|187/353',
        '|-mustrecharge|p1a: Tauros',
        '|move|p2a: Tauros|Hyper Beam|p1a: Tauros',
        '|-crit|p1a: Tauros',
        '|-damage|p1a: Tauros|0 fnt',
        '|faint|p1a: Tauros',
        '|switch|p1a: Tauros|Tauros|353/353',
        '|turn|2',
      ]);
    }
    // Switch vs. Switch
    {
      const battle = startBattle([TIE(2)], [
        {species: 'Zapdos', evs, moves: ['Drill Peck']},
        {species: 'Dodrio', evs, moves: ['Fury Attack']},
      ], [
        {species: 'Raichu', evs, moves: ['Thunderbolt']},
        {species: 'Mew', evs, moves: ['Psychic']},
      ]);

      battle.makeChoices('switch 2', 'switch 2');

      verify(battle, [
        '|switch|p2a: Mew|Mew|403/403',
        '|switch|p1a: Dodrio|Dodrio|323/323',
        '|turn|2',
      ]);
    }
    // Move vs. Switch
    {
      const battle = startBattle([HIT, NO_CRIT, MIN_DMG], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
        {species: 'Starmie', evs, moves: ['Surf']},
      ], [
        {species: 'Tauros', evs, moves: ['Hyper Beam']},
        {species: 'Alakazam', evs, moves: ['Psychic']},
      ]);

      const p2hp = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 255);

      verify(battle, [
        '|switch|p2a: Alakazam|Alakazam|313/313',
        '|move|p1a: Tauros|Hyper Beam|p2a: Alakazam',
        '|-damage|p2a: Alakazam|58/313',
        '|-mustrecharge|p1a: Tauros',
        '|turn|2',
      ]);
    }
  });

  test('turn order (complex speed tie)', () => {
    // multiple events
    {
      const battle = startBattle([
        TIE(2), METRONOME('Fly'), METRONOME('Dig'), TIE(1),
        HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        METRONOME('Swift'), NO_CRIT, MIN_DMG, METRONOME('Petal Dance'),
        THRASH(3), HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Clefable', evs, moves: ['Metronome', 'Quick Attack']},
      ], [
        {species: 'Clefable', evs, moves: ['Metronome']},
        {species: 'Farfetch’d', evs, moves: ['Metronome']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp1 = battle.p2.pokemon[0].hp;
      let p2hp2 = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 50);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 64);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp1 -= 43);

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp2 -= 32);

      verify(battle, [
        '|move|p2a: Clefable|Metronome|p2a: Clefable',
        '|move|p2a: Clefable|Fly||[from]Metronome|[still]',
        '|-prepare|p2a: Clefable|Fly',
        '|move|p1a: Clefable|Metronome|p1a: Clefable',
        '|move|p1a: Clefable|Dig||[from]Metronome|[still]',
        '|-prepare|p1a: Clefable|Dig',
        '|turn|2',
        '|move|p1a: Clefable|Dig|p2a: Clefable|[from]Dig|[miss]',
        '|-miss|p1a: Clefable',
        '|move|p2a: Clefable|Fly|p1a: Clefable|[from]Fly',
        '|-damage|p1a: Clefable|343/393',
        '|turn|3',
        '|move|p1a: Clefable|Quick Attack|p2a: Clefable',
        '|-damage|p2a: Clefable|350/393',
        '|move|p2a: Clefable|Metronome|p2a: Clefable',
        '|move|p2a: Clefable|Swift|p1a: Clefable|[from]Metronome',
        '|-damage|p1a: Clefable|279/393',
        '|turn|4',
        '|switch|p2a: Farfetch’d|Farfetch’d|307/307',
        '|move|p1a: Clefable|Metronome|p1a: Clefable',
        '|move|p1a: Clefable|Petal Dance|p2a: Farfetch’d|[from]Metronome',
        '|-resisted|p2a: Farfetch’d',
        '|-damage|p2a: Farfetch’d|275/307',
        '|turn|5',
      ]);
    }
    // beforeTurnMove
    {
      const NOP = TIE(2);
      const battle = startBattle([NOP, TIE(1), HIT, HIT], [
        {species: 'Chansey', evs, moves: ['Counter']},
      ], [
        {species: 'Chansey', evs, moves: ['Counter']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      verify(battle, [
        '|move|p1a: Chansey|Counter|p2a: Chansey',
        '|-fail|p1a: Chansey',
        '|move|p2a: Chansey|Counter|p1a: Chansey',
        '|-fail|p2a: Chansey',
        '|turn|2',
      ]);
    }
  });

  test('turn order (switch vs. move)', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG], [
      {species: 'Raticate', evs, moves: ['Quick Attack']},
      {species: 'Rattata', evs, moves: ['Quick Attack']},
    ], [
      {species: 'Ninetales', evs, moves: ['Quick Attack']},
      {species: 'Vulpix', evs, moves: ['Quick Attack']},
    ]);

    const rattata = battle.p1.pokemon[1].hp;
    const vulpix = battle.p2.pokemon[1].hp;

    // Switch > Quick Attack
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(vulpix - 64);

    // Switch > Quick Attack
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(rattata - 32);

    verify(battle, [
      '|switch|p2a: Vulpix|Vulpix|279/279',
      '|move|p1a: Raticate|Quick Attack|p2a: Vulpix',
      '|-damage|p2a: Vulpix|215/279',
      '|turn|2',
      '|switch|p1a: Rattata|Rattata|263/263',
      '|move|p2a: Vulpix|Quick Attack|p1a: Rattata',
      '|-damage|p1a: Rattata|231/263',
      '|turn|3',
    ]);
  });

  test('PP deduction', () => {
    const battle = startBattle([], [
      {species: 'Alakazam', evs, moves: ['Teleport']},
    ], [
      {species: 'Abra', evs, moves: ['Teleport']},
    ]);

    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(32);
    expect(battle.p1.pokemon[0].baseMoveSlots[0].pp).toBe(32);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(32);
    expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(32);

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(31);
    expect(battle.p1.pokemon[0].baseMoveSlots[0].pp).toBe(31);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(31);
    expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(31);

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(30);
    expect(battle.p1.pokemon[0].baseMoveSlots[0].pp).toBe(30);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(30);
    expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(30);
  });

  test('accuracy (normal)', () => {
    const hit = {...HIT, value: ranged(Math.floor(85 * 255 / 100), 256) - 1};
    const miss = {...MISS, value: hit.value + 1};
    const battle = startBattle([hit, CRIT, MAX_DMG, miss], [
      {species: 'Hitmonchan', evs, moves: ['Mega Punch']},
    ], [
      {species: 'Machamp', evs, moves: ['Mega Punch']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 159);

    verify(battle, [
      '|move|p1a: Hitmonchan|Mega Punch|p2a: Machamp',
      '|-crit|p2a: Machamp',
      '|-damage|p2a: Machamp|224/383',
      '|move|p2a: Machamp|Mega Punch|p1a: Hitmonchan|[miss]',
      '|-miss|p2a: Machamp',
      '|turn|2',
    ]);
  });

  test('damage calc', () => {
    const NO_BRN = SECONDARY(ranged(77, 256));
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, NO_BRN, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Starmie', evs, moves: ['Water Gun', 'Thunderbolt']},
    ], [
      {species: 'Golem', evs, moves: ['Fire Blast', 'Strength']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // STAB super effective non-critical min damage vs. non-STAB resisted critical max damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 70);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 248);

    // immune vs. normal
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 68);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Starmie|Water Gun|p2a: Golem',
      '|-supereffective|p2a: Golem',
      '|-damage|p2a: Golem|115/363',
      '|move|p2a: Golem|Fire Blast|p1a: Starmie',
      '|-crit|p1a: Starmie',
      '|-resisted|p1a: Starmie',
      '|-damage|p1a: Starmie|253/323',
      '|turn|2',
      '|move|p1a: Starmie|Thunderbolt|p2a: Golem',
      '|-immune|p2a: Golem',
      '|move|p2a: Golem|Strength|p1a: Starmie',
      '|-damage|p1a: Starmie|185/323',
      '|turn|3',
    ]);
  });

  test('type precedence', () => {
    const no_proc = SECONDARY(MAX);
    const battle = startBattle([HIT, HIT, NO_CRIT, MAX_DMG, no_proc], [
      {species: 'Sandshrew', evs, moves: ['Poison Sting']},
    ], [
      {species: 'Weedle', evs, moves: ['String Shot']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 20);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 21);

    verify(battle, [
      '|move|p2a: Weedle|String Shot|p1a: Sandshrew',
      '|-unboost|p1a: Sandshrew|spe|1',
      '|move|p1a: Sandshrew|Poison Sting|p2a: Weedle',
      '|-damage|p2a: Weedle|262/283',
      '|turn|2',
    ]);
  });

  test('fainting (single)', () => {
    // Switch
    {
      const battle = startBattle([HIT, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Venusaur', evs, moves: ['Leech Seed']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Water Gun']},
        {species: 'Dratini', evs, moves: ['Dragon Rage']},
      ]);

      battle.p2.pokemon[0].hp = 1;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      expect(choices(battle, 'p1')).toEqual([]);
      expect(choices(battle, 'p2')).toEqual(['switch 2']);

      verify(battle, [
        '|move|p1a: Venusaur|Leech Seed|p2a: Slowpoke',
        '|-start|p2a: Slowpoke|move: Leech Seed',
        '|move|p2a: Slowpoke|Water Gun|p1a: Venusaur',
        '|-resisted|p1a: Venusaur',
        '|-damage|p1a: Venusaur|348/363',
        '|-damage|p2a: Slowpoke|0 fnt|[from] Leech Seed|[of] p1a: Venusaur',
        '|-heal|p1a: Venusaur|363/363|[silent]',
        '|faint|p2a: Slowpoke',
      ]);
    }
    // Win
    {
      const battle = startBattle([HIT], [
        {species: 'Dratini', evs, moves: ['Dragon Rage']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Water Gun']},
      ]);

      battle.p1.pokemon[0].hp = 1;
      battle.p2.pokemon[0].hp = 1;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Dratini|Dragon Rage|p2a: Slowpoke',
        '|-damage|p2a: Slowpoke|0 fnt',
        '|faint|p2a: Slowpoke',
        '|win|Player 1',
      ]);
    }
    // Lose
    {
      const battle = startBattle([NO_CRIT, MIN_DMG, HIT], [
        {species: 'Jolteon', evs, moves: ['Swift']},
      ], [
        {species: 'Dratini', evs, moves: ['Dragon Rage']},
      ]);

      battle.p1.pokemon[0].hp = 1;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(232);

      verify(battle, [
        '|move|p1a: Jolteon|Swift|p2a: Dratini',
        '|-damage|p2a: Dratini|232/285',
        '|move|p2a: Dratini|Dragon Rage|p1a: Jolteon',
        '|-damage|p1a: Jolteon|0 fnt',
        '|faint|p1a: Jolteon',
        '|win|Player 2',
      ]);
    }
  });

  test('fainting (double)', () => {
    // Switch
    {
      const battle = startBattle([HIT, CRIT, MAX_DMG], [
        {species: 'Weezing', evs, moves: ['Explosion']},
        {species: 'Koffing', evs, moves: ['Self-Destruct']},
      ], [
        {species: 'Weedle', evs, moves: ['Poison Sting']},
        {species: 'Caterpie', evs, moves: ['String Shot']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('switch 2', 'switch 2');

      verify(battle, [
        '|move|p1a: Weezing|Explosion|p2a: Weedle',
        '|-crit|p2a: Weedle',
        '|-damage|p2a: Weedle|0 fnt',
        '|faint|p2a: Weedle',
        '|faint|p1a: Weezing',
        '|switch|p1a: Koffing|Koffing|283/283',
        '|switch|p2a: Caterpie|Caterpie|293/293',
        '|turn|2',
      ]);
    }
    // Switch (boosted)
    {
      const battle = startBattle([HIT, NO_CRIT, MAX_DMG], [
        {species: 'Farfetch’d', evs, moves: ['Agility', 'Splash']},
        {species: 'Cubone', evs, moves: ['Bone Club']},
      ], [
        {species: 'Charmeleon', evs, moves: ['Splash', 'Explosion']},
        {species: 'Pikachu', evs, moves: ['Surf']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('switch 2', 'switch 2');

      verify(battle, [
        '|move|p2a: Charmeleon|Splash|p2a: Charmeleon',
        '|-nothing',
        '|move|p1a: Farfetch’d|Agility|p1a: Farfetch’d',
        '|-boost|p1a: Farfetch’d|spe|2',
        '|turn|2',
        '|move|p1a: Farfetch’d|Splash|p1a: Farfetch’d',
        '|-nothing',
        '|move|p2a: Charmeleon|Explosion|p1a: Farfetch’d',
        '|-damage|p1a: Farfetch’d|0 fnt',
        '|faint|p1a: Farfetch’d',
        '|faint|p2a: Charmeleon',
        '|switch|p2a: Pikachu|Pikachu|273/273',
        '|switch|p1a: Cubone|Cubone|303/303',
        '|turn|3',
      ]);
    }
    // Switch (paralyzed)
    {
      const battle = startBattle([HIT, PAR_CAN, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Farfetch’d', evs, moves: ['Thunder Wave', 'Splash']},
        {species: 'Cubone', evs, moves: ['Bone Club']},
      ], [
        {species: 'Charmeleon', evs, moves: ['Splash', 'Explosion']},
        {species: 'Pikachu', evs, moves: ['Surf']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].status).toBe('par');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('switch 2', 'switch 2');

      verify(battle, [
        '|move|p2a: Charmeleon|Splash|p2a: Charmeleon',
        '|-nothing',
        '|move|p1a: Farfetch’d|Thunder Wave|p2a: Charmeleon',
        '|-status|p2a: Charmeleon|par',
        '|turn|2',
        '|move|p1a: Farfetch’d|Splash|p1a: Farfetch’d',
        '|-nothing',
        '|move|p2a: Charmeleon|Explosion|p1a: Farfetch’d',
        '|-damage|p1a: Farfetch’d|0 fnt',
        '|faint|p1a: Farfetch’d',
        '|faint|p2a: Charmeleon',
        '|switch|p1a: Cubone|Cubone|303/303',
        '|switch|p2a: Pikachu|Pikachu|273/273',
        '|turn|3',
      ]);
    }
    // Tie
    {
      const battle = startBattle([HIT, CRIT, MAX_DMG], [
        {species: 'Weezing', evs, moves: ['Explosion']},
      ], [
        {species: 'Weedle', evs, moves: ['Poison Sting']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Weezing|Explosion|p2a: Weedle',
        '|-crit|p2a: Weedle',
        '|-damage|p2a: Weedle|0 fnt',
        '|faint|p2a: Weedle',
        '|faint|p1a: Weezing',
        '|tie',
      ]);
    }
  });

  test('end turn (turn limit)', () => {
    const battle = startBattle([], [
      {species: 'Bulbasaur', evs, moves: ['Tackle']},
      {species: 'Charmander', evs, moves: ['Scratch']},
    ], [
      {species: 'Squirtle', evs, moves: ['Tackle']},
      {species: 'Pikachu', evs, moves: ['Thunder Shock']},
    ]);

    for (let i = 0; i < 998; i++) {
      battle.makeChoices('switch 2', 'switch 2');
    }
    expect(battle.ended).toBe(false);
    expect(battle.turn).toBe(999);
    (battle as any).log = [];

    battle.makeChoices('switch 2', 'switch 2');
    expect(battle.ended).toBe(true);

    verify(battle, [
      '|switch|p1a: Charmander|Charmander|281/281',
      '|switch|p2a: Pikachu|Pikachu|273/273',
      '|tie',
    ]);
  });

  test('Endless Battle Clause (initial)', () => {
    const battle = startBattle([], [
      {species: 'Gengar', evs, moves: ['Lick']},
    ], [
      {species: 'Gengar', moves: ['Lick']},
    ], b => {
      b.p1.pokemon[0].moveSlots[0].pp = 0;
      b.p2.pokemon[0].moveSlots[0].pp = 0;
    });

    expect(battle.ended).toBe(true);
    verify(battle, [
      '|switch|p1a: Gengar|Gengar|323/323',
      '|switch|p2a: Gengar|Gengar|260/260',
      '|tie',
    ]);
  });

  test('Endless Battle Clause (basic)', () => {
    {
      const battle = startBattle([], [
        {species: 'Mew', evs, moves: ['Transform']},
      ], [
        {species: 'Ditto', evs, moves: ['Transform']},
      ], b => {
        b.p1.pokemon[0].moveSlots[0].pp = 0;
        b.p2.pokemon[0].moveSlots[0].pp = 0;
      });

      expect(battle.ended).toBe(true);
    }
    {
      const battle = startBattle([], [
        {species: 'Mew', evs, moves: ['Transform']},
        {species: 'Muk', evs, moves: ['Pound']},
      ], [
        {species: 'Ditto', moves: ['Transform']},
      ]);

      expect(battle.ended).toBe(false);
      battle.p1.pokemon[1].fainted = true;
      battle.makeChoices('move 1', 'move 1');
      expect(battle.ended).toBe(true);
    }
  });

  test('choices', () => {
    const random = new PRNG([1, 2, 3, 4]);
    const battle = new Battle({
      formatid: formatFor(gen), ...Options.get(gen, random) as any,
    });

    expect(choices(battle, 'p1')).toEqual([
      'switch 2', 'switch 3', 'switch 4', 'switch 5', 'switch 6',
      'move 1', 'move 2', 'move 3', 'move 4',
    ]);

    battle.p1.activeRequest!.forceSwitch = true;
    expect(choices(battle, 'p1')).toEqual([
      'switch 2', 'switch 3', 'switch 4', 'switch 5', 'switch 6',
    ]);

    battle.p1.activeRequest!.wait = true;
    expect(choices(battle, 'p1')).toEqual([]);
  });

  // Moves

  test('HighCritical effect', () => {
    const no_crit =
      {...CRIT, value: ranged(Math.floor(gen.species.get('Machop')!.baseStats.spe / 2), 256)};
    // Regular non-crit roll is still a crit for high critical moves
    const battle = startBattle([HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG], [
      {species: 'Machop', evs, moves: ['Karate Chop']},
    ], [
      {species: 'Machop', level: 99, evs, moves: ['Strength']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 73);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 92);

    verify(battle, [
      '|move|p1a: Machop|Karate Chop|p2a: Machop',
      '|-crit|p2a: Machop',
      '|-damage|p2a: Machop|247/339',
      '|move|p2a: Machop|Strength|p1a: Machop',
      '|-damage|p1a: Machop|270/343',
      '|turn|2',
    ]);
  });

  test('FocusEnergy effect', () => {
    const value = ranged(Math.floor(gen.species.get('Machoke')!.baseStats.spe / 2), 256) - 1;
    const crit = {...CRIT, value};
    const battle = startBattle([HIT, crit, MIN_DMG, HIT, crit, MIN_DMG], [
      {species: 'Machoke', evs, moves: ['Focus Energy', 'Strength']},
    ], [
      {species: 'Koffing', evs, moves: ['Double Team', 'Haze']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    // No crit after Focus Energy
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp -= 60);

    // Crit once Haze removes Focus Energy
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp -= 115);

    verify(battle, [
      '|move|p1a: Machoke|Focus Energy|p1a: Machoke',
      '|-start|p1a: Machoke|move: Focus Energy',
      '|move|p2a: Koffing|Double Team|p2a: Koffing',
      '|-boost|p2a: Koffing|evasion|1',
      '|turn|2',
      '|move|p1a: Machoke|Strength|p2a: Koffing',
      '|-damage|p2a: Koffing|223/283',
      '|move|p2a: Koffing|Haze|p2a: Koffing',
      '|-activate|p2a: Koffing|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p1a: Machoke|move: Focus Energy|[silent]',
      '|turn|3',
      '|move|p1a: Machoke|Strength|p2a: Koffing',
      '|-crit|p2a: Koffing',
      '|-damage|p2a: Koffing|108/283',
      '|move|p2a: Koffing|Double Team|p2a: Koffing',
      '|-boost|p2a: Koffing|evasion|1',
      '|turn|4',
    ]);
  });

  test('MultiHit effect', () => {
    const hit3 = {key: 'data/mods/gen1/scripts.ts:428:27', value: 0x60000000};
    const hit5 = {...hit3, value: MAX};
    const battle = startBattle([HIT, hit3, NO_CRIT, MAX_DMG, HIT, hit5, NO_CRIT, MAX_DMG], [
      {species: 'Kangaskhan', evs, moves: ['Comet Punch']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;
    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - (31 * 3) - 95);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    // Breaking a target's Substitute ends the move
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    verify(battle, [
      '|move|p1a: Kangaskhan|Comet Punch|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|352/383',
      '|-damage|p2a: Slowpoke|321/383',
      '|-damage|p2a: Slowpoke|290/383',
      '|-hitcount|p2a: Slowpoke|3',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|195/383',
      '|turn|2',
      '|move|p1a: Kangaskhan|Comet Punch|p2a: Slowpoke',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|-end|p2a: Slowpoke|Substitute',
      '|-hitcount|p2a: Slowpoke|4',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|turn|3',
    ]);
  });

  test('DoubleHit effect', () => {
    const battle = startBattle([HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG], [
      {species: 'Marowak', evs, moves: ['Bonemerang']},
    ], [
      {species: 'Slowpoke', level: 80, evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - (91 * 2) - 77);

    // Breaking a target's Substitute ends the move
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Marowak|Bonemerang|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|217/308',
      '|-damage|p2a: Slowpoke|126/308',
      '|-hitcount|p2a: Slowpoke|2',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|49/308',
      '|turn|2',
      '|move|p1a: Marowak|Bonemerang|p2a: Slowpoke',
      '|-end|p2a: Slowpoke|Substitute',
      '|-hitcount|p2a: Slowpoke|1',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|turn|3',
    ]);
  });

  test('Twineedle effect', () => {
    const proc = SECONDARY(ranged(52, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);
    const battle = startBattle([
      HIT, CRIT, MAX_DMG,
      HIT, NO_CRIT, MIN_DMG, no_proc,
      HIT, NO_CRIT, MIN_DMG, proc,
      HIT, NO_CRIT, MIN_DMG, proc,
    ], [
      {species: 'Beedrill', evs, moves: ['Twineedle']},
    ], [
      {species: 'Voltorb', evs, moves: ['Substitute', 'Splash']},
      {species: 'Weezing', evs, moves: ['Explosion']},
    ]);

    let voltorb = battle.p2.pokemon[0].hp;
    const weezing = battle.p2.pokemon[1].hp;

    // Breaking a target's Substitute ends the move
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(voltorb -= 70);
    expect(battle.p2.pokemon[0].status).toBe('');

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(voltorb -= (36 * 2));
    expect(battle.p2.pokemon[0].status).toBe('');

    // The second hit can poison the target
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(voltorb - (36 * 2));
    expect(battle.p2.pokemon[0].status).toBe('psn');

    // Poison types cannot be poisoned
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(weezing - (45 * 2));
    expect(battle.p2.pokemon[0].status).toBe('');

    verify(battle, [
      '|move|p2a: Voltorb|Substitute|p2a: Voltorb',
      '|-start|p2a: Voltorb|Substitute',
      '|-damage|p2a: Voltorb|213/283',
      '|move|p1a: Beedrill|Twineedle|p2a: Voltorb',
      '|-crit|p2a: Voltorb',
      '|-end|p2a: Voltorb|Substitute',
      '|-hitcount|p2a: Voltorb|1',
      '|turn|2',
      '|move|p2a: Voltorb|Splash|p2a: Voltorb',
      '|-nothing',
      '|move|p1a: Beedrill|Twineedle|p2a: Voltorb',
      '|-damage|p2a: Voltorb|177/283',
      '|-damage|p2a: Voltorb|141/283',
      '|-hitcount|p2a: Voltorb|2',
      '|turn|3',
      '|move|p2a: Voltorb|Splash|p2a: Voltorb',
      '|-nothing',
      '|move|p1a: Beedrill|Twineedle|p2a: Voltorb',
      '|-damage|p2a: Voltorb|105/283',
      '|-damage|p2a: Voltorb|69/283',
      '|-status|p2a: Voltorb|psn',
      '|-hitcount|p2a: Voltorb|2',
      '|turn|4',
      '|switch|p2a: Weezing|Weezing|333/333',
      '|move|p1a: Beedrill|Twineedle|p2a: Weezing',
      '|-supereffective|p2a: Weezing',
      '|-damage|p2a: Weezing|288/333',
      '|-damage|p2a: Weezing|243/333',
      '|-hitcount|p2a: Weezing|2',
      '|turn|5',
    ]);
  });

  test('Poison effect', () => {
    {
      const battle = startBattle([HIT, HIT, HIT, HIT], [
        {species: 'Jolteon', evs, moves: ['Toxic', 'Substitute']},
        {species: 'Abra', evs, moves: ['Splash']},
      ], [
        {species: 'Venomoth', evs, moves: ['Splash', 'Toxic']},
        {species: 'Drowzee', evs, moves: ['Poison Gas', 'Splash']},
      ]);

      let jolteon = battle.p1.pokemon[0].hp;
      let abra = battle.p1.pokemon[1].hp;
      let drowzee = battle.p2.pokemon[1].hp;

      // Poison-type Pokémon cannot be poisoned
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].status).toBe('');

      // Substitute blocks poison
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(jolteon -= 83);
      expect(battle.p1.pokemon[0].status).toBe('');

      // Toxic damage increases each turn
      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(drowzee);
      expect(battle.p2.pokemon[0].status).toBe('tox');

      battle.makeChoices('switch 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(abra);
      expect(battle.p1.pokemon[0].status).toBe('psn');
      expect(battle.p2.pokemon[0].hp).toBe(drowzee -= 20);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(abra -= 15);
      expect(battle.p2.pokemon[0].hp).toBe(drowzee -= 40);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(abra -= 15);
      expect(battle.p2.pokemon[0].hp).toBe(drowzee -= 60);

      verify(battle, [
        '|move|p1a: Jolteon|Toxic|p2a: Venomoth',
        '|-immune|p2a: Venomoth',
        '|move|p2a: Venomoth|Splash|p2a: Venomoth',
        '|-nothing',
        '|turn|2',
        '|move|p1a: Jolteon|Substitute|p1a: Jolteon',
        '|-start|p1a: Jolteon|Substitute',
        '|-damage|p1a: Jolteon|250/333',
        '|move|p2a: Venomoth|Toxic|p1a: Jolteon',
        '|-fail|p1a: Jolteon',
        '|turn|3',
        '|switch|p2a: Drowzee|Drowzee|323/323',
        '|move|p1a: Jolteon|Toxic|p2a: Drowzee',
        '|-status|p2a: Drowzee|tox',
        '|turn|4',
        '|switch|p1a: Abra|Abra|253/253',
        '|move|p2a: Drowzee|Poison Gas|p1a: Abra',
        '|-status|p1a: Abra|psn',
        '|-damage|p2a: Drowzee|303/323 tox|[from] psn',
        '|turn|5',
        '|move|p1a: Abra|Splash|p1a: Abra',
        '|-nothing',
        '|-damage|p1a: Abra|238/253 psn|[from] psn',
        '|move|p2a: Drowzee|Splash|p2a: Drowzee',
        '|-nothing',
        '|-damage|p2a: Drowzee|263/323 tox|[from] psn',
        '|turn|6',
        '|move|p1a: Abra|Splash|p1a: Abra',
        '|-nothing',
        '|-damage|p1a: Abra|223/253 psn|[from] psn',
        '|move|p2a: Drowzee|Splash|p2a: Drowzee',
        '|-nothing',
        '|-damage|p2a: Drowzee|203/323 tox|[from] psn',
        '|turn|7',
      ]);
    }
    {
      const battle = startBattle([HIT, HIT], [
        {species: 'Clefable', evs, moves: ['Toxic', 'Recover']},
      ], [
        {species: 'Diglett', level: 14, moves: ['Leech Seed', 'Recover']},
      ]);

      expect(battle.p2.active[0].maxhp).toBe(31);

      battle.makeChoices('move 1', 'move 1');
      for (let i = 0; i < 29; i++) {
        battle.makeChoices('move 2', 'move 2');
      }

      expect(battle.ended).toBe(false);
      expect(battle.p2.active[0].volatiles.residualdmg.counter).toBe(30);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.ended).toBe(true);

      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    }
  });

  test('PoisonChance effect', () => {
    const lo_proc = SECONDARY(ranged(52, 256) - 1);
    const hi_proc = SECONDARY(ranged(103, 256) - 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, lo_proc, HIT, NO_CRIT, MIN_DMG, hi_proc,
      HIT, NO_CRIT, MAX_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, lo_proc,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, lo_proc,
    ], [
      {species: 'Tentacruel', evs, moves: ['Poison Sting', 'Sludge']},
    ], [
      {species: 'Persian', evs, moves: ['Substitute', 'Poison Sting', 'Scratch']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Can't poison Poison-types / moves have different poison chances
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 5);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 18);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Substitute prevents poison chance
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p2.pokemon[0].status).toBe('');

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 46);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 18);
    expect(battle.p2.pokemon[0].status).toBe('psn');

    // Can't poison already poisoned Pokémon / poison causes residual damage
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 46);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 20 - 18));

    verify(battle, [
      '|move|p2a: Persian|Poison Sting|p1a: Tentacruel',
      '|-resisted|p1a: Tentacruel',
      '|-damage|p1a: Tentacruel|358/363',
      '|move|p1a: Tentacruel|Poison Sting|p2a: Persian',
      '|-damage|p2a: Persian|315/333',
      '|turn|2',
      '|move|p2a: Persian|Substitute|p2a: Persian',
      '|-start|p2a: Persian|Substitute',
      '|-damage|p2a: Persian|232/333',
      '|move|p1a: Tentacruel|Sludge|p2a: Persian',
      '|-end|p2a: Persian|Substitute',
      '|turn|3',
      '|move|p2a: Persian|Scratch|p1a: Tentacruel',
      '|-damage|p1a: Tentacruel|312/363',
      '|move|p1a: Tentacruel|Poison Sting|p2a: Persian',
      '|-damage|p2a: Persian|214/333',
      '|-status|p2a: Persian|psn',
      '|turn|4',
      '|move|p2a: Persian|Scratch|p1a: Tentacruel',
      '|-damage|p1a: Tentacruel|266/363',
      '|-damage|p2a: Persian|194/333 psn|[from] psn|[of] p1a: Tentacruel',
      '|move|p1a: Tentacruel|Poison Sting|p2a: Persian',
      '|-damage|p2a: Persian|176/333 psn',
      '|turn|5',
    ]);
  });

  test('BurnChance effect', () => {
    const lo_proc = SECONDARY(ranged(26, 256) - 1);
    const hi_proc = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, hi_proc,
      HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, lo_proc,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, lo_proc,
    ], [
      {species: 'Charizard', evs, moves: ['Ember', 'Fire Blast']},
    ], [
      {species: 'Tauros', evs, moves: ['Substitute', 'Fire Blast', 'Tackle']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Can't burn Fire-types / moves have different burn chances
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 38);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 51);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Substitute prevents burn chance
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 88);
    expect(battle.p2.pokemon[0].status).toBe('');

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 45);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 51);
    expect(battle.p2.pokemon[0].status).toBe('brn');

    // Can't burn already burnt Pokémon / Burn lowers attack and causes residual damage
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 22 - 51));

    verify(battle, [
      '|move|p2a: Tauros|Fire Blast|p1a: Charizard',
      '|-resisted|p1a: Charizard',
      '|-damage|p1a: Charizard|321/359',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|302/353',
      '|turn|2',
      '|move|p2a: Tauros|Substitute|p2a: Tauros',
      '|-start|p2a: Tauros|Substitute',
      '|-damage|p2a: Tauros|214/353',
      '|move|p1a: Charizard|Fire Blast|p2a: Tauros',
      '|-end|p2a: Tauros|Substitute',
      '|turn|3',
      '|move|p2a: Tauros|Tackle|p1a: Charizard',
      '|-damage|p1a: Charizard|276/359',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|163/353',
      '|-status|p2a: Tauros|brn',
      '|turn|4',
      '|move|p2a: Tauros|Tackle|p1a: Charizard',
      '|-damage|p1a: Charizard|253/359',
      '|-damage|p2a: Tauros|141/353 brn|[from] brn|[of] p1a: Charizard',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|90/353 brn',
      '|turn|5',
    ]);
  });

  test('FreezeChance effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT,
      HIT, NO_CRIT, MIN_DMG, FRZ, PAR_CANT,
      HIT, NO_CRIT, MIN_DMG, FRZ,
      HIT,
      HIT, NO_CRIT, MIN_DMG, FRZ,
      HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      HIT, NO_CRIT, MIN_DMG, MISS,
      MISS,
      HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Starmie', evs, moves: ['Ice Beam']},
      {species: 'Magmar', evs, moves: ['Ice Beam', 'Flamethrower', 'Substitute']},
      {species: 'Lickitung', evs, moves: ['Slam']},
    ], [
      {species: 'Jynx', evs, moves: ['Thunder Wave', 'Blizzard', 'Fire Spin', 'Flamethrower']},
    ]);

    let starmie = battle.p1.pokemon[0].hp;
    let magmar = battle.p1.pokemon[1].hp;
    let lickitung = battle.p1.pokemon[2].hp;
    let jynx = battle.p2.pokemon[0].hp;

    // Can't freeze Ice-types
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].hp).toBe(jynx -= 35);

    // Can't freeze a Pokémon which is already statused
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(starmie -= 63);
    expect(battle.p1.pokemon[0].status).toBe('par');

    // Can freeze Fire types
    battle.makeChoices('switch 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 140);
    expect(battle.p1.pokemon[0].status).toBe('frz');

    // Freezing prevents action
    battle.makeChoices('move 1', 'move 1');
    // ...Pokémon Showdown still lets you choose whatever
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2', 'move 3']);

    // Freeze Clause Mod prevents multiple Pokémon from being frozen
    battle.makeChoices('switch 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(lickitung -= 173);
    expect(battle.p1.pokemon[0].status).toBe('');

    // Fire Spin does not thaw frozen Pokémon
    battle.makeChoices('switch 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 5);
    expect(battle.p1.pokemon[0].status).toBe('frz');

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 5);

    // Other Fire moves thaw frozen Pokémon
    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 36);
    expect(battle.p1.pokemon[0].status).toBe('');

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 83);

    // Substitute blocks Freeze
    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar);
    expect(battle.p1.pokemon[0].status).toBe('');

    verify(battle, [
      '|move|p1a: Starmie|Ice Beam|p2a: Jynx',
      '|-resisted|p2a: Jynx',
      '|-damage|p2a: Jynx|298/333',
      '|move|p2a: Jynx|Thunder Wave|p1a: Starmie',
      '|-status|p1a: Starmie|par',
      '|turn|2',
      '|move|p2a: Jynx|Blizzard|p1a: Starmie',
      '|-resisted|p1a: Starmie',
      '|-damage|p1a: Starmie|260/323 par',
      '|cant|p1a: Starmie|par',
      '|turn|3',
      '|switch|p1a: Magmar|Magmar|333/333',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar',
      '|-damage|p1a: Magmar|193/333',
      '|-status|p1a: Magmar|frz',
      '|turn|4',
      '|move|p2a: Jynx|Thunder Wave|p1a: Magmar',
      '|-fail|p1a: Magmar',
      '|cant|p1a: Magmar|frz',
      '|turn|5',
      '|switch|p1a: Lickitung|Lickitung|383/383',
      '|move|p2a: Jynx|Blizzard|p1a: Lickitung',
      '|-damage|p1a: Lickitung|210/383',
      '|turn|6',
      '|switch|p1a: Magmar|Magmar|193/333 frz',
      '|move|p2a: Jynx|Fire Spin|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|188/333 frz',
      '|turn|7',
      '|move|p2a: Jynx|Fire Spin|p1a: Magmar|[from]Fire Spin',
      '|-damage|p1a: Magmar|183/333 frz',
      '|cant|p1a: Magmar|frz',
      '|turn|8',
      '|move|p2a: Jynx|Flamethrower|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|147/333 frz',
      '|-curestatus|p1a: Magmar|frz|[msg]',
      '|move|p1a: Magmar|Ice Beam|p2a: Jynx|[miss]',
      '|-miss|p1a: Magmar',
      '|turn|9',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar|[miss]',
      '|-miss|p2a: Jynx',
      '|move|p1a: Magmar|Substitute|p1a: Magmar',
      '|-start|p1a: Magmar|Substitute',
      '|-damage|p1a: Magmar|64/333',
      '|turn|10',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar',
      '|-end|p1a: Magmar|Substitute',
      '|move|p1a: Magmar|Substitute|p1a: Magmar',
      '|-fail|p1a: Magmar|move: Substitute|[weak]',
      '|turn|11',
    ]);
  });

  test('Paralyze effect', () => {
    const battle = startBattle([
      MISS, HIT,
      HIT, PAR_CAN, HIT,
      PAR_CANT,
      HIT, PAR_CAN, HIT,
      PAR_CAN,
      PAR_CAN, HIT,
    ], [
      {species: 'Arbok', evs, moves: ['Glare']},
      {species: 'Dugtrio', evs, moves: ['Earthquake', 'Substitute']},
    ], [
      {species: 'Magneton', evs, moves: ['Thunder Wave']},
      {species: 'Gengar', evs, moves: ['Toxic', 'Thunder Wave', 'Glare']},
    ]);

    // Glare can miss
    battle.makeChoices('move 1', 'move 1');
    // Electric-type Pokémon can be paralyzed
    battle.makeChoices('move 1', 'move 1');
    // Can be fully paralyzed
    battle.makeChoices('move 1', 'switch 2');
    // Glare ignores type immunity
    battle.makeChoices('move 1', 'move 1');
    // Thunder Wave does not ignore type immunity
    battle.makeChoices('switch 2', 'move 2');
    // Primary paralysis ignores Substitute
    battle.makeChoices('move 2', 'move 3');

    // Paralysis lowers speed
    expect(battle.p2.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(79);
    expect(battle.p2.pokemon[0].storedStats.spe).toBe(318);

    verify(battle, [
      '|move|p1a: Arbok|Glare|p2a: Magneton|[miss]',
      '|-miss|p1a: Arbok',
      '|move|p2a: Magneton|Thunder Wave|p1a: Arbok',
      '|-status|p1a: Arbok|par',
      '|turn|2',
      '|move|p2a: Magneton|Thunder Wave|p1a: Arbok',
      '|-fail|p1a: Arbok|par',
      '|move|p1a: Arbok|Glare|p2a: Magneton',
      '|-status|p2a: Magneton|par',
      '|turn|3',
      '|switch|p2a: Gengar|Gengar|323/323',
      '|cant|p1a: Arbok|par',
      '|turn|4',
      '|move|p2a: Gengar|Toxic|p1a: Arbok',
      '|-fail|p1a: Arbok',
      '|move|p1a: Arbok|Glare|p2a: Gengar',
      '|-status|p2a: Gengar|par',
      '|turn|5',
      '|switch|p1a: Dugtrio|Dugtrio|273/273',
      '|move|p2a: Gengar|Thunder Wave|p1a: Dugtrio',
      '|-immune|p1a: Dugtrio',
      '|turn|6',
      '|move|p1a: Dugtrio|Substitute|p1a: Dugtrio',
      '|-start|p1a: Dugtrio|Substitute',
      '|-damage|p1a: Dugtrio|205/273',
      '|move|p2a: Gengar|Glare|p1a: Dugtrio',
      '|-status|p1a: Dugtrio|par',
      '|turn|7',
    ]);
  });

  test('ParalyzeChance effect', () => {
    const hi_proc = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, hi_proc, HIT, NO_CRIT, MIN_DMG, hi_proc,
      PAR_CAN, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, hi_proc, PAR_CANT,
    ], [
      {species: 'Jolteon', evs, moves: ['Body Slam', 'Thundershock']},
      {species: 'Dugtrio', evs, moves: ['Earthquake']},
    ], [
      {species: 'Raticate', evs, moves: ['Body Slam', 'Thunderbolt', 'Substitute']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Cannot paralyze a Pokémon of the same type as the move
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 21);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 64);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Moves have different paralysis rates / Electric-type Pokémon can be paralyzed
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 110);
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 71);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Paralysis lowers speed / Substitute block paralysis chance
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 78);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Doesn't work if already statused / paralysis can prevent action
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 110);

    // Doesn't trigger if the opponent is immune to the move
    battle.makeChoices('switch 2', 'move 2');

    verify(battle, [
      '|move|p1a: Jolteon|Body Slam|p2a: Raticate',
      '|-damage|p2a: Raticate|249/313',
      '|move|p2a: Raticate|Thunderbolt|p1a: Jolteon',
      '|-resisted|p1a: Jolteon',
      '|-damage|p1a: Jolteon|312/333',
      '|turn|2',
      '|move|p1a: Jolteon|Thunder Shock|p2a: Raticate',
      '|-damage|p2a: Raticate|178/313',
      '|move|p2a: Raticate|Body Slam|p1a: Jolteon',
      '|-damage|p1a: Jolteon|202/333',
      '|-status|p1a: Jolteon|par',
      '|turn|3',
      '|move|p2a: Raticate|Substitute|p2a: Raticate',
      '|-start|p2a: Raticate|Substitute',
      '|-damage|p2a: Raticate|100/313',
      '|move|p1a: Jolteon|Thunder Shock|p2a: Raticate',
      '|-activate|p2a: Raticate|Substitute|[damage]',
      '|turn|4',
      '|move|p2a: Raticate|Body Slam|p1a: Jolteon',
      '|-damage|p1a: Jolteon|92/333 par',
      '|cant|p1a: Jolteon|par',
      '|turn|5',
      '|switch|p1a: Dugtrio|Dugtrio|273/273',
      '|move|p2a: Raticate|Thunderbolt|p1a: Dugtrio',
      '|-immune|p1a: Dugtrio',
      '|turn|6',
    ]);
  });

  test('Sleep effect', () => {
    const battle = startBattle([
      HIT, SLP(1), HIT, SLP(2), HIT, HIT, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Parasect', evs, moves: ['Spore', 'Cut']},
    ], [
      {species: 'Geodude', evs, moves: ['Tackle']},
      {species: 'Slowpoke', evs, moves: ['Water Gun']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    // Can wake up immediately but still lose their turn
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');

    // Can be put to sleep for multiple turns
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // Sleep Clause Mod prevents multiple Pokémon from being put to sleep
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].status).toBe('');

    // Can't sleep someone already sleeping, turns only decrement while in battle
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // Eventually wakes up
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 17);

    verify(battle, [
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-status|p2a: Geodude|slp|[from] move: Spore',
      '|-curestatus|p2a: Geodude|slp|[msg]',
      '|turn|2',
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-status|p2a: Geodude|slp|[from] move: Spore',
      '|cant|p2a: Geodude|slp',
      '|turn|3',
      '|switch|p2a: Slowpoke|Slowpoke|383/383',
      '|move|p1a: Parasect|Spore|p2a: Slowpoke',
      '|turn|4',
      '|switch|p2a: Geodude|Geodude|283/283 slp',
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-fail|p2a: Geodude|slp',
      '|turn|5',
      '|move|p1a: Parasect|Cut|p2a: Geodude',
      '|-resisted|p2a: Geodude',
      '|-damage|p2a: Geodude|266/283 slp',
      '|-curestatus|p2a: Geodude|slp|[msg]',
      '|turn|6',
    ]);
  });

  test('Confusion effect', () => {
    const battle = startBattle([HIT, HIT, HIT, CFZ(3), CFZ_CANT, HIT, CFZ_CAN, HIT, HIT], [
      {species: 'Haunter', evs, moves: ['Confuse Ray', 'Night Shade']},
    ], [
      {species: 'Gengar', evs, moves: ['Substitute', 'Agility']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // Confusion is blocked by Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 80);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    battle.makeChoices('move 2', 'move 1');

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();

    // Can't confuse a Pokémon that already has a confusion
    battle.makeChoices('move 1', 'move 2');
    // Confused Pokémon can hurt themselves in confusion (typeless damage)
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 37);

    // Pokémon can still successfully move despite being confused
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

    // Pokémon snap out of confusion
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Gengar|Substitute|p2a: Gengar',
      '|-start|p2a: Gengar|Substitute',
      '|-damage|p2a: Gengar|243/323',
      '|move|p1a: Haunter|Confuse Ray|p2a: Gengar',
      '|-fail|p2a: Gengar',
      '|turn|2',
      '|move|p2a: Gengar|Substitute|p2a: Gengar',
      '|-fail|p2a: Gengar|move: Substitute',
      '|move|p1a: Haunter|Night Shade|p2a: Gengar',
      '|-end|p2a: Gengar|Substitute',
      '|turn|3',
      '|move|p2a: Gengar|Agility|p2a: Gengar',
      '|-boost|p2a: Gengar|spe|2',
      '|move|p1a: Haunter|Confuse Ray|p2a: Gengar',
      '|-start|p2a: Gengar|confusion',
      '|turn|4',
      '|-activate|p2a: Gengar|confusion',
      '|-damage|p2a: Gengar|206/323|[from] confusion',
      '|move|p1a: Haunter|Confuse Ray|p2a: Gengar',
      '|turn|5',
      '|-activate|p2a: Gengar|confusion',
      '|move|p2a: Gengar|Agility|p2a: Gengar',
      '|-boost|p2a: Gengar|spe|2',
      '|move|p1a: Haunter|Night Shade|p2a: Gengar',
      '|-damage|p2a: Gengar|106/323',
      '|turn|6',
      '|-end|p2a: Gengar|confusion',
      '|move|p2a: Gengar|Agility|p2a: Gengar',
      '|-boost|p2a: Gengar|spe|2',
      '|move|p1a: Haunter|Night Shade|p2a: Gengar',
      '|-damage|p2a: Gengar|6/323',
      '|turn|7',
    ]);
  });

  test('ConfusionChance effect', () => {
    const sub_proc = {key: 'data/mods/gen1/moves.ts:874:50', value: ranged(25, 256) - 1};
    const no_proc = SECONDARY(sub_proc.value + 1);
    const battle = startBattle([
      HIT, NO_CRIT, MAX_DMG, sub_proc, CFZ(2), CFZ_CAN,
      HIT, NO_CRIT, MAX_DMG,
      HIT, NO_CRIT, MAX_DMG, no_proc,
    ], [
      {species: 'Venomoth', evs, moves: ['Psybeam', 'Splash']},
    ], [
      {species: 'Jolteon', evs, moves: ['Substitute', 'Agility']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // ConfusionChance works through substitute if it doesn't break
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();

    battle.makeChoices('move 2', 'move 2');

    // Can't confuse after breaking the substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|250/333',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-activate|p2a: Jolteon|Substitute|[damage]',
      '|-start|p2a: Jolteon|confusion',
      '|turn|2',
      '|-activate|p2a: Jolteon|confusion',
      '|move|p2a: Jolteon|Agility|p2a: Jolteon',
      '|-boost|p2a: Jolteon|spe|2',
      '|move|p1a: Venomoth|Splash|p1a: Venomoth',
      '|-nothing',
      '|turn|3',
      '|-end|p2a: Jolteon|confusion',
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-fail|p2a: Jolteon|move: Substitute',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-end|p2a: Jolteon|Substitute',
      '|turn|4',
      '|move|p2a: Jolteon|Agility|p2a: Jolteon',
      '|-boost|p2a: Jolteon|spe|2',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-damage|p2a: Jolteon|201/333',
      '|turn|5',
    ]);
  });

  test('FlinchChance effect', () => {
    const lo_proc = SECONDARY(ranged(26, 256) - 1);
    const hi_proc = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, hi_proc,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, hi_proc,
      HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, lo_proc,
      HIT, NO_CRIT, MIN_DMG, lo_proc,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, hi_proc,
      MISS, MISS,
    ], [
      {species: 'Raticate', evs, moves: ['Hyper Fang', 'Headbutt', 'Hyper Beam']},
    ], [
      {species: 'Marowak', evs, moves: ['Headbutt', 'Hyper Beam', 'Substitute']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Moves have different flinch rates
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 72 - 80));

    // Substitute blocks flinch, flinch doesn't prevent movement when slower
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 60);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 128);

    // Flinch prevents movement but counts as recharge turn
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 72);

    // Can prevent movement even without recharge
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 72);

    // (need to artificially recover HP to survive Raticate's Hyper Beam)
    p2hp = battle.p2.pokemon[0].hp = 323;
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 60);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 133);
    expect(choices(battle, 'p1')).toEqual(['move 1', 'move 2', 'move 3']);

    // Flinch should clear recharge
    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Raticate|Hyper Fang|p2a: Marowak',
      '|-damage|p2a: Marowak|251/323',
      '|move|p2a: Marowak|Substitute|p2a: Marowak',
      '|-start|p2a: Marowak|Substitute',
      '|-damage|p2a: Marowak|171/323',
      '|turn|2',
      '|move|p1a: Raticate|Headbutt|p2a: Marowak',
      '|-activate|p2a: Marowak|Substitute|[damage]',
      '|move|p2a: Marowak|Headbutt|p1a: Raticate',
      '|-damage|p1a: Raticate|253/313',
      '|turn|3',
      '|move|p1a: Raticate|Headbutt|p2a: Marowak',
      '|-end|p2a: Marowak|Substitute',
      '|move|p2a: Marowak|Hyper Beam|p1a: Raticate',
      '|-damage|p1a: Raticate|125/313',
      '|-mustrecharge|p2a: Marowak',
      '|turn|4',
      '|move|p1a: Raticate|Hyper Fang|p2a: Marowak',
      '|-damage|p2a: Marowak|99/323',
      '|cant|p2a: Marowak|flinch',
      '|turn|5',
      '|move|p1a: Raticate|Hyper Fang|p2a: Marowak',
      '|-damage|p2a: Marowak|27/323',
      '|cant|p2a: Marowak|flinch',
      '|turn|6',
      '|move|p1a: Raticate|Hyper Beam|p2a: Marowak',
      '|-damage|p2a: Marowak|190/323',
      '|-mustrecharge|p1a: Raticate',
      '|move|p2a: Marowak|Headbutt|p1a: Raticate',
      '|-damage|p1a: Raticate|65/313',
      '|turn|7',
      '|move|p1a: Raticate|Hyper Fang|p2a: Marowak|[miss]',
      '|-miss|p1a: Raticate',
      '|move|p2a: Marowak|Headbutt|p1a: Raticate|[miss]',
      '|-miss|p2a: Marowak',
      '|turn|8',
    ]);
  });

  test('StatDown effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, HIT,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT,
    ], [
      {species: 'Ekans', evs, moves: ['Screech', 'Strength']},
    ], [
      {species: 'Caterpie', evs, moves: ['String Shot', 'Tackle']},
      {species: 'Gastly', evs, moves: ['Night Shade']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 75);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.spe).toBe(-1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].boosts.def).toBe(-2);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 149);

    // Ghosts shouldn't be immune
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].boosts.def).toBe(-2);

    verify(battle, [
      '|move|p1a: Ekans|Strength|p2a: Caterpie',
      '|-damage|p2a: Caterpie|218/293',
      '|move|p2a: Caterpie|Tackle|p1a: Ekans',
      '|-damage|p1a: Ekans|251/273',
      '|turn|2',
      '|move|p1a: Ekans|Screech|p2a: Caterpie',
      '|-unboost|p2a: Caterpie|def|2',
      '|move|p2a: Caterpie|String Shot|p1a: Ekans',
      '|-unboost|p1a: Ekans|spe|1',
      '|turn|3',
      '|move|p2a: Caterpie|Tackle|p1a: Ekans',
      '|-damage|p1a: Ekans|229/273',
      '|move|p1a: Ekans|Strength|p2a: Caterpie',
      '|-damage|p2a: Caterpie|69/293',
      '|turn|4',
      '|switch|p2a: Gastly|Gastly|263/263',
      '|move|p1a: Ekans|Screech|p2a: Gastly',
      '|-unboost|p2a: Gastly|def|2',
      '|turn|5',
    ]);
  });

  test('StatDownChance effect', () => {
    const proc = SECONDARY(ranged(85, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, proc,
      HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, proc,
      HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, no_proc,
    ], [
      {species: 'Alakazam', evs, moves: ['Psychic']},
    ], [
      {species: 'Starmie', evs, moves: ['Bubble Beam']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 57);
    expect(battle.p1.pokemon[0].boosts.spe).toBe(-1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 60);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 57);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 60);
    expect(battle.p2.pokemon[0].boosts.spa).toBe(-1);
    expect(battle.p2.pokemon[0].boosts.spd).toBe(-1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 39);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

    verify(battle, [
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|263/323',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|256/313',
      '|-unboost|p1a: Alakazam|spe|1',
      '|turn|2',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|199/313',
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|203/323',
      '|-unboost|p2a: Starmie|spa|1',
      '|-unboost|p2a: Starmie|spd|1',
      '|turn|3',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|160/313',
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|112/323',
      '|turn|4',
    ]);
  });

  test('StatUp effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Scyther', evs, moves: ['Swords Dance', 'Cut']},
    ], [
      {species: 'Slowbro', evs, moves: ['Withdraw', 'Water Gun']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 54);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 37);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 54);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);

    verify(battle, [
      '|move|p1a: Scyther|Cut|p2a: Slowbro',
      '|-damage|p2a: Slowbro|356/393',
      '|move|p2a: Slowbro|Water Gun|p1a: Scyther',
      '|-damage|p1a: Scyther|289/343',
      '|turn|2',
      '|move|p1a: Scyther|Swords Dance|p1a: Scyther',
      '|-boost|p1a: Scyther|atk|2',
      '|move|p2a: Slowbro|Withdraw|p2a: Slowbro',
      '|-boost|p2a: Slowbro|def|1',
      '|turn|3',
      '|move|p1a: Scyther|Cut|p2a: Slowbro',
      '|-damage|p2a: Slowbro|307/393',
      '|move|p2a: Slowbro|Water Gun|p1a: Scyther',
      '|-damage|p1a: Scyther|235/343',
      '|turn|4',
    ]);
  });

  test('OHKO effect', () => {
    const battle = startBattle([MISS, HIT], [
      {species: 'Kingler', evs, moves: ['Guillotine']},
      {species: 'Tauros', moves: ['Horn Drill']},
    ], [
      {species: 'Dugtrio', evs, moves: ['Fissure']},
      {species: 'Gengar', evs, moves: ['Dig']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 2', '');

    // Type-immunity trumps OHKO-immunity
    battle.makeChoices('move 1', 'switch 2');

    // Invulnerability trumps immunity on Pokémon Showdown
    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Dugtrio|Fissure|p1a: Kingler|[miss]',
      '|-miss|p2a: Dugtrio',
      '|move|p1a: Kingler|Guillotine|p2a: Dugtrio',
      '|-immune|p2a: Dugtrio|[ohko]',
      '|turn|2',
      '|move|p2a: Dugtrio|Fissure|p1a: Kingler',
      '|-damage|p1a: Kingler|0 fnt',
      '|-ohko',
      '|faint|p1a: Kingler',
      '|switch|p1a: Tauros|Tauros|290/290',
      '|turn|3',
      '|switch|p2a: Gengar|Gengar|323/323',
      '|move|p1a: Tauros|Horn Drill|p2a: Gengar',
      '|-immune|p2a: Gengar',
      '|turn|4',
      '|move|p2a: Gengar|Dig||[still]',
      '|-prepare|p2a: Gengar|Dig',
      '|move|p1a: Tauros|Horn Drill|p2a: Gengar|[miss]',
      '|-miss|p1a: Tauros',
      '|turn|5',
    ]);
  });

  test('Charge effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, DISABLE_MOVE(2, 2), DISABLE_DURATION(2), HIT,
    ], [
      {species: 'Wartortle', evs, moves: ['Water Gun', 'Skull Bash']},
      {species: 'Ivysaur', evs, moves: ['Vine Whip']},
    ], [
      {species: 'Psyduck', evs, moves: ['Scratch', 'Water Gun', 'Disable']},
      {species: 'Horsea', evs, moves: ['Bubble']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[1].pp;

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Wartortle|Skull Bash||[still]',
      '|-prepare|p1a: Wartortle|Skull Bash',
      '|move|p2a: Psyduck|Scratch|p1a: Wartortle',
      '|-damage|p1a: Wartortle|298/321',
      '|turn|2',
      '|move|p1a: Wartortle|Skull Bash|p2a: Psyduck|[from]Skull Bash',
      '|-damage|p2a: Psyduck|220/303',
      '|move|p2a: Psyduck|Scratch|p1a: Wartortle',
      '|-damage|p1a: Wartortle|275/321',
      '|turn|3',
      '|move|p1a: Wartortle|Skull Bash||[still]',
      '|-prepare|p1a: Wartortle|Skull Bash',
      '|move|p2a: Psyduck|Disable|p1a: Wartortle',
      '|-start|p1a: Wartortle|Disable|Skull Bash',
      '|turn|4',
      '|cant|p1a: Wartortle|Disable|Skull Bash',
      '|move|p2a: Psyduck|Disable|p1a: Wartortle',
      '|-fail|p1a: Wartortle',
      '|turn|5',
    ]);
  });

  test('Fly/Dig effect', () => {
    // normal
    {
      const battle = startBattle([
        HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Pidgeot', evs, moves: ['Fly', 'Sand-Attack']},
        {species: 'Metapod', evs, moves: ['Harden']},
      ], [
        {species: 'Lickitung', evs, moves: ['Strength', 'Lick']},
        {species: 'Bellsprout', evs, moves: ['Vine Whip']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      let pp = battle.p1.pokemon[0].moveSlots[0].pp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(choices(battle, 'p1')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 79);
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 74);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      verify(battle, [
        '|move|p1a: Pidgeot|Fly||[still]',
        '|-prepare|p1a: Pidgeot|Fly',
        '|move|p2a: Lickitung|Strength|p1a: Pidgeot|[miss]',
        '|-miss|p2a: Lickitung',
        '|turn|2',
        '|move|p1a: Pidgeot|Fly|p2a: Lickitung|[from]Fly',
        '|-damage|p2a: Lickitung|304/383',
        '|move|p2a: Lickitung|Strength|p1a: Pidgeot',
        '|-damage|p1a: Pidgeot|295/369',
        '|turn|3',
      ]);
    }
    // fainting
    {
      const battle = startBattle([HIT, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Seadra', evs, moves: ['Toxic']},
        {species: 'Ninetales', evs, moves: ['Dig']},
      ], [
        {species: 'Shellder', evs, moves: ['Splash']},
        {species: 'Arcanine', evs, moves: ['Splash']},
      ]);

      battle.p2.pokemon[0].hp = 31;
      let p2hp = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(15);

      battle.makeChoices('switch 2', 'switch 2');

      battle.makeChoices('move 1', 'move 1');

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('', 'switch 2');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 141);

      verify(battle, [
        '|move|p1a: Seadra|Toxic|p2a: Shellder',
        '|-status|p2a: Shellder|tox',
        '|move|p2a: Shellder|Splash|p2a: Shellder',
        '|-nothing',
        '|-damage|p2a: Shellder|15/263 tox|[from] psn',
        '|turn|2',
        '|switch|p1a: Ninetales|Ninetales|349/349',
        '|switch|p2a: Arcanine|Arcanine|383/383',
        '|turn|3',
        '|move|p1a: Ninetales|Dig||[still]',
        '|-prepare|p1a: Ninetales|Dig',
        '|move|p2a: Arcanine|Splash|p2a: Arcanine',
        '|-nothing',
        '|turn|4',
        '|switch|p2a: Shellder|Shellder|15/263 tox',
        '|-status|p2a: Shellder|psn|[silent]',
        '|-damage|p2a: Shellder|0 fnt|[from] psn',
        '|faint|p2a: Shellder',
        '|switch|p2a: Arcanine|Arcanine|383/383',
        '|turn|5',
        '|move|p1a: Ninetales|Dig|p2a: Arcanine|[from]Dig',
        '|-supereffective|p2a: Arcanine',
        '|-damage|p2a: Arcanine|242/383',
        '|move|p2a: Arcanine|Splash|p2a: Arcanine',
        '|-nothing',
        '|turn|6',
      ]);
    }
  });

  test('SwitchAndTeleport effect', () => {
    const battle = startBattle([HIT, MISS], [
      {species: 'Abra', evs, moves: ['Teleport']},
    ], [
      {species: 'Pidgey', evs, moves: ['Whirlwind']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Abra|Teleport|p1a: Abra',
      '|move|p2a: Pidgey|Whirlwind|p1a: Abra',
      '|turn|2',
      '|move|p1a: Abra|Teleport|p1a: Abra',
      '|move|p2a: Pidgey|Whirlwind|p1a: Abra|[miss]',
      '|-miss|p2a: Pidgey',
      '|turn|3',
    ]);
  });

  test('Splash effect', () => {
    const battle = startBattle([],
      [{species: 'Gyarados', evs, moves: ['Splash']}],
      [{species: 'Magikarp', evs, moves: ['Splash']}]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Gyarados|Splash|p1a: Gyarados',
      '|-nothing',
      '|move|p2a: Magikarp|Splash|p2a: Magikarp',
      '|-nothing',
      '|turn|2',
    ]);
  });

  test('Binding effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      HIT, NO_CRIT, MAX_DMG, REWRAP,
      HIT,
      PAR_CAN, HIT, MAX_WRAP, PAR_CAN,
      PAR_CANT, PAR_CAN,
      HIT, MIN_WRAP,
    ], [
      {species: 'Dragonite', evs, moves: ['Wrap', 'Agility']},
      {species: 'Moltres', evs, moves: ['Fire Spin', 'Fire Blast']},
    ], [
      {species: 'Cloyster', evs, moves: ['Clamp', 'Surf']},
      {species: 'Tangela', evs, moves: ['Bind', 'Stun Spore']},
      {species: 'Gengar', evs, moves: ['Splash', 'Night Shade']},
    ]);

    let cloyster = battle.p2.pokemon[0].hp;
    let tangela = battle.p2.pokemon[1].hp;
    const gengar = battle.p2.pokemon[2].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);
    expect(battle.p2.pokemon[0].hp).toBe(cloyster -= 10);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);
    expect(battle.p2.pokemon[0].hp).toBe(tangela -= 15);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(tangela -= 15);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].status).toBe('par');

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'switch 3');
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');

    battle.makeChoices('switch 2', 'move 1');

    verify(battle, [
      '|move|p1a: Dragonite|Wrap|p2a: Cloyster',
      '|-damage|p2a: Cloyster|293/303',
      '|cant|p2a: Cloyster|partiallytrapped',
      '|turn|2',
      '|switch|p2a: Tangela|Tangela|333/333',
      '|move|p1a: Dragonite|Wrap|p2a: Tangela',
      '|-damage|p2a: Tangela|318/333',
      '|turn|3',
      '|move|p1a: Dragonite|Wrap|p2a: Tangela|[from]Wrap',
      '|-damage|p2a: Tangela|303/333',
      '|cant|p2a: Tangela|partiallytrapped',
      '|turn|4',
      '|move|p1a: Dragonite|Agility|p1a: Dragonite',
      '|-boost|p1a: Dragonite|spe|2',
      '|move|p2a: Tangela|Stun Spore|p1a: Dragonite',
      '|-status|p1a: Dragonite|par',
      '|turn|5',
      '|switch|p2a: Gengar|Gengar|323/323',
      '|move|p1a: Dragonite|Wrap|p2a: Gengar',
      '|-damage|p2a: Gengar|323/323',
      '|turn|6',
      '|cant|p2a: Gengar|partiallytrapped',
      '|move|p1a: Dragonite|Wrap|p2a: Gengar|[from]Wrap',
      '|-damage|p2a: Gengar|323/323',
      '|turn|7',
      '|cant|p2a: Gengar|partiallytrapped',
      '|cant|p1a: Dragonite|par',
      '|turn|8',
      '|move|p2a: Gengar|Splash|p2a: Gengar',
      '|-nothing',
      '|move|p1a: Dragonite|Wrap|p2a: Gengar',
      '|-damage|p2a: Gengar|323/323',
      '|turn|9',
      '|switch|p1a: Moltres|Moltres|383/383',
      '|cant|p2a: Gengar|partiallytrapped',
      '|turn|10',
    ]);
  });

  test('JumpKick effect', () => {
    const battle = startBattle([MISS, HIT, CRIT, MAX_DMG, MISS, MISS], [
      {species: 'Hitmonlee', evs, moves: ['Jump Kick', 'Substitute']},
    ], [
      {species: 'Hitmonlee', level: 99, evs, moves: ['High Jump Kick', 'Substitute']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 75);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(76);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 75);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(76);

    // Jump Kick causes crash damage to the opponent's sub if both Pokémon have one
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(75);

    // Jump Kick causes 1 HP crash damage unless only the user who crashed has a Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(75);

    verify(battle, [
      '|move|p1a: Hitmonlee|Substitute|p1a: Hitmonlee',
      '|-start|p1a: Hitmonlee|Substitute',
      '|-damage|p1a: Hitmonlee|228/303',
      '|move|p2a: Hitmonlee|Substitute|p2a: Hitmonlee',
      '|-start|p2a: Hitmonlee|Substitute',
      '|-damage|p2a: Hitmonlee|225/300',
      '|turn|2',
      '|move|p1a: Hitmonlee|Jump Kick|p2a: Hitmonlee|[miss]',
      '|-miss|p1a: Hitmonlee',
      '|-activate|p2a: Hitmonlee|Substitute|[damage]',
      '|move|p2a: Hitmonlee|High Jump Kick|p1a: Hitmonlee',
      '|-crit|p1a: Hitmonlee',
      '|-end|p1a: Hitmonlee|Substitute',
      '|turn|3',
      '|move|p1a: Hitmonlee|Jump Kick|p2a: Hitmonlee|[miss]',
      '|-miss|p1a: Hitmonlee',
      '|-damage|p1a: Hitmonlee|227/303',
      '|move|p2a: Hitmonlee|High Jump Kick|p1a: Hitmonlee|[miss]',
      '|-miss|p2a: Hitmonlee',
      '|turn|4',
    ]);
  });

  test('Recoil effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Slowpoke', evs, moves: ['Splash']},
      {species: 'Rhydon', evs, moves: ['Take Down', 'Splash']},
    ], [
      {species: 'Tauros', evs, moves: ['Double Edge', 'Substitute']},
    ]);

    battle.p1.pokemon[0].hp = 1;

    let p1hp = battle.p1.pokemon[1].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Recoil inflicts at least 1 HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);

    battle.makeChoices('switch 2', '');

    // Deals no damage if the move breaks the target's Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 88);

    // Inflicts 1/4 of damage dealt to user as recoil
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 48);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 12);

    verify(battle, [
      '|move|p2a: Tauros|Double-Edge|p1a: Slowpoke',
      '|-damage|p1a: Slowpoke|0 fnt',
      '|-damage|p2a: Tauros|352/353|[from] Recoil|[of] p1a: Slowpoke',
      '|faint|p1a: Slowpoke',
      '|switch|p1a: Rhydon|Rhydon|413/413',
      '|turn|2',
      '|move|p2a: Tauros|Substitute|p2a: Tauros',
      '|-start|p2a: Tauros|Substitute',
      '|-damage|p2a: Tauros|264/353',
      '|move|p1a: Rhydon|Take Down|p2a: Tauros',
      '|-end|p2a: Tauros|Substitute',
      '|turn|3',
      '|move|p2a: Tauros|Double-Edge|p1a: Rhydon',
      '|-resisted|p1a: Rhydon',
      '|-damage|p1a: Rhydon|365/413',
      '|-damage|p2a: Tauros|252/353|[from] Recoil|[of] p1a: Rhydon',
      '|move|p1a: Rhydon|Splash|p1a: Rhydon',
      '|-nothing',
      '|turn|4',
    ]);
  });

  test('Struggle effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Abra', evs, moves: ['Substitute', 'Splash']},
      {species: 'Golem', evs, moves: ['Harden']},
    ], [
      {species: 'Arcanine', evs, moves: ['Splash']},
    ]);

    battle.p1.pokemon[0].hp = 64;
    battle.p2.pokemon[0].moveSlots[0].pp = 1;

    const p1hp = battle.p1.pokemon[1].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Struggle only becomes an option if the user has no PP left
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(0);

    // Deals no recoil damage if the move breaks the target's Substitute
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(0);

    // Struggle recoil inflicts at least 1 HP
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);

    battle.makeChoices('switch 2', '');

    // Respects type effectiveness and inflicts 1/2 of damage dealt to user as recoil
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 16);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 8);

    verify(battle, [
      '|move|p2a: Arcanine|Splash|p2a: Arcanine',
      '|-nothing',
      '|move|p1a: Abra|Substitute|p1a: Abra',
      '|-start|p1a: Abra|Substitute',
      '|-damage|p1a: Abra|1/253',
      '|turn|2',
      '|move|p2a: Arcanine|Struggle|p1a: Abra',
      '|-end|p1a: Abra|Substitute',
      '|move|p1a: Abra|Splash|p1a: Abra',
      '|-nothing',
      '|turn|3',
      '|move|p2a: Arcanine|Struggle|p1a: Abra',
      '|-damage|p1a: Abra|0 fnt',
      '|-damage|p2a: Arcanine|382/383|[from] Recoil|[of] p1a: Abra',
      '|faint|p1a: Abra',
      '|switch|p1a: Golem|Golem|363/363',
      '|turn|4',
      '|move|p2a: Arcanine|Struggle|p1a: Golem',
      '|-resisted|p1a: Golem',
      '|-damage|p1a: Golem|347/363',
      '|-damage|p2a: Arcanine|374/383|[from] Recoil|[of] p1a: Golem',
      '|move|p1a: Golem|Harden|p1a: Golem',
      '|-boost|p1a: Golem|def|1',
      '|turn|5',
    ]);
  });

  test('Thrashing effect', () => {
    // normal
    {
      const battle = startBattle([
        THRASH(3), HIT, NO_CRIT, MIN_DMG, HIT, CFZ(5),
        CFZ_CAN, MISS, THRASH(3), MISS,
        CFZ_CAN, CFZ(5), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        CFZ_CAN, HIT, PAR_CANT,
        CFZ_CAN, HIT, PAR_CAN, THRASH(3), HIT, NO_CRIT, MAX_DMG,
      ], [
        {species: 'Nidoking', evs, moves: ['Thrash', 'Thunder Wave']},
        {species: 'Nidoqueen', evs, moves: ['Poison Sting']},
      ], [
        {species: 'Vileplume', evs, moves: ['Petal Dance', 'Confuse Ray']},
        {species: 'Victreebel', evs, moves: ['Razor Leaf']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      let pp = battle.p1.pokemon[0].moveSlots[0].pp;

      // Thrashing locks user in for 3-4 turns
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(choices(battle, 'p1')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      // Thrashing locks you in whether you hit or not
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(4);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(choices(battle, 'p1')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['move 1']);

      // Thrashing confuses you even if already confused
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 91);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(choices(battle, 'p2')).toEqual(['move 1']);

      // Thrashing doesn't confuse you if the user is prevented from moving
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].status).toBe('par');
      expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 108);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      verify(battle, [
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume',
        '|-damage|p2a: Vileplume|285/353',
        '|move|p2a: Vileplume|Confuse Ray|p1a: Nidoking',
        '|-start|p1a: Nidoking|confusion',
        '|turn|2',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume|[from]Thrash|[miss]',
        '|-miss|p1a: Nidoking',
        '|move|p2a: Vileplume|Petal Dance|p1a: Nidoking|[miss]',
        '|-miss|p2a: Vileplume',
        '|turn|3',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume|[from]Thrash',
        '|-start|p1a: Nidoking|confusion|[silent]',
        '|-damage|p2a: Vileplume|217/353',
        '|move|p2a: Vileplume|Petal Dance|p1a: Nidoking|[from]Petal Dance',
        '|-damage|p1a: Nidoking|274/365',
        '|turn|4',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thunder Wave|p2a: Vileplume',
        '|-status|p2a: Vileplume|par',
        '|cant|p2a: Vileplume|par',
        '|turn|5',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thunder Wave|p2a: Vileplume',
        '|-fail|p2a: Vileplume|par',
        '|move|p2a: Vileplume|Petal Dance|p1a: Nidoking',
        '|-damage|p1a: Nidoking|166/365',
        '|turn|6',
      ]);
    }
    // immune
    {
      const battle = startBattle([THRASH(3), HIT, NO_CRIT, MIN_DMG, CFZ(5)], [
        {species: 'Mankey', evs, moves: ['Thrash', 'Scratch']},
      ], [
        {species: 'Scyther', evs, moves: ['Cut']},
        {species: 'Goldeen', evs, moves: ['Water Gun']},
        {species: 'Gastly', evs, moves: ['Splash']},
      ]);

      let goldeen = battle.p2.pokemon[1].hp;
      const gastly = battle.p2.pokemon[2].hp;

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(goldeen -= 77);

      battle.makeChoices('move 1', 'switch 3');
      expect(battle.p2.pokemon[0].hp).toBe(gastly);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(gastly);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);

      verify(battle, [
        '|switch|p2a: Goldeen|Goldeen|293/293',
        '|move|p1a: Mankey|Thrash|p2a: Goldeen',
        '|-damage|p2a: Goldeen|216/293',
        '|turn|2',
        '|switch|p2a: Gastly|Gastly|263/263',
        '|move|p1a: Mankey|Thrash|p2a: Gastly|[from]Thrash',
        '|-immune|p2a: Gastly',
        '|turn|3',
        '|move|p2a: Gastly|Splash|p2a: Gastly',
        '|-nothing',
        '|move|p1a: Mankey|Thrash|p2a: Gastly|[from]Thrash',
        '|-start|p1a: Mankey|confusion|[silent]',
        '|-immune|p2a: Gastly',
        '|turn|4',
      ]);
    }
  });

  test('FixedDamage effect', () => {
    const battle = startBattle([HIT, HIT, HIT], [
      {species: 'Voltorb', evs, moves: ['Sonic Boom']},
    ], [
      {species: 'Dratini', evs, moves: ['Dragon Rage']},
      {species: 'Gastly', evs, moves: ['Night Shade']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp1 = battle.p2.pokemon[0].hp;
    const p2hp2 = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'switch 2');

    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 40);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp2 - 20);
    expect(battle.p2.pokemon[1].hp).toEqual(p2hp1 - 20);

    verify(battle, [
      '|move|p1a: Voltorb|Sonic Boom|p2a: Dratini',
      '|-damage|p2a: Dratini|265/285',
      '|move|p2a: Dratini|Dragon Rage|p1a: Voltorb',
      '|-damage|p1a: Voltorb|243/283',
      '|turn|2',
      '|switch|p2a: Gastly|Gastly|263/263',
      '|move|p1a: Voltorb|Sonic Boom|p2a: Gastly',
      '|-damage|p2a: Gastly|243/263',
      '|turn|3',
    ]);
  });

  test('LevelDamage effect', () => {
    const battle = startBattle([HIT, HIT], [
      {species: 'Gastly', evs, level: 22, moves: ['Night Shade']},
    ], [
      {species: 'Clefairy', evs, level: 16, moves: ['Seismic Toss']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 16);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 22);

    verify(battle, [
      '|move|p1a: Gastly|Night Shade|p2a: Clefairy',
      '|-damage|p2a: Clefairy|41/63',
      '|move|p2a: Clefairy|Seismic Toss|p1a: Gastly',
      '|-damage|p1a: Gastly|49/65',
      '|turn|2',
    ]);
  });

  test('Psywave effect', () => {
    const PSY_MAX = {key: 'data/mods/gen1/moves.ts:576:32', value: MAX};
    const PSY_MIN = {...PSY_MAX, value: MIN};
    const battle = startBattle([HIT, PSY_MAX, HIT, PSY_MIN], [
      {species: 'Gengar', evs, level: 59, moves: ['Psywave']},
    ], [
      {species: 'Clefable', evs, level: 42, moves: ['Psywave']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 87);

    verify(battle, [
      '|move|p1a: Gengar|Psywave|p2a: Clefable',
      '|-damage|p2a: Clefable|83/170',
      '|move|p2a: Clefable|Psywave|p1a: Gengar',
      '|turn|2',
    ]);
  });

  test('SuperFang effect', () => {
    const battle = startBattle([HIT, HIT, HIT], [
      {species: 'Raticate', evs, moves: ['Super Fang']},
      {species: 'Haunter', evs, moves: ['Dream Eater']},
    ], [
      {species: 'Rattata', evs, moves: ['Super Fang']},
    ]);

    battle.p1.pokemon[0].hp = 1;
    expect(battle.p2.pokemon[0].hp).toBe(263);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(132);

    battle.makeChoices('switch 2', '');
    expect(battle.p1.pokemon[0].hp).toBe(293);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(147);

    verify(battle, [
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
  });

  test('Disable effect', () => {
    const NO_FRZ = SECONDARY(ranged(26, 256));
    const battle = startBattle([
      HIT, DISABLE_MOVE(1), DISABLE_DURATION(1), HIT, NO_CRIT, MIN_DMG,
      HIT, DISABLE_MOVE(2), DISABLE_DURATION(5), HIT, NO_CRIT, MIN_DMG,
      HIT, DISABLE_MOVE(4), DISABLE_DURATION(5),
      HIT, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, NO_FRZ,
    ], [
      {species: 'Golduck', evs, moves: ['Disable', 'Water Gun']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Water Gun', 'Haze', 'Rest', 'Blizzard']},
      {species: 'Flareon', evs, moves: ['Flamethrower']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Disable can end immediately
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
    expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

    expect(choices(battle, 'p2'))
      .toEqual(['switch 2', 'move 1', 'move 2', 'move 3', 'move 4']);

    // Should skip over moves which are already out of PP
    battle.p2.pokemon[0].moveSlots[1].pp = 0;
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 4']);
    delete battle.p2.pokemon[0].volatiles['disable'];
    battle.p2.pokemon[0].moveSlots[1].pp = 1;

    // Can be disabled for many turns
    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].volatiles['disable'].time).toBe(4);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    // Disable fails if a move is already disabled
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
    expect(battle.p2.pokemon[0].volatiles['disable'].time).toBe(3);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    // Haze clears disable
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
    expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 3', 'move 4']);

    battle.makeChoices('move 2', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 53);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);

    verify(battle, [
      '|move|p1a: Golduck|Disable|p2a: Vaporeon',
      '|-start|p2a: Vaporeon|Disable|Water Gun',
      '|-end|p2a: Vaporeon|Disable',
      '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
      '|-resisted|p1a: Golduck',
      '|-damage|p1a: Golduck|336/363',
      '|turn|2',
      '|move|p1a: Golduck|Disable|p2a: Vaporeon',
      '|-start|p2a: Vaporeon|Disable|Rest',
      '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
      '|-resisted|p1a: Golduck',
      '|-damage|p1a: Golduck|309/363',
      '|turn|3',
      '|move|p1a: Golduck|Disable|p2a: Vaporeon',
      '|-start|p2a: Vaporeon|Disable|Blizzard',
      '|cant|p2a: Vaporeon|Disable|Blizzard',
      '|turn|4',
      '|move|p1a: Golduck|Disable|p2a: Vaporeon',
      '|-fail|p2a: Vaporeon',
      '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
      '|-resisted|p1a: Golduck',
      '|-damage|p1a: Golduck|282/363',
      '|turn|5',
      '|move|p1a: Golduck|Water Gun|p2a: Vaporeon',
      '|-resisted|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|446/463',
      '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
      '|-activate|p2a: Vaporeon|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p2a: Vaporeon|Disable|[silent]',
      '|turn|6',
      '|move|p1a: Golduck|Water Gun|p2a: Vaporeon',
      '|-resisted|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|429/463',
      '|move|p2a: Vaporeon|Blizzard|p1a: Golduck',
      '|-resisted|p1a: Golduck',
      '|-damage|p1a: Golduck|229/363',
      '|turn|7',
    ]);
  });

  test('Mist effect', () => {
    const proc = SECONDARY(ranged(85, 256) - 1);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, proc,
      HIT, NO_CRIT, MIN_DMG, HIT,
      HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, HIT,
    ], [
      {species: 'Articuno', evs, moves: ['Mist', 'Peck']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Aurora Beam', 'Growl', 'Haze']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Mist doesn't protect against secondary effects
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 42);
    expect(battle.p1.pokemon[0].volatiles['mist']).toBeDefined();
    expect(battle.p1.pokemon[0].boosts.atk).toBe(-1);

    // Mist does protect against primary stat lowering effects
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(-1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 31);

    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 31);

    // Haze ends Mist's effect
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].volatiles['mist']).toBeUndefined();
    expect(battle.p1.pokemon[0].boosts.atk).toBe(-1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    verify(battle, [
      '|move|p1a: Articuno|Mist|p1a: Articuno',
      '|-start|p1a: Articuno|Mist',
      '|move|p2a: Vaporeon|Aurora Beam|p1a: Articuno',
      '|-damage|p1a: Articuno|341/383',
      '|-unboost|p1a: Articuno|atk|1',
      '|turn|2',
      '|move|p1a: Articuno|Peck|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|432/463',
      '|move|p2a: Vaporeon|Growl|p1a: Articuno',
      '|-activate|p1a: Articuno|move: Mist',
      '|-fail|p1a: Articuno',
      '|turn|3',
      '|move|p1a: Articuno|Peck|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|401/463',
      '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
      '|-activate|p2a: Vaporeon|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p1a: Articuno|Mist|[silent]',
      '|turn|4',
      '|move|p1a: Articuno|Peck|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|353/463',
      '|move|p2a: Vaporeon|Growl|p1a: Articuno',
      '|-unboost|p1a: Articuno|atk|1',
      '|turn|5',
    ]);
  });

  test('HyperBeam effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Tauros', evs, moves: ['Hyper Beam', 'Body Slam']},
      {species: 'Exeggutor', evs, moves: ['Sleep Powder']},
    ], [
      {species: 'Jolteon', evs, moves: ['Substitute', 'Splash']},
      {species: 'Chansey', evs, moves: ['Splash', 'Soft-Boiled']},
    ]);

    battle.p2.pokemon[0].hp = 100;

    let jolteon = battle.p2.pokemon[0].hp;
    let chansey = battle.p2.pokemon[1].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    // Doesn't require a recharge if it knocks out a Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(jolteon -= 83);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    // Doesn't require a recharge if it knocks out opponent
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(0);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual([]);
    expect(choices(battle, 'p2')).toEqual(['switch 2']);

    battle.makeChoices('', 'switch 2');

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 442);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(chansey);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    verify(battle, [
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|17/333',
      '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
      '|-end|p2a: Jolteon|Substitute',
      '|turn|2',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
      '|-damage|p2a: Jolteon|0 fnt',
      '|faint|p2a: Jolteon',
      '|switch|p2a: Chansey|Chansey|703/703',
      '|turn|3',
      '|move|p1a: Tauros|Hyper Beam|p2a: Chansey',
      '|-damage|p2a: Chansey|261/703',
      '|-mustrecharge|p1a: Tauros',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|turn|4',
      '|cant|p1a: Tauros|recharge',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|turn|5',
    ]);
  });

  test('Counter effect', () => {
    const hit2 = {key: 'data/mods/gen1/scripts.ts:428:27', value: MIN};
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, NO_PAR, HIT,
      HIT, hit2, NO_CRIT, MIN_DMG, HIT,
      HIT, HIT,
      HIT, HIT,
      HIT, hit2, NO_CRIT, MIN_DMG, HIT,
      HIT,
      HIT,
      HIT, HIT,
      HIT,
      HIT, SLP(3),
    ], [
      {species: 'Voltorb', evs, moves: ['Thunderbolt', 'Double Slap', 'Counter', 'Sonic Boom']},
      {species: 'Gengar', evs, moves: ['Teleport', 'Seismic Toss']},
      {species: 'Snorlax', evs, moves: ['Lovely Kiss', 'Reflect']},
    ], [
      {species: 'Chansey', evs, moves: ['Counter']},
    ]);

    let voltorb = battle.p1.pokemon[0].hp;
    let gengar = battle.p1.pokemon[1].hp;
    let snorlax = battle.p1.pokemon[2].hp;
    let chansey = battle.p2.pokemon[0].hp;

    // Fails for moves which are not Normal / Fighting
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(voltorb);
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 69);

    // Deals back double damage to target, though only of the last hit of a multi-hit move
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(voltorb -= 34);
    expect(battle.p2.pokemon[0].hp).toBe(chansey = chansey - (2 * 17));

    // Cannot Counter an opponent's Counter
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(voltorb);
    expect(battle.p2.pokemon[0].hp).toBe(chansey);

    // Works on fixed damage moves including Sonic Boom
    battle.makeChoices('move 4', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(voltorb -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 20);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(voltorb -= 34);
    expect(battle.p2.pokemon[0].hp).toBe(chansey = chansey - (2 * 17));

    // Ignores type immunity and works across switches
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(gengar -= 68);

    // Certain zero damage moves like Teleport should not reset it
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(gengar);

    // Fixed damage works with Seismic Toss
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(gengar -= 200);
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 100);

    // Last damage gets updated to the damage Counter inflicted and doubles again
    battle.makeChoices('switch 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 400);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // When slept, Counter's negative priority gets preserved
    battle.makeChoices('move 2', 'move 1');

    verify(battle, [
      '|move|p1a: Voltorb|Thunderbolt|p2a: Chansey',
      '|-damage|p2a: Chansey|634/703',
      '|move|p2a: Chansey|Counter|p1a: Voltorb',
      '|-fail|p2a: Chansey',
      '|turn|2',
      '|move|p1a: Voltorb|Double Slap|p2a: Chansey',
      '|-damage|p2a: Chansey|617/703',
      '|-damage|p2a: Chansey|600/703',
      '|-hitcount|p2a: Chansey|2',
      '|move|p2a: Chansey|Counter|p1a: Voltorb',
      '|-damage|p1a: Voltorb|249/283',
      '|turn|3',
      '|move|p1a: Voltorb|Counter|p2a: Chansey',
      '|-fail|p1a: Voltorb',
      '|move|p2a: Chansey|Counter|p1a: Voltorb',
      '|-fail|p2a: Chansey',
      '|turn|4',
      '|move|p1a: Voltorb|Sonic Boom|p2a: Chansey',
      '|-damage|p2a: Chansey|580/703',
      '|move|p2a: Chansey|Counter|p1a: Voltorb',
      '|-damage|p1a: Voltorb|209/283',
      '|turn|5',
      '|move|p1a: Voltorb|Double Slap|p2a: Chansey',
      '|-damage|p2a: Chansey|563/703',
      '|-damage|p2a: Chansey|546/703',
      '|-hitcount|p2a: Chansey|2',
      '|move|p2a: Chansey|Counter|p1a: Voltorb',
      '|-damage|p1a: Voltorb|175/283',
      '|turn|6',
      '|switch|p1a: Gengar|Gengar|323/323',
      '|move|p2a: Chansey|Counter|p1a: Gengar',
      '|-damage|p1a: Gengar|255/323',
      '|turn|7',
      '|move|p1a: Gengar|Teleport|p1a: Gengar',
      '|move|p2a: Chansey|Counter|p1a: Gengar',
      '|-fail|p2a: Chansey',
      '|turn|8',
      '|move|p1a: Gengar|Seismic Toss|p2a: Chansey',
      '|-damage|p2a: Chansey|446/703',
      '|move|p2a: Chansey|Counter|p1a: Gengar',
      '|-damage|p1a: Gengar|55/323',
      '|turn|9',
      '|switch|p1a: Snorlax|Snorlax|523/523',
      '|move|p2a: Chansey|Counter|p1a: Snorlax',
      '|-damage|p1a: Snorlax|123/523',
      '|turn|10',
      '|move|p1a: Snorlax|Lovely Kiss|p2a: Chansey',
      '|-status|p2a: Chansey|slp|[from] move: Lovely Kiss',
      '|cant|p2a: Chansey|slp',
      '|turn|11',
      '|move|p1a: Snorlax|Reflect|p1a: Snorlax',
      '|-start|p1a: Snorlax|Reflect',
      '|cant|p2a: Chansey|slp',
      '|turn|12',
    ]);
  });

  test('Heal effect', () => {
    const battle = startBattle([HIT, CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG], [
      {species: 'Alakazam', evs, moves: ['Recover', 'Mega Kick']},
    ], [
      {species: 'Chansey', evs, moves: ['Soft-Boiled', 'Mega Punch']},
    ]);

    battle.p2.pokemon[0].hp = 448;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Fails at full health or at specific fractions
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 51);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 362);

    // Heals 1/2 of maximum HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 51);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 351);

    verify(battle, [
      '|move|p1a: Alakazam|Recover|p1a: Alakazam',
      '|-fail|p1a: Alakazam',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-fail|p2a: Chansey',
      '|turn|2',
      '|move|p1a: Alakazam|Mega Kick|p2a: Chansey',
      '|-crit|p2a: Chansey',
      '|-damage|p2a: Chansey|86/703',
      '|move|p2a: Chansey|Mega Punch|p1a: Alakazam',
      '|-damage|p1a: Alakazam|262/313',
      '|turn|3',
      '|move|p1a: Alakazam|Recover|p1a: Alakazam',
      '|-heal|p1a: Alakazam|313/313',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-heal|p2a: Chansey|437/703',
      '|turn|4',
    ]);
  });

  test('Rest effect', () => {
    const battle = startBattle([
      HIT, HIT, NO_CRIT, MIN_DMG, PAR_CAN, SLP(5),
      HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Porygon', evs, moves: ['Thunder Wave', 'Tackle', 'Rest']},
      {species: 'Dragonair', evs, moves: ['Slam']},
    ], [
      {species: 'Chansey', evs, moves: ['Rest', 'Splash']},
      {species: 'Jynx', evs, moves: ['Hypnosis']},
    ]);

    battle.p2.pokemon[0].hp = 192;

    let p2hp = battle.p2.pokemon[0].hp;

    // Fails at specific fractions
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(49);
    expect(battle.p2.pokemon[0].storedStats.spe).toBe(198);

    // Puts user to sleep to fully heal HP and removes status
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 77 + 588));
    expect(battle.p2.pokemon[0].status).toBe('slp');

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 77);

    // Fails at full HP / Last two turns but stat penalty still remains after waking
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(49);
    expect(battle.p2.pokemon[0].storedStats.spe).toBe(198);

    verify(battle, [
      '|move|p2a: Chansey|Rest|p2a: Chansey',
      '|-fail|p2a: Chansey',
      '|move|p1a: Porygon|Thunder Wave|p2a: Chansey',
      '|-status|p2a: Chansey|par',
      '|turn|2',
      '|move|p1a: Porygon|Tackle|p2a: Chansey',
      '|-damage|p2a: Chansey|115/703 par',
      '|move|p2a: Chansey|Rest|p2a: Chansey',
      '|-status|p2a: Chansey|slp|[from] move: Rest',
      '|-heal|p2a: Chansey|703/703 slp|[silent]',
      '|turn|3',
      '|move|p1a: Porygon|Tackle|p2a: Chansey',
      '|-damage|p2a: Chansey|626/703 slp',
      '|cant|p2a: Chansey|slp',
      '|turn|4',
      '|move|p1a: Porygon|Rest|p1a: Porygon',
      '|-fail|p1a: Porygon',
      '|-curestatus|p2a: Chansey|slp|[msg]',
      '|turn|5',
    ]);
  });

  test('DrainHP effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Slowpoke', evs, moves: ['Splash']},
      {species: 'Butterfree', evs, moves: ['Mega Drain']},
    ], [
      {species: 'Parasect', evs, moves: ['Leech Life']},
    ]);

    battle.p1.pokemon[0].hp = 1;
    battle.p2.pokemon[0].hp = 300;

    let p1hp = battle.p1.pokemon[1].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Heals at least 1 HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 1);

    battle.makeChoices('switch 2', '');

    // Heals 1/2 of the damage dealt unless the user is at full health
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 16);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 6 + 8);

    verify(battle, [
      '|move|p2a: Parasect|Leech Life|p1a: Slowpoke',
      '|-supereffective|p1a: Slowpoke',
      '|-damage|p1a: Slowpoke|0 fnt',
      '|-heal|p2a: Parasect|301/323|[from] drain|[of] p1a: Slowpoke',
      '|faint|p1a: Slowpoke',
      '|switch|p1a: Butterfree|Butterfree|323/323',
      '|turn|2',
      '|move|p1a: Butterfree|Mega Drain|p2a: Parasect',
      '|-resisted|p2a: Parasect',
      '|-damage|p2a: Parasect|295/323',
      '|move|p2a: Parasect|Leech Life|p1a: Butterfree',
      '|-resisted|p1a: Butterfree',
      '|-damage|p1a: Butterfree|307/323',
      '|-heal|p2a: Parasect|303/323|[from] drain|[of] p1a: Butterfree',
      '|turn|3',
    ]);
  });

  test('DreamEater effect', () => {
    {
      const battle = startBattle([
        HIT, SLP(5), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, SLP(5),
      ], [
        {species: 'Hypno', evs, moves: ['Dream Eater', 'Hypnosis', 'Splash']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash']},
        {species: 'Gengar', evs, moves: ['Substitute', 'Rest']},
      ]);

      battle.p1.pokemon[0].hp = 100;
      battle.p2.pokemon[0].hp = 182;

      let hypno = battle.p1.pokemon[0].hp;
      let gengar = battle.p2.pokemon[1].hp;

      // Fails unless the target is sleeping
      battle.makeChoices('move 1', 'move 1');

      battle.makeChoices('move 2', 'move 1');

      // Heals 1/2 of the damage dealt
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(hypno += 90);
      expect(battle.p2.pokemon[0].hp).toBe(1);

      // Heals at least 1 HP
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(hypno += 1);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('', 'switch 2');

      battle.makeChoices('move 3', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(gengar -= 80);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(81);

      // Substitute blocks Dream Eater on Pokémon Showdown
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(gengar += 80);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(81);

      verify(battle, [
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-immune|p2a: Wigglytuff',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|turn|2',
        '|move|p1a: Hypno|Hypnosis|p2a: Wigglytuff',
        '|-status|p2a: Wigglytuff|slp|[from] move: Hypnosis',
        '|cant|p2a: Wigglytuff|slp',
        '|turn|3',
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-damage|p2a: Wigglytuff|1/483 slp',
        '|-heal|p1a: Hypno|190/373|[from] drain|[of] p2a: Wigglytuff',
        '|cant|p2a: Wigglytuff|slp',
        '|turn|4',
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-damage|p2a: Wigglytuff|0 fnt',
        '|-heal|p1a: Hypno|191/373|[from] drain|[of] p2a: Wigglytuff',
        '|faint|p2a: Wigglytuff',
        '|switch|p2a: Gengar|Gengar|323/323',
        '|turn|5',
        '|move|p2a: Gengar|Substitute|p2a: Gengar',
        '|-start|p2a: Gengar|Substitute',
        '|-damage|p2a: Gengar|243/323',
        '|move|p1a: Hypno|Splash|p1a: Hypno',
        '|-nothing',
        '|turn|6',
        '|move|p2a: Gengar|Rest|p2a: Gengar',
        '|-status|p2a: Gengar|slp|[from] move: Rest',
        '|-heal|p2a: Gengar|323/323 slp|[silent]',
        '|move|p1a: Hypno|Dream Eater|p2a: Gengar',
        '|-immune|p2a: Gengar',
        '|turn|7',
      ]);
    }
    // Invulnerable
    {
      const battle = startBattle([], [
        {species: 'Drowzee', evs, moves: ['Dream Eater']},
      ], [
        {species: 'Dugtrio', evs, moves: ['Dig']},
      ]);

      // Missing due to Invulnerability takes precedence on Pokémon Showdown
      battle.makeChoices('move 1', 'move 1');

      verify(battle, [
        '|move|p2a: Dugtrio|Dig||[still]',
        '|-prepare|p2a: Dugtrio|Dig',
        '|move|p1a: Drowzee|Dream Eater|p2a: Dugtrio|[miss]',
        '|-miss|p1a: Drowzee',
        '|turn|2',
      ]);
    }
  });

  test('LeechSeed effect', () => {
    const battle = startBattle([MISS, HIT, HIT, HIT, HIT], [
      {species: 'Venusaur', evs, moves: ['Leech Seed']},
      {species: 'Exeggutor', evs, moves: ['Leech Seed', 'Splash']},
    ], [
      {species: 'Gengar', evs, moves: ['Leech Seed', 'Substitute', 'Night Shade']},
      {species: 'Slowbro', evs, moves: ['Splash']},
    ]);

    battle.p2.pokemon[1].hp = 1;

    let exeggutor = battle.p1.pokemon[1].hp;
    let gengar = battle.p2.pokemon[0].hp;
    const slowbro = battle.p2.pokemon[1].hp;

    // Leed Seed can miss / Grass-type Pokémon are immune
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    // Leech Seed ignores Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(gengar -= 80);

    // Leech Seed does not |-heal| when at full health
    battle.makeChoices('switch 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(exeggutor);
    expect(battle.p2.pokemon[0].hp).toBe(gengar -= 20);

    // Leech Seed fails if already seeded / heals back damage
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(exeggutor -= 100 - 20);
    expect(battle.p2.pokemon[0].hp).toBe(gengar -= 20);

    // Switching breaks Leech Seed
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].hp).toBe(exeggutor);
    expect(battle.p2.pokemon[0].hp).toBe(slowbro);

    // Leech Seed's uncapped damage is added back
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(exeggutor += 24);
    expect(battle.p2.pokemon[0].hp).toBe(slowbro - 1);

    verify(battle, [
      '|move|p2a: Gengar|Leech Seed|p1a: Venusaur',
      '|-immune|p1a: Venusaur',
      '|move|p1a: Venusaur|Leech Seed|p2a: Gengar|[miss]',
      '|-miss|p1a: Venusaur',
      '|turn|2',
      '|move|p2a: Gengar|Substitute|p2a: Gengar',
      '|-start|p2a: Gengar|Substitute',
      '|-damage|p2a: Gengar|243/323',
      '|move|p1a: Venusaur|Leech Seed|p2a: Gengar',
      '|-start|p2a: Gengar|move: Leech Seed',
      '|turn|3',
      '|switch|p1a: Exeggutor|Exeggutor|393/393',
      '|move|p2a: Gengar|Substitute|p2a: Gengar',
      '|-fail|p2a: Gengar|move: Substitute',
      '|-damage|p2a: Gengar|223/323|[from] Leech Seed|[of] p1a: Exeggutor',
      '|turn|4',
      '|move|p2a: Gengar|Night Shade|p1a: Exeggutor',
      '|-damage|p1a: Exeggutor|293/393',
      '|-damage|p2a: Gengar|203/323|[from] Leech Seed|[of] p1a: Exeggutor',
      '|-heal|p1a: Exeggutor|313/393|[silent]',
      '|move|p1a: Exeggutor|Leech Seed|p2a: Gengar',
      '|turn|5',
      '|switch|p2a: Slowbro|Slowbro|1/393',
      '|move|p1a: Exeggutor|Leech Seed|p2a: Slowbro',
      '|-start|p2a: Slowbro|move: Leech Seed',
      '|turn|6',
      '|move|p1a: Exeggutor|Splash|p1a: Exeggutor',
      '|-nothing',
      '|move|p2a: Slowbro|Splash|p2a: Slowbro',
      '|-nothing',
      '|-damage|p2a: Slowbro|0 fnt|[from] Leech Seed|[of] p1a: Exeggutor',
      '|-heal|p1a: Exeggutor|337/393|[silent]',
      '|faint|p2a: Slowbro',
    ]);
  });

  test('PayDay effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG, HIT, CRIT, MAX_DMG,
    ], [
      {species: 'Meowth', evs, moves: ['Pay Day']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Splash']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 43 - 95);

    // Pay Day should still scatter coins even if it hits a Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeDefined();

    // Pay Day should not scatter coins if it breaks the Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|340/383',
      '|-fieldactivate|move: Pay Day',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|245/383',
      '|turn|2',
      '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|turn|3',
      '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
      '|-crit|p2a: Slowpoke',
      '|-end|p2a: Slowpoke|Substitute',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|turn|4',
    ]);
  });

  test('Rage effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, MISS,
      HIT, NO_CRIT, MIN_DMG, HIT, DISABLE_MOVE(1, 2), DISABLE_DURATION(5),
      MISS, HIT, NO_CRIT, MAX_DMG,
    ], [
      {species: 'Charmeleon', evs, moves: ['Rage', 'Flamethrower']},
      {species: 'Doduo', evs, moves: ['Drill Peck']},
    ], [
      {species: 'Grimer', evs, moves: ['Pound', 'Disable', 'Self-Destruct']},
      {species: 'Tentacruel', evs, moves: ['Surf']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(3);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(4);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    battle.makeChoices('', 'switch 2');

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Charmeleon|Rage|p2a: Grimer',
      '|-damage|p2a: Grimer|346/363',
      '|move|p2a: Grimer|Pound|p1a: Charmeleon',
      '|-damage|p1a: Charmeleon|284/319',
      '|-boost|p1a: Charmeleon|atk|1|[from] Rage',
      '|turn|2',
      '|move|p1a: Charmeleon|Rage|p2a: Grimer|[from]Rage',
      '|-damage|p2a: Grimer|321/363',
      '|move|p2a: Grimer|Disable|p1a: Charmeleon|[miss]',
      '|-miss|p2a: Grimer',
      '|-boost|p1a: Charmeleon|atk|1|[from] Rage',
      '|turn|3',
      '|move|p1a: Charmeleon|Rage|p2a: Grimer|[from]Rage',
      '|-damage|p2a: Grimer|287/363',
      '|move|p2a: Grimer|Disable|p1a: Charmeleon',
      '|-start|p1a: Charmeleon|Disable|Rage',
      '|-boost|p1a: Charmeleon|atk|1|[from] Rage',
      '|turn|4',
      '|cant|p1a: Charmeleon|Disable|Rage',
      '|move|p2a: Grimer|Self-Destruct|p1a: Charmeleon|[miss]',
      '|-miss|p2a: Grimer',
      '|-boost|p1a: Charmeleon|atk|1|[from] Rage',
      '|faint|p2a: Grimer',
      '|switch|p2a: Tentacruel|Tentacruel|363/363',
      '|turn|5',
      '|move|p2a: Tentacruel|Surf|p1a: Charmeleon',
      '|-supereffective|p1a: Charmeleon',
      '|-damage|p1a: Charmeleon|0 fnt',
      '|faint|p1a: Charmeleon',
    ]);
  });

  test('Mimic effect', () => {
    const battle = startBattle([HIT, MIMIC(3, 3)], [
      {species: 'Mr. Mime', evs, moves: ['Mimic']},
      {species: 'Abra', evs, moves: ['Splash']},
    ], [
      {species: 'Jigglypuff', evs, moves: ['Blizzard', 'Thunderbolt', 'Splash']},
    ]);

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Splash');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Splash');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('switch 2', 'move 3');
    battle.makeChoices('switch 2', 'move 3');

    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Mr. Mime|Mimic|p2a: Jigglypuff',
      '|-start|p1a: Mr. Mime|Mimic|Splash',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|turn|2',
      '|move|p1a: Mr. Mime|Splash|p1a: Mr. Mime',
      '|-nothing',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|turn|3',
      '|switch|p1a: Abra|Abra|253/253',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|turn|4',
      '|switch|p1a: Mr. Mime|Mr. Mime|283/283',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|turn|5',
    ]);
  });

  test('LightScreen effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MIN_DMG,
    ], [
      {species: 'Chansey', evs, moves: ['Light Screen', 'Splash']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Water Gun', 'Haze']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    // Water Gun does normal damage before Light Screen
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['lightscreen']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 45);

    // Water Gun's damage is reduced after Light Screen
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 23);

    // Critical hits ignore Light Screen
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 87);

    // Haze removes Light Screen
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].volatiles['lightscreen']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-damage|p1a: Chansey|658/703',
      '|move|p1a: Chansey|Light Screen|p1a: Chansey',
      '|-start|p1a: Chansey|Light Screen',
      '|turn|2',
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-damage|p1a: Chansey|635/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|3',
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|548/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|4',
      '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
      '|-activate|p2a: Vaporeon|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p1a: Chansey|Light Screen|[silent]',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|5',
    ]);
  });

  test('Reflect effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MIN_DMG,
    ], [
      {species: 'Chansey', evs, moves: ['Reflect', 'Splash']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Tackle', 'Haze']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    // Tackle does normal damage before Reflect
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['reflect']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 54);

    // Tackle's damage is reduced after Reflect
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 28);

    // Critical hits ignore Reflect
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 104);

    // Haze removes Reflect
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].volatiles['reflect']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-damage|p1a: Chansey|649/703',
      '|move|p1a: Chansey|Reflect|p1a: Chansey',
      '|-start|p1a: Chansey|Reflect',
      '|turn|2',
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-damage|p1a: Chansey|621/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|3',
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|517/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|4',
      '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
      '|-activate|p2a: Vaporeon|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p1a: Chansey|Reflect|[silent]',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|turn|5',
    ]);
  });

  test('Haze effect', () => {
    const proc = SECONDARY(MIN);
    const battle = startBattle([
      HIT, HIT,
      HIT, PAR_CAN, HIT, CFZ(5),
      CFZ_CAN, PAR_CAN, METRONOME('Haze'),
      PAR_CAN, METRONOME('Ember'), HIT, NO_CRIT, MIN_DMG, proc,
      PAR_CAN,
    ], [
      {species: 'Golbat', evs, moves: ['Toxic', 'Agility', 'Confuse Ray', 'Metronome']},
    ], [
      {species: 'Exeggutor', evs, moves: ['Leech Seed', 'Stun Spore', 'Double Team', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeDefined();
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(278);
    expect(battle.p2.pokemon[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 24);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p1.pokemon[0].boosts.spe).toBe(2);
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(139);
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 48 + 22));

    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(1);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(3);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 72 + 22));

    battle.makeChoices('move 4', 'move 4');
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeUndefined();
    expect(battle.p1.pokemon[0].boosts.spe).toBe(0);
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(278);
    expect(battle.p2.pokemon[0].status).toBe('');
    // expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(4);
    expect(battle.p2.pokemon[0].volatiles['residualdmg']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 96);

    battle.makeChoices('move 4', 'move 4');
    expect(battle.p2.pokemon[0].volatiles['residualdmg']).toBeUndefined();
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 42 - 24));

    battle.makeChoices('move 2', 'move 4');
    expect(battle.p1.pokemon[0].boosts.spe).toBe(2);
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(556);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 24);

    verify(battle, [
      '|move|p1a: Golbat|Toxic|p2a: Exeggutor',
      '|-status|p2a: Exeggutor|tox',
      '|move|p2a: Exeggutor|Leech Seed|p1a: Golbat',
      '|-start|p1a: Golbat|move: Leech Seed',
      '|-damage|p2a: Exeggutor|369/393 tox|[from] psn',
      '|turn|2',
      '|move|p1a: Golbat|Agility|p1a: Golbat',
      '|-boost|p1a: Golbat|spe|2',
      '|-damage|p1a: Golbat|331/353|[from] Leech Seed|[of] p2a: Exeggutor',
      '|-heal|p2a: Exeggutor|391/393 tox|[silent]',
      '|move|p2a: Exeggutor|Stun Spore|p1a: Golbat',
      '|-status|p1a: Golbat|par',
      '|-damage|p2a: Exeggutor|343/393 tox|[from] psn',
      '|turn|3',
      '|move|p2a: Exeggutor|Double Team|p2a: Exeggutor',
      '|-boost|p2a: Exeggutor|evasion|1',
      '|-damage|p2a: Exeggutor|271/393 tox|[from] psn',
      '|move|p1a: Golbat|Confuse Ray|p2a: Exeggutor',
      '|-start|p2a: Exeggutor|confusion',
      '|-damage|p1a: Golbat|309/353 par|[from] Leech Seed|[of] p2a: Exeggutor',
      '|-heal|p2a: Exeggutor|293/393 tox|[silent]',
      '|turn|4',
      '|-activate|p2a: Exeggutor|confusion',
      '|move|p2a: Exeggutor|Splash|p2a: Exeggutor',
      '|-nothing',
      '|-damage|p2a: Exeggutor|197/393 tox|[from] psn',
      '|move|p1a: Golbat|Metronome|p1a: Golbat',
      '|move|p1a: Golbat|Haze|p1a: Golbat|[from]Metronome',
      '|-activate|p1a: Golbat|move: Haze',
      '|-clearallboost|[silent]',
      '|-end|p1a: Golbat|move: Leech Seed|[silent]',
      '|-curestatus|p2a: Exeggutor|tox|[silent]',
      '|-end|p2a: Exeggutor|confusion|[silent]',
      '|-end|p2a: Exeggutor|Toxic counter|[silent]',
      '|turn|5',
      '|move|p1a: Golbat|Metronome|p1a: Golbat',
      '|move|p1a: Golbat|Ember|p2a: Exeggutor|[from]Metronome',
      '|-supereffective|p2a: Exeggutor',
      '|-damage|p2a: Exeggutor|155/393',
      '|-status|p2a: Exeggutor|brn',
      '|move|p2a: Exeggutor|Splash|p2a: Exeggutor',
      '|-nothing',
      '|-damage|p2a: Exeggutor|131/393 brn|[from] brn',
      '|turn|6',
      '|move|p1a: Golbat|Agility|p1a: Golbat',
      '|-boost|p1a: Golbat|spe|2',
      '|move|p2a: Exeggutor|Splash|p2a: Exeggutor',
      '|-nothing',
      '|-damage|p2a: Exeggutor|107/393 brn|[from] brn',
      '|turn|7',
    ]);
  });

  test('Bide effect', () => {
    {
      const battle = startBattle([
        BIDE(3), HIT, HIT, HIT, NO_CRIT, MIN_DMG, BIDE(3), HIT, HIT, CFZ(3), CFZ_CAN,
      ], [
        {species: 'Chansey', evs, moves: ['Bide', 'Splash']},
        {species: 'Onix', evs, moves: ['Bide']},
      ], [
        {species: 'Magnemite', evs, moves: ['Sonic Boom']},
        {species: 'Dugtrio', evs, moves: ['Dig']},
        {species: 'Haunter', evs, moves: ['Night Shade', 'Confuse Ray']},
      ]);

      let chansey = battle.p1.pokemon[0].hp;
      let dugtrio = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);
      expect(battle.p2.pokemon[0].hp).toBe(dugtrio -= 120);

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 256);

      battle.makeChoices('move 1', 'switch 3');
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 100);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(14);

      verify(battle, [
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|683/703',
        '|turn|2',
        '|-activate|p1a: Chansey|Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|663/703',
        '|turn|3',
        '|switch|p2a: Dugtrio|Dugtrio|273/273',
        '|-activate|p1a: Chansey|Bide',
        '|turn|4',
        '|move|p2a: Dugtrio|Dig||[still]',
        '|-prepare|p2a: Dugtrio|Dig',
        '|-end|p1a: Chansey|Bide',
        '|-damage|p2a: Dugtrio|153/273',
        '|turn|5',
        '|move|p2a: Dugtrio|Dig|p1a: Chansey|[from]Dig',
        '|-damage|p1a: Chansey|407/703',
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|Bide',
        '|turn|6',
        '|switch|p2a: Haunter|Haunter|293/293',
        '|-activate|p1a: Chansey|Bide',
        '|turn|7',
        '|move|p2a: Haunter|Night Shade|p1a: Chansey',
        '|-damage|p1a: Chansey|307/703',
        '|-activate|p1a: Chansey|Bide',
        '|turn|8',
        '|move|p2a: Haunter|Confuse Ray|p1a: Chansey',
        '|-start|p1a: Chansey|confusion',
        '|-activate|p1a: Chansey|confusion',
        '|-end|p1a: Chansey|Bide',
        '|-damage|p2a: Haunter|0 fnt',
        '|faint|p2a: Haunter',
      ]);
    }
    // failure
    {
      const battle = startBattle([HIT, BIDE(2)], [
        {species: 'Wartortle', evs, moves: ['Seismic Toss', 'Splash']},
      ], [
        {species: 'Pinsir', level: 50, evs, moves: ['Bide']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 100);

      battle.makeChoices('move 2', 'move 1');

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);

      verify(battle, [
        '|move|p1a: Wartortle|Seismic Toss|p2a: Pinsir',
        '|-damage|p2a: Pinsir|71/171',
        '|move|p2a: Pinsir|Bide|p2a: Pinsir',
        '|-start|p2a: Pinsir|Bide',
        '|turn|2',
        '|move|p1a: Wartortle|Splash|p1a: Wartortle',
        '|-nothing',
        '|-activate|p2a: Pinsir|Bide',
        '|turn|3',
        '|move|p1a: Wartortle|Splash|p1a: Wartortle',
        '|-nothing',
        '|-end|p2a: Pinsir|Bide',
        '|-fail|p2a: Pinsir',
        '|turn|4',
      ]);
    }
  });

  test('Metronome effect', () => {
    const battle = startBattle([
      METRONOME('Wrap'), HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      METRONOME('Tackle'), HIT,
      METRONOME('Petal Dance'), THRASH(3), HIT, NO_CRIT, MIN_DMG,
      MISS, CFZ(2), MISS,
      CFZ_CAN, METRONOME('Mimic'), HIT, MIMIC(2, 2), METRONOME('Disable'),
      HIT, DISABLE_MOVE(2, 3), DISABLE_DURATION(3),
      METRONOME('Rage'), HIT, NO_CRIT, MIN_DMG,
      METRONOME('Quick Attack'), HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Clefable', evs, moves: ['Metronome', 'Splash']},
    ], [
      {species: 'Primeape', evs, moves: ['Metronome', 'Mimic', 'Fury Swipes']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Pokémon Showdown partial trapping lock doesn't work with Metronome...
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 14);
    // expect(choices(battle, 'p2')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 14);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 41);
    expect(choices(battle, 'p2')).toEqual(['move 1']);

    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 2', 'move 1');

    // Metronome -> Mimic only works on Pokémon Showdown if Mimic
    // is in the moveset and replaces *that* slot instead of Metronome
    battle.makeChoices('move 1', 'move 1');
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 3']);

    // Quick Attack via Metronome only executes at normal priority
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);
    expect(choices(battle, 'p2')).toEqual(['move 1']);

    verify(battle, [
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Wrap|p1a: Clefable|[from]Metronome',
      '|-damage|p1a: Clefable|379/393',
      '|cant|p1a: Clefable|partiallytrapped',
      '|turn|2',
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Tackle|p1a: Clefable|[from]Metronome',
      '|-damage|p1a: Clefable|365/393',
      '|cant|p1a: Clefable|partiallytrapped',
      '|turn|3',
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Petal Dance|p1a: Clefable|[from]Metronome',
      '|-damage|p1a: Clefable|324/393',
      '|move|p1a: Clefable|Splash|p1a: Clefable',
      '|-nothing',
      '|turn|4',
      '|move|p2a: Primeape|Petal Dance|p1a: Clefable|[from]Petal Dance|[miss]',
      '|-miss|p2a: Primeape',
      '|move|p1a: Clefable|Splash|p1a: Clefable',
      '|-nothing',
      '|turn|5',
      '|move|p2a: Primeape|Petal Dance|p1a: Clefable|[from]Petal Dance|[miss]',
      '|-start|p2a: Primeape|confusion|[silent]',
      '|-miss|p2a: Primeape',
      '|move|p1a: Clefable|Splash|p1a: Clefable',
      '|-nothing',
      '|turn|6',
      '|-activate|p2a: Primeape|confusion',
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Mimic|p1a: Clefable|[from]Metronome',
      '|-start|p2a: Primeape|Mimic|Splash',
      '|move|p1a: Clefable|Metronome|p1a: Clefable',
      '|move|p1a: Clefable|Disable|p2a: Primeape|[from]Metronome',
      '|-start|p2a: Primeape|Disable|Splash',
      '|turn|7',
      '|-end|p2a: Primeape|confusion',
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Rage|p1a: Clefable|[from]Metronome',
      '|-damage|p1a: Clefable|305/393',
      '|move|p1a: Clefable|Metronome|p1a: Clefable',
      '|move|p1a: Clefable|Quick Attack|p2a: Primeape|[from]Metronome',
      '|-damage|p2a: Primeape|285/333',
      '|-boost|p2a: Primeape|atk|1|[from] Rage',
      '|turn|8',
    ]);
  });

  test('MirrorMove effect', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      NO_CRIT, MIN_DMG, MISS, MISS,
    ], [
      {species: 'Fearow', evs, moves: ['Mirror Move', 'Peck', 'Fly']},
    ], [
      {species: 'Pidgeot', evs, moves: ['Mirror Move', 'Swift']},
      {species: 'Pidgeotto', evs, moves: ['Gust']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Can't Mirror Move if no move has been used or if Mirror Move is last used
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(31);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(31);

    // Can Mirror Move regular attacks
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 44);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 43);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('peck');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('peck');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(31);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(30);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 74);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 43);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('peck');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(30);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(30);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 74);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 74);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(29);

    // Should actually copy Swift and not Fly
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 74);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(28);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('fly');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(28);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(27);

    // Switching resets last used moves
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p2.pokemon[0].lastMove).toBeNull();
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(28);

    verify(battle, [
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|-fail|p1a: Fearow',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|-fail|p2a: Pidgeot',
      '|turn|2',
      '|move|p1a: Fearow|Peck|p2a: Pidgeot',
      '|-damage|p2a: Pidgeot|326/369',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Peck|p1a: Fearow|[from]Mirror Move',
      '|-damage|p1a: Fearow|289/333',
      '|turn|3',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|move|p1a: Fearow|Peck|p2a: Pidgeot|[from]Mirror Move',
      '|-damage|p2a: Pidgeot|283/369',
      '|move|p2a: Pidgeot|Swift|p1a: Fearow',
      '|-damage|p1a: Fearow|215/333',
      '|turn|4',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|move|p1a: Fearow|Swift|p2a: Pidgeot|[from]Mirror Move',
      '|-damage|p2a: Pidgeot|209/369',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Swift|p1a: Fearow|[from]Mirror Move',
      '|-damage|p1a: Fearow|141/333',
      '|turn|5',
      '|move|p1a: Fearow|Fly||[still]',
      '|-prepare|p1a: Fearow|Fly',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Swift|p1a: Fearow|[from]Mirror Move',
      '|-damage|p1a: Fearow|67/333',
      '|turn|6',
      '|move|p1a: Fearow|Fly|p2a: Pidgeot|[from]Fly|[miss]',
      '|-miss|p1a: Fearow',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Fly||[from]Mirror Move|[still]',
      '|-prepare|p2a: Pidgeot|Fly',
      '|turn|7',
      '|move|p1a: Fearow|Peck|p2a: Pidgeot|[miss]',
      '|-miss|p1a: Fearow',
      '|move|p2a: Pidgeot|Fly|p1a: Fearow|[from]Fly|[miss]',
      '|-miss|p2a: Pidgeot',
      '|turn|8',
      '|switch|p2a: Pidgeotto|Pidgeotto|329/329',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|-fail|p1a: Fearow',
      '|turn|9',
    ]);
  });

  test('Explode effect', () => {
    const battle = startBattle([HIT, HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG], [
      {species: 'Electrode', level: 80, evs, moves: ['Explosion', 'Toxic']},
      {species: 'Onix', evs, moves: ['Self-Destruct']},
    ], [
      {species: 'Chansey', evs, moves: ['Substitute', 'Splash']},
      {species: 'Gengar', evs, moves: ['Night Shade']},
    ]);

    const electrode = battle.p1.pokemon[0].hp;
    const onix = battle.p1.pokemon[1].hp;
    let chansey = battle.p2.pokemon[0].hp;
    const gengar = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(electrode);
    expect(battle.p2.pokemon[0].hp).toBe(chansey = chansey - 175 - 43);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 86);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 342);

    battle.makeChoices('switch 2', '');
    expect(battle.p1.pokemon[0].hp).toBe(onix);
    expect(battle.p2.pokemon[0].hp).toBe(chansey);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    verify(battle, [
      '|move|p1a: Electrode|Toxic|p2a: Chansey',
      '|-status|p2a: Chansey|tox',
      '|move|p2a: Chansey|Substitute|p2a: Chansey',
      '|-start|p2a: Chansey|Substitute',
      '|-damage|p2a: Chansey|528/703 tox',
      '|-damage|p2a: Chansey|485/703 tox|[from] psn',
      '|turn|2',
      '|move|p1a: Electrode|Explosion|p2a: Chansey',
      '|-end|p2a: Chansey|Substitute',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|-damage|p2a: Chansey|399/703 tox|[from] psn',
      '|turn|3',
      '|move|p1a: Electrode|Explosion|p2a: Chansey',
      '|-damage|p2a: Chansey|57/703 tox',
      '|faint|p1a: Electrode',
      '|switch|p1a: Onix|Onix|273/273',
      '|turn|4',
      '|switch|p2a: Gengar|Gengar|323/323',
      '|move|p1a: Onix|Self-Destruct|p2a: Gengar',
      '|-immune|p2a: Gengar',
      '|faint|p1a: Onix',
      '|win|Player 2',
    ]);
  });

  test('Swift effect', () => {
    const battle = startBattle([NO_CRIT, MIN_DMG], [
      {species: 'Eevee', evs, moves: ['Swift']},
    ], [
      {species: 'Diglett', evs, moves: ['Dig']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 91);

    verify(battle, [
      '|move|p2a: Diglett|Dig||[still]',
      '|-prepare|p2a: Diglett|Dig',
      '|move|p1a: Eevee|Swift|p2a: Diglett',
      '|-damage|p2a: Diglett|132/223',
      '|turn|2',
    ]);
  });

  test('Transform effect', () => {
    const IVS = {hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0};
    const no_crit = {
      ...CRIT,
      value: ranged(Math.floor(gen.species.get('Articuno')!.baseStats.spe / 2), 256),
    };
    const battle = startBattle([
      TIE(1), MISS, TIE(2), HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, TIE(2),
    ], [
      {species: 'Mew', level: 50, evs, moves: ['Swords Dance', 'Transform']},
      {species: 'Ditto', ivs: IVS, evs, moves: ['Transform']},
    ], [
      {species: 'Articuno', evs, moves: ['Agility', 'Fly', 'Peck']},
    ]);

    const pp = battle.p1.pokemon[0].moveSlots[1].pp;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.spe).toBe(2);

    // Transform can hit an invulnerable target
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].baseMoveSlots[1].pp).toBe(pp - 1);

    // Transform should copy species, types, stats, and boosts but not level or HP
    expect(battle.p1.pokemon[0].species.name).toBe('Articuno');
    expect(battle.p1.pokemon[0].types).toEqual(battle.p2.pokemon[0].types);
    expect(battle.p1.pokemon[0].level).toBe(50);
    expect(battle.p1.pokemon[0].modifiedStats).toEqual(battle.p2.pokemon[0].modifiedStats);
    expect(battle.p1.pokemon[0].boosts).toEqual(battle.p2.pokemon[0].boosts);

    expect(battle.p1.pokemon[0].moveSlots).toHaveLength(3);
    expect(battle.p1.pokemon[0].moveSlots.map(m => m.move)).toEqual(['Agility', 'Fly', 'Peck']);
    expect(battle.p1.pokemon[0].moveSlots.map(m => m.pp)).toEqual([5, 5, 5]);

    battle.makeChoices('move 3', 'move 1');

    // Transformed Pokémon should retain their original crit rate (and this should speed tie)
    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 20);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].modifiedStats).toEqual(battle.p2.pokemon[0].modifiedStats);
    expect(battle.p1.pokemon[0].boosts).toEqual(battle.p2.pokemon[0].boosts);

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[1].species.name).toBe('Mew');
    expect(battle.p1.pokemon[1].modifiedStats).toEqual(battle.p1.pokemon[1].storedStats);
    expect(battle.p1.pokemon[1].moveSlots[1].pp).toBe(pp - 1);

    const stats = {...battle.p1.pokemon[0].modifiedStats};
    expect(battle.p1.pokemon[0].modifiedStats).toEqual(stats);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].modifiedStats).toEqual(battle.p2.pokemon[0].modifiedStats);

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[1].modifiedStats).toEqual(stats);

    verify(battle, [
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|move|p1a: Mew|Swords Dance|p1a: Mew',
      '|-boost|p1a: Mew|atk|2',
      '|turn|2',
      '|move|p2a: Articuno|Fly||[still]',
      '|-prepare|p2a: Articuno|Fly',
      '|move|p1a: Mew|Transform|p2a: Articuno',
      '|-transform|p1a: Mew|p2a: Articuno',
      '|turn|3',
      '|move|p1a: Mew|Peck|p2a: Articuno|[miss]',
      '|-miss|p1a: Mew',
      '|move|p2a: Articuno|Fly|p1a: Mew|[from]Fly|[miss]',
      '|-miss|p2a: Articuno',
      '|turn|4',
      '|move|p2a: Articuno|Peck|p1a: Mew',
      '|-damage|p1a: Mew|171/206',
      '|move|p1a: Mew|Peck|p2a: Articuno',
      '|-crit|p2a: Articuno',
      '|-damage|p2a: Articuno|363/383',
      '|turn|5',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|move|p1a: Mew|Agility|p1a: Mew',
      '|-boost|p1a: Mew|spe|2',
      '|turn|6',
      '|switch|p1a: Ditto|Ditto|269/269',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|turn|7',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-fail|p2a: Articuno',
      '|move|p1a: Ditto|Transform|p2a: Articuno',
      '|-transform|p1a: Ditto|p2a: Articuno',
      '|turn|8',
      '|switch|p1a: Mew|Mew, L50|171/206',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-fail|p2a: Articuno',
      '|turn|9',
    ]);
  });

  test('Conversion effect', () => {
    const battle = startBattle([], [
      {species: 'Porygon', evs, moves: ['Conversion']},
    ], [
      {species: 'Slowbro', evs, moves: ['Splash']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Porygon|Conversion|p2a: Slowbro',
      '|-start|p1a: Porygon|typechange|Water/Psychic|[from] move: Conversion|[of] p2a: Slowbro',
      '|move|p2a: Slowbro|Splash|p2a: Slowbro',
      '|-nothing',
      '|turn|2',
    ]);
  });

  test('Substitute effect', () => {
    const battle = startBattle([HIT, HIT, NO_CRIT, MIN_DMG, HIT, HIT], [
      {species: 'Mewtwo', evs, moves: ['Substitute', 'Splash']},
      {species: 'Abra', level: 2, moves: ['Substitute']},
    ], [
      {species: 'Electabuzz', moves: ['Flash', 'Strength']},
    ]);

    battle.p1.pokemon[1].hp = 3;
    battle.p1.pokemon[1].maxhp = 3;

    let mewtwo = battle.p1.pokemon[0].hp;
    const abra = battle.p1.pokemon[1].hp;

    // Takes 1/4 of maximum HP to make a Substitute with that HP + 1, protects against stat down
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(mewtwo -= 103);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(104);

    // Can't make a Substitute if you already have one, absorbs damage
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(mewtwo);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(62);

    // Disappears when switching out
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(abra);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();

    // Can get "free" Substitutes if 3 or less max HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(abra);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(1);

    verify(battle, [
      '|move|p1a: Mewtwo|Substitute|p1a: Mewtwo',
      '|-start|p1a: Mewtwo|Substitute',
      '|-damage|p1a: Mewtwo|312/415',
      '|move|p2a: Electabuzz|Flash|p1a: Mewtwo',
      '|-fail|p1a: Mewtwo',
      '|turn|2',
      '|move|p1a: Mewtwo|Substitute|p1a: Mewtwo',
      '|-fail|p1a: Mewtwo|move: Substitute',
      '|move|p2a: Electabuzz|Strength|p1a: Mewtwo',
      '|-activate|p1a: Mewtwo|Substitute|[damage]',
      '|turn|3',
      '|switch|p1a: Abra|Abra, L2|3/3',
      '|move|p2a: Electabuzz|Flash|p1a: Abra',
      '|-unboost|p1a: Abra|accuracy|1',
      '|turn|4',
      '|move|p2a: Electabuzz|Flash|p1a: Abra',
      '|-unboost|p1a: Abra|accuracy|1',
      '|move|p1a: Abra|Substitute|p1a: Abra',
      '|-start|p1a: Abra|Substitute',
      '|turn|5',
    ]);
  });

  // Pokémon Showdown Bugs

  test('Bide residual bug', () => {
    const battle = startBattle([HIT, HIT, BIDE(2), HIT, HIT], [
      {species: 'Jolteon', evs, moves: ['Leech Seed', 'Bide']},
    ], [
      {species: 'Sandslash', evs, moves: ['Toxic', 'Seismic Toss']},
      {species: 'Victreebel', evs, moves: ['Solar Beam']},
    ]);

    battle.p2.active[0].hp = 100;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp = p1hp - 20 - 100 + 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp = p1hp - 40 - 100 + 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 60);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Jolteon|Leech Seed|p2a: Sandslash',
      '|-start|p2a: Sandslash|move: Leech Seed',
      '|move|p2a: Sandslash|Toxic|p1a: Jolteon',
      '|-status|p1a: Jolteon|tox',
      '|-damage|p2a: Sandslash|78/353|[from] Leech Seed|[of] p1a: Jolteon',
      '|turn|2',
      '|move|p1a: Jolteon|Bide|p1a: Jolteon',
      '|-start|p1a: Jolteon|Bide',
      '|-damage|p1a: Jolteon|313/333 tox|[from] psn',
      '|move|p2a: Sandslash|Seismic Toss|p1a: Jolteon',
      '|-damage|p1a: Jolteon|213/333 tox',
      '|-damage|p2a: Sandslash|56/353|[from] Leech Seed|[of] p1a: Jolteon',
      '|-heal|p1a: Jolteon|235/333 tox|[silent]',
      '|turn|3',
      '|-activate|p1a: Jolteon|Bide',
      '|-damage|p1a: Jolteon|195/333 tox|[from] psn',
      '|move|p2a: Sandslash|Seismic Toss|p1a: Jolteon',
      '|-damage|p1a: Jolteon|95/333 tox',
      '|-damage|p2a: Sandslash|34/353|[from] Leech Seed|[of] p1a: Jolteon',
      '|-heal|p1a: Jolteon|117/333 tox|[silent]',
      '|turn|4',
      '|-end|p1a: Jolteon|Bide',
      '|-damage|p2a: Sandslash|0 fnt',
      '|-damage|p1a: Jolteon|57/333 tox|[from] psn',
      '|faint|p2a: Sandslash',
    ]);
  });

  test('Confusion self-hit bug', () => {
    const IVS = {hp: 14, atk: 2, def: 6, spa: 31, spd: 31, spe: 31};
    const EVS = {...evs, hp: 18, atk: 159, def: 30};
    const battle = startBattle([HIT, CFZ(5), CFZ_CANT, CFZ_CANT], [
      {species: 'Jolteon', evs, moves: ['Confuse Ray', 'Reflect']},
    ], [
      {species: 'Arcanine', level: 97, ivs: IVS, evs: EVS, moves: ['Flamethrower']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 50);

    battle.makeChoices('move 2', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 50);

    verify(battle, [
      '|move|p1a: Jolteon|Confuse Ray|p2a: Arcanine',
      '|-start|p2a: Arcanine|confusion',
      '|-activate|p2a: Arcanine|confusion',
      '|-damage|p2a: Arcanine|249/299|[from] confusion',
      '|turn|2',
      '|move|p1a: Jolteon|Reflect|p1a: Jolteon',
      '|-start|p1a: Jolteon|Reflect',
      '|-activate|p2a: Arcanine|confusion',
      '|-damage|p2a: Arcanine|199/299|[from] confusion',
      '|turn|3',
    ]);
  });

  test('Flinch persistence bug', () => {
    const proc = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([HIT, HIT, NO_CRIT, MIN_DMG, proc], [
      {species: 'Persian', evs, moves: ['Poison Powder', 'Splash']},
    ], [
      {species: 'Arcanine', evs, moves: ['Rolling Kick']},
      {species: 'Squirtle', evs, moves: ['Water Gun']},
      {species: 'Rhydon', evs, moves: ['Earthquale']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    battle.p2.pokemon[0].hp = 1;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 127);
    expect(battle.p1.pokemon[0].volatiles['flinch']).toBeDefined();
    expect(battle.p2.pokemon[0].hp).toBe(0);

    battle.makeChoices('', 'switch 2');

    battle.makeChoices('move 2', 'switch 3');
    // expect(battle.p1.pokemon[0].volatiles['flinch']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Persian|Poison Powder|p2a: Arcanine',
      '|-status|p2a: Arcanine|psn',
      '|move|p2a: Arcanine|Rolling Kick|p1a: Persian',
      '|-supereffective|p1a: Persian',
      '|-damage|p1a: Persian|206/333',
      '|-damage|p2a: Arcanine|0 fnt|[from] psn|[of] p1a: Persian',
      '|faint|p2a: Arcanine',
      '|switch|p2a: Squirtle|Squirtle|291/291',
      '|turn|2',
      '|switch|p2a: Rhydon|Rhydon|413/413',
      '|cant|p1a: Persian|flinch',
      '|turn|3',
    ]);
  });

  test('Disable + Transform bug', () => {
    {
      const battle = startBattle([HIT, DISABLE_MOVE(2), DISABLE_DURATION(5)], [
        {species: 'Voltorb', evs, moves: ['Disable', 'Splash']},
      ], [
        {species: 'Goldeen', evs, moves: ['Transform', 'Water Gun', 'Splash', 'Haze']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      // Pokémon Showdown thinks "Water Gun" was disabled instead of move slot 2
      // expect(choices(battle, 'p2')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

      verify(battle, [
        '|move|p1a: Voltorb|Disable|p2a: Goldeen',
        '|-start|p2a: Goldeen|Disable|Water Gun',
        '|move|p2a: Goldeen|Transform|p1a: Voltorb',
        '|-transform|p2a: Goldeen|p1a: Voltorb',
        '|turn|2',
      ]);
    }
    {
      const battle = startBattle([HIT, DISABLE_MOVE(2), DISABLE_DURATION(5)], [
        {species: 'Voltorb', evs, moves: ['Disable', 'Water Gun', 'Splash']},
      ], [
        {species: 'Goldeen', evs, moves: ['Transform', 'Splash', 'Water Gun', 'Haze']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      // Pokémon Showdown thinks "Splash" was disabled instead of move slot 2
      // expect(choices(battle, 'p2')).toEqual(['move 1', 'move 3']);
      expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

      verify(battle, [
        '|move|p1a: Voltorb|Disable|p2a: Goldeen',
        '|-start|p2a: Goldeen|Disable|Splash',
        '|move|p2a: Goldeen|Transform|p1a: Voltorb',
        '|-transform|p2a: Goldeen|p1a: Voltorb',
        '|turn|2',
      ]);
    }
  });

  // Fixed by smogon/pokemon-showdown#{9201,9301} & smogon/pokemon-showdown@203fda57
  test('Disable + Bide bug', () => {
    const battle = startBattle([
      HIT, PAR_CAN, BIDE(3), HIT, DISABLE_MOVE(1, 2), DISABLE_DURATION(5),
    ], [
      {species: 'Voltorb', evs, moves: ['Glare', 'Disable', 'Splash']},
    ], [
      {species: 'Golem', evs, moves: ['Bide', 'Flash']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].status).toBe('par');
    expect(battle.p2.active[0].volatiles['bide'].time).toBe(3);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.active[0].volatiles['disable'].time).toBe(4);
    expect(battle.p2.active[0].volatiles['bide'].time).toBe(3);

    // Bide should not execute when Disabled
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.active[0].volatiles['disable'].time).toBe(3);
    expect(battle.p2.active[0].volatiles['bide'].time).toBe(3);

    // Disabled should trump paralysis
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.active[0].volatiles['disable'].time).toBe(2);
    expect(battle.p2.active[0].volatiles['bide'].time).toBe(3);

    verify(battle, [
      '|move|p1a: Voltorb|Glare|p2a: Golem',
      '|-status|p2a: Golem|par',
      '|move|p2a: Golem|Bide|p2a: Golem',
      '|-start|p2a: Golem|Bide',
      '|turn|2',
      '|move|p1a: Voltorb|Disable|p2a: Golem',
      '|-start|p2a: Golem|Disable|Bide',
      '|cant|p2a: Golem|Disable|Bide',
      '|turn|3',
      '|move|p1a: Voltorb|Splash|p1a: Voltorb',
      '|-nothing',
      '|cant|p2a: Golem|Disable|Bide',
      '|turn|4',
      '|move|p1a: Voltorb|Splash|p1a: Voltorb',
      '|-nothing',
      '|cant|p2a: Golem|Disable|Bide',
      '|turn|5',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#9243
  test('Charge + Sleep bug', () => {
    const battle = startBattle([HIT, SLP(1), HIT, NO_CRIT, MIN_DMG], [
      {species: 'Venusaur', evs, moves: ['Solar Beam', 'Tackle']},
    ], [
      {species: 'Snorlax', evs, moves: ['Lovely Kiss', 'Splash']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 2');

    // The charging move should be forced and should execute instead of preparing again
    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 168);

    verify(battle, [
      '|move|p1a: Venusaur|Solar Beam||[still]',
      '|-prepare|p1a: Venusaur|Solar Beam',
      '|move|p2a: Snorlax|Lovely Kiss|p1a: Venusaur',
      '|-status|p1a: Venusaur|slp|[from] move: Lovely Kiss',
      '|turn|2',
      '|-curestatus|p1a: Venusaur|slp|[msg]',
      '|move|p2a: Snorlax|Splash|p2a: Snorlax',
      '|-nothing',
      '|turn|3',
      '|move|p1a: Venusaur|Solar Beam|p2a: Snorlax|[from]Solar Beam',
      '|-damage|p2a: Snorlax|355/523',
      '|move|p2a: Snorlax|Splash|p2a: Snorlax',
      '|-nothing',
      '|turn|4',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#9034
  test('Explosion invulnerability bug', () => {
    const battle = startBattle([], [
      {species: 'Dugtrio', evs, moves: ['Dig']},
    ], [
      {species: 'Golem', evs, moves: ['Explosion']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    // Explode effects should cause the user to faint if the target is invulnerable
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Dugtrio|Dig||[still]',
      '|-prepare|p1a: Dugtrio|Dig',
      '|move|p2a: Golem|Explosion|p1a: Dugtrio|[miss]',
      '|-miss|p2a: Golem',
      '|faint|p2a: Golem',
      '|win|Player 1',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#9201
  test('Bide + Substitute bug', () => {
    const battle = startBattle([BIDE(2), HIT, HIT], [
      {species: 'Voltorb', evs, moves: ['Sonic Boom', 'Substitute']},
    ], [
      {species: 'Chansey', evs, moves: ['Bide', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // On Pokémon Showdown the opponent having a Substitute blanks Bide
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 70);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(71);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(71);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 20);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 20);

    verify(battle, [
      '|move|p1a: Voltorb|Substitute|p1a: Voltorb',
      '|-start|p1a: Voltorb|Substitute',
      '|-damage|p1a: Voltorb|213/283',
      '|move|p2a: Chansey|Bide|p2a: Chansey',
      '|-start|p2a: Chansey|Bide',
      '|turn|2',
      '|move|p1a: Voltorb|Sonic Boom|p2a: Chansey',
      '|-damage|p2a: Chansey|683/703',
      '|-activate|p2a: Chansey|Bide',
      '|turn|3',
      '|move|p1a: Voltorb|Sonic Boom|p2a: Chansey',
      '|-damage|p2a: Chansey|663/703',
      '|-end|p2a: Chansey|Bide',
      '|-end|p1a: Voltorb|Substitute',
      '|turn|4',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#8969
  test('Counter + Substitute bug', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, HIT], [
      {species: 'Snorlax', evs, moves: ['Reflect', 'Body Slam']},
    ], [
      {species: 'Chansey', evs, moves: ['Substitute', 'Counter']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 175);

    verify(battle, [
      '|move|p2a: Chansey|Substitute|p2a: Chansey',
      '|-start|p2a: Chansey|Substitute',
      '|-damage|p2a: Chansey|528/703',
      '|move|p1a: Snorlax|Reflect|p1a: Snorlax',
      '|-start|p1a: Snorlax|Reflect',
      '|turn|2',
      '|move|p1a: Snorlax|Body Slam|p2a: Chansey',
      '|-end|p2a: Chansey|Substitute',
      '|move|p2a: Chansey|Counter|p1a: Snorlax',
      '|-damage|p1a: Snorlax|0 fnt',
      '|faint|p1a: Snorlax',
      '|win|Player 2',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#8974
  test('Simultaneous Counter bug', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, HIT], [
      {species: 'Golem', evs, moves: ['Strength']},
      {species: 'Chansey', evs, moves: ['Counter']},
    ], [
      {species: 'Tauros', evs, moves: ['Strength']},
      {species: 'Snorlax', evs, moves: ['Counter']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 35);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 63);

    battle.makeChoices('switch 2', 'switch 2');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(battle.p1.pokemon[0].maxhp);
    expect(battle.p2.pokemon[0].hp).toBe(battle.p2.pokemon[0].maxhp);

    verify(battle, [
      '|move|p2a: Tauros|Strength|p1a: Golem',
      '|-resisted|p1a: Golem',
      '|-damage|p1a: Golem|328/363',
      '|move|p1a: Golem|Strength|p2a: Tauros',
      '|-damage|p2a: Tauros|290/353',
      '|turn|2',
      '|switch|p2a: Snorlax|Snorlax|523/523',
      '|switch|p1a: Chansey|Chansey|703/703',
      '|turn|3',
      '|move|p1a: Chansey|Counter|p2a: Snorlax',
      '|-fail|p1a: Chansey',
      '|move|p2a: Snorlax|Counter|p1a: Chansey',
      '|-fail|p2a: Snorlax',
      '|turn|4',
    ]);
  });

  test('Counter + sleep = Desync Clause Mod bug', () => {
    const battle = startBattle([
      HIT, HIT, SLP(8), HIT, HIT, NO_CRIT, MIN_DMG, HIT,
    ], [
      {species: 'Alakazam', evs, moves: ['Seismic Toss', 'Psychic']},
      {species: 'Snorlax', evs, moves: ['Body Slam']},
    ], [
      {species: 'Chansey', evs, moves: ['Sing', 'Soft-Boiled', 'Counter']},
    ]);

    const alakazam = battle.p1.pokemon[0].hp;
    const snorlax = battle.p1.pokemon[1].hp;
    let chansey = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('slp');
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 100);

    battle.makeChoices('switch 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(snorlax);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 168);

    battle.makeChoices('switch 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(703);

    // Choice made while sleeping should not have been saved (and lead to a desync) as
    // on the cartridge no opportunity is given for choosing a move while sleeping
    battle.makeChoices('move 2', 'move 3');
    // expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p1.pokemon[0].hp).toBe(alakazam);

    verify(battle, [
      '|move|p1a: Alakazam|Seismic Toss|p2a: Chansey',
      '|-damage|p2a: Chansey|603/703',
      '|move|p2a: Chansey|Sing|p1a: Alakazam',
      '|-status|p1a: Alakazam|slp|[from] move: Sing',
      '|turn|2',
      '|switch|p1a: Snorlax|Snorlax|523/523',
      '|move|p2a: Chansey|Counter|p1a: Snorlax',
      '|-fail|p2a: Chansey',
      '|turn|3',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-heal|p2a: Chansey|703/703',
      '|move|p1a: Snorlax|Body Slam|p2a: Chansey',
      '|-damage|p2a: Chansey|435/703',
      '|turn|4',
      '|switch|p1a: Alakazam|Alakazam|313/313 slp',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-heal|p2a: Chansey|703/703',
      '|turn|5',
      '|cant|p1a: Alakazam|slp',
      '|move|p2a: Chansey|Counter|p1a: Alakazam',
      '|-fail|p2a: Chansey',
      '|turn|6',
    ]);
  });

  test('Counter via Metronome bug', () => {
    // Counter first
    {
      const battle = startBattle([HIT, METRONOME('Counter'), HIT, HIT], [
        {species: 'Snorlax', evs, moves: ['Seismic Toss']},
      ], [
        {species: 'Chansey', evs, moves: ['Splash', 'Metronome']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

      verify(battle, [
        '|move|p2a: Chansey|Splash|p2a: Chansey',
        '|-nothing',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-damage|p2a: Chansey|603/703',
        '|turn|2',
        '|move|p2a: Chansey|Metronome|p2a: Chansey',
        '|move|p2a: Chansey|Counter|p1a: Snorlax|[from]Metronome',
        '|-fail|p2a: Chansey',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-damage|p2a: Chansey|503/703',
        '|turn|3',
      ]);
    }
    // Counter second
    {
      const battle = startBattle([HIT, METRONOME('Counter'), HIT], [
        {species: 'Alakazam', evs, moves: ['Seismic Toss']},
      ], [
        {species: 'Chansey', evs, moves: ['Metronome']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

      verify(battle, [
        '|move|p1a: Alakazam|Seismic Toss|p2a: Chansey',
        '|-damage|p2a: Chansey|603/703',
        '|move|p2a: Chansey|Metronome|p2a: Chansey',
        '|move|p2a: Chansey|Counter|p1a: Alakazam|[from]Metronome',
        '|-fail|p2a: Chansey',
        '|turn|2',
      ]);
    }
  });

  // Fixed by smogon/pokemon-showdown#9243
  test('Infinite Metronome', () => {
    // Charge
    {
      const battle = startBattle([
        METRONOME('Skull Bash'), METRONOME('Mirror Move'),
        METRONOME('Mirror Move'), METRONOME('Fly'), MISS,
      ], [
        {species: 'Clefairy', evs, moves: ['Metronome']},
      ], [
        {species: 'Clefable', evs, moves: ['Metronome']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(16);
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(16);

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(15);
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(15);

      verify(battle, [
        '|move|p2a: Clefable|Metronome|p2a: Clefable',
        '|move|p2a: Clefable|Skull Bash||[from]Metronome|[still]',
        '|-prepare|p2a: Clefable|Skull Bash',
        '|move|p1a: Clefairy|Metronome|p1a: Clefairy',
        '|move|p1a: Clefairy|Mirror Move|p1a: Clefairy|[from]Metronome',
        '|move|p1a: Clefairy|Metronome|p1a: Clefairy|[from]Mirror Move',
        '|move|p1a: Clefairy|Mirror Move|p1a: Clefairy|[from]Metronome',
        '|move|p1a: Clefairy|Metronome|p1a: Clefairy|[from]Mirror Move',
        '|move|p1a: Clefairy|Fly||[from]Metronome|[still]',
        '|-prepare|p1a: Clefairy|Fly',
        '|turn|2',
        '|move|p2a: Clefable|Skull Bash|p1a: Clefairy|[from]Skull Bash|[miss]',
        '|-miss|p2a: Clefable',
        '|move|p1a: Clefairy|Fly|p2a: Clefable|[from]Fly|[miss]',
        '|-miss|p1a: Clefairy',
        '|turn|3',
      ]);
    }
    // non-Charge
    {
      const battle = startBattle([
        METRONOME('Pound'), HIT, NO_CRIT, MIN_DMG, METRONOME('Mirror Move'), HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Clefable', evs, moves: ['Metronome']},
      ], [
        {species: 'Clefairy', evs, moves: ['Metronome']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      verify(battle, [
        '|move|p1a: Clefable|Metronome|p1a: Clefable',
        '|move|p1a: Clefable|Pound|p2a: Clefairy|[from]Metronome',
        '|-damage|p2a: Clefairy|289/343',
        '|move|p2a: Clefairy|Metronome|p2a: Clefairy',
        '|move|p2a: Clefairy|Mirror Move|p2a: Clefairy|[from]Metronome',
        '|move|p2a: Clefairy|Pound|p1a: Clefable|[from]Mirror Move',
        '|-damage|p1a: Clefable|359/393',
        '|turn|2',
      ]);
    }
  });

  test('Mirror Move/Metronome + Substitute bug', () => {
    const battle = startBattle([
      METRONOME('Seismic Toss'), HIT, MISS, METRONOME('Bonemerang'), HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Hitmonchan', evs, moves: ['Metronome']},
    ], [
      {species: 'Kadabra', evs, moves: ['Substitute', 'Sludge']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 70);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 71);

    verify(battle, [
      '|move|p2a: Kadabra|Substitute|p2a: Kadabra',
      '|-start|p2a: Kadabra|Substitute',
      '|-damage|p2a: Kadabra|213/283',
      '|move|p1a: Hitmonchan|Metronome|p1a: Hitmonchan',
      '|move|p1a: Hitmonchan|Seismic Toss|p2a: Kadabra|[from]Metronome',
      '|-end|p2a: Kadabra|Substitute',
      '|turn|2',
      '|move|p2a: Kadabra|Sludge|p1a: Hitmonchan|[miss]',
      '|-miss|p2a: Kadabra',
      '|move|p1a: Hitmonchan|Metronome|p1a: Hitmonchan',
      '|move|p1a: Hitmonchan|Bonemerang|p2a: Kadabra|[from]Metronome',
      '|-damage|p2a: Kadabra|142/283',
      '|-hitcount|p2a: Kadabra|1',
      '|turn|3',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#8963
  test('Hyper Beam + Substitute bug', () => {
    const battle = startBattle([HIT, NO_CRIT, MAX_DMG], [
      {species: 'Abra', evs, moves: ['Hyper Beam']},
    ], [
      {species: 'Jolteon', evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // Should require recharge if it doesn't knock out the Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBeGreaterThan(0);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBeGreaterThan(0);

    verify(battle, [
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|250/333',
      '|move|p1a: Abra|Hyper Beam|p2a: Jolteon',
      '|-activate|p2a: Jolteon|Substitute|[damage]',
      '|-mustrecharge|p1a: Abra',
      '|turn|2',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|cant|p1a: Abra|recharge',
      '|turn|3',
    ]);
  });

  test('Mimic infinite PP bug', () => {
    // Mimic first
    {
      const battle = startBattle([HIT, MIMIC(2, 2)], [
        {species: 'Gengar', evs, moves: ['Splash', 'Mega Kick']},
      ], [
        {species: 'Gengar', level: 99, evs, moves: ['Mimic', 'Mega Kick', 'Splash']},
        {species: 'Clefable', evs, moves: ['Splash']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(15);
      expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(15);
      expect(battle.p2.pokemon[0].moveSlots[1].pp).toBe(8);
      expect(battle.p2.pokemon[0].baseMoveSlots[1].pp).toBe(8);

      for (let i = 0; i < 18; i++) {
        battle.makeChoices('move 1', 'move 1');
      }
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(-3);
      expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(15);
      expect(battle.p2.pokemon[0].moveSlots[1].pp).toBe(8);
      expect(battle.p2.pokemon[0].baseMoveSlots[1].pp).toBe(8);

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[1].moveSlots[0].pp).toBe(-3);
      expect(battle.p2.pokemon[1].baseMoveSlots[0].pp).toBe(-3);
      expect(battle.p2.pokemon[1].moveSlots[1].pp).toBe(8);
      expect(battle.p2.pokemon[1].baseMoveSlots[1].pp).toBe(8);

      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    }
    // Mimicked move first
    {
      const battle = startBattle([HIT, MIMIC(2, 2)], [
        {species: 'Gengar', evs, moves: ['Splash', 'Mega Kick']},
      ], [
        {species: 'Gengar', level: 99, evs, moves: ['Mega Kick', 'Mimic', 'Splash']},
        {species: 'Clefable', evs, moves: ['Splash']},
      ]);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(8);
      expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(8);
      expect(battle.p2.pokemon[0].moveSlots[1].pp).toBe(15);
      expect(battle.p2.pokemon[0].baseMoveSlots[1].pp).toBe(15);

      for (let i = 0; i < 18; i++) {
        battle.makeChoices('move 1', 'move 2');
      }
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(-10);
      expect(battle.p2.pokemon[0].baseMoveSlots[0].pp).toBe(-10);
      expect(battle.p2.pokemon[0].moveSlots[1].pp).toBe(15);
      expect(battle.p2.pokemon[0].baseMoveSlots[1].pp).toBe(15);

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[1].moveSlots[0].pp).toBe(-10);
      expect(battle.p2.pokemon[1].baseMoveSlots[0].pp).toBe(-10);
      expect(battle.p2.pokemon[1].moveSlots[1].pp).toBe(15);
      expect(battle.p2.pokemon[1].baseMoveSlots[1].pp).toBe(15);

      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    }
  });

  test('Mirror Move + Wrap bug', () => {
    const battle = startBattle([MISS, HIT, NO_CRIT, MIN_DMG, MIN_WRAP, HIT], [
      {species: 'Tentacruel', evs, moves: ['Wrap', 'Surf']},
    ], [
      {species: 'Pidgeot', evs, moves: ['Mirror Move', 'Gust']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);

    // Should be locked into Wrap...
    expect(choices(battle, 'p1')).toEqual(['move 1', 'move 2']);
    // expect(choices(battle, 'p2')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);

    verify(battle, [
      '|move|p1a: Tentacruel|Wrap|p2a: Pidgeot|[miss]',
      '|-miss|p1a: Tentacruel',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Wrap|p1a: Tentacruel|[from]Mirror Move',
      '|-damage|p1a: Tentacruel|343/363',
      '|turn|2',
      '|cant|p1a: Tentacruel|partiallytrapped',
      '|move|p2a: Pidgeot|Gust|p1a: Tentacruel|[from]Gust',
      '|-damage|p1a: Tentacruel|323/363',
      '|turn|3',
    ]);
  });

  test('Mirror Move recharge bug', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MAX_DMG], [
      {species: 'Kadabra', evs, moves: ['Hyper Beam']},
      {species: 'Haunter', evs, moves: ['Splash']},
    ], [
      {species: 'Pidgeot', evs, moves: ['Mirror Move', 'Gust']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 74);

    battle.makeChoices('switch 2', '');

    // Mirror Move should not apply Hyper Beam recharge upon KOing a Pokemon
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    verify(battle, [
      '|move|p1a: Kadabra|Hyper Beam|p2a: Pidgeot',
      '|-damage|p2a: Pidgeot|295/369',
      '|-mustrecharge|p1a: Kadabra',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Hyper Beam|p1a: Kadabra|[from]Mirror Move',
      '|-damage|p1a: Kadabra|0 fnt',
      '|faint|p1a: Kadabra',
      '|switch|p1a: Haunter|Haunter|293/293',
      '|turn|2',
      '|move|p1a: Haunter|Splash|p1a: Haunter',
      '|-nothing',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Splash|p2a: Pidgeot|[from]Mirror Move',
      '|-nothing',
      '|turn|3',
    ]);
  });

  test('Wrap locking + KOs bug', () => {
    const proc = SECONDARY(MIN);
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, proc, HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      HIT, MISS, HIT, NO_CRIT, MIN_DMG, proc, MISS,
      HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
    ], [
      {species: 'Dragonair', evs, moves: ['Wrap']},
      {species: 'Dragonite', evs, moves: ['Dragon Rage', 'Ember', 'Wrap']},
    ], [
      {species: 'Beedrill', evs, moves: ['Poison Sting']},
      {species: 'Kakuna', evs, moves: ['Harden']},
    ]);

    battle.p1.pokemon[0].hp = 21;
    battle.p2.pokemon[0].hp = 210;

    let beedrill = battle.p2.pokemon[0].hp;
    let kakuna = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(beedrill -= 17);

    battle.makeChoices('switch 2', '');

    // Target should not still be bound after the user faints from residual damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(beedrill -= 40);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(beedrill = (beedrill - 91 - 20));
    expect(battle.p2.pokemon[0].status).toBe('brn');

    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(0);

    battle.makeChoices('', 'switch 2');

    // User should not still be locked into Wrap after residual KO
    expect(choices(battle, 'p1')).toEqual(['move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(kakuna -= 21);

    verify(battle, [
      '|move|p2a: Beedrill|Poison Sting|p1a: Dragonair',
      '|-damage|p1a: Dragonair|1/325',
      '|-status|p1a: Dragonair|psn',
      '|move|p1a: Dragonair|Wrap|p2a: Beedrill',
      '|-damage|p2a: Beedrill|193/333',
      '|-damage|p1a: Dragonair|0 fnt|[from] psn|[of] p2a: Beedrill',
      '|faint|p1a: Dragonair',
      '|switch|p1a: Dragonite|Dragonite|385/385',
      '|turn|2',
      '|move|p1a: Dragonite|Dragon Rage|p2a: Beedrill',
      '|-damage|p2a: Beedrill|153/333',
      '|move|p2a: Beedrill|Poison Sting|p1a: Dragonite|[miss]',
      '|-miss|p2a: Beedrill',
      '|turn|3',
      '|move|p1a: Dragonite|Ember|p2a: Beedrill',
      '|-supereffective|p2a: Beedrill',
      '|-damage|p2a: Beedrill|62/333',
      '|-status|p2a: Beedrill|brn',
      '|move|p2a: Beedrill|Poison Sting|p1a: Dragonite|[miss]',
      '|-miss|p2a: Beedrill',
      '|-damage|p2a: Beedrill|42/333 brn|[from] brn|[of] p1a: Dragonite',
      '|turn|4',
      '|move|p1a: Dragonite|Wrap|p2a: Beedrill',
      '|-damage|p2a: Beedrill|19/333 brn',
      '|cant|p2a: Beedrill|partiallytrapped',
      '|-damage|p2a: Beedrill|0 fnt|[from] brn|[of] p1a: Dragonite',
      '|faint|p2a: Beedrill',
      '|switch|p2a: Kakuna|Kakuna|293/293',
      '|turn|5',
      '|move|p1a: Dragonite|Wrap|p2a: Kakuna',
      '|-damage|p2a: Kakuna|272/293',
      '|cant|p2a: Kakuna|partiallytrapped',
      '|turn|6',
    ]);
  });

  test('Thrashing + Substitute bugs', () => {
    // Thrash should lock the user into the move even if it hits a Substitute
    // Fixed by smogon/pokemon-showdown#8963
    {
      const battle = startBattle([THRASH(3), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Nidoking', level: 50, evs, moves: ['Thrash', 'Thunder Wave']},
      ], [
        {species: 'Vileplume', evs, moves: ['Substitute', 'Splash']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;
      let subhp = 89;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 88);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(subhp -= 18);

      expect(choices(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(subhp -= 18);

      verify(battle, [
        '|move|p2a: Vileplume|Substitute|p2a: Vileplume',
        '|-start|p2a: Vileplume|Substitute',
        '|-damage|p2a: Vileplume|265/353',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume',
        '|-activate|p2a: Vileplume|Substitute|[damage]',
        '|turn|2',
        '|move|p2a: Vileplume|Splash|p2a: Vileplume',
        '|-nothing',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume|[from]Thrash',
        '|-activate|p2a: Vileplume|Substitute|[damage]',
        '|turn|3',
      ]);
    }
    // Thrash should lock the user into the move even if it breaks a Substitute
    // Fixed by smogon/pokemon-showdown#9315
    {
      const battle = startBattle([THRASH(3), HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Nidoking', evs, moves: ['Thrash', 'Thunder Wave']},
      ], [
        {species: 'Abra', evs, moves: ['Substitute', 'Splash']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 63);

      expect(choices(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 142);

      verify(battle, [
        '|move|p2a: Abra|Substitute|p2a: Abra',
        '|-start|p2a: Abra|Substitute',
        '|-damage|p2a: Abra|190/253',
        '|move|p1a: Nidoking|Thrash|p2a: Abra',
        '|-end|p2a: Abra|Substitute',
        '|turn|2',
        '|move|p2a: Abra|Splash|p2a: Abra',
        '|-nothing',
        '|move|p1a: Nidoking|Thrash|p2a: Abra|[from]Thrash',
        '|-damage|p2a: Abra|48/253',
        '|turn|3',
      ]);
    }
  });

  test('Thrashing speed tie bug', () => {
    const battle = startBattle([
      TIE(1), THRASH(4), HIT, NO_CRIT, MIN_DMG, TIE(1), HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Dratini', evs, moves: ['Thrash']},
    ], [
      {species: 'Vileplume', evs, moves: ['Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 55);

    // Dratini should go first because it wins the speed tie
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 55);

    verify(battle, [
      '|move|p1a: Dratini|Thrash|p2a: Vileplume',
      '|-damage|p2a: Vileplume|298/353',
      '|move|p2a: Vileplume|Splash|p2a: Vileplume',
      '|-nothing',
      '|turn|2',
      '|move|p2a: Vileplume|Splash|p2a: Vileplume',
      '|-nothing',
      '|move|p1a: Dratini|Thrash|p2a: Vileplume|[from]Thrash',
      '|-damage|p2a: Vileplume|243/353',
      '|turn|3',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#9475
  test('Min/max stat recalculation bug', () => {
    const hi_proc = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([
      HIT, HIT, PAR_CAN, SLP(5), HIT, HIT, HIT, HIT, NO_CRIT,
      MIN_DMG, hi_proc, PAR_CAN, SLP(5), HIT, PAR_CAN, HIT, PAR_CAN,
    ], [
      {species: 'Jolteon', evs, moves: ['String Shot', 'Thunder Wave', 'Lick', 'Splash']},
    ], [
      {species: 'Omanyte', evs, level: 51, moves: ['Splash', 'Rest']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;
    battle.p2.pokemon[0].hp = 1;
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(88);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-1);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(58);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.active[0].boosts.spe).toBe(-1);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(14);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].status).toBe('slp');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-2);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(44);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-3);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(35);
    expect(battle.p2.pokemon[0].status).toBe('');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-4);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(29);

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p2.active[0].boosts.spe).toBe(-4);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(7);
    expect(battle.p2.pokemon[0].status).toBe('slp');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 4', 'move 1');
    battle.makeChoices('move 4', 'move 1');

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-4);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(1);
    expect(battle.p2.pokemon[0].status).toBe('par');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.active[0].boosts.spe).toBe(-4);
    expect(battle.p2.active[0].modifiedStats!.spe).toBe(1);

    verify(battle, [
      '|move|p1a: Jolteon|String Shot|p2a: Omanyte',
      '|-unboost|p2a: Omanyte|spe|1',
      '|move|p2a: Omanyte|Splash|p2a: Omanyte',
      '|-nothing',
      '|turn|2',
      '|move|p1a: Jolteon|Thunder Wave|p2a: Omanyte',
      '|-status|p2a: Omanyte|par',
      '|move|p2a: Omanyte|Rest|p2a: Omanyte',
      '|-status|p2a: Omanyte|slp|[from] move: Rest',
      '|-heal|p2a: Omanyte|144/144 slp|[silent]',
      '|turn|3',
      '|move|p1a: Jolteon|String Shot|p2a: Omanyte',
      '|-unboost|p2a: Omanyte|spe|1',
      '|cant|p2a: Omanyte|slp',
      '|turn|4',
      '|move|p1a: Jolteon|String Shot|p2a: Omanyte',
      '|-unboost|p2a: Omanyte|spe|1',
      '|-curestatus|p2a: Omanyte|slp|[msg]',
      '|turn|5',
      '|move|p1a: Jolteon|String Shot|p2a: Omanyte',
      '|-unboost|p2a: Omanyte|spe|1',
      '|move|p2a: Omanyte|Splash|p2a: Omanyte',
      '|-nothing',
      '|turn|6',
      '|move|p1a: Jolteon|Lick|p2a: Omanyte',
      '|-damage|p2a: Omanyte|122/144',
      '|-status|p2a: Omanyte|par',
      '|move|p2a: Omanyte|Rest|p2a: Omanyte',
      '|-status|p2a: Omanyte|slp|[from] move: Rest',
      '|-heal|p2a: Omanyte|144/144 slp|[silent]',
      '|turn|7',
      '|move|p1a: Jolteon|Splash|p1a: Jolteon',
      '|-nothing',
      '|cant|p2a: Omanyte|slp',
      '|turn|8',
      '|move|p1a: Jolteon|Splash|p1a: Jolteon',
      '|-nothing',
      '|-curestatus|p2a: Omanyte|slp|[msg]',
      '|turn|9',
      '|move|p1a: Jolteon|Thunder Wave|p2a: Omanyte',
      '|-status|p2a: Omanyte|par',
      '|move|p2a: Omanyte|Splash|p2a: Omanyte',
      '|-nothing',
      '|turn|10',
      '|move|p1a: Jolteon|String Shot|p2a: Omanyte',
      '|-unboost|p2a: Omanyte|spe|1',
      '|-boost|p2a: Omanyte|spe|1',
      '|-fail|p2a: Omanyte',
      '|move|p2a: Omanyte|Splash|p2a: Omanyte',
      '|-nothing',
      '|turn|11',
    ]);
  });

  // Glitches

  test('0 damage glitch', () => {
    const battle = startBattle([HIT, HIT, NO_CRIT, HIT, HIT, HIT, NO_CRIT], [
      {species: 'Bulbasaur', evs, moves: ['Growl']},
    ], [
      {species: 'Bellsprout', level: 2, moves: ['Vine Whip']},
      {species: 'Chansey', level: 2, moves: ['Vine Whip']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);

    battle.makeChoices('move 1', 'switch 2');
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);

    verify(battle, [
      '|move|p1a: Bulbasaur|Growl|p2a: Bellsprout',
      '|-unboost|p2a: Bellsprout|atk|1',
      '|move|p2a: Bellsprout|Vine Whip|p1a: Bulbasaur',
      '|-resisted|p1a: Bulbasaur',
      '|-damage|p1a: Bulbasaur|293/293',
      '|turn|2',
      '|switch|p2a: Chansey|Chansey, L2|22/22',
      '|move|p1a: Bulbasaur|Growl|p2a: Chansey',
      '|-unboost|p2a: Chansey|atk|1',
      '|turn|3',
      '|move|p1a: Bulbasaur|Growl|p2a: Chansey',
      '|-unboost|p2a: Chansey|atk|1',
      '|move|p2a: Chansey|Vine Whip|p1a: Bulbasaur',
      '|-resisted|p1a: Bulbasaur',
      '|-damage|p1a: Bulbasaur|293/293',
      '|turn|4',
    ]);
  });

  test('1/256 miss glitch', () => {
    const battle = startBattle([MISS, MISS], [
      {species: 'Jigglypuff', evs, moves: ['Pound']},
    ], [
      {species: 'Nidoran-F', evs, moves: ['Scratch']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

    verify(battle, [
      '|move|p2a: Nidoran-F|Scratch|p1a: Jigglypuff|[miss]',
      '|-miss|p2a: Nidoran-F',
      '|move|p1a: Jigglypuff|Pound|p2a: Nidoran-F|[miss]',
      '|-miss|p1a: Jigglypuff',
      '|turn|2',
    ]);
  });

  // Fixed by smogon/pokemon-showdown#9201
  test('Bide damage accumulation glitches', () => {
    // Non-damaging move/action damage accumulation
    {
      const battle = startBattle([BIDE(2), HIT, NO_CRIT, MIN_DMG], [
        {species: 'Poliwrath', level: 40, evs, moves: ['Surf', 'Splash']},
        {species: 'Snorlax', level: 80, evs, moves: ['Rest']},
      ], [
        {species: 'Chansey', level: 80, evs, moves: ['Bide']},
      ]);

      let p1hp = battle.p1.pokemon[1].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 18);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      battle.makeChoices('switch 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 72);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      verify(battle, [
        '|move|p2a: Chansey|Bide|p2a: Chansey',
        '|-start|p2a: Chansey|Bide',
        '|move|p1a: Poliwrath|Surf|p2a: Chansey',
        '|-damage|p2a: Chansey|546/564',
        '|turn|2',
        '|-activate|p2a: Chansey|Bide',
        '|move|p1a: Poliwrath|Splash|p1a: Poliwrath',
        '|-nothing',
        '|turn|3',
        '|switch|p1a: Snorlax|Snorlax, L80|420/420',
        '|-end|p2a: Chansey|Bide',
        '|-damage|p1a: Snorlax|348/420',
        '|turn|4',
      ]);
    }
    // Fainted Pokémon damage accumulation desync
    {
      const battle = startBattle([
        HIT, BIDE(2), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash', 'Tri Attack']},
        {species: 'Snorlax', evs, moves: ['Defense Curl']},
      ], [
        {species: 'Chansey', evs, moves: ['Toxic', 'Bide']},
      ]);

      battle.p1.pokemon[0].hp = 179;

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].status).toBe('tox');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 30);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 60);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 191);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 191);

      battle.makeChoices('switch 2', '');

      verify(battle, [
        '|move|p2a: Chansey|Toxic|p1a: Wigglytuff',
        '|-status|p1a: Wigglytuff|tox',
        '|move|p1a: Wigglytuff|Splash|p1a: Wigglytuff',
        '|-nothing',
        '|-damage|p1a: Wigglytuff|149/483 tox|[from] psn',
        '|turn|2',
        '|move|p2a: Chansey|Bide|p2a: Chansey',
        '|-start|p2a: Chansey|Bide',
        '|move|p1a: Wigglytuff|Tri Attack|p2a: Chansey',
        '|-damage|p2a: Chansey|512/703',
        '|-damage|p1a: Wigglytuff|89/483 tox|[from] psn',
        '|turn|3',
        '|-activate|p2a: Chansey|Bide',
        '|move|p1a: Wigglytuff|Tri Attack|p2a: Chansey',
        '|-damage|p2a: Chansey|321/703',
        '|-damage|p1a: Wigglytuff|0 fnt|[from] psn',
        '|faint|p1a: Wigglytuff',
        '|switch|p1a: Snorlax|Snorlax|523/523',
        '|turn|4',
      ]);
    }
  });

  test('Counter glitches', () => {
    // self-Counter
    {
      const battle = startBattle([
        HIT, PAR_CAN, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, PAR_CANT, HIT,
      ], [
        {species: 'Jolteon', evs, moves: ['Agility', 'Tackle']},
      ], [
        {species: 'Chansey', level: 80, evs, moves: ['Thunder Wave', 'Mega Drain', 'Counter']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].status).toBe('par');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 67 + 9));

      battle.makeChoices('move 2', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= (2 * 9));
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      verify(battle, [
        '|move|p1a: Jolteon|Agility|p1a: Jolteon',
        '|-boost|p1a: Jolteon|spe|2',
        '|move|p2a: Chansey|Thunder Wave|p1a: Jolteon',
        '|-status|p1a: Jolteon|par',
        '|turn|2',
        '|move|p1a: Jolteon|Tackle|p2a: Chansey',
        '|-damage|p2a: Chansey|497/564',
        '|move|p2a: Chansey|Mega Drain|p1a: Jolteon',
        '|-damage|p1a: Jolteon|314/333 par',
        '|-heal|p2a: Chansey|506/564|[from] drain|[of] p1a: Jolteon',
        '|turn|3',
        '|cant|p1a: Jolteon|par',
        '|move|p2a: Chansey|Counter|p1a: Jolteon',
        '|-damage|p1a: Jolteon|296/333 par',
        '|turn|4',
      ]);
    }
    // Desync
    {
      const battle = startBattle([
        HIT, PAR_CAN, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, PAR_CANT, HIT,
      ], [
        {species: 'Jolteon', evs, moves: ['Agility', 'Tackle']},
      ], [
        {species: 'Chansey', level: 80, evs, moves: ['Thunder Wave', 'Mega Drain', 'Counter']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].status).toBe('par');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 67 + 9));

      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      verify(battle, [
        '|move|p1a: Jolteon|Agility|p1a: Jolteon',
        '|-boost|p1a: Jolteon|spe|2',
        '|move|p2a: Chansey|Thunder Wave|p1a: Jolteon',
        '|-status|p1a: Jolteon|par',
        '|turn|2',
        '|move|p1a: Jolteon|Tackle|p2a: Chansey',
        '|-damage|p2a: Chansey|497/564',
        '|move|p2a: Chansey|Mega Drain|p1a: Jolteon',
        '|-damage|p1a: Jolteon|314/333 par',
        '|-heal|p2a: Chansey|506/564|[from] drain|[of] p1a: Jolteon',
        '|turn|3',
        '|cant|p1a: Jolteon|par',
        '|move|p2a: Chansey|Counter|p1a: Jolteon',
        '|-fail|p2a: Chansey',
        '|turn|4',
      ]);
    }
  });

  test('Freeze top move selection glitch', () => {
    const NO_BRN = {...FRZ, value: FRZ.value + 1};
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, FRZ, HIT, NO_CRIT, MIN_DMG,
      HIT, NO_CRIT, MIN_DMG, NO_BRN,
    ], [
      {species: 'Slowbro', evs, moves: ['Psychic', 'Amnesia', 'Splash']},
      {species: 'Spearow', level: 8, evs, moves: ['Peck']},
    ], [
      {species: 'Mew', evs, moves: ['Blizzard', 'Fire Blast']},
    ], b => {
      b.p1.pokemon[0].moveSlots[0].pp = 0;
    });

    let p1hp = battle.p1.pokemon[0].hp;

    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);

    // last_selected_move is Amnesia before getting Frozen
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 50);
    expect(battle.p1.pokemon[0].status).toBe('frz');

    battle.makeChoices('switch 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 2', '');

    // last_selected_move is still Amnesia but desync occurs as Psychic gets chosen
    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 50);

    verify(battle, [
      '|switch|p1a: Slowbro|Slowbro|393/393',
      '|switch|p2a: Mew|Mew|403/403',
      '|turn|1',
      '|move|p2a: Mew|Blizzard|p1a: Slowbro',
      '|-resisted|p1a: Slowbro',
      '|-damage|p1a: Slowbro|343/393',
      '|-status|p1a: Slowbro|frz',
      '|cant|p1a: Slowbro|frz',
      '|turn|2',
      '|switch|p1a: Spearow|Spearow, L8|31/31',
      '|move|p2a: Mew|Fire Blast|p1a: Spearow',
      '|-damage|p1a: Spearow|0 fnt',
      '|faint|p1a: Spearow',
      '|switch|p1a: Slowbro|Slowbro|343/393 frz',
      '|turn|3',
      '|move|p2a: Mew|Fire Blast|p1a: Slowbro',
      '|-resisted|p1a: Slowbro',
      '|-damage|p1a: Slowbro|293/393 frz',
      '|-curestatus|p1a: Slowbro|frz|[msg]',
      '|move|p1a: Slowbro|Splash|p1a: Slowbro',
      '|-nothing',
      '|turn|4',
    ]);
  });

  test('Toxic counter glitches', () => {
    const BRN = SECONDARY(ranged(77, 256) - 1);
    const battle = startBattle([HIT, SLP(5), HIT, HIT, NO_CRIT, MIN_DMG, BRN], [
      {species: 'Venusaur', evs, moves: ['Toxic', 'Leech Seed', 'Splash', 'Fire Blast']},
    ], [
      {species: 'Clefable', evs, moves: ['Splash', 'Rest']},
    ]);

    battle.p2.pokemon[0].hp = 392;

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(0);
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(0);
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(1);
    battle.makeChoices('move 4', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(3);

    verify(battle, [
      '|move|p1a: Venusaur|Toxic|p2a: Clefable',
      '|-status|p2a: Clefable|tox',
      '|move|p2a: Clefable|Rest|p2a: Clefable',
      '|-status|p2a: Clefable|slp|[from] move: Rest',
      '|-heal|p2a: Clefable|393/393 slp|[silent]',
      '|turn|2',
      '|move|p1a: Venusaur|Splash|p1a: Venusaur',
      '|-nothing',
      '|cant|p2a: Clefable|slp',
      '|turn|3',
      '|move|p1a: Venusaur|Leech Seed|p2a: Clefable',
      '|-start|p2a: Clefable|move: Leech Seed',
      '|-curestatus|p2a: Clefable|slp|[msg]',
      '|-damage|p2a: Clefable|369/393|[from] Leech Seed|[of] p1a: Venusaur',
      '|turn|4',
      '|move|p1a: Venusaur|Fire Blast|p2a: Clefable',
      '|-damage|p2a: Clefable|273/393',
      '|-status|p2a: Clefable|brn',
      '|move|p2a: Clefable|Splash|p2a: Clefable',
      '|-nothing',
      '|-damage|p2a: Clefable|225/393 brn|[from] brn',
      '|-damage|p2a: Clefable|153/393 brn|[from] Leech Seed|[of] p1a: Venusaur',
      '|turn|5',
    ]);
  });

  test('Poison/Burn animation with 0 HP', () => {
    // Faint from Recoil (no healing on Pokémon Showdown)
    {
      const battle = startBattle([HIT, HIT, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Ivysaur', evs, moves: ['Toxic', 'Leech Seed']},
        {species: 'Nidoran-M', evs, moves: ['Horn Attack']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash', 'Double Edge']},
        {species: 'Nidoran-F', evs, moves: ['Double Kick']},
      ]);

      battle.p1.pokemon[0].hp = 137;
      battle.p2.pokemon[0].hp = 60;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(137);
      expect(battle.p2.pokemon[0].hp).toBe(30);
      expect(battle.p2.pokemon[0].status).toBe('tox');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Ivysaur|Toxic|p2a: Wigglytuff',
        '|-status|p2a: Wigglytuff|tox',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|-damage|p2a: Wigglytuff|30/483 tox|[from] psn',
        '|turn|2',
        '|move|p1a: Ivysaur|Leech Seed|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|move: Leech Seed',
        '|move|p2a: Wigglytuff|Double-Edge|p1a: Ivysaur',
        '|-damage|p1a: Ivysaur|1/323',
        '|-damage|p2a: Wigglytuff|0 fnt|[from] Recoil|[of] p1a: Ivysaur',
        '|faint|p2a: Wigglytuff',
      ]);
    }
    // Faint from Crash (no healing on Pokémon Showdown)
    {
      const battle = startBattle([HIT, HIT, MISS], [
        {species: 'Ivysaur', evs, moves: ['Toxic', 'Leech Seed']},
        {species: 'Nidoran-M', evs, moves: ['Horn Attack']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash', 'Jump Kick']},
        {species: 'Nidoran-F', evs, moves: ['Double Kick']},
      ]);

      battle.p1.pokemon[0].hp = 1;
      battle.p2.pokemon[0].hp = 31;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].status).toBe('tox');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Ivysaur|Toxic|p2a: Wigglytuff',
        '|-status|p2a: Wigglytuff|tox',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|-damage|p2a: Wigglytuff|1/483 tox|[from] psn',
        '|turn|2',
        '|move|p1a: Ivysaur|Leech Seed|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|move: Leech Seed',
        '|move|p2a: Wigglytuff|Jump Kick|p1a: Ivysaur|[miss]',
        '|-miss|p2a: Wigglytuff',
        '|-damage|p2a: Wigglytuff|0 fnt',
        '|faint|p2a: Wigglytuff',
      ]);
    }
    // Faint from Toxic (heals on Pokémon Showdown)
    {
      const battle = startBattle([HIT, HIT], [
        {species: 'Ivysaur', evs, moves: ['Toxic', 'Leech Seed']},
        {species: 'Nidoran-M', evs, moves: ['Horn Attack']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash', 'Double Edge']},
        {species: 'Nidoran-F', evs, moves: ['Double Kick']},
      ]);

      battle.p1.pokemon[0].hp = 1;
      battle.p2.pokemon[0].hp = 60;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(30);
      expect(battle.p2.pokemon[0].status).toBe('tox');

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(91);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Ivysaur|Toxic|p2a: Wigglytuff',
        '|-status|p2a: Wigglytuff|tox',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|-damage|p2a: Wigglytuff|30/483 tox|[from] psn',
        '|turn|2',
        '|move|p1a: Ivysaur|Leech Seed|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|move: Leech Seed',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|-damage|p2a: Wigglytuff|0 fnt|[from] psn',
        '|-heal|p1a: Ivysaur|91/323|[silent]',
        '|faint|p2a: Wigglytuff',
      ]);
    }
    // Faint from confusion self-hit (heals on Pokémon Showdown)
    {
      const battle = startBattle([HIT, CFZ(5), CFZ_CANT, HIT, CFZ_CANT], [
        {species: 'Ivysaur', evs, moves: ['Confuse Ray', 'Leech Seed']},
        {species: 'Nidoran-M', evs, moves: ['Horn Attack']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Splash', 'Double Edge']},
        {species: 'Nidoran-F', evs, moves: ['Double Kick']},
      ]);

      battle.p1.pokemon[0].hp = 1;
      battle.p2.pokemon[0].hp = 50;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(6);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(31);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Ivysaur|Confuse Ray|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|confusion',
        '|-activate|p2a: Wigglytuff|confusion',
        '|-damage|p2a: Wigglytuff|6/483|[from] confusion',
        '|turn|2',
        '|move|p1a: Ivysaur|Leech Seed|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|move: Leech Seed',
        '|-activate|p2a: Wigglytuff|confusion',
        '|-damage|p2a: Wigglytuff|0 fnt|[from] confusion',
        '|-heal|p1a: Ivysaur|31/323|[silent]',
        '|faint|p2a: Wigglytuff',
      ]);
    }
  });

  test('Defrost move forcing', () => {
    const NO_BRN = {...FRZ, value: FRZ.value + 1};
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, FRZ,
      HIT, NO_CRIT, MIN_DMG, NO_BRN, HIT, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Hypno', level: 50, evs, moves: ['Splash', 'Ice Punch', 'Fire Punch']},
    ], [
      {species: 'Bulbasaur', level: 6, evs, moves: ['Vine Whip']},
      {species: 'Poliwrath', level: 40, evs, moves: ['Surf', 'Water Gun']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[1].hp;

    // Set up P2's last_selected_move to be Vine Whip
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 2);

    // Switching clears last_used_move but not last_selected_move
    battle.makeChoices('move 2', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 23);
    expect(battle.p2.pokemon[0].status).toBe('frz');

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    // After defrosting, Poliwrath will appear to use Surf to P1 and Vine Whip to P2
    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 23);
    expect(battle.p2.pokemon[0].status).toBe('');

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    verify(battle, [
      '|move|p1a: Hypno|Splash|p1a: Hypno',
      '|-nothing',
      '|move|p2a: Bulbasaur|Vine Whip|p1a: Hypno',
      '|-damage|p1a: Hypno|189/191',
      '|turn|2',
      '|switch|p2a: Poliwrath|Poliwrath, L40|159/159',
      '|move|p1a: Hypno|Ice Punch|p2a: Poliwrath',
      '|-resisted|p2a: Poliwrath',
      '|-damage|p2a: Poliwrath|136/159',
      '|-status|p2a: Poliwrath|frz',
      '|turn|3',
      '|move|p1a: Hypno|Fire Punch|p2a: Poliwrath',
      '|-resisted|p2a: Poliwrath',
      '|-damage|p2a: Poliwrath|113/159 frz',
      '|-curestatus|p2a: Poliwrath|frz|[msg]',
      '|move|p2a: Poliwrath|Water Gun|p1a: Hypno',
      '|-damage|p1a: Hypno|177/191',
      '|turn|4',
    ]);
  });

  test('Division by 0', () => {
    // Attack/Special > 255 vs. Defense/Special stat < 4.
    {
      const battle = startBattle([HIT, HIT, MISS, MISS, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Cloyster', level: 65, evs, moves: ['Screech']},
        {species: 'Parasect', evs, moves: ['Swords Dance', 'Leech Life']},
      ], [
        {species: 'Rattata', level: 2, moves: ['Tail Whip']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('switch 2', 'move 1');
      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].modifiedStats!.atk).toBe(576);
      expect(battle.p2.pokemon[0].modifiedStats!.def).toBe(3);

      // 576 Atk vs. 3 Def = should result in a division by 0 freeze
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p1a: Cloyster|Screech|p2a: Rattata',
        '|-unboost|p2a: Rattata|def|2',
        '|move|p2a: Rattata|Tail Whip|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|def|1',
        '|turn|2',
        '|switch|p1a: Parasect|Parasect|323/323',
        '|move|p2a: Rattata|Tail Whip|p1a: Parasect|[miss]',
        '|-miss|p2a: Rattata',
        '|turn|3',
        '|move|p1a: Parasect|Swords Dance|p1a: Parasect',
        '|-boost|p1a: Parasect|atk|2',
        '|move|p2a: Rattata|Tail Whip|p1a: Parasect|[miss]',
        '|-miss|p2a: Rattata',
        '|turn|4',
        '|move|p1a: Parasect|Leech Life|p2a: Rattata',
        '|-damage|p2a: Rattata|0 fnt',
        '|faint|p2a: Rattata',
        '|win|Player 1',
      ]);
    }
    // Defense/Special stat is 512 or 513 + Reflect/Light Screen.
    {
      const def12 = {hp: 0, atk: 0, def: 12, spa: 0, spd: 0, spe: 0};
      const battle = startBattle([
        HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG,
        HIT, HIT, NO_CRIT, MAX_DMG,
      ], [
        {species: 'Cloyster', level: 64, evs: def12, moves: ['Withdraw', 'Reflect']},
      ], [
        {species: 'Pidgey', level: 5, moves: ['Gust', 'Sand-Attack']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;

      expect(battle.p1.pokemon[0].storedStats.def).toBe(256);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 3);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 3);
      expect(battle.p1.pokemon[0].modifiedStats!.def).toBe(512);

      battle.makeChoices('move 2', 'move 2');

      // Division by 0 should occur
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);

      verify(battle, [
        '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
        '|-boost|p1a: Cloyster|def|1',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|154/157',
        '|turn|2',
        '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
        '|-boost|p1a: Cloyster|def|1',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|151/157',
        '|turn|3',
        '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
        '|-start|p1a: Cloyster|Reflect',
        '|move|p2a: Pidgey|Sand Attack|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|accuracy|1',
        '|turn|4',
        '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
        '|-fail|p1a: Cloyster',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|139/157',
        '|turn|5',
      ]);
    }
    // Defense/Special stat >= 514 + Reflect/Light Screen.
    {
      const def20 = {hp: 0, atk: 0, def: 20, spa: 0, spd: 0, spe: 0};
      const battle = startBattle([
        HIT, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MAX_DMG, HIT, HIT, NO_CRIT, MAX_DMG,
      ], [
        {species: 'Cloyster', level: 64, evs: def20, moves: ['Withdraw', 'Reflect']},
      ], [
        {species: 'Pidgey', level: 5, moves: ['Gust', 'Sand-Attack']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;

      expect(battle.p1.pokemon[0].storedStats.def).toBe(257);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 3);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 3);
      expect(battle.p1.pokemon[0].modifiedStats!.def).toBe(514);

      battle.makeChoices('move 2', 'move 2');

      // Higher damage should occur
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);

      verify(battle, [
        '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
        '|-boost|p1a: Cloyster|def|1',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|154/157',
        '|turn|2',
        '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
        '|-boost|p1a: Cloyster|def|1',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|151/157',
        '|turn|3',
        '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
        '|-start|p1a: Cloyster|Reflect',
        '|move|p2a: Pidgey|Sand Attack|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|accuracy|1',
        '|turn|4',
        '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
        '|-fail|p1a: Cloyster',
        '|move|p2a: Pidgey|Gust|p1a: Cloyster',
        '|-damage|p1a: Cloyster|139/157',
        '|turn|5',
      ]);
    }
  });

  test('Hyper Beam + Freeze permanent helplessness', () => {
    const NO_BRN = {...FRZ, value: FRZ.value + 1};
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, FRZ,
      HIT, NO_CRIT, MIN_DMG, NO_BRN, MISS,
      HIT, NO_CRIT, MIN_DMG, NO_BRN, MISS,
    ], [
      {species: 'Chansey', evs, moves: ['Hyper Beam', 'Soft-Boiled']},
      {species: 'Blastoise', evs, moves: ['Hydro Pump']},
    ], [
      {species: 'Lapras', level: 56, evs, moves: ['Blizzard', 'Haze']},
      {species: 'Charizard', evs, moves: ['Flamethrower']},
    ]);

    let chansey = battle.p1.pokemon[0].hp;
    let lapras = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(chansey -= 39);
    expect(battle.p1.pokemon[0].status).toBe('frz');
    expect(battle.p2.pokemon[0].hp).toBe(lapras -= 120);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    // After thawing Chansey should still be stuck recharging
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(lapras);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'switch 2');

    // expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    // Using a Fire-type move after should do nothing to fix the problem
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(chansey -= 90);

    // expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(chansey -= 90);

    verify(battle, [
      '|move|p1a: Chansey|Hyper Beam|p2a: Lapras',
      '|-damage|p2a: Lapras|143/263',
      '|-mustrecharge|p1a: Chansey',
      '|move|p2a: Lapras|Blizzard|p1a: Chansey',
      '|-damage|p1a: Chansey|664/703',
      '|-status|p1a: Chansey|frz',
      '|turn|2',
      '|cant|p1a: Chansey|frz',
      '|move|p2a: Lapras|Haze|p2a: Lapras',
      '|-activate|p2a: Lapras|move: Haze',
      '|-clearallboost|[silent]',
      '|-curestatus|p1a: Chansey|frz|[silent]',
      '|turn|3',
      '|switch|p2a: Charizard|Charizard|359/359',
      '|cant|p1a: Chansey|recharge',
      '|turn|4',
      '|move|p2a: Charizard|Flamethrower|p1a: Chansey',
      '|-damage|p1a: Chansey|574/703',
      '|move|p1a: Chansey|Hyper Beam|p2a: Charizard|[miss]',
      '|-miss|p1a: Chansey',
      '|turn|5',
      '|move|p2a: Charizard|Flamethrower|p1a: Chansey',
      '|-damage|p1a: Chansey|484/703',
      '|move|p1a: Chansey|Hyper Beam|p2a: Charizard|[miss]',
      '|-miss|p1a: Chansey',
      '|turn|6',
    ]);
  });

  test('Hyper Beam + Sleep move glitch', () => {
    const BRN = FRZ;
    const battle = startBattle([
      HIT, HIT, NO_CRIT, MIN_DMG, SLP(2), HIT, NO_CRIT, MIN_DMG, BRN, MISS,
    ], [
      {species: 'Hypno', evs, moves: ['Toxic', 'Hypnosis', 'Splash', 'Fire Punch']},
    ], [
      {species: 'Snorlax', evs, moves: ['Hyper Beam']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 217);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 32);
    expect(battle.p2.pokemon[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(1);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');

    // The Toxic counter should be preserved
    battle.makeChoices('move 4', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 78 - 64));
    expect(battle.p2.pokemon[0].status).toBe('brn');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(2);

    verify(battle, [
      '|move|p1a: Hypno|Toxic|p2a: Snorlax',
      '|-status|p2a: Snorlax|tox',
      '|move|p2a: Snorlax|Hyper Beam|p1a: Hypno',
      '|-damage|p1a: Hypno|156/373',
      '|-mustrecharge|p2a: Snorlax',
      '|-damage|p2a: Snorlax|491/523 tox|[from] psn',
      '|turn|2',
      '|move|p1a: Hypno|Hypnosis|p2a: Snorlax',
      '|-status|p2a: Snorlax|slp|[from] move: Hypnosis',
      '|cant|p2a: Snorlax|slp',
      '|turn|3',
      '|move|p1a: Hypno|Splash|p1a: Hypno',
      '|-nothing',
      '|-curestatus|p2a: Snorlax|slp|[msg]',
      '|turn|4',
      '|move|p1a: Hypno|Fire Punch|p2a: Snorlax',
      '|-damage|p2a: Snorlax|413/523',
      '|-status|p2a: Snorlax|brn',
      '|move|p2a: Snorlax|Hyper Beam|p1a: Hypno|[miss]',
      '|-miss|p2a: Snorlax',
      '|-damage|p2a: Snorlax|349/523 brn|[from] brn|[of] p1a: Hypno',
      '|turn|5',
    ]);
  });

  test('Hyper Beam automatic selection glitch', () => {
    // Regular
    {
      const battle = startBattle([MISS, HIT, NO_CRIT, MIN_DMG, MISS], [
        {species: 'Chansey', evs, moves: ['Hyper Beam', 'Soft-Boiled']},
      ], [
        {species: 'Tentacool', evs, moves: ['Wrap']},
      ]);

      battle.p1.pokemon[0].moveSlots[0].pp = 1;

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 105);

      // Missing should cause Hyper Beam to be automatically selected and underflow
      battle.makeChoices('move 1', 'move 1');
      // expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(63);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);

      verify(battle, [
        '|move|p2a: Tentacool|Wrap|p1a: Chansey|[miss]',
        '|-miss|p2a: Tentacool',
        '|move|p1a: Chansey|Hyper Beam|p2a: Tentacool',
        '|-damage|p2a: Tentacool|178/283',
        '|-mustrecharge|p1a: Chansey',
        '|turn|2',
        '|move|p2a: Tentacool|Wrap|p1a: Chansey|[miss]',
        '|-miss|p2a: Tentacool',
        '|cant|p1a: Chansey|recharge',
        '|turn|3',
      ]);
    }
    // via Metronome
    {
      const battle = startBattle([MISS, METRONOME('Hyper Beam'), HIT, NO_CRIT, MIN_DMG, MISS], [
        {species: 'Chansey', evs, moves: ['Metronome', 'Soft-Boiled']},
      ], [
        {species: 'Tentacool', evs, moves: ['Wrap']},
      ]);

      battle.p1.pokemon[0].moveSlots[0].pp = 1;

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 105);

      // Missing should cause Hyper Beam to be automatically selected and underflow
      battle.makeChoices('move 1', 'move 1');
      // expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(63);

      verify(battle, [
        '|move|p2a: Tentacool|Wrap|p1a: Chansey|[miss]',
        '|-miss|p2a: Tentacool',
        '|move|p1a: Chansey|Metronome|p1a: Chansey',
        '|move|p1a: Chansey|Hyper Beam|p2a: Tentacool|[from]Metronome',
        '|-damage|p2a: Tentacool|178/283',
        '|-mustrecharge|p1a: Chansey',
        '|turn|2',
        '|move|p2a: Tentacool|Wrap|p1a: Chansey|[miss]',
        '|-miss|p2a: Tentacool',
        '|cant|p1a: Chansey|recharge',
        '|turn|3',
      ]);
    }
  });

  test('Invulnerability glitch', () => {
    const battle = startBattle([
      HIT,
      PAR_CAN,
      PAR_CANT,
      PAR_CAN, NO_CRIT, MIN_DMG,
      PAR_CAN,
      PAR_CAN, HIT,
      NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, NO_PAR,
    ], [
      {species: 'Fearow', evs, moves: ['Agility', 'Fly']},
    ], [
      {species: 'Pikachu', level: 50, evs, moves: ['Thunder Wave', 'Thunder Shock', 'Swift']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('par');

    battle.makeChoices('move 2', 'move 2');

    // After Fly is interrupted by Paralysis, Invulnerability should be preserved
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);

    // Swift should still be able to hit
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 11);

    battle.makeChoices('move 2', 'move 2');

    // Successfully completing Fly removes Invulnerability
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 130);

    verify(battle, [
      '|move|p1a: Fearow|Agility|p1a: Fearow',
      '|-boost|p1a: Fearow|spe|2',
      '|move|p2a: Pikachu|Thunder Wave|p1a: Fearow',
      '|-status|p1a: Fearow|par',
      '|turn|2',
      '|move|p1a: Fearow|Fly||[still]',
      '|-prepare|p1a: Fearow|Fly',
      '|move|p2a: Pikachu|Thunder Shock|p1a: Fearow|[miss]',
      '|-miss|p2a: Pikachu',
      '|turn|3',
      '|cant|p1a: Fearow|par',
      '|move|p2a: Pikachu|Thunder Shock|p1a: Fearow|[miss]',
      '|-miss|p2a: Pikachu',
      '|turn|4',
      '|move|p1a: Fearow|Agility|p1a: Fearow',
      '|-boost|p1a: Fearow|spe|2',
      '|move|p2a: Pikachu|Swift|p1a: Fearow',
      '|-damage|p1a: Fearow|322/333 par',
      '|turn|5',
      '|move|p1a: Fearow|Fly||[still]',
      '|-prepare|p1a: Fearow|Fly',
      '|move|p2a: Pikachu|Thunder Shock|p1a: Fearow|[miss]',
      '|-miss|p2a: Pikachu',
      '|turn|6',
      '|move|p1a: Fearow|Fly|p2a: Pikachu|[from]Fly',
      '|-resisted|p2a: Pikachu',
      '|-damage|p2a: Pikachu|11/141',
      '|move|p2a: Pikachu|Thunder Shock|p1a: Fearow',
      '|-supereffective|p1a: Fearow',
      '|-damage|p1a: Fearow|297/333 par',
      '|turn|7',
    ]);
  });

  test('Stat modification errors', () => {
    {
      const battle = startBattle([HIT, HIT, PAR_CAN, HIT, PAR_CAN, HIT], [
        {species: 'Bulbasaur', level: 6, moves: ['Stun Spore', 'Growth']},
      ], [
        {species: 'Pidgey', level: 56, moves: ['Sand-Attack']},
      ]);

      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(12);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(84);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(12);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(21);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(12);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(5);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(12);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(1);

      verify(battle, [
        '|move|p2a: Pidgey|Sand Attack|p1a: Bulbasaur',
        '|-unboost|p1a: Bulbasaur|accuracy|1',
        '|move|p1a: Bulbasaur|Stun Spore|p2a: Pidgey',
        '|-status|p2a: Pidgey|par',
        '|turn|2',
        '|move|p2a: Pidgey|Sand Attack|p1a: Bulbasaur',
        '|-unboost|p1a: Bulbasaur|accuracy|1',
        '|move|p1a: Bulbasaur|Growth|p1a: Bulbasaur',
        '|-boost|p1a: Bulbasaur|spa|1',
        '|-boost|p1a: Bulbasaur|spd|1',
        '|turn|3',
        '|move|p1a: Bulbasaur|Growth|p1a: Bulbasaur',
        '|-boost|p1a: Bulbasaur|spa|1',
        '|-boost|p1a: Bulbasaur|spd|1',
        '|move|p2a: Pidgey|Sand Attack|p1a: Bulbasaur',
        '|-unboost|p1a: Bulbasaur|accuracy|1',
        '|turn|4',
      ]);
    }
    {
      const battle = startBattle([HIT, PAR_CAN, HIT, PAR_CANT, HIT, HIT, PAR_CANT], [
        {species: 'Bulbasaur', level: 6, moves: ['Stun Spore', 'Growth']},
        {species: 'Cloyster', level: 82, moves: ['Withdraw']},
      ], [
        {species: 'Rattata', level: 2, moves: ['Thunder Wave', 'Tail Whip', 'String Shot']},
      ]);

      expect(battle.p1.pokemon[1].modifiedStats!.spe).toBe(144);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(8);

      battle.makeChoices('switch 2', 'move 1');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(36);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(8);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(9);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(8);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(2);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(8);

      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(23);
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(8);

      verify(battle, [
        '|switch|p1a: Cloyster|Cloyster, L82|198/198',
        '|move|p2a: Rattata|Thunder Wave|p1a: Cloyster',
        '|-status|p1a: Cloyster|par',
        '|turn|2',
        '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
        '|-boost|p1a: Cloyster|def|1',
        '|move|p2a: Rattata|Tail Whip|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|def|1',
        '|turn|3',
        '|cant|p1a: Cloyster|par',
        '|move|p2a: Rattata|Tail Whip|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|def|1',
        '|turn|4',
        '|move|p2a: Rattata|String Shot|p1a: Cloyster',
        '|-unboost|p1a: Cloyster|spe|1',
        '|cant|p1a: Cloyster|par',
        '|turn|5',
      ]);
    }
  });

  test('Stat down modifier overflow glitch', () => {
    const proc = SECONDARY(ranged(85, 256) - 1);
    // 342 -> 1026
    {
      const spc342 = {...evs, spa: 12, spd: 12};
      const battle = startBattle([HIT, NO_CRIT, MIN_DMG, proc, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Porygon', level: 58, moves: ['Recover', 'Psychic']},
      ], [
        {species: 'Mewtwo', level: 99, evs: spc342, moves: ['Amnesia', 'Recover']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(342);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(684);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(2);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(4);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(5);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 2);
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(1026);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(4);

      // Division by 0
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-boost|p2a: Mewtwo|spd|2',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|2',
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-boost|p2a: Mewtwo|spd|2',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|3',
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-unboost|p2a: Mewtwo|spa|1',
        '|-boost|p2a: Mewtwo|spd|2',
        '|-unboost|p2a: Mewtwo|spd|1',
        '|-fail|p2a: Mewtwo',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|4',
        '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
        '|-fail|p2a: Mewtwo',
        '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
        '|-resisted|p2a: Mewtwo',
        '|-damage|p2a: Mewtwo|408/410',
        '|-unboost|p2a: Mewtwo|spa|1',
        '|-unboost|p2a: Mewtwo|spd|1',
        '|turn|5',
        '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
        '|-heal|p2a: Mewtwo|410/410',
        '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
        '|-resisted|p2a: Mewtwo',
        '|-damage|p2a: Mewtwo|0 fnt',
        '|faint|p2a: Mewtwo',
        '|win|Player 1',
      ]);
    }
    // 343 -> 1029
    {
      const battle = startBattle([HIT, NO_CRIT, MIN_DMG, proc, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Porygon', level: 58, moves: ['Recover', 'Psychic']},
      ], [
        {species: 'Mewtwo', moves: ['Amnesia', 'Recover']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(343);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(686);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(2);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(4);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(5);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 2);
      expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(1029);
      expect(battle.p2.pokemon[0].boosts.spa).toBe(4);

      // Overflow means Mewtwo gets KOed
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      verify(battle, [
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-boost|p2a: Mewtwo|spd|2',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|2',
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-boost|p2a: Mewtwo|spd|2',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|3',
        '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
        '|-boost|p2a: Mewtwo|spa|2',
        '|-unboost|p2a: Mewtwo|spa|1',
        '|-boost|p2a: Mewtwo|spd|2',
        '|-unboost|p2a: Mewtwo|spd|1',
        '|-fail|p2a: Mewtwo',
        '|move|p1a: Porygon|Recover|p1a: Porygon',
        '|-fail|p1a: Porygon',
        '|turn|4',
        '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
        '|-fail|p2a: Mewtwo',
        '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
        '|-resisted|p2a: Mewtwo',
        '|-damage|p2a: Mewtwo|350/352',
        '|-unboost|p2a: Mewtwo|spa|1',
        '|-unboost|p2a: Mewtwo|spd|1',
        '|turn|5',
        '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
        '|-heal|p2a: Mewtwo|352/352',
        '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
        '|-resisted|p2a: Mewtwo',
        '|-damage|p2a: Mewtwo|0 fnt',
        '|faint|p2a: Mewtwo',
        '|win|Player 1',
      ]);
    }
  });

  test('Struggle bypassing / Switch PP underflow', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, MIN_WRAP, HIT, NO_CRIT, MIN_DMG, REWRAP], [
      {species: 'Victreebel', evs, moves: ['Wrap', 'Vine Whip']},
      {species: 'Seel', evs, moves: ['Bubble']},
    ], [
      {species: 'Kadabra', evs, moves: ['Splash']},
      {species: 'Mr. Mime', evs, moves: ['Splash']},
    ], b => {
      b.p1.pokemon[0].moveSlots[0].pp = 1;
    });

    const kadabra = battle.p2.pokemon[0].hp;
    const mrmime = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(kadabra - 22);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(63);
    expect(battle.p2.pokemon[0].hp).toBe(mrmime - 16);

    verify(battle, [
      '|switch|p1a: Victreebel|Victreebel|363/363',
      '|switch|p2a: Kadabra|Kadabra|283/283',
      '|turn|1',
      '|move|p2a: Kadabra|Splash|p2a: Kadabra',
      '|-nothing',
      '|move|p1a: Victreebel|Wrap|p2a: Kadabra',
      '|-damage|p2a: Kadabra|261/283',
      '|turn|2',
      '|switch|p2a: Mr. Mime|Mr. Mime|283/283',
      '|move|p1a: Victreebel|Wrap|p2a: Mr. Mime',
      '|-damage|p2a: Mr. Mime|267/283',
      '|turn|3',
    ]);
  });

  test('Trapping sleep glitch', () => {
    const battle = startBattle([HIT, NO_CRIT, MIN_DMG, MIN_WRAP, HIT, SLP(5), HIT], [
      {species: 'Weepinbell', evs, moves: ['Wrap', 'Sleep Powder']},
      {species: 'Gloom', evs, moves: ['Absorb']},
    ], [
      {species: 'Sandshrew', evs, moves: ['Scratch', 'Sand Attack']},
      {species: 'Magnemite', evs, moves: ['Thunder Shock', 'Sonic Boom']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 11);
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 11);
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 2', 'switch 2');
    expect(battle.p2.pokemon[0].status).toBe('slp');
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(battle.p2.pokemon[0].statusState.time).toBe(5);

    // Should not have a turn, can only pass!
    battle.makeChoices('move 2', 'move 1');
    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);
    // expect(battle.p2.pokemon[0].statusState.time).toBe(5);
    expect(battle.p2.pokemon[0].statusState.time).toBe(4);

    verify(battle, [
      '|move|p1a: Weepinbell|Wrap|p2a: Sandshrew',
      '|-damage|p2a: Sandshrew|292/303',
      '|cant|p2a: Sandshrew|partiallytrapped',
      '|turn|2',
      '|move|p1a: Weepinbell|Wrap|p2a: Sandshrew|[from]Wrap',
      '|-damage|p2a: Sandshrew|281/303',
      '|cant|p2a: Sandshrew|partiallytrapped',
      '|turn|3',
      '|switch|p2a: Magnemite|Magnemite|253/253',
      '|move|p1a: Weepinbell|Sleep Powder|p2a: Magnemite',
      '|-status|p2a: Magnemite|slp|[from] move: Sleep Powder',
      '|turn|4',
      '|move|p1a: Weepinbell|Sleep Powder|p2a: Magnemite',
      '|-fail|p2a: Magnemite|slp',
      '|cant|p2a: Magnemite|slp',
      '|turn|5',
    ]);
  });

  test('Partial trapping move Mirror Move glitch', () => {
    const battle = startBattle([MISS, HIT, NO_CRIT, MAX_DMG, MIN_WRAP],
      [{species: 'Pidgeot', evs, moves: ['Agility', 'Mirror Move']}],
      [{species: 'Moltres', evs, moves: ['Leer', 'Fire Spin']},
        {species: 'Drowzee', evs, moves: ['Pound']}]);

    const p2hp1 = battle.p2.pokemon[0].hp;
    const p2hp2 = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 2');
    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 2', 'switch 2');

    expect(battle.p2.pokemon[0].hp).toEqual(p2hp2);
    expect(battle.p2.pokemon[1].hp).toEqual(p2hp1 - 5);

    verify(battle, [
      '|move|p1a: Pidgeot|Agility|p1a: Pidgeot',
      '|-boost|p1a: Pidgeot|spe|2',
      '|move|p2a: Moltres|Fire Spin|p1a: Pidgeot|[miss]',
      '|-miss|p2a: Moltres',
      '|turn|2',
      '|move|p1a: Pidgeot|Mirror Move|p1a: Pidgeot',
      '|move|p1a: Pidgeot|Fire Spin|p2a: Moltres|[from]Mirror Move',
      '|-resisted|p2a: Moltres',
      '|-damage|p2a: Moltres|378/383',
      '|cant|p2a: Moltres|partiallytrapped',
      '|turn|3',
      '|switch|p2a: Drowzee|Drowzee|323/323',
      '|move|p1a: Pidgeot|Mirror Move|p1a: Pidgeot',
      '|-fail|p1a: Pidgeot',
      '|turn|4',
    ]);
  });

  test('Rage + Substitute bug', () => {
    const battle = startBattle([
      HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG,
    ], [
      {species: 'Jigglypuff', evs, moves: ['Splash', 'Tackle']},
    ], [
      {species: 'Electabuzz', evs, moves: ['Substitute', 'Rage']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 28);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    // expect(battle.p2.pokemon[0].boosts.atk).toBe(1);
    expect(battle.p2.pokemon[0].boosts.atk).toBe(0);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 28);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    // expect(battle.p2.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.atk).toBe(0);

    verify(battle, [
      '|move|p2a: Electabuzz|Substitute|p2a: Electabuzz',
      '|-start|p2a: Electabuzz|Substitute',
      '|-damage|p2a: Electabuzz|250/333',
      '|move|p1a: Jigglypuff|Splash|p1a: Jigglypuff',
      '|-nothing',
      '|turn|2',
      '|move|p2a: Electabuzz|Rage|p1a: Jigglypuff',
      '|-damage|p1a: Jigglypuff|405/433',
      '|move|p1a: Jigglypuff|Tackle|p2a: Electabuzz',
      '|-activate|p2a: Electabuzz|Substitute|[damage]',
      '|turn|3',
      '|move|p2a: Electabuzz|Rage|p1a: Jigglypuff|[from]Rage',
      '|-damage|p1a: Jigglypuff|377/433',
      '|move|p1a: Jigglypuff|Tackle|p2a: Electabuzz',
      '|-crit|p2a: Electabuzz',
      '|-end|p2a: Electabuzz|Substitute',
      '|turn|4',
    ]);
  });

  test('Rage stat modification error bug', () => {
    const battle = startBattle([HIT, PAR_CAN, HIT, PAR_CAN, HIT, NO_CRIT, MIN_DMG, PAR_CAN, HIT], [
      {species: 'Charizard', evs, moves: ['Glare', 'Rage']},
    ], [
      {species: 'Sandshrew', evs, moves: ['Stun Spore', 'Seismic Toss']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(298);
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(178);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(74);
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(44);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 100);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 15);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(1);
    expect(battle.p1.pokemon[0].modifiedStats!.spe).toBe(74);
    // expect(battle.p2.pokemon[0].modifiedStats.spe).toBe(11);
    expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(44);

    verify(battle, [
      '|move|p1a: Charizard|Glare|p2a: Sandshrew',
      '|-status|p2a: Sandshrew|par',
      '|move|p2a: Sandshrew|Stun Spore|p1a: Charizard',
      '|-status|p1a: Charizard|par',
      '|turn|2',
      '|move|p1a: Charizard|Rage|p2a: Sandshrew',
      '|-damage|p2a: Sandshrew|288/303 par',
      '|move|p2a: Sandshrew|Seismic Toss|p1a: Charizard',
      '|-damage|p1a: Charizard|259/359 par',
      '|-boost|p1a: Charizard|atk|1|[from] Rage',
      '|turn|3',
    ]);
  });

  test('Rage and Thrash / Petal Dance accuracy bug', () => {
    const hit = (n: number) => ({...HIT, value: ranged(n, 256) - 1});
    const miss = (n: number) => ({...HIT, value: hit(n).value + 1});
    const battle = startBattle([
      THRASH(4), hit(255), NO_CRIT, MIN_DMG, hit(168), NO_CRIT, MIN_DMG, miss(84),
    ], [
      {species: 'Nidoking', evs, moves: ['Thrash']},
    ], [
      {species: 'Onix', evs, moves: ['Double Team']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // 255 -> 168
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    // 168 -> 84
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    // should miss!
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Nidoking|Thrash|p2a: Onix',
      '|-resisted|p2a: Onix',
      '|-damage|p2a: Onix|251/273',
      '|move|p2a: Onix|Double Team|p2a: Onix',
      '|-boost|p2a: Onix|evasion|1',
      '|turn|2',
      '|move|p1a: Nidoking|Thrash|p2a: Onix|[from]Thrash',
      '|-resisted|p2a: Onix',
      '|-damage|p2a: Onix|229/273',
      '|move|p2a: Onix|Double Team|p2a: Onix',
      '|-boost|p2a: Onix|evasion|1',
      '|turn|3',
      '|move|p1a: Nidoking|Thrash|p2a: Onix|[from]Thrash|[miss]',
      '|-miss|p1a: Nidoking',
      '|move|p2a: Onix|Double Team|p2a: Onix',
      '|-boost|p2a: Onix|evasion|1',
      '|turn|4',
    ]);
  });

  test('Substitute HP drain bug', () => {
    {
      const battle = startBattle([HIT, NO_CRIT, MIN_DMG, HIT, HIT, NO_CRIT, MIN_DMG], [
        {species: 'Butterfree', evs, moves: ['Mega Drain']},
      ], [
        {species: 'Jolteon', evs, moves: ['Substitute', 'Sonic Boom']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 83);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 20 + 12);

      verify(battle, [
        '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
        '|-start|p2a: Jolteon|Substitute',
        '|-damage|p2a: Jolteon|250/333',
        '|move|p1a: Butterfree|Mega Drain|p2a: Jolteon',
        '|-activate|p2a: Jolteon|Substitute|[damage]',
        '|turn|2',
        '|move|p2a: Jolteon|Sonic Boom|p1a: Butterfree',
        '|-damage|p1a: Butterfree|303/323',
        '|move|p1a: Butterfree|Mega Drain|p2a: Jolteon',
        '|-activate|p2a: Jolteon|Substitute|[damage]',
        '|-heal|p1a: Butterfree|315/323|[from] drain|[of] p2a: Jolteon',
        '|turn|3',
      ]);
    }
    {
      const battle = startBattle([HIT, NO_CRIT], [
        {species: 'Sandshrew', level: 1, evs, moves: ['Absorb']},
      ], [
        {species: 'Venusaur', evs, moves: ['Substitute']},
      ]);

      battle.p1.active[0].hp = 1;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      // expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p1.pokemon[0].hp).toBe(2);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 90);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(91);

      verify(battle, [
        '|move|p2a: Venusaur|Substitute|p2a: Venusaur',
        '|-start|p2a: Venusaur|Substitute',
        '|-damage|p2a: Venusaur|273/363',
        '|move|p1a: Sandshrew|Absorb|p2a: Venusaur',
        '|-resisted|p2a: Venusaur',
        '|-activate|p2a: Venusaur|Substitute|[damage]',
        '|-heal|p1a: Sandshrew|2/12|[from] drain|[of] p2a: Venusaur',
        '|turn|2',
      ]);
    }
  });

  test('Substitute 1/4 HP glitch', () => {
    const battle = startBattle([], [
      {species: 'Pidgey', level: 3, moves: ['Substitute']},
      {species: 'Pikachu', level: 6, moves: ['Substitute']},
    ], [
      {species: 'Rattata', level: 4, moves: ['Focus Energy']},
    ]);

    battle.p1.pokemon[0].hp = 4;
    battle.p1.pokemon[1].hp = 5;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 2', '');

    // Due to rounding, this should also cause the 1/4 HP glitch
    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p1.pokemon[0].hp).toBe(5);

    verify(battle, [
      '|move|p2a: Rattata|Focus Energy|p2a: Rattata',
      '|-start|p2a: Rattata|move: Focus Energy',
      '|move|p1a: Pidgey|Substitute|p1a: Pidgey',
      '|-start|p1a: Pidgey|Substitute',
      '|-damage|p1a: Pidgey|0 fnt',
      '|faint|p1a: Pidgey',
      '|switch|p1a: Pikachu|Pikachu, L6|5/22',
      '|turn|2',
      '|move|p1a: Pikachu|Substitute|p1a: Pikachu',
      '|-fail|p1a: Pikachu|move: Substitute|[weak]',
      '|move|p2a: Rattata|Focus Energy|p2a: Rattata',
      '|turn|3',
    ]);
  });

  test('Substitute + Confusion glitch', () => {
    // Confused Pokémon has Substitute
    {
      const battle = startBattle([HIT, CFZ(5), CFZ_CAN, HIT, CFZ_CANT, HIT, CFZ_CANT], [
        {species: 'Bulbasaur', level: 6, evs, moves: ['Substitute', 'Growl', 'Harden']},
      ], [
        {species: 'Zubat', level: 10, evs, moves: ['Supersonic']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 6);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(7);

      // If Substitute is up, opponent's sub takes damage for Confusion self-hit or 0 damage
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(7);

      // Pokémon Showdown incorrectly applies damage to the confused Pokémon's sub when
      // selecting a self-targeting move
      battle.makeChoices('move 3', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      // expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(7);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(2);

      verify(battle, [
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|confusion',
        '|-activate|p1a: Bulbasaur|confusion',
        '|move|p1a: Bulbasaur|Substitute|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|Substitute',
        '|-damage|p1a: Bulbasaur|20/26',
        '|turn|2',
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-fail|p1a: Bulbasaur',
        '|-activate|p1a: Bulbasaur|confusion',
        '|turn|3',
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-fail|p1a: Bulbasaur',
        '|-activate|p1a: Bulbasaur|confusion',
        '|-activate|p1a: Bulbasaur|Substitute|[damage]',
        '|turn|4',
      ]);
    }
    // Both Pokémon have Substitutes
    {
      const battle = startBattle([
        HIT, NO_CRIT, MIN_DMG, HIT, CFZ(5), CFZ_CANT, CFZ_CAN, CFZ_CANT,
      ], [
        {species: 'Bulbasaur', level: 6, evs, moves: ['Substitute', 'Tackle']},
      ], [
        {species: 'Zubat', level: 10, evs, moves: ['Supersonic', 'Substitute']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;
      const sub1 = 7;
      let sub2 = 10;

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= (sub2 - 1));
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2 -= 3);

      // Opponent's sub doesn't take damage because confused user doesn't have one
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= (sub1 - 1));
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(sub1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2);

      // Opponent's sub takes damage for Confusion self-hit if both have one
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(sub1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2 -= 5);

      verify(battle, [
        '|move|p2a: Zubat|Substitute|p2a: Zubat',
        '|-start|p2a: Zubat|Substitute',
        '|-damage|p2a: Zubat|28/37',
        '|move|p1a: Bulbasaur|Tackle|p2a: Zubat',
        '|-activate|p2a: Zubat|Substitute|[damage]',
        '|turn|2',
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|confusion',
        '|-activate|p1a: Bulbasaur|confusion',
        '|-damage|p1a: Bulbasaur|21/26|[from] confusion',
        '|turn|3',
        '|move|p2a: Zubat|Substitute|p2a: Zubat',
        '|-fail|p2a: Zubat|move: Substitute',
        '|-activate|p1a: Bulbasaur|confusion',
        '|move|p1a: Bulbasaur|Substitute|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|Substitute',
        '|-damage|p1a: Bulbasaur|15/26',
        '|turn|4',
        '|move|p2a: Zubat|Substitute|p2a: Zubat',
        '|-fail|p2a: Zubat|move: Substitute',
        '|-activate|p1a: Bulbasaur|confusion',
        '|-activate|p2a: Zubat|Substitute|[damage]',
        '|turn|5',
      ]);
    }
  });

  test('Psywave infinite loop', () => {
    const PSY_MAX = {key: 'data/mods/gen1/moves.ts:576:32', value: MAX};
    const battle = startBattle([HIT, HIT, PSY_MAX], [
      {species: 'Charmander', evs, level: 1, moves: ['Psywave']},
    ], [
      {species: 'Rattata', evs, level: 3, moves: ['Tail Whip']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

    verify(battle, [
      '|move|p2a: Rattata|Tail Whip|p1a: Charmander',
      '|-unboost|p1a: Charmander|def|1',
      '|move|p1a: Charmander|Psywave|p2a: Rattata',
      '|turn|2',
    ]);
  });

  test('Transform + Mirror Move/Metronome PP error', () => {
    // PP
    {
      const battle = startBattle([HIT, TIE(2), HIT, HIT], [
        {species: 'Mew', evs, moves: ['Transform', 'Ice Beam', 'Psychic']},
      ], [
        {species: 'Spearow', evs, moves: ['Growl', 'Leer', 'Mirror Move']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].baseMoveSlots[2].pp).toBe(16);

      battle.makeChoices('move 3', 'move 1');
      // expect(battle.p1.pokemon[0].baseMoveSlots[2].pp).toBe(17);
      expect(battle.p1.pokemon[0].baseMoveSlots[2].pp).toBe(16);

      verify(battle, [
        '|move|p1a: Mew|Transform|p2a: Spearow',
        '|-transform|p1a: Mew|p2a: Spearow',
        '|move|p2a: Spearow|Growl|p1a: Mew',
        '|-unboost|p1a: Mew|atk|1',
        '|turn|2',
        '|move|p2a: Spearow|Growl|p1a: Mew',
        '|-unboost|p1a: Mew|atk|1',
        '|move|p1a: Mew|Mirror Move|p1a: Mew',
        '|move|p1a: Mew|Growl|p2a: Spearow|[from]Mirror Move',
        '|-unboost|p2a: Spearow|atk|1',
        '|turn|3',
      ]);
    }
    // Struggle softlock
    {
      const battle = startBattle([HIT, TIE(1), HIT, HIT, HIT, MISS, HIT, NO_CRIT, MIN_DMG, HIT], [
        {species: 'Ditto', level: 34, evs, moves: ['Transform']},
        {species: 'Koffing', evs, moves: ['Explosion']},
      ], [
        {species: 'Spearow', level: 23, evs, moves: ['Growl', 'Leer', 'Mirror Move']},
      ], b => {
        b.p1.pokemon[0].moveSlots[0].pp = 1;
      });

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1']);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 3', 'move 1');
      battle.makeChoices('switch 2', 'move 1');
      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('switch 2', '');

      // expect(choices(battle, 'p1')).toEqual([]);
      expect(choices(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 1');

      verify(battle, [
        '|switch|p1a: Ditto|Ditto, L34|108/108',
        '|switch|p2a: Spearow|Spearow, L23|72/72',
        '|turn|1',
        '|move|p1a: Ditto|Transform|p2a: Spearow',
        '|-transform|p1a: Ditto|p2a: Spearow',
        '|move|p2a: Spearow|Growl|p1a: Ditto',
        '|-unboost|p1a: Ditto|atk|1',
        '|turn|2',
        '|move|p1a: Ditto|Mirror Move|p1a: Ditto',
        '|move|p1a: Ditto|Growl|p2a: Spearow|[from]Mirror Move',
        '|-unboost|p2a: Spearow|atk|1',
        '|move|p2a: Spearow|Growl|p1a: Ditto',
        '|-unboost|p1a: Ditto|atk|1',
        '|turn|3',
        '|switch|p1a: Koffing|Koffing|283/283',
        '|move|p2a: Spearow|Growl|p1a: Koffing',
        '|-unboost|p1a: Koffing|atk|1',
        '|turn|4',
        '|move|p1a: Koffing|Explosion|p2a: Spearow|[miss]',
        '|-miss|p1a: Koffing',
        '|faint|p1a: Koffing',
        '|switch|p1a: Ditto|Ditto, L34|108/108',
        '|turn|5',
        '|move|p1a: Ditto|Struggle|p2a: Spearow',
        '|-damage|p2a: Spearow|38/72',
        '|-damage|p1a: Ditto|91/108|[from] Recoil|[of] p2a: Spearow',
        '|move|p2a: Spearow|Growl|p1a: Ditto',
        '|-unboost|p1a: Ditto|atk|1',
        '|turn|6',
      ]);
    }
    // Disable softlock
    {
      const battle = startBattle([HIT, TIE(1), HIT, HIT, TIE(1), HIT], [
        {species: 'Ditto', level: 34, evs, moves: ['Transform']},
        {species: 'Koffing', evs, moves: ['Explosion']},
      ], [
        {species: 'Spearow', level: 23, evs, moves: ['Growl', 'Leer', 'Mirror Move']},
        {species: 'Drowzee', level: 23, evs, moves: ['Disable']},
      ], b => {
        b.p1.pokemon[0].moveSlots[0].pp = 1;
      });

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 3', 'move 1');
      battle.makeChoices('switch 2', 'switch 2');
      battle.makeChoices('switch 2', 'move 1');

      verify(battle, [
        '|switch|p1a: Ditto|Ditto, L34|108/108',
        '|switch|p2a: Spearow|Spearow, L23|72/72',
        '|turn|1',
        '|move|p1a: Ditto|Transform|p2a: Spearow',
        '|-transform|p1a: Ditto|p2a: Spearow',
        '|move|p2a: Spearow|Growl|p1a: Ditto',
        '|-unboost|p1a: Ditto|atk|1',
        '|turn|2',
        '|move|p1a: Ditto|Mirror Move|p1a: Ditto',
        '|move|p1a: Ditto|Growl|p2a: Spearow|[from]Mirror Move',
        '|-unboost|p2a: Spearow|atk|1',
        '|move|p2a: Spearow|Growl|p1a: Ditto',
        '|-unboost|p1a: Ditto|atk|1',
        '|turn|3',
        '|switch|p1a: Koffing|Koffing|283/283',
        '|switch|p2a: Drowzee|Drowzee, L23|81/81',
        '|turn|4',
        '|switch|p1a: Ditto|Ditto, L34|108/108',
        '|move|p2a: Drowzee|Disable|p1a: Ditto',
        '|-fail|p1a: Ditto',
        '|turn|5',
      ]);
    }
  });
});
