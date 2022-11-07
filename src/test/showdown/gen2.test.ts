import {Battle, Dex, PRNG} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {MIN, MAX, ROLLS, ranged, formatFor, createStartBattle, FixedRNG, verify} from './helpers';
import * as gen2 from '../benchmark/gen2';

const gens = new Generations(Dex as any);
const gen = gens.get(2);
const choices = gen2.Choices.sim;
const startBattle = createStartBattle(gen);

const {HIT, MISS, CRIT, NO_CRIT, MIN_DMG, MAX_DMG} = ROLLS.basic;
const {SS_MOD, SS_RES, SS_RUN, SS_EACH, INS, GLM} = ROLLS.nops;

const QKC = {key: ['Battle.randomChance', 'Battle.nextTurn'], value: MIN};
const QKCs = (n: number) => Array(n).fill(QKC);
const TIE = (n: 1 | 2) =>
  ({key: ['Battle.speedSort', 'BattleQueue.sort'], value: ranged(n, 2) - 1});
const SLP = (n: number) =>
  ({key: ['Battle.random', 'Pokemon.setStatus'], value: ranged(n, 8 - 1)});
const DISABLE_DURATION = (n: number) =>
  ({key: ['Battle.onStart', 'Pokemon.addVolatile'], value: ranged(n, 9 - 1) - 1});
const DISABLE_MOVE = (m: number, n = 4) =>
  ({key: ['Battle.onStart', 'Pokemon.addVolatile'], value: ranged(m, n) - 1});
const MIMIC = (m: number, n = 4) =>
  ({key: ['Battle.sample', 'Battle.singleEvent'], value: ranged(m, n) - 1});
const BIDE = (n: 2 | 3) =>
  ({key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: ranged(n - 2, 5 - 3)});
const NO_PAR = {key: HIT.key, value: MAX};
const PAR_CANT = {key: 'Battle.onBeforeMove', value: ranged(63, 256) - 1};
const PAR_CAN = {key: 'Battle.onBeforeMove', value: PAR_CANT.value + 1};
const FRZ = {key: HIT.key, value: ranged(26, 256) - 1};
const CFZ = (n: number) =>
  ({key: ['Battle.onStart', 'Pokemon.addVolatile'], value: ranged(n - 1, 6 - 2) - 1});
const CFZ_CAN = {key: 'Battle.onBeforeMove', value: ranged(128, 256) - 1};
const CFZ_CANT = {key: 'Battle.onBeforeMove', value: CFZ_CAN.value + 1};
const THRASH = (n: 3 | 4) =>
  ({key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: ranged(n - 2, 5 - 3) - 1});
const MIN_WRAP = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MIN};
const MAX_WRAP = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MAX};
const REWRAP = {key: ['Battle.sample', 'BattleActions.runMove'], value: MIN};
const MOVES: string[] = Array.from(gen.moves)
  .sort((a, b) => a.num - b.num)
  .map(m => m.name)
  .filter(m => !['Struggle', 'Metronome'].includes(m));
const METRONOME = (move: string) => ({
  key: ['Battle.sample', 'Battle.singleEvent'],
  value: ranged(MOVES.indexOf(move) + 1, MOVES.length) - 1,
});

