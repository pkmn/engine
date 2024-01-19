import {Generations} from '@pkmn/data';
import {Battle, Dex, ID, PRNG} from '@pkmn/sim';

import {Options} from '../benchmark';
import {
  Choices, FixedRNG, MAX, MIN, ROLLS, createStartBattle, formatFor, ranged, verify,
} from '../showdown';

const gens = new Generations(Dex as any);
const gen = gens.get(2);
const choices = Choices.get(gen);
const startBattle = createStartBattle(gen);

const {HIT, MISS, CRIT, NO_CRIT, MIN_DMG, MAX_DMG, TIE, DRAG} = ROLLS.basic({
  hit: 'data/mods/gen2/scripts.ts:253:62',
  crit: 'data/mods/gen2/scripts.ts:552:27',
  dmg: 'data/mods/gen2/scripts.ts:711:27',
});

const QKC = {key: 'sim/battle.ts:1627:49', value: MAX};
const QKCs = (n: number) => Array(n).fill(QKC);
const SECONDARY = (value: number) => ({key: 'data/mods/gen2/scripts.ts:464:66', value});
const PROC_SEC = SECONDARY(MIN);
const SLP = (n: number) =>
  ({key: 'data/mods/gen2/conditions.ts:37:33', value: ranged(n, 8 - 2) - 1});
const DISABLE_DURATION = (n: number) =>
  ({key: 'data/mods/gen3/moves.ts:207:17', value: ranged(n - 2, 6) - 1});
const PAR_CANT = {key: 'data/mods/gen2/conditions.ts:21:13', value: ranged(1, 4) - 1};
const PAR_CAN = {...PAR_CANT, value: PAR_CANT.value + 1};
const FRZ = SECONDARY(ranged(25, 256) - 1);
const THAW = {key: 'data/mods/gen2/conditions.ts:77:13', value: ranged(25, 256) - 1};
const NO_THAW = {...THAW, value: THAW.value + 1};
const CFZ = (n: number) =>
  ({key: 'data/mods/gen2/conditions.ts:127:34', value: ranged(n - 1, 6 - 2) - 1});
const CFZ_CAN = {key: 'data/mods/gen2/conditions.ts:137:13', value: ranged(1, 2) - 1};
const CFZ_CANT = {...CFZ_CAN, value: CFZ_CAN.value + 1};
const THRASH = (n: 2 | 3) =>
  ({key: 'data/mods/gen2/conditions.ts:169:16', value: ranged(n, 4) - 1});
const MIN_WRAP = {key: 'data/mods/gen2/conditions.ts:160:16', value: MIN};
const METRONOME = ROLLS.metronome(gen, [
  'Counter', 'Destiny Bond', 'Detect', 'Endure', 'Metronome', 'Mimic',
  'Mirror Coat', 'Protect', 'Sketch', 'Sleep Talk', 'Struggle', 'Thief',
]);

const evs = {hp: 255, atk: 255, def: 255, spa: 255, spd: 255, spe: 255};
const slow = {...evs, spe: 0};

