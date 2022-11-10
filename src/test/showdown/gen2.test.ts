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

const QKC = {key: ['Battle.randomChance', 'Battle.nextTurn'], value: MAX};
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
const DRAG = (m: number, n = 5) => ({
  key: ['Battle.getRandomSwitchable', 'BattleActions.dragIn'], value: ranged(m - 1, n)});
const NO_PAR = {key: HIT.key, value: MAX};
const PAR_CANT = {key: 'Battle.onBeforeMove', value: ranged(1, 4) - 1};
const PAR_CAN = {key: 'Battle.onBeforeMove', value: PAR_CANT.value + 1};
const FRZ = {key: HIT.key, value: ranged(25, 256) - 1};
const THAW = {key: ['Battle.randomChance', 'Battle.onResidual'], value: ranged(25, 256) - 1};
const NO_THAW = {key: THAW.key, value: THAW.value + 1};
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
      QKC, QKC, CFZ_CAN, NO_CRIT, MIN_DMG, QKC,
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

  test('Stick effect', () => {
    const no_crit = {key: CRIT.key, value: ranged(4, 16) - 1};
    const battle = startBattle([
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC,
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC, QKC,
    ], [
      {species: 'Farfetchd', item: 'Stick', evs, moves: ['Cut']},
    ], [
      {species: 'Totodile', evs, moves: ['Thief']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 109);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 56);

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
      '|move|p2a: Totodile|Thief|p1a: Farfetch’d',
      '|-damage|p1a: Farfetch’d|257/307',
      '|turn|3',
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
    const hit = {key: HIT.key, value: ranged(Math.floor(85 * 255 / 100), 256) - 1};
    const battle = startBattle([QKC, hit, MISS, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Umbreon', item: 'Bright Powder', evs, moves: ['Mega Punch', 'Teleport']},
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
      '|move|p1a: Umbreon|Teleport|p1a: Umbreon',
      '|move|p2a: Croconaw|Swift|p1a: Umbreon',
      '|-damage|p1a: Umbreon|358/393',
      '|turn|3',
    ]);
  });

  test('MetalPowder effect', () => {
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG,
      QKC, SS_EACH, NO_CRIT, MIN_DMG, SS_EACH, SS_EACH,
      QKC, TIE(1), SS_EACH, SS_EACH, NO_CRIT, MIN_DMG,
      SS_EACH, NO_CRIT, MIN_DMG, SS_EACH, SS_EACH, QKC,
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
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 48);

    battle.makeChoices('move 1', 'move 2');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 57);
    // TODO: expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);
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
      '|-damage|p1a: Ditto|144/299',
      '|turn|3',
      '|move|p1a: Ditto|Surf|p2a: Slowking',
      '|-resisted|p2a: Slowking',
      '|-damage|p2a: Slowking|345/393',
      '|move|p2a: Slowking|Strength|p1a: Ditto',
      '|-damage|p1a: Ditto|87/299',
      '|turn|4',
    ]);
  });

  test('QuickClaw effect', () => {
    const proc = {key: QKC.key, value: ranged(60, 256) - 1};
    const no_proc = {key: QKC.key, value: proc.value + 1};
    const battle = startBattle([
      no_proc, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, no_proc,
    ], [
      {species: 'Igglybuff', item: 'Quick Claw', evs, moves: ['Teleport']},
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
      '|move|p1a: Igglybuff|Teleport|p1a: Igglybuff',
      '|turn|2',
      '|move|p1a: Igglybuff|Teleport|p1a: Igglybuff',
      '|move|p2a: Natu|Peck|p1a: Igglybuff',
      '|-damage|p1a: Igglybuff|265/383',
      '|turn|3',
      '|move|p2a: Natu|Quick Attack|p1a: Igglybuff',
      '|-damage|p1a: Igglybuff|220/383',
      '|move|p1a: Igglybuff|Teleport|p1a: Igglybuff',
      '|turn|4',
    ]);
  });

  test.todo('Flinch effect');

  test('CriticalUp effect', () => {
    const no_crit = {key: CRIT.key, value: ranged(2, 16) - 1};
    const battle = startBattle([
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC,
      QKC, HIT, no_crit, MIN_DMG, no_crit, MIN_DMG, PROC_SEC, QKC,
    ], [
      {species: 'Gligar', item: 'Scope Lens', evs, moves: ['Cut']},
    ], [
      {species: 'Ariados', evs, moves: ['Thief']},
    ]);

    const p1hp = battle.p1.pokemon[0].hp;
    const p2hp = battle.p2.pokemon[0].hp;

    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 109);

    battle.makeChoices('move 1', 'move 1');
    // expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
    // expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 56);

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
    const battle = startBattle([QKC, HIT, SS_MOD, SS_MOD, QKC, CFZ(5), SS_MOD, QKC], [
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

  test('FocusBand effect', () => {
    const band = {key: HIT.key, value: ranged(30, 256) - 1};
    const confusion = {key: HIT.key, value: ranged(25, 256) - 1};
    const battle = startBattle([QKC, CRIT, MAX_DMG, band, confusion, CFZ(5), CFZ_CANT], [
      {species: 'Igglybuff', item: 'Focus Band', evs, moves: ['Teleport']},
    ], [
      {species: 'Espeon', evs, moves: ['Psybeam']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Espeon|Psybeam|p1a: Igglybuff',
      '|-crit|p1a: Igglybuff',
      '|-activate|p1a: Igglybuff|item: Focus Band',
      '|-damage|p1a: Igglybuff|1/383',
      '|-start|p1a: Igglybuff|confusion',
      '|-activate|p1a: Igglybuff|confusion',
      '|-damage|p1a: Igglybuff|0 fnt|[from] confusion',
      '|faint|p1a: Igglybuff',
      '|win|Player 2',
    ]);
  });

  // Moves

  test('HighCritical effect', () => {
    const no_crit = {key: CRIT.key, value: ranged(2, 16) - 1};
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

  test('Poison effect', () => {
    {
      const battle = startBattle([
        QKC, HIT, QKC, HIT, QKC, HIT, SS_MOD, QKC, HIT, SS_MOD, QKC, QKC, QKC,
      ], [
        {species: 'Jolteon', evs, moves: ['Toxic', 'Substitute']},
        {species: 'Abra', evs, moves: ['Teleport']},
      ], [
        {species: 'Venomoth', evs, moves: ['Teleport', 'Toxic']},
        {species: 'Drowzee', evs, moves: ['Poison Gas', 'Teleport']},
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
        '|move|p2a: Venomoth|Teleport|p2a: Venomoth',
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
        '|move|p1a: Abra|Teleport|p1a: Abra',
        '|-damage|p1a: Abra|222/253 psn|[from] psn',
        '|move|p2a: Drowzee|Teleport|p2a: Drowzee',
        '|-damage|p2a: Drowzee|263/323 tox|[from] psn',
        '|turn|6',
        '|move|p1a: Abra|Teleport|p1a: Abra',
        '|-damage|p1a: Abra|191/253 psn|[from] psn',
        '|move|p2a: Drowzee|Teleport|p2a: Drowzee',
        '|-damage|p2a: Drowzee|203/323 tox|[from] psn',
        '|turn|7',
      ]);
    }
    {
      const battle = startBattle([QKC, HIT, SS_MOD, HIT, ...QKCs(30)], [
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
    const proc = {key: HIT.key, value: ranged(76, 256) - 1};
    const no_proc = {key: HIT.key, value: proc.value + 1};

    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, NO_CRIT, MIN_DMG, no_proc,
      QKC, NO_CRIT, MAX_DMG,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, SS_MOD,
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
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const no_proc = {key: HIT.key, value: proc.value + 1};

    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, no_proc,
      QKC, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, proc, SS_MOD,
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
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};

    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, SS_MOD, NO_CRIT, MIN_DMG, proc, SS_MOD, QKC,
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
    const lo_proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const hi_proc = {key: HIT.key, value: ranged(127, 256) - 1};

    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, lo_proc, SS_MOD, HIT, NO_CRIT, MIN_DMG, hi_proc, SS_MOD, QKC,
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
    const wrap = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MIN};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, SS_MOD,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, PAR_CANT,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD, NO_THAW,
      QKC, NO_THAW,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD,
      QKC, HIT, NO_CRIT, MIN_DMG, wrap, NO_THAW,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_THAW,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG,
      QKC, MISS,
      QKC, HIT, CRIT, MAX_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD, THAW, QKC,
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
    const battle = startBattle([
      QKC, MISS, HIT,
      QKC, PAR_CAN, HIT, SS_MOD,
      QKC, PAR_CANT,
      QKC, HIT, PAR_CAN,
      QKC,
      QKC, HIT, QKC,
    ], [
      {species: 'Arbok', evs, moves: ['Glare']},
      {species: 'Dugtrio', evs, moves: ['Earthquake', 'Substitute']},
    ], [
      {species: 'Magneton', evs, moves: ['Thunder Wave']},
      {species: 'Gengar', evs, moves: ['Toxic', 'Thunder Wave', 'Glare']},
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
    ]);
  });

  test('ParalyzeChance effect', () => {
    const lo_proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const hi_proc = {key: HIT.key, value: ranged(76, 256) - 1};

    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, hi_proc, SS_MOD, PAR_CAN, NO_CRIT, MIN_DMG, hi_proc,
      QKC, QKC, NO_CRIT, MIN_DMG, lo_proc, SS_MOD,
      QKC, PAR_CAN, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, lo_proc, PAR_CANT,
      QKC, QKC,
    ], [
      {species: 'Jolteon', evs, moves: ['Body Slam', 'Teleport']},
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
      '|move|p1a: Jolteon|Teleport|p1a: Jolteon',
      '|turn|3',
      '|move|p1a: Jolteon|Teleport|p1a: Jolteon',
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
    const proc = {key: HIT.key, value: ranged(51, 256) - 1};
    const no_proc = {key: proc.key, value: proc.value + 1};

    const par = {key: ['Battle.random', 'Battle.singleEvent'], value: ranged(1, 3)};
    const frz = {key: par.key, value: ranged(2, 3)};
    const brn = {key: par.key, value: ranged(3, 3)};

    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, frz, proc, SS_MOD, NO_THAW,
      QKC, NO_CRIT, MIN_DMG, brn, no_proc, MISS,
      QKC, NO_CRIT, MIN_DMG, par, proc, SS_MOD,
      QKC, NO_CRIT, MIN_DMG, par, proc, QKC,
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
    // expect(battle.p2.pokemon[0].status).toBe('brn');
    expect(battle.p2.pokemon[0].status).toBe('');
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
      '|turn|5',
    ]);
  });

  test.todo('Sleep effect');

  test('Confusion effect', () => {
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
  });

  test.todo('ConfusionChance effect');

  test('FlinchChance effect', () => {
    const lo_proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const hi_proc = {key: HIT.key, value: ranged(76, 256) - 1};

    const battle = startBattle([
      QKC, HIT, NO_CRIT, MIN_DMG, hi_proc,
      QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, hi_proc,
      QKC, NO_CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG,
      QKC, HIT, NO_CRIT, MIN_DMG, lo_proc,
      QKC, HIT, NO_CRIT, MIN_DMG, lo_proc,
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, hi_proc, SS_RES,
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
    const proc = {key: HIT.key, value: ranged(76, 256) - 1};
    const no_proc = {key: HIT.key, value: proc.value + 1};
    const battle = startBattle([
      QKC, HIT, SS_MOD, SLP(5), QKC, NO_CRIT, HIT, no_proc, HIT, QKC, NO_CRIT, HIT, proc, QKC,
    ], [
      {species: 'Heracross', evs, moves: ['Snore']},
    ], [
      {species: 'Bellossom', evs, moves: ['Sleep Powder', 'Teleport']},
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
    const proc = {key: HIT.key, value: ranged(76, 256) - 1};
    const no_proc = {key: HIT.key, value: proc.value + 1};
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
      QKC, HIT, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Ekans', evs, moves: ['Screech', 'Strength']},
    ], [
      {species: 'Caterpie', evs, moves: ['String Shot', 'Tackle']},
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
    ]);
  });

  test('StatDownChance effect', () => {
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const no_proc = {key: proc.key, value: proc.value + 1};
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
      {species: 'Blissey', evs, moves: ['Teleport']},
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
      '|move|p2a: Blissey|Teleport|p2a: Blissey',
      '|turn|2',
      '|move|p1a: Miltank|Rollout|p2a: Blissey|[miss]',
      '|-miss|p1a: Miltank',
      '|move|p2a: Blissey|Teleport|p2a: Blissey',
      '|turn|3',
      '|move|p1a: Miltank|Defense Curl|p1a: Miltank',
      '|-boost|p1a: Miltank|def|1',
      '|move|p2a: Blissey|Teleport|p2a: Blissey',
      '|turn|4',
      '|move|p1a: Miltank|Rollout|p2a: Blissey',
      '|-damage|p2a: Blissey|569/713',
      '|move|p2a: Blissey|Teleport|p2a: Blissey',
      '|turn|5',
    ]);
  });

  test('StatUpChance effect', () => {
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const no_proc = {key: proc.key, value: proc.value + 1};

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
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const no_proc = {key: proc.key, value: proc.value + 1};
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
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Wartortle', evs, moves: ['Skull Bash', 'Water Gun']},
      {species: 'Ivysaur', evs, moves: ['Vine Whip']},
    ], [
      {species: 'Psyduck', evs, moves: ['Scratch', 'Water Gun']},
      {species: 'Horsea', evs, moves: ['Bubble']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;
    let p2hp = battle.p2.pokemon[0].hp;

    let pp = battle.p1.pokemon[0].moveSlots[0].pp;

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 16);
    expect(battle.p1.pokemon[0].boosts.def).toBe(1);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

    expect(choices(battle, 'p1')).toEqual(['move 1']);
    expect(choices(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 16);
    expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
    expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

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
    ]);
  });

  test('RazorWind effect', () => {
    const crit2 = {key: CRIT.key, value: ranged(2, 16)};
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

  test.todo('Solarbeam effect');
  test.todo('Fly effect');
  test.todo('Dig effect');
  test.todo('Gust/Earthquake effect');
  test.todo('Twister effect');

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

  test.todo('Trapping effect');

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
      {species: 'Slowpoke', evs, moves: ['Teleport']},
      {species: 'Rhydon', evs, moves: ['Take Down', 'Teleport']},
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
      '|move|p1a: Rhydon|Teleport|p1a: Rhydon',
      '|turn|4',
    ]);
  });

  test('Struggle effect', () => {
    const battle = startBattle([
      QKC, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
    ], [
      {species: 'Abra', evs, moves: ['Substitute', 'Teleport']},
      {species: 'Golem', evs, moves: ['Harden']},
    ], [
      {species: 'Arcanine', evs, moves: ['Teleport']},
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
      '|move|p2a: Arcanine|Teleport|p2a: Arcanine',
      '|move|p1a: Abra|Substitute|p1a: Abra',
      '|-start|p1a: Abra|Substitute',
      '|-damage|p1a: Abra|1/253',
      '|turn|2',
      '|move|p2a: Arcanine|Struggle|p1a: Abra',
      '|-end|p1a: Abra|Substitute',
      '|-damage|p2a: Arcanine|382/383|[from] Recoil|[of] p1a: Abra',
      '|move|p1a: Abra|Teleport|p1a: Abra',
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

  test('Mist effect', () => {
    const proc = {key: HIT.key, value: ranged(25, 256) - 1};
    const battle = startBattle([
      QKC, NO_CRIT, MIN_DMG, proc, QKC, NO_CRIT, MIN_DMG,
      QKC, NO_CRIT, MIN_DMG, QKC, QKC
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
      '|switch|p1a: Suicune|Suicune|403/403',
      '|move|p2a: Vaporeon|Growl|p1a: Suicune',
      '|-activate|p1a: Suicune|move: Mist',
      '|turn|5',
    ]);
  });

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
      QKC, QKC, NO_CRIT, MIN_DMG, SS_MOD, SLP(5), QKC,
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
      QKC, NO_CRIT, MIN_DMG, QKC, NO_CRIT, MIN_DMG, QKC,
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
      QKC, HIT, NO_CRIT, MIN_DMG, QKC, HIT, NO_CRIT, MIN_DMG, QKC,
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

  test('Teleport effect', () => {
    const battle = startBattle([QKC, QKC], [
      {species: 'Smeargle', evs, moves: ['Sketch']},
    ], [
      {species: 'Abra', evs, moves: ['Teleport']},
    ]);

    battle.makeChoices('move 1', 'move 1');

    verify(battle, [
      '|move|p2a: Abra|Teleport|p2a: Abra',
      '|move|p1a: Smeargle|Sketch|p2a: Abra',
      '|-nothing',
      '|turn|2',
    ]);
  });

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

  test('MeanLook effect', () => {
    const battle = startBattle([QKC, QKC, QKC, QKC, QKC], [
      {species: 'Umbreon', evs, moves: ['Mean Look', 'Baton Pass']},
      {species: 'Spinarak', evs, moves: ['Teleport']},
    ], [
      {species: 'Espeon', evs, moves: ['Teleport', 'Baton Pass']},
      {species: 'Ledyba', evs, moves: ['Teleport']},
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
      '|move|p2a: Espeon|Teleport|p2a: Espeon',
      '|move|p1a: Umbreon|Mean Look|p2a: Espeon',
      '|-activate|p2a: Espeon|trapped',
      '|turn|2',
      '|move|p2a: Espeon|Teleport|p2a: Espeon',
      '|move|p1a: Umbreon|Baton Pass|p1a: Umbreon',
      '|switch|p1a: Spinarak|Spinarak, M|283/283',
      '|turn|3',
      '|move|p2a: Espeon|Baton Pass|p2a: Espeon',
      '|switch|p2a: Ledyba|Ledyba, M|283/283',
      '|move|p1a: Spinarak|Teleport|p1a: Spinarak',
      '|turn|4',
      '|switch|p1a: Umbreon|Umbreon, M|393/393',
      '|move|p2a: Ledyba|Teleport|p2a: Ledyba',
      '|turn|5',
    ]);
  });

  test.todo('LockOn effect');
  test.todo('Nightmare effect');
  test.todo('Curse effect');

  test('Reversal', () => {
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
    const spite2 = {key: ['Battle.onHit', 'Battle.singleEvent'], value: ranged(0, 4)};
    const spite3 = {key: spite2.key, value: ranged(1, 4)};
    const battle = startBattle([
      QKC, spite2, MISS, QKC, spite2, MISS, QKC, spite3, MISS, QKC, spite2, QKC,
    ], [
      {species: 'Misdreavus', evs, moves: ['Spite']},
    ], [
      {species: 'Ampharos', evs, moves: ['Zap Cannon', 'Teleport']},
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
      '|move|p2a: Ampharos|Teleport|p2a: Ampharos',
      '|turn|5',
    ]);
  });

  test.todo('Protect effect');
  test.todo('Endure effect');
  test.todo('BellyDrum effect');

  test('Spikes effect', () => {
    const battle = startBattle([QKC, QKC, QKC, NO_CRIT, MIN_DMG, QKC], [
      {species: 'Pineco', evs, moves: ['Spikes', 'Teleport']},
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
      '|move|p1a: Pineco|Teleport|p1a: Pineco',
      '|turn|4',
    ]);
  });

  test('RapidSpin effect', () => {
    const wrap = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MIN};
    const battle = startBattle([
      QKC, QKC, HIT, QKC, HIT, NO_CRIT, MIN_DMG, wrap, NO_CRIT, MIN_DMG, QKC,
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

  test.todo('Foresight effect');

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


  test.todo('PerishSong effect');
  test.todo('Rollout effect');

  test('FalseSwipe effect', () => {
    const battle = startBattle([QKC, NO_CRIT, MAX_DMG, QKC, NO_CRIT, MAX_DMG, QKC], [
      {species: 'Scizor', evs, moves: ['False Swipe']},
    ], [
      {species: 'Phanpy', level: 3, evs, moves: ['Defense Curl']},
    ]);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(1);

    battle.makeChoices('move 1', 'move 1');
    expect(battle.p2.pokemon[0].hp).toBe(1);

    verify(battle, [
      '|move|p1a: Scizor|False Swipe|p2a: Phanpy',
      '|-damage|p2a: Phanpy|1/21',
      '|move|p2a: Phanpy|Defense Curl|p2a: Phanpy',
      '|-boost|p2a: Phanpy|def|1',
      '|turn|2',
      '|move|p1a: Scizor|False Swipe|p2a: Phanpy',
      '|-damage|p2a: Phanpy|1/21',
      '|move|p2a: Phanpy|Defense Curl|p2a: Phanpy',
      '|-boost|p2a: Phanpy|def|1',
      '|turn|3',
    ]);
  });

  test('Swagger effect', () => {
    const battle = startBattle([QKC, HIT, CFZ(5), QKC, CFZ_CANT, HIT, QKC, CFZ_CANT, HIT, QKC], [
      {species: 'Scyther', evs, moves: ['Swords Dance']},
    ], [
      {species: 'Aipom', evs, moves: ['Swagger']},
    ]);

    let p1hp = battle.p1.pokemon[0].hp;

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
    ]);
  });

  test.todo('FuryCutter effect');
  test.todo('Attract effect');
  test.todo('SleepTalk effect');
  test.todo('HealBell effect');

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

  test.todo('Spikes 0 HP glitch');
  test.todo('Thick Club wrap around glitch');
  test.todo('Metal Powder increased damage glitch');
  test.todo('Reflect / Light Screen wrap around glitch');
  test.todo('Secondary chance 1/256 glitch');
  test.todo('Belly Drum failure glitch');
  test.todo('Berserk Gene confusion duration glitch');
  test.todo('Confusion self-hit damage glitch');
  test.todo('Defense lowering after breaking Substitute glitch');
  test.todo('PP Up + Disable freeze');
  test.todo('Lock-On / Mind Reader oversight');
  test.todo('Beat Up desync');
  test.todo('Beat Up partyless glitch');
  test.todo('Beat Up Kings Rock failure glitch');
  test.todo('Return/Frustration 0 damage glitch');
  test.todo('Switching <4 max HP freeze');
  test.todo('Stat increase post KO glitch');
});
