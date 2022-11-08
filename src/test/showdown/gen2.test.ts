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
const PROC_SEC = {key: ['Battle.randomChance', 'BattleActions.moveHit'], value: MIN};
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

  test('ThickClub effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Marowak', item: 'Thick Club', evs, moves: ['Strength']},
    ], [
      {species: 'Teddiursa', evs, moves: ['Thief', 'Scratch']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 22);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 151);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 36);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 75);

    verify(battle, [
      '|move|p1a: Marowak|Strength|p2a: Teddiursa',
      '|-damage|p2a: Teddiursa|172/323',
      '|move|p2a: Teddiursa|Thief|p1a: Marowak',
      '|-damage|p1a: Marowak|301/323',
      '|-item|p2a: Teddiursa|Thick Club|[from] move: Thief|[of] p1a: Marowak',
      '|turn|2',
      '|move|p1a: Marowak|Strength|p2a: Teddiursa',
      '|-damage|p2a: Teddiursa|97/323',
      '|move|p2a: Teddiursa|Scratch|p1a: Marowak',
      '|-damage|p1a: Marowak|265/323',
      '|turn|3',
    ]);
  });

  test('LightBall effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, PROC_SEC, QKC,
    ], [
      {species: 'Pikachu', item: 'Light Ball', evs, moves: ['Surf']},
    ], [
      {species: 'Ursaring', evs, moves: ['Thief']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 109);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 40);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 55);

    verify(battle, [
      '|move|p1a: Pikachu|Surf|p2a: Ursaring',
      '|-damage|p2a: Ursaring|274/383',
      '|move|p2a: Ursaring|Thief|p1a: Pikachu',
      '|-damage|p1a: Pikachu|233/273',
      '|-item|p2a: Ursaring|Light Ball|[from] move: Thief|[of] p1a: Pikachu',
      '|turn|2',
      '|move|p1a: Pikachu|Surf|p2a: Ursaring',
      '|-damage|p2a: Ursaring|219/383',
      '|move|p2a: Ursaring|Thief|p1a: Pikachu',
      '|-damage|p1a: Pikachu|193/273',
      '|turn|3',
    ]);
  });

  test('BerserkGene effect', () => {
    const battle = startBattle([
      QKC, QKC, CFZ_CAN, NO_CRIT, MIN_DMG, QKC
    ], [
      {species: 'Magby', evs, moves: ['Flamethrower']},
      {species: 'Cleffa', item: 'Berserk Gene', evs, moves: ['Pound']},
    ], [
      {species: 'Smoochum', evs, moves: ['Teleport']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('switch 2', 'move 1');
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
    expect(battle.p1.pokemon[0].volatiles['confusion']).toBeDefined();

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);

    verify(battle, [
      '|switch|p1a: Cleffa|Cleffa, M|303/303',
      '|-enditem|p1a: Cleffa|Berserk Gene',
      '|-boost|p1a: Cleffa|atk|2|[from] item: Berserk Gene',
      '|-start|p1a: Cleffa|confusion',
      '|move|p2a: Smoochum|Teleport|p2a: Smoochum',
      '|turn|2',
      '|move|p2a: Smoochum|Teleport|p2a: Smoochum',
      '|-activate|p1a: Cleffa|confusion',
      '|move|p1a: Cleffa|Pound|p2a: Smoochum',
      '|-damage|p2a: Smoochum|193/293',
      '|turn|3',
    ]);
  });

  test.todo('Stick effect');
  test.todo('Boost effect');
  test.todo('BrightPowder effect');
  test.todo('MetalPowder effect');
  test.todo('QuickClaw effect');
  test.todo('Flinch effect');
  test.todo('CriticalUp effect');

  test('Leftovers effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Scizor', item: 'Leftovers', evs, moves: ['False Swipe']},
    ], [
      {species: 'Magikarp', level: 2,  item: 'Leftovers', evs, moves: ['Dragon Rage']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

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

  test.todo('HealStatus effect');

  test('Berry effect', () => {
    const battle = startBattle([QKC, QKC, QKC], [
      {species: 'Togepi', evs, moves: ['Seismic Toss']},
    ], [
      {species: 'Tyrogue', item: 'Gold Berry', evs, moves: ['Teleport']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 100);
    expect(battle.p2.pokemon[0].item).toBe('goldberry');

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 100 + 30);
    expect(battle.p2.pokemon[0].item).toBe('');

    verify(battle, [
      '|move|p2a: Tyrogue|Teleport|p2a: Tyrogue',
      '|move|p1a: Togepi|Seismic Toss|p2a: Tyrogue',
      '|-damage|p2a: Tyrogue|173/273',
      '|turn|2',
      '|move|p2a: Tyrogue|Teleport|p2a: Tyrogue',
      '|move|p1a: Togepi|Seismic Toss|p2a: Tyrogue',
      '|-damage|p2a: Tyrogue|73/273',
      '|-enditem|p2a: Tyrogue|Gold Berry|[eat]',
      '|-heal|p2a: Tyrogue|103/273|[from] item: Gold Berry',
      '|turn|3',
    ]);
  });

  test.todo('RestorePP effect');

  test('Mail effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MIN_DMG, PROC_SEC, QKC], [
      {species: 'Spinarak', item: 'Mail', evs, moves: ['Teleport']},
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
      '|move|p1a: Spinarak|Teleport|p1a: Spinarak',
      '|turn|2',
    ]);
  });

  test.todo('FocusBand effect');

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

  test('MultiHit effect', () => {
    const key = ['Battle.sample', 'BattleActions.tryMoveHit'];
    const hit3 = {key, value: 0x60000000};
    const hit5 = {key, value: MAX};
    const battle = startBattle([
      QKC, HIT, hit3, NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, CRIT, MIN_DMG,
      QKC, HIT, hit5, NO_CRIT, MAX_DMG, CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, QKC,
    ], [
      {species: 'Kangaskhan', evs, moves: ['Comet Punch']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Teleport']},
    ]);

    let p2hp = battle.p2.pokemon[0].hp;
    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - 26 - 31 - 51 - 95);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    // Move continues after breaking the target's Substitute
    battle.makeChoices('move 1', 'move 2');
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
      '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
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
      {species: 'Slowpoke', evs, moves: ['Substitute', 'Teleport']},
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
      '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
      '|turn|3',
    ]);
  });

  test('TripleKick effect effect', () => {
    const key = ['Battle.random', 'BattleActions.tryMoveHit'];
    const hit2 = {key, value: ranged(2, 3 + 1)};
    const hit3 = {key, value: MAX};
    const battle = startBattle([
      QKC, HIT, hit2, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, HIT, hit3, CRIT, MAX_DMG, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Hitmontop', evs, moves: ['Triple Kick']},
    ], [
      {species: 'Bayleef', evs, moves: ['Substitute', 'Teleport']},
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
      '|move|p2a: Bayleef|Teleport|p2a: Bayleef',
      '|turn|3',
    ]);
  });

  test('Twineedle effect', () => {
    const proc = {key: HIT.key, value: ranged(51, 256) - 1};
    const no_proc = {key: HIT.key, value: proc.value + 1};

    const battle = startBattle([
      QKC, CRIT, MAX_DMG, NO_CRIT, MIN_DMG, proc, SS_MOD,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, no_proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MAX_DMG, proc, SS_MOD,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, QKC,
    ], [
      {species: 'Beedrill', evs, moves: ['Twineedle']},
    ], [
      {species: 'Voltorb', evs, moves: ['Substitute']},
      {species: 'Magnemite', evs, moves: ['Teleport']},
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
      '|move|p2a: Magnemite|Teleport|p2a: Magnemite',
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

  test.todo('WeatherHeal effect');
  test.todo('Rest effect');

  test('DrainHP effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Slowpoke', evs, moves: ['Teleport']},
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
    ]);
  });

  test('DreamEater effect', () => {
    const battle = startBattle([
      QKC,  QKC, NO_CRIT, MIN_DMG, SS_MOD, SLP(5), QKC,
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Hypno', evs, moves: ['Dream Eater', 'Confusion']},
    ], [
      {species: 'Wigglytuff', evs, moves: ['Substitute', 'Rest', 'Teleport']},
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
      '|move|p2a: Wigglytuff|Teleport|p2a: Wigglytuff',
      '|turn|6',
    ]);
  });

  test.todo('LeechSeed effect');

  test('PayDay effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MAX_DMG, QKC], [
      {species: 'Meowth', evs, moves: ['Pay Day']},
    ], [
      {species: 'Slowpoke', evs, moves: ['Teleport']},
    ]);

    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(p2hp - 43);

    verify(battle, [
      '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
      '|-damage|p2a: Slowpoke|340/383',
      '|-fieldactivate|move: Pay Day',
      '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
      '|turn|2',
    ]);
  });

  test.todo('Rage effect');
  test.todo('Mimic effect');

  test('LightScreen effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
      QKC, CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC
    ], [
      {species: 'Chansey', evs, moves: ['Light Screen', 'Teleport']},
      {species: 'Blissey', evs, moves: ['Teleport']},
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
      '|move|p1a: Chansey|Teleport|p1a: Chansey',
      '|turn|3',
      '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|546/703',
      '|move|p1a: Chansey|Teleport|p1a: Chansey',
      '|turn|4',
      '|switch|p1a: Blissey|Blissey, F|713/713',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|693/713',
      '|turn|5',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|673/713',
      '|move|p1a: Blissey|Teleport|p1a: Blissey',
      '|-sideend|p1: Player 1|move: Light Screen',
      '|turn|6',
      '|move|p2a: Vaporeon|Water Gun|p1a: Blissey',
      '|-damage|p1a: Blissey|635/713',
      '|move|p1a: Blissey|Teleport|p1a: Blissey',
      '|turn|7',
    ]);
  });

  test('Reflect effect', () => {
    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG, QKC
    ], [
      {species: 'Chansey', evs, moves: ['Reflect', 'Teleport']},
      {species: 'Blissey', evs, moves: ['Teleport']},
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
      '|move|p1a: Chansey|Teleport|p1a: Chansey',
      '|turn|3',
      '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
      '|-crit|p1a: Chansey',
      '|-damage|p1a: Chansey|514/703',
      '|move|p1a: Chansey|Teleport|p1a: Chansey',
      '|turn|4',
      '|switch|p1a: Blissey|Blissey, F|713/713',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|688/713',
      '|turn|5',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|663/713',
      '|move|p1a: Blissey|Teleport|p1a: Blissey',
      '|-sideend|p1: Player 1|Reflect',
      '|turn|6',
      '|move|p2a: Vaporeon|Tackle|p1a: Blissey',
      '|-damage|p1a: Blissey|614/713',
      '|move|p1a: Blissey|Teleport|p1a: Blissey',
      '|turn|7',
    ]);
  });

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

  test('Thief effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, PROC_SEC,
      QKC, NO_CRIT, MIN_DMG, PROC_SEC, QKC,
    ], [
      {species: 'Snubbull', evs, moves: ['Teleport']},
      {species: 'Granbull', item: 'Dragon Fang', evs, moves: ['Crunch']},
    ], [
      {species: 'Sneasel', evs, moves: ['Thief']},
    ]);

    let snubbull = battle.p1.pokemon[0].hp;
    let granbull = battle.p1.pokemon[1].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(snubbull -= 41);
    expect(battle.p1.pokemon[0].item).toBe('');
    expect(battle.p2.pokemon[0].item).toBe('');

    battle.makeChoices('switch 2', 'move 1');
     expect(battle.p1.pokemon[0].hp).toBe(granbull -= 34);
     expect(battle.p1.pokemon[0].item).toBe('');
     expect(battle.p2.pokemon[0].item).toBe('dragonfang');

    verify(battle, [
      '|move|p2a: Sneasel|Thief|p1a: Snubbull',
      '|-damage|p1a: Snubbull|282/323',
      '|move|p1a: Snubbull|Teleport|p1a: Snubbull',
      '|turn|2',
      '|switch|p1a: Granbull|Granbull, M|383/383',
      '|move|p2a: Sneasel|Thief|p1a: Granbull',
      '|-damage|p1a: Granbull|349/383',
      '|-item|p2a: Sneasel|Dragon Fang|[from] move: Thief|[of] p1a: Granbull',
      '|turn|3',
    ]);
  });

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