describe('Gen 2', () => {
  // General

  test('start (first fainted)', () => {
    const battle = startBattle([QKC], [
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
      '|switch|p1a: Pikachu|Pikachu, M|0 fnt',
      '|switch|p2a: Charmander|Charmander, M|0 fnt',
      '|turn|1',
    ]);
  });

  test('start (all fainted)', () => {
    // Win
    {
      const battle = startBattle([QKC], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p2.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur, M|293/293',
        '|switch|p2a: Charmander|Charmander, M|0 fnt',
        '|turn|1',
      ]);
    }
    // Lose
    {
      const battle = startBattle([QKC], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p1.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur, M|0 fnt',
        '|switch|p2a: Charmander|Charmander, M|281/281',
        '|turn|1',
      ]);
    }
    // Tie
    {
      const battle = startBattle([QKC], [
        {species: 'Bulbasaur', evs, moves: ['Tackle']},
      ], [
        {species: 'Charmander', evs, moves: ['Scratch']},
      ], b => {
        b.p1.pokemon[0].hp = 0;
        b.p2.pokemon[0].hp = 0;
      });

      // lol...
      verify(battle, [
        '|switch|p1a: Bulbasaur|Bulbasaur, M|0 fnt',
        '|switch|p2a: Charmander|Charmander, M|0 fnt',
        '|turn|1',
      ]);
    }
  });

  test('switching (order)', () => {
    const battle = startBattle(QKCs(7),
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
      '|switch|p1a: Abra|Abra, L30, M|64/64',
      '|switch|p2a: Gastly|Gastly, L2, M|13/13',
      '|turn|7',
    ]);
  });

  test('turn order (priority)', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, QKC,
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
      const battle = startBattle([
        QKC, TIE(1), HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MAX_DMG, QKC,
      ], [
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
      const battle = startBattle([
        QKC, TIE(1), HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, QKC,
      ], [
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
        '|-mustrecharge|p2a: Tauros',
        '|faint|p1a: Tauros',
        '|switch|p1a: Tauros|Tauros, M|353/353',
        '|turn|2',
      ]);
    }
    // Switch vs. Switch
    {
      const battle = startBattle([QKC, TIE(2), QKC], [
        {species: 'Zapdos', evs, moves: ['Drill Peck']},
        {species: 'Dodrio', evs, moves: ['Fury Attack']},
      ], [
        {species: 'Raichu', evs, moves: ['Thunderbolt']},
        {species: 'Mew', evs, moves: ['Psychic']},
      ]);

      battle.makeChoices('switch 2', 'switch 2');

      verify(battle, [
        '|switch|p2a: Mew|Mew|403/403',
        '|switch|p1a: Dodrio|Dodrio, M|323/323',
        '|turn|2',
      ]);
    }
    // Move vs. Switch
    {
      const battle = startBattle([QKC, HIT, NO_CRIT, MIN_DMG, QKC], [
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
        '|switch|p2a: Alakazam|Alakazam, M|313/313',
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
        QKC, TIE(2), METRONOME('Fly'), METRONOME('Dig'),
        QKC, TIE(1), HIT, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
        METRONOME('Swift'), NO_CRIT, MIN_DMG,
        QKC, METRONOME('Petal Dance'), NO_CRIT, MIN_DMG, THRASH(3), QKC,
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
      expect(battle.p2.pokemon[0].hp).toBe(p2hp2 -= 30);

      verify(battle, [
        '|move|p2a: Clefable|Metronome|p2a: Clefable',
        '|move|p2a: Clefable|Fly||[from]Metronome|[still]',
        '|-prepare|p2a: Clefable|Fly',
        '|move|p1a: Clefable|Metronome|p1a: Clefable',
        '|move|p1a: Clefable|Dig||[from]Metronome|[still]',
        '|-prepare|p1a: Clefable|Dig',
        '|turn|2',
        '|move|p1a: Clefable|Dig|p2a: Clefable|[miss]',
        '|-miss|p1a: Clefable',
        '|move|p2a: Clefable|Fly|p1a: Clefable',
        '|-damage|p1a: Clefable|343/393',
        '|turn|3',
        '|move|p1a: Clefable|Quick Attack|p2a: Clefable',
        '|-damage|p2a: Clefable|350/393',
        '|move|p2a: Clefable|Metronome|p2a: Clefable',
        '|move|p2a: Clefable|Swift|p1a: Clefable|[from]Metronome',
        '|-damage|p1a: Clefable|279/393',
        '|turn|4',
        '|switch|p2a: Farfetch’d|Farfetch’d, M|307/307',
        '|move|p1a: Clefable|Metronome|p1a: Clefable',
        '|move|p1a: Clefable|Petal Dance|p2a: Farfetch’d|[from]Metronome',
        '|-resisted|p2a: Farfetch’d',
        '|-damage|p2a: Farfetch’d|277/307',
        '|turn|5',
      ]);
    }
    // beforeTurnMove
    {
      const NOP = TIE(2);
      const battle = startBattle([QKC, NOP, TIE(1), QKC], [
        {species: 'Chansey', evs, moves: ['Counter']},
      ], [
        {species: 'Chansey', evs, moves: ['Mirror Coat']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      verify(battle, [
        '|move|p1a: Chansey|Counter|p2a: Chansey',
        '|-fail|p2a: Chansey',
        '|move|p2a: Chansey|Mirror Coat|p1a: Chansey',
        '|-fail|p1a: Chansey',
        '|turn|2',
      ]);
    }
  });
  test('turn order (switch vs. move)', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC], [
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
      '|switch|p2a: Vulpix|Vulpix, M|279/279',
      '|move|p1a: Raticate|Quick Attack|p2a: Vulpix',
      '|-damage|p2a: Vulpix|215/279',
      '|turn|2',
      '|switch|p1a: Rattata|Rattata, M|263/263',
      '|move|p2a: Vulpix|Quick Attack|p1a: Rattata',
      '|-damage|p1a: Rattata|231/263',
      '|turn|3',
    ]);
  });

  test('PP deduction', () => {
    const battle = startBattle([QKC, QKC, QKC], [
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
    const battle = startBattle([QKC, hit, CRIT, MAX_DMG, miss, QKC], [
      {species: 'Hitmonchan', evs, moves: ['Mega Punch']},
    ], [
      {species: 'Machamp', evs, moves: ['Mega Punch']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 162);

    verify(battle, [
      '|move|p1a: Hitmonchan|Mega Punch|p2a: Machamp',
      '|-crit|p2a: Machamp',
      '|-damage|p2a: Machamp|221/383',
      '|move|p2a: Machamp|Mega Punch|p1a: Hitmonchan|[miss]',
      '|-miss|p2a: Machamp',
      '|turn|2',
    ]);
  });

  test('damage calc', () => {
    const no_brn = SECONDARY(ranged(25, 256));
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, no_brn, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Starmie', evs, moves: ['Water Gun', 'Thunderbolt']},
    ], [
      {species: 'Golem', evs, moves: ['Fire Blast', 'Strength']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // STAB super effective non-critical min damage vs. non-STAB resisted critical max damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 79);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 228);

    // immune vs. normal
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 68);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Starmie|Water Gun|p2a: Golem',
      '|-supereffective|p2a: Golem',
      '|-damage|p2a: Golem|135/363',
      '|move|p2a: Golem|Fire Blast|p1a: Starmie',
      '|-crit|p1a: Starmie',
      '|-resisted|p1a: Starmie',
      '|-damage|p1a: Starmie|244/323',
      '|turn|2',
      '|move|p1a: Starmie|Thunderbolt|p2a: Golem',
      '|-immune|p2a: Golem',
      '|move|p2a: Golem|Strength|p1a: Starmie',
      '|-damage|p1a: Starmie|176/323',
      '|turn|3',
    ]);
  });

  test('type precedence', () => {
    const battle = startBattle([QKC, NO_CRIT, MAX_DMG, QKC], [
      {species: 'Heracross', evs, moves: ['Mach Punch']},
    ], [
      {species: 'Skarmory', evs, moves: ['Sand Attack']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // Super effective vs. Type 1 + Resist vs Type 2 of higher precedence
    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);

    verify(battle, [
      '|move|p1a: Heracross|Mach Punch|p2a: Skarmory',
      '|-damage|p2a: Skarmory|284/333',
      '|move|p2a: Skarmory|Sand Attack|p1a: Heracross',
      '|-unboost|p1a: Heracross|accuracy|1',
      '|turn|2',
    ]);
  });

  test('fainting (single)', () => {
    // Switch
    {
      const battle = startBattle([QKC, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Venusaur', evs, moves: ['Leech Seed']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Water Gun']},
        {species: 'Dratini', evs, moves: ['Dragon Rage']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      battle.p2.pokemon[0].hp = 1;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 14);
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
        '|-heal|p1a: Venusaur|349/363|[silent]',
        '|faint|p2a: Slowpoke',
      ]);
    }
    // Win
    {
      const battle = startBattle([QKC], [
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
      const battle = startBattle([QKC, NO_CRIT, MIN_DMG], [
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
      const battle = startBattle([QKC, CRIT, MAX_DMG, QKC], [
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
        '|faint|p1a: Weezing',
        '|faint|p2a: Weedle',
        '|switch|p1a: Koffing|Koffing, M|283/283',
        '|switch|p2a: Caterpie|Caterpie, M|293/293',
        '|turn|2',
      ]);
    }
    // Switch (boosted)
    {
      const battle = startBattle([QKC, QKC, NO_CRIT, MAX_DMG, QKC], [
        {species: 'Farfetch’d', evs, moves: ['Agility', 'Splash']},
        {species: 'Cubone', evs, moves: ['BoneClub']},
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
        '|-fail|p2a: Charmeleon',
        '|move|p1a: Farfetch’d|Agility|p1a: Farfetch’d',
        '|-boost|p1a: Farfetch’d|spe|2',
        '|turn|2',
        '|move|p1a: Farfetch’d|Splash|p1a: Farfetch’d',
        '|-nothing',
        '|-fail|p1a: Farfetch’d',
        '|move|p2a: Charmeleon|Explosion|p1a: Farfetch’d',
        '|-damage|p1a: Farfetch’d|0 fnt',
        '|faint|p2a: Charmeleon',
        '|faint|p1a: Farfetch’d',
        '|switch|p2a: Pikachu|Pikachu, M|273/273',
        '|switch|p1a: Cubone|Cubone, M|303/303',
        '|turn|3',
      ]);
    }
    // Switch (paralyzed)
    {
      const battle = startBattle([QKC, QKC, PAR_CAN, NO_CRIT, MAX_DMG, QKC], [
        {species: 'Farfetch’d', evs, moves: ['Thunder Wave', 'Splash']},
        {species: 'Cubone', evs, moves: ['BoneClub']},
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
        '|-fail|p2a: Charmeleon',
        '|move|p1a: Farfetch’d|Thunder Wave|p2a: Charmeleon',
        '|-status|p2a: Charmeleon|par',
        '|turn|2',
        '|move|p1a: Farfetch’d|Splash|p1a: Farfetch’d',
        '|-nothing',
        '|-fail|p1a: Farfetch’d',
        '|move|p2a: Charmeleon|Explosion|p1a: Farfetch’d',
        '|-damage|p1a: Farfetch’d|0 fnt',
        '|faint|p2a: Charmeleon',
        '|faint|p1a: Farfetch’d',
        '|switch|p2a: Pikachu|Pikachu, M|273/273',
        '|switch|p1a: Cubone|Cubone, M|303/303',
        '|turn|3',
      ]);
    }
    // Tie
    {
      const battle = startBattle([QKC, CRIT, MAX_DMG], [
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
        '|faint|p1a: Weezing',
        '|faint|p2a: Weedle',
        '|tie',
      ]);
    }
  });

  test('end turn (turn limit)', () => {
    const battle = startBattle(QKCs(999), [
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
      '|switch|p1a: Charmander|Charmander, M|281/281',
      '|switch|p2a: Pikachu|Pikachu, M|273/273',
      '|tie',
    ]);
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

  // Items

  test('ThickClub effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG,
      QKC, TIE(2), NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Marowak', item: 'Thick Club', evs, moves: ['Strength']},
    ], [
      {species: 'Teddiursa', evs, moves: ['Thief', 'Transform']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 151);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 75);

    // Only provides boost if original species is correct
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 47);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 47);

    verify(battle, [
      '|move|p1a: Marowak|Strength|p2a: Teddiursa',
      '|-damage|p2a: Teddiursa|172/323',
      '|move|p2a: Teddiursa|Thief|p1a: Marowak',
      '|-damage|p1a: Marowak|301/323',
      '|-item|p2a: Teddiursa|Thick Club|[from] move: Thief|[of] p1a: Marowak',
      '|turn|2',
      '|move|p1a: Marowak|Strength|p2a: Teddiursa',
      '|-damage|p2a: Teddiursa|97/323',
      '|move|p2a: Teddiursa|Transform|p1a: Marowak',
      '|-transform|p2a: Teddiursa|p1a: Marowak',
      '|turn|3',
      '|move|p2a: Teddiursa|Strength|p1a: Marowak',
      '|-damage|p1a: Marowak|254/323',
      '|move|p1a: Marowak|Strength|p2a: Teddiursa',
      '|-damage|p2a: Teddiursa|50/323',
      '|turn|4',
    ]);
  });

  test('LightBall effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG,
      QKC, TIE(2), NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Pikachu', item: 'Light Ball', evs, moves: ['Surf']},
    ], [
      {species: 'Ursaring', evs, moves: ['Thief', 'Transform']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 109);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 55);

    // Only provides boost if original species is correct
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 76);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 76);

    verify(battle, [
      '|move|p1a: Pikachu|Surf|p2a: Ursaring',
      '|-damage|p2a: Ursaring|274/383',
      '|move|p2a: Ursaring|Thief|p1a: Pikachu',
      '|-damage|p1a: Pikachu|233/273',
      '|-item|p2a: Ursaring|Light Ball|[from] move: Thief|[of] p1a: Pikachu',
      '|turn|2',
      '|move|p1a: Pikachu|Surf|p2a: Ursaring',
      '|-damage|p2a: Ursaring|219/383',
      '|move|p2a: Ursaring|Transform|p1a: Pikachu',
      '|-transform|p2a: Ursaring|p1a: Pikachu',
      '|turn|3',
      '|move|p2a: Ursaring|Surf|p1a: Pikachu',
      '|-damage|p1a: Pikachu|157/273',
      '|move|p1a: Pikachu|Surf|p2a: Ursaring',
      '|-damage|p2a: Ursaring|143/383',
      '|turn|4',
    ]);
  });

  test('BerserkGene effect', () => {
    const battle = startBattle([
      QKC, QKC, CFZ_CAN, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Magby', evs, moves: ['Flamethrower']},
      {species: 'Cleffa', item: 'Berserk Gene', evs, moves: ['Pound']},
    ], [
      {species: 'Smoochum', evs, moves: ['Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(256);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

    verify(battle, [
      '|switch|p1a: Cleffa|Cleffa, M|303/303',
      '|-enditem|p1a: Cleffa|Berserk Gene',
      '|-boost|p1a: Cleffa|atk|2|[from] item: Berserk Gene',
      '|-start|p1a: Cleffa|confusion',
      '|move|p2a: Smoochum|Splash|p2a: Smoochum',
      '|-nothing',
      '|-fail|p2a: Smoochum',
      '|turn|2',
      '|move|p2a: Smoochum|Splash|p2a: Smoochum',
      '|-nothing',
      '|-fail|p2a: Smoochum',
      '|-activate|p1a: Cleffa|confusion',
      '|move|p1a: Cleffa|Pound|p2a: Smoochum',
      '|-damage|p2a: Smoochum|193/293',
      '|turn|3',
    ]);
  });

  test('Stick effect', () => {
    const no_crit = {...CRIT, value: ranged(4, 16) - 1};
    const battle = startBattle([
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC,
      QKC, HIT, no_crit, MIN_DMG,
      QKC, TIE(2), HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG, QKC,
    ], [
      {species: 'Farfetch’d', item: 'Stick', evs, moves: ['Cut']},
    ], [
      {species: 'Totodile', evs, moves: ['Thief', 'Transform']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 109);

    battle.makeChoices('move 1', 'move 2');
    // expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 56);

    // Only provides boost if original species is correct
    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 61);
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 119);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 61);

    verify(battle, [
      '|move|p1a: Farfetch’d|Cut|p2a: Totodile',
      '|-crit|p2a: Totodile',
      '|-damage|p2a: Totodile|194/303',
      '|move|p2a: Totodile|Thief|p1a: Farfetch’d',
      '|-damage|p1a: Farfetch’d|282/307',
      '|-item|p2a: Totodile|Stick|[from] move: Thief|[of] p1a: Farfetch’d',
      '|turn|2',
      '|move|p1a: Farfetch’d|Cut|p2a: Totodile',
      '|-damage|p2a: Totodile|138/303',
      '|move|p2a: Totodile|Transform|p1a: Farfetch’d',
      '|-transform|p2a: Totodile|p1a: Farfetch’d',
      '|turn|3',
      '|move|p2a: Totodile|Cut|p1a: Farfetch’d',
      '|-crit|p1a: Farfetch’d',
      '|-damage|p1a: Farfetch’d|163/307',
      '|move|p1a: Farfetch’d|Cut|p2a: Totodile',
      '|-damage|p2a: Totodile|77/303',
      '|turn|4',
    ]);
  });

  test('Boost effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Azumarill', item: 'Mystic Water', evs, moves: ['Surf', 'Strength']},
    ], [
      {species: 'Azumarill', item: 'Polkadot Bow', evs: slow, moves: ['Surf', 'Strength']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 49);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 43);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 39);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 45);

    verify(battle, [
      '|move|p1a: Azumarill|Surf|p2a: Azumarill',
      '|-resisted|p2a: Azumarill',
      '|-damage|p2a: Azumarill|360/403',
      '|move|p2a: Azumarill|Strength|p1a: Azumarill',
      '|-damage|p1a: Azumarill|354/403',
      '|turn|2',
      '|move|p1a: Azumarill|Strength|p2a: Azumarill',
      '|-damage|p2a: Azumarill|315/403',
      '|move|p2a: Azumarill|Surf|p1a: Azumarill',
      '|-resisted|p1a: Azumarill',
      '|-damage|p1a: Azumarill|315/403',
      '|turn|3',
    ]);
  });

  test('BrightPowder effect', () => {
    // Mega Punch would hit if not for Bright Powder
    const hit = {...HIT, value: ranged(Math.floor(85 * 255 / 100), 256) - 1};
    const battle = startBattle([QKC, hit, MISS, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Umbreon', item: 'Bright Powder', evs, moves: ['Mega Punch', 'Splash']},
    ], [
      {species: 'Croconaw', item: 'Bright Powder', evs, moves: ['Surf', 'Swift']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    // Even 100% accurate moves can miss
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

    // Swift still hits
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 35);

    verify(battle, [
      '|move|p1a: Umbreon|Mega Punch|p2a: Croconaw|[miss]',
      '|-miss|p1a: Umbreon',
      '|move|p2a: Croconaw|Surf|p1a: Umbreon|[miss]',
      '|-miss|p2a: Croconaw',
      '|turn|2',
      '|move|p1a: Umbreon|Splash|p1a: Umbreon',
      '|-nothing',
      '|-fail|p1a: Umbreon',
      '|move|p2a: Croconaw|Swift|p1a: Umbreon',
      '|-damage|p1a: Umbreon|358/393',
      '|turn|3',
    ]);
  });

  test('MetalPowder effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG,
      QKC, TIE(1), NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Jumpluff', evs, moves: ['Cotton Spore']},
      {species: 'Ditto', item: 'Metal Powder', evs, moves: ['Transform']},
    ], [
      {species: 'Slowking', item: 'Metal Powder', evs, moves: ['Surf', 'Strength']},
    ]);

    let p1hp = battle.p1.pokemon[1].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 107);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 32);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 38);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    verify(battle, [
      '|switch|p1a: Ditto|Ditto|299/299',
      '|move|p2a: Slowking|Surf|p1a: Ditto',
      '|-damage|p1a: Ditto|192/299',
      '|turn|2',
      '|move|p1a: Ditto|Transform|p2a: Slowking',
      '|-transform|p1a: Ditto|p2a: Slowking',
      '|move|p2a: Slowking|Surf|p1a: Ditto',
      '|-resisted|p1a: Ditto',
      '|-damage|p1a: Ditto|160/299',
      '|turn|3',
      '|move|p1a: Ditto|Surf|p2a: Slowking',
      '|-resisted|p2a: Slowking',
      '|-damage|p2a: Slowking|345/393',
      '|move|p2a: Slowking|Strength|p1a: Ditto',
      '|-damage|p1a: Ditto|122/299',
      '|turn|4',
    ]);
  });

  test('QuickClaw effect', () => {
    const proc = {...QKC, value: ranged(60, 256) - 1};
    const no_proc = {...QKC, value: proc.value + 1};
    const battle = startBattle([
      no_proc, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, no_proc,
    ], [
      {species: 'Igglybuff', item: 'Quick Claw', evs, moves: ['Splash']},
    ], [
      {species: 'Natu', evs, moves: ['Peck', 'Quick Attack']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 59);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 59);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 45);

    verify(battle, [
      '|move|p2a: Natu|Peck|p1a: Igglybuff',
      '|-damage|p1a: Igglybuff|324/383',
      '|move|p1a: Igglybuff|Splash|p1a: Igglybuff',
      '|-nothing',
      '|-fail|p1a: Igglybuff',
      '|turn|2',
      '|move|p1a: Igglybuff|Splash|p1a: Igglybuff',
      '|-nothing',
      '|-fail|p1a: Igglybuff',
      '|move|p2a: Natu|Peck|p1a: Igglybuff',
      '|-damage|p1a: Igglybuff|265/383',
      '|turn|3',
      '|move|p2a: Natu|Quick Attack|p1a: Igglybuff',
      '|-damage|p1a: Igglybuff|220/383',
      '|move|p1a: Igglybuff|Splash|p1a: Igglybuff',
      '|-nothing',
      '|-fail|p1a: Igglybuff',
      '|turn|4',
    ]);
  });

  test('Flinch effect', () => {
    const item = 'Kings Rock';
    const hit3 = {key: 'data/mods/gen2/scripts.ts:265:26', value: 0x60000000};
    const rock = {key: 'data/mods/gen2/scripts.ts:464:66', value: ranged(30, 256) - 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MAX_DMG, SLP(8),
      QKC, HIT, hit3, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, rock,
      QKC, MISS, QKC, NO_CRIT, MIN_DMG, rock, QKC,
    ], [
      {species: 'Dunsparce', item, evs, moves: ['Earthquake', 'Strength', 'Fury Swipes']},
    ], [
      {species: 'Snorlax', evs, moves: ['Substitute', 'Rest', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // Not all moves are eligible for causing flinches
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 75 - 130);
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeDefined();

    // Substitute protects from flinching
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].status).toBe('slp');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 205);

    // Can flinch even when sleeping, only last roll of MultiHit can proc
    battle.makeChoices('move 3', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 21);

    battle.makeChoices('move 3', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);

    verify(battle, [
      '|move|p1a: Dunsparce|Earthquake|p2a: Snorlax',
      '|-damage|p2a: Snorlax|448/523',
      '|move|p2a: Snorlax|Substitute|p2a: Snorlax',
      '|-start|p2a: Snorlax|Substitute',
      '|-damage|p2a: Snorlax|318/523',
      '|turn|2',
      '|move|p1a: Dunsparce|Strength|p2a: Snorlax',
      '|-activate|p2a: Snorlax|Substitute|[damage]',
      '|move|p2a: Snorlax|Rest|p2a: Snorlax',
      '|-status|p2a: Snorlax|slp|[from] move: Rest',
      '|-heal|p2a: Snorlax|523/523 slp|[silent]',
      '|turn|3',
      '|move|p1a: Dunsparce|Fury Swipes|p2a: Snorlax',
      '|-activate|p2a: Snorlax|Substitute|[damage]',
      '|-end|p2a: Snorlax|Substitute',
      '|-damage|p2a: Snorlax|502/523 slp',
      '|-hitcount|p2a: Snorlax|3',
      '|cant|p2a: Snorlax|slp',
      '|turn|4',
      '|move|p1a: Dunsparce|Fury Swipes|p2a: Snorlax|[miss]',
      '|-miss|p1a: Dunsparce',
      '|cant|p2a: Snorlax|slp',
      '|turn|5',
      '|move|p1a: Dunsparce|Strength|p2a: Snorlax',
      '|-damage|p2a: Snorlax|411/523 slp',
      '|-curestatus|p2a: Snorlax|slp|[msg]',
      '|cant|p2a: Snorlax|flinch',
      '|turn|6',
    ]);
  });

  test('CriticalUp effect', () => {
    const no_crit = {...CRIT, value: ranged(2, 16) - 1};
    const battle = startBattle([
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC,
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC, QKC,
    ], [
      {species: 'Gligar', item: 'Scope Lens', evs, moves: ['Cut']},
    ], [
      {species: 'Ariados', evs, moves: ['Thief']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 28);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 74);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 56);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 38);

    verify(battle, [
      '|move|p1a: Gligar|Cut|p2a: Ariados',
      '|-crit|p2a: Ariados',
      '|-damage|p2a: Ariados|269/343',
      '|move|p2a: Ariados|Thief|p1a: Gligar',
      '|-damage|p1a: Gligar|305/333',
      '|-item|p2a: Ariados|Scope Lens|[from] move: Thief|[of] p1a: Gligar',
      '|turn|2',
      '|move|p1a: Gligar|Cut|p2a: Ariados',
      '|-damage|p2a: Ariados|231/343',
      '|move|p2a: Ariados|Thief|p1a: Gligar',
      '|-crit|p1a: Gligar',
      '|-damage|p1a: Gligar|249/333',
      '|turn|3',
    ]);
  });

  test('Leftovers effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Scizor', item: 'Leftovers', evs, moves: ['False Swipe']},
    ], [
      {species: 'Magikarp', level: 2, item: 'Leftovers', evs, moves: ['Dragon Rage']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 40 + 21);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 13 + 1);

    verify(battle, [
      '|move|p1a: Scizor|False Swipe|p2a: Magikarp',
      '|-damage|p2a: Magikarp|1/14',
      '|move|p2a: Magikarp|Dragon Rage|p1a: Scizor',
      '|-damage|p1a: Scizor|303/343',
      '|-heal|p1a: Scizor|324/343|[from] item: Leftovers',
      '|-heal|p2a: Magikarp|2/14|[from] item: Leftovers',
      '|turn|2',
    ]);
  });

  test('HealStatus effect', () => {
    const battle = startBattle([QKC, HIT, QKC, CFZ(5), QKC], [
      {species: 'Flaaffy', item: 'Bitter Berry', evs, moves: ['Thunder Wave']},
    ], [
      {species: 'Girafarig', item: 'PRZ Cure Berry', evs, moves: ['Toxic', 'Confuse Ray']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('tox');
    expect(battle.p1.pokemon[0].item).toBe('bitterberry');
    expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].item).toBe('');

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].status).toBe('tox');
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeUndefined();
    expect(battle.p2.pokemon[0].status).toBe('par');

    verify(battle, [
      '|move|p2a: Girafarig|Toxic|p1a: Flaaffy',
      '|-status|p1a: Flaaffy|tox',
      '|move|p1a: Flaaffy|Thunder Wave|p2a: Girafarig',
      '|-status|p2a: Girafarig|par',
      '|-damage|p1a: Flaaffy|322/343 tox|[from] psn',
      '|-enditem|p2a: Girafarig|PRZ Cure Berry|[eat]',
      '|-curestatus|p2a: Girafarig|par|[msg]',
      '|turn|2',
      '|move|p2a: Girafarig|Confuse Ray|p1a: Flaaffy',
      '|-start|p1a: Flaaffy|confusion',
      '|-enditem|p1a: Flaaffy|Bitter Berry|[eat]',
      '|-end|p1a: Flaaffy|confusion',
      '|move|p1a: Flaaffy|Thunder Wave|p2a: Girafarig',
      '|-status|p2a: Girafarig|par',
      '|-damage|p1a: Flaaffy|280/343 tox|[from] psn',
      '|turn|3',
    ]);
  });

  test('Berry effect', () => {
    const battle = startBattle([QKC, QKC, QKC], [
      {species: 'Togepi', evs, moves: ['Seismic Toss']},
    ], [
      {species: 'Tyrogue', item: 'Gold Berry', evs, moves: ['Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);
    expect(battle.p2.pokemon[0].item).toBe('goldberry');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 100 + 30);
    expect(battle.p2.pokemon[0].item).toBe('');

    verify(battle, [
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|move|p1a: Togepi|Seismic Toss|p2a: Tyrogue',
      '|-damage|p2a: Tyrogue|173/273',
      '|turn|2',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|move|p1a: Togepi|Seismic Toss|p2a: Tyrogue',
      '|-damage|p2a: Tyrogue|73/273',
      '|-enditem|p2a: Tyrogue|Gold Berry|[eat]',
      '|-heal|p2a: Tyrogue|103/273|[from] item: Gold Berry',
      '|turn|3',
    ]);
  });

  test('RestorePP effect', () => {
    const battle = startBattle(QKCs(34), [
      {species: 'Xatu', item: 'Mystery Berry', evs, moves: ['Teleport']},
    ], [
      {species: 'Hoppip', evs, moves: ['Splash']},
    ]);

    for (let i = 0; i < 31; i++) {
      battle.makeChoices('move 1', 'move 1');
    }
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(1);
    expect(battle.p1.pokemon[0].item).toBe('mysteryberry');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(5);
    expect(battle.p1.pokemon[0].item).toBe('');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(4);

    expect((battle.prng as FixedRNG).exhausted()).toBe(true);
  });

  test('Mail effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, PROC_SEC, QKC], [
      {species: 'Spinarak', item: 'Mail', evs, moves: ['Splash']},
    ], [
      {species: 'Houndour', evs, moves: ['Thief']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 63);

    // expect(battle.p1.pokemon[0].item).toBe('mail');
    // expect(battle.p2.pokemon[0].item).toBe('');
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p2.pokemon[0].item).toBe('mail');

    verify(battle, [
      '|move|p2a: Houndour|Thief|p1a: Spinarak',
      '|-damage|p1a: Spinarak|220/283',
      '|-item|p2a: Houndour|Mail|[from] move: Thief|[of] p1a: Spinarak',
      '|move|p1a: Spinarak|Splash|p1a: Spinarak',
      '|-nothing',
      '|-fail|p1a: Spinarak',
      '|turn|2',
    ]);
  });

  test('FocusBand effect', () => {
    const band = {key: 'data/mods/gen2/items.ts:60:13', value: ranged(30, 256) - 1};
    const no_band = {...band, value: band.value + 1};
    const confusion = SECONDARY(ranged(25, 256) - 1);
    const battle = startBattle([
      QKC, CRIT, MAX_DMG, band, confusion, CFZ(5), CFZ_CANT,
      QKC, NO_CRIT, MIN_DMG, band, NO_CRIT, MIN_DMG, no_band,
    ], [
      {species: 'Igglybuff', item: 'Focus Band', evs, moves: ['Splash']},
      {species: 'Cleffa', level: 5, item: 'Focus Band', evs, moves: ['Splash']},
    ], [
      {species: 'Espeon', evs, moves: ['Psybeam', 'Double Kick']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('switch 2', '');

    // If Focus Band activates from a multi-hit move, the holder does not faint from any hit
    battle.makeChoices('move 1', 'move 2');
    // expect(battle.p1.pokemon[0].hp).toBe(1);
    expect(battle.p1.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p2a: Espeon|Psybeam|p1a: Igglybuff',
      '|-crit|p1a: Igglybuff',
      '|-activate|p1a: Igglybuff|item: Focus Band',
      '|-damage|p1a: Igglybuff|1/383',
      '|-start|p1a: Igglybuff|confusion',
      '|-activate|p1a: Igglybuff|confusion',
      '|-damage|p1a: Igglybuff|0 fnt|[from] confusion',
      '|faint|p1a: Igglybuff',
      '|switch|p1a: Cleffa|Cleffa, L5, M|24/24',
      '|turn|2',
      '|move|p2a: Espeon|Double Kick|p1a: Cleffa',
      '|-supereffective|p1a: Cleffa',
      '|-activate|p1a: Cleffa|item: Focus Band',
      '|-damage|p1a: Cleffa|1/24',
      '|-supereffective|p1a: Cleffa',
      '|-damage|p1a: Cleffa|0 fnt',
      '|-hitcount|p1a: Cleffa|2',
      '|faint|p1a: Cleffa',
      '|win|Player 2',
    ]);
  });

  // Moves

  test('HighCritical effect', () => {
    const no_crit = {...CRIT, value: ranged(4, 16) - 1};
    // Regular non-crit roll is still a crit for high critical moves
    const battle = startBattle([QKC, no_crit, MIN_DMG, no_crit, MIN_DMG, QKC], [
      {species: 'Machop', evs, moves: ['Karate Chop']},
    ], [
      {species: 'Machop', level: 99, evs, moves: ['Strength']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 73);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 140);

    verify(battle, [
      '|move|p1a: Machop|Karate Chop|p2a: Machop',
      '|-crit|p2a: Machop',
      '|-damage|p2a: Machop|199/339',
      '|move|p2a: Machop|Strength|p1a: Machop',
      '|-damage|p1a: Machop|270/343',
      '|turn|2',
    ]);
  });

  test('FocusEnergy effect', () => {
    const no_crit = {...CRIT, value: ranged(2, 16) - 1};
    const battle = startBattle([
      QKC, no_crit, MIN_DMG, QKC, QKC, no_crit, MIN_DMG, QKC, QKC, QKC, no_crit, MIN_DMG, QKC,
    ], [
      {species: 'Scyther', evs, moves: ['Strength', 'Focus Energy', 'Baton Pass']},
      {species: 'Pinsir', evs, moves: ['Strength']},
    ], [
      {species: 'Weezing', evs, moves: ['Splash', 'Haze']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 55);

    battle.makeChoices('move 2', 'move 1');

    // Increases critical hit rate
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 108);

    // Does not get cleared by Haze
    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 3', 'move 1');

    battle.makeChoices('switch 2', '');

    // Gets transferred by Baton Pass
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 119);

    verify(battle, [
      '|move|p1a: Scyther|Strength|p2a: Weezing',
      '|-damage|p2a: Weezing|278/333',
      '|move|p2a: Weezing|Splash|p2a: Weezing',
      '|-nothing',
      '|-fail|p2a: Weezing',
      '|turn|2',
      '|move|p1a: Scyther|Focus Energy|p1a: Scyther',
      '|-start|p1a: Scyther|move: Focus Energy',
      '|move|p2a: Weezing|Splash|p2a: Weezing',
      '|-nothing',
      '|-fail|p2a: Weezing',
      '|turn|3',
      '|move|p1a: Scyther|Strength|p2a: Weezing',
      '|-crit|p2a: Weezing',
      '|-damage|p2a: Weezing|170/333',
      '|move|p2a: Weezing|Haze|p2a: Weezing',
      '|-clearallboost',
      '|turn|4',
      '|move|p1a: Scyther|Focus Energy|p1a: Scyther',
      '|-fail|p1a: Scyther',
      '|move|p2a: Weezing|Splash|p2a: Weezing',
      '|-nothing',
      '|-fail|p2a: Weezing',
      '|turn|5',
      '|move|p1a: Scyther|Baton Pass|p1a: Scyther',
      '|switch|p1a: Pinsir|Pinsir, M|333/333|[from] Baton Pass',
      '|move|p2a: Weezing|Splash|p2a: Weezing',
      '|-nothing',
      '|-fail|p2a: Weezing',
      '|turn|6',
      '|move|p1a: Pinsir|Strength|p2a: Weezing',
      '|-crit|p2a: Weezing',
      '|-damage|p2a: Weezing|51/333',
      '|move|p2a: Weezing|Splash|p2a: Weezing',
      '|-nothing',
      '|-fail|p2a: Weezing',
      '|turn|7',
    ]);
  });

  test('MultiHit effect', () => {
    const hit3 = {key: 'data/mods/gen2/scripts.ts:265:26', value: 0x60000000};
    const hit5 = {...hit3, value: MAX};
    const battle = startBattle([
      QKC, HIT, hit3, NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, CRIT, MIN_DMG,
      QKC, HIT, hit5, NO_CRIT, MAX_DMG, CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Kangaskhan', evs, moves: ['Comet Punch']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Counter']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;
    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 26 - 31 - 51 - 95);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    // Move continues after breaking the target's Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 62);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 26 - 31);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    verify(battle, [
      '|move|p1a: Kangaskhan|Comet Punch|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|357/383',
      '|-damage|p2a: Slowpoke|326/383',
      '|-crit|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|275/383',
      '|-hitcount|p2a: Slowpoke|3',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|180/383',
      '|turn|2',
      '|move|p1a: Kangaskhan|Comet Punch|p2a: Slowpoke',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|-crit|p2a: Slowpoke',
      '|-activate|p2a: Slowpoke|Substitute|[damage]',
      '|-end|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|154/383',
      '|-damage|p2a: Slowpoke|123/383',
      '|-hitcount|p2a: Slowpoke|5',
      '|move|p2a: Slowpoke|Counter|p1a: Kangaskhan',
      '|-damage|p1a: Kangaskhan|351/413',
      '|turn|3',
    ]);
  });

  test('DoubleHit effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MAX_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Marowak', evs, moves: ['Bonemerang']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 73 - 62 - 95);

    // Move continues after breaking the target's Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 62);

    verify(battle, [
      '|move|p1a: Marowak|Bonemerang|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|310/383',
      '|-damage|p2a: Slowpoke|248/383',
      '|-hitcount|p2a: Slowpoke|2',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|153/383',
      '|turn|2',
      '|move|p1a: Marowak|Bonemerang|p2a: Slowpoke',
      '|-crit|p2a: Slowpoke',
      '|-end|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|91/383',
      '|-hitcount|p2a: Slowpoke|2',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|-fail|p2a: Slowpoke',
      '|turn|3',
    ]);
  });

  test('TripleKick effect', () => {
    const hit2 = {key: 'data/mods/gen2/scripts.ts:267:26', value: ranged(2, 3 + 1)};
    const hit3 = {...hit2, value: MAX};
    const battle = startBattle([
      QKC, HIT, hit2, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, hit3, CRIT, MAX_DMG, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Hitmontop', evs, moves: ['Triple Kick']},
    ], [
      {species: 'Bayleef', evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 13 - 25 - 80);

    // Move continues after breaking the target's Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 38);

    verify(battle, [
      '|move|p1a: Hitmontop|Triple Kick|p2a: Bayleef',
      '|-damage|p2a: Bayleef|310/323',
      '|-damage|p2a: Bayleef|285/323',
      '|-hitcount|p2a: Bayleef|2',
      '|move|p2a: Bayleef|Substitute|p2a: Bayleef',
      '|-start|p2a: Bayleef|Substitute',
      '|-damage|p2a: Bayleef|205/323',
      '|turn|2',
      '|move|p1a: Hitmontop|Triple Kick|p2a: Bayleef',
      '|-crit|p2a: Bayleef',
      '|-activate|p2a: Bayleef|Substitute|[damage]',
      '|-crit|p2a: Bayleef',
      '|-end|p2a: Bayleef|Substitute',
      '|-damage|p2a: Bayleef|167/323',
      '|-hitcount|p2a: Bayleef|3',
      '|move|p2a: Bayleef|Splash|p2a: Bayleef',
      '|-nothing',
      '|-fail|p2a: Bayleef',
      '|turn|3',
    ]);
  });

  test('Twineedle effect', () => {
    const proc = SECONDARY(ranged(51, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);

    const battle = startBattle([
      QKC, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, no_proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Beedrill', evs, moves: ['Twineedle']},
    ], [
      {species: 'Voltorb', evs, moves: ['Substitute']},
      {species: 'Magnemite', evs, moves: ['Splash']},
      {species: 'Weezing', evs, moves: ['Explosion']},
    ]);

    const voltorb = battle.p2.pokemon[0].hp;
    let magnemite = battle.p2.pokemon[1].hp;
    const weezing = battle.p2.pokemon[2].hp;

    // Breaking a target's Substitute should nullify the poison chance
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(voltorb - 70 - 36);
    // expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].status).toBe('psn');

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(magnemite -= (15 * 2));
    expect(battle.p2.pokemon[0].status).toBe('');

    // The second hit can poison the target, even if they're Steel-type
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(magnemite - 15 - 18 - 31);
    expect(battle.p2.pokemon[0].status).toBe('psn');

    // Poison types cannot be poisoned
    battle.makeChoices('move 1', 'switch 3');
    expect(battle.p2.pokemon[0].hp).toBe(weezing - (11 * 2));
    expect(battle.p2.pokemon[0].status).toBe('');

    verify(battle, [
      '|move|p2a: Voltorb|Substitute|p2a: Voltorb',
      '|-start|p2a: Voltorb|Substitute',
      '|-damage|p2a: Voltorb|213/283',
      '|move|p1a: Beedrill|Twineedle|p2a: Voltorb',
      '|-crit|p2a: Voltorb',
      '|-end|p2a: Voltorb|Substitute',
      '|-damage|p2a: Voltorb|177/283',
      '|-status|p2a: Voltorb|psn',
      '|-hitcount|p2a: Voltorb|2',
      '|turn|2',
      '|switch|p2a: Magnemite|Magnemite|253/253',
      '|move|p1a: Beedrill|Twineedle|p2a: Magnemite',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|238/253',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|223/253',
      '|-hitcount|p2a: Magnemite|2',
      '|turn|3',
      '|move|p1a: Beedrill|Twineedle|p2a: Magnemite',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|208/253',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|190/253',
      '|-status|p2a: Magnemite|psn',
      '|-hitcount|p2a: Magnemite|2',
      '|move|p2a: Magnemite|Splash|p2a: Magnemite',
      '|-nothing',
      '|-fail|p2a: Magnemite',
      '|-damage|p2a: Magnemite|159/253 psn|[from] psn',
      '|turn|4',
      '|switch|p2a: Weezing|Weezing, M|333/333',
      '|move|p1a: Beedrill|Twineedle|p2a: Weezing',
      '|-resisted|p2a: Weezing',
      '|-damage|p2a: Weezing|322/333',
      '|-resisted|p2a: Weezing',
      '|-damage|p2a: Weezing|311/333',
      '|-hitcount|p2a: Weezing|2',
      '|turn|5',
    ]);
  });

  test('Poison effect', () => {
    {
      const battle = startBattle([
        QKC, HIT, QKC, HIT, QKC, HIT, QKC, HIT, QKC, QKC, QKC,
      ], [
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
      expect(battle.p1.pokemon[0].hp).toBe(abra -= 31);
      expect(battle.p2.pokemon[0].hp).toBe(drowzee -= 40);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(abra -= 31);
      expect(battle.p2.pokemon[0].hp).toBe(drowzee -= 60);

      verify(battle, [
        '|move|p1a: Jolteon|Toxic|p2a: Venomoth',
        '|-immune|p2a: Venomoth',
        '|move|p2a: Venomoth|Splash|p2a: Venomoth',
        '|-nothing',
        '|-fail|p2a: Venomoth',
        '|turn|2',
        '|move|p1a: Jolteon|Substitute|p1a: Jolteon',
        '|-start|p1a: Jolteon|Substitute',
        '|-damage|p1a: Jolteon|250/333',
        '|move|p2a: Venomoth|Toxic|p1a: Jolteon',
        '|-activate|p1a: Jolteon|Substitute|[block] Toxic',
        '|turn|3',
        '|switch|p2a: Drowzee|Drowzee, M|323/323',
        '|move|p1a: Jolteon|Toxic|p2a: Drowzee',
        '|-status|p2a: Drowzee|tox',
        '|turn|4',
        '|switch|p1a: Abra|Abra, M|253/253',
        '|move|p2a: Drowzee|Poison Gas|p1a: Abra',
        '|-status|p1a: Abra|psn',
        '|-damage|p2a: Drowzee|303/323 tox|[from] psn',
        '|turn|5',
        '|move|p1a: Abra|Splash|p1a: Abra',
        '|-nothing',
        '|-fail|p1a: Abra',
        '|-damage|p1a: Abra|222/253 psn|[from] psn',
        '|move|p2a: Drowzee|Splash|p2a: Drowzee',
        '|-nothing',
        '|-fail|p2a: Drowzee',
        '|-damage|p2a: Drowzee|263/323 tox|[from] psn',
        '|turn|6',
        '|move|p1a: Abra|Splash|p1a: Abra',
        '|-nothing',
        '|-fail|p1a: Abra',
        '|-damage|p1a: Abra|191/253 psn|[from] psn',
        '|move|p2a: Drowzee|Splash|p2a: Drowzee',
        '|-nothing',
        '|-fail|p2a: Drowzee',
        '|-damage|p2a: Drowzee|203/323 tox|[from] psn',
        '|turn|7',
      ]);
    }
    {
      const battle = startBattle([QKC, HIT, HIT, ...QKCs(30)], [
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
    const proc = SECONDARY(ranged(76, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, no_proc,
      QKC, NO_CRIT, MAX_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Tentacruel', evs, moves: ['Poison Sting', 'Sludge']},
    ], [
      {species: 'Persian', evs, moves: ['Substitute', 'Poison Sting', 'Scratch']},
    ]);
    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Can't poison Poison-types
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
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 41 - 18));

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
      '|-damage|p2a: Persian|173/333 psn|[from] psn|[of] p1a: Tentacruel',
      '|move|p1a: Tentacruel|Poison Sting|p2a: Persian',
      '|-damage|p2a: Persian|155/333 psn',
      '|turn|5',
    ]);
  });

  test('BurnChance effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, no_proc,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Charizard', evs, moves: ['Ember', 'Fire Blast']},
    ], [
      {species: 'Tauros', evs, moves: ['Substitute', 'Fire Blast', 'Tackle']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Can't burn Fire-types
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 28);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 58);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Substitute prevents burn chance
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 88);
    expect(battle.p2.pokemon[0].status).toBe('');

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 45);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 58);
    expect(battle.p2.pokemon[0].status).toBe('brn');

    // Can't burn already burnt Pokémon / Burn lowers attack and causes residual damage
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 44 - 58));

    verify(battle, [
      '|move|p2a: Tauros|Fire Blast|p1a: Charizard',
      '|-resisted|p1a: Charizard',
      '|-damage|p1a: Charizard|331/359',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|295/353',
      '|turn|2',
      '|move|p2a: Tauros|Substitute|p2a: Tauros',
      '|-start|p2a: Tauros|Substitute',
      '|-damage|p2a: Tauros|207/353',
      '|move|p1a: Charizard|Fire Blast|p2a: Tauros',
      '|-end|p2a: Tauros|Substitute',
      '|turn|3',
      '|move|p2a: Tauros|Tackle|p1a: Charizard',
      '|-damage|p1a: Charizard|286/359',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|149/353',
      '|-status|p2a: Tauros|brn',
      '|turn|4',
      '|move|p2a: Tauros|Tackle|p1a: Charizard',
      '|-damage|p1a: Charizard|263/359',
      '|-damage|p2a: Tauros|105/353 brn|[from] brn|[of] p1a: Charizard',
      '|move|p1a: Charizard|Ember|p2a: Tauros',
      '|-damage|p2a: Tauros|47/353 brn',
      '|turn|5',
    ]);
  });

  test('FlameWheel effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Quilava', evs, moves: ['Flame Wheel']},
    ], [
      {species: 'Suicune', evs, moves: ['Ice Beam']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 41);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
    expect(battle.p2.pokemon[0].status).toBe('brn');

    verify(battle, [
      '|move|p2a: Suicune|Ice Beam|p1a: Quilava',
      '|-resisted|p1a: Quilava',
      '|-damage|p1a: Quilava|278/319',
      '|-status|p1a: Quilava|frz',
      '|move|p1a: Quilava|Flame Wheel|p2a: Suicune',
      '|-resisted|p2a: Suicune',
      '|-damage|p2a: Suicune|378/403',
      '|-status|p2a: Suicune|brn',
      '|-curestatus|p1a: Quilava|frz|[msg]',
      '|turn|2',
    ]);
  });

  test('SacredFire effect', () => {
    const lo_proc = SECONDARY(ranged(25, 256) - 1);
    const hi_proc = SECONDARY(ranged(127, 256) - 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, lo_proc, HIT, NO_CRIT, MIN_DMG, hi_proc, QKC,
    ], [
      {species: 'Ho-Oh', evs, moves: ['Sacred Fire']},
    ], [
      {species: 'Lugia', evs, moves: ['Ice Beam']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 47);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 85);
    expect(battle.p2.pokemon[0].status).toBe('brn');

    verify(battle, [
      '|move|p2a: Lugia|Ice Beam|p1a: Ho-Oh',
      '|-damage|p1a: Ho-Oh|368/415',
      '|-status|p1a: Ho-Oh|frz',
      '|move|p1a: Ho-Oh|Sacred Fire|p2a: Lugia',
      '|-damage|p2a: Lugia|330/415',
      '|-status|p2a: Lugia|brn',
      '|-curestatus|p1a: Ho-Oh|frz|[msg]',
      '|turn|2',
    ]);
  });

  test('FreezeChance effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, PAR_CANT,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, NO_THAW,
      QKC, NO_THAW,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ,
      QKC, HIT, NO_CRIT, MIN_DMG, MIN_WRAP, NO_THAW,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_THAW,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, MISS,
      QKC, HIT, CRIT, MAX_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, THAW, QKC,
    ], [
      {species: 'Starmie', evs, moves: ['Ice Beam']},
      {species: 'Magmar', evs, moves: ['Ice Beam', 'Flamethrower', 'Substitute', 'Recover']},
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
    expect(battle.p1.pokemon[0].hp).toBe(starmie -= 79);
    expect(battle.p1.pokemon[0].status).toBe('par');

    // Can freeze Fire types
    battle.makeChoices('switch 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 79);
    expect(battle.p1.pokemon[0].status).toBe('frz');

    // Freezing prevents action
    battle.makeChoices('move 1', 'move 1');
    // ...Pokémon Showdown still lets you choose whatever
    expect(choices(battle, 'p1')).toEqual([
      'switch 2', 'switch 3', 'move 1', 'move 2', 'move 3', 'move 4',
    ]);

    // Freeze Clause Mod prevents multiple Pokémon from being frozen
    battle.makeChoices('switch 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(lickitung -= 171);
    expect(battle.p1.pokemon[0].status).toBe('');

    // Fire Spin does not THAW frozen Pokémon
    battle.makeChoices('switch 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 26);
    expect(battle.p1.pokemon[0].status).toBe('frz');

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 26);

    // Other Fire moves THAW frozen Pokémon
    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 41);
    expect(battle.p1.pokemon[0].status).toBe('');

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 83);

    // Substitute blocks Freeze
    battle.makeChoices('move 4', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar += 167);
    expect(battle.p1.pokemon[0].status).toBe('');

    // Can thaw naturally but miss turn
    battle.makeChoices('move 4', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(magmar -= 79);
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
      '|-damage|p1a: Starmie|244/323 par',
      '|cant|p1a: Starmie|par',
      '|turn|3',
      '|switch|p1a: Magmar|Magmar, M|333/333',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|254/333',
      '|-status|p1a: Magmar|frz',
      '|turn|4',
      '|move|p2a: Jynx|Thunder Wave||[still]',
      '|-fail|p2a: Jynx',
      '|cant|p1a: Magmar|frz',
      '|turn|5',
      '|switch|p1a: Lickitung|Lickitung, M|383/383',
      '|move|p2a: Jynx|Blizzard|p1a: Lickitung',
      '|-damage|p1a: Lickitung|212/383',
      '|turn|6',
      '|switch|p1a: Magmar|Magmar, M|254/333 frz',
      '|move|p2a: Jynx|Fire Spin|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|248/333 frz',
      '|-activate|p1a: Magmar|move: Fire Spin|[of] p2a: Jynx',
      '|-damage|p1a: Magmar|228/333 frz|[from] move: Fire Spin|[partiallytrapped]',
      '|turn|7',
      '|move|p2a: Jynx|Fire Spin|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|222/333 frz',
      '|cant|p1a: Magmar|frz',
      '|-damage|p1a: Magmar|202/333 frz|[from] move: Fire Spin|[partiallytrapped]',
      '|turn|8',
      '|move|p2a: Jynx|Flamethrower|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|161/333 frz',
      '|-curestatus|p1a: Magmar|frz|[msg]',
      '|move|p1a: Magmar|Ice Beam|p2a: Jynx',
      '|-resisted|p2a: Jynx',
      '|-damage|p2a: Jynx|263/333',
      '|-end|p1a: Magmar|Fire Spin|[partiallytrapped]',
      '|turn|9',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar|[miss]',
      '|-miss|p2a: Jynx',
      '|move|p1a: Magmar|Substitute|p1a: Magmar',
      '|-start|p1a: Magmar|Substitute',
      '|-damage|p1a: Magmar|78/333',
      '|turn|10',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar',
      '|-crit|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-end|p1a: Magmar|Substitute',
      '|move|p1a: Magmar|Recover|p1a: Magmar',
      '|-heal|p1a: Magmar|245/333',
      '|turn|11',
      '|move|p2a: Jynx|Blizzard|p1a: Magmar',
      '|-resisted|p1a: Magmar',
      '|-damage|p1a: Magmar|166/333',
      '|-status|p1a: Magmar|frz',
      '|cant|p1a: Magmar|frz',
      '|-curestatus|p1a: Magmar|frz|[msg]',
      '|turn|12',
    ]);
  });

  test('Paralyze effect', () => {
    const curse = {key: 'data/mods/gen2/scripts.ts:441:59', value: 0};
    const battle = startBattle([
      QKC, MISS, QKC, PAR_CAN, HIT, QKC, PAR_CANT,	QKC, HIT, PAR_CAN,
      QKC, QKC, HIT, QKC, QKC, HIT,	QKC, PAR_CAN, QKC, PAR_CAN, curse, QKC,
    ], [
      {species: 'Arbok', evs, moves: ['Glare', 'Curse']},
      {species: 'Dugtrio', evs, moves: ['Earthquake', 'Substitute', 'Splash', 'Baton Pass']},
    ], [
      {species: 'Magneton', evs, moves: ['Thunder Wave']},
      {species: 'Gengar', evs, moves: ['Toxic', 'Thunder Wave', 'Glare', 'Night Shade']},
    ]);

    // Glare can miss
    battle.makeChoices('move 1', 'move 1');

    // Paralysis lowers speed
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p1.pokemon[0].getStat('spe')).toBe(64);
    expect(battle.p1.pokemon[0].storedStats.spe).toBe(258);

    // Electric-type Pokémon can be paralyzed
    battle.makeChoices('move 1', 'move 1');
    // Can be fully paralyzed
    battle.makeChoices('move 1', 'switch 2');
    // Glare does not ignores type immunity
    battle.makeChoices('move 1', 'move 1');
    // Thunder Wave does not ignore type immunity
    battle.makeChoices('switch 2', 'move 2');
    // Substitute blocks paralysis
    battle.makeChoices('move 2', 'move 3');

    battle.makeChoices('move 3', 'move 4');
    battle.makeChoices('move 3', 'move 3');

    expect(battle.p1.pokemon[0].status).toBe('par');

    // Baton Pass from one paralyzed Pokémon to another should not reduce speed until recalculated
    battle.makeChoices('move 4', 'move 2');
    battle.makeChoices('switch 2', '');

    // expect(battle.p1.pokemon[0].getStat('spe')).toBe(258);
    expect(battle.p1.pokemon[0].getStat('spe')).toBe(64);

    battle.makeChoices('move 2', 'move 2');

    expect(battle.p1.pokemon[0].getStat('spe')).toBe(42);

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
      '|switch|p2a: Gengar|Gengar, M|323/323',
      '|cant|p1a: Arbok|par',
      '|turn|4',
      '|move|p2a: Gengar|Toxic||[still]',
      '|-fail|p2a: Gengar',
      '|move|p1a: Arbok|Glare|p2a: Gengar',
      '|-immune|p2a: Gengar',
      '|turn|5',
      '|switch|p1a: Dugtrio|Dugtrio, M|273/273',
      '|move|p2a: Gengar|Thunder Wave|p1a: Dugtrio',
      '|-immune|p1a: Dugtrio',
      '|turn|6',
      '|move|p1a: Dugtrio|Substitute|p1a: Dugtrio',
      '|-start|p1a: Dugtrio|Substitute',
      '|-damage|p1a: Dugtrio|205/273',
      '|move|p2a: Gengar|Glare|p1a: Dugtrio',
      '|-activate|p1a: Dugtrio|Substitute|[block] Glare',
      '|turn|7',
      '|move|p1a: Dugtrio|Splash|p1a: Dugtrio',
      '|-nothing',
      '|-fail|p1a: Dugtrio',
      '|move|p2a: Gengar|Night Shade|p1a: Dugtrio',
      '|-end|p1a: Dugtrio|Substitute',
      '|turn|8',
      '|move|p1a: Dugtrio|Splash|p1a: Dugtrio',
      '|-nothing',
      '|-fail|p1a: Dugtrio',
      '|move|p2a: Gengar|Glare|p1a: Dugtrio',
      '|-status|p1a: Dugtrio|par',
      '|turn|9',
      '|move|p2a: Gengar|Thunder Wave|p1a: Dugtrio',
      '|-immune|p1a: Dugtrio',
      '|move|p1a: Dugtrio|Baton Pass|p1a: Dugtrio',
      '|switch|p1a: Arbok|Arbok, M|323/323 par|[from] Baton Pass',
      '|turn|10',
      '|move|p2a: Gengar|Thunder Wave|p1a: Arbok',
      '|-fail|p1a: Arbok|par',
      '|move|p1a: Arbok|Curse|p1a: Arbok',
      '|-unboost|p1a: Arbok|spe|1',
      '|-boost|p1a: Arbok|atk|1',
      '|-boost|p1a: Arbok|def|1',
      '|turn|11',
    ]);
  });

  test('ParalyzeChance effect', () => {
    const lo_proc = SECONDARY(ranged(25, 256) - 1);
    const hi_proc = SECONDARY(ranged(76, 256) - 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, hi_proc, PAR_CAN, NO_CRIT, MIN_DMG, hi_proc,
      QKC, QKC, NO_CRIT, MIN_DMG, lo_proc,
      QKC, PAR_CAN, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, lo_proc, PAR_CANT,
      QKC, QKC,
    ], [
      {species: 'Jolteon', evs, moves: ['Body Slam', 'Splash']},
      {species: 'Dugtrio', evs, moves: ['Earthquake']},
    ], [
      {species: 'Raticate', evs, moves: ['Body Slam', 'Thunderbolt', 'Substitute']},
      {species: 'Ampharos', evs, moves: ['Thundershock', 'Substitute']},
    ]);

    let jolteon = battle.p1.pokemon[0].hp;
    let raticate = battle.p2.pokemon[0].hp;
    let ampharos = battle.p2.pokemon[1].hp;

    // Can paralyze a Pokémon of the same type as the move
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(jolteon -= 23);
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(raticate -= 64);
    expect(battle.p2.pokemon[0].status).toBe('par');

    battle.makeChoices('move 2', 'switch 2');

    // Moves have different paralysis rates / Electric-type Pokémon can be paralyzed
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(jolteon -= 25);
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].hp).toBe(ampharos);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Paralysis lowers speed / Substitute block paralysis chance
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(jolteon);
    expect(battle.p2.pokemon[0].hp).toBe(ampharos -= 95);
    expect(battle.p2.pokemon[0].status).toBe('');

    // Doesn't work if already statused / paralysis can prevent action
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(jolteon -= 25);

    // Doesn't trigger if the opponent is immune to the move
    battle.makeChoices('switch 2', 'move 1');

    verify(battle, [
      '|move|p1a: Jolteon|Body Slam|p2a: Raticate',
      '|-damage|p2a: Raticate|249/313',
      '|-status|p2a: Raticate|par',
      '|move|p2a: Raticate|Thunderbolt|p1a: Jolteon',
      '|-resisted|p1a: Jolteon',
      '|-damage|p1a: Jolteon|310/333',
      '|turn|2',
      '|switch|p2a: Ampharos|Ampharos, M|383/383',
      '|move|p1a: Jolteon|Splash|p1a: Jolteon',
      '|-nothing',
      '|-fail|p1a: Jolteon',
      '|turn|3',
      '|move|p1a: Jolteon|Splash|p1a: Jolteon',
      '|-nothing',
      '|-fail|p1a: Jolteon',
      '|move|p2a: Ampharos|Thunder Shock|p1a: Jolteon',
      '|-resisted|p1a: Jolteon',
      '|-damage|p1a: Jolteon|285/333',
      '|-status|p1a: Jolteon|par',
      '|turn|4',
      '|move|p2a: Ampharos|Substitute|p2a: Ampharos',
      '|-start|p2a: Ampharos|Substitute',
      '|-damage|p2a: Ampharos|288/383',
      '|move|p1a: Jolteon|Body Slam|p2a: Ampharos',
      '|-activate|p2a: Ampharos|Substitute|[damage]',
      '|turn|5',
      '|move|p2a: Ampharos|Thunder Shock|p1a: Jolteon',
      '|-resisted|p1a: Jolteon',
      '|-damage|p1a: Jolteon|260/333 par',
      '|cant|p1a: Jolteon|par',
      '|turn|6',
      '|switch|p1a: Dugtrio|Dugtrio, M|273/273',
      '|move|p2a: Ampharos|Thunder Shock|p1a: Dugtrio',
      '|-immune|p1a: Dugtrio',
      '|turn|7',
    ]);
  });

  test('TriAttack effect', () => {
    const proc = SECONDARY(ranged(51, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const par = {key: 'data/mods/gen2/moves.ts:942:49', value: ranged(1, 3)};
    const frz = {...par, value: ranged(2, 3)};
    const brn = {...par, value: ranged(3, 3)};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, frz, proc, NO_THAW,
      QKC, NO_CRIT, MIN_DMG, brn, no_proc, MISS,
      QKC, NO_CRIT, MIN_DMG, par, proc,
      QKC, NO_CRIT, MIN_DMG, brn, proc, QKC,
    ], [
      {species: 'Porygon2', evs, moves: ['Tri-Attack']},
    ], [
      {species: 'Swinub', evs, moves: ['Blizzard']},
      {species: 'Mareep', evs, moves: ['Thundershock']},
      {species: 'Togepi', evs, moves: ['Metronome']},
    ]);

    let swinub = battle.p2.pokemon[0].hp;
    let mareep = battle.p2.pokemon[1].hp;
    let togepi = battle.p2.pokemon[2].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('frz');
    expect(battle.p2.pokemon[0].hp).toBe(swinub -= 125);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.pokemon[0].hp).toBe(swinub -= 125);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].hp).toBe(mareep -= 125);

    battle.makeChoices('move 1', 'switch 3');
    expect(battle.p2.pokemon[0].status).toBe('brn');
    expect(battle.p2.pokemon[0].hp).toBe(togepi -= 97);

    verify(battle, [
      '|move|p1a: Porygon2|Tri Attack|p2a: Swinub',
      '|-damage|p2a: Swinub|178/303',
      '|-status|p2a: Swinub|frz',
      '|cant|p2a: Swinub|frz',
      '|turn|2',
      '|move|p1a: Porygon2|Tri Attack|p2a: Swinub',
      '|-damage|p2a: Swinub|53/303 frz',
      '|-curestatus|p2a: Swinub|frz|[msg]',
      '|move|p2a: Swinub|Blizzard|p1a: Porygon2|[miss]',
      '|-miss|p2a: Swinub',
      '|turn|3',
      '|switch|p2a: Mareep|Mareep, M|313/313',
      '|move|p1a: Porygon2|Tri Attack|p2a: Mareep',
      '|-damage|p2a: Mareep|188/313',
      '|-status|p2a: Mareep|par',
      '|turn|4',
      '|switch|p2a: Togepi|Togepi, M|273/273',
      '|move|p1a: Porygon2|Tri Attack|p2a: Togepi',
      '|-damage|p2a: Togepi|176/273',
      '|-status|p2a: Togepi|brn',
      '|turn|5',
    ]);
  });

  test('Sleep effect', () => {
    const battle = startBattle([
      QKC, SLP(1), QKC, HIT, NO_CRIT, MIN_DMG, QKC, SLP(2), QKC, QKC, QKC, HIT,
      NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Parasect', evs, moves: ['Spore', 'Cut']},
    ], [
      {species: 'Geodude', evs, moves: ['Tackle']},
      {species: 'Slowpoke', evs, moves: ['Water Gun']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Always must sleep for at least one turn
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // Pokemon can make a move the turn it wakes up
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 26);
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

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // Eventually wakes up
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 26);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
    expect(battle.p2.pokemon[0].status).toBe('');

    verify(battle, [
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-status|p2a: Geodude|slp|[from] move: Spore',
      '|cant|p2a: Geodude|slp',
      '|turn|2',
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-fail|p2a: Geodude|slp',
      '|-curestatus|p2a: Geodude|slp|[msg]',
      '|move|p2a: Geodude|Tackle|p1a: Parasect',
      '|-damage|p1a: Parasect|297/323',
      '|turn|3',
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-status|p2a: Geodude|slp|[from] move: Spore',
      '|cant|p2a: Geodude|slp',
      '|turn|4',
      '|switch|p2a: Slowpoke|Slowpoke, M|383/383',
      '|move|p1a: Parasect|Spore|p2a: Slowpoke',
      '|turn|5',
      '|switch|p2a: Geodude|Geodude, M|283/283 slp',
      '|move|p1a: Parasect|Spore|p2a: Geodude',
      '|-fail|p2a: Geodude|slp',
      '|turn|6',
      '|move|p1a: Parasect|Cut|p2a: Geodude',
      '|-resisted|p2a: Geodude',
      '|-damage|p2a: Geodude|266/283 slp',
      '|cant|p2a: Geodude|slp',
      '|turn|7',
      '|move|p1a: Parasect|Cut|p2a: Geodude',
      '|-resisted|p2a: Geodude',
      '|-damage|p2a: Geodude|249/283 slp',
      '|-curestatus|p2a: Geodude|slp|[msg]',
      '|move|p2a: Geodude|Tackle|p1a: Parasect',
      '|-damage|p1a: Parasect|271/323',
      '|turn|8',
    ]);
  });

  test('Confusion effect', () => {
    {
      const battle = startBattle([QKC, QKC, QKC, CFZ(3), QKC, CFZ_CANT, QKC, CFZ_CAN, QKC, QKC], [
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
        '|-activate|p2a: Gengar|Substitute|[block] Confuse Ray',
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
        '|-fail|p2a: Gengar',
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
    }
    // Confused Pokémon has Substitute
    {
      const battle = startBattle([QKC, HIT, CFZ(5), CFZ_CAN, QKC, HIT, CFZ_CANT, QKC], [
        {species: 'Bulbasaur', level: 6, evs, moves: ['Substitute', 'Growl']},
      ], [
        {species: 'Zubat', level: 10, evs, moves: ['Supersonic']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 6);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(6);

      // Confusion self-hit bypasses own Substitute
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 5);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(6);

      verify(battle, [
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|confusion',
        '|-activate|p1a: Bulbasaur|confusion',
        '|move|p1a: Bulbasaur|Substitute|p1a: Bulbasaur',
        '|-start|p1a: Bulbasaur|Substitute',
        '|-damage|p1a: Bulbasaur|20/26',
        '|turn|2',
        '|move|p2a: Zubat|Supersonic|p1a: Bulbasaur',
        '|-activate|p1a: Bulbasaur|Substitute|[block] Supersonic',
        '|-activate|p1a: Bulbasaur|confusion',
        '|-damage|p1a: Bulbasaur|15/26|[from] confusion',
        '|turn|3',
      ]);
    }
    // Both Pokémon have Substitutes
    {
      const battle = startBattle([
        QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, CFZ(5), CFZ_CANT, QKC, CFZ_CAN, QKC, CFZ_CANT, QKC,
      ], [
        {species: 'Bulbasaur', level: 6, evs, moves: ['Substitute', 'Tackle']},
      ], [
        {species: 'Zubat', level: 10, evs, moves: ['Supersonic', 'Substitute']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;
      const sub1 = 6;
      let sub2 = 9;

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= sub2);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2 -= 3);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= sub1);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(sub1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 5);
      expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(sub1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(sub2);

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
        '|-damage|p1a: Bulbasaur|10/26|[from] confusion',
        '|turn|5',
      ]);
    }
  });

  test('ConfusionChance effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const battle = startBattle([
      QKC, NO_CRIT, MAX_DMG,
      QKC, NO_CRIT, MAX_DMG,
      QKC, NO_CRIT, MAX_DMG, proc, CFZ(2), QKC,
    ], [
      {species: 'Venomoth', evs, moves: ['Psybeam', 'Splash']},
    ], [
      {species: 'Jolteon', evs, moves: ['Substitute', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    // Substitute blocks ConfusionChance
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();

    verify(battle, [
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|250/333',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-activate|p2a: Jolteon|Substitute|[damage]',
      '|turn|2',
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-fail|p2a: Jolteon|move: Substitute',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-end|p2a: Jolteon|Substitute',
      '|turn|3',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|-fail|p2a: Jolteon',
      '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
      '|-damage|p2a: Jolteon|196/333',
      '|-start|p2a: Jolteon|confusion',
      '|turn|4',
    ]);
  });

  test('FlinchChance effect', () => {
    const lo_proc = SECONDARY(ranged(25, 256) - 1);
    const hi_proc = SECONDARY(ranged(76, 256) - 1);
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, hi_proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, hi_proc,
      QKC, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, lo_proc,
      QKC, HIT, NO_CRIT, MIN_DMG, lo_proc,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, hi_proc,
      QKC, NO_CRIT, MIN_DMG, lo_proc, QKC,
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
    expect(choices(battle, 'p1')).toEqual(['move 1']);

    // Flinch does not clear recharge
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 60);

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
      '|cant|p2a: Marowak|recharge',
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
      '|cant|p1a: Raticate|recharge',
      '|move|p2a: Marowak|Headbutt|p1a: Raticate',
      '|-damage|p1a: Raticate|5/313',
      '|turn|8',
    ]);
  });

  test('Snore effect', () => {
    const proc = SECONDARY(ranged(76, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const battle = startBattle([
      QKC, HIT, SLP(5), QKC, NO_CRIT, MIN_DMG, no_proc, HIT,
      QKC, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Heracross', evs, moves: ['Snore']},
    ], [
      {species: 'Bellossom', evs, moves: ['Sleep Powder', 'Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('slp');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 38);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 38);

    verify(battle, [
      '|move|p1a: Heracross|Snore|p2a: Bellossom',
      '|move|p2a: Bellossom|Sleep Powder|p1a: Heracross',
      '|-status|p1a: Heracross|slp|[from] move: Sleep Powder',
      '|turn|2',
      '|cant|p1a: Heracross|slp',
      '|move|p1a: Heracross|Snore|p2a: Bellossom',
      '|-damage|p2a: Bellossom|315/353',
      '|move|p2a: Bellossom|Sleep Powder|p1a: Heracross',
      '|-fail|p1a: Heracross|slp',
      '|turn|3',
      '|cant|p1a: Heracross|slp',
      '|move|p1a: Heracross|Snore|p2a: Bellossom',
      '|-damage|p2a: Bellossom|277/353',
      '|cant|p2a: Bellossom|flinch',
      '|turn|4',
    ]);
  });

  test('Stomp effect', () => {
    const proc = SECONDARY(ranged(76, 256) - 1);
    const no_proc = SECONDARY(proc.value + 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_proc, QKC, HIT, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Miltank', evs, moves: ['Stomp']},
    ], [
      {species: 'Blissey', evs, moves: ['Minimize']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 155);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 308);

    verify(battle, [
      '|move|p1a: Miltank|Stomp|p2a: Blissey',
      '|-damage|p2a: Blissey|558/713',
      '|move|p2a: Blissey|Minimize|p2a: Blissey',
      '|-boost|p2a: Blissey|evasion|1',
      '|turn|2',
      '|move|p1a: Miltank|Stomp|p2a: Blissey',
      '|-damage|p2a: Blissey|250/713',
      '|cant|p2a: Blissey|flinch',
      '|turn|3',
    ]);
  });

  test('StatDown effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, HIT,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, QKC,
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
      '|switch|p2a: Gastly|Gastly, M|263/263',
      '|move|p1a: Ekans|Screech|p2a: Gastly',
      '|-unboost|p2a: Gastly|def|2',
      '|turn|5',
    ]);
  });

  test('StatDownChance effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_proc, NO_CRIT, MIN_DMG, proc,
      QKC, NO_CRIT, MIN_DMG, no_proc, NO_CRIT, MIN_DMG, proc,
      QKC, NO_CRIT, MIN_DMG, no_proc, NO_CRIT, MIN_DMG, no_proc, QKC,
    ], [
      {species: 'Alakazam', evs, moves: ['Psychic']},
    ], [
      {species: 'Starmie', evs, moves: ['Bubble Beam']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 79);
    expect(battle.p1.pokemon[0].boosts.spe).toBe(-1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 66);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 79);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 66);
    expect(battle.p2.pokemon[0].boosts.spa).toBe(0);
    expect(battle.p2.pokemon[0].boosts.spd).toBe(-1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 79);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 102);

    verify(battle, [
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|257/323',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|234/313',
      '|-unboost|p1a: Alakazam|spe|1',
      '|turn|2',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|155/313',
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|191/323',
      '|-unboost|p2a: Starmie|spd|1',
      '|turn|3',
      '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
      '|-damage|p1a: Alakazam|76/313',
      '|move|p1a: Alakazam|Psychic|p2a: Starmie',
      '|-resisted|p2a: Starmie',
      '|-damage|p2a: Starmie|89/323',
      '|turn|4',
    ]);
  });

  test('StatUp effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Scyther', evs, moves: ['Swords Dance', 'Cut']},
    ], [
      {species: 'Slowbro', evs, moves: ['Withdraw', 'Water Gun']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 51);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 37);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 51);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);

    verify(battle, [
      '|move|p1a: Scyther|Cut|p2a: Slowbro',
      '|-damage|p2a: Slowbro|356/393',
      '|move|p2a: Slowbro|Water Gun|p1a: Scyther',
      '|-damage|p1a: Scyther|292/343',
      '|turn|2',
      '|move|p1a: Scyther|Swords Dance|p1a: Scyther',
      '|-boost|p1a: Scyther|atk|2',
      '|move|p2a: Slowbro|Withdraw|p2a: Slowbro',
      '|-boost|p2a: Slowbro|def|1',
      '|turn|3',
      '|move|p1a: Scyther|Cut|p2a: Slowbro',
      '|-damage|p2a: Slowbro|307/393',
      '|move|p2a: Slowbro|Water Gun|p1a: Scyther',
      '|-damage|p1a: Scyther|241/343',
      '|turn|4',
    ]);
  });

  test('DefenseCurl effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, MISS, QKC, QKC, HIT, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Miltank', evs, moves: ['Rollout', 'Defense Curl']},
    ], [
      {species: 'Blissey', evs, moves: ['Splash']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.def).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].boosts.def).toBe(1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 96);

    verify(battle, [
      '|move|p1a: Miltank|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|665/713',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|2',
      '|move|p1a: Miltank|Rollout|p2a: Blissey|[miss]',
      '|-miss|p1a: Miltank',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|3',
      '|move|p1a: Miltank|Defense Curl|p1a: Miltank',
      '|-boost|p1a: Miltank|def|1',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|4',
      '|move|p1a: Miltank|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|569/713',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|5',
    ]);
  });

  test('StatUpChance effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, proc, HIT, NO_CRIT, MIN_DMG, no_proc, QKC,
    ], [
      {species: 'Skarmory', evs, moves: ['Metal Claw']},
    ], [
      {species: 'Gligar', evs, moves: ['Steel Wing']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 17);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 31);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);

    verify(battle, [
      '|move|p2a: Gligar|Steel Wing|p1a: Skarmory',
      '|-resisted|p1a: Skarmory',
      '|-damage|p1a: Skarmory|316/333',
      '|-boost|p2a: Gligar|def|1',
      '|move|p1a: Skarmory|Metal Claw|p2a: Gligar',
      '|-damage|p2a: Gligar|302/333',
      '|turn|2',
    ]);
  });

  test('AllStatUpChance effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_proc, QKC, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Aerodactyl', evs, moves: ['Ancient Power']},
    ], [
      {species: 'Skarmory', evs, moves: ['Spikes']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);
    for (const stat of gen.stats) {
      if (stat === 'hp') continue;
      expect(battle.p1.pokemon[0].boosts[stat]).toBe(0);
    }

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);
    for (const stat of gen.stats) {
      if (stat === 'hp') continue;
      expect(battle.p1.pokemon[0].boosts[stat]).toBe(1);
    }

    verify(battle, [
      '|move|p1a: Aerodactyl|Ancient Power|p2a: Skarmory',
      '|-damage|p2a: Skarmory|279/333',
      '|move|p2a: Skarmory|Spikes|p1a: Aerodactyl',
      '|-sidestart|p1: Player 1|Spikes',
      '|turn|2',
      '|move|p1a: Aerodactyl|Ancient Power|p2a: Skarmory',
      '|-damage|p2a: Skarmory|225/333',
      '|-boost|p1a: Aerodactyl|atk|1',
      '|-boost|p1a: Aerodactyl|def|1',
      '|-boost|p1a: Aerodactyl|spa|1',
      '|-boost|p1a: Aerodactyl|spd|1',
      '|-boost|p1a: Aerodactyl|spe|1',
      '|move|p2a: Skarmory|Spikes|p1a: Aerodactyl',
      '|-fail|p1a: Aerodactyl',
      '|turn|3',
    ]);
  });

  test('OHKO effect', () => {
    const hit = {...HIT, value: ranged(176, 256) - 1};
    const miss = {...MISS, value: hit.value + 1};
    const battle = startBattle([
      QKC, QKC, miss, QKC, miss, QKC, hit, QKC, MISS, QKC, QKC, QKC,
    ], [
      {species: 'Krabby', level: 5, evs, moves: ['Guillotine']},
      {species: 'Nidoking', level: 50, evs, moves: ['Horn Drill', 'Dig']},
      {species: 'Tauros', moves: ['Counter', 'Horn Drill']},
    ], [
      {species: 'Dugtrio', evs, moves: ['Fissure']},
      {species: 'Rhydon', evs, moves: ['Fissure']},
      {species: 'Gengar', evs, moves: ['Dig']},
    ]);

    // 100% accurate if the level gap is large enough
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 2', '');

    // Can't OHKO a higher level Pokémon
    battle.makeChoices('move 1', 'move 1');

    battle.makeChoices('move 2', 'move 1');

    // Fissure can still hit while underground
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 3', '');

    // Should be able to Counter a missed Fissure / Horn Drill (but not Guillotine)
    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(0);

    // Type-immunity trumps OHKO-immunity
    battle.makeChoices('move 2', 'switch 3');

    // Invulnerability trumps immunity on Pokémon Showdown
    battle.makeChoices('move 2', 'move 1');

    verify(battle, [
      '|move|p2a: Dugtrio|Fissure|p1a: Krabby',
      '|-damage|p1a: Krabby|0 fnt',
      '|-ohko',
      '|faint|p1a: Krabby',
      '|switch|p1a: Nidoking|Nidoking, L50, M|187/187',
      '|turn|2',
      '|move|p2a: Dugtrio|Fissure|p1a: Nidoking|[miss]',
      '|-miss|p2a: Dugtrio',
      '|move|p1a: Nidoking|Horn Drill|p2a: Dugtrio',
      '|-immune|p2a: Dugtrio|[ohko]',
      '|turn|3',
      '|move|p2a: Dugtrio|Fissure|p1a: Nidoking|[miss]',
      '|-miss|p2a: Dugtrio',
      '|move|p1a: Nidoking|Dig||[still]',
      '|-prepare|p1a: Nidoking|Dig',
      '|turn|4',
      '|move|p2a: Dugtrio|Fissure|p1a: Nidoking',
      '|-damage|p1a: Nidoking|0 fnt',
      '|-ohko',
      '|faint|p1a: Nidoking',
      '|switch|p1a: Tauros|Tauros, M|290/290',
      '|turn|5',
      '|move|p2a: Dugtrio|Fissure|p1a: Tauros|[miss]',
      '|-miss|p2a: Dugtrio',
      '|move|p1a: Tauros|Counter|p2a: Dugtrio',
      '|-fail|p2a: Dugtrio',
      '|turn|6',
      '|switch|p2a: Gengar|Gengar, M|323/323',
      '|move|p1a: Tauros|Horn Drill|p2a: Gengar',
      '|-immune|p2a: Gengar',
      '|turn|7',
      '|move|p2a: Gengar|Dig||[still]',
      '|-prepare|p2a: Gengar|Dig',
      '|move|p1a: Tauros|Horn Drill|p2a: Gengar|[miss]',
      '|-miss|p1a: Tauros',
      '|turn|8',
    ]);
  });

  test('SkyAttack effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Hoothoot', evs, moves: ['Sky Attack', 'Peck']},
      {species: 'Ivysaur', evs, moves: ['Vine Whip']},
    ], [
      {species: 'Psyduck', evs, moves: ['Scratch', 'Water Gun']},
      {species: 'Horsea', evs, moves: ['Bubble']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 37);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 37);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 123);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    verify(battle, [
      '|move|p2a: Psyduck|Scratch|p1a: Hoothoot',
      '|-damage|p1a: Hoothoot|286/323',
      '|move|p1a: Hoothoot|Sky Attack||[still]',
      '|-prepare|p1a: Hoothoot|Sky Attack',
      '|turn|2',
      '|move|p2a: Psyduck|Scratch|p1a: Hoothoot',
      '|-damage|p1a: Hoothoot|249/323',
      '|move|p1a: Hoothoot|Sky Attack|p2a: Psyduck',
      '|-damage|p2a: Psyduck|180/303',
      '|turn|3',
    ]);
  });

  test('SkullBash effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, DISABLE_DURATION(3), QKC, HIT, QKC,
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
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 16);
    expect(battle.p1.pokemon[0].boosts.def).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 16);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Wartortle|Skull Bash||[still]',
      '|-prepare|p1a: Wartortle|Skull Bash',
      '|-boost|p1a: Wartortle|def|1',
      '|move|p2a: Psyduck|Scratch|p1a: Wartortle',
      '|-damage|p1a: Wartortle|305/321',
      '|turn|2',
      '|move|p1a: Wartortle|Skull Bash|p2a: Psyduck',
      '|-damage|p2a: Psyduck|220/303',
      '|move|p2a: Psyduck|Scratch|p1a: Wartortle',
      '|-damage|p1a: Wartortle|289/321',
      '|turn|3',
      '|move|p1a: Wartortle|Skull Bash||[still]',
      '|-prepare|p1a: Wartortle|Skull Bash',
      '|-boost|p1a: Wartortle|def|1',
      '|move|p2a: Psyduck|Disable|p1a: Wartortle',
      '|-start|p1a: Wartortle|Disable|Skull Bash',
      '|turn|4',
      '|cant|p1a: Wartortle|Disable|Skull Bash',
      '|move|p2a: Psyduck|Disable|p1a: Wartortle',
      '|-fail|p1a: Wartortle',
      '|turn|5',
    ]);
  });

  test('RazorWind effect', () => {
    const crit2 = {...CRIT, value: ranged(2, 16)};
    const battle = startBattle([
      QKC, crit2, MIN_DMG, QKC, HIT, crit2, MIN_DMG, crit2, MIN_DMG, QKC,
    ], [
      {species: 'Feraligatr', evs, moves: ['Razor Wind', 'Water Gun']},
      {species: 'Ivysaur', evs, moves: ['Vine Whip']},
    ], [
      {species: 'Psyduck', evs, moves: ['Scratch', 'Water Gun']},
      {species: 'Horsea', evs, moves: ['Bubble']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 20);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 183);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Feraligatr|Razor Wind||[still]',
      '|-prepare|p1a: Feraligatr|Razor Wind',
      '|move|p2a: Psyduck|Scratch|p1a: Feraligatr',
      '|-damage|p1a: Feraligatr|353/373',
      '|turn|2',
      '|move|p1a: Feraligatr|Razor Wind|p2a: Psyduck',
      '|-crit|p2a: Psyduck',
      '|-damage|p2a: Psyduck|120/303',
      '|move|p2a: Psyduck|Scratch|p1a: Feraligatr',
      '|-damage|p1a: Feraligatr|333/373',
      '|turn|3',
    ]);
  });

  test('SolarBeam effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Sunflora', evs, moves: ['Solar Beam', 'Vine Whip']},
      {species: 'Ivysaur', evs, moves: ['Vine Whip']},
    ], [
      {species: 'Qwilfish', evs, moves: ['Scratch', 'Water Gun', 'Rain Dance', 'Sunny Day']},
      {species: 'Horsea', evs, moves: ['Bubble']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 192);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 95);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p2a: Qwilfish|Scratch|p1a: Sunflora',
      '|-damage|p1a: Sunflora|313/353',
      '|move|p1a: Sunflora|Solar Beam||[still]',
      '|-prepare|p1a: Sunflora|Solar Beam',
      '|turn|2',
      '|move|p2a: Qwilfish|Scratch|p1a: Sunflora',
      '|-damage|p1a: Sunflora|273/353',
      '|move|p1a: Sunflora|Solar Beam|p2a: Qwilfish',
      '|-damage|p2a: Qwilfish|141/333',
      '|turn|3',
      '|move|p2a: Qwilfish|Rain Dance|p2a: Qwilfish',
      '|-weather|RainDance',
      '|move|p1a: Sunflora|Solar Beam||[still]',
      '|-prepare|p1a: Sunflora|Solar Beam',
      '|-weather|RainDance|[upkeep]',
      '|turn|4',
      '|move|p2a: Qwilfish|Rain Dance|p2a: Qwilfish',
      '|-weather|RainDance',
      '|move|p1a: Sunflora|Solar Beam|p2a: Qwilfish',
      '|-damage|p2a: Qwilfish|46/333',
      '|-weather|RainDance|[upkeep]',
      '|turn|5',
      '|move|p2a: Qwilfish|Sunny Day|p2a: Qwilfish',
      '|-weather|SunnyDay',
      '|move|p1a: Sunflora|Solar Beam||[still]',
      '|-prepare|p1a: Sunflora|Solar Beam',
      '|-anim|p1a: Sunflora|Solar Beam|p2a: Qwilfish',
      '|-damage|p2a: Qwilfish|0 fnt',
      '|faint|p2a: Qwilfish',
    ]);
  });

  test('Fly/Dig effect', () => {
    // normal
    {
      const battle = startBattle([
        QKC, QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
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
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(choices(battle, 'p1')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 79);
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 74);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      verify(battle, [
        '|move|p1a: Pidgeot|Fly||[still]',
        '|-prepare|p1a: Pidgeot|Fly',
        '|move|p2a: Lickitung|Strength|p1a: Pidgeot|[miss]',
        '|-miss|p2a: Lickitung',
        '|turn|2',
        '|move|p1a: Pidgeot|Fly|p2a: Lickitung',
        '|-damage|p2a: Lickitung|304/383',
        '|move|p2a: Lickitung|Strength|p1a: Pidgeot',
        '|-damage|p1a: Pidgeot|295/369',
        '|turn|3',
      ]);
    }
    // fainting
    {
      const battle = startBattle([
        QKC, HIT, QKC, QKC, QKC, QKC, QKC,
      ], [
        {species: 'Seadra', evs, moves: ['Toxic']},
        {species: 'Ninetales', evs, moves: ['Dig']},
      ], [
        {species: 'Shellder', evs, moves: ['Splash']},
        {species: 'Arcanine', evs, moves: ['Splash']},
      ]);

      battle.p2.pokemon[0].hp = 31;
      const p2hp = battle.p2.pokemon[1].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(15);

      battle.makeChoices('switch 2', 'switch 2');

      battle.makeChoices('move 1', 'move 1');

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);

      battle.makeChoices('', 'switch 2');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      verify(battle, [
        '|move|p1a: Seadra|Toxic|p2a: Shellder',
        '|-status|p2a: Shellder|tox',
        '|move|p2a: Shellder|Splash|p2a: Shellder',
        '|-nothing',
        '|-fail|p2a: Shellder',
        '|-damage|p2a: Shellder|15/263 tox|[from] psn',
        '|turn|2',
        '|switch|p1a: Ninetales|Ninetales, M|349/349',
        '|switch|p2a: Arcanine|Arcanine, M|383/383',
        '|turn|3',
        '|move|p1a: Ninetales|Dig||[still]',
        '|-prepare|p1a: Ninetales|Dig',
        '|move|p2a: Arcanine|Splash|p2a: Arcanine',
        '|-nothing',
        '|-fail|p2a: Arcanine',
        '|turn|4',
        '|switch|p2a: Shellder|Shellder, M|15/263 tox',
        '|-status|p2a: Shellder|psn|[silent]',
        '|-damage|p2a: Shellder|0 fnt|[from] psn',
        '|faint|p2a: Shellder',
        '|switch|p2a: Arcanine|Arcanine, M|383/383',
        '|turn|5',
        '|move|p1a: Ninetales|Dig||[still]',
        '|-prepare|p1a: Ninetales|Dig',
        '|move|p2a: Arcanine|Splash|p2a: Arcanine',
        '|-nothing',
        '|-fail|p2a: Arcanine',
        '|turn|6',
      ]);
    }
  });

  test('Gust/Earthquake effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
      QKC, MISS, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Mew', evs, moves: ['Earthquake', 'Fly']},
    ], [
      {species: 'Suicune', evs, moves: ['Gust', 'Dig']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 65);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 49);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 37);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 130);

    verify(battle, [
      '|move|p1a: Mew|Earthquake|p2a: Suicune',
      '|-damage|p2a: Suicune|338/403',
      '|move|p2a: Suicune|Gust|p1a: Mew',
      '|-damage|p1a: Mew|378/403',
      '|turn|2',
      '|move|p1a: Mew|Fly||[still]',
      '|-prepare|p1a: Mew|Fly',
      '|move|p2a: Suicune|Gust|p1a: Mew',
      '|-damage|p1a: Mew|329/403',
      '|turn|3',
      '|move|p1a: Mew|Fly|p2a: Suicune|[miss]',
      '|-miss|p1a: Mew',
      '|move|p2a: Suicune|Dig||[still]',
      '|-prepare|p2a: Suicune|Dig',
      '|turn|4',
      '|move|p1a: Mew|Earthquake|p2a: Suicune',
      '|-damage|p2a: Suicune|208/403',
      '|move|p2a: Suicune|Dig|p1a: Mew',
      '|-damage|p1a: Mew|292/403',
      '|turn|5',
    ]);
  });

  test('Twister effect', () => {
    const proc = SECONDARY(ranged(51, 256) - 1);
    const no_proc = {...proc, value: proc.value + 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_proc, QKC, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Kingdra', evs, moves: ['Twister']},
    ], [
      {species: 'Hoothoot', evs, moves: ['Fly']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 61);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 120);

    verify(battle, [
      '|move|p1a: Kingdra|Twister|p2a: Hoothoot',
      '|-damage|p2a: Hoothoot|262/323',
      '|move|p2a: Hoothoot|Fly||[still]',
      '|-prepare|p2a: Hoothoot|Fly',
      '|turn|2',
      '|move|p1a: Kingdra|Twister|p2a: Hoothoot',
      '|-damage|p2a: Hoothoot|142/323',
      '|cant|p2a: Hoothoot|flinch',
      '|turn|3',
    ]);
  });

  test('ForceSwitch effect', () => {
    const battle = startBattle([QKC, DRAG(1, 1), QKC, DRAG(1, 1), QKC], [
      {species: 'Zapdos', evs, moves: ['Whirlwind']},
    ], [
      {species: 'Raikou', evs, moves: ['Roar']},
      {species: 'Lugia', evs, moves: ['Fly']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].species.name).toBe('Lugia');

    // Whirlwind can hit through Fly invulnerability
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].species.name).toBe('Raikou');

    verify(battle, [
      '|move|p2a: Raikou|Roar|p1a: Zapdos',
      '|-fail|p1a: Zapdos',
      '|move|p1a: Zapdos|Whirlwind|p2a: Raikou',
      '|drag|p2a: Lugia|Lugia|415/415',
      '|turn|2',
      '|move|p2a: Lugia|Fly||[still]',
      '|-prepare|p2a: Lugia|Fly',
      '|move|p1a: Zapdos|Whirlwind|p2a: Lugia',
      '|drag|p2a: Raikou|Raikou|383/383',
      '|turn|3',
    ]);
  });

  test('Teleport effect', () => {
    const battle = startBattle([QKC, QKC], [
      {species: 'Abra', evs, moves: ['Teleport']},
    ], [
      {species: 'Kadabra', evs, moves: ['Teleport']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Kadabra|Teleport|p2a: Kadabra',
      '|move|p1a: Abra|Teleport|p1a: Abra',
      '|turn|2',
    ]);
  });

  test('Splash effect', () => {
    const battle = startBattle([QKC, QKC],
      [{species: 'Gyarados', evs, moves: ['Splash']}],
      [{species: 'Magikarp', evs, moves: ['Splash']}]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Gyarados|Splash|p1a: Gyarados',
      '|-nothing',
      '|-fail|p1a: Gyarados',
      '|move|p2a: Magikarp|Splash|p2a: Magikarp',
      '|-nothing',
      '|-fail|p2a: Magikarp',
      '|turn|2',
    ]);
  });

  test('Binding effect', () => {
    const battle = startBattle([
      QKC, QKC, HIT, NO_CRIT, MIN_DMG, MIN_WRAP, QKC, QKC, HIT,
      NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG, MIN_WRAP, QKC, QKC,
      HIT, NO_CRIT, MIN_DMG, MIN_WRAP, QKC, HIT, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Shuckle', evs, moves: ['Wrap', 'Splash']},
      {species: 'Scizor', evs, moves: ['Metal Claw', 'Clamp']},
    ], [
      {species: 'Misdreavus', evs, moves: ['Splash']},
      {species: 'Elekid', evs, moves: ['Splash']},
      {species: 'Cleffa', evs, moves: ['Splash', 'Substitute']},
    ]);

    const misdreavus = battle.p2.pokemon[0].hp;
    let elekid = battle.p2.pokemon[1].hp;
    let cleffa = battle.p2.pokemon[2].hp;

    // Can't hit Ghosts
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(misdreavus);

    // Traps for variable turns, but can still attack
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(elekid = elekid - 8 - 18);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['move 1']);

    // Wrapper can switch moves
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(elekid -= 18);

    // Doesn't extend duration if already existing
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(elekid -= 8);

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1']);

    battle.makeChoices('move 1', 'switch 3');
    expect(battle.p2.pokemon[0].hp).toBe(cleffa = cleffa - 9 - 18);

    battle.makeChoices('switch 2', 'move 1');

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    // Creating a Substitute will cause the user to escape a Binding move
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(cleffa = cleffa - 26 - 75);

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    // Binding moves will not trap the target if it is behind a Substitute
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(cleffa);

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'switch 3', 'move 1', 'move 2']);

    verify(battle, [
      '|move|p2a: Misdreavus|Splash|p2a: Misdreavus',
      '|-nothing',
      '|-fail|p2a: Misdreavus',
      '|move|p1a: Shuckle|Wrap|p2a: Misdreavus',
      '|-immune|p2a: Misdreavus',
      '|turn|2',
      '|switch|p2a: Elekid|Elekid, M|293/293',
      '|move|p1a: Shuckle|Wrap|p2a: Elekid',
      '|-damage|p2a: Elekid|285/293',
      '|-activate|p2a: Elekid|move: Wrap|[of] p1a: Shuckle',
      '|-damage|p2a: Elekid|267/293|[from] move: Wrap|[partiallytrapped]',
      '|turn|3',
      '|move|p2a: Elekid|Splash|p2a: Elekid',
      '|-nothing',
      '|-fail|p2a: Elekid',
      '|move|p1a: Shuckle|Splash|p1a: Shuckle',
      '|-nothing',
      '|-fail|p1a: Shuckle',
      '|-damage|p2a: Elekid|249/293|[from] move: Wrap|[partiallytrapped]',
      '|turn|4',
      '|move|p2a: Elekid|Splash|p2a: Elekid',
      '|-nothing',
      '|-fail|p2a: Elekid',
      '|move|p1a: Shuckle|Wrap|p2a: Elekid',
      '|-damage|p2a: Elekid|241/293',
      '|-end|p2a: Elekid|Wrap|[partiallytrapped]',
      '|turn|5',
      '|switch|p2a: Cleffa|Cleffa, M|303/303',
      '|move|p1a: Shuckle|Wrap|p2a: Cleffa',
      '|-damage|p2a: Cleffa|294/303',
      '|-activate|p2a: Cleffa|move: Wrap|[of] p1a: Shuckle',
      '|-damage|p2a: Cleffa|276/303|[from] move: Wrap|[partiallytrapped]',
      '|turn|6',
      '|switch|p1a: Scizor|Scizor, M|343/343',
      '|move|p2a: Cleffa|Splash|p2a: Cleffa',
      '|-nothing',
      '|-fail|p2a: Cleffa',
      '|turn|7',
      '|move|p1a: Scizor|Clamp|p2a: Cleffa',
      '|-damage|p2a: Cleffa|250/303',
      '|-activate|p2a: Cleffa|move: Clamp|[of] p1a: Scizor',
      '|move|p2a: Cleffa|Substitute|p2a: Cleffa',
      '|-start|p2a: Cleffa|Substitute',
      '|-damage|p2a: Cleffa|175/303',
      '|turn|8',
      '|move|p1a: Scizor|Clamp|p2a: Cleffa',
      '|-activate|p2a: Cleffa|Substitute|[damage]',
      '|move|p2a: Cleffa|Splash|p2a: Cleffa',
      '|-nothing',
      '|-fail|p2a: Cleffa',
      '|turn|9',
    ]);
  });

  test('JumpKick effect', () => {
    const battle = startBattle([
      QKC, QKC, MISS, CRIT, MIN_DMG, HIT, CRIT, MAX_DMG,
      QKC, MISS, NO_CRIT, MIN_DMG, MISS, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Hitmonlee', evs, moves: ['Jump Kick', 'Substitute']},
    ], [
      {species: 'Hitmonlee', level: 99, evs, moves: ['High Jump Kick', 'Substitute']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 75);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(75);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 75);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(75);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 31);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(75);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 15);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 21);
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
      '|-damage|p1a: Hitmonlee|197/303',
      '|move|p2a: Hitmonlee|High Jump Kick|p1a: Hitmonlee',
      '|-crit|p1a: Hitmonlee',
      '|-end|p1a: Hitmonlee|Substitute',
      '|turn|3',
      '|move|p1a: Hitmonlee|Jump Kick|p2a: Hitmonlee|[miss]',
      '|-miss|p1a: Hitmonlee',
      '|-damage|p1a: Hitmonlee|182/303',
      '|move|p2a: Hitmonlee|High Jump Kick|p1a: Hitmonlee|[miss]',
      '|-miss|p2a: Hitmonlee',
      '|-damage|p2a: Hitmonlee|204/300',
      '|turn|4',
    ]);
  });

  test('Recoil effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MAX_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
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

    // Still receives damage if the move breaks the target's Substitute, though only 1 HP
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 88);

    // Inflicts 1/4 of damage dealt to user as recoil
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 57);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 14);

    verify(battle, [
      '|move|p2a: Tauros|Double-Edge|p1a: Slowpoke',
      '|-damage|p1a: Slowpoke|0 fnt',
      '|-damage|p2a: Tauros|352/353|[from] Recoil|[of] p1a: Slowpoke',
      '|faint|p1a: Slowpoke',
      '|switch|p1a: Rhydon|Rhydon, M|413/413',
      '|turn|2',
      '|move|p2a: Tauros|Substitute|p2a: Tauros',
      '|-start|p2a: Tauros|Substitute',
      '|-damage|p2a: Tauros|264/353',
      '|move|p1a: Rhydon|Take Down|p2a: Tauros',
      '|-end|p2a: Tauros|Substitute',
      '|-damage|p1a: Rhydon|412/413|[from] Recoil|[of] p2a: Tauros',
      '|turn|3',
      '|move|p2a: Tauros|Double-Edge|p1a: Rhydon',
      '|-resisted|p1a: Rhydon',
      '|-damage|p1a: Rhydon|355/413',
      '|-damage|p2a: Tauros|250/353|[from] Recoil|[of] p1a: Rhydon',
      '|move|p1a: Rhydon|Splash|p1a: Rhydon',
      '|-nothing',
      '|-fail|p1a: Rhydon',
      '|turn|4',
    ]);
  });

  test('Struggle effect', () => {
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
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

    // Still deals recoil damage if the move breaks the target's Substitute
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(1);
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 15);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(0);

    // Struggle recoil inflicts at least 1 HP
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);

    battle.makeChoices('switch 2', '');

    // Deals typeless damage and inflicts 1/4 of damage dealt to user as recoil
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 33);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 8);

    verify(battle, [
      '|move|p2a: Arcanine|Splash|p2a: Arcanine',
      '|-nothing',
      '|-fail|p2a: Arcanine',
      '|move|p1a: Abra|Substitute|p1a: Abra',
      '|-start|p1a: Abra|Substitute',
      '|-damage|p1a: Abra|1/253',
      '|turn|2',
      '|move|p2a: Arcanine|Struggle|p1a: Abra',
      '|-end|p1a: Abra|Substitute',
      '|-damage|p2a: Arcanine|382/383|[from] Recoil|[of] p1a: Abra',
      '|move|p1a: Abra|Splash|p1a: Abra',
      '|-nothing',
      '|-fail|p1a: Abra',
      '|turn|3',
      '|move|p2a: Arcanine|Struggle|p1a: Abra',
      '|-damage|p1a: Abra|0 fnt',
      '|-damage|p2a: Arcanine|381/383|[from] Recoil|[of] p1a: Abra',
      '|faint|p1a: Abra',
      '|switch|p1a: Golem|Golem, M|363/363',
      '|turn|4',
      '|move|p2a: Arcanine|Struggle|p1a: Golem',
      '|-damage|p1a: Golem|330/363',
      '|-damage|p2a: Arcanine|373/383|[from] Recoil|[of] p1a: Golem',
      '|move|p1a: Golem|Harden|p1a: Golem',
      '|-boost|p1a: Golem|def|1',
      '|turn|5',
    ]);
  });

  test('Thrashing effect', () => {
    // normal
    {
      const battle = startBattle([
        QKC, HIT, CFZ(5), QKC, CFZ_CAN, NO_CRIT, MIN_DMG, THRASH(2), MISS, THRASH(3),
        QKC, CFZ_CAN, NO_CRIT, MIN_DMG, CFZ(5), MISS, QKC, CFZ_CAN, PAR_CANT, QKC,
      ], [
        {species: 'Nidoking', evs, moves: ['Thrash', 'Thunder Wave', 'Sand-Attack']},
        {species: 'Nidoqueen', evs, moves: ['Poison Sting']},
      ], [
        {species: 'Vileplume', evs, moves: ['Petal Dance', 'Confuse Ray']},
        {species: 'Victreebel', evs, moves: ['Razor Leaf']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      let pp = battle.p1.pokemon[0].moveSlots[0].pp;

      battle.makeChoices('move 3', 'move 2');
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p2.pokemon[0].boosts.accuracy).toBe(-1);

      // Thrashing locks user in for 2-3 turns whether you hit or not
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(4);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);

      expect(choices(battle, 'p1')).toEqual(['move 1']);
      expect(choices(battle, 'p2')).toEqual(['move 1']);

      // Thrashing confuses you even if already confused
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);
      expect(choices(battle, 'p2')).toEqual(['move 1']);

      // Thrashing doesn't confuse you if the user is prevented from moving
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].status).toBe('par');
      expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);
      expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      verify(battle, [
        '|move|p1a: Nidoking|Sand Attack|p2a: Vileplume',
        '|-unboost|p2a: Vileplume|accuracy|1',
        '|move|p2a: Vileplume|Confuse Ray|p1a: Nidoking',
        '|-start|p1a: Nidoking|confusion',
        '|turn|2',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume',
        '|-damage|p2a: Vileplume|285/353',
        '|move|p2a: Vileplume|Petal Dance|p1a: Nidoking|[miss]',
        '|-miss|p2a: Vileplume',
        '|turn|3',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thrash|p2a: Vileplume',
        '|-damage|p2a: Vileplume|217/353',
        '|-start|p1a: Nidoking|confusion|[silent]',
        '|move|p2a: Vileplume|Petal Dance|p1a: Nidoking|[miss]',
        '|-miss|p2a: Vileplume',
        '|turn|4',
        '|-activate|p1a: Nidoking|confusion',
        '|move|p1a: Nidoking|Thunder Wave|p2a: Vileplume',
        '|-status|p2a: Vileplume|par',
        '|cant|p2a: Vileplume|par',
        '|turn|5',
      ]);
    }
    // immune
    {
      const battle = startBattle([QKC, NO_CRIT, MIN_DMG, THRASH(3), QKC, QKC, CFZ(5), QKC], [
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
        '|switch|p2a: Goldeen|Goldeen, M|293/293',
        '|move|p1a: Mankey|Thrash|p2a: Goldeen',
        '|-damage|p2a: Goldeen|216/293',
        '|turn|2',
        '|switch|p2a: Gastly|Gastly, M|263/263',
        '|move|p1a: Mankey|Thrash|p2a: Gastly',
        '|-immune|p2a: Gastly',
        '|turn|3',
        '|move|p2a: Gastly|Splash|p2a: Gastly',
        '|-nothing',
        '|-fail|p2a: Gastly',
        '|move|p1a: Mankey|Thrash|p2a: Gastly',
        '|-immune|p2a: Gastly',
        '|-start|p1a: Mankey|confusion|[silent]',
        '|turn|4',
      ]);
    }
  });

  test('FixedDamage effect', () => {
    const battle = startBattle([QKC, HIT, QKC, QKC], [
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
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp2);
    expect(battle.p2.pokemon[1].hp).toEqual(p2hp1 - 20);

    verify(battle, [
      '|move|p1a: Voltorb|Sonic Boom|p2a: Dratini',
      '|-damage|p2a: Dratini|265/285',
      '|move|p2a: Dratini|Dragon Rage|p1a: Voltorb',
      '|-damage|p1a: Voltorb|243/283',
      '|turn|2',
      '|switch|p2a: Gastly|Gastly, M|263/263',
      '|move|p1a: Voltorb|Sonic Boom|p2a: Gastly',
      '|-immune|p2a: Gastly',
      '|turn|3',
    ]);
  });

  test('LevelDamage effect', () => {
    const battle = startBattle([QKC, QKC], [
      {species: 'Murkrow', evs, level: 22, moves: ['Night Shade']},
    ], [
      {species: 'Clefairy', evs, level: 16, moves: ['Seismic Toss']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 16);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

    verify(battle, [
      '|move|p1a: Murkrow|Night Shade|p2a: Clefairy',
      '|-immune|p2a: Clefairy',
      '|move|p2a: Clefairy|Seismic Toss|p1a: Murkrow',
      '|-damage|p1a: Murkrow|62/78',
      '|turn|2',
    ]);
  });

  test('Psywave effect', () => {
    const PSY_MAX = {key: 'data/mods/gen2/moves.ts:584:16', value: MAX};
    const PSY_MIN = {...PSY_MAX, value: MIN};
    const battle = startBattle([QKC, HIT, PSY_MAX, HIT, PSY_MIN, QKC], [
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
      '|-damage|p1a: Gengar|193/194',
      '|turn|2',
    ]);
  });

  test('SuperFang effect', () => {
    const battle = startBattle([QKC, HIT, HIT, QKC, QKC], [
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
    expect(battle.p1.pokemon[0].hp).toBe(293);

    verify(battle, [
      '|move|p1a: Raticate|Super Fang|p2a: Rattata',
      '|-damage|p2a: Rattata|132/263',
      '|move|p2a: Rattata|Super Fang|p1a: Raticate',
      '|-damage|p1a: Raticate|0 fnt',
      '|faint|p1a: Raticate',
      '|switch|p1a: Haunter|Haunter, M|293/293',
      '|turn|2',
      '|move|p1a: Haunter|Dream Eater|p2a: Rattata',
      '|-immune|p2a: Rattata',
      '|move|p2a: Rattata|Super Fang|p1a: Haunter',
      '|-immune|p1a: Haunter',
      '|turn|3',
    ]);
  });

  test('Disable effect', () => {
    const proc = {key: 'data/mods/gen2/moves.ts:771:40', value: MIN};
    const battle = startBattle([
      QKC, HIT, QKC, HIT, DISABLE_DURATION(3), QKC, HIT,
      SLP(2), proc, QKC, HIT, DISABLE_DURATION(3), QKC,
    ], [
      {species: 'Hypno', evs, moves: ['Disable', 'Hypnosis']},
    ], [
      {species: 'Porygon2', evs, moves: ['Splash', 'Sleep Talk']},
    ]);

    battle.p2.pokemon[0].moveSlots[1].pp = 1;

    // Fails if no last used move
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

    // Disables last used move
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['disable'].duration).toBe(1);

    expect(choices(battle, 'p2')).toEqual(['move 2']);

    // Can still call through Sleep Talk
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

    // Can call move after duration elapsed, can't disable 0 PP moves
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Hypno|Disable|p2a: Porygon2',
      '|-fail|p2a: Porygon2',
      '|move|p2a: Porygon2|Splash|p2a: Porygon2',
      '|-nothing',
      '|-fail|p2a: Porygon2',
      '|turn|2',
      '|move|p1a: Hypno|Disable|p2a: Porygon2',
      '|-start|p2a: Porygon2|Disable|Splash',
      '|cant|p2a: Porygon2|Disable|Splash',
      '|turn|3',
      '|move|p1a: Hypno|Hypnosis|p2a: Porygon2',
      '|-status|p2a: Porygon2|slp|[from] move: Hypnosis',
      '|cant|p2a: Porygon2|slp',
      '|move|p2a: Porygon2|Sleep Talk|p2a: Porygon2',
      '|move|p2a: Porygon2|Splash|p2a: Porygon2|[from]Sleep Talk',
      '|-nothing',
      '|-fail|p2a: Porygon2',
      '|-end|p2a: Porygon2|move: Disable',
      '|turn|4',
      '|move|p1a: Hypno|Disable|p2a: Porygon2',
      '|-fail|p2a: Porygon2',
      '|cant|p2a: Porygon2|slp',
      '|turn|5',
    ]);
  });

  test('Mist effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, QKC, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, QKC, QKC,
    ], [
      {species: 'Articuno', evs, moves: ['Mist', 'Peck', 'Baton Pass']},
      {species: 'Suicune', evs, moves: ['Surf']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Aurora Beam', 'Growl', 'Haze']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Mist protects against secondary effects
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 43);
    expect(battle.p1.pokemon[0].volatiles['mist']).toBeDefined();
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);

    // Mist protects against primary stat lowering effects
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    // Haze doesn't end Mist's effect / Mist can be passed via Baton Pass
    battle.makeChoices('move 3', 'move 2');
    battle.makeChoices('switch 2', '');

    expect(battle.p1.pokemon[0].volatiles['mist']).toBeDefined();
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Articuno|Mist|p1a: Articuno',
      '|-start|p1a: Articuno|Mist',
      '|move|p2a: Vaporeon|Aurora Beam|p1a: Articuno',
      '|-damage|p1a: Articuno|340/383',
      '|turn|2',
      '|move|p1a: Articuno|Peck|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|415/463',
      '|move|p2a: Vaporeon|Growl|p1a: Articuno',
      '|-activate|p1a: Articuno|move: Mist',
      '|turn|3',
      '|move|p1a: Articuno|Peck|p2a: Vaporeon',
      '|-damage|p2a: Vaporeon|367/463',
      '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
      '|-clearallboost',
      '|turn|4',
      '|move|p1a: Articuno|Baton Pass|p1a: Articuno',
      '|switch|p1a: Suicune|Suicune|403/403|[from] Baton Pass',
      '|move|p2a: Vaporeon|Growl|p1a: Suicune',
      '|-activate|p1a: Suicune|move: Mist',
      '|turn|5',
    ]);
  });

  test('HyperBeam effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MAX_DMG, QKC, QKC, HIT, NO_CRIT, MAX_DMG,
      QKC, QKC, HIT, NO_CRIT, MIN_DMG, QKC,
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

    // Requires recharge if it knocks out a Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(jolteon -= 83);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(jolteon);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    // Requires a recharge if it knocks out opponent
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(0);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual([]);
    expect(choices(battle, 'p2')).toEqual(['switch 2']);

    battle.makeChoices('', 'switch 2');

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(chansey);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(chansey -= 442);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    verify(battle, [
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|17/333',
      '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
      '|-end|p2a: Jolteon|Substitute',
      '|-mustrecharge|p1a: Tauros',
      '|turn|2',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|-fail|p2a: Jolteon',
      '|cant|p1a: Tauros|recharge',
      '|turn|3',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|-fail|p2a: Jolteon',
      '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
      '|-damage|p2a: Jolteon|0 fnt',
      '|-mustrecharge|p1a: Tauros',
      '|faint|p2a: Jolteon',
      '|switch|p2a: Chansey|Chansey, F|703/703',
      '|turn|4',
      '|cant|p1a: Tauros|recharge',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|-fail|p2a: Chansey',
      '|turn|5',
      '|move|p1a: Tauros|Hyper Beam|p2a: Chansey',
      '|-damage|p2a: Chansey|261/703',
      '|-mustrecharge|p1a: Tauros',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|-fail|p2a: Chansey',
      '|turn|6',
    ]);
  });

  test('Counter effect', () => {
    {
      const battle = startBattle([
        QKC, NO_CRIT, MIN_DMG, QKC, QKC, QKC, HIT, QKC, NO_CRIT, MIN_DMG,
        QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, QKC, SLP(1), QKC, QKC, HIT,
        QKC, QKC, MISS, QKC, MISS, QKC,
      ], [
        {species: 'Snorlax', evs, moves: ['Counter', 'Dragon Rage', 'Hidden Power']},
        {species: 'Misdreavus', evs, moves: ['Splash', 'Counter', 'Sonic Boom']},
      ], [
        {species: 'Miltank', evs, moves: ['Earthquake', 'Counter', 'Sonic Boom', 'Beat Up']},
        {species: 'Parasect', evs, moves: ['Spore', 'Counter', 'Guillotine', 'Fissure']},
      ]);

      let snorlax = battle.p1.pokemon[0].hp;
      const misdreavus = battle.p1.pokemon[1].hp;
      let miltank = battle.p2.pokemon[0].hp;
      let parasect = battle.p2.pokemon[1].hp;

      // Works for all types of Physical moves, even those which are not Normal / Fighting
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 81);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 162);

      // Fails on Special attacks
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 40);

      // Cannot Counter an opponent's Counter
      battle.makeChoices('move 1', 'move 2');

      // Works on fixed damage moves including Sonic Boom
      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 20);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 40);

      // Counter works against Hidden Power regardless of type
      battle.makeChoices('move 3', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 98);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 49);

      // Counter works against Beat Up despite being Special
      battle.makeChoices('move 1', 'move 4');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax = snorlax - 10 - 11);
      // expect(battle.p2.pokemon[0].hp).toBe(miltank -= 0);
      expect(battle.p2.pokemon[0].hp).toBe(miltank);

      battle.makeChoices('switch 2', 'switch 2');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].status).toBe('slp');

      // When slept, Counters' negative priority gets preserved
      battle.makeChoices('move 2', 'move 1');

      // Does not ignore Ghost-type immunity
      battle.makeChoices('move 3', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(misdreavus);
      expect(battle.p2.pokemon[0].hp).toBe(parasect -= 20);
      expect(battle.p1.pokemon[0].status).toBe('');

      battle.makeChoices('switch 2', 'move 2');

      // Fissure/Horn Drill (but not Guillotine) can be countered for maximum damage
      battle.makeChoices('move 1', 'move 3');

      battle.makeChoices('move 1', 'move 4');
      // expect(battle.p2.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(parasect);

      verify(battle, [
        '|move|p2a: Miltank|Earthquake|p1a: Snorlax',
        '|-damage|p1a: Snorlax|442/523',
        '|move|p1a: Snorlax|Counter|p2a: Miltank',
        '|-damage|p2a: Miltank|231/393',
        '|turn|2',
        '|move|p1a: Snorlax|Dragon Rage|p2a: Miltank',
        '|-damage|p2a: Miltank|191/393',
        '|move|p2a: Miltank|Counter|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|turn|3',
        '|move|p2a: Miltank|Counter|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|move|p1a: Snorlax|Counter|p2a: Miltank',
        '|-damage|p2a: Miltank|191/393',
        '|turn|4',
        '|move|p2a: Miltank|Sonic Boom|p1a: Snorlax',
        '|-damage|p1a: Snorlax|422/523',
        '|move|p1a: Snorlax|Counter|p2a: Miltank',
        '|-damage|p2a: Miltank|151/393',
        '|turn|5',
        '|move|p1a: Snorlax|Hidden Power|p2a: Miltank',
        '|-damage|p2a: Miltank|102/393',
        '|move|p2a: Miltank|Counter|p1a: Snorlax',
        '|-damage|p1a: Snorlax|324/523',
        '|turn|6',
        '|move|p2a: Miltank|Beat Up|p1a: Snorlax',
        '|-activate|p2a: Miltank|move: Beat Up|[of] Miltank',
        '|-damage|p1a: Snorlax|314/523',
        '|-activate|p2a: Miltank|move: Beat Up|[of] Parasect',
        '|-damage|p1a: Snorlax|303/523',
        '|-hitcount|p1a: Snorlax|2',
        '|move|p1a: Snorlax|Counter|p2a: Miltank',
        '|-fail|p2a: Miltank',
        '|turn|7',
        '|switch|p2a: Parasect|Parasect, M|323/323',
        '|switch|p1a: Misdreavus|Misdreavus, M|323/323',
        '|turn|8',
        '|move|p1a: Misdreavus|Splash|p1a: Misdreavus',
        '|-nothing',
        '|-fail|p1a: Misdreavus',
        '|move|p2a: Parasect|Spore|p1a: Misdreavus',
        '|-status|p1a: Misdreavus|slp|[from] move: Spore',
        '|turn|9',
        '|move|p2a: Parasect|Spore|p1a: Misdreavus',
        '|-fail|p1a: Misdreavus|slp',
        '|cant|p1a: Misdreavus|slp',
        '|turn|10',
        '|-curestatus|p1a: Misdreavus|slp|[msg]',
        '|move|p1a: Misdreavus|Sonic Boom|p2a: Parasect',
        '|-damage|p2a: Parasect|303/323',
        '|move|p2a: Parasect|Counter|p1a: Misdreavus',
        '|-immune|p1a: Misdreavus',
        '|turn|11',
        '|switch|p1a: Snorlax|Snorlax, M|303/523',
        '|move|p2a: Parasect|Counter|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|turn|12',
        '|move|p2a: Parasect|Guillotine|p1a: Snorlax|[miss]',
        '|-miss|p2a: Parasect',
        '|move|p1a: Snorlax|Counter|p2a: Parasect',
        '|-fail|p2a: Parasect',
        '|turn|13',
        '|move|p2a: Parasect|Fissure|p1a: Snorlax|[miss]',
        '|-miss|p2a: Parasect',
        '|move|p1a: Snorlax|Counter|p2a: Parasect',
        '|-fail|p2a: Parasect',
        '|turn|14',
      ]);
    }
    // Substitute
    {
      const battle = startBattle([QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
        {species: 'Snorlax', evs, moves: ['Reflect', 'Body Slam']},
      ], [
        {species: 'Chansey', evs, moves: ['Substitute', 'Counter']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 175);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 175);

      verify(battle, [
        '|move|p2a: Chansey|Substitute|p2a: Chansey',
        '|-start|p2a: Chansey|Substitute',
        '|-damage|p2a: Chansey|528/703',
        '|move|p1a: Snorlax|Reflect|p1a: Snorlax',
        '|-sidestart|p1: Player 1|Reflect',
        '|turn|2',
        '|move|p1a: Snorlax|Body Slam|p2a: Chansey',
        '|-end|p2a: Chansey|Substitute',
        '|move|p2a: Chansey|Counter|p1a: Snorlax',
        '|-damage|p1a: Snorlax|523/523',
        '|turn|3',
      ]);
    }
  });

  test('MirrorCoat effect', () => {
    {
      const battle = startBattle([
        QKC, NO_CRIT, MIN_DMG, QKC, HIT, QKC, QKC, QKC, NO_CRIT, MIN_DMG,
        QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, QKC, SLP(1), QKC, QKC, QKC,
      ], [
        {species: 'Snorlax', evs, moves: ['Mirror Coat', 'Sonic Boom', 'Hidden Power']},
        {species: 'Tyranitar', evs, moves: ['Splash', 'Mirror Coat', 'Dragon Rage']},
      ], [
        {species: 'Miltank', evs, moves: ['Surf', 'Mirror Coat', 'Dragon Rage', 'Beat Up']},
        {species: 'Parasect', evs, moves: ['Spore', 'Mirror Coat']},
      ]);

      let snorlax = battle.p1.pokemon[0].hp;
      const tyranitar = battle.p1.pokemon[1].hp;
      let miltank = battle.p2.pokemon[0].hp;
      let parasect = battle.p2.pokemon[1].hp;

      // Works for all types of Special moves
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 39);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 78);

      // Fails on Physical attacks
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 20);

      // Cannot Mirror Coat an opponent's Mirror Coat
      battle.makeChoices('move 1', 'move 2');

      // Works on fixed damage moves including Dragon Rage
      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax -= 40);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 80);

      // Mirror Coat fails against Hidden Power regardless of type
      battle.makeChoices('move 3', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 49);

      // Mirror Coat fails against Beat Up despite being Special
      battle.makeChoices('move 1', 'move 4');
      expect(battle.p1.pokemon[0].hp).toBe(snorlax = snorlax - 10 - 11);
      // expect(battle.p2.pokemon[0].hp).toBe(miltank);
      expect(battle.p2.pokemon[0].hp).toBe(miltank -= 22);

      battle.makeChoices('switch 2', 'switch 2');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].status).toBe('slp');

      // When slept, Mirror Coat's negative priority gets preserved
      battle.makeChoices('move 2', 'move 1');

      // Does not ignore Dark-type immunity
      battle.makeChoices('move 3', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(tyranitar);
      expect(battle.p2.pokemon[0].hp).toBe(parasect -= 40);
      expect(battle.p1.pokemon[0].status).toBe('');

      verify(battle, [
        '|move|p2a: Miltank|Surf|p1a: Snorlax',
        '|-damage|p1a: Snorlax|484/523',
        '|move|p1a: Snorlax|Mirror Coat|p2a: Miltank',
        '|-damage|p2a: Miltank|315/393',
        '|turn|2',
        '|move|p1a: Snorlax|Sonic Boom|p2a: Miltank',
        '|-damage|p2a: Miltank|295/393',
        '|move|p2a: Miltank|Mirror Coat|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|turn|3',
        '|move|p2a: Miltank|Mirror Coat|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|move|p1a: Snorlax|Mirror Coat|p2a: Miltank',
        '|-damage|p2a: Miltank|295/393',
        '|turn|4',
        '|move|p2a: Miltank|Dragon Rage|p1a: Snorlax',
        '|-damage|p1a: Snorlax|444/523',
        '|move|p1a: Snorlax|Mirror Coat|p2a: Miltank',
        '|-damage|p2a: Miltank|215/393',
        '|turn|5',
        '|move|p1a: Snorlax|Hidden Power|p2a: Miltank',
        '|-damage|p2a: Miltank|166/393',
        '|move|p2a: Miltank|Mirror Coat|p1a: Snorlax',
        '|-fail|p1a: Snorlax',
        '|turn|6',
        '|move|p2a: Miltank|Beat Up|p1a: Snorlax',
        '|-activate|p2a: Miltank|move: Beat Up|[of] Miltank',
        '|-damage|p1a: Snorlax|434/523',
        '|-activate|p2a: Miltank|move: Beat Up|[of] Parasect',
        '|-damage|p1a: Snorlax|423/523',
        '|-hitcount|p1a: Snorlax|2',
        '|move|p1a: Snorlax|Mirror Coat|p2a: Miltank',
        '|-damage|p2a: Miltank|144/393',
        '|turn|7',
        '|switch|p2a: Parasect|Parasect, M|323/323',
        '|switch|p1a: Tyranitar|Tyranitar, M|403/403',
        '|turn|8',
        '|move|p1a: Tyranitar|Splash|p1a: Tyranitar',
        '|-nothing',
        '|-fail|p1a: Tyranitar',
        '|move|p2a: Parasect|Spore|p1a: Tyranitar',
        '|-status|p1a: Tyranitar|slp|[from] move: Spore',
        '|turn|9',
        '|move|p2a: Parasect|Spore|p1a: Tyranitar',
        '|-fail|p1a: Tyranitar|slp',
        '|cant|p1a: Tyranitar|slp',
        '|turn|10',
        '|-curestatus|p1a: Tyranitar|slp|[msg]',
        '|move|p1a: Tyranitar|Dragon Rage|p2a: Parasect',
        '|-damage|p2a: Parasect|283/323',
        '|move|p2a: Parasect|Mirror Coat|p1a: Tyranitar',
        '|-immune|p1a: Tyranitar',
        '|turn|11',
      ]);
    }
    // Substitute
    {
      const battle = startBattle([QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
        {species: 'Ho-Oh', evs, moves: ['Light Screen', 'Flamethrower']},
      ], [
        {species: 'Alakazam', evs, moves: ['Substitute', 'Mirror Coat']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 78);

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 78);

      verify(battle, [
        '|move|p2a: Alakazam|Substitute|p2a: Alakazam',
        '|-start|p2a: Alakazam|Substitute',
        '|-damage|p2a: Alakazam|235/313',
        '|move|p1a: Ho-Oh|Light Screen|p1a: Ho-Oh',
        '|-sidestart|p1: Player 1|move: Light Screen',
        '|turn|2',
        '|move|p1a: Ho-Oh|Flamethrower|p2a: Alakazam',
        '|-end|p2a: Alakazam|Substitute',
        '|move|p2a: Alakazam|Mirror Coat|p1a: Ho-Oh',
        '|-damage|p1a: Ho-Oh|415/415',
        '|turn|3',
      ]);
    }
  });

  test('Heal effect', () => {
    const battle = startBattle([QKC, QKC, QKC], [
      {species: 'Alakazam', evs, moves: ['Recover']},
    ], [
      {species: 'Chansey', evs, moves: ['Soft-Boiled']},
    ]);

    battle.p1.pokemon[0].hp = 1;
    battle.p2.pokemon[0].hp = 448;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 157);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 255);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 155);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Alakazam|Recover|p1a: Alakazam',
      '|-heal|p1a: Alakazam|158/313',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-heal|p2a: Chansey|703/703',
      '|turn|2',
      '|move|p1a: Alakazam|Recover|p1a: Alakazam',
      '|-heal|p1a: Alakazam|313/313',
      '|move|p2a: Chansey|Soft-Boiled|p2a: Chansey',
      '|-fail|p2a: Chansey',
      '|turn|3',
    ]);
  });

  test('WeatherHeal effect', () => {
    const no_brn = SECONDARY(ranged(25, 256));
    const battle = startBattle([
      QKC, CRIT, MIN_DMG, no_brn, QKC, QKC, QKC, CRIT, MAX_DMG, no_brn, QKC, QKC,
    ], [
      {species: 'Sunkern', evs, moves: ['Synthesis', 'Sunny Day']},
    ], [
      {species: 'Wooper', evs, moves: ['Flamethrower', 'Rain Dance', 'Ember', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    // Fails if at full health
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 255);

    // Heals 50% regularly
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 131);

    // Heals 25% in non-Sunny weather
    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 65);

    battle.makeChoices('move 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 192);

    // Heals 100% in Sunny weather
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 251);

    verify(battle, [
      '|move|p1a: Sunkern|Synthesis|p1a: Sunkern',
      '|move|p2a: Wooper|Flamethrower|p1a: Sunkern',
      '|-crit|p1a: Sunkern',
      '|-supereffective|p1a: Sunkern',
      '|-damage|p1a: Sunkern|8/263',
      '|turn|2',
      '|move|p1a: Sunkern|Synthesis|p1a: Sunkern',
      '|-heal|p1a: Sunkern|139/263',
      '|move|p2a: Wooper|Rain Dance|p2a: Wooper',
      '|-weather|RainDance',
      '|-weather|RainDance|[upkeep]',
      '|turn|3',
      '|move|p1a: Sunkern|Synthesis|p1a: Sunkern',
      '|-heal|p1a: Sunkern|204/263',
      '|move|p2a: Wooper|Splash|p2a: Wooper',
      '|-nothing',
      '|-fail|p2a: Wooper',
      '|-weather|RainDance|[upkeep]',
      '|turn|4',
      '|move|p1a: Sunkern|Sunny Day|p1a: Sunkern',
      '|-weather|SunnyDay',
      '|move|p2a: Wooper|Ember|p1a: Sunkern',
      '|-crit|p1a: Sunkern',
      '|-supereffective|p1a: Sunkern',
      '|-damage|p1a: Sunkern|12/263',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|5',
      '|move|p1a: Sunkern|Synthesis|p1a: Sunkern',
      '|-heal|p1a: Sunkern|263/263',
      '|move|p2a: Wooper|Rain Dance|p2a: Wooper',
      '|-weather|RainDance',
      '|-weather|RainDance|[upkeep]',
      '|turn|6',
    ]);
  });

  test('Rest effect', () => {
    const proc = {key: 'data/mods/gen2/moves.ts:771:40', value: MIN};
    const battle = startBattle([
      QKC, HIT, QKC, QKC, SLP(8), NO_CRIT, MIN_DMG, QKC, proc, QKC, QKC, QKC, QKC,
    ], [
      {species: 'Sunflora', evs, moves: ['Toxic', 'Splash', 'Pound']},
    ], [
      {species: 'Dewgong', evs, moves: ['Rest', 'Safeguard', 'Sleep Talk']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    // Fails at full HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].status).toBe('tox');

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 23);

    // Works through Safeguard, puts user to sleep to fully heal HP and removes status
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 28);
    expect(battle.p2.pokemon[0].status).toBe('slp');

    // Can still be called through Sleep Talk to restore HP and reset sleep turns
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 2', 'move 1');

    // Can attack on the 3rd turn
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].status).toBe('');

    verify(battle, [
      '|move|p2a: Dewgong|Rest|p2a: Dewgong',
      '|-fail|p2a: Dewgong',
      '|move|p1a: Sunflora|Toxic|p2a: Dewgong',
      '|-status|p2a: Dewgong|tox',
      '|turn|2',
      '|move|p2a: Dewgong|Rest|p2a: Dewgong',
      '|-fail|p2a: Dewgong',
      '|-damage|p2a: Dewgong|360/383 tox|[from] psn',
      '|move|p1a: Sunflora|Splash|p1a: Sunflora',
      '|-nothing',
      '|-fail|p1a: Sunflora',
      '|turn|3',
      '|move|p2a: Dewgong|Rest|p2a: Dewgong',
      '|-status|p2a: Dewgong|slp|[from] move: Rest',
      '|-heal|p2a: Dewgong|383/383 slp|[silent]',
      '|move|p1a: Sunflora|Pound|p2a: Dewgong',
      '|-damage|p2a: Dewgong|355/383 slp',
      '|turn|4',
      '|cant|p2a: Dewgong|slp',
      '|move|p2a: Dewgong|Sleep Talk|p2a: Dewgong',
      '|move|p2a: Dewgong|Rest|p2a: Dewgong|[from]Sleep Talk',
      '|-status|p2a: Dewgong|slp|[from] move: Rest',
      '|-heal|p2a: Dewgong|383/383 slp|[silent]',
      '|move|p1a: Sunflora|Splash|p1a: Sunflora',
      '|-nothing',
      '|-fail|p1a: Sunflora',
      '|turn|5',
      '|cant|p2a: Dewgong|slp',
      '|move|p1a: Sunflora|Splash|p1a: Sunflora',
      '|-nothing',
      '|-fail|p1a: Sunflora',
      '|turn|6',
      '|cant|p2a: Dewgong|slp',
      '|move|p1a: Sunflora|Splash|p1a: Sunflora',
      '|-nothing',
      '|-fail|p1a: Sunflora',
      '|turn|7',
      '|-curestatus|p2a: Dewgong|slp|[msg]',
      '|move|p2a: Dewgong|Safeguard|p2a: Dewgong',
      '|-sidestart|p2: Player 2|Safeguard',
      '|move|p1a: Sunflora|Splash|p1a: Sunflora',
      '|-nothing',
      '|-fail|p1a: Sunflora',
      '|turn|8',
    ]);
  });

  test('DrainHP effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, QKC,
    ], [
      {species: 'Slowpoke', evs, moves: ['Splash']},
      {species: 'Butterfree', evs, moves: ['Mega Drain', 'Substitute']},
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

    // Draining moves always miss against Substitute
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 80);

    verify(battle, [
      '|move|p2a: Parasect|Leech Life|p1a: Slowpoke',
      '|-supereffective|p1a: Slowpoke',
      '|-damage|p1a: Slowpoke|0 fnt',
      '|-heal|p2a: Parasect|301/323|[from] drain|[of] p1a: Slowpoke',
      '|faint|p1a: Slowpoke',
      '|switch|p1a: Butterfree|Butterfree, M|323/323',
      '|turn|2',
      '|move|p1a: Butterfree|Mega Drain|p2a: Parasect',
      '|-resisted|p2a: Parasect',
      '|-damage|p2a: Parasect|295/323',
      '|move|p2a: Parasect|Leech Life|p1a: Butterfree',
      '|-resisted|p1a: Butterfree',
      '|-damage|p1a: Butterfree|307/323',
      '|-heal|p2a: Parasect|303/323|[from] drain|[of] p1a: Butterfree',
      '|turn|3',
      '|move|p1a: Butterfree|Substitute|p1a: Butterfree',
      '|-start|p1a: Butterfree|Substitute',
      '|-damage|p1a: Butterfree|227/323',
      '|move|p2a: Parasect|Leech Life|p1a: Butterfree',
      '|-miss|p2a: Parasect',
      '|turn|4',
    ]);
  });

  test('DreamEater effect', () => {
    {
      const battle = startBattle([
        QKC, QKC, NO_CRIT, MIN_DMG, SLP(5), QKC,
        QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
      ], [
        {species: 'Hypno', evs, moves: ['Dream Eater', 'Confusion']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Substitute', 'Rest', 'Splash']},
      ]);

      battle.p1.pokemon[0].hp = 100;

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      // Fails unless the target is sleeping
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 120);
      expect(battle.p2.pokemon[0].status).toBe('');

      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp += 120);
      expect(battle.p2.pokemon[0].status).toBe('slp');

      // Substitute blocks Dream Eater
      battle.makeChoices('move 1', 'move 3');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBeGreaterThan(0);

      battle.makeChoices('move 2', 'move 3');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();

      // Heals 1/2 of the damage dealt
      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp += 66);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 133);

      verify(battle, [
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-immune|p2a: Wigglytuff',
        '|move|p2a: Wigglytuff|Substitute|p2a: Wigglytuff',
        '|-start|p2a: Wigglytuff|Substitute',
        '|-damage|p2a: Wigglytuff|363/483',
        '|turn|2',
        '|move|p1a: Hypno|Confusion|p2a: Wigglytuff',
        '|-activate|p2a: Wigglytuff|Substitute|[damage]',
        '|move|p2a: Wigglytuff|Rest|p2a: Wigglytuff',
        '|-status|p2a: Wigglytuff|slp|[from] move: Rest',
        '|-heal|p2a: Wigglytuff|483/483 slp|[silent]',
        '|turn|3',
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-immune|p2a: Wigglytuff',
        '|cant|p2a: Wigglytuff|slp',
        '|turn|4',
        '|move|p1a: Hypno|Confusion|p2a: Wigglytuff',
        '|-end|p2a: Wigglytuff|Substitute',
        '|cant|p2a: Wigglytuff|slp',
        '|turn|5',
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-damage|p2a: Wigglytuff|350/483 slp',
        '|-heal|p1a: Hypno|166/373|[from] drain|[of] p2a: Wigglytuff',
        '|-curestatus|p2a: Wigglytuff|slp|[msg]',
        '|move|p2a: Wigglytuff|Splash|p2a: Wigglytuff',
        '|-nothing',
        '|-fail|p2a: Wigglytuff',
        '|turn|6',
      ]);
    }
    // Invulnerable
    {
      const battle = startBattle([QKC, QKC], [
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
    const battle = startBattle([
      QKC, MISS, QKC, HIT, QKC, HIT, QKC, HIT, QKC, HIT,
      QKC, HIT, HIT, QKC, NO_CRIT, MIN_DMG, QKC, HIT, QKC,
    ], [
      {species: 'Venusaur', evs, moves: ['Leech Seed']},
      {species: 'Donphan', evs, moves: ['Night Shade', 'Haze', 'Leech Seed', 'Rapid Spin']},
    ], [
      {species: 'Gengar', evs, moves: ['Leech Seed', 'Substitute', 'Toxic', 'Baton Pass']},
      {species: 'Bayleef', evs, moves: ['Splash']},
      {species: 'Slowbro', evs, moves: ['Splash']},
    ]);

    battle.p1.pokemon[0].hp = 1;
    battle.p2.pokemon[2].hp = 1;

    let venusaur = battle.p1.pokemon[0].hp;
    let donphan = battle.p1.pokemon[1].hp;
    let gengar = battle.p2.pokemon[0].hp;
    let bayleef = battle.p2.pokemon[1].hp;
    const slowbro = battle.p2.pokemon[2].hp;

    // Leed Seed can miss / Grass-type Pokémon are immune
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(venusaur);
    expect(battle.p2.pokemon[0].hp).toBe(gengar);
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeUndefined();

    // Substitute blocks Leech Seed
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(gengar -= 80);
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeUndefined();

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(donphan);
    expect(battle.p2.pokemon[0].hp).toBe(gengar);
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeDefined();

    // Leech Seed fails if already seeded / heals back damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(donphan -= 47);
    expect(battle.p2.pokemon[0].hp).toBe(gengar += 47);

    //  Leech Seed no longer interacts with Toxic damage or Haze
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(donphan = donphan - 23 - 47);
    expect(battle.p2.pokemon[0].hp).toBe(gengar += 33);

    // Leech Seed does not |-heal| when at full health
    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(donphan = donphan - 46 - 47);
    expect(battle.p2.pokemon[0].hp).toBe(gengar);
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeDefined();

    // Rapid Spin breaks Leech Seed / Leech Seed is Baton Passed even to Grass-types
    battle.makeChoices('move 4', 'move 4');
    battle.makeChoices('', 'switch 2');
    expect(battle.p1.pokemon[0].hp).toBe(donphan -= 69);
    expect(battle.p2.pokemon[0].hp).toBe(bayleef -= 20);
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeDefined();

    // Switching breaks Leech Seed
    battle.makeChoices('move 3', 'switch 3');
    expect(battle.p1.pokemon[0].hp).toBe(donphan -= 92);
    expect(battle.p2.pokemon[0].hp).toBe(slowbro);
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeDefined();

    // Leech Seed's healing is based on capped damage
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(venusaur += 1);
    expect(battle.p2.pokemon[0].hp).toBe(0);

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
      '|-activate|p2a: Gengar|Substitute|[block] Leech Seed',
      '|turn|3',
      '|switch|p1a: Donphan|Donphan, M|383/383',
      '|move|p2a: Gengar|Leech Seed|p1a: Donphan',
      '|-start|p1a: Donphan|move: Leech Seed',
      '|turn|4',
      '|move|p2a: Gengar|Leech Seed|p1a: Donphan',
      '|move|p1a: Donphan|Night Shade|p2a: Gengar',
      '|-end|p2a: Gengar|Substitute',
      '|-damage|p1a: Donphan|336/383|[from] Leech Seed|[of] p2a: Gengar',
      '|-heal|p2a: Gengar|290/323|[silent]',
      '|turn|5',
      '|move|p2a: Gengar|Toxic|p1a: Donphan',
      '|-status|p1a: Donphan|tox',
      '|move|p1a: Donphan|Haze|p1a: Donphan',
      '|-clearallboost',
      '|-damage|p1a: Donphan|313/383 tox|[from] psn',
      '|-damage|p1a: Donphan|266/383 tox|[from] Leech Seed|[of] p2a: Gengar',
      '|-heal|p2a: Gengar|323/323|[silent]',
      '|turn|6',
      '|move|p2a: Gengar|Toxic|p1a: Donphan',
      '|-fail|p1a: Donphan|tox',
      '|move|p1a: Donphan|Leech Seed|p2a: Gengar',
      '|-start|p2a: Gengar|move: Leech Seed',
      '|-damage|p1a: Donphan|220/383 tox|[from] psn',
      '|-damage|p1a: Donphan|173/383 tox|[from] Leech Seed|[of] p2a: Gengar',
      '|turn|7',
      '|move|p2a: Gengar|Baton Pass|p2a: Gengar',
      '|switch|p2a: Bayleef|Bayleef, M|323/323|[from] Baton Pass',
      '|move|p1a: Donphan|Rapid Spin|p2a: Bayleef',
      '|-damage|p2a: Bayleef|303/323',
      '|-end|p1a: Donphan|Leech Seed|[from] move: Rapid Spin|[of] p1a: Donphan',
      '|-damage|p1a: Donphan|104/383 tox|[from] psn',
      '|turn|8',
      '|switch|p2a: Slowbro|Slowbro, M|1/393',
      '|move|p1a: Donphan|Leech Seed|p2a: Slowbro',
      '|-start|p2a: Slowbro|move: Leech Seed',
      '|-damage|p1a: Donphan|12/383 tox|[from] psn',
      '|turn|9',
      '|switch|p1a: Venusaur|Venusaur, M|1/363',
      '|move|p2a: Slowbro|Splash|p2a: Slowbro',
      '|-nothing',
      '|-fail|p2a: Slowbro',
      '|-damage|p2a: Slowbro|0 fnt|[from] Leech Seed|[of] p1a: Venusaur',
      '|-heal|p1a: Venusaur|2/363|[silent]',
      '|faint|p2a: Slowbro',
    ]);
  });

  test('PayDay effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MAX_DMG, QKC, NO_CRIT, MAX_DMG, QKC, CRIT, MAX_DMG, QKC,
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

    // Pay Day should still scatter coins even if it breaks the Substitute
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
      '|-fail|p2a: Slowpoke',
      '|turn|3',
      '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
      '|-crit|p2a: Slowpoke',
      '|-end|p2a: Slowpoke|Substitute',
      '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
      '|-nothing',
      '|-fail|p2a: Slowpoke',
      '|turn|4',
    ]);
  });

  test('Rage effect', () => {
    const no_brn = SECONDARY(ranged(25, 256));
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, no_brn, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, HIT, DISABLE_DURATION(5), QKC,
    ], [
      {species: 'Charmeleon', evs, moves: ['Rage', 'Flamethrower']},
      {species: 'Doduo', evs, moves: ['Drill Peck']},
    ], [
      {species: 'Grimer', evs, moves: ['Pound', 'Disable', 'Self-Destruct']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    // Rage increases attack when hit by a move but does not lock-in
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    // When used consecutively, the damage Rage deals is multiplied by a separate counter
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 135);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    // Disable does not proc Rage, the Rage counter gets reset when the user ceases to use Rage
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    verify(battle, [
      '|move|p1a: Charmeleon|Rage|p2a: Grimer',
      '|-damage|p2a: Grimer|346/363',
      '|-singlemove|p1a: Charmeleon|Rage',
      '|move|p2a: Grimer|Pound|p1a: Charmeleon',
      '|-damage|p1a: Charmeleon|284/319',
      '|-boost|p1a: Charmeleon|atk|1',
      '|turn|2',
      '|move|p1a: Charmeleon|Rage|p2a: Grimer',
      '|-damage|p2a: Grimer|321/363',
      '|-singlemove|p1a: Charmeleon|Rage',
      '|move|p2a: Grimer|Pound|p1a: Charmeleon',
      '|-damage|p1a: Charmeleon|249/319',
      '|-boost|p1a: Charmeleon|atk|1',
      '|turn|3',
      '|move|p1a: Charmeleon|Flamethrower|p2a: Grimer',
      '|-damage|p2a: Grimer|186/363',
      '|move|p2a: Grimer|Pound|p1a: Charmeleon',
      '|-damage|p1a: Charmeleon|214/319',
      '|turn|4',
      '|move|p1a: Charmeleon|Rage|p2a: Grimer',
      '|-damage|p2a: Grimer|152/363',
      '|-singlemove|p1a: Charmeleon|Rage',
      '|move|p2a: Grimer|Disable|p1a: Charmeleon',
      '|-start|p1a: Charmeleon|Disable|Rage',
      '|turn|5',
    ]);
  });

  test('Mimic effect', () => {
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, QKC, QKC, NO_CRIT, MIN_DMG, QKC, QKC, QKC,
    ], [
      {species: 'Mr. Mime', evs, moves: ['Mimic', 'Splash']},
      {species: 'Abra', evs, moves: ['Splash']},
    ], [
      {species: 'Jigglypuff', evs, moves: ['Blizzard', 'Surf', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    // Fails if the target does not have a last used move
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    // Fails to copy any move the user already knows
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 39);

    // Copies the targets last used move and gives it 5 PP
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Surf');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(5);
    expect(battle.p1.pokemon[0].baseMoveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(4);
    expect(battle.p1.pokemon[0].baseMoveSlots[0].pp).toBe(pp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 137);

    battle.makeChoices('switch 2', 'move 3');
    battle.makeChoices('switch 2', 'move 3');

    expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Mimic');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

    verify(battle, [
      '|move|p1a: Mr. Mime|Mimic|p2a: Jigglypuff',
      '|-fail|p2a: Jigglypuff',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|-fail|p2a: Jigglypuff',
      '|turn|2',
      '|move|p1a: Mr. Mime|Mimic|p2a: Jigglypuff',
      '|-fail|p2a: Jigglypuff',
      '|move|p2a: Jigglypuff|Surf|p1a: Mr. Mime',
      '|-damage|p1a: Mr. Mime|244/283',
      '|turn|3',
      '|move|p1a: Mr. Mime|Mimic|p2a: Jigglypuff',
      '|-activate|p1a: Mr. Mime|move: Mimic|Surf',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|-fail|p2a: Jigglypuff',
      '|turn|4',
      '|move|p1a: Mr. Mime|Surf|p2a: Jigglypuff',
      '|-damage|p2a: Jigglypuff|296/433',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|-fail|p2a: Jigglypuff',
      '|turn|5',
      '|switch|p1a: Abra|Abra, M|253/253',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|-fail|p2a: Jigglypuff',
      '|turn|6',
      '|switch|p1a: Mr. Mime|Mr. Mime, M|244/283',
      '|move|p2a: Jigglypuff|Splash|p2a: Jigglypuff',
      '|-nothing',
      '|-fail|p2a: Jigglypuff',
      '|turn|7',
    ]);
  });

  test('LightScreen effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
      QKC, CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Chansey', evs, moves: ['Light Screen', 'Splash']},
      {species: 'Blissey', evs, moves: ['Splash']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Water Gun', 'Haze']},
    ]);

    let chansey = battle.p1.pokemon[0].hp;
    let blissey = battle.p1.pokemon[1].hp;

    // Water Gun does normal damage before Light Screen
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.sideConditions['lightscreen']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 45);

    // Water Gun's damage is reduced after Light Screen
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 23);

    // Critical hits ignore Light Screen
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 89);

    // Teammates benefit as well, not removed by Haze
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.sideConditions['lightscreen']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 20);

    // Ends after 5 turns
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 20);
    expect(battle.p1.sideConditions['lightscreen']).toBeUndefined();

    // Returns to normal damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 38);

    verify(battle, [
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-damage|p1a: Chansey|658/703',
      '|move|p1a: Chansey|Light Screen|p1a: Chansey',
      '|-sidestart|p1: Player 1|move: Light Screen',
      '|turn|2',
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-damage|p1a: Chansey|635/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|-fail|p1a: Chansey',
      '|turn|3',
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|546/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|-fail|p1a: Chansey',
      '|turn|4',
      '|switch|p1a: Blissey|Blissey, F|713/713',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|693/713',
      '|turn|5',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|673/713',
      '|move|p1a: Blissey|Splash|p1a: Blissey',
      '|-nothing',
      '|-fail|p1a: Blissey',
      '|-sideend|p1: Player 1|move: Light Screen',
      '|turn|6',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|635/713',
      '|move|p1a: Blissey|Splash|p1a: Blissey',
      '|-nothing',
      '|-fail|p1a: Blissey',
      '|turn|7',
    ]);
  });

  test('Reflect effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Chansey', evs, moves: ['Reflect', 'Splash']},
      {species: 'Blissey', evs, moves: ['Splash']},
    ], [
      {species: 'Vaporeon', evs, moves: ['Tackle', 'Haze']},
    ]);

    let chansey = battle.p1.pokemon[0].hp;
    let blissey = battle.p1.pokemon[1].hp;

    // Tackle does normal damage before Reflect
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.sideConditions['reflect']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 54);

    // Tackle's damage is reduced after Reflect
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 28);

    // Critical hits ignore Reflect
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(chansey -= 107);

    // Teammates benefit as well, not removed by Haze
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.sideConditions['reflect']).toBeDefined();
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 25);

    // Ends after 5 turns
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 25);
    expect(battle.p1.sideConditions['reflect']).toBeUndefined();

    // Returns to normal damage
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(blissey -= 49);

    verify(battle, [
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-damage|p1a: Chansey|649/703',
      '|move|p1a: Chansey|Reflect|p1a: Chansey',
      '|-sidestart|p1: Player 1|Reflect',
      '|turn|2',
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-damage|p1a: Chansey|621/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|-fail|p1a: Chansey',
      '|turn|3',
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|514/703',
      '|move|p1a: Chansey|Splash|p1a: Chansey',
      '|-nothing',
      '|-fail|p1a: Chansey',
      '|turn|4',
      '|switch|p1a: Blissey|Blissey, F|713/713',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|688/713',
      '|turn|5',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|663/713',
      '|move|p1a: Blissey|Splash|p1a: Blissey',
      '|-nothing',
      '|-fail|p1a: Blissey',
      '|-sideend|p1: Player 1|Reflect',
      '|turn|6',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|614/713',
      '|move|p1a: Blissey|Splash|p1a: Blissey',
      '|-nothing',
      '|-fail|p1a: Blissey',
      '|turn|7',
    ]);
  });

  test('Haze effect', () => {
    const battle = startBattle([
      QKC, HIT, HIT, QKC, HIT,
      QKC, PAR_CAN, HIT, CFZ(5), QKC, CFZ_CAN, PAR_CAN, QKC,
    ], [
      {species: 'Golbat', evs, moves: ['Toxic', 'Agility', 'Confuse Ray', 'Haze']},
    ], [
      {species: 'Exeggutor', evs, moves: ['Leech Seed', 'Stun Spore', 'Double Team', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeDefined();
    expect(battle.p2.pokemon[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 24);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 44);
    expect(battle.p1.pokemon[0].boosts.spe).toBe(2);
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp + 24 - 48));

    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 44);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(1);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(3);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 72 + 44));

    battle.makeChoices('move 4', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 44);
    expect(battle.p1.pokemon[0].status).toBe('par');
    expect(battle.p1.pokemon[0].volatiles['leechseed']).toBeDefined();
    expect(battle.p1.pokemon[0].boosts.spe).toBe(0);
    expect(battle.p2.pokemon[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(4);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = (p2hp - 96 + 44));

    verify(battle, [
      '|move|p1a: Golbat|Toxic|p2a: Exeggutor',
      '|-status|p2a: Exeggutor|tox',
      '|move|p2a: Exeggutor|Leech Seed|p1a: Golbat',
      '|-start|p1a: Golbat|move: Leech Seed',
      '|-damage|p2a: Exeggutor|369/393 tox|[from] psn',
      '|turn|2',
      '|move|p1a: Golbat|Agility|p1a: Golbat',
      '|-boost|p1a: Golbat|spe|2',
      '|-damage|p1a: Golbat|309/353|[from] Leech Seed|[of] p2a: Exeggutor',
      '|-heal|p2a: Exeggutor|393/393 tox|[silent]',
      '|move|p2a: Exeggutor|Stun Spore|p1a: Golbat',
      '|-status|p1a: Golbat|par',
      '|-damage|p2a: Exeggutor|345/393 tox|[from] psn',
      '|turn|3',
      '|move|p2a: Exeggutor|Double Team|p2a: Exeggutor',
      '|-boost|p2a: Exeggutor|evasion|1',
      '|-damage|p2a: Exeggutor|273/393 tox|[from] psn',
      '|move|p1a: Golbat|Confuse Ray|p2a: Exeggutor',
      '|-start|p2a: Exeggutor|confusion',
      '|-damage|p1a: Golbat|265/353 par|[from] Leech Seed|[of] p2a: Exeggutor',
      '|-heal|p2a: Exeggutor|317/393 tox|[silent]',
      '|turn|4',
      '|-activate|p2a: Exeggutor|confusion',
      '|move|p2a: Exeggutor|Splash|p2a: Exeggutor',
      '|-nothing',
      '|-fail|p2a: Exeggutor',
      '|-damage|p2a: Exeggutor|221/393 tox|[from] psn',
      '|move|p1a: Golbat|Haze|p1a: Golbat',
      '|-clearallboost',
      '|-damage|p1a: Golbat|221/353 par|[from] Leech Seed|[of] p2a: Exeggutor',
      '|-heal|p2a: Exeggutor|265/393 tox|[silent]',
      '|turn|5',
    ]);
  });

  test('Bide effect', () => {
    const bide = (n: 2 | 3) =>
      ({key: 'data/mods/gen2/moves.ts:56:17', value: ranged(n - 2, 5 - 3)});
    {
      const battle = startBattle([
        QKC, bide(3), HIT, QKC, HIT, QKC, QKC, QKC, NO_CRIT, MIN_DMG, bide(3),
        QKC, QKC, QKC, CFZ(2), CFZ_CAN, QKC, bide(3), QKC, HIT, SLP(2), QKC,
        QKC, bide(2), HIT, QKC, HIT, QKC, HIT, QKC,
      ], [
        {species: 'Chansey', evs, moves: ['Bide', 'Splash']},
        {species: 'Onix', evs, moves: ['Bide']},
      ], [
        {species: 'Magnemite', evs, moves: ['Sonic Boom']},
        {species: 'Dugtrio', evs, moves: ['Dig']},
        {species: 'Haunter', evs, moves: ['Dragon Rage', 'Confuse Ray', 'Hypnosis']},
      ]);

      let chansey = battle.p1.pokemon[0].hp;
      let magnemite = battle.p2.pokemon[0].hp;
      const dugtrio = battle.p2.pokemon[1].hp;
      const haunter = battle.p2.pokemon[2].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);

      expect(choices(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);

      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(dugtrio);

      expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 154);

      battle.makeChoices('move 1', 'switch 3');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 40);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(haunter);

      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(chansey);
      expect(battle.p1.pokemon[0].status).toBe('slp');

      battle.makeChoices('move 1', 'switch 2');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);
      expect(battle.p1.pokemon[0].status).toBe('');

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(chansey -= 20);
      expect(battle.p2.pokemon[0].hp).toBe(magnemite -= 80);

      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(12);

      verify(battle, [
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|move: Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|683/703',
        '|turn|2',
        '|-activate|p1a: Chansey|move: Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|663/703',
        '|turn|3',
        '|switch|p2a: Dugtrio|Dugtrio, M|273/273',
        '|-activate|p1a: Chansey|move: Bide',
        '|turn|4',
        '|move|p2a: Dugtrio|Dig||[still]|[miss]',
        '|-prepare|p2a: Dugtrio|Dig',
        '|-end|p1a: Chansey|move: Bide',
        '|-miss|p1a: Chansey',
        '|-end|p1a: Chansey|move: Bide|[silent]',
        '|turn|5',
        '|move|p2a: Dugtrio|Dig|p1a: Chansey',
        '|-damage|p1a: Chansey|509/703',
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|move: Bide',
        '|turn|6',
        '|switch|p2a: Haunter|Haunter, M|293/293',
        '|-activate|p1a: Chansey|move: Bide',
        '|turn|7',
        '|move|p2a: Haunter|Dragon Rage|p1a: Chansey',
        '|-damage|p1a: Chansey|469/703',
        '|-activate|p1a: Chansey|move: Bide',
        '|turn|8',
        '|move|p2a: Haunter|Confuse Ray|p1a: Chansey',
        '|-start|p1a: Chansey|confusion',
        '|-activate|p1a: Chansey|confusion',
        '|-end|p1a: Chansey|move: Bide',
        '|-immune|p2a: Haunter',
        '|-end|p1a: Chansey|move: Bide|[silent]',
        '|turn|9',
        '|move|p2a: Haunter|Confuse Ray|p1a: Chansey',
        '|-fail|p1a: Chansey',
        '|-end|p1a: Chansey|confusion',
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|move: Bide',
        '|turn|10',
        '|move|p2a: Haunter|Hypnosis|p1a: Chansey',
        '|-status|p1a: Chansey|slp|[from] move: Hypnosis',
        '|cant|p1a: Chansey|slp',
        '|-end|p1a: Chansey|move: Bide|[silent]',
        '|turn|11',
        '|switch|p2a: Magnemite|Magnemite|253/253',
        '|cant|p1a: Chansey|slp',
        '|turn|12',
        '|-curestatus|p1a: Chansey|slp|[msg]',
        '|move|p1a: Chansey|Bide|p1a: Chansey',
        '|-start|p1a: Chansey|move: Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|449/703',
        '|turn|13',
        '|-activate|p1a: Chansey|move: Bide',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|429/703',
        '|turn|14',
        '|-end|p1a: Chansey|move: Bide',
        '|-damage|p2a: Magnemite|173/253',
        '|-end|p1a: Chansey|move: Bide|[silent]',
        '|move|p2a: Magnemite|Sonic Boom|p1a: Chansey',
        '|-damage|p1a: Chansey|409/703',
        '|turn|15',
      ]);
    }
    // Bide + Substitute
    {
      const battle = startBattle([QKC, QKC, bide(2), QKC, QKC, QKC], [
        {species: 'Snorlax', evs, moves: ['Seismic Toss']},
      ], [
        {species: 'Chansey', evs, moves: ['Substitute', 'Bide', 'Splash']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 175);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

      // Damage dealt to a Substitute is not considered for the damage Bide deals
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 200);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

      verify(battle, [
        '|move|p2a: Chansey|Substitute|p2a: Chansey',
        '|-start|p2a: Chansey|Substitute',
        '|-damage|p2a: Chansey|528/703',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-activate|p2a: Chansey|Substitute|[damage]',
        '|turn|2',
        '|move|p2a: Chansey|Bide|p2a: Chansey',
        '|-start|p2a: Chansey|move: Bide',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-end|p2a: Chansey|Substitute',
        '|turn|3',
        '|-activate|p2a: Chansey|move: Bide',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-damage|p2a: Chansey|428/703',
        '|turn|4',
        '|-end|p2a: Chansey|move: Bide',
        '|-damage|p1a: Snorlax|323/523',
        '|-end|p2a: Chansey|move: Bide|[silent]',
        '|move|p1a: Snorlax|Seismic Toss|p2a: Chansey',
        '|-damage|p2a: Chansey|328/703',
        '|turn|5',
      ]);
    }
  });

  test('Metronome effect', () => {
    const battle = startBattle([
      QKC, METRONOME('Wrap'), HIT, NO_CRIT, MIN_DMG, MIN_WRAP,
      METRONOME('Petal Dance'), NO_CRIT, MIN_DMG, THRASH(2), QKC,
      NO_CRIT, MIN_DMG, CFZ(2), QKC, METRONOME('Disable'), HIT, DISABLE_DURATION(3),
      CFZ_CAN, METRONOME('Quick Attack'), NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Clefable', evs, moves: ['Metronome', 'Splash']},
    ], [
      {species: 'Primeape', evs, moves: ['Metronome', 'Mimic', 'Fury Swipes']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp = p1hp - 14 - 24);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 57);

    // Still get stuck into Thrashing
    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2', 'move 3']);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 24);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 57);

    // Quick Attack via Metronome only executes at normal priority
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    verify(battle, [
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Wrap|p1a: Clefable|[from]Metronome',
      '|-damage|p1a: Clefable|379/393',
      '|-activate|p1a: Clefable|move: Wrap|[of] p2a: Primeape',
      '|move|p1a: Clefable|Metronome|p1a: Clefable',
      '|move|p1a: Clefable|Petal Dance|p2a: Primeape|[from]Metronome',
      '|-damage|p2a: Primeape|276/333',
      '|-damage|p1a: Clefable|355/393|[from] move: Wrap|[partiallytrapped]',
      '|turn|2',
      '|move|p2a: Primeape|Mimic|p1a: Clefable',
      '|-fail|p1a: Clefable',
      '|move|p1a: Clefable|Petal Dance|p2a: Primeape',
      '|-damage|p2a: Primeape|219/333',
      '|-start|p1a: Clefable|confusion|[silent]',
      '|-damage|p1a: Clefable|331/393|[from] move: Wrap|[partiallytrapped]',
      '|turn|3',
      '|move|p2a: Primeape|Metronome|p2a: Primeape',
      '|move|p2a: Primeape|Disable|p1a: Clefable|[from]Metronome',
      '|-fail|p1a: Clefable',
      '|-activate|p1a: Clefable|confusion',
      '|move|p1a: Clefable|Metronome|p1a: Clefable',
      '|move|p1a: Clefable|Quick Attack|p2a: Primeape|[from]Metronome',
      '|-damage|p2a: Primeape|171/333',
      '|-end|p1a: Clefable|Wrap|[partiallytrapped]',
      '|turn|4',
    ]);
  });

  test('MirrorMove effect', () => {
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
      QKC, MISS, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
      QKC, NO_CRIT, MIN_DMG, QKC, TIE(1), NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Fearow', evs, moves: ['Mirror Move', 'Peck', 'Fly', 'Transform']},
    ], [
      {species: 'Pidgeot', evs, moves: ['Mirror Move', 'Swift']},
      {species: 'Pidgeotto', evs, moves: ['Gust', 'Mirror Move']},
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
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(31);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(30);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 74);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('swift');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(30);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(30);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 74);
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(29);

    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('fly');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(28);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('fly');
    expect(battle.p2.pokemon[0].lastMove!.id).toBe('fly');
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(28);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 44);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 43);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(29);
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(27);

    // Switching resets last used moves
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p1.pokemon[0].lastMove!.id).toBe('mirrormove');
    expect(battle.p2.pokemon[0].lastMove).toBeNull();
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(28);

    battle.makeChoices('move 4', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 46);

    // Mirror Move will always fail when used by a transformed Pokémon.
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 46);

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
      '|-fail|p1a: Fearow',
      '|move|p2a: Pidgeot|Swift|p1a: Fearow',
      '|-damage|p1a: Fearow|215/333',
      '|turn|4',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|move|p1a: Fearow|Swift|p2a: Pidgeot|[from]Mirror Move',
      '|-damage|p2a: Pidgeot|252/369',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|-fail|p2a: Pidgeot',
      '|turn|5',
      '|move|p1a: Fearow|Fly||[still]',
      '|-prepare|p1a: Fearow|Fly',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Fly||[from]Mirror Move|[still]',
      '|-prepare|p2a: Pidgeot|Fly',
      '|turn|6',
      '|move|p1a: Fearow|Fly|p2a: Pidgeot|[miss]',
      '|-miss|p1a: Fearow',
      '|move|p2a: Pidgeot|Fly|p1a: Fearow|[miss]',
      '|-miss|p2a: Pidgeot',
      '|turn|7',
      '|move|p1a: Fearow|Peck|p2a: Pidgeot',
      '|-damage|p2a: Pidgeot|209/369',
      '|move|p2a: Pidgeot|Mirror Move|p2a: Pidgeot',
      '|move|p2a: Pidgeot|Peck|p1a: Fearow|[from]Mirror Move',
      '|-damage|p1a: Fearow|171/333',
      '|turn|8',
      '|switch|p2a: Pidgeotto|Pidgeotto, M|329/329',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|-fail|p1a: Fearow',
      '|turn|9',
      '|move|p1a: Fearow|Transform|p2a: Pidgeotto',
      '|-transform|p1a: Fearow|p2a: Pidgeotto',
      '|move|p2a: Pidgeotto|Gust|p1a: Fearow',
      '|-damage|p1a: Fearow|125/333',
      '|turn|10',
      '|move|p1a: Fearow|Mirror Move|p1a: Fearow',
      '|-fail|p1a: Fearow',
      '|move|p2a: Pidgeotto|Gust|p1a: Fearow',
      '|-damage|p1a: Fearow|79/333',
      '|turn|11',
    ]);
  });

  test('Explode effect', () => {
    const battle = startBattle([
      QKC, HIT, QKC, NO_CRIT, MAX_DMG, QKC, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Electrode', level: 80, evs, moves: ['Explosion', 'Toxic']},
      {species: 'Steelix', evs, moves: ['Explosion']},
      {species: 'Onix', evs, moves: ['Self-Destruct']},
    ], [
      {species: 'Chansey', evs, moves: ['Substitute', 'Splash']},
      {species: 'Gengar', evs, moves: ['Night Shade']},
    ]);

    const electrode = battle.p1.pokemon[0].hp;
    const steelix = battle.p1.pokemon[1].hp;
    const onix = battle.p1.pokemon[2].hp;
    let chansey = battle.p2.pokemon[0].hp;
    const gengar = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(electrode);
    expect(battle.p2.pokemon[0].hp).toBe(chansey = chansey - 175 - 43);

    // Breaking a Substitute with Explosion/Self-Destruct still causes the user to faint
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(chansey);

    battle.makeChoices('switch 2', '');
    expect(battle.p1.pokemon[0].hp).toBe(steelix);
    expect(battle.p2.pokemon[0].hp).toBe(chansey);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    battle.makeChoices('switch 3', 'switch 2');
    expect(battle.p1.pokemon[0].hp).toBe(onix);
    expect(battle.p2.pokemon[0].hp).toBe(gengar);

    battle.makeChoices('move 1', 'move 1');
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
      '|faint|p1a: Electrode',
      '|switch|p1a: Steelix|Steelix, M|353/353',
      '|turn|3',
      '|move|p2a: Chansey|Splash|p2a: Chansey',
      '|-nothing',
      '|-fail|p2a: Chansey',
      '|-damage|p2a: Chansey|399/703 tox|[from] psn',
      '|move|p1a: Steelix|Explosion|p2a: Chansey',
      '|-damage|p2a: Chansey|0 fnt',
      '|faint|p1a: Steelix',
      '|faint|p2a: Chansey',
      '|switch|p2a: Gengar|Gengar, M|323/323',
      '|switch|p1a: Onix|Onix, M|273/273',
      '|turn|4',
      '|move|p2a: Gengar|Night Shade|p1a: Onix',
      '|-damage|p1a: Onix|173/273',
      '|move|p1a: Onix|Self-Destruct|p2a: Gengar',
      '|-immune|p2a: Gengar',
      '|faint|p1a: Onix',
      '|win|Player 2',
    ]);
  });

  test('AlwaysHit effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Eevee', evs, moves: ['Swift']},
    ], [
      {species: 'Larvitar', evs, moves: ['Dig']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);

    // Misses invulnerable opponents
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 74);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Eevee|Swift|p2a: Larvitar',
      '|-resisted|p2a: Larvitar',
      '|-damage|p2a: Larvitar|269/303',
      '|move|p2a: Larvitar|Dig||[still]',
      '|-prepare|p2a: Larvitar|Dig',
      '|turn|2',
      '|move|p1a: Eevee|Swift|p2a: Larvitar|[miss]',
      '|-miss|p1a: Eevee',
      '|move|p2a: Larvitar|Dig|p1a: Eevee',
      '|-damage|p1a: Eevee|239/313',
      '|turn|3',
    ]);
  });

  test('Transform effect', () => {
    const battle = startBattle([
      QKC, QKC, QKC, MISS, QKC, TIE(2), NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, TIE(2), QKC, QKC,
    ], [
      {species: 'Mew', level: 50, evs, moves: ['Swords Dance', 'Transform']},
      {species: 'Ditto', evs, moves: ['Swords Dance', 'Transform']},
    ], [
      {species: 'Articuno', evs, moves: ['Agility', 'Fly', 'Peck']},
    ]);

    let pp = battle.p1.pokemon[0].moveSlots[1].pp;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.spe).toBe(2);

    // Transform cannot hit an invulnerable target
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].species.name).toBe('Mew');
    expect(battle.p1.pokemon[0].baseMoveSlots[1].pp).toBe(pp -= 1);

    battle.makeChoices('move 2', 'move 1');
    // Transform should copy species, types, stats, and boosts but not level or HP
    expect(battle.p1.pokemon[0].species.name).toBe('Articuno');
    expect(battle.p1.pokemon[0].types).toEqual(battle.p2.pokemon[0].types);
    expect(battle.p1.pokemon[0].level).toBe(50);
    expect(battle.p1.pokemon[0].boosts).toEqual(battle.p2.pokemon[0].boosts);

    expect(battle.p1.pokemon[0].moveSlots).toHaveLength(3);
    expect(battle.p1.pokemon[0].moveSlots.map(m => m.move)).toEqual(['Agility', 'Fly', 'Peck']);
    expect(battle.p1.pokemon[0].moveSlots.map(m => m.pp)).toEqual([5, 5, 5]);
    expect(battle.p1.pokemon[0].baseMoveSlots[1].pp).toBe(pp -= 1);

    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 18);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts).toEqual(battle.p2.pokemon[0].boosts);

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[1].species.name).toBe('Mew');
    expect(battle.p1.pokemon[1].moveSlots[1].pp).toBe(pp);

    verify(battle, [
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|move|p1a: Mew|Swords Dance|p1a: Mew',
      '|-boost|p1a: Mew|atk|2',
      '|turn|2',
      '|move|p2a: Articuno|Fly||[still]',
      '|-prepare|p2a: Articuno|Fly',
      '|move|p1a: Mew|Transform|p2a: Articuno|[miss]',
      '|-miss|p1a: Mew',
      '|turn|3',
      '|move|p2a: Articuno|Fly|p1a: Mew|[miss]',
      '|-miss|p2a: Articuno',
      '|move|p1a: Mew|Transform|p2a: Articuno',
      '|-transform|p1a: Mew|p2a: Articuno',
      '|turn|4',
      '|move|p2a: Articuno|Peck|p1a: Mew',
      '|-damage|p1a: Mew|171/206',
      '|move|p1a: Mew|Peck|p2a: Articuno',
      '|-damage|p2a: Articuno|365/383',
      '|turn|5',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|move|p1a: Mew|Agility|p1a: Mew',
      '|-boost|p1a: Mew|spe|2',
      '|turn|6',
      '|switch|p1a: Ditto|Ditto|299/299',
      '|move|p2a: Articuno|Agility|p2a: Articuno',
      '|-boost|p2a: Articuno|spe|2',
      '|turn|7',
    ]);
  });

  test('Conversion effect', () => {
    const proc = {key: 'data/mods/gen3/moves.ts:151:22', value: ranged(0, 2)};
    const battle = startBattle([QKC, proc, QKC], [
      {species: 'Porygon', evs, moves: ['Conversion', 'Sharpen']},
    ], [
      {species: 'Porygon2', evs, moves: ['Conversion', 'Curse', 'Ice Beam', 'Thunderbolt']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Porygon2|Conversion|p2a: Porygon2',
      '|-start|p2a: Porygon2|typechange|Ice',
      '|move|p1a: Porygon|Conversion|p1a: Porygon',
      '|-fail|p1a: Porygon',
      '|turn|2',
    ]);
  });

  test('Conversion2 effect', () => {
    const proc = {key: 'data/moves.ts:2893:28', value: MAX};
    const battle = startBattle([QKC, proc, QKC], [
      {species: 'Porygon2', evs, moves: ['Conversion2']},
    ], [
      {species: 'Porygon2', evs: slow, moves: ['Conversion2']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Porygon2|Conversion 2|p2a: Porygon2',
      '|-fail|p2a: Porygon2',
      '|move|p2a: Porygon2|Conversion 2|p1a: Porygon2',
      '|-start|p2a: Porygon2|typechange|Rock',
      '|turn|2',
    ]);
  });

  test('Substitute effect', () => {
    const battle = startBattle([
      QKC, HIT, QKC, NO_CRIT, MIN_DMG, QKC, HIT, QKC, QKC, HIT, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Mewtwo', evs, moves: ['Substitute', 'Splash']},
      {species: 'Abra', level: 2, moves: ['Substitute', 'Psychic']},
    ], [
      {species: 'Electabuzz', moves: ['Flash', 'Strength', 'Substitute', 'Baton Pass']},
      {species: 'Blissey', moves: ['Splash']},
    ]);

    battle.p1.pokemon[1].hp = 3;

    let mewtwo = battle.p1.pokemon[0].hp;
    const abra = battle.p1.pokemon[1].hp;
    let electabuzz = battle.p2.pokemon[0].hp;

    // Takes 1/4 of maximum HP to make a Substitute with that HP, protects against stat down
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(mewtwo -= 103);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(103);

    // Can't make a Substitute if you already have one, absorbs damage
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(mewtwo);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(61);

    // Disappears when switching out
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(abra);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();

    // Can be too weak to create a Substitute
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(abra);
    expect(battle.p2.pokemon[0].hp).toBe(electabuzz -= 67);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(67);

    // A Substitute can be passed by Baton Pass, and it will keep whatever HP it has remaining
    battle.makeChoices('move 2', 'move 4');
    battle.makeChoices('', 'switch 2');
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(63);

    verify(battle, [
      '|move|p1a: Mewtwo|Substitute|p1a: Mewtwo',
      '|-start|p1a: Mewtwo|Substitute',
      '|-damage|p1a: Mewtwo|312/415',
      '|move|p2a: Electabuzz|Flash|p1a: Mewtwo',
      '|-activate|p1a: Mewtwo|Substitute|[block] Flash',
      '|turn|2',
      '|move|p1a: Mewtwo|Substitute|p1a: Mewtwo',
      '|-fail|p1a: Mewtwo|move: Substitute',
      '|move|p2a: Electabuzz|Strength|p1a: Mewtwo',
      '|-activate|p1a: Mewtwo|Substitute|[damage]',
      '|turn|3',
      '|switch|p1a: Abra|Abra, L2, M|3/13',
      '|move|p2a: Electabuzz|Flash|p1a: Abra',
      '|-unboost|p1a: Abra|accuracy|1',
      '|turn|4',
      '|move|p2a: Electabuzz|Substitute|p2a: Electabuzz',
      '|-start|p2a: Electabuzz|Substitute',
      '|-damage|p2a: Electabuzz|203/270',
      '|move|p1a: Abra|Substitute|p1a: Abra',
      '|-fail|p1a: Abra|move: Substitute|[weak]',
      '|turn|5',
      '|move|p2a: Electabuzz|Baton Pass|p2a: Electabuzz',
      '|switch|p2a: Blissey|Blissey, F|650/650|[from] Baton Pass',
      '|move|p1a: Abra|Psychic|p2a: Blissey',
      '|-activate|p2a: Blissey|Substitute|[damage]',
      '|turn|6',
    ]);
  });

  test('Sketch effect', () => {
    const battle = startBattle([QKC, QKC], [
      {species: 'Smeargle', evs, moves: ['Sketch']},
    ], [
      {species: 'Abra', evs, moves: ['Splash']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Abra|Splash|p2a: Abra',
      '|-nothing',
      '|-fail|p2a: Abra',
      '|move|p1a: Smeargle|Sketch|p2a: Abra',
      '|-nothing',
      '|turn|2',
    ]);
  });

  test('Thief effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Snubbull', evs, moves: ['Splash']},
      {species: 'Granbull', item: 'Dragon Fang', evs, moves: ['Thief']},
    ], [
      {species: 'Sneasel', evs, moves: ['Thief', 'Substitute']},
    ]);

    const snubbull = battle.p1.pokemon[0].hp;
    const granbull = battle.p1.pokemon[1].hp;
    const sneasel = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(snubbull - 41);
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p2.pokemon[0].item).toBe('');

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(granbull - 34);
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p2.pokemon[0].item).toBe('dragonfang');

    // Thief cannot steal an item from a Pokémon behind a Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(sneasel - 78);
    expect(battle.p2.pokemon[0].item).toBe('dragonfang');

    verify(battle, [
      '|move|p2a: Sneasel|Thief|p1a: Snubbull',
      '|-damage|p1a: Snubbull|282/323',
      '|move|p1a: Snubbull|Splash|p1a: Snubbull',
      '|-nothing',
      '|-fail|p1a: Snubbull',
      '|turn|2',
      '|switch|p1a: Granbull|Granbull, M|383/383',
      '|move|p2a: Sneasel|Thief|p1a: Granbull',
      '|-damage|p1a: Granbull|349/383',
      '|-item|p2a: Sneasel|Dragon Fang|[from] move: Thief|[of] p1a: Granbull',
      '|turn|3',
      '|move|p2a: Sneasel|Substitute|p2a: Sneasel',
      '|-start|p2a: Sneasel|Substitute',
      '|-damage|p2a: Sneasel|235/313',
      '|move|p1a: Granbull|Thief|p2a: Sneasel',
      '|-resisted|p2a: Sneasel',
      '|-activate|p2a: Sneasel|Substitute|[damage]',
      '|turn|4',
    ]);
  });

  test('MeanLook effect', () => {
    const battle = startBattle([QKC, QKC, QKC, QKC, QKC], [
      {species: 'Umbreon', evs, moves: ['Mean Look', 'Baton Pass']},
      {species: 'Spinarak', evs, moves: ['Splash']},
    ], [
      {species: 'Espeon', evs, moves: ['Splash', 'Baton Pass']},
      {species: 'Ledyba', evs, moves: ['Splash']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('switch 2', '');
    expect(choices(battle, 'p2')).toEqual(['move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 2');
    battle.makeChoices('', 'switch 2');
    expect(choices(battle, 'p2')).toEqual(['move 1']);

    battle.makeChoices('switch 2', 'move 1');
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1']);

    verify(battle, [
      '|move|p2a: Espeon|Splash|p2a: Espeon',
      '|-nothing',
      '|-fail|p2a: Espeon',
      '|move|p1a: Umbreon|Mean Look|p2a: Espeon',
      '|-activate|p2a: Espeon|trapped',
      '|turn|2',
      '|move|p2a: Espeon|Splash|p2a: Espeon',
      '|-nothing',
      '|-fail|p2a: Espeon',
      '|move|p1a: Umbreon|Baton Pass|p1a: Umbreon',
      '|switch|p1a: Spinarak|Spinarak, M|283/283|[from] Baton Pass',
      '|turn|3',
      '|move|p2a: Espeon|Baton Pass|p2a: Espeon',
      '|switch|p2a: Ledyba|Ledyba, M|283/283|[from] Baton Pass',
      '|move|p1a: Spinarak|Splash|p1a: Spinarak',
      '|-nothing',
      '|-fail|p1a: Spinarak',
      '|turn|4',
      '|switch|p1a: Umbreon|Umbreon, M|393/393',
      '|move|p2a: Ledyba|Splash|p2a: Ledyba',
      '|-nothing',
      '|-fail|p2a: Ledyba',
      '|turn|5',
    ]);
  });

  test('LockOn effect', () => {
    const battle = startBattle([
      QKC, QKC, CRIT, MAX_DMG, QKC, QKC, QKC, MISS, QKC, QKC, QKC, QKC,
    ], [
      {species: 'Machamp', evs, moves: ['Lock-On', 'Dynamic Punch']},
      {species: 'Octillery', evs, moves: ['Lock-On', 'Zap Cannon']},
    ], [
      {species: 'Dunsparce', evs, moves: ['Dig']},
      {species: 'Abra', evs, moves: ['Splash', 'Protect', 'Substitute']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    // Lock-On skips to-hit rolls
    battle.makeChoices('move 2', 'move 1');

    battle.makeChoices('', 'switch 2');

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('switch 2', 'move 1');

    // Lock-On doesn't last through switching
    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 1', 'move 1');

    // Lock-On doesn't bypass Protect
    battle.makeChoices('move 2', 'move 2');

    // Substitute blocks Lock-On
    battle.makeChoices('move 1', 'move 3');

    verify(battle, [
      '|move|p1a: Machamp|Lock-On|p2a: Dunsparce',
      '|-activate|p1a: Machamp|move: Lock-On|[of] p2a: Dunsparce',
      '|move|p2a: Dunsparce|Dig||[still]',
      '|-prepare|p2a: Dunsparce|Dig',
      '|turn|2',
      '|move|p1a: Machamp|Dynamic Punch|p2a: Dunsparce',
      '|-crit|p2a: Dunsparce',
      '|-supereffective|p2a: Dunsparce',
      '|-damage|p2a: Dunsparce|0 fnt',
      '|faint|p2a: Dunsparce',
      '|switch|p2a: Abra|Abra, M|253/253',
      '|turn|3',
      '|move|p2a: Abra|Splash|p2a: Abra',
      '|-nothing',
      '|-fail|p2a: Abra',
      '|move|p1a: Machamp|Lock-On|p2a: Abra',
      '|-activate|p1a: Machamp|move: Lock-On|[of] p2a: Abra',
      '|turn|4',
      '|switch|p1a: Octillery|Octillery, M|353/353',
      '|move|p2a: Abra|Splash|p2a: Abra',
      '|-nothing',
      '|-fail|p2a: Abra',
      '|turn|5',
      '|move|p2a: Abra|Splash|p2a: Abra',
      '|-nothing',
      '|-fail|p2a: Abra',
      '|move|p1a: Octillery|Zap Cannon|p2a: Abra|[miss]',
      '|-miss|p1a: Octillery',
      '|turn|6',
      '|move|p2a: Abra|Splash|p2a: Abra',
      '|-nothing',
      '|-fail|p2a: Abra',
      '|move|p1a: Octillery|Lock-On|p2a: Abra',
      '|-activate|p1a: Octillery|move: Lock-On|[of] p2a: Abra',
      '|turn|7',
      '|move|p2a: Abra|Protect|p2a: Abra',
      '|-singleturn|p2a: Abra|Protect',
      '|move|p1a: Octillery|Zap Cannon|p2a: Abra',
      '|-activate|p2a: Abra|Protect',
      '|turn|8',
      '|move|p2a: Abra|Substitute|p2a: Abra',
      '|-start|p2a: Abra|Substitute',
      '|-damage|p2a: Abra|190/253',
      '|move|p1a: Octillery|Lock-On|p2a: Abra',
      '|-activate|p2a: Abra|Substitute|[block] Lock-On',
      '|turn|9',
    ]);
  });

  test('Nightmare effect', () => {
    let p2hp = 0;
    const battle = startBattle([QKC, QKC, SLP(2), QKC, QKC, QKC, QKC, QKC, SLP(2), QKC], [
      {species: 'Misdreavus', evs, moves: ['Nightmare', 'Splash']},
    ], [
      {species: 'Jolteon', evs, moves: ['Sand-Attack', 'Rest', 'Splash', 'Substitute']},
    ], b => {
      p2hp = b.p2.pokemon[0].hp;
      b.p2.pokemon[0].hp = 1;
    });

    // Fails when foe is not sleeping
    battle.makeChoices('move 1', 'move 1');

    // Bypasses accuracy and always hits when foe is sleeping
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    // Damage equal to one quarter maximum HP each turn
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);

    // Nightmare ends when foe wakes up
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 2', 'move 4');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);

    // Substitute blocks Nightmare
    battle.makeChoices('move 1', 'move 2');

    verify(battle, [
      '|switch|p1a: Misdreavus|Misdreavus, M|323/323',
      '|switch|p2a: Jolteon|Jolteon, M|1/333',
      '|turn|1',
      '|move|p2a: Jolteon|Sand Attack|p1a: Misdreavus',
      '|-unboost|p1a: Misdreavus|accuracy|1',
      '|move|p1a: Misdreavus|Nightmare|p2a: Jolteon',
      '|-fail|p2a: Jolteon',
      '|turn|2',
      '|move|p2a: Jolteon|Rest|p2a: Jolteon',
      '|-status|p2a: Jolteon|slp|[from] move: Rest',
      '|-heal|p2a: Jolteon|333/333 slp|[silent]',
      '|move|p1a: Misdreavus|Nightmare|p2a: Jolteon',
      '|-start|p2a: Jolteon|Nightmare',
      '|turn|3',
      '|cant|p2a: Jolteon|slp',
      '|-damage|p2a: Jolteon|250/333 slp|[from] Nightmare|[of] p1a: Misdreavus',
      '|move|p1a: Misdreavus|Nightmare|p2a: Jolteon',
      '|-fail|p2a: Jolteon',
      '|turn|4',
      '|cant|p2a: Jolteon|slp',
      '|-damage|p2a: Jolteon|167/333 slp|[from] Nightmare|[of] p1a: Misdreavus',
      '|move|p1a: Misdreavus|Splash|p1a: Misdreavus',
      '|-nothing',
      '|-fail|p1a: Misdreavus',
      '|turn|5',
      '|-curestatus|p2a: Jolteon|slp|[msg]',
      '|-end|p2a: Jolteon|Nightmare|[silent]',
      '|move|p2a: Jolteon|Splash|p2a: Jolteon',
      '|-nothing',
      '|-fail|p2a: Jolteon',
      '|move|p1a: Misdreavus|Splash|p1a: Misdreavus',
      '|-nothing',
      '|-fail|p1a: Misdreavus',
      '|turn|6',
      '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
      '|-start|p2a: Jolteon|Substitute',
      '|-damage|p2a: Jolteon|84/333',
      '|move|p1a: Misdreavus|Splash|p1a: Misdreavus',
      '|-nothing',
      '|-fail|p1a: Misdreavus',
      '|turn|7',
      '|move|p2a: Jolteon|Rest|p2a: Jolteon',
      '|-status|p2a: Jolteon|slp|[from] move: Rest',
      '|-heal|p2a: Jolteon|333/333 slp|[silent]',
      '|move|p1a: Misdreavus|Nightmare|p2a: Jolteon',
      '|-activate|p2a: Jolteon|Substitute|[block] Nightmare',
      '|turn|8',
    ]);
  });

  test('Curse effect', () => {
    // Ghost
    {
      const battle = startBattle([QKC, QKC, QKC, QKC, QKC], [
        {species: 'Misdreavus', level: 98, evs, moves: ['Curse']},
        {species: 'Jolteon', evs, moves: ['Substitute']},
      ], [
        {species: 'Furret', evs, moves: ['Protect', 'Splash']},
        {species: 'Gastly', evs, moves: ['Curse']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      // Hits through Protect, subtracts half user's health
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 158);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      // Fails when already Cursed, damages 1/4 HP
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 93);

      // Can cause user's HP to drop to 0 but is still successful
      battle.makeChoices('move 1', 'switch 2');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].volatiles['curse']).toBeDefined();

      battle.makeChoices('switch 2', '');

      // Blocked by Substitute
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[1].volatiles['curse']).toBeUndefined();

      verify(battle, [
        '|move|p2a: Furret|Protect|p2a: Furret',
        '|-singleturn|p2a: Furret|Protect',
        '|move|p1a: Misdreavus|Curse|p2a: Furret',
        '|-start|p2a: Furret|Curse|[of] p1a: Misdreavus',
        '|-damage|p1a: Misdreavus|158/316',
        '|turn|2',
        '|move|p2a: Furret|Splash|p2a: Furret',
        '|-nothing',
        '|-fail|p2a: Furret',
        '|-damage|p2a: Furret|280/373|[from] Curse',
        '|move|p1a: Misdreavus|Curse|p2a: Furret',
        '|-fail|p2a: Furret',
        '|turn|3',
        '|switch|p2a: Gastly|Gastly, M|263/263',
        '|move|p1a: Misdreavus|Curse|p2a: Gastly',
        '|-start|p2a: Gastly|Curse|[of] p1a: Misdreavus',
        '|-damage|p1a: Misdreavus|0 fnt',
        '|faint|p1a: Misdreavus',
        '|switch|p1a: Jolteon|Jolteon, M|333/333',
        '|turn|4',
        '|move|p1a: Jolteon|Substitute|p1a: Jolteon',
        '|-start|p1a: Jolteon|Substitute',
        '|-damage|p1a: Jolteon|250/333',
        '|move|p2a: Gastly|Curse|p1a: Jolteon',
        '|-fail|p1a: Jolteon',
        '|-damage|p2a: Gastly|198/263|[from] Curse|[of] p1a: Jolteon',
        '|turn|5',
      ]);
    }
    // Non-Ghost
    {
      const curse = {key: 'data/mods/gen2/scripts.ts:441:59', value: 0};
      const battle = startBattle([QKC, QKC, QKC, QKC, QKC, curse, QKC, curse, QKC, curse, QKC], [
        {species: 'Snorlax', evs, moves: ['Swords Dance', 'Iron Defense', 'Curse']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Splash']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].boosts.atk).toBe(2);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].boosts.atk).toBe(4);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].boosts.def).toBe(2);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].boosts.def).toBe(4);

      battle.makeChoices('move 3', 'move 1');
      expect(battle.p1.pokemon[0].boosts.atk).toBe(5);
      expect(battle.p1.pokemon[0].boosts.def).toBe(5);
      expect(battle.p1.pokemon[0].boosts.spe).toBe(-1);

      battle.makeChoices('move 3', 'move 1');
      // expect(battle.p1.pokemon[0].boosts.atk).toBe(6);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(5);
      expect(battle.p1.pokemon[0].boosts.def).toBe(6);
      expect(battle.p1.pokemon[0].boosts.spe).toBe(-2);

      // Curse should fail if Attack and Defense are both at +6, even if Speed isn't at -6
      battle.makeChoices('move 3', 'move 1');
      // expect(battle.p1.pokemon[0].boosts.atk).toBe(6);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(5);
      expect(battle.p1.pokemon[0].boosts.def).toBe(6);
      // expect(battle.p1.pokemon[0].boosts.spe).toBe(-2);
      expect(battle.p1.pokemon[0].boosts.spe).toBe(-3);

      verify(battle, [
        '|move|p1a: Snorlax|Swords Dance|p1a: Snorlax',
        '|-boost|p1a: Snorlax|atk|2',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|turn|2',
        '|move|p1a: Snorlax|Swords Dance|p1a: Snorlax',
        '|-boost|p1a: Snorlax|atk|2',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|turn|3',
        '|move|p1a: Snorlax|Iron Defense|p1a: Snorlax',
        '|-boost|p1a: Snorlax|def|2',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|turn|4',
        '|move|p1a: Snorlax|Iron Defense|p1a: Snorlax',
        '|-boost|p1a: Snorlax|def|2',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|turn|5',
        '|move|p1a: Snorlax|Curse|p1a: Snorlax',
        '|-unboost|p1a: Snorlax|spe|1',
        '|-boost|p1a: Snorlax|atk|1',
        '|-boost|p1a: Snorlax|def|1',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|turn|6',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|move|p1a: Snorlax|Curse|p1a: Snorlax',
        '|-unboost|p1a: Snorlax|spe|1',
        '|-boost|p1a: Snorlax|atk|0',
        '|-boost|p1a: Snorlax|def|1',
        '|turn|7',
        '|move|p2a: Slowpoke|Splash|p2a: Slowpoke',
        '|-nothing',
        '|-fail|p2a: Slowpoke',
        '|move|p1a: Snorlax|Curse|p1a: Snorlax',
        '|-unboost|p1a: Snorlax|spe|1',
        '|-boost|p1a: Snorlax|atk|0',
        '|-boost|p1a: Snorlax|def|0',
        '|turn|8',
      ]);
    }
  });

  test('Reversal effect', () => {
    const battle = startBattle([QKC, QKC, QKC, QKC, QKC, QKC], [
      {species: 'Hitmontop', evs, moves: ['Reversal']},
    ], [
      {species: 'Sudowoodo', evs, moves: ['Flail']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 36);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 36);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 48);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 88);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 92);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|295/343',
      '|move|p2a: Sudowoodo|Flail|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|284/303',
      '|turn|2',
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|247/343',
      '|move|p2a: Sudowoodo|Flail|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|265/303',
      '|turn|3',
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|199/343',
      '|move|p2a: Sudowoodo|Flail|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|229/303',
      '|turn|4',
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|151/343',
      '|move|p2a: Sudowoodo|Flail|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|193/303',
      '|turn|5',
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|59/343',
      '|move|p2a: Sudowoodo|Flail|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|105/303',
      '|turn|6',
      '|move|p1a: Hitmontop|Reversal|p2a: Sudowoodo',
      '|-supereffective|p2a: Sudowoodo',
      '|-damage|p2a: Sudowoodo|0 fnt',
      '|faint|p2a: Sudowoodo',
      '|win|Player 1',
    ]);
  });

  test('Spite effect', () => {
    const spite2 = {key: 'data/mods/gen3/moves.ts:569:22', value: ranged(0, 4)};
    const spite3 = {...spite2, value: ranged(1, 4)};
    const battle = startBattle([
      QKC, spite2, MISS, QKC, spite2, MISS, QKC, spite3, MISS, QKC, spite2, QKC,
    ], [
      {species: 'Misdreavus', evs, moves: ['Spite']},
    ], [
      {species: 'Ampharos', evs, moves: ['Zap Cannon', 'Splash']},
    ]);

    let pp = battle.p2.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(pp -= 3);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(pp -= 4);

    battle.makeChoices('move 1', 'move 2');

    verify(battle, [
      '|move|p1a: Misdreavus|Spite|p2a: Ampharos',
      '|-fail|p2a: Ampharos',
      '|move|p2a: Ampharos|Zap Cannon|p1a: Misdreavus|[miss]',
      '|-miss|p2a: Ampharos',
      '|turn|2',
      '|move|p1a: Misdreavus|Spite|p2a: Ampharos',
      '|-activate|p2a: Ampharos|move: Spite|zapcannon|2',
      '|move|p2a: Ampharos|Zap Cannon|p1a: Misdreavus|[miss]',
      '|-miss|p2a: Ampharos',
      '|turn|3',
      '|move|p1a: Misdreavus|Spite|p2a: Ampharos',
      '|-activate|p2a: Ampharos|move: Spite|zapcannon|3',
      '|move|p2a: Ampharos|Zap Cannon|p1a: Misdreavus|[miss]',
      '|-miss|p2a: Ampharos',
      '|turn|4',
      '|move|p1a: Misdreavus|Spite|p2a: Ampharos',
      '|-fail|p2a: Ampharos',
      '|move|p2a: Ampharos|Splash|p2a: Ampharos',
      '|-nothing',
      '|-fail|p2a: Ampharos',
      '|turn|5',
    ]);
  });

  test('Protect effect', () => {
    const no_protect = {key: 'data/mods/gen2/conditions.ts:227:16', value: ranged(127, 255) + 1};
    const battle = startBattle([
      QKC, QKC, HIT, QKC, NO_CRIT, MIN_DMG, QKC, QKC, no_protect, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Raikou', evs, moves: ['Protect', 'Toxic', 'Thunderbolt']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Protect', 'Substitute', 'Surf']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Protect blocks all effects of moves
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.active[0].status).toBe('');

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.active[0].status).toBe('tox');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 95 - 23);

    // Fails when used behind Substitute
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 46);
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeUndefined();

    // Protect fails if used second
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 69);

    // Protect has an increased chance of failing on successive uses
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 62);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 92);

    verify(battle, [
      '|move|p2a: Slowpoke|Protect|p2a: Slowpoke',
      '|-singleturn|p2a: Slowpoke|Protect',
      '|move|p1a: Raikou|Toxic|p2a: Slowpoke',
      '|-activate|p2a: Slowpoke|Protect',
      '|turn|2',
      '|move|p1a: Raikou|Toxic|p2a: Slowpoke',
      '|-status|p2a: Slowpoke|tox',
      '|move|p2a: Slowpoke|Substitute|p2a: Slowpoke',
      '|-start|p2a: Slowpoke|Substitute',
      '|-damage|p2a: Slowpoke|288/383 tox',
      '|-damage|p2a: Slowpoke|265/383 tox|[from] psn',
      '|turn|3',
      '|move|p2a: Slowpoke|Protect|p2a: Slowpoke',
      '|-fail|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|219/383 tox|[from] psn',
      '|move|p1a: Raikou|Thunderbolt|p2a: Slowpoke',
      '|-supereffective|p2a: Slowpoke',
      '|-end|p2a: Slowpoke|Substitute',
      '|turn|4',
      '|move|p1a: Raikou|Protect|p1a: Raikou',
      '|-singleturn|p1a: Raikou|Protect',
      '|move|p2a: Slowpoke|Protect|p2a: Slowpoke',
      '|-fail|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|150/383 tox|[from] psn',
      '|turn|5',
      '|move|p1a: Raikou|Protect|p1a: Raikou',
      '|-fail|p1a: Raikou',
      '|move|p2a: Slowpoke|Surf|p1a: Raikou',
      '|-damage|p1a: Raikou|321/383',
      '|-damage|p2a: Slowpoke|58/383 tox|[from] psn',
      '|turn|6',
    ]);
  });

  test('Endure effect', () => {
    const proc2 = {key: 'data/mods/gen2/conditions.ts:227:16', value: ranged(127, 255)};
    const no_proc3 = {...proc2, value: ranged(63, 255) + 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG,
      QKC, proc2, NO_CRIT, MIN_DMG,
      QKC, no_proc3, NO_CRIT, MIN_DMG,
    ], [
      {species: 'Charmander', level: 10, evs, moves: ['Endure']},
    ], [
      {species: 'Dragonite', evs, moves: ['Extreme Speed']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(1);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Charmander|Endure|p1a: Charmander',
      '|-singleturn|p1a: Charmander|move: Endure',
      '|move|p2a: Dragonite|Extreme Speed|p1a: Charmander',
      '|-activate|p1a: Charmander|move: Endure',
      '|-damage|p1a: Charmander|1/37',
      '|turn|2',
      '|move|p1a: Charmander|Endure|p1a: Charmander',
      '|-singleturn|p1a: Charmander|move: Endure',
      '|move|p2a: Dragonite|Extreme Speed|p1a: Charmander',
      '|-activate|p1a: Charmander|move: Endure',
      '|-damage|p1a: Charmander|1/37',
      '|turn|3',
      '|move|p1a: Charmander|Endure|p1a: Charmander',
      '|-fail|p1a: Charmander',
      '|move|p2a: Dragonite|Extreme Speed|p1a: Charmander',
      '|-damage|p1a: Charmander|0 fnt',
      '|faint|p1a: Charmander',
      '|win|Player 2',
    ]);
  });

  test('BellyDrum effect', () => {
    const battle = startBattle([QKC, QKC, QKC], [
      {species: 'Lickitung', evs: {...evs, hp: 0}, moves: ['Belly Drum']},
    ], [
      {species: 'Umbreon', evs, moves: ['Charm', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 160);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(6);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);

    verify(battle, [
      '|move|p2a: Umbreon|Charm|p1a: Lickitung',
      '|-unboost|p1a: Lickitung|atk|2',
      '|move|p1a: Lickitung|Belly Drum|p1a: Lickitung',
      '|-damage|p1a: Lickitung|160/320',
      '|-setboost|p1a: Lickitung|atk|6|[from] move: Belly Drum',
      '|turn|2',
      '|move|p2a: Umbreon|Splash|p2a: Umbreon',
      '|-nothing',
      '|-fail|p2a: Umbreon',
      '|move|p1a: Lickitung|Belly Drum|p1a: Lickitung',
      '|-fail|p1a: Lickitung',
      '|turn|3',
    ]);
  });

  test('Spikes effect', () => {
    const battle = startBattle([QKC, QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Pineco', evs, moves: ['Spikes', 'Splash']},
    ], [
      {species: 'Forretress', evs, moves: ['Rapid Spin']},
      {species: 'Mantine', evs, moves: ['Fly']},
    ]);

    const pineco = battle.p1.pokemon[0].hp;
    const forretress = battle.p2.pokemon[0].hp;
    const mantine = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.sideConditions['spikes']).toBeDefined();
    expect(battle.p2.pokemon[0].hp).toBe(mantine);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(forretress - 44);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(pineco - 15);
    expect(battle.p2.sideConditions['spikes']).toBeUndefined();

    verify(battle, [
      '|switch|p2a: Mantine|Mantine, M|333/333',
      '|move|p1a: Pineco|Spikes|p2a: Mantine',
      '|-sidestart|p2: Player 2|Spikes',
      '|turn|2',
      '|switch|p2a: Forretress|Forretress, M|353/353',
      '|-damage|p2a: Forretress|309/353|[from] Spikes',
      '|move|p1a: Pineco|Spikes|p2a: Forretress',
      '|-fail|p2a: Forretress',
      '|turn|3',
      '|move|p2a: Forretress|Rapid Spin|p1a: Pineco',
      '|-damage|p1a: Pineco|288/303',
      '|-sideend|p2: Player 2|Spikes|[from] move: Rapid Spin|[of] p2a: Forretress',
      '|move|p1a: Pineco|Splash|p1a: Pineco',
      '|-nothing',
      '|-fail|p1a: Pineco',
      '|turn|4',
    ]);
  });

  test('RapidSpin effect', () => {
    const battle = startBattle([
      QKC, QKC, HIT, QKC, HIT, NO_CRIT, MIN_DMG, MIN_WRAP, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Venusaur', evs, moves: ['Spikes', 'Leech Seed', 'Wrap']},
    ], [
      {species: 'Donphan', evs, moves: ['Defense Curl', 'Rapid Spin']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.sideConditions['spikes']).toBeDefined();

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 47);
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeDefined();

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 19);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 5);
    expect(battle.p2.sideConditions['spikes']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['leechseed']).toBeUndefined();
    expect(battle.p2.pokemon[0].volatiles['partiallytrapped']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Venusaur|Spikes|p2a: Donphan',
      '|-sidestart|p2: Player 2|Spikes',
      '|move|p2a: Donphan|Defense Curl|p2a: Donphan',
      '|-boost|p2a: Donphan|def|1',
      '|turn|2',
      '|move|p1a: Venusaur|Leech Seed|p2a: Donphan',
      '|-start|p2a: Donphan|move: Leech Seed',
      '|move|p2a: Donphan|Defense Curl|p2a: Donphan',
      '|-boost|p2a: Donphan|def|1',
      '|-damage|p2a: Donphan|336/383|[from] Leech Seed|[of] p1a: Venusaur',
      '|turn|3',
      '|move|p1a: Venusaur|Wrap|p2a: Donphan',
      '|-damage|p2a: Donphan|331/383',
      '|-activate|p2a: Donphan|move: Wrap|[of] p1a: Venusaur',
      '|move|p2a: Donphan|Rapid Spin|p1a: Venusaur',
      '|-damage|p1a: Venusaur|344/363',
      '|-end|p2a: Donphan|Leech Seed|[from] move: Rapid Spin|[of] p2a: Donphan',
      '|-sideend|p2: Player 2|Spikes|[from] move: Rapid Spin|[of] p2a: Donphan',
      '|-end|p2a: Donphan|Wrap|[partiallytrapped]',
      '|turn|4',
    ]);
  });

  test('Foresight effect', () => {
    const hit = {...HIT, value: ranged(Math.floor(90 * 255 / 100), 256) - 1};
    const no_proc = SECONDARY(ranged(76, 256));
    const battle = startBattle([
      QKC, MISS, QKC, HIT, QKC, hit, QKC, HIT, QKC, QKC, HIT, NO_CRIT, MIN_DMG, no_proc, QKC,
    ], [
      {species: 'Noctowl', evs, moves: ['Foresight', 'Steel Wing', 'Baton Pass']},
      {species: 'Machoke', evs, moves: ['Low Kick']},
    ], [
      {species: 'Raikou', evs, moves: ['Sand Attack', 'Double Team']},
      {species: 'Gengar', evs, moves: ['Splash']},
    ]);

    const gengar = battle.p2.pokemon[1].hp;

    // Can miss (100% accuracy)
    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 2');

    // Ignores accuracy/evasiveness stages
    battle.makeChoices('move 2', 'move 2');

    battle.makeChoices('move 1', 'switch 2');
    battle.makeChoices('move 3', 'move 1');
    battle.makeChoices('switch 2', '');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(gengar - 37);

    verify(battle, [
      '|move|p2a: Raikou|Sand Attack|p1a: Noctowl',
      '|-unboost|p1a: Noctowl|accuracy|1',
      '|move|p1a: Noctowl|Foresight|p2a: Raikou|[miss]',
      '|-miss|p1a: Noctowl',
      '|turn|2',
      '|move|p2a: Raikou|Double Team|p2a: Raikou',
      '|-boost|p2a: Raikou|evasion|1',
      '|move|p1a: Noctowl|Foresight|p2a: Raikou',
      '|-start|p2a: Raikou|Foresight',
      '|turn|3',
      '|move|p2a: Raikou|Double Team|p2a: Raikou',
      '|-boost|p2a: Raikou|evasion|1',
      '|move|p1a: Noctowl|Steel Wing|p2a: Raikou|[miss]',
      '|-miss|p1a: Noctowl',
      '|turn|4',
      '|switch|p2a: Gengar|Gengar, M|323/323',
      '|move|p1a: Noctowl|Foresight|p2a: Gengar',
      '|-start|p2a: Gengar|Foresight',
      '|turn|5',
      '|move|p2a: Gengar|Splash|p2a: Gengar',
      '|-nothing',
      '|-fail|p2a: Gengar',
      '|move|p1a: Noctowl|Baton Pass|p1a: Noctowl',
      '|switch|p1a: Machoke|Machoke, M|363/363|[from] Baton Pass',
      '|turn|6',
      '|move|p2a: Gengar|Splash|p2a: Gengar',
      '|-nothing',
      '|-fail|p2a: Gengar',
      '|move|p1a: Machoke|Low Kick|p2a: Gengar',
      '|-resisted|p2a: Gengar',
      '|-damage|p2a: Gengar|286/323',
      '|turn|7',
    ]);
  });

  test('DestinyBond effect', () => {
    const battle = startBattle([QKC, CRIT, MAX_DMG, QKC, NO_CRIT, MIN_DMG], [
      {species: 'Misdreavus', evs, moves: ['Destiny Bond']},
    ], [
      {species: 'Tyranitar', evs, moves: ['Earthquake']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 284);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Misdreavus|Destiny Bond|p1a: Misdreavus',
      '|-singlemove|p1a: Misdreavus|Destiny Bond',
      '|move|p2a: Tyranitar|Earthquake|p1a: Misdreavus',
      '|-crit|p1a: Misdreavus',
      '|-damage|p1a: Misdreavus|39/323',
      '|turn|2',
      '|move|p1a: Misdreavus|Destiny Bond|p1a: Misdreavus',
      '|-singlemove|p1a: Misdreavus|Destiny Bond',
      '|move|p2a: Tyranitar|Earthquake|p1a: Misdreavus',
      '|-damage|p1a: Misdreavus|0 fnt',
      '|faint|p1a: Misdreavus',
      '|-activate|p1a: Misdreavus|move: Destiny Bond',
      '|faint|p2a: Tyranitar',
      '|tie',
    ]);
  });

  test('PerishSong effect', () => {
    const battle = startBattle(QKCs(9), [
      {species: 'Politoed', evs, moves: ['Perish Song', 'Splash']},
      {species: 'Celebi', evs, moves: ['Perish Song', 'Splash']},
      {species: 'Smoochum', evs, moves: ['Splash']},
    ], [
      {species: 'Togetic', evs, moves: ['Baton Pass', 'Splash']},
      {species: 'Furret', evs, moves: ['Splash']},
      {species: 'Misdreavus', evs, moves: ['Splash']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('', 'switch 2');

    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 2', 'move 1');
    battle.makeChoices('move 2', 'move 1');

    battle.makeChoices('switch 2', 'switch 2');

    battle.makeChoices('move 1', 'move 2');
    battle.makeChoices('move 1', 'switch 3');
    battle.makeChoices('move 2', 'move 1');

    battle.makeChoices('switch 3', 'move 1');
    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Politoed|Perish Song|p1a: Politoed',
      '|-start|p1a: Politoed|perish3|[silent]',
      '|-start|p2a: Togetic|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|move|p2a: Togetic|Baton Pass|p2a: Togetic',
      '|switch|p2a: Furret|Furret, M|373/373|[from] Baton Pass',
      '|-start|p1a: Politoed|perish3',
      '|-start|p2a: Furret|perish3',
      '|turn|2',
      '|move|p2a: Furret|Splash|p2a: Furret',
      '|-nothing',
      '|-fail|p2a: Furret',
      '|move|p1a: Politoed|Splash|p1a: Politoed',
      '|-nothing',
      '|-fail|p1a: Politoed',
      '|-start|p1a: Politoed|perish2',
      '|-start|p2a: Furret|perish2',
      '|turn|3',
      '|move|p2a: Furret|Splash|p2a: Furret',
      '|-nothing',
      '|-fail|p2a: Furret',
      '|move|p1a: Politoed|Splash|p1a: Politoed',
      '|-nothing',
      '|-fail|p1a: Politoed',
      '|-start|p1a: Politoed|perish1',
      '|-start|p2a: Furret|perish1',
      '|turn|4',
      '|move|p2a: Furret|Splash|p2a: Furret',
      '|-nothing',
      '|-fail|p2a: Furret',
      '|move|p1a: Politoed|Splash|p1a: Politoed',
      '|-nothing',
      '|-fail|p1a: Politoed',
      '|-start|p1a: Politoed|perish0',
      '|-start|p2a: Furret|perish0',
      '|faint|p1a: Politoed',
      '|faint|p2a: Furret',
      '|switch|p2a: Togetic|Togetic, M|313/313',
      '|switch|p1a: Celebi|Celebi|403/403',
      '|turn|5',
      '|move|p1a: Celebi|Perish Song|p1a: Celebi',
      '|-start|p1a: Celebi|perish3|[silent]',
      '|-start|p2a: Togetic|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|move|p2a: Togetic|Splash|p2a: Togetic',
      '|-nothing',
      '|-fail|p2a: Togetic',
      '|-start|p1a: Celebi|perish3',
      '|-start|p2a: Togetic|perish3',
      '|turn|6',
      '|switch|p2a: Misdreavus|Misdreavus, M|323/323',
      '|move|p1a: Celebi|Perish Song|p1a: Celebi',
      '|-start|p2a: Misdreavus|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|-start|p1a: Celebi|perish2',
      '|-start|p2a: Misdreavus|perish3',
      '|turn|7',
      '|move|p1a: Celebi|Splash|p1a: Celebi',
      '|-nothing',
      '|-fail|p1a: Celebi',
      '|move|p2a: Misdreavus|Splash|p2a: Misdreavus',
      '|-nothing',
      '|-fail|p2a: Misdreavus',
      '|-start|p1a: Celebi|perish1',
      '|-start|p2a: Misdreavus|perish2',
      '|turn|8',
      '|switch|p1a: Smoochum|Smoochum, F|293/293',
      '|move|p2a: Misdreavus|Splash|p2a: Misdreavus',
      '|-nothing',
      '|-fail|p2a: Misdreavus',
      '|-start|p2a: Misdreavus|perish1',
      '|turn|9',
      '|move|p2a: Misdreavus|Splash|p2a: Misdreavus',
      '|-nothing',
      '|-fail|p2a: Misdreavus',
      '|move|p1a: Smoochum|Splash|p1a: Smoochum',
      '|-nothing',
      '|-fail|p1a: Smoochum',
      '|-start|p2a: Misdreavus|perish0',
      '|faint|p2a: Misdreavus',
    ]);
  });

  test('Rollout effect', () => {
    const proc = {key: 'data/mods/gen2/moves.ts:771:40', value: MIN};
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, MISS,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, SLP(5),
      QKC, proc, HIT, NO_CRIT, MIN_DMG,
      QKC, QKC,
    ], [
      {species: 'Shuckle', evs, moves: ['Rollout', 'Sleep Talk']},
      {species: 'Pupitar', evs, moves: ['Harden']},
    ], [
      {species: 'Blissey', evs, moves: ['Soft-Boiled', 'Sing']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);

    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 34);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    for (let i = 0; i < 5; i++) {
      battle.makeChoices('move 1', 'move 1');
    }
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 516);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 2');

    // Does not lock-in if called via Sleep Talk
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp + 357 - 34);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 193);

    verify(battle, [
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-fail|p2a: Blissey',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|679/713',
      '|turn|2',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey|[miss]',
      '|-miss|p1a: Shuckle',
      '|turn|3',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-fail|p2a: Blissey',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|679/713',
      '|turn|4',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|647/713',
      '|turn|5',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|583/713',
      '|turn|6',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|455/713',
      '|turn|7',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|197/713',
      '|turn|8',
      '|move|p2a: Blissey|Sing|p1a: Shuckle',
      '|-status|p1a: Shuckle|slp|[from] move: Sing',
      '|cant|p1a: Shuckle|slp',
      '|turn|9',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|554/713',
      '|cant|p1a: Shuckle|slp',
      '|move|p1a: Shuckle|Sleep Talk|p1a: Shuckle',
      '|move|p1a: Shuckle|Rollout|p2a: Blissey|[from]Sleep Talk',
      '|-damage|p2a: Blissey|520/713',
      '|turn|10',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|cant|p1a: Shuckle|slp',
      '|turn|11',
    ]);
  });

  test('FalseSwipe effect', () => {
    const battle = startBattle([QKC, QKC, NO_CRIT, MAX_DMG, QKC, NO_CRIT, MAX_DMG, QKC], [
      {species: 'Scizor', evs, moves: ['False Swipe', 'Splash']},
    ], [
      {species: 'Phanpy', level: 3, evs, moves: ['Defense Curl', 'Substitute']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 5);
    expect(battle.p2.pokemon[0].volatiles['substitute'].hp).toBe(5);

    // False Swipe does not leave Substitute at 1 HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeUndefined();

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(1);

    verify(battle, [
      '|move|p1a: Scizor|Splash|p1a: Scizor',
      '|-nothing',
      '|-fail|p1a: Scizor',
      '|move|p2a: Phanpy|Substitute|p2a: Phanpy',
      '|-start|p2a: Phanpy|Substitute',
      '|-damage|p2a: Phanpy|16/21',
      '|turn|2',
      '|move|p1a: Scizor|False Swipe|p2a: Phanpy',
      '|-end|p2a: Phanpy|Substitute',
      '|move|p2a: Phanpy|Defense Curl|p2a: Phanpy',
      '|-boost|p2a: Phanpy|def|1',
      '|turn|3',
      '|move|p1a: Scizor|False Swipe|p2a: Phanpy',
      '|-damage|p2a: Phanpy|1/21',
      '|move|p2a: Phanpy|Defense Curl|p2a: Phanpy',
      '|-boost|p2a: Phanpy|def|1',
      '|turn|4',
    ]);
  });

  test('Swagger effect', () => {
    const battle = startBattle([
      QKC, HIT, CFZ(3), QKC, CFZ_CANT, HIT, QKC, CFZ_CANT, HIT, QKC, MISS, QKC, HIT, QKC,
    ], [
      {species: 'Scyther', evs, moves: ['Swords Dance', 'Swagger']},
    ], [
      {species: 'Aipom', evs, moves: ['Swagger', 'Substitute']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(4);
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 126);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(6);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 132);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(6);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 78);
    expect(battle.p2.pokemon[0].volatiles['substitute']).toBeDefined();

    // Attack is still sharply raised behind a Substitute but confusion is not inflicted
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Scyther|Swords Dance|p1a: Scyther',
      '|-boost|p1a: Scyther|atk|2',
      '|move|p2a: Aipom|Swagger|p1a: Scyther',
      '|-boost|p1a: Scyther|atk|2',
      '|-start|p1a: Scyther|confusion',
      '|turn|2',
      '|-activate|p1a: Scyther|confusion',
      '|-damage|p1a: Scyther|217/343|[from] confusion',
      '|move|p2a: Aipom|Swagger|p1a: Scyther',
      '|-boost|p1a: Scyther|atk|2',
      '|turn|3',
      '|-activate|p1a: Scyther|confusion',
      '|-damage|p1a: Scyther|85/343|[from] confusion',
      '|move|p2a: Aipom|Swagger|p1a: Scyther',
      '|-miss|p2a: Aipom',
      '|turn|4',
      '|-end|p1a: Scyther|confusion',
      '|move|p1a: Scyther|Swagger|p2a: Aipom|[miss]',
      '|-miss|p1a: Scyther',
      '|move|p2a: Aipom|Substitute|p2a: Aipom',
      '|-start|p2a: Aipom|Substitute',
      '|-damage|p2a: Aipom|235/313',
      '|turn|5',
      '|move|p1a: Scyther|Swagger|p2a: Aipom',
      '|-boost|p2a: Aipom|atk|2',
      '|move|p2a: Aipom|Substitute|p2a: Aipom',
      '|-fail|p2a: Aipom|move: Substitute',
      '|turn|6',
    ]);
  });

  test('FuryCutter effect', () => {
    const proc = {key: 'data/mods/gen2/moves.ts:771:40', value: MIN};
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, MISS,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, SLP(5),
      QKC, proc, HIT, NO_CRIT, MIN_DMG,
      QKC, QKC,
    ], [
      {species: 'Shuckle', evs, moves: ['Fury Cutter', 'Sleep Talk']},
      {species: 'Pupitar', evs, moves: ['Harden']},
    ], [
      {species: 'Blissey', evs, moves: ['Soft-Boiled', 'Sing']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 12);

    expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 12);

    for (let i = 0; i < 5; i++) {
      battle.makeChoices('move 1', 'move 1');
    }
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 173);

    battle.makeChoices('move 1', 'move 2');

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp + 173 - 12);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 12);

    verify(battle, [
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-fail|p2a: Blissey',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|701/713',
      '|turn|2',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey|[miss]',
      '|-miss|p1a: Shuckle',
      '|turn|3',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-fail|p2a: Blissey',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|701/713',
      '|turn|4',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|691/713',
      '|turn|5',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|669/713',
      '|turn|6',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|626/713',
      '|turn|7',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey',
      '|-damage|p2a: Blissey|540/713',
      '|turn|8',
      '|move|p2a: Blissey|Sing|p1a: Shuckle',
      '|-status|p1a: Shuckle|slp|[from] move: Sing',
      '|cant|p1a: Shuckle|slp',
      '|turn|9',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|cant|p1a: Shuckle|slp',
      '|move|p1a: Shuckle|Sleep Talk|p1a: Shuckle',
      '|move|p1a: Shuckle|Fury Cutter|p2a: Blissey|[from]Sleep Talk',
      '|-damage|p2a: Blissey|701/713',
      '|turn|10',
      '|move|p2a: Blissey|Soft-Boiled|p2a: Blissey',
      '|-heal|p2a: Blissey|713/713',
      '|cant|p1a: Shuckle|slp',
      '|turn|11',
    ]);
  });

  test('Attract effect', () => {
    const can = {key: 'data/moves.ts:735:14', value: MAX};
    const cant = {...can, value: MIN};
    const battle = startBattle([QKC, QKC, QKC, QKC, QKC, cant, QKC, can, QKC, QKC], [
      {species: 'Smoochum', evs, moves: ['Attract', 'Splash']},
    ], [
      {species: 'Blissey', evs, moves: ['Splash']},
      {species: 'Celebi', evs, moves: ['Splash']},
      {species: 'Nidoking', evs, moves: ['Substitute', 'Baton Pass']},
      {species: 'Tyrogue', evs, moves: ['Meditate']},
    ]);

    let p2hp = battle.p2.pokemon[2].hp;

    // Can't attract same gender
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['attract']).toBeUndefined();

    // Can't attract Pokémon with unknown gender
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].volatiles['attract']).toBeUndefined();

    battle.makeChoices('move 2', 'switch 3');

    // Can attract Pokémon through a Substitute
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 91);
    expect(battle.p2.pokemon[0].volatiles['attract']).toBeDefined();

    // Infatuated Pokémon are sometimes prevented from moving
    battle.makeChoices('move 1', 'move 2');

    battle.makeChoices('move 2', 'move 2');
    battle.makeChoices('', 'switch 4');

    // Infatuation is not preserved after Baton Pass
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].volatiles['attract']).toBeUndefined();

    verify(battle, [
      '|move|p1a: Smoochum|Attract|p2a: Blissey',
      '|-immune|p2a: Blissey',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|2',
      '|switch|p2a: Celebi|Celebi|403/403',
      '|move|p1a: Smoochum|Attract|p2a: Celebi',
      '|-immune|p2a: Celebi',
      '|turn|3',
      '|switch|p2a: Nidoking|Nidoking, M|365/365',
      '|move|p1a: Smoochum|Splash|p1a: Smoochum',
      '|-nothing',
      '|-fail|p1a: Smoochum',
      '|turn|4',
      '|move|p2a: Nidoking|Substitute|p2a: Nidoking',
      '|-start|p2a: Nidoking|Substitute',
      '|-damage|p2a: Nidoking|274/365',
      '|move|p1a: Smoochum|Attract|p2a: Nidoking',
      '|-start|p2a: Nidoking|Attract',
      '|turn|5',
      '|-activate|p2a: Nidoking|move: Attract|[of] p1a: Smoochum',
      '|cant|p2a: Nidoking|Attract',
      '|move|p1a: Smoochum|Attract|p2a: Nidoking',
      '|-fail|p2a: Nidoking',
      '|turn|6',
      '|-activate|p2a: Nidoking|move: Attract|[of] p1a: Smoochum',
      '|move|p2a: Nidoking|Baton Pass|p2a: Nidoking',
      '|switch|p2a: Tyrogue|Tyrogue, M|273/273|[from] Baton Pass',
      '|move|p1a: Smoochum|Splash|p1a: Smoochum',
      '|-nothing',
      '|-fail|p1a: Smoochum',
      '|turn|7',
      '|move|p1a: Smoochum|Splash|p1a: Smoochum',
      '|-nothing',
      '|-fail|p1a: Smoochum',
      '|move|p2a: Tyrogue|Meditate|p2a: Tyrogue',
      '|-boost|p2a: Tyrogue|atk|1',
      '|turn|8',
    ]);
  });

  test('SleepTalk effect', () => {
    const SLP_TLK = (value: number) => ({key: 'data/mods/gen2/moves.ts:771:40', value});
    const moves = ['Sleep Talk', 'Vital Throw', 'Razor Wind', 'Metronome'];
    const battle = startBattle([
      QKC, SLP(5), QKC, SLP_TLK(MAX), QKC, SLP_TLK(MIN), QKC, SLP_TLK(MAX),
      QKC, SLP(5), QKC, SLP_TLK(MIN), NO_CRIT, MIN_DMG, QKC, SLP_TLK(MAX),
      METRONOME('Fly', moves), QKC, QKC, SLP_TLK(MAX), METRONOME('Spore', moves),
      SLP(5), QKC,
    ], [
      {species: 'Togetic', evs, moves: ['Sleep Talk', 'Splash', 'Rest']},
      {species: 'Marill', evs, moves},
    ], [
      {species: 'Parasect', evs, moves: ['Spore', 'Seismic Toss']},
      {species: 'Magcargo', evs, moves: ['Sleep Talk', 'Dig', 'Skull Bash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.p1.pokemon[0].moveSlots[1].pp = 0;

    // Fails if not asleep
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('slp');
    expect(battle.p1.pokemon[0].statusState.time).toBe(6);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    // Sleep Talk can call Rest
    battle.makeChoices('move 1', 'move 1');

    // Sleep Talk can call moves with 0 PP
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 100);
    expect(battle.p1.pokemon[0].statusState.time).toBe(4);

    // If not at full HP, Rest works via Sleep Talk and resets sleep counter/HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp += 100);
    expect(battle.p1.pokemon[0].statusState.time).toBe(3);

    battle.makeChoices('switch 2', 'move 1');

    // Sleep Talk can call Moves at the incorrect priority
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('slp');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 13);

    // Fails if it calls a two-turn move via Metronome / Mirror Move
    battle.makeChoices('move 1', 'switch 2');

    // expect(choices(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3', 'move 4']);
    expect(choices(battle, 'p1')).toEqual(['move 1']);

    battle.makeChoices('move 1', 'move 1');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    verify(battle, [
      '|move|p1a: Togetic|Sleep Talk|p1a: Togetic',
      '|move|p2a: Parasect|Spore|p1a: Togetic',
      '|-status|p1a: Togetic|slp|[from] move: Spore',
      '|turn|2',
      '|cant|p1a: Togetic|slp',
      '|move|p1a: Togetic|Sleep Talk|p1a: Togetic',
      '|move|p1a: Togetic|Rest|p1a: Togetic|[from]Sleep Talk',
      '|-fail|p1a: Togetic',
      '|move|p2a: Parasect|Spore|p1a: Togetic',
      '|-fail|p1a: Togetic|slp',
      '|turn|3',
      '|cant|p1a: Togetic|slp',
      '|move|p1a: Togetic|Sleep Talk|p1a: Togetic',
      '|move|p1a: Togetic|Splash|p1a: Togetic|[from]Sleep Talk',
      '|-nothing',
      '|-fail|p1a: Togetic',
      '|move|p2a: Parasect|Seismic Toss|p1a: Togetic',
      '|-damage|p1a: Togetic|213/313 slp',
      '|turn|4',
      '|cant|p1a: Togetic|slp',
      '|move|p1a: Togetic|Sleep Talk|p1a: Togetic',
      '|move|p1a: Togetic|Rest|p1a: Togetic|[from]Sleep Talk',
      '|-status|p1a: Togetic|slp|[from] move: Rest',
      '|-heal|p1a: Togetic|313/313 slp|[silent]',
      '|move|p2a: Parasect|Spore|p1a: Togetic',
      '|-fail|p1a: Togetic|slp',
      '|turn|5',
      '|switch|p1a: Marill|Marill, M|343/343',
      '|move|p2a: Parasect|Spore|p1a: Marill',
      '|-status|p1a: Marill|slp|[from] move: Spore',
      '|turn|6',
      '|cant|p1a: Marill|slp',
      '|move|p1a: Marill|Sleep Talk|p1a: Marill',
      '|move|p1a: Marill|Vital Throw|p2a: Parasect|[from]Sleep Talk',
      '|-resisted|p2a: Parasect',
      '|-damage|p2a: Parasect|310/323',
      '|move|p2a: Parasect|Spore|p1a: Marill',
      '|-fail|p1a: Marill|slp',
      '|turn|7',
      '|switch|p2a: Magcargo|Magcargo, M|303/303',
      '|cant|p1a: Marill|slp',
      '|move|p1a: Marill|Sleep Talk|p1a: Marill',
      '|move|p1a: Marill|Metronome|p1a: Marill|[from]Sleep Talk',
      '|move|p1a: Marill|Fly||[from]Metronome|[still]',
      '|-prepare|p1a: Marill|Fly',
      '|turn|8',
      '|cant|p1a: Marill|slp',
      '|move|p2a: Magcargo|Sleep Talk|p2a: Magcargo',
      '|turn|9',
      '|cant|p1a: Marill|slp',
      '|move|p1a: Marill|Sleep Talk|p1a: Marill',
      '|move|p1a: Marill|Metronome|p1a: Marill|[from]Sleep Talk',
      '|move|p1a: Marill|Spore|p2a: Magcargo|[from]Metronome',
      '|-status|p2a: Magcargo|slp|[from] move: Spore',
      '|cant|p2a: Magcargo|slp',
      '|move|p2a: Magcargo|Sleep Talk|p2a: Magcargo',
      '|-fail|p2a: Magcargo',
      '|turn|10',
    ]);
  });

  test('HealBell effect', () => {
    const proc = SECONDARY(ranged(25, 256) - 1);
    const battle = startBattle([
      QKC, HIT, SLP(8), QKC, HIT, QKC, QKC, CRIT, MAX_DMG, QKC, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Houndoom', evs, moves: ['Toxic', 'Splash', 'Ember']},
    ], [
      {species: 'Igglybuff', evs, moves: ['Rest']},
      {species: 'Miltank', evs, moves: ['Heal Bell', 'Substitute', 'Counter']},
    ], b => {
      b.p2.pokemon[0].hp = 1;
    });

    let p2hp = battle.p2.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('slp');

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].status).toBe('tox');

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 98 - 24);
    expect(battle.p2.active[0].volatiles.residualdmg.counter).toBe(1);

    // Heal Bell works behind a Substitute and cures the entire team's statuses
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].status).toBe('');
    expect(battle.p2.active[0].volatiles.residualdmg.counter).toBe(1);
    expect(battle.p2.pokemon[1].status).toBe('');

    // Residual damage counter doesn't get cleared
    battle.makeChoices('move 3', 'move 3');
    expect(battle.p2.pokemon[0].status).toBe('brn');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 58 - 48);
    // expect(battle.p2.active[0].volatiles.residualdmg.counter).toBe(1);
    expect(battle.p2.active[0].volatiles.residualdmg.counter).toBe(2);

    verify(battle, [
      '|switch|p1a: Houndoom|Houndoom, M|353/353',
      '|switch|p2a: Igglybuff|Igglybuff, M|1/383',
      '|turn|1',
      '|move|p1a: Houndoom|Toxic|p2a: Igglybuff',
      '|-status|p2a: Igglybuff|tox',
      '|move|p2a: Igglybuff|Rest|p2a: Igglybuff',
      '|-status|p2a: Igglybuff|slp|[from] move: Rest',
      '|-heal|p2a: Igglybuff|383/383 slp|[silent]',
      '|turn|2',
      '|switch|p2a: Miltank|Miltank, F|393/393',
      '|move|p1a: Houndoom|Toxic|p2a: Miltank',
      '|-status|p2a: Miltank|tox',
      '|turn|3',
      '|move|p2a: Miltank|Substitute|p2a: Miltank',
      '|-start|p2a: Miltank|Substitute',
      '|-damage|p2a: Miltank|295/393 tox',
      '|-damage|p2a: Miltank|271/393 tox|[from] psn',
      '|move|p1a: Houndoom|Splash|p1a: Houndoom',
      '|-nothing',
      '|-fail|p1a: Houndoom',
      '|turn|4',
      '|move|p2a: Miltank|Heal Bell|p2a: Miltank',
      '|-cureteam|p2a: Miltank|[from] move: Heal Bell',
      '|move|p1a: Houndoom|Ember|p2a: Miltank',
      '|-crit|p2a: Miltank',
      '|-end|p2a: Miltank|Substitute',
      '|turn|5',
      '|move|p1a: Houndoom|Ember|p2a: Miltank',
      '|-damage|p2a: Miltank|213/393',
      '|-status|p2a: Miltank|brn',
      '|move|p2a: Miltank|Counter|p1a: Houndoom',
      '|-fail|p1a: Houndoom',
      '|-damage|p2a: Miltank|165/393 brn|[from] brn|[of] p1a: Houndoom',
      '|turn|6',
    ]);
  });

  test('Return/Frustration effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Granbull', happiness: 200, evs, moves: ['Return', 'Frustration']},
    ], [
      {species: 'Granbull', happiness: 100, evs: slow, moves: ['Return', 'Frustration']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 91);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp -= 118);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 59);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp -= 34);

    verify(battle, [
      '|move|p1a: Granbull|Return|p2a: Granbull',
      '|-damage|p2a: Granbull|265/383',
      '|move|p2a: Granbull|Frustration|p1a: Granbull',
      '|-damage|p1a: Granbull|292/383',
      '|turn|2',
      '|move|p1a: Granbull|Frustration|p2a: Granbull',
      '|-damage|p2a: Granbull|231/383',
      '|move|p2a: Granbull|Return|p1a: Granbull',
      '|-damage|p1a: Granbull|233/383',
      '|turn|3',
    ]);
  });

  test('Present effect', () => {
    const present = {key: 'data/moves.ts:14397:22', value: ranged(1, 10) - 1};
    const present40 = {...present, value: ranged(6, 10) - 1};
    const present120 = {...present, value: ranged(10, 10) - 1};
    const battle = startBattle([
      QKC, present, HIT,
      QKC, present, HIT, present40, HIT, NO_CRIT, MIN_DMG,
      QKC, present120, HIT, NO_CRIT, MIN_DMG, present, MISS, QKC,
    ], [
      {species: 'Delibird', evs, moves: ['Present']},
    ], [
      {species: 'Pichu', level: 90, evs, moves: ['Substitute', 'Present']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 2);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Delibird|Present|p2a: Pichu',
      '|-fail|p2a: Pichu',
      '|move|p2a: Pichu|Substitute|p2a: Pichu',
      '|-start|p2a: Pichu|Substitute',
      '|-damage|p2a: Pichu|165/219',
      '|turn|2',
      '|move|p1a: Delibird|Present|p2a: Pichu',
      '|move|p2a: Pichu|Present|p1a: Delibird',
      '|-damage|p1a: Delibird|291/293',
      '|turn|3',
      '|move|p1a: Delibird|Present|p2a: Pichu',
      '|-end|p2a: Pichu|Substitute',
      '|move|p2a: Pichu|Present|p1a: Delibird|[miss]',
      '|-miss|p2a: Pichu',
      '|turn|4',
    ]);
  });

  test('Safeguard effect', () => {
    const battle = startBattle([
      QKC, CFZ(5), CFZ_CAN,
      QKC, CFZ_CAN, HIT,
      QKC,
      QKC, CFZ_CAN, NO_CRIT, MIN_DMG, THRASH(2),
      QKC, CFZ_CAN, SLP(5), NO_CRIT, MIN_DMG,
      QKC, QKC,
    ], [
      {species: 'Wobbuffet', evs, moves: ['Safeguard', 'Toxic']},
      {species: 'Ledian', item: 'Berserk Gene', evs, moves: ['Safeguard', 'Rest']},
    ], [
      {species: 'Quagsire', evs, moves: ['Confuse Ray', 'Safeguard']},
      {species: 'Piloswine', evs, moves: ['Thrash', 'Splash']},
    ]);

    battle.p1.pokemon[1].hp = 200;
    let ledian = battle.p1.pokemon[1].hp;

    // Doesn't cure existing status
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p1.sideConditions['safeguard']).toBeDefined();

    // Prevents status
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].status).toBe('');
    expect(battle.p2.sideConditions['safeguard']).toBeDefined();

    // Doesn't prevent Berserk Gene
    battle.makeChoices('switch 2', 'switch 2');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();

    // Fails if already active
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(ledian -= 98);

    // Doesn't prevent Rest
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].status).toBe('slp');
    expect(battle.p1.pokemon[0].hp).toBe(ledian = ledian + 211 - 98);
    expect(battle.p1.sideConditions['safeguard']).toBeUndefined();

    // Prevents Thrash confusion
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();
    expect(battle.p2.sideConditions['safeguard']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Quagsire|Confuse Ray|p1a: Wobbuffet',
      '|-start|p1a: Wobbuffet|confusion',
      '|-activate|p1a: Wobbuffet|confusion',
      '|move|p1a: Wobbuffet|Safeguard|p1a: Wobbuffet',
      '|-sidestart|p1: Player 1|Safeguard',
      '|turn|2',
      '|move|p2a: Quagsire|Safeguard|p2a: Quagsire',
      '|-sidestart|p2: Player 2|Safeguard',
      '|-activate|p1a: Wobbuffet|confusion',
      '|move|p1a: Wobbuffet|Toxic|p2a: Quagsire',
      '|-activate|p2a: Quagsire|move: Safeguard',
      '|turn|3',
      '|switch|p2a: Piloswine|Piloswine, M|403/403',
      '|switch|p1a: Ledian|Ledian, M|200/313',
      '|-enditem|p1a: Ledian|Berserk Gene',
      '|-boost|p1a: Ledian|atk|2|[from] item: Berserk Gene',
      '|-start|p1a: Ledian|confusion',
      '|turn|4',
      '|-activate|p1a: Ledian|confusion',
      '|move|p1a: Ledian|Safeguard|p1a: Ledian',
      '|-fail|p1a: Ledian',
      '|move|p2a: Piloswine|Thrash|p1a: Ledian',
      '|-damage|p1a: Ledian|102/313',
      '|turn|5',
      '|-activate|p1a: Ledian|confusion',
      '|move|p1a: Ledian|Rest|p1a: Ledian',
      '|-status|p1a: Ledian|slp|[from] move: Rest',
      '|-heal|p1a: Ledian|313/313 slp|[silent]',
      '|move|p2a: Piloswine|Thrash|p1a: Ledian',
      '|-damage|p1a: Ledian|215/313 slp',
      '|-sideend|p1: Player 1|Safeguard',
      '|turn|6',
      '|cant|p1a: Ledian|slp',
      '|move|p2a: Piloswine|Splash|p2a: Piloswine',
      '|-nothing',
      '|-fail|p2a: Piloswine',
      '|-sideend|p2: Player 2|Safeguard',
      '|turn|7',
    ]);
  });

  test('PainSplit effect', () => {
    const battle = startBattle([QKC, QKC, QKC, HIT, QKC, HIT, QKC, HIT, QKC], [
      {species: 'Misdreavus', evs, moves: ['Pain Split', 'Counter', 'Seismic Toss']},
    ], [
      {species: 'Noctowl', evs, moves: ['Substitute', 'Pain Split', 'Sand-Attack']},
    ]);

    battle.p2.pokemon[0].hp = 323;

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Does nothing if both Pokémon have the same HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

    // Can hit Ghost-type Pokémon but blocked by Substitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 50);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp += 50);

    // Can't be countered (doesn't set last damage)
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 3', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    // Can miss if accuracy is reduced
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    verify(battle, [
      '|move|p1a: Misdreavus|Pain Split|p2a: Noctowl',
      '|-sethp|p2a: Noctowl|323/403|[from] move: Pain Split|[silent]',
      '|-sethp|p1a: Misdreavus|323/323|[from] move: Pain Split',
      '|move|p2a: Noctowl|Substitute|p2a: Noctowl',
      '|-start|p2a: Noctowl|Substitute',
      '|-damage|p2a: Noctowl|223/403',
      '|turn|2',
      '|move|p1a: Misdreavus|Pain Split|p2a: Noctowl',
      '|-activate|p2a: Noctowl|Substitute|[block] Pain Split',
      '|move|p2a: Noctowl|Pain Split|p1a: Misdreavus',
      '|-sethp|p1a: Misdreavus|273/323|[from] move: Pain Split|[silent]',
      '|-sethp|p2a: Noctowl|273/403|[from] move: Pain Split',
      '|turn|3',
      '|move|p2a: Noctowl|Sand Attack|p1a: Misdreavus',
      '|-unboost|p1a: Misdreavus|accuracy|1',
      '|move|p1a: Misdreavus|Counter|p2a: Noctowl',
      '|turn|4',
      '|move|p1a: Misdreavus|Seismic Toss|p2a: Noctowl',
      '|-end|p2a: Noctowl|Substitute',
      '|move|p2a: Noctowl|Sand Attack|p1a: Misdreavus',
      '|-unboost|p1a: Misdreavus|accuracy|1',
      '|turn|5',
      '|move|p1a: Misdreavus|Pain Split|p2a: Noctowl',
      '|-sethp|p2a: Noctowl|273/403|[from] move: Pain Split|[silent]',
      '|-sethp|p1a: Misdreavus|273/323|[from] move: Pain Split',
      '|move|p2a: Noctowl|Sand Attack|p1a: Misdreavus',
      '|-unboost|p1a: Misdreavus|accuracy|1',
      '|turn|6',
    ]);
  });

  test('Magnitude effect', () => {
    const mag8 = {key: 'data/moves.ts:11248:19', value: ranged(85, 100) - 1};
    const mag5 = {...mag8, value: ranged(15, 100) - 1};
    const battle = startBattle([
      QKC, mag8, NO_CRIT, MIN_DMG, QKC, mag5, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Diglett', evs, moves: ['Magnitude']},
    ], [
      {species: 'Meganium', evs, moves: ['Dig']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 76);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

    verify(battle, [
      '|move|p1a: Diglett|Magnitude|p2a: Meganium',
      '|-activate|p1a: Diglett|move: Magnitude|8',
      '|-resisted|p2a: Meganium',
      '|-damage|p2a: Meganium|329/363',
      '|move|p2a: Meganium|Dig||[still]',
      '|-prepare|p2a: Meganium|Dig',
      '|turn|2',
      '|move|p1a: Diglett|Magnitude|p2a: Meganium',
      '|-activate|p1a: Diglett|move: Magnitude|5',
      '|-resisted|p2a: Meganium',
      '|-damage|p2a: Meganium|307/363',
      '|move|p2a: Meganium|Dig|p1a: Diglett',
      '|-damage|p1a: Diglett|147/223',
      '|turn|3',
    ]);
  });

  test('BatonPass effect', () => {
    const battle = startBattle([
      QKC, QKC, QKC, HIT, CFZ(5), QKC, CFZ_CAN, NO_CRIT, MIN_DMG,
      QKC, CFZ_CAN, HIT, NO_CRIT, MIN_DMG, PROC_SEC, PAR_CAN,
    ], [
      {species: 'Celebi', evs, moves: ['Swords Dance', 'Perish Song', 'Lock-On', 'Baton Pass']},
      {species: 'Lanturn', evs, moves: ['Zap Cannon']},
    ], [
      {species: 'Umbreon', evs, moves: ['Sand-Attack', 'Confuse Ray', 'Pursuit', 'Baton Pass']},
    ]);

    const lanturn = battle.p1.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].boosts.accuracy).toBe(-1);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].boosts.accuracy).toBe(-2);
    expect(battle.p1.pokemon[0].volatiles['perishsong']).toBeDefined();
    expect(battle.p2.pokemon[0].volatiles['perishsong']).toBeDefined();

    // Lock-On should require a roll to hit
    battle.makeChoices('move 3', 'move 2');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].boosts.accuracy).toBe(-2);
    expect(battle.p1.pokemon[0].volatiles['lockon']).toBeDefined();
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p1.pokemon[0].volatiles['perishsong']).toBeDefined();
    expect(battle.p2.pokemon[0].volatiles['perishsong']).toBeDefined();

    battle.makeChoices('move 4', 'move 3');
    battle.makeChoices('switch 2', '');
    expect(battle.p1.pokemon[0].hp).toBe(lanturn - 39);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].boosts.accuracy).toBe(-2);
    // Lock-On should be passed
    // expect(battle.p1.pokemon[0].volatiles['lockon']).toBeDefined();
    expect(battle.p1.pokemon[0].volatiles['lockon']).toBeUndefined();
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();
    expect(battle.p1.pokemon[0].volatiles['perishsong']).toBeDefined();
    expect(battle.p2.pokemon[0].volatiles['perishsong']).toBeDefined();

    battle.makeChoices('move 1', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(0);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Celebi|Swords Dance|p1a: Celebi',
      '|-boost|p1a: Celebi|atk|2',
      '|move|p2a: Umbreon|Sand Attack|p1a: Celebi',
      '|-unboost|p1a: Celebi|accuracy|1',
      '|turn|2',
      '|move|p1a: Celebi|Perish Song|p1a: Celebi',
      '|-start|p1a: Celebi|perish3|[silent]',
      '|-start|p2a: Umbreon|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|move|p2a: Umbreon|Sand Attack|p1a: Celebi',
      '|-unboost|p1a: Celebi|accuracy|1',
      '|-start|p1a: Celebi|perish3',
      '|-start|p2a: Umbreon|perish3',
      '|turn|3',
      '|move|p1a: Celebi|Lock-On|p2a: Umbreon',
      '|-activate|p1a: Celebi|move: Lock-On|[of] p2a: Umbreon',
      '|move|p2a: Umbreon|Confuse Ray|p1a: Celebi',
      '|-start|p1a: Celebi|confusion',
      '|-start|p1a: Celebi|perish2',
      '|-start|p2a: Umbreon|perish2',
      '|turn|4',
      '|-activate|p1a: Celebi|confusion',
      '|move|p1a: Celebi|Baton Pass|p1a: Celebi',
      '|switch|p1a: Lanturn|Lanturn, M|453/453|[from] Baton Pass',
      '|move|p2a: Umbreon|Pursuit|p1a: Lanturn',
      '|-damage|p1a: Lanturn|414/453',
      '|-start|p1a: Lanturn|perish1',
      '|-start|p2a: Umbreon|perish1',
      '|turn|5',
      '|-activate|p1a: Lanturn|confusion',
      '|move|p1a: Lanturn|Zap Cannon|p2a: Umbreon',
      '|-damage|p2a: Umbreon|317/393',
      '|-status|p2a: Umbreon|par',
      '|move|p2a: Umbreon|Baton Pass||[still]',
      '|-fail|p2a: Umbreon',
      '|-start|p1a: Lanturn|perish0',
      '|-start|p2a: Umbreon|perish0',
      '|faint|p1a: Lanturn',
      '|faint|p2a: Umbreon',
      '|win|Player 1',
    ]);
  });

  test('Encore effect', () => {
    const encore = (n: number) =>
      ({key: 'data/mods/gen2/moves.ts:190:17', value: ranged(n - 3, 7 - 3) - 1});

    const battle = startBattle([
      QKC, encore(3), QKC, encore(3), encore(3), QKC, QKC, encore(3), QKC,
      QKC, encore(5), QKC, HIT, DISABLE_DURATION(5), QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Togetic', evs, moves: ['Substitute', 'Encore', 'Splash', 'Disable']},
    ], [
      {species: 'Skiploom', evs, moves: ['Encore']},
      {species: 'Clefable', evs, moves: ['Encore', 'Rest']},
    ]);

    battle.p1.pokemon[0].moveSlots[0].pp = 1;
    battle.p1.pokemon[0].moveSlots[2].pp = 3;

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[1].hp;

    // Fails if the target has not made a move
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 78);

    // Fails if the opponent's move has 0 PP / fails to Encore specific moves
    battle.makeChoices('move 2', 'move 1');

    battle.makeChoices('move 3', 'switch 2');

    // Encore can hit through a Substitute / if last move was before the Encore user switched
    battle.makeChoices('move 2', 'move 1');

    expect(choices(battle, 'p1')).toEqual(['move 3']);

    // Prevents the target from changing moves / fails if the target is already under the effect
    battle.makeChoices('move 3', 'move 1');

    // Ends when the target runs out of PP / Encore can be used against Rest
    battle.makeChoices('move 2', 'move 2');

    expect(choices(battle, 'p1')).toEqual(['move 2', 'move 4']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 2']);

    battle.makeChoices('move 4', 'move 2');

    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1']);

    // Forced to use Struggle until the effects of Disable or Encore have worn off
    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 1);

    verify(battle, [
      '|move|p2a: Skiploom|Encore|p1a: Togetic',
      '|-fail|p1a: Togetic',
      '|move|p1a: Togetic|Substitute|p1a: Togetic',
      '|-start|p1a: Togetic|Substitute',
      '|-damage|p1a: Togetic|235/313',
      '|turn|2',
      '|move|p2a: Skiploom|Encore|p1a: Togetic',
      '|-fail|p1a: Togetic',
      '|move|p1a: Togetic|Encore|p2a: Skiploom',
      '|-fail|p2a: Skiploom',
      '|turn|3',
      '|switch|p2a: Clefable|Clefable, M|393/393',
      '|move|p1a: Togetic|Splash|p1a: Togetic',
      '|-nothing',
      '|-fail|p1a: Togetic',
      '|turn|4',
      '|move|p2a: Clefable|Encore|p1a: Togetic',
      '|-start|p1a: Togetic|Encore',
      '|move|p1a: Togetic|Splash|p1a: Togetic',
      '|-nothing',
      '|-fail|p1a: Togetic',
      '|turn|5',
      '|move|p2a: Clefable|Encore|p1a: Togetic',
      '|-fail|p1a: Togetic',
      '|move|p1a: Togetic|Splash|p1a: Togetic',
      '|-nothing',
      '|-fail|p1a: Togetic',
      '|-end|p1a: Togetic|Encore',
      '|turn|6',
      '|move|p2a: Clefable|Rest|p2a: Clefable',
      '|-fail|p2a: Clefable',
      '|move|p1a: Togetic|Encore|p2a: Clefable',
      '|-start|p2a: Clefable|Encore',
      '|turn|7',
      '|move|p2a: Clefable|Rest|p2a: Clefable',
      '|-fail|p2a: Clefable',
      '|move|p1a: Togetic|Disable|p2a: Clefable',
      '|-start|p2a: Clefable|Disable|Rest',
      '|turn|8',
      '|move|p2a: Clefable|Struggle|p1a: Togetic',
      '|-activate|p1a: Togetic|Substitute|[damage]',
      '|-damage|p2a: Clefable|392/393|[from] Recoil|[of] p1a: Togetic',
      '|move|p1a: Togetic|Encore|p2a: Clefable',
      '|-fail|p2a: Clefable',
      '|turn|9',
    ]);
  });

  test('Pursuit effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC, QKC, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Larvitar', evs, moves: ['Pursuit', 'Splash']},
    ], [
      {species: 'Chinchou', evs, moves: ['Splash']},
      {species: 'Cyndaquil', evs, moves: ['Substitute']},
      {species: 'Sunkern', evs, moves: ['Absorb']},
    ]);

    battle.p2.pokemon[0].hp = 79;
    const chinchou = battle.p2.pokemon[0].hp;
    const cyndaquil = battle.p2.pokemon[1].hp;
    const sunkern = battle.p2.pokemon[2].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(chinchou - 27);

    // Double damage if switching out, but will still switch even if it faints
    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[1].hp).toBe(0);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(cyndaquil - 70);

    // Substitute takes Pursuit damage when switching out
    battle.makeChoices('move 1', 'switch 3');
    expect(battle.p2.pokemon[0].hp).toBe(sunkern);

    verify(battle, [
      '|move|p2a: Chinchou|Splash|p2a: Chinchou',
      '|-nothing',
      '|-fail|p2a: Chinchou',
      '|move|p1a: Larvitar|Pursuit|p2a: Chinchou',
      '|-damage|p2a: Chinchou|52/353',
      '|turn|2',
      '|-activate|p2a: Chinchou|move: Pursuit',
      '|move|p1a: Larvitar|Pursuit|p2a: Chinchou|[from]Pursuit',
      '|-damage|p2a: Chinchou|0 fnt',
      '|faint|p2a: Chinchou',
      '|switch|p2a: Cyndaquil|Cyndaquil, M|281/281',
      '|turn|3',
      '|move|p2a: Cyndaquil|Substitute|p2a: Cyndaquil',
      '|-start|p2a: Cyndaquil|Substitute',
      '|-damage|p2a: Cyndaquil|211/281',
      '|move|p1a: Larvitar|Splash|p1a: Larvitar',
      '|-nothing',
      '|-fail|p1a: Larvitar',
      '|turn|4',
      '|-activate|p2a: Cyndaquil|move: Pursuit',
      '|move|p1a: Larvitar|Pursuit|p2a: Cyndaquil|[from]Pursuit',
      '|-activate|p2a: Cyndaquil|Substitute|[damage]',
      '|switch|p2a: Sunkern|Sunkern, M|263/263',
      '|turn|5',
    ]);
  });

  test('HiddenPower effect', () => {
    const grass69 = {hp: 0, atk: 28, def: 20, spe: 20, spa: 20, spd: 20};
    const ground31 = {hp: 12, atk: 8, def: 6, spe: 6, spa: 8, spd: 8};
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Raikou', evs, ivs: grass69, moves: ['Hidden Power']},
    ], [
      {species: 'Zapdos', evs, ivs: ground31, moves: ['Hidden Power']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 51);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 30);

    verify(battle, [
      '|move|p1a: Raikou|Hidden Power|p2a: Zapdos',
      '|-resisted|p2a: Zapdos',
      '|-damage|p2a: Zapdos|335/365',
      '|move|p2a: Zapdos|Hidden Power|p1a: Raikou',
      '|-supereffective|p1a: Raikou',
      '|-damage|p1a: Raikou|302/353',
      '|turn|2',
    ]);
  });

  test('Sandstorm effect', () => {
    const battle = startBattle([
      QKC, QKC, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, QKC, QKC,
    ], [
      {species: 'Quagsire', evs, moves: ['Sandstorm', 'Splash', 'Surf']},
    ], [
      {species: 'Entei', evs, moves: ['Sunny Day', 'Dig', 'Morning Sun', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Replaces other weather, damages non-resistant types
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);
    expect(battle.field.weather).toBe('sandstorm');

    // Doesn't inflict damage when underground
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);

    battle.makeChoices('move 3', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 53);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 190 - 54);

    // Reduces healing from weather-dependent healing moves
    battle.makeChoices('move 2', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp + 108 - 54);

    // Lasts 5 turns
    battle.makeChoices('move 2', 'move 4');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.field.weather).toBe('');

    verify(battle, [
      '|move|p2a: Entei|Sunny Day|p2a: Entei',
      '|-weather|SunnyDay',
      '|move|p1a: Quagsire|Sandstorm|p1a: Quagsire',
      '|-weather|Sandstorm',
      '|-weather|Sandstorm|[upkeep]',
      '|-damage|p2a: Entei|379/433|[from] Sandstorm',
      '|turn|2',
      '|move|p2a: Entei|Dig||[still]',
      '|-prepare|p2a: Entei|Dig',
      '|move|p1a: Quagsire|Sandstorm|p1a: Quagsire',
      '|-fail|p1a: Quagsire',
      '|-weather|Sandstorm|[upkeep]',
      '|turn|3',
      '|move|p2a: Entei|Dig|p1a: Quagsire',
      '|-damage|p1a: Quagsire|340/393',
      '|move|p1a: Quagsire|Surf|p2a: Entei',
      '|-supereffective|p2a: Entei',
      '|-damage|p2a: Entei|189/433',
      '|-weather|Sandstorm|[upkeep]',
      '|-damage|p2a: Entei|135/433|[from] Sandstorm',
      '|turn|4',
      '|move|p2a: Entei|Morning Sun|p2a: Entei',
      '|-heal|p2a: Entei|243/433',
      '|move|p1a: Quagsire|Splash|p1a: Quagsire',
      '|-nothing',
      '|-fail|p1a: Quagsire',
      '|-weather|Sandstorm|[upkeep]',
      '|-damage|p2a: Entei|189/433|[from] Sandstorm',
      '|turn|5',
      '|move|p2a: Entei|Splash|p2a: Entei',
      '|-nothing',
      '|-fail|p2a: Entei',
      '|move|p1a: Quagsire|Splash|p1a: Quagsire',
      '|-nothing',
      '|-fail|p1a: Quagsire',
      '|-weather|none',
      '|turn|6',
    ]);
  });

  test('SunnyDay effect', () => {
    const no_brn = SECONDARY(ranged(25, 256));
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_brn, QKC, NO_CRIT, MIN_DMG,
      QKC, QKC, QKC, QKC, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Bellossom', evs, moves: ['Sunny Day', 'Splash']},
    ], [
      {species: 'Tyrogue', evs, moves: ['Fire Punch', 'Water Gun', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 93);
    expect(battle.field.weather).toBe('sunnyday');
    expect(battle.field.weatherState.duration).toBe(4);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 4);
    expect(battle.field.weather).toBe('sunnyday');
    expect(battle.field.weatherState.duration).toBe(4);

    for (let i = 0; i < 4; i++) {
      battle.makeChoices('move 2', 'move 3');
      const duration = 3 - i;
      expect(battle.field.weather).toBe(duration ? 'sunnyday' : '');
      expect(battle.field.weatherState.duration).toEqual(duration || undefined);
    }

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 8);

    verify(battle, [
      '|move|p1a: Bellossom|Sunny Day|p1a: Bellossom',
      '|-weather|SunnyDay',
      '|move|p2a: Tyrogue|Fire Punch|p1a: Bellossom',
      '|-supereffective|p1a: Bellossom',
      '|-damage|p1a: Bellossom|260/353',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|2',
      '|move|p1a: Bellossom|Sunny Day|p1a: Bellossom',
      '|-weather|SunnyDay',
      '|move|p2a: Tyrogue|Water Gun|p1a: Bellossom',
      '|-resisted|p1a: Bellossom',
      '|-damage|p1a: Bellossom|256/353',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|3',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|4',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|5',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|6',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|none',
      '|turn|7',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Water Gun|p1a: Bellossom',
      '|-resisted|p1a: Bellossom',
      '|-damage|p1a: Bellossom|248/353',
      '|turn|8',
    ]);
  });

  test('RainDance effect', () => {
    const no_brn = SECONDARY(ranged(25, 256));
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, no_brn, QKC, NO_CRIT, MIN_DMG,
      QKC, QKC, QKC, QKC, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Bellossom', evs, moves: ['Rain Dance', 'Splash']},
    ], [
      {species: 'Tyrogue', evs, moves: ['Fire Punch', 'Water Gun', 'Splash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 30);
    expect(battle.field.weather).toBe('raindance');
    expect(battle.field.weatherState.duration).toBe(4);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);
    expect(battle.field.weather).toBe('raindance');
    expect(battle.field.weatherState.duration).toBe(4);

    for (let i = 0; i < 4; i++) {
      battle.makeChoices('move 2', 'move 3');
      const duration = 3 - i;
      expect(battle.field.weather).toBe(duration ? 'raindance' : '');
      expect(battle.field.weatherState.duration).toEqual(duration || undefined);
    }

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 8);

    verify(battle, [
      '|move|p1a: Bellossom|Rain Dance|p1a: Bellossom',
      '|-weather|RainDance',
      '|move|p2a: Tyrogue|Fire Punch|p1a: Bellossom',
      '|-supereffective|p1a: Bellossom',
      '|-damage|p1a: Bellossom|323/353',
      '|-weather|RainDance|[upkeep]',
      '|turn|2',
      '|move|p1a: Bellossom|Rain Dance|p1a: Bellossom',
      '|-weather|RainDance',
      '|move|p2a: Tyrogue|Water Gun|p1a: Bellossom',
      '|-resisted|p1a: Bellossom',
      '|-damage|p1a: Bellossom|311/353',
      '|-weather|RainDance|[upkeep]',
      '|turn|3',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|RainDance|[upkeep]',
      '|turn|4',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|RainDance|[upkeep]',
      '|turn|5',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|RainDance|[upkeep]',
      '|turn|6',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Splash|p2a: Tyrogue',
      '|-nothing',
      '|-fail|p2a: Tyrogue',
      '|-weather|none',
      '|turn|7',
      '|move|p1a: Bellossom|Splash|p1a: Bellossom',
      '|-nothing',
      '|-fail|p1a: Bellossom',
      '|move|p2a: Tyrogue|Water Gun|p1a: Bellossom',
      '|-resisted|p1a: Bellossom',
      '|-damage|p1a: Bellossom|303/353',
      '|turn|8',
    ]);
  });

  test('Thunder effect', () => {
    const proc = SECONDARY(ranged(76, 256) - 1);
    const acc70 = {...HIT, value: ranged(Math.floor(70 * 255 / 100), 256) - 1};
    const acc50 = {...MISS, value: ranged(Math.floor(50 * 255 / 100), 256) - 1};
    const battle = startBattle([
      QKC, acc70, NO_CRIT, MIN_DMG, proc, PAR_CAN,
      QKC, NO_CRIT, MIN_DMG, proc, PAR_CAN,
      QKC, PAR_CANT, QKC, QKC, acc50, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Remoraid', evs, moves: ['Thunder', 'Sunny Day']},
    ], [
      {species: 'Slugma', evs, moves: ['Rain Dance', 'Dig']},
      {species: 'Zapdos', evs, moves: ['Fly']},
    ]);

    let slugma = battle.p2.pokemon[0].hp;
    let zapdos = battle.p2.pokemon[1].hp;

    // 30% paralysis chance
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(slugma -= 111);
    expect(battle.p2.pokemon[0].status).toBe('par');
    expect(battle.field.weather).toBe('raindance');

    // Always hits while raining
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(slugma -= 111);
    expect(battle.field.weather).toBe('raindance');

    // ...unless the Pokémon is underground
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(slugma);

    battle.makeChoices('move 2', 'switch 2');
    expect(battle.field.weather).toBe('sunnyday');

    // Sunny Day reduces accuracy / can paralyze Electric-type Pokémon and hit during Fly
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(zapdos -= 72);
    expect(battle.p2.pokemon[0].status).toBe('par');

    verify(battle, [
      '|move|p1a: Remoraid|Thunder|p2a: Slugma',
      '|-damage|p2a: Slugma|172/283',
      '|-status|p2a: Slugma|par',
      '|move|p2a: Slugma|Rain Dance|p2a: Slugma',
      '|-weather|RainDance',
      '|-weather|RainDance|[upkeep]',
      '|turn|2',
      '|move|p1a: Remoraid|Thunder|p2a: Slugma',
      '|-damage|p2a: Slugma|61/283 par',
      '|move|p2a: Slugma|Dig||[still]',
      '|-prepare|p2a: Slugma|Dig',
      '|-weather|RainDance|[upkeep]',
      '|turn|3',
      '|move|p1a: Remoraid|Thunder|p2a: Slugma|[miss]',
      '|-miss|p1a: Remoraid',
      '|cant|p2a: Slugma|par',
      '|-weather|RainDance|[upkeep]',
      '|turn|4',
      '|switch|p2a: Zapdos|Zapdos|383/383',
      '|move|p1a: Remoraid|Sunny Day|p1a: Remoraid',
      '|-weather|SunnyDay',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|5',
      '|move|p2a: Zapdos|Fly||[still]',
      '|-prepare|p2a: Zapdos|Fly',
      '|move|p1a: Remoraid|Thunder|p2a: Zapdos',
      '|-damage|p2a: Zapdos|311/383',
      '|-status|p2a: Zapdos|par',
      '|-weather|SunnyDay|[upkeep]',
      '|turn|6',
    ]);
  });

  test('PsychUp effect', () => {
    const battle = startBattle([QKC, QKC, QKC, QKC], [
      {species: 'Stantler', evs, moves: ['Psych Up', 'Splash']},
    ], [
      {species: 'Chikorita', evs, moves: ['Swords Dance', 'Minimize', 'Protect']},
    ]);

    // Fails if no stat changes to copy
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);
    expect(battle.p1.pokemon[0].boosts.evasion).toBe(0);
    expect(battle.p2.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(0);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);
    expect(battle.p1.pokemon[0].boosts.evasion).toBe(0);
    expect(battle.p2.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(1);

    // Bypasses accuracy and protect
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].boosts.evasion).toBe(1);
    expect(battle.p2.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.evasion).toBe(1);

    verify(battle, [
      '|move|p1a: Stantler|Psych Up|p2a: Chikorita',
      '|-copyboost|p1a: Stantler|p2a: Chikorita|[from] move: Psych Up',
      '|move|p2a: Chikorita|Swords Dance|p2a: Chikorita',
      '|-boost|p2a: Chikorita|atk|2',
      '|turn|2',
      '|move|p1a: Stantler|Splash|p1a: Stantler',
      '|-nothing',
      '|-fail|p1a: Stantler',
      '|move|p2a: Chikorita|Minimize|p2a: Chikorita',
      '|-boost|p2a: Chikorita|evasion|1',
      '|turn|3',
      '|move|p2a: Chikorita|Protect|p2a: Chikorita',
      '|-singleturn|p2a: Chikorita|Protect',
      '|move|p1a: Stantler|Psych Up|p2a: Chikorita',
      '|-copyboost|p1a: Stantler|p2a: Chikorita|[from] move: Psych Up',
      '|turn|4',
    ]);
  });

  test('FutureSight effect', () => {
    const hit = {key: 'data/mods/gen4/scripts.ts:149:43', value: 0xE6666667 - 1};
    const miss = {...hit, value: hit.value + 1};
    const band = {key: 'data/mods/gen2/items.ts:60:13', value: ranged(30, 256) - 1};
    const battle = startBattle([
      QKC, MAX_DMG, QKC, QKC, miss, QKC, MIN_DMG, QKC,
      QKC, hit, band, QKC, MAX_DMG, QKC, QKC, hit, QKC,
    ], [
      {species: 'Girafarig', evs, moves: ['Future Sight']},
      {species: 'Magcargo', evs, moves: ['Fire Blast', 'Future Sight', 'Splash']},
    ], [
      {species: 'Blissey', evs, moves: ['Splash', 'Substitute']},
      {species: 'Houndour', level: 5, item: 'Focus Band', evs, moves: ['Protect']},
    ]);

    let blissey = battle.p2.pokemon[0].hp;
    const houndour = battle.p2.pokemon[1].hp;

    // Schedules an attack for 2 turns in the future
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    // Fails if already in effect
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    // Can miss (should show up on 3rd turn as having "failed")
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    battle.makeChoices('move 1', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(houndour);

    // Uses original user's stats vs. original targets, can hit Dark, respects Focus Band
    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(1);

    battle.makeChoices('move 2', 'switch 2');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(blissey -= 178);

    // Substitute takes damage from Future Sight
    battle.makeChoices('move 3', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(blissey);

    verify(battle, [
      '|move|p1a: Girafarig|Future Sight|p2a: Blissey',
      '|-start|p1a: Girafarig|Future Sight',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|2',
      '|move|p1a: Girafarig|Future Sight|p2a: Blissey',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|3',
      '|move|p1a: Girafarig|Future Sight|p2a: Blissey',
      '|move|p2a: Blissey|Splash|p2a: Blissey|[miss]',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|-end|p2a: Blissey|move: Future Sight',
      '|-miss|p1a: Girafarig|p2a: Blissey',
      '|turn|4',
      '|move|p1a: Girafarig|Future Sight|p2a: Blissey',
      '|-start|p1a: Girafarig|Future Sight',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|turn|5',
      '|switch|p2a: Houndour|Houndour, L5, M|24/24',
      '|move|p1a: Girafarig|Future Sight|p2a: Houndour',
      '|turn|6',
      '|switch|p1a: Magcargo|Magcargo, M|303/303',
      '|move|p2a: Houndour|Protect|p2a: Houndour',
      '|-fail|p2a: Houndour',
      '|-end|p2a: Houndour|move: Future Sight',
      '|-activate|p2a: Houndour|item: Focus Band',
      '|-damage|p2a: Houndour|1/24',
      '|turn|7',
      '|switch|p2a: Blissey|Blissey, F|713/713',
      '|move|p1a: Magcargo|Future Sight|p2a: Blissey',
      '|-start|p1a: Magcargo|Future Sight',
      '|turn|8',
      '|move|p2a: Blissey|Substitute|p2a: Blissey',
      '|-start|p2a: Blissey|Substitute',
      '|-damage|p2a: Blissey|535/713',
      '|move|p1a: Magcargo|Splash|p1a: Magcargo',
      '|-nothing',
      '|-fail|p1a: Magcargo',
      '|turn|9',
      '|move|p2a: Blissey|Splash|p2a: Blissey',
      '|-nothing',
      '|-fail|p2a: Blissey',
      '|move|p1a: Magcargo|Splash|p1a: Magcargo',
      '|-nothing',
      '|-fail|p1a: Magcargo',
      '|-end|p2a: Blissey|move: Future Sight',
      '|-activate|p2a: Blissey|Substitute|[damage]',
      '|turn|10',
    ]);
  });

  test('BeatUp effect', () => {
    const band = {key: 'data/mods/gen2/items.ts:60:13', value: ranged(30, 256) - 1};
    const no_band = {...band, value: band.value + 1};
    const kings = SECONDARY(band.value);
    const no_kings = SECONDARY(no_band.value);
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, no_band, NO_CRIT, MIN_DMG, no_band, no_kings,
      QKC, QKC, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, band, kings, QKC,
      CRIT, MAX_DMG, band, NO_CRIT, MIN_DMG, no_band,
    ], [
      {species: 'Sneasel', item: 'Kings Rock', evs, moves: ['Swords Dance', 'Beat Up']},
      {species: 'Politoed', evs, moves: ['Rain Dance']},
      {species: 'Elekid', evs, moves: ['Thundershock']},
      {species: 'Mewtwo', evs, moves: ['Psychic']},
    ], [
      {
        species: 'Gengar',
        level: 20,
        item: 'Focus Band',
        evs,
        moves: ['Withdraw', 'Counter', 'Substitute']},
    ]);

    battle.p1.pokemon[1].hp = 0;
    battle.p1.pokemon[1].fainted = true;
    battle.p1.pokemon[2].status = 'slp' as ID;

    const p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);

    // Ignores boosts / cannot be countered
    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 12 - 14);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(4);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 18);

    // Should end after breaking a Substitute
    battle.makeChoices('move 2', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 14);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);

    // Focus Band on the first hit can prevent subsequent hits from KOing
    battle.makeChoices('move 2', 'move 1');
    // expect(battle.p2.pokemon[0].hp).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(0);

    verify(battle, [
      '|move|p1a: Sneasel|Swords Dance|p1a: Sneasel',
      '|-boost|p1a: Sneasel|atk|2',
      '|move|p2a: Gengar|Withdraw|p2a: Gengar',
      '|-boost|p2a: Gengar|def|1',
      '|turn|2',
      '|move|p1a: Sneasel|Beat Up|p2a: Gengar',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Sneasel',
      '|-damage|p2a: Gengar|60/72',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Mewtwo',
      '|-damage|p2a: Gengar|46/72',
      '|-hitcount|p2a: Gengar|2',
      '|move|p2a: Gengar|Counter|p1a: Sneasel',
      '|-fail|p1a: Sneasel',
      '|turn|3',
      '|move|p1a: Sneasel|Swords Dance|p1a: Sneasel',
      '|-boost|p1a: Sneasel|atk|2',
      '|move|p2a: Gengar|Substitute|p2a: Gengar',
      '|-start|p2a: Gengar|Substitute',
      '|-damage|p2a: Gengar|28/72',
      '|turn|4',
      '|move|p1a: Sneasel|Beat Up|p2a: Gengar',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Sneasel',
      '|-crit|p2a: Gengar',
      '|-end|p2a: Gengar|Substitute',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Mewtwo',
      '|-damage|p2a: Gengar|14/72',
      '|-hitcount|p2a: Gengar|2',
      '|cant|p2a: Gengar|flinch',
      '|turn|5',
      '|move|p1a: Sneasel|Beat Up|p2a: Gengar',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Sneasel',
      '|-crit|p2a: Gengar',
      '|-activate|p2a: Gengar|item: Focus Band',
      '|-damage|p2a: Gengar|1/72',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Mewtwo',
      '|-damage|p2a: Gengar|0 fnt',
      '|-hitcount|p2a: Gengar|2',
      '|faint|p2a: Gengar',
      '|win|Player 1',
    ]);
  });

  // Pokémon Showdown Bugs

  // TODO

  // Glitches

  test('Spikes 0 HP glitch', () => {
    const battle = startBattle([QKC, QKC, QKC, QKC], [
      {species: 'Misdreavus', evs, moves: ['Perish Song']},
      {species: 'Weezing', evs, moves: ['Pain Split']},
      {species: 'Furret', evs, moves: ['Slam']},
    ], [
      {species: 'Forretress', evs, moves: ['Spikes']},
      {species: 'Unown', evs, moves: ['Splash']},
    ]);

    battle.p1.pokemon[1].hp = 1;

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'switch 2');
    battle.makeChoices('switch 2', '');
    expect(battle.p1.pokemon[0].hp).toBe(0);

    // expect(choices(battle, 'p1')).toEqual(['switch 3', 'move 1']);
    expect(choices(battle, 'p1')).toEqual(['switch 3']);

    // battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p1a: Misdreavus|Perish Song|p1a: Misdreavus',
      '|-start|p1a: Misdreavus|perish3|[silent]',
      '|-start|p2a: Forretress|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|move|p2a: Forretress|Spikes|p1a: Misdreavus',
      '|-sidestart|p1: Player 1|Spikes',
      '|-start|p1a: Misdreavus|perish3',
      '|-start|p2a: Forretress|perish3',
      '|turn|2',
      '|move|p1a: Misdreavus|Perish Song|p1a: Misdreavus',
      '|-fail|p1a: Misdreavus',
      '|move|p2a: Forretress|Spikes|p1a: Misdreavus',
      '|-fail|p1a: Misdreavus',
      '|-start|p1a: Misdreavus|perish2',
      '|-start|p2a: Forretress|perish2',
      '|turn|3',
      '|move|p1a: Misdreavus|Perish Song|p1a: Misdreavus',
      '|-fail|p1a: Misdreavus',
      '|move|p2a: Forretress|Spikes|p1a: Misdreavus',
      '|-fail|p1a: Misdreavus',
      '|-start|p1a: Misdreavus|perish1',
      '|-start|p2a: Forretress|perish1',
      '|turn|4',
      '|switch|p2a: Unown|Unown|299/299',
      '|move|p1a: Misdreavus|Perish Song|p1a: Misdreavus',
      '|-start|p2a: Unown|perish3|[silent]',
      '|-fieldactivate|move: Perish Song',
      '|-start|p1a: Misdreavus|perish0',
      '|-start|p2a: Unown|perish3',
      '|faint|p1a: Misdreavus',
      '|switch|p1a: Weezing|Weezing, M|1/333',
      '|-damage|p1a: Weezing|0 fnt|[from] Spikes',
      '|faint|p1a: Weezing',
    ]);
  });

  test('Thick Club wrap around glitch', () => {
    const battle = startBattle([QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Marowak', item: 'Thick Club', evs, moves: ['Swords Dance', 'Earthquake']},
    ], [
      {species: 'Ursaring', level: 44, evs, moves: ['Splash']},
    ]);
    const p2hp = battle.p2.pokemon[0].hp;

    expect(battle.p1.pokemon[0].getStat('atk')).toBe(516);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].getStat('atk')).toBe(1032);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 10);

    verify(battle, [
      '|move|p1a: Marowak|Swords Dance|p1a: Marowak',
      '|-boost|p1a: Marowak|atk|2',
      '|move|p2a: Ursaring|Splash|p2a: Ursaring',
      '|-nothing',
      '|-fail|p2a: Ursaring',
      '|turn|2',
      '|move|p1a: Marowak|Earthquake|p2a: Ursaring',
      '|-damage|p2a: Ursaring|164/174',
      '|move|p2a: Ursaring|Splash|p2a: Ursaring',
      '|-nothing',
      '|-fail|p2a: Ursaring',
      '|turn|3',
    ]);
  });

  test('Metal Powder increased damage glitch', () => {
    const battle = startBattle([
      QKC, QKC, TIE(1), QKC, TIE(1), NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Ditto', item: 'Metal Powder', evs, moves: ['Transform']},
    ], [
      {species: 'Steelix', evs, moves: ['Harden', 'Strength']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    expect(battle.p2.pokemon[0].getStat('def')).toBe(498);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].getStat('def')).toBe(747);
    expect(battle.p2.pokemon[0].boosts.def).toBe(1);
    expect(battle.p2.pokemon[0].getStat('def')).toBe(747);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].boosts.def).toBe(1);
    expect(battle.p1.pokemon[0].getStat('def')).toBe(1120);
    expect(battle.p2.pokemon[0].boosts.def).toBe(2);
    expect(battle.p2.pokemon[0].getStat('def')).toBe(996);

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 79);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 8);

    verify(battle, [
      '|move|p1a: Ditto|Transform|p2a: Steelix',
      '|-transform|p1a: Ditto|p2a: Steelix',
      '|move|p2a: Steelix|Harden|p2a: Steelix',
      '|-boost|p2a: Steelix|def|1',
      '|turn|2',
      '|move|p1a: Ditto|Harden|p1a: Ditto',
      '|-boost|p1a: Ditto|def|1',
      '|move|p2a: Steelix|Harden|p2a: Steelix',
      '|-boost|p2a: Steelix|def|1',
      '|turn|3',
      '|move|p1a: Ditto|Strength|p2a: Steelix',
      '|-resisted|p2a: Steelix',
      '|-damage|p2a: Steelix|345/353',
      '|move|p2a: Steelix|Strength|p1a: Ditto',
      '|-resisted|p1a: Ditto',
      '|-damage|p1a: Ditto|220/299',
      '|turn|4',
    ]);
  });

  test('Reflect / Light Screen wrap around glitch', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Octillery', evs, moves: ['Water Gun']},
    ], [
      {species: 'Jumpluff', evs, moves: ['Amnesia', 'Light Screen']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 12);
    expect(battle.p2.pokemon[0].boosts.spd).toBe(2);
    expect(battle.p2.pokemon[0].getStat('spd')).toBe(536);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 137);
    expect(battle.p2.pokemon[0].getStat('spd')).toBe(1072);

    verify(battle, [
      '|move|p2a: Jumpluff|Amnesia|p2a: Jumpluff',
      '|-boost|p2a: Jumpluff|spd|2',
      '|move|p1a: Octillery|Water Gun|p2a: Jumpluff',
      '|-resisted|p2a: Jumpluff',
      '|-damage|p2a: Jumpluff|341/353',
      '|turn|2',
      '|move|p2a: Jumpluff|Light Screen|p2a: Jumpluff',
      '|-sidestart|p2: Player 2|move: Light Screen',
      '|move|p1a: Octillery|Water Gun|p2a: Jumpluff',
      '|-resisted|p2a: Jumpluff',
      '|-damage|p2a: Jumpluff|204/353',
      '|turn|3',
    ]);
  });

  test('Secondary chance 1/256 glitch', () => {
    const no_proc = {...PROC_SEC, value: MAX};
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, no_proc, QKC], [
      {species: 'Abra', level: 10, evs, moves: ['Thief']},
    ], [
      {species: 'Snubbull', item: 'Leftovers', level: 10, evs, moves: ['Splash']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 7 + 2);

    verify(battle, [
      '|move|p1a: Abra|Thief|p2a: Snubbull',
      '|-damage|p2a: Snubbull|34/41',
      '|move|p2a: Snubbull|Splash|p2a: Snubbull',
      '|-nothing',
      '|-fail|p2a: Snubbull',
      '|-heal|p2a: Snubbull|36/41|[from] item: Leftovers',
      '|turn|2',
    ]);
  });

  test('Belly Drum failure glitch', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Poliwag', level: 6, evs, moves: ['Strength', 'Belly Drum']},
    ], [
      {species: 'Magnemite', level: 16, evs, moves: ['Splash']},
    ]);

    battle.p1.pokemon[0].hp = 7;

    const p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 2);

    verify(battle, [
      '|move|p2a: Magnemite|Splash|p2a: Magnemite',
      '|-nothing',
      '|-fail|p2a: Magnemite',
      '|move|p1a: Poliwag|Strength|p2a: Magnemite',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|47/48',
      '|turn|2',
      '|move|p2a: Magnemite|Splash|p2a: Magnemite',
      '|-nothing',
      '|-fail|p2a: Magnemite',
      '|move|p1a: Poliwag|Belly Drum|p1a: Poliwag',
      '|-boost|p1a: Poliwag|atk|2|[silent]',
      '|-fail|p1a: Poliwag',
      '|turn|3',
      '|move|p2a: Magnemite|Splash|p2a: Magnemite',
      '|-nothing',
      '|-fail|p2a: Magnemite',
      '|move|p1a: Poliwag|Strength|p2a: Magnemite',
      '|-resisted|p2a: Magnemite',
      '|-damage|p2a: Magnemite|45/48',
      '|turn|4',
    ]);
  });

  test('Berserk Gene confusion duration glitch', () => {
    const battle = startBattle([QKC, HIT, CFZ(3), CFZ_CANT, QKC, QKC], [
      {species: 'Yanma', evs, moves: ['Supersonic', 'Splash']},
    ], [
      {species: 'Dunsparce', evs, moves: ['Hyper Beam']},
      {species: 'Corsola', item: 'Berserk Gene', evs, moves: ['Surf']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 35);
    expect(battle.p2.pokemon[0].volatiles['confusion'].time).toBe(2);

    battle.makeChoices('move 2', 'switch 2');
    // expect(battle.p2.pokemon[0].volatiles['confusion'].time).toBe(2);
    expect(battle.p2.pokemon[0].volatiles['confusion'].time).toBe(256);

    verify(battle, [
      '|move|p1a: Yanma|Supersonic|p2a: Dunsparce',
      '|-start|p2a: Dunsparce|confusion',
      '|-activate|p2a: Dunsparce|confusion',
      '|-damage|p2a: Dunsparce|368/403|[from] confusion',
      '|turn|2',
      '|switch|p2a: Corsola|Corsola, M|313/313',
      '|-enditem|p2a: Corsola|Berserk Gene',
      '|-boost|p2a: Corsola|atk|2|[from] item: Berserk Gene',
      '|-start|p2a: Corsola|confusion',
      '|move|p1a: Yanma|Splash|p1a: Yanma',
      '|-nothing',
      '|-fail|p1a: Yanma',
      '|turn|3',
    ]);
  });

  test('Confusion self-hit damage glitch', () => {
    const battle = startBattle([QKC, CFZ(5), CFZ_CANT, QKC, CFZ_CANT, QKC, CFZ_CANT, QKC], [
      {species: 'Crobat', evs, moves: ['Confuse Ray']},
    ], [
      {species: 'Golem', item: 'Poison Barb', evs, moves: ['Rollout', 'Toxic', 'Self-Destruct']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 31);

    battle.makeChoices('move 1', 'move 2');
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 34);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 31);

    battle.makeChoices('move 1', 'move 3');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 62);

    verify(battle, [
      '|move|p1a: Crobat|Confuse Ray|p2a: Golem',
      '|-start|p2a: Golem|confusion',
      '|-activate|p2a: Golem|confusion',
      '|-damage|p2a: Golem|332/363|[from] confusion',
      '|turn|2',
      '|move|p1a: Crobat|Confuse Ray|p2a: Golem',
      '|-fail|p2a: Golem',
      '|-activate|p2a: Golem|confusion',
      '|-damage|p2a: Golem|301/363|[from] confusion',
      '|turn|3',
      '|move|p1a: Crobat|Confuse Ray|p2a: Golem',
      '|-fail|p2a: Golem',
      '|-activate|p2a: Golem|confusion',
      '|-damage|p2a: Golem|239/363|[from] confusion',
      '|turn|4',
    ]);
  });

  test('Defense lowering after breaking Substitute glitch', () => {
    const battle = startBattle([
      QKC, QKC, HIT, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Krabby', level: 20, evs, moves: ['Substitute']},
    ], [
      {species: 'Poliwrath', evs, moves: ['Splash', 'Dynamic Punch', 'Rock Smash']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 15);

    // Usually moves with secondary chances do not trigger when breaking a Subtitute
    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 15);

    // DefenseDownChance moves *should* still have a chance of triggering
    battle.makeChoices('move 1', 'move 3');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 15);
    // expect(battle.p1.pokemon[0].boosts.def).toBe(-1);
    expect(battle.p1.pokemon[0].boosts.def).toBe(0);

    verify(battle, [
      '|move|p2a: Poliwrath|Splash|p2a: Poliwrath',
      '|-nothing',
      '|-fail|p2a: Poliwrath',
      '|move|p1a: Krabby|Substitute|p1a: Krabby',
      '|-start|p1a: Krabby|Substitute',
      '|-damage|p1a: Krabby|45/60',
      '|turn|2',
      '|move|p2a: Poliwrath|Dynamic Punch|p1a: Krabby',
      '|-end|p1a: Krabby|Substitute',
      '|move|p1a: Krabby|Substitute|p1a: Krabby',
      '|-start|p1a: Krabby|Substitute',
      '|-damage|p1a: Krabby|30/60',
      '|turn|3',
      '|move|p2a: Poliwrath|Rock Smash|p1a: Krabby',
      '|-end|p1a: Krabby|Substitute',
      '|move|p1a: Krabby|Substitute|p1a: Krabby',
      '|-start|p1a: Krabby|Substitute',
      '|-damage|p1a: Krabby|15/60',
      '|turn|4',
    ]);
  });

  test('PP Up + Disable freeze', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, HIT, DISABLE_DURATION(5),
      QKC, NO_CRIT, MIN_DMG, HIT, QKC,
    ], [
      {species: 'Nidoking', evs, moves: ['Earthquake', 'Thunder', 'Fire Blast', 'Shadow Ball']},
    ], [
      {species: 'Drowzee', evs, moves: ['Disable']},
    ]);

    battle.p1.pokemon[0].moveSlots[1].pp = 0;
    battle.p1.pokemon[0].moveSlots[2].pp = 0;
    battle.p1.pokemon[0].moveSlots[3].pp = 0;

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 161);

    // Game should freeze here
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);

    verify(battle, [
      '|move|p1a: Nidoking|Earthquake|p2a: Drowzee',
      '|-damage|p2a: Drowzee|162/323',
      '|move|p2a: Drowzee|Disable|p1a: Nidoking',
      '|-start|p1a: Nidoking|Disable|Earthquake',
      '|turn|2',
      '|move|p1a: Nidoking|Struggle|p2a: Drowzee',
      '|-damage|p2a: Drowzee|108/323',
      '|-damage|p1a: Nidoking|352/365|[from] Recoil|[of] p2a: Drowzee',
      '|move|p2a: Drowzee|Disable|p1a: Nidoking',
      '|-fail|p1a: Nidoking',
      '|turn|3',
    ]);
  });

  test('Lock-On / Mind Reader oversight', () => {
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC, QKC,
    ], [
      {species: 'Hitmontop', evs, moves: ['Lock-On', 'Strength', 'Attract']},
    ], [
      {species: 'Miltank', evs, moves: ['Milk Drink', 'Dig']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].volatiles['lockon']).toBeDefined();

    battle.makeChoices('move 2', 'move 2');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 54);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 39);
    expect(battle.p1.pokemon[0].volatiles['lockon']).toBeDefined();

    battle.makeChoices('move 3', 'move 2');
    expect(battle.p2.pokemon[0].volatiles['attract']).toBeUndefined();

    verify(battle, [
      '|move|p2a: Miltank|Milk Drink|p2a: Miltank',
      '|-fail|p2a: Miltank',
      '|move|p1a: Hitmontop|Lock-On|p2a: Miltank',
      '|-activate|p1a: Hitmontop|move: Lock-On|[of] p2a: Miltank',
      '|turn|2',
      '|move|p2a: Miltank|Dig||[still]',
      '|-prepare|p2a: Miltank|Dig',
      '|move|p1a: Hitmontop|Strength|p2a: Miltank',
      '|-damage|p2a: Miltank|339/393',
      '|turn|3',
      '|move|p2a: Miltank|Dig|p1a: Hitmontop',
      '|-damage|p1a: Hitmontop|264/303',
      '|move|p1a: Hitmontop|Lock-On|p2a: Miltank',
      '|-activate|p1a: Hitmontop|move: Lock-On|[of] p2a: Miltank',
      '|turn|4',
      '|move|p2a: Miltank|Dig||[still]',
      '|-prepare|p2a: Miltank|Dig',
      '|move|p1a: Hitmontop|Attract|p2a: Miltank|[miss]',
      '|-miss|p1a: Hitmontop',
      '|turn|5',
    ]);
  });

  test('Beat Up desync', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, MISS, QKC,
    ], [
      {species: 'Typhlosion', evs, moves: ['Flame Wheel']},
      {species: 'Sneasel', evs, moves: ['Beat Up']},
      {species: 'Lugia', evs, moves: ['Aeroblast']},
    ], [
      {species: 'Blissey', evs, moves: ['Egg Bomb']},
    ]);

    const p1hp = battle.p1.pokemon[1].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    // Lugia's HP is Sneasel's position in the party mod 256
    battle.p1.pokemon[2].status = 'frz' as ID;
    battle.p1.pokemon[2].hp = 1;

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp - 62);

    // Should execute Typhlosion's hit, Sneasel's hit and then desync on Lugia's
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 68 - 61);

    verify(battle, [
      '|switch|p1a: Sneasel|Sneasel, M|313/313',
      '|move|p2a: Blissey|Egg Bomb|p1a: Sneasel',
      '|-damage|p1a: Sneasel|251/313',
      '|turn|2',
      '|move|p1a: Sneasel|Beat Up|p2a: Blissey',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Sneasel',
      '|-damage|p2a: Blissey|645/713',
      '|-activate|p1a: Sneasel|move: Beat Up|[of] Typhlosion',
      '|-damage|p2a: Blissey|584/713',
      '|-hitcount|p2a: Blissey|2',
      '|move|p2a: Blissey|Egg Bomb|p1a: Sneasel|[miss]',
      '|-miss|p2a: Blissey',
      '|turn|3',
    ]);
  });

  test('Beat Up Kings Rock failure glitch', () => {
    const proc = SECONDARY(ranged(30, 256) - 1);
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, proc, QKC], [
      {species: 'Houndoom', item: 'Kings Rock', evs, moves: ['Beat Up']},
    ], [
      {species: 'Skiploom', evs, moves: ['Return']},
    ]);
    const p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    // Beat Up can fail with no party but Kings Rock can still trigger
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp);
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 14);

    verify(battle, [
      '|move|p1a: Houndoom|Beat Up|p2a: Skiploom',
      '|-activate|p1a: Houndoom|move: Beat Up|[of] Houndoom',
      '|-damage|p2a: Skiploom|299/313',
      '|-hitcount|p2a: Skiploom|1',
      '|cant|p2a: Skiploom|flinch',
      '|turn|2',
    ]);
  });

  test('Return/Frustration 0 damage glitch', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC, QKC,
    ], [
      {species: 'Granbull', happiness: 255, evs, moves: ['Return', 'Frustration']},
    ], [
      {species: 'Granbull', happiness: 0, evs: slow, moves: ['Return', 'Frustration']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp -= 150);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp -= 150);

    battle.makeChoices('move 2', 'move 1');
    expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
    expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

    verify(battle, [
      '|move|p1a: Granbull|Return|p2a: Granbull',
      '|-damage|p2a: Granbull|233/383',
      '|move|p2a: Granbull|Frustration|p1a: Granbull',
      '|-damage|p1a: Granbull|233/383',
      '|turn|2',
      '|move|p1a: Granbull|Frustration|p2a: Granbull',
      '|move|p2a: Granbull|Return|p1a: Granbull',
      '|turn|3',
    ]);
  });

  test('Stat increase post KO glitch', () => {
    const battle = startBattle([QKC, HIT, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Skarmory', evs, moves: ['Metal Claw']},
    ], [
      {species: 'Sentret', level: 5, evs, moves: ['Tackle']},
      {species: 'Typhlosion', evs, moves: ['Flame Wheel']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('', 'switch 2');

    expect(battle.p1.pokemon[0].boosts.atk).toBe(0);

    verify(battle, [
      '|move|p1a: Skarmory|Metal Claw|p2a: Sentret',
      '|-damage|p2a: Sentret|0 fnt',
      '|faint|p2a: Sentret',
      '|switch|p2a: Typhlosion|Typhlosion, M|359/359',
      '|turn|2',
    ]);
  });
});