const evs = {hp: 255, atk: 255, def: 255, spa: 255, spd: 255, spe: 255};

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
        INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC,
        TIE(1),
        SS_EACH, SS_EACH, HIT, NO_CRIT, MIN_DMG,
        SS_EACH, HIT, NO_CRIT, MAX_DMG,
        SS_EACH, SS_RES, SS_EACH, QKC,
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
        INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC,
        TIE(1),
        SS_EACH, SS_EACH, HIT, NO_CRIT, MIN_DMG,
        SS_EACH, HIT, CRIT, MAX_DMG,
        SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC,
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
      const battle = startBattle([
        INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC, TIE(2), SS_EACH,
        SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC,
      ], [
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
      const battle = startBattle([
        INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, QKC,
        SS_EACH, SS_EACH, HIT, NO_CRIT, MIN_DMG, QKC,
      ], [
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

  test.todo('turn order (complex speed tie)');

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
    const hit = {key: HIT.key, value: ranged(Math.floor(85 * 255 / 100), 256) - 1};
    const miss = {key: MISS.key, value: hit.value + 1};
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
    const NO_BRN = {key: HIT.key, value: ranged(77, 256)};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, NO_BRN, QKC, NO_CRIT, MIN_DMG, QKC,
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
      const battle = startBattle([QKC, CRIT, MAX_DMG], [
        {species: 'Weezing', evs, moves: ['Explosion']},
        {species: 'Koffing', evs, moves: ['Self-Destruct']},
      ], [
        {species: 'Weedle', evs, moves: ['Poison Sting']},
        {species: 'Caterpie', evs, moves: ['String Shot']},
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

  test.todo('choices');

  // Items

  test.todo('Boost effect');
  test.todo('BrightPowder effect');
  test.todo('MetalPowder effect');
  test.todo('QuickClaw effect');
  test.todo('Flinch effect');
  test.todo('CriticalUp effect');
  test.todo('Leftovers effect');
  test.todo('HealStatus effect');
  test.todo('Berry effect');
  test.todo('RestorePP effect');
  test.todo('Mail effect');

  // Moves

  test('HighCritical effect', () => {
    const no_crit = {
      key: CRIT.key,
      value: ranged(Math.floor(gen.species.get('Machop')!.baseStats.spe / 2), 256),
    };
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

  test.todo('FocusEnergy effect');
  test.todo('MultiHit effect');
  test.todo('DoubleHit effect');
  test.todo('TripleKick effect');
  test.todo('Twineedle effect');
  test.todo('Poison effect');
  test.todo('PoisonChance effect');
  test.todo('BurnChance effect');
  test.todo('FlameWheel effect');
  test.todo('SacredFire effect');
  test.todo('FreezeChance effect');
  test.todo('Paralyze effect');
  test.todo('ParalyzeChance effect');
  test.todo('TriAttack effect');
  test.todo('Sleep effect');
  test.todo('Confusion effect');
  test.todo('ConfusionChance effect');
  test.todo('FlinchChance effect');
  test.todo('Snore effect');
  test.todo('Stomp effect');
  test.todo('StatDown effect');
  test.todo('StatDownChance effect');
  test.todo('StatUp effect');
  test.todo('DefenseCurl effect');
  test.todo('StatUpChance effect');
  test.todo('AllStatUpChance effect');

  test('OHKO effect', () => {
    const battle = startBattle([QKC, MISS, QKC, HIT], [
      {species: 'Kingler', level: 99, evs, moves: ['Guillotine']},
      {species: 'Tauros', evs, moves: ['Horn Drill']},
    ], [
      {species: 'Dugtrio', evs, moves: ['Fissure']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    battle.makeChoices('move 1', 'move 1');

    expect(battle.p1.pokemon[0].hp).toBe(0);

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
    ]);
  });

  test.todo('SkyAttack effect');
  test.todo('SkullBash effect');
  test.todo('RazorWind effect');
  test.todo('Solarbeam effect');
  test.todo('Fly/Dig effect');
  test.todo('Gust/Earthquake effect');
  test.todo('Twister effect');
  test.todo('ForceSwitch effect');

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

  test.todo('Trapping effect');
  test.todo('JumpKick effect');
  test.todo('RecoilHit effect');
  test.todo('Struggle effect');
  test.todo('Thrashing effect');

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
    const PSY_MAX = {key: 'Battle.damageCallback', value: MAX};
    const PSY_MIN = {key: 'Battle.damageCallback', value: MIN};
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

  test.todo('Disable effect');
  test.todo('Mist effect');
  test.todo('HyperBeam effect');
  test.todo('Counter effect');
  test.todo('MirrorCoat effect');
  test.todo('Heal effect');
  test.todo('WeatherHeal effect');
  test.todo('Rest effect');
  test.todo('DrainHP effect');
  test.todo('DreamEater effect');
  test.todo('LeechSeed effect');
  test.todo('Rage effect');
  test.todo('Mimic effect');
  test.todo('LightScreen effect');
  test.todo('Reflect effect');
  test.todo('Haze effect');
  test.todo('Bide effect');
  test.todo('Metronome effect');
  test.todo('MirrorMove effect');
  test.todo('Explode effect');
  test.todo('AlwaysHit effect');
  test.todo('Transform effect');
  test.todo('Conversion effect');
  test.todo('Conversion2 effect');
  test.todo('Substitute effect');
  test.todo('Sketch effect');
  test.todo('Thief effect');
  test.todo('MeanLook effect');
  test.todo('LockOn effect');
  test.todo('Nightmare effect');
  test.todo('Curse effect');
  test.todo('Reversal effect');
  test.todo('Spite effect');
  test.todo('Protect effect');
  test.todo('Endure effect');
  test.todo('BellyDrum effect');
  test.todo('Spikes effect');
  test.todo('RapidSpin effect');
  test.todo('Foresight effect');
  test.todo('DestinyBond effect');
  test.todo('PerishSong effect');
  test.todo('Rollout effect');
  test.todo('FalseSwipe effect');
  test.todo('Swagger effect');
  test.todo('FuryCutter effect');
  test.todo('Attract effect');
  test.todo('SleepTalk effect');
  test.todo('HealBell effect');
  test.todo('Return effect');
  test.todo('Frustration effect');
  test.todo('Present effect');
  test.todo('Safeguard effect');
  test.todo('PainSplit effect');
  test.todo('Magnitude effect');
  test.todo('BatonPass effect');
  test.todo('Encore effect');
  test.todo('Pursuit effect');
  test.todo('HiddenPower effect');
  test.todo('Sandstorm effect');
  test.todo('RainDance effect');
  test.todo('Thunder effect');
  test.todo('SunnyDay effect');
  test.todo('PsychUp effect');
  test.todo('FutureSight effect');
  test.todo('BeatUp effect');

  // Pokémon Showdown Bugs

  // TODO

  // Glitches

  // TODO
});
