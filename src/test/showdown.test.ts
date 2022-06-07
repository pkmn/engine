import {Battle, Dex, ID, PRNG, PRNGSeed} from '@pkmn/sim';
import {Generations, PokemonSet} from '@pkmn/data';

import * as gen1 from './benchmark/gen1';

const MIN = 0;
const MAX = 0xFFFFFFFF;
const NOP = 42;

const HIT = {key: 'BattleActions.tryMoveHit', value: MIN};
const MISS = {key: 'BattleActions.tryMoveHit', value: MAX};
const CRIT = {key: ['Battle.randomChance', 'BattleActions.getDamage'], value: MIN};
const NO_CRIT = {key: ['Battle.randomChance', 'BattleActions.getDamage'], value: MAX};
const MIN_DMG = {key: ['Battle.random', 'BattleActions.getDamage'], value: MIN};
const MAX_DMG = {key: ['Battle.random', 'BattleActions.getDamage'], value: MAX};

const SRF = {key: 'Side.randomFoe', value: NOP};
const SS_MOD = {key: ['Battle.speedSort', 'Pokemon.setStatus'], value: NOP};
const SS_RES = {key: ['Battle.speedSort', 'Battle.residualEvent'], value: NOP};
const SS_RUN = {key: ['Battle.speedSort', 'Battle.runEvent'], value: NOP};
const SS_EACH = {key: ['Battle.speedSort', 'Battle.eachEvent'], value: NOP};
const INS = {key: ['BattleQueue.insertChoice', 'BattleActions.switchIn'], value: NOP};
const GLM = {key: 'Pokemon.getLockedMove', value: NOP};

const ranged = (n: number, d: number) => n * (0x100000000 / d);

const TIE = (n: 1 | 2) =>
  ({key: ['Battle.speedSort', 'BattleQueue.sort'], value: ranged(n, 2) - 1});
const SLP = (n: number) =>
  ({key: ['Battle.random', 'Pokemon.setStatus'], value: ranged(n, 8 - 1)});
const DISABLE_DURATION = (n: number) =>
  ({key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: ranged(n, 7 - 1) - 1});
const DISABLE_MOVE = (m: number, n = 4) =>
  ({key: ['Battle.onStart', 'Pokemon.addVolatile'], value: ranged(m, n) - 1});
const PAR_CANT = {key: 'Battle.onBeforeMove', value: ranged(63, 256) - 1};
const PAR_CAN = {key: 'Battle.onBeforeMove', value: PAR_CANT.value + 1};
const FRZ = {key: HIT.key, value: ranged(26, 256) - 1};
const CFZ = (n: number) =>
  ({key: ['Battle.onStart', 'Pokemon.addVolatile'], value: ranged(n - 1, 6 - 2) - 1});
const CFZ_CAN = {name: 'CFZ_CAN', key: 'Battle.onBeforeMove', value: ranged(128, 256) - 1};
const CFZ_CANT = {name: 'CFZ_CANT', key: 'Battle.onBeforeMove', value: CFZ_CAN.value + 1};
const THRASH = (n: 3 | 4) =>
  ({key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: ranged(n - 2, 5 - 3) - 1});

const MODS: {[gen: number]: string[]} = {
  1: ['Endless Battle Clause', 'Sleep Clause Mod', 'Freeze Clause Mod'],
};

for (const gen of new Generations(Dex as any)) {
  if (gen.num > 1) break;

  const startBattle = (
    rolls: Roll[],
    p1: Partial<PokemonSet>[],
    p2: Partial<PokemonSet>[],
    fn?: (b: Battle) => void,
  ) => {
    const formatid = `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID;
    const battle = new Battle({formatid, strictChoices: true});
    (battle as any).debugMode = false;
    (battle as any).prng = new FixedRNG(rolls);
    if (fn) battle.started = true;
    battle.setPlayer('p1', {team: p1 as PokemonSet[]});
    battle.setPlayer('p2', {team: p2 as PokemonSet[]});
    if (fn) {
      fn(battle);
      battle.started = false;
      battle.start();
    } else {
      (battle as any).log = [];
    }
    return battle;
  };

  const EVS = gen.num >= 3 ? 0 : 255;
  const evs = {hp: EVS, atk: EVS, def: EVS, spa: EVS, spd: EVS, spe: EVS};

  describe(`Gen ${gen.num}`, () => {
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
      expectLog(battle, [
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
        expectLog(battle, [
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
        expectLog(battle, [
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
        expectLog(battle, [
          '|switch|p1a: Bulbasaur|Bulbasaur|0 fnt',
          '|switch|p2a: Charmander|Charmander|0 fnt',
          '|turn|1',
        ]);
      }
    });

    test('switching (order)', () => {
      const battle = startBattle([], [
        {species: 'Abra', level: 10, moves: ['Teleport']},
        {species: 'Abra', level: 20, moves: ['Teleport']},
        {species: 'Abra', level: 30, moves: ['Teleport']},
        {species: 'Abra', level: 40, moves: ['Teleport']},
        {species: 'Abra', level: 50, moves: ['Teleport']},
        {species: 'Abra', level: 60, moves: ['Teleport']},
      ], [
        {species: 'Gastly', level: 1, moves: ['Lick']},
        {species: 'Gastly', level: 2, moves: ['Lick']},
        {species: 'Gastly', level: 3, moves: ['Lick']},
        {species: 'Gastly', level: 4, moves: ['Lick']},
        {species: 'Gastly', level: 5, moves: ['Lick']},
        {species: 'Gastly', level: 6, moves: ['Lick']},
      ]);

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

      expectLog(battle, [
        '|switch|p1a: Abra|Abra, L30|64/64',
        '|switch|p2a: Gastly|Gastly, L2|13/13',
        '|turn|7',
      ]);
    });

    test('turn order (priority)', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT,
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

      expectLog(battle, [
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

    test('turn order (basic speed tie)', () => {
      // Move vs. Move
      {
        const battle = startBattle([
          INS, INS,	SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH,
          SRF, SRF, TIE(1),
          SS_EACH, SS_EACH, HIT, NO_CRIT, MIN_DMG,
          SS_EACH, HIT, NO_CRIT, MAX_DMG,
          SS_EACH, SS_EACH,
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

        expectLog(battle, [
          '|move|p1a: Tauros|Hyper Beam|p2a: Tauros',
          '|-damage|p2a: Tauros|187/353',
          '|-mustrecharge|p1a: Tauros',
          '|move|p2a: Tauros|Hyper Beam|p1a: Tauros',
          '|-damage|p1a: Tauros|157/353',
          '|-mustrecharge|p2a: Tauros',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
      // Switch vs. Switch
      {
        const battle = startBattle([
          INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH, TIE(2), SS_EACH, SS_EACH,
        ], [
          {species: 'Tauros', evs, moves: ['Hyper Beam']},
          {species: 'Starmie', evs, moves: ['Surf']},
        ], [
          {species: 'Tauros', evs, moves: ['Hyper Beam']},
          {species: 'Alakazam', evs, moves: ['Psychic']},
        ]);

        battle.makeChoices('switch 2', 'switch 2');

        expectLog(battle, [
          '|switch|p2a: Alakazam|Alakazam|313/313',
          '|switch|p1a: Starmie|Starmie|323/323',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
      // Move vs. Switch
      {
        const battle = startBattle([
          INS, INS, SS_EACH, SS_EACH, SS_EACH, SS_EACH, SS_EACH,
          SRF, SS_EACH, SS_EACH, HIT, NO_CRIT, MIN_DMG,
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

        expectLog(battle, [
          '|switch|p2a: Alakazam|Alakazam|313/313',
          '|move|p1a: Tauros|Hyper Beam|p2a: Alakazam',
          '|-damage|p2a: Alakazam|58/313',
          '|-mustrecharge|p1a: Tauros',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
    });

    test.todo('turn order (complex speed tie)');

    test('turn order (switch vs. move)', () => {
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MIN_DMG, SRF, HIT, NO_CRIT, MIN_DMG,
      ], [
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

      expectLog(battle, [
        '|switch|p2a: Vulpix|Vulpix|279/279',
        '|move|p1a: Raticate|Quick Attack|p2a: Vulpix',
        '|-damage|p2a: Vulpix|215/279',
        '|turn|2',
        '|switch|p1a: Rattata|Rattata|263/263',
        '|move|p2a: Vulpix|Quick Attack|p1a: Rattata',
        '|-damage|p1a: Rattata|231/263',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
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
      const hit = {key: HIT.key, value: ranged(Math.floor(85 * 255 / 100), 256) - 1};
      const miss = {key: MISS.key, value: hit.value + 1};
      const battle = startBattle([SRF, SRF, hit, CRIT, MAX_DMG, miss], [
        {species: 'Hitmonchan', evs, moves: ['Mega Punch']},
      ], [
        {species: 'Machamp', evs, moves: ['Mega Punch']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
      expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 159);

      expectLog(battle, [
        '|move|p1a: Hitmonchan|Mega Punch|p2a: Machamp',
        '|-crit|p2a: Machamp',
        '|-damage|p2a: Machamp|224/383',
        '|move|p2a: Machamp|Mega Punch|p1a: Hitmonchan|[miss]',
        '|-miss|p2a: Machamp',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('damage calc', () => {
      const NO_BRN = {key: HIT.key, value: ranged(77, 256)};
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, CRIT, MAX_DMG, NO_BRN,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG,
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('fainting (single)', () => {
      // Switch
      {
        const battle = startBattle([SRF, SRF, HIT, HIT, NO_CRIT, MAX_DMG], [
          {species: 'Venusaur', evs, moves: ['Leech Seed']},
        ], [
          {species: 'Slowpoke', evs, moves: ['Water Gun']},
          {species: 'Dratini', evs, moves: ['Dragon Rage']},
        ]);

        battle.p2.pokemon[0].hp = 1;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(0);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual([]);
        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2']);

        expectLog(battle, [
          '|move|p1a: Venusaur|Leech Seed|p2a: Slowpoke',
          '|-start|p2a: Slowpoke|move: Leech Seed',
          '|move|p2a: Slowpoke|Water Gun|p1a: Venusaur',
          '|-resisted|p1a: Venusaur',
          '|-damage|p1a: Venusaur|348/363',
          '|-damage|p2a: Slowpoke|0 fnt|[from] Leech Seed|[of] p1a: Venusaur',
          '|-heal|p1a: Venusaur|363/363|[silent]',
          '|faint|p2a: Slowpoke',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
      // Win
      {
        const battle = startBattle([SRF, SRF, HIT], [
          {species: 'Dratini', evs, moves: ['Dragon Rage']},
        ], [
          {species: 'Slowpoke', evs, moves: ['Water Gun']},
        ]);

        battle.p1.pokemon[0].hp = 1;
        battle.p2.pokemon[0].hp = 1;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(0);

        expectLog(battle, [
          '|move|p1a: Dratini|Dragon Rage|p2a: Slowpoke',
          '|-damage|p2a: Slowpoke|0 fnt',
          '|faint|p2a: Slowpoke',
          '|win|Player 1',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
      // Lose
      {
        const battle = startBattle([SRF, SRF, SRF, NO_CRIT, MIN_DMG, HIT], [
          {species: 'Jolteon', evs, moves: ['Swift']},
        ], [
          {species: 'Dratini', evs, moves: ['Dragon Rage']},
        ]);

        battle.p1.pokemon[0].hp = 1;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(0);
        expect(battle.p2.pokemon[0].hp).toBe(232);

        expectLog(battle, [
          '|move|p1a: Jolteon|Swift|p2a: Dratini',
          '|-damage|p2a: Dratini|232/285',
          '|move|p2a: Dratini|Dragon Rage|p1a: Jolteon',
          '|-damage|p1a: Jolteon|0 fnt',
          '|faint|p1a: Jolteon',
          '|win|Player 2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
    });

    test('fainting (double)', () => {
      // Switch
      {
        const battle = startBattle([SRF, SRF, HIT, CRIT, MAX_DMG], [
          {species: 'Weezing', evs, moves: ['Explosion']},
          {species: 'Koffing', evs, moves: ['Self-Destruct']},
        ], [
          {species: 'Weedle', evs, moves: ['Poison Sting']},
          {species: 'Caterpie', evs, moves: ['String Shot']},
        ]);

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(0);
        expect(battle.p2.pokemon[0].hp).toBe(0);

        expectLog(battle, [
          '|move|p1a: Weezing|Explosion|p2a: Weedle',
          '|-crit|p2a: Weedle',
          '|-damage|p2a: Weedle|0 fnt',
          '|faint|p2a: Weedle',
          '|faint|p1a: Weezing',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      }
      // Tie
      {
        const battle = startBattle([SRF, SRF, HIT, CRIT, MAX_DMG], [
          {species: 'Weezing', evs, moves: ['Explosion']},
        ], [
          {species: 'Weedle', evs, moves: ['Poison Sting']},
        ]);

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(0);
        expect(battle.p2.pokemon[0].hp).toBe(0);

        expectLog(battle, [
          '|move|p1a: Weezing|Explosion|p2a: Weedle',
          '|-crit|p2a: Weedle',
          '|-damage|p2a: Weedle|0 fnt',
          '|faint|p2a: Weedle',
          '|faint|p1a: Weezing',
          '|tie',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
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

      expectLog(battle, [
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
      expectLog(battle, [
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
        const battle = startBattle([SRF, SRF], [
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
      const formatid = `gen${gen.num}customgame@@@${MODS[gen.num].join(',')}` as ID;
      const battle = new Battle({formatid, ...gen1.Battle.options(gen, random) as any});

      expect(gen1.Choices.sim(battle, 'p1')).toEqual([
        'switch 2', 'switch 3', 'switch 4', 'switch 5', 'switch 6',
        'move 1', 'move 2', 'move 3', 'move 4',
      ]);

      battle.p1.activeRequest!.forceSwitch = true;
      expect(gen1.Choices.sim(battle, 'p1')).toEqual([
        'switch 2', 'switch 3', 'switch 4', 'switch 5', 'switch 6',
      ]);

      battle.p1.activeRequest!.wait = true;
      expect(gen1.Choices.sim(battle, 'p1')).toEqual([]);
    });

    test('HighCritical', () => {
      const value = ranged(Math.floor(gen.species.get('Machop')!.baseStats.spe / 2), 256);
      const no_crit = {key: CRIT.key, value};
      // Regular non-crit roll is still a crit for high critical moves
      const battle = startBattle([SRF, SRF, HIT, no_crit, MIN_DMG, HIT, no_crit, MIN_DMG], [
        {species: 'Machop', evs, moves: ['Karate Chop']},
      ], [
        {species: 'Machop', level: 99, evs, moves: ['Strength']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 73);
      expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 92);

      expectLog(battle, [
        '|move|p1a: Machop|Karate Chop|p2a: Machop',
        '|-crit|p2a: Machop',
        '|-damage|p2a: Machop|247/339',
        '|move|p2a: Machop|Strength|p1a: Machop',
        '|-damage|p1a: Machop|270/343',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('FocusEnergy', () => {
      const value = ranged(Math.floor(gen.species.get('Machoke')!.baseStats.spe / 2), 256) - 1;
      const crit = {key: CRIT.key, value};
      const battle = startBattle([SRF, HIT, crit, MIN_DMG, SRF, HIT, crit, MIN_DMG], [
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

      expectLog(battle, [
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
        '|-end|p1a: Machoke|focusenergy|[silent]',
        '|turn|3',
        '|move|p1a: Machoke|Strength|p2a: Koffing',
        '|-crit|p2a: Koffing',
        '|-damage|p2a: Koffing|108/283',
        '|move|p2a: Koffing|Double Team|p2a: Koffing',
        '|-boost|p2a: Koffing|evasion|1',
        '|turn|4',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('MultiHit', () => {
      const key = ['Battle.sample', 'BattleActions.tryMoveHit'];
      const hit3 = {key, value: 3 * (0x100000000 / 8) - 1};
      const hit5 = {key, value: MAX};
      const battle = startBattle([
        SRF, HIT, hit3, NO_CRIT, MAX_DMG, SRF, HIT, hit5, NO_CRIT, MAX_DMG,
      ], [
        {species: 'Kangaskhan', evs, moves: ['Comet Punch']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Substitute', 'Teleport']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - (31 * 3) - 95);

      // Breaking a target's Substitute ends the move
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      expectLog(battle, [
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
        '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('DoubleHit', () => {
      const battle = startBattle([SRF, HIT, NO_CRIT, MAX_DMG, SRF, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Marowak', evs, moves: ['Bonemerang']},
      ], [
        {species: 'Slowpoke', level: 80, evs, moves: ['Substitute', 'Teleport']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp = p2hp - (91 * 2) - 77);

      // Breaking a target's Substitute ends the move
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      expectLog(battle, [
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
        '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
        '|turn|3',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    // test('Twineedle', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    // test('Poison (primary)', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    // test('PoisonChance', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    // test('BurnChance', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    // test('FreezeChance', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    test('Paralyze (primary)', () => {
      const battle = startBattle([
        SRF, SRF, MISS, HIT, SS_MOD,
        SRF, SRF, HIT, PAR_CAN, HIT, SS_MOD,
        SRF, PAR_CANT,
        SRF, SRF, HIT, PAR_CAN, HIT, SS_MOD,
        SRF, PAR_CAN,
        SRF, PAR_CAN, HIT, SS_MOD,
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    // test('ParalyzeChance', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    // test('Sleep', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    test('Confusion (primary)', () => {
      const battle = startBattle([
        SRF, HIT, SRF, HIT, SRF, HIT, CFZ(3), SRF, CFZ_CANT, HIT, SRF, CFZ_CAN, HIT, SRF, HIT,
      ], [
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('ConfusionChance', () => {
      const proc = {key: HIT.key, value: ranged(25, 256) - 1};
      const no_proc = {key: proc.key, value: proc.value + 1};
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MAX_DMG, proc,
        SRF, HIT, NO_CRIT, MAX_DMG, proc,
        SRF, HIT, NO_CRIT, MAX_DMG, no_proc, CFZ(3),
      ], [
        {species: 'Venomoth', evs, moves: ['Psybeam']},
      ], [
        {species: 'Jolteon', evs, moves: ['Substitute', 'Agility']},
      ]);

      let p2hp = battle.p2.pokemon[0].hp;

      // Substitute blocks ConfusionChance on Pokémon Showdown
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
      expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      // Pokémon Showdown procs on 26 instead of 25, so no_proc will still proc
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 49);
      expect(battle.p2.pokemon[0].volatiles['confusion']).toBeDefined();

      expectLog(battle, [
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
        '|move|p2a: Jolteon|Agility|p2a: Jolteon',
        '|-boost|p2a: Jolteon|spe|2',
        '|move|p1a: Venomoth|Psybeam|p2a: Jolteon',
        '|-damage|p2a: Jolteon|201/333',
        '|-start|p2a: Jolteon|confusion',
        '|turn|4',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    // test('FlinchChance', () => {
    //   const battle = startBattle([], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ], [
    //     {species: 'TODO', evs, moves: ['TODO']},
    //   ]);

    //   let p1hp = battle.p1.pokemon[0].hp;
    //   let p2hp = battle.p2.pokemon[0].hp;

    //   battle.makeChoices('move 1', 'move 1');
    //   expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 0);
    //   expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 0);

    //   expectLog(battle, [
    //   ]);
    //   expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    // });

    test('StatDown', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, SRF, HIT,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('StatDownChance', () => {
      const proc = {key: HIT.key, value: ranged(85, 256) - 1};
      const no_proc = {key: proc.key, value: proc.value + 1};
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, proc,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, proc,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, no_proc, HIT, NO_CRIT, MIN_DMG, no_proc,
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

      expectLog(battle, [
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
        '|-unboost|p2a: Starmie|spd|1',
        '|-unboost|p2a: Starmie|spa|1',
        '|turn|3',
        '|move|p2a: Starmie|Bubble Beam|p1a: Alakazam',
        '|-damage|p1a: Alakazam|160/313',
        '|move|p1a: Alakazam|Psychic|p2a: Starmie',
        '|-resisted|p2a: Starmie',
        '|-damage|p2a: Starmie|112/323',
        '|turn|4',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('StatUp', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('OHKO', () => {
      const battle = startBattle([SRF, SRF, MISS, SRF, SRF, HIT], [
        {species: 'Kingler', evs, moves: ['Guillotine']},
        {species: 'Tauros', evs, moves: ['Horn Drill']},
      ], [
        {species: 'Dugtrio', evs, moves: ['Fissure']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].hp).toBe(0);

      expectLog(battle, [
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

    test('Charge', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
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
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 23);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 83);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expectLog(battle, [
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
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Fly / Dig', () => {
      const battle = startBattle([
        SRF, SRF, SS_RES, GLM,
        GLM, GLM, SRF, SRF, SS_RUN, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
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

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 74);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 79);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SwitchAndTeleport', () => {
      const battle = startBattle([SRF, HIT, SRF, MISS], [
        {species: 'Abra', evs, moves: ['Teleport']},
      ], [
        {species: 'Pidgey', evs, moves: ['Whirlwind']},
      ]);

      battle.makeChoices('move 1', 'move 1');
      battle.makeChoices('move 1', 'move 1');

      expectLog(battle, [
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

      expectLog(battle, [
        '|move|p1a: Gyarados|Splash|p1a: Gyarados',
        '|-nothing',
        '|move|p2a: Magikarp|Splash|p2a: Magikarp',
        '|-nothing',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test.todo('Trapping');

    test('JumpKick', () => {
      const battle = startBattle([SRF, SRF, MISS, HIT, CRIT, MAX_DMG, SRF, SRF, MISS, MISS], [
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Recoil', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG,
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

      // Struggle only becomes an pption if the user has no PP left
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].moveSlots[0].pp).toBe(0);

      // Deals no damage if the move breaks the target's Substitute
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      // Struggle recoil inflicts at least 1 HP
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(0);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 1);

      battle.makeChoices('switch 2', '');

      // Respects type effectiveness and inflicts 1/2 of damage dealt to user as recoil
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp - 16);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 8);

      expectLog(battle, [
        '|move|p2a: Arcanine|Teleport|p2a: Arcanine',
        '|move|p1a: Abra|Substitute|p1a: Abra',
        '|-start|p1a: Abra|Substitute',
        '|-damage|p1a: Abra|1/253',
        '|turn|2',
        '|move|p2a: Arcanine|Struggle|p1a: Abra',
        '|-end|p1a: Abra|Substitute',
        '|move|p1a: Abra|Teleport|p1a: Abra',
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Thrashing', () => {
      const battle = startBattle([
        SRF, SRF, SRF, HIT, NO_CRIT, MIN_DMG, THRASH(3), HIT, CFZ(5),
        SRF, SRF, SRF, SRF, CFZ_CAN, MISS, SRF, MISS, THRASH(3),
        SRF, SRF, SRF, SRF, SRF, CFZ_CAN, HIT, NO_CRIT, MIN_DMG, CFZ(5), SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, SRF, CFZ_CAN, HIT, SS_MOD, SRF, PAR_CANT,
        SRF, SRF, CFZ_CAN, HIT, SRF, PAR_CAN, HIT, NO_CRIT, MAX_DMG, THRASH(3),
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

      // Thrashig locks user in for 3-4 turns
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      // Thrashing locks you in whether you hit or not
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(4);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['move 1']);

      // Thrashing confuses you even if already confused
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 91);
      expect(battle.p1.pokemon[0].volatiles['confusion'].time).toBe(5);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 68);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['move 1']);

      // Thrashing doesn't confuse you if the user is prevented from moving
      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);
      expect(battle.p2.pokemon[0].status).toBe('par');
      expect(battle.p2.pokemon[0].volatiles['confusion']).toBeUndefined();

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 108);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp);

      expectLog(battle, [
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
        '|-damage|p2a: Vileplume|217/353',
        '|-start|p1a: Nidoking|confusion|[silent]',
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SpecialDamage (fixed)', () => {
      const battle = startBattle([SRF, SRF, HIT, HIT, SRF], [
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

      expectLog(battle, [
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
      const battle = startBattle([SRF, SRF, HIT, HIT], [
        {species: 'Gastly', evs, level: 22, moves: ['Night Shade']},
      ], [
        {species: 'Clefairy', evs, level: 16, moves: ['Seismic Toss']},
      ]);

      const p1hp = battle.p1.pokemon[0].hp;
      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 16);
      expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 22);

      expectLog(battle, [
        '|move|p1a: Gastly|Night Shade|p2a: Clefairy',
        '|-damage|p2a: Clefairy|41/63',
        '|move|p2a: Clefairy|Seismic Toss|p1a: Gastly',
        '|-damage|p1a: Gastly|49/65',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SpecialDamage (Psywave)', () => {
      const PSY_MAX = {key: 'Battle.damageCallback', value: MAX};
      const PSY_MIN = {key: 'Battle.damageCallback', value: MIN};
      const battle = startBattle([SRF, SRF, HIT, PSY_MAX, HIT, PSY_MIN], [
        {species: 'Gengar', evs, level: 59, moves: ['Psywave']},
      ], [
        {species: 'Clefable', evs, level: 42, moves: ['Psywave']},
      ]);

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');

      expect(battle.p2.pokemon[0].hp).toEqual(p2hp - 87);

      expectLog(battle, [
        '|move|p1a: Gengar|Psywave|p2a: Clefable',
        '|-damage|p2a: Clefable|83/170',
        '|move|p2a: Clefable|Psywave|p1a: Gengar',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('SuperFang', () => {
      const battle = startBattle([SRF, SRF, HIT, HIT, SRF, SRF, HIT], [
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

      expectLog(battle, [
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

    test('Disable', () => {
      const no_frz = {key: HIT.key, value: ranged(26, 256)};
      const battle = startBattle([
        SRF, SRF, HIT, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, DISABLE_DURATION(1), DISABLE_MOVE(1),
        SRF, SRF, HIT, DISABLE_DURATION(5), DISABLE_MOVE(3), HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, DISABLE_DURATION(5), DISABLE_MOVE(4),
        SRF, SRF, HIT, HIT, NO_CRIT, MIN_DMG,
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, no_frz,
      ], [
        {species: 'Golduck', evs, moves: ['Disable', 'Water Gun']},
      ], [
        {species: 'Vaporeon', evs, moves: ['Water Gun', 'Haze', 'Rest', 'Blizzard']},
        {species: 'Flareon', evs, moves: ['Flamethrower']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      // Fails on Pokémon Showdown if there is no last move
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
      expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

      expect(gen1.Choices.sim(battle, 'p2'))
        .toEqual(['switch 2', 'move 1', 'move 2', 'move 3', 'move 4']);

      // On Pokémon Showdown lasts a minimum of 1 turn instead of 0
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();

      expect(gen1.Choices.sim(battle, 'p2'))
        .toEqual(['switch 2', 'move 1', 'move 2', 'move 3', 'move 4']);

      // Should skip over moves which are already out of PP (but Pokémon Showdown doesn't)
      battle.p2.pokemon[0].moveSlots[2].pp = 0;
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 4']);
      delete battle.p2.pokemon[0].volatiles['disable'];

      // Can be disabled for many turns
      battle.makeChoices('move 1', 'move 4');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      expect(battle.p2.pokemon[0].volatiles['disable'].duration).toBe(4);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      // Disable fails if a move is already disabled
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 27);
      expect(battle.p2.pokemon[0].volatiles['disable'].duration).toBe(3);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      // Haze clears disable
      battle.makeChoices('move 2', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
      expect(battle.p2.pokemon[0].volatiles['disable']).toBeUndefined();
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2', 'move 4']);

      battle.makeChoices('move 2', 'move 4');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 53);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);

      expectLog(battle, [
        '|move|p1a: Golduck|Disable|p2a: Vaporeon',
        '|-fail|p2a: Vaporeon',
        '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
        '|-resisted|p1a: Golduck',
        '|-damage|p1a: Golduck|336/363',
        '|turn|2',
        '|move|p1a: Golduck|Disable|p2a: Vaporeon',
        '|-start|p2a: Vaporeon|Disable|Water Gun',
        '|cant|p2a: Vaporeon|Disable|Water Gun',
        '|-end|p2a: Vaporeon|Disable',
        '|turn|3',
        '|move|p1a: Golduck|Disable|p2a: Vaporeon',
        '|-start|p2a: Vaporeon|Disable|Rest',
        '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
        '|-resisted|p1a: Golduck',
        '|-damage|p1a: Golduck|309/363',
        '|turn|4',
        '|move|p1a: Golduck|Disable|p2a: Vaporeon',
        '|-start|p2a: Vaporeon|Disable|Blizzard',
        '|cant|p2a: Vaporeon|Disable|Blizzard',
        '|turn|5',
        '|move|p1a: Golduck|Disable|p2a: Vaporeon',
        '|move|p2a: Vaporeon|Water Gun|p1a: Golduck',
        '|-resisted|p1a: Golduck',
        '|-damage|p1a: Golduck|282/363',
        '|turn|6',
        '|move|p1a: Golduck|Water Gun|p2a: Vaporeon',
        '|-resisted|p2a: Vaporeon',
        '|-damage|p2a: Vaporeon|446/463',
        '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
        '|-activate|p2a: Vaporeon|move: Haze',
        '|-clearallboost|[silent]',
        '|-end|p2a: Vaporeon|Disable',
        '|-end|p2a: Vaporeon|disable|[silent]',
        '|turn|7',
        '|move|p1a: Golduck|Water Gun|p2a: Vaporeon',
        '|-resisted|p2a: Vaporeon',
        '|-damage|p2a: Vaporeon|429/463',
        '|move|p2a: Vaporeon|Blizzard|p1a: Golduck',
        '|-resisted|p1a: Golduck',
        '|-damage|p1a: Golduck|229/363',
        '|turn|8',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Mist', () => {
      const proc = {key: HIT.key, value: ranged(85, 256) - 1};
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MIN_DMG, proc,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, SRF, HIT,
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, SRF, HIT,
      ], [
        {species: 'Articuno', evs, moves: ['Mist', 'Peck']},
      ], [
        {species: 'Vaporeon', evs, moves: ['Aurora Beam', 'Growl', 'Haze']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      // Mist doesn't protect against secondary effects
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 43);
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

      expectLog(battle, [
        '|move|p1a: Articuno|Mist|p1a: Articuno',
        '|-start|p1a: Articuno|Mist',
        '|move|p2a: Vaporeon|Aurora Beam|p1a: Articuno',
        '|-damage|p1a: Articuno|340/383',
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
        '|-end|p1a: Articuno|mist|[silent]',
        '|turn|4',
        '|move|p1a: Articuno|Peck|p2a: Vaporeon',
        '|-damage|p2a: Vaporeon|353/463',
        '|move|p2a: Vaporeon|Growl|p1a: Articuno',
        '|-unboost|p1a: Articuno|atk|1',
        '|turn|5',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('HyperBeam', () => {
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MAX_DMG,
        SRF, HIT, NO_CRIT, MAX_DMG,
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF,
      ], [
        {species: 'Tauros', evs, moves: ['Hyper Beam', 'Body Slam']},
        {species: 'Exeggutor', evs, moves: ['Sleep Powder']},
      ], [
        {species: 'Jolteon', evs, moves: ['Substitute', 'Teleport']},
        {species: 'Chansey', evs, moves: ['Teleport', 'Soft-Boiled']},
      ]);

      battle.p2.pokemon[0].hp = 100;

      let jolteon = battle.p2.pokemon[0].hp;
      let chansey = battle.p2.pokemon[1].hp;

      let pp = battle.p1.pokemon[0].moveSlots[0].pp;

      // Doesn't require a recharge if it knocks out a Substitute
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(jolteon -= 83);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      // Doesn't require a recharge if it knocks out opponent
      battle.makeChoices('move 1', 'move 2');
      expect(battle.p2.pokemon[0].hp).toBe(0);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual([]);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2']);

      battle.makeChoices('', 'switch 2');

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(chansey -= 442);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['move 1', 'move 2']);

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(chansey);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['move 1', 'move 2']);

      expectLog(battle, [
        '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
        '|-start|p2a: Jolteon|Substitute',
        '|-damage|p2a: Jolteon|17/333',
        '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
        '|-end|p2a: Jolteon|Substitute',
        '|turn|2',
        '|move|p2a: Jolteon|Teleport|p2a: Jolteon',
        '|move|p1a: Tauros|Hyper Beam|p2a: Jolteon',
        '|-damage|p2a: Jolteon|0 fnt',
        '|faint|p2a: Jolteon',
        '|switch|p2a: Chansey|Chansey|703/703',
        '|turn|3',
        '|move|p1a: Tauros|Hyper Beam|p2a: Chansey',
        '|-damage|p2a: Chansey|261/703',
        '|-mustrecharge|p1a: Tauros',
        '|move|p2a: Chansey|Teleport|p2a: Chansey',
        '|turn|4',
        '|cant|p1a: Tauros|recharge',
        '|move|p2a: Chansey|Teleport|p2a: Chansey',
        '|turn|5',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test.todo('Counter');

    test('Heal (normal)', () => {
      const battle = startBattle([SRF, SRF, HIT, CRIT, MAX_DMG, HIT, NO_CRIT, MIN_DMG], [
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Heal (Rest)', () => {
      const battle = startBattle([
        SRF, HIT, SS_MOD,
        SRF, HIT, NO_CRIT, MIN_DMG, PAR_CAN, SS_MOD, SLP(5),
        SRF, HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Porygon', evs, moves: ['Thunder Wave', 'Tackle', 'Rest']},
        {species: 'Dragonair', evs, moves: ['Slam']},
      ], [
        {species: 'Chansey', evs, moves: ['Rest', 'Teleport']},
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

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2', 'move 3']);
      expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

      battle.makeChoices('move 2', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 77);

      // Fails at full HP / Last two turns but stat penalty still remains after waking
      battle.makeChoices('move 3', 'move 1');
      expect(battle.p2.pokemon[0].status).toBe('');
      expect(battle.p2.pokemon[0].modifiedStats!.spe).toBe(49);
      expect(battle.p2.pokemon[0].storedStats.spe).toBe(198);

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Drain', () => {
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MIN_DMG, SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
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

      expectLog(battle, [
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('DreamEater', () => {
      const battle = startBattle([
        SRF, SRF, HIT, SS_MOD, SLP(5), SRF, HIT, NO_CRIT, MIN_DMG, SRF, HIT, NO_CRIT, MIN_DMG,
      ], [
        {species: 'Hypno', evs, moves: ['Dream Eater', 'Hypnosis']},
      ], [
        {species: 'Wigglytuff', evs, moves: ['Teleport']},
      ]);

      battle.p1.pokemon[0].hp = 100;
      battle.p2.pokemon[0].hp = 182;

      let p1hp = battle.p1.pokemon[0].hp;

      // Fails unless the target is sleeping
      battle.makeChoices('move 1', 'move 1');

      battle.makeChoices('move 2', 'move 1');

      // Heals 1/2 of the damage dealt
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp += 90);
      expect(battle.p2.pokemon[0].hp).toBe(1);

      // Heals at least 1 HP
      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp += 1);
      expect(battle.p2.pokemon[0].hp).toBe(0);

      expectLog(battle, [
        '|move|p1a: Hypno|Dream Eater|p2a: Wigglytuff',
        '|-immune|p2a: Wigglytuff',
        '|move|p2a: Wigglytuff|Teleport|p2a: Wigglytuff',
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
        '|win|Player 1',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('LeechSeed', () => {
      const battle = startBattle([SRF, SRF, MISS, SRF, HIT, SRF, SRF, HIT, HIT, SRF, HIT], [
        {species: 'Venusaur', evs, moves: ['Leech Seed']},
        {species: 'Exeggutor', evs, moves: ['Leech Seed', 'Teleport']},
      ], [
        {species: 'Gengar', evs, moves: ['Leech Seed', 'Substitute', 'Night Shade']},
        {species: 'Slowbro', evs, moves: ['Teleport']},
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

      expectLog(battle, [
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
        '|move|p1a: Exeggutor|Teleport|p1a: Exeggutor',
        '|move|p2a: Slowbro|Teleport|p2a: Slowbro',
        '|-damage|p2a: Slowbro|0 fnt|[from] Leech Seed|[of] p1a: Exeggutor',
        '|-heal|p1a: Exeggutor|337/393|[silent]',
        '|faint|p2a: Slowbro',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('PayDay', () => {
      const battle = startBattle([SRF, HIT, NO_CRIT, MAX_DMG], [
        {species: 'Meowth', evs, moves: ['Pay Day']},
      ], [
        {species: 'Slowpoke', evs, moves: ['Teleport']},
      ]);

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 43);

      expectLog(battle, [
        '|move|p1a: Meowth|Pay Day|p2a: Slowpoke',
        '|-damage|p2a: Slowpoke|340/383',
        '|-fieldactivate|move: Pay Day',
        '|move|p2a: Slowpoke|Teleport|p2a: Slowpoke',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Rage', () => {
      const battle = startBattle([
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, MISS,
        SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, DISABLE_DURATION(5), DISABLE_MOVE(1, 2),
        SRF, SRF, MISS,
      ], [
        {species: 'Charmeleon', evs, moves: ['Rage', 'Flamethrower']},
        {species: 'Doduo', evs, moves: ['Drill Peck']},
      ], [
        {species: 'Grimer', evs, moves: ['Pound', 'Disable', 'Self-Destruct']},
      ]);

      let p1hp = battle.p1.pokemon[0].hp;
      let p2hp = battle.p2.pokemon[0].hp;

      let pp = battle.p1.pokemon[0].moveSlots[0].pp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 35);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 17);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp -= 1);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      // expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(1);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 2');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      // expect(battle.p1.pokemon[0].boosts.atk).toBe(3);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
      expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 25);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);

      battle.makeChoices('move 1', 'move 3');
      expect(battle.p1.pokemon[0].hp).toBe(p1hp);
      // expect(battle.p1.pokemon[0].boosts.atk).toBe(4);
      expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
      expect(battle.p2.pokemon[0].hp).toBe(0);
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(pp);

      expectLog(battle, [
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
        '|turn|3',
        '|move|p1a: Charmeleon|Rage|p2a: Grimer|[from]Rage',
        '|-damage|p2a: Grimer|296/363',
        '|move|p2a: Grimer|Disable|p1a: Charmeleon',
        '|-boost|p1a: Charmeleon|atk|1|[from] Rage',
        '|-start|p1a: Charmeleon|Disable|Rage',
        '|turn|4',
        '|cant|p1a: Charmeleon|Disable|Rage',
        '|move|p2a: Grimer|Self-Destruct|p1a: Charmeleon|[miss]',
        '|-miss|p2a: Grimer',
        '|faint|p2a: Grimer',
        '|win|Player 1',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test.todo('Mimic');

    test('LightScreen', () => {
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, HIT, CRIT, MIN_DMG,
      ], [
        {species: 'Chansey', evs, moves: ['Light Screen', 'Teleport']},
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

      expectLog(battle, [
        '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
        '|-damage|p1a: Chansey|658/703',
        '|move|p1a: Chansey|Light Screen|p1a: Chansey',
        '|-start|p1a: Chansey|Light Screen',
        '|turn|2',
        '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
        '|-damage|p1a: Chansey|635/703',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|3',
        '|move|p2a: Vaporeon|Water Gun|p1a: Chansey',
        '|-crit|p1a: Chansey',
        '|-damage|p1a: Chansey|548/703',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|4',
        '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
        '|-activate|p2a: Vaporeon|move: Haze',
        '|-clearallboost|[silent]',
        '|-end|p1a: Chansey|lightscreen|[silent]',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|5',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Reflect', () => {
      const battle = startBattle([
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, HIT, NO_CRIT, MIN_DMG,
        SRF, HIT, CRIT, MIN_DMG,
      ], [
        {species: 'Chansey', evs, moves: ['Reflect', 'Teleport']},
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

      expectLog(battle, [
        '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
        '|-damage|p1a: Chansey|649/703',
        '|move|p1a: Chansey|Reflect|p1a: Chansey',
        '|-start|p1a: Chansey|Reflect',
        '|turn|2',
        '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
        '|-damage|p1a: Chansey|621/703',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|3',
        '|move|p2a: Vaporeon|Tackle|p1a: Chansey',
        '|-crit|p1a: Chansey',
        '|-damage|p1a: Chansey|517/703',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|4',
        '|move|p2a: Vaporeon|Haze|p2a: Vaporeon',
        '|-activate|p2a: Vaporeon|move: Haze',
        '|-clearallboost|[silent]',
        '|-end|p1a: Chansey|reflect|[silent]',
        '|move|p1a: Chansey|Teleport|p1a: Chansey',
        '|turn|5',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test.todo('Haze');
    test.todo('Bide');
    test.todo('Metronome');
    test.todo('MirrorMove');

    test('Explode', () => {
      const battle = startBattle([
        SRF, HIT, SS_MOD,
        SRF, HIT, NO_CRIT, MAX_DMG,
        SRF, HIT, NO_CRIT, MAX_DMG,
        SRF,
      ], [
        {species: 'Electrode', level: 80, evs, moves: ['Explosion', 'Toxic']},
        {species: 'Onix', evs, moves: ['Self-Destruct']},
      ], [
        {species: 'Chansey', evs, moves: ['Substitute', 'Teleport']},
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

      expectLog(battle, [
        '|move|p1a: Electrode|Toxic|p2a: Chansey',
        '|-status|p2a: Chansey|tox',
        '|move|p2a: Chansey|Substitute|p2a: Chansey',
        '|-start|p2a: Chansey|Substitute',
        '|-damage|p2a: Chansey|528/703 tox',
        '|-damage|p2a: Chansey|485/703 tox|[from] psn',
        '|turn|2',
        '|move|p1a: Electrode|Explosion|p2a: Chansey',
        '|-end|p2a: Chansey|Substitute',
        '|move|p2a: Chansey|Teleport|p2a: Chansey',
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
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Swift', () => {
      const battle = startBattle([SRF, SRF, SRF, NO_CRIT, MIN_DMG, SS_RES, GLM], [
        {species: 'Eevee', evs, moves: ['Swift']},
      ], [
        {species: 'Diglett', evs, moves: ['Dig']},
      ]);

      const p2hp = battle.p2.pokemon[0].hp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p2.pokemon[0].hp).toBe(p2hp - 91);

      expectLog(battle, [
        '|move|p2a: Diglett|Dig||[still]',
        '|-prepare|p2a: Diglett|Dig',
        '|move|p1a: Eevee|Swift|p2a: Diglett',
        '|-damage|p2a: Diglett|132/223',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Transform', () => {
      const battle = startBattle([SRF, SRF, SS_RES, GLM, GLM, GLM, SRF, SRF, SS_RUN, MISS], [
        {species: 'Mew', level: 50, moves: ['Swords Dance', 'Transform']},
      ], [
        {species: 'Articuno', evs, moves: ['Agility', 'Fly']},
      ]);
      const pp = battle.p1.pokemon[0].moveSlots[1].pp;

      battle.makeChoices('move 1', 'move 1');
      expect(battle.p1.pokemon[0].boosts.atk).toBe(2);
      expect(battle.p2.pokemon[0].boosts.spe).toBe(2);

      // Pokémon Showdown is bugged and doesn't let Transform hit while Flying
      battle.makeChoices('move 2', 'move 2');

      // Transform should copy species, types, stats, and boosts but not level or HP
      battle.makeChoices('move 2', 'move 1');
      // expect(battle.p1.pokemon[0].baseMoveSlots[1].pp).toBe(pp - 1);
      expect(battle.p1.pokemon[0].baseMoveSlots[1].pp).toBe(pp - 2);

      expect(battle.p1.pokemon[0].species).toEqual(battle.p2.pokemon[0].species);
      expect(battle.p1.pokemon[0].types).toEqual(battle.p2.pokemon[0].types);
      expect(battle.p1.pokemon[0].level).toBe(50);
      expect(battle.p1.pokemon[0].storedStats).toEqual(battle.p2.pokemon[0].storedStats);
      expect(battle.p1.pokemon[0].boosts).toEqual(battle.p2.pokemon[0].boosts);

      expect(battle.p1.pokemon[0].moveSlots).toHaveLength(2);
      expect(battle.p1.pokemon[0].moveSlots[0].move).toBe('Agility');
      expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(5);
      expect(battle.p1.pokemon[0].moveSlots[1].move).toBe('Fly');
      expect(battle.p1.pokemon[0].moveSlots[1].pp).toBe(5);

      expectLog(battle, [
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
        '|move|p2a: Articuno|Fly|p1a: Mew|[from]Fly|[miss]',
        '|-miss|p2a: Articuno',
        '|move|p1a: Mew|Transform|p2a: Articuno',
        '|-transform|p1a: Mew|p2a: Articuno',
        '|turn|4',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });

    test('Conversion', () => {
      const battle = startBattle([SRF], [
        {species: 'Porygon', evs, moves: ['Conversion']},
      ], [
        {species: 'Slowbro', evs, moves: ['Teleport']},
      ]);

      battle.makeChoices('move 1', 'move 1');

      expectLog(battle, [
        '|move|p1a: Porygon|Conversion|p2a: Slowbro',
        '|-start|p1a: Porygon|typechange|Water/Psychic|[from] move: Conversion|[of] p2a: Slowbro',
        '|move|p2a: Slowbro|Teleport|p2a: Slowbro',
        '|turn|2',
      ]);
      expect((battle.prng as FixedRNG).exhausted()).toBe(true);
    });
  });

  test('Substitute', () => {
    const battle = startBattle([SRF, HIT, SRF, HIT, NO_CRIT, MIN_DMG, SRF, HIT, SRF, HIT], [
      {species: 'Mewtwo', evs, moves: ['Substitute', 'Teleport']},
      {species: 'Abra', level: 2, moves: ['Substitute']},
    ], [
      {species: 'Electabuzz', moves: ['Flash', 'Strength']},
    ]);

    battle.p1.pokemon[1].hp = 3;
    battle.p1.pokemon[1].maxhp = 3;

    let mewtwo = battle.p1.pokemon[0].hp;
    const mew = battle.p1.pokemon[1].hp;

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
    expect(battle.p1.pokemon[0].hp).toBe(mew);
    expect(battle.p1.pokemon[0].volatiles['substitute']).toBeUndefined();

    // Can get "free" Substitutes if 3 or less max HP
    battle.makeChoices('move 1', 'move 1');
    expect(battle.p1.pokemon[0].hp).toBe(mew);
    expect(battle.p1.pokemon[0].volatiles['substitute'].hp).toBe(1);

    expectLog(battle, [
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
    expect((battle.prng as FixedRNG).exhausted()).toBe(true);
  });

  if (gen.num === 1) {
    describe('Gen 1', () => {
      test('0 damage glitch', () => {
        const battle = startBattle([
          SRF, SRF, SRF, HIT, HIT, NO_CRIT,
          SRF, SRF, HIT,
          SRF, SRF, SRF, HIT, HIT, NO_CRIT,
        ], [
          {species: 'Bulbasaur', evs, moves: ['Growl']},
        ], [
          {species: 'Bellsprout', level: 2, moves: ['Vine Whip']},
          {species: 'Chansey', level: 2, moves: ['Vine Whip']},
        ]);

        const p1hp = battle.p1.pokemon[0].hp;

        battle.makeChoices('move 1', 'move 1');
        // expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
        expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 1);
        battle.makeChoices('move 1', 'switch 2');
        battle.makeChoices('move 1', 'move 1');
        // expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
        expect(battle.p1.pokemon[0].hp).toEqual(p1hp - 1);

        expectLog(battle, [
          '|move|p1a: Bulbasaur|Growl|p2a: Bellsprout',
          '|-unboost|p2a: Bellsprout|atk|1',
          '|move|p2a: Bellsprout|Vine Whip|p1a: Bulbasaur',
          '|-resisted|p1a: Bulbasaur',
          '|-damage|p1a: Bulbasaur|292/293',
          '|turn|2',
          '|switch|p2a: Chansey|Chansey, L2|22/22',
          '|move|p1a: Bulbasaur|Growl|p2a: Chansey',
          '|-unboost|p2a: Chansey|atk|1',
          '|turn|3',
          '|move|p1a: Bulbasaur|Growl|p2a: Chansey',
          '|-unboost|p2a: Chansey|atk|1',
          '|move|p2a: Chansey|Vine Whip|p1a: Bulbasaur',
          '|-resisted|p1a: Bulbasaur',
          '|-damage|p1a: Bulbasaur|292/293',
          '|turn|4',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('1/256 miss glitch', () => {
        const battle = startBattle([SRF, SRF, MISS, MISS], [
          {species: 'Jigglypuff', evs, moves: ['Pound']},
        ], [
          {species: 'Nidoran-F', evs, moves: ['Scratch']},
        ]);

        const p1hp = battle.p1.pokemon[0].hp;
        const p2hp = battle.p2.pokemon[0].hp;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toEqual(p1hp);
        expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

        expectLog(battle, [
          '|move|p2a: Nidoran-F|Scratch|p1a: Jigglypuff|[miss]',
          '|-miss|p2a: Nidoran-F',
          '|move|p1a: Jigglypuff|Pound|p2a: Nidoran-F|[miss]',
          '|-miss|p1a: Jigglypuff',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test.todo('Bide errors');
      test.todo('Counter glitches');

      test('Freeze top move selection glitch', () => {
        const NO_BRN = {key: FRZ.key, value: FRZ.value + 1};
        const battle = startBattle([
          SRF, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD,
          SRF, HIT, NO_CRIT, MIN_DMG, NO_BRN,
          SRF, HIT, NO_CRIT, MIN_DMG, NO_BRN,
        ], [
          {species: 'Slowbro', evs, moves: ['Psychic', 'Amnesia', 'Teleport']},
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

        expectLog(battle, [
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
          '|move|p1a: Slowbro|Teleport|p1a: Slowbro',
          '|turn|4',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test.todo('Haze glitch');

      test('Toxic counter glitches', () => {
        const BRN = {key: HIT.key, value: ranged(77, 256) - 1};
        const battle = startBattle([
          SRF, HIT, SS_MOD, SS_MOD, SLP(5), SRF, HIT, SRF, HIT, NO_CRIT, MIN_DMG, BRN, SS_MOD,
        ], [
          {species: 'Venusaur', evs, moves: ['Toxic', 'Leech Seed', 'Teleport', 'Fire Blast']},
        ], [
          {species: 'Clefable', evs, moves: ['Teleport', 'Rest']},
        ]);

        battle.p2.pokemon[0].hp = 392;

        battle.makeChoices('move 1', 'move 2');
        expect(battle.p2.active[0].volatiles['residualdmg'].counter).toBe(0);
        battle.makeChoices('move 3', 'move 1');
        expect(battle.p2.active[0].volatiles['residualdmg'].counter).toBe(0);
        battle.makeChoices('move 2', 'move 1');
        expect(battle.p2.active[0].volatiles['residualdmg'].counter).toBe(1);
        battle.makeChoices('move 4', 'move 1');
        expect(battle.p2.active[0].volatiles['residualdmg'].counter).toBe(3);

        expectLog(battle, [
          '|move|p1a: Venusaur|Toxic|p2a: Clefable',
          '|-status|p2a: Clefable|tox',
          '|move|p2a: Clefable|Rest|p2a: Clefable',
          '|-status|p2a: Clefable|slp|[from] move: Rest',
          '|-heal|p2a: Clefable|393/393 slp|[silent]',
          '|turn|2',
          '|move|p1a: Venusaur|Teleport|p1a: Venusaur',
          '|cant|p2a: Clefable|slp',
          '|turn|3',
          '|move|p1a: Venusaur|Leech Seed|p2a: Clefable',
          '|-start|p2a: Clefable|move: Leech Seed',
          '|-damage|p2a: Clefable|369/393 slp|[from] Leech Seed|[of] p1a: Venusaur',
          '|-curestatus|p2a: Clefable|slp|[msg]',
          '|turn|4',
          '|move|p1a: Venusaur|Fire Blast|p2a: Clefable',
          '|-damage|p2a: Clefable|273/393',
          '|-status|p2a: Clefable|brn',
          '|move|p2a: Clefable|Teleport|p2a: Clefable',
          '|-damage|p2a: Clefable|225/393 brn|[from] brn',
          '|-damage|p2a: Clefable|153/393 brn|[from] Leech Seed|[of] p1a: Venusaur',
          '|turn|5',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Defrost move forcing', () => {
        const NO_BRN = {key: FRZ.key, value: FRZ.value + 1};
        const battle = startBattle([
          SRF, HIT, NO_CRIT, MIN_DMG,
          SRF, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD,
          SRF, SRF, HIT, NO_CRIT, MIN_DMG, NO_BRN, HIT, NO_CRIT, MIN_DMG,
        ], [
          {species: 'Hypno', level: 50, evs, moves: ['Teleport', 'Ice Punch', 'Fire Punch']},
        ], [
          {species: 'Bulbasaur', level: 6, evs, moves: ['Vine Whip']},
          {species: 'Poliwrath', level: 40, evs, moves: ['Surf', 'Water Gun']},
        ]);

        let p1hp = battle.p1.pokemon[0].hp;
        let p2hp = battle.p2.pokemon[1].hp;

        // Set up P2's last_selected_move to be Vine Whip
        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 3);

        // Switching clears last_used_move but not last_selected_move
        battle.makeChoices('move 2', 'switch 2');
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 23);
        expect(battle.p2.pokemon[0].status).toBe('frz');

        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        // After defrosting, Poliwrath will appear to use Surf to P1 and Vine Whip to P2
        battle.makeChoices('move 3', 'move 2');
        expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 23);
        expect(battle.p2.pokemon[0].status).toBe('');

        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        expectLog(battle, [
          '|move|p1a: Hypno|Teleport|p1a: Hypno',
          '|move|p2a: Bulbasaur|Vine Whip|p1a: Hypno',
          '|-damage|p1a: Hypno|188/191',
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
          '|-damage|p1a: Hypno|176/191',
          '|turn|4',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Division by 0', () => {
        //  Attack/Special > 255 vs. Defense/Special stat < 4.
        {
          const battle = startBattle([
            SRF, SRF, HIT, SRF, HIT,
            SRF, SRF, MISS,
            SRF, SRF, MISS,
            SRF, SRF, HIT, NO_CRIT, MIN_DMG,
          ], [
            {species: 'Cloyster', level: 65, evs, moves: ['Screech']},
            {species: 'Parasect', level: 100, evs, moves: ['Swords Dance', 'Leech Life']},
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

          expectLog(battle, [
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
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
        // Defense/Special stat is 512 or 513 + Reflect/Light Screen.
        {
          const def12 = {hp: 0, atk: 0, def: 12, spa: 0, spd: 0, spe: 0};
          const battle = startBattle([
            SRF, HIT, NO_CRIT, MAX_DMG,
            SRF, HIT, NO_CRIT, MAX_DMG,
            SRF, HIT,
            SRF, HIT, NO_CRIT, MAX_DMG,
          ], [
            {species: 'Cloyster', level: 64, evs: def12, moves: ['Withdraw', 'Reflect']},
          ], [
            {species: 'Pidgey', level: 5, moves: ['Gust', 'Sand-Attack']},
          ]);

          let p1hp = battle.p1.pokemon[0].hp;

          expect(battle.p1.pokemon[0].storedStats.def).toBe(256);

          battle.makeChoices('move 1', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 4);

          battle.makeChoices('move 1', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 4);
          expect(battle.p1.pokemon[0].modifiedStats!.def).toBe(512);

          battle.makeChoices('move 2', 'move 2');

          // Division by 0 should occur
          battle.makeChoices('move 2', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);

          expectLog(battle, [
            '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
            '|-boost|p1a: Cloyster|def|1',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|153/157',
            '|turn|2',
            '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
            '|-boost|p1a: Cloyster|def|1',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|149/157',
            '|turn|3',
            '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
            '|-start|p1a: Cloyster|Reflect',
            '|move|p2a: Pidgey|Sand Attack|p1a: Cloyster',
            '|-unboost|p1a: Cloyster|accuracy|1',
            '|turn|4',
            '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
            '|-fail|p1a: Cloyster',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|137/157',
            '|turn|5',
          ]);
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
        // Defense/Special stat >= 514 + Reflect/Light Screen.
        {
          const def20 = {hp: 0, atk: 0, def: 20, spa: 0, spd: 0, spe: 0};
          const battle = startBattle([
            SRF, HIT, NO_CRIT, MAX_DMG,
            SRF, HIT, NO_CRIT, MAX_DMG,
            SRF, HIT,
            SRF, HIT, NO_CRIT, MAX_DMG,
          ], [
            {species: 'Cloyster', level: 64, evs: def20, moves: ['Withdraw', 'Reflect']},
          ], [
            {species: 'Pidgey', level: 5, moves: ['Gust', 'Sand-Attack']},
          ]);

          let p1hp = battle.p1.pokemon[0].hp;

          expect(battle.p1.pokemon[0].storedStats.def).toBe(257);

          battle.makeChoices('move 1', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 4);

          battle.makeChoices('move 1', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 4);
          expect(battle.p1.pokemon[0].modifiedStats!.def).toBe(514);

          battle.makeChoices('move 2', 'move 2');

          // Division by 0 should occur
          battle.makeChoices('move 2', 'move 1');
          expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 12);

          expectLog(battle, [
            '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
            '|-boost|p1a: Cloyster|def|1',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|153/157',
            '|turn|2',
            '|move|p1a: Cloyster|Withdraw|p1a: Cloyster',
            '|-boost|p1a: Cloyster|def|1',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|149/157',
            '|turn|3',
            '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
            '|-start|p1a: Cloyster|Reflect',
            '|move|p2a: Pidgey|Sand Attack|p1a: Cloyster',
            '|-unboost|p1a: Cloyster|accuracy|1',
            '|turn|4',
            '|move|p1a: Cloyster|Reflect|p1a: Cloyster',
            '|-fail|p1a: Cloyster',
            '|move|p2a: Pidgey|Gust|p1a: Cloyster',
            '|-damage|p1a: Cloyster|137/157',
            '|turn|5',
          ]);
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
      });

      test('Hyper Beam + Freeze permanent helplessness', () => {
        const NO_BRN = {key: FRZ.key, value: FRZ.value + 1};
        const battle = startBattle([
          SRF, SRF, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, FRZ, SS_MOD,
          SRF, SRF,
          SRF, HIT, NO_CRIT, MIN_DMG,
          SRF, SRF, HIT, NO_CRIT, MIN_DMG, NO_BRN, SRF,
          SRF, SRF, HIT, NO_CRIT, MIN_DMG, NO_BRN, HIT, NO_CRIT, MIN_DMG,
        ], [
          {species: 'Chansey', evs, moves: ['Hyper Beam', 'Soft-Boiled']},
          {species: 'Blastoise', evs, moves: ['Hydro Pump']},
        ], [
          {species: 'Lapras', level: 56, evs, moves: ['Blizzard', 'Haze']},
          {species: 'Charizard', evs, moves: ['Flamethrower']},
        ]);

        let chansey = battle.p1.pokemon[0].hp;
        let lapras = battle.p2.pokemon[0].hp;
        let charizard = battle.p2.pokemon[1].hp;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].status).toBe('frz');
        expect(battle.p2.pokemon[0].hp).toBe(lapras -= 120);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);

        // After thawing Chansey should still be stuck recharging
        battle.makeChoices('move 1', 'move 2');
        expect(battle.p1.pokemon[0].status).toBe('');
        expect(battle.p2.pokemon[0].hp).toBe(lapras);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

        battle.makeChoices('move 1', 'switch 2');
        expect(battle.p2.pokemon[0].hp).toBe(charizard -= 69);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['move 1']);

        // Using a Fire-type move after should do nothing to fix the problem
        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(chansey -= 129);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(chansey -= 90);
        expect(battle.p2.pokemon[0].hp).toBe(charizard -= 69);

        expectLog(battle, [
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
          '|-end|p1a: Chansey|mustrecharge|[silent]',
          '|turn|3',
          '|switch|p2a: Charizard|Charizard|359/359',
          '|move|p1a: Chansey|Hyper Beam|p2a: Charizard',
          '|-damage|p2a: Charizard|290/359',
          '|-mustrecharge|p1a: Chansey',
          '|turn|4',
          '|move|p2a: Charizard|Flamethrower|p1a: Chansey',
          '|-damage|p1a: Chansey|574/703',
          '|cant|p1a: Chansey|recharge',
          '|turn|5',
          '|move|p2a: Charizard|Flamethrower|p1a: Chansey',
          '|-damage|p1a: Chansey|484/703',
          '|move|p1a: Chansey|Hyper Beam|p2a: Charizard',
          '|-damage|p2a: Charizard|221/359',
          '|-mustrecharge|p1a: Chansey',
          '|turn|6',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Hyper Beam + Sleep move glitch', () => {
        const battle = startBattle([
          SRF, SRF, HIT, SS_MOD, HIT, NO_CRIT, MIN_DMG,
          SRF, SRF, SS_MOD, SLP(1), SRF,
          SRF, SRF, SRF, HIT, SS_MOD, MISS,
        ], [
          {species: 'Hypno', evs, moves: ['Toxic', 'Hypnosis', 'Teleport']},
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
        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 32);
        expect(battle.p2.pokemon[0].status).toBe('tox');
        // expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(2);
        expect(battle.p2.pokemon[0].volatiles['residualdmg'].counter).toBe(1);

        expectLog(battle, [
          '|move|p1a: Hypno|Toxic|p2a: Snorlax',
          '|-status|p2a: Snorlax|tox',
          '|move|p2a: Snorlax|Hyper Beam|p1a: Hypno',
          '|-damage|p1a: Hypno|156/373',
          '|-damage|p2a: Snorlax|491/523 tox|[from] psn',
          '|-mustrecharge|p2a: Snorlax',
          '|turn|2',
          '|move|p1a: Hypno|Hypnosis|p2a: Snorlax',
          '|-status|p2a: Snorlax|slp|[from] move: Hypnosis',
          '|cant|p2a: Snorlax|slp',
          '|turn|3',
          '|move|p1a: Hypno|Teleport|p1a: Hypno',
          '|-curestatus|p2a: Snorlax|slp|[msg]',
          '|turn|4',
          '|move|p1a: Hypno|Toxic|p2a: Snorlax',
          '|-status|p2a: Snorlax|tox',
          '|move|p2a: Snorlax|Hyper Beam|p1a: Hypno|[miss]',
          '|-miss|p2a: Snorlax',
          '|-damage|p2a: Snorlax|459/523 tox|[from] psn',
          '|turn|5',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Hyper Beam automatic selection glitch', () => {
        const battle = startBattle([SRF, SRF, MISS, HIT, NO_CRIT, MIN_DMG, SRF, SRF, MISS, SRF], [
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

        expectLog(battle, [
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
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Invulnerability glitch', () => {
        const NO_PAR = {key: HIT.key, value: ranged(26, 256)};
        const battle = startBattle([
          SRF, HIT, SS_MOD,
          SRF, SRF, PAR_CAN, SS_RES, GLM,
          GLM, GLM, SRF, SRF, PAR_CANT, HIT, NO_CRIT, MIN_DMG, NO_PAR,
          SRF, PAR_CAN, SRF, NO_CRIT, MIN_DMG,
          SRF, SRF, PAR_CAN, SS_RES, GLM,
          GLM, GLM, SRF, SRF, PAR_CAN, SS_RUN, HIT, NO_CRIT, MIN_DMG, HIT, NO_CRIT, MIN_DMG, NO_PAR,
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
        // expect(battle.p1.pokemon[0].hp).toBe(p1hp);
        expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);

        // Swift should still be able to hit
        battle.makeChoices('move 1', 'move 3');
        expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 11);

        battle.makeChoices('move 2', 'move 2');

        // Successfully completing Fly removes Invulnerability
        battle.makeChoices('move 1', 'move 2');
        expect(battle.p1.pokemon[0].hp).toBe(p1hp -= 25);
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 130);

        expectLog(battle, [
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
          '|move|p2a: Pikachu|Thunder Shock|p1a: Fearow',
          '|-supereffective|p1a: Fearow',
          '|-damage|p1a: Fearow|308/333 par',
          '|turn|4',
          '|move|p1a: Fearow|Agility|p1a: Fearow',
          '|-boost|p1a: Fearow|spe|2',
          '|move|p2a: Pikachu|Swift|p1a: Fearow',
          '|-damage|p1a: Fearow|297/333 par',
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
          '|-damage|p1a: Fearow|272/333 par',
          '|turn|7',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Stat modification errors', () => {
        {
          const battle = startBattle([
            SRF, SRF, HIT, HIT, SS_MOD, SRF, PAR_CAN, HIT, SRF, PAR_CAN, HIT,
          ], [
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

          expectLog(battle, [
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
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
        {
          const battle = startBattle([
            SRF, HIT, SS_MOD,
            SRF, PAR_CAN, SRF, HIT,
            SRF, PAR_CANT, SRF, HIT,
            SRF, SRF, HIT, PAR_CANT,
          ], [
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

          expectLog(battle, [
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
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
      });

      test('Stat down modifier overflow glitch', () => {
        const proc = {key: HIT.key, value: ranged(85, 256) - 1};
        const no_proc = {key: proc.key, value: proc.value + 1};
        // 342 -> 1026
        {
          const spc342 = {...evs, spa: 12, spd: 12};
          const battle = startBattle([
            SRF, HIT, NO_CRIT, MIN_DMG, proc,
            SRF, HIT, NO_CRIT, MIN_DMG, no_proc,
          ], [
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
          // expect(battle.p2.pokemon[0].boosts.spa).toBe(5);
          expect(battle.p2.pokemon[0].boosts.spa).toBe(6);

          battle.makeChoices('move 2', 'move 2');
          expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 2);
          // expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(1026);
          expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
          // expect(battle.p2.pokemon[0].boosts.spa).toBe(4);
          expect(battle.p2.pokemon[0].boosts.spa).toBe(5);

          // Division by 0
          battle.makeChoices('move 2', 'move 2');
          expect(battle.p2.pokemon[0].hp).toBe(p2hp);

          expectLog(battle, [
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|2',
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|3',
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|4',
            '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
            '|-fail|p2a: Mewtwo',
            '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
            '|-resisted|p2a: Mewtwo',
            '|-damage|p2a: Mewtwo|408/410',
            '|-unboost|p2a: Mewtwo|spd|1',
            '|-unboost|p2a: Mewtwo|spa|1',
            '|turn|5',
            '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
            '|-heal|p2a: Mewtwo|410/410',
            '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
            '|-resisted|p2a: Mewtwo',
            '|-damage|p2a: Mewtwo|408/410',
            '|turn|6',
          ]);
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
        // 343 -> 1029
        {
          const battle = startBattle([
            SRF, HIT, NO_CRIT, MIN_DMG, proc,
            SRF, HIT, NO_CRIT, MIN_DMG, no_proc,
          ], [
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
          // expect(battle.p2.pokemon[0].boosts.spa).toBe(5);
          expect(battle.p2.pokemon[0].boosts.spa).toBe(6);

          battle.makeChoices('move 2', 'move 2');
          expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 2);
          // expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(1029);
          expect(battle.p2.pokemon[0].modifiedStats!.spa).toBe(999);
          // expect(battle.p2.pokemon[0].boosts.spa).toBe(4);
          expect(battle.p2.pokemon[0].boosts.spa).toBe(5);

          // Overflow means Mewtwo gets KOed
          battle.makeChoices('move 2', 'move 2');
          // expect(battle.p2.pokemon[0].hp).toBe(0);
          expect(battle.p2.pokemon[0].hp).toBe(p2hp);

          expectLog(battle, [
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|2',
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|3',
            '|move|p2a: Mewtwo|Amnesia|p2a: Mewtwo',
            '|-boost|p2a: Mewtwo|spd|2',
            '|-boost|p2a: Mewtwo|spa|2',
            '|move|p1a: Porygon|Recover|p1a: Porygon',
            '|-fail|p1a: Porygon',
            '|turn|4',
            '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
            '|-fail|p2a: Mewtwo',
            '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
            '|-resisted|p2a: Mewtwo',
            '|-damage|p2a: Mewtwo|350/352',
            '|-unboost|p2a: Mewtwo|spd|1',
            '|-unboost|p2a: Mewtwo|spa|1',
            '|turn|5',
            '|move|p2a: Mewtwo|Recover|p2a: Mewtwo',
            '|-heal|p2a: Mewtwo|352/352',
            '|move|p1a: Porygon|Psychic|p2a: Mewtwo',
            '|-resisted|p2a: Mewtwo',
            '|-damage|p2a: Mewtwo|350/352',
            '|turn|6',
          ]);
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
      });

      test('Struggle bypassing / Switch PP underflow', () => {
        const wrap = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MAX};
        const rewrap = {key: ['Battle.sample', 'BattleActions.runMove'], value: MAX};
        const battle = startBattle([
          SRF, HIT, NO_CRIT, MIN_DMG, wrap, SRF, HIT, NO_CRIT, MIN_DMG, rewrap,
        ], [
          {species: 'Victreebel', evs, moves: ['Wrap', 'Vine Whip']},
          {species: 'Seel', evs, moves: ['Bubble']},
        ], [
          {species: 'Kadabra', evs, moves: ['Teleport']},
          {species: 'Mr. Mime', evs, moves: ['Teleport']},
        ], b => {
          b.p1.pokemon[0].moveSlots[0].pp = 1;
        });

        const kadabra = battle.p2.pokemon[0].hp;
        const mrmime = battle.p2.pokemon[1].hp;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(0);
        expect(battle.p2.pokemon[0].hp).toBe(kadabra - 22);

        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1']);

        battle.makeChoices('move 1', 'switch 2');
        expect(battle.p1.pokemon[0].moveSlots[0].pp).toBe(63);
        expect(battle.p2.pokemon[0].hp).toBe(mrmime - 16);

        expectLog(battle, [
          '|switch|p1a: Victreebel|Victreebel|363/363',
          '|switch|p2a: Kadabra|Kadabra|283/283',
          '|turn|1',
          '|move|p2a: Kadabra|Teleport|p2a: Kadabra',
          '|move|p1a: Victreebel|Wrap|p2a: Kadabra',
          '|-damage|p2a: Kadabra|261/283',
          '|turn|2',
          '|switch|p2a: Mr. Mime|Mr. Mime|283/283',
          '|move|p1a: Victreebel|Wrap|p2a: Mr. Mime',
          '|-damage|p2a: Mr. Mime|267/283',
          '|turn|3',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Trapping sleep glitch', () => {
        const wrap = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MIN};
        const battle = startBattle([
          SRF, SRF, HIT, NO_CRIT, MIN_DMG, wrap,
          SRF, SRF,
          SRF, SRF, HIT, SS_MOD, SLP(5),
          SRF, SRF, HIT,
        ], [
          {species: 'Weepinbell', evs, moves: ['Wrap', 'Sleep Powder']},
          {species: 'Gloom', evs, moves: ['Absorb']},
        ], [
          {species: 'Sandshrew', evs, moves: ['Scratch', 'Sand Attack']},
          {species: 'Magnemite', evs, moves: ['Thunder Shock']},
        ]);

        let p2hp = battle.p2.pokemon[0].hp;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 11);
        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1']);
        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 11);
        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        battle.makeChoices('move 2', 'move 1');
        expect(battle.p2.pokemon[0].status).toBe('slp');
        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
        // expect(gen1.Choices.sim(battle, 'p2')).toEqual([]);
        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        // Should not have a turn, can only pass!
        battle.makeChoices('move 2', 'move 1');
        expect(gen1.Choices.sim(battle, 'p1')).toEqual(['switch 2', 'move 1', 'move 2']);
        // expect(gen1.Choices.sim(battle, 'p2')).toEqual([]);
        expect(gen1.Choices.sim(battle, 'p2')).toEqual(['switch 2', 'move 1', 'move 2']);

        expectLog(battle, [
          '|move|p1a: Weepinbell|Wrap|p2a: Sandshrew',
          '|-damage|p2a: Sandshrew|292/303',
          '|cant|p2a: Sandshrew|partiallytrapped',
          '|turn|2',
          '|move|p1a: Weepinbell|Wrap|p2a: Sandshrew|[from]Wrap',
          '|-damage|p2a: Sandshrew|281/303',
          '|cant|p2a: Sandshrew|partiallytrapped',
          '|turn|3',
          '|move|p1a: Weepinbell|Sleep Powder|p2a: Sandshrew',
          '|-status|p2a: Sandshrew|slp|[from] move: Sleep Powder',
          '|cant|p2a: Sandshrew|slp',
          '|turn|4',
          '|move|p1a: Weepinbell|Sleep Powder|p2a: Sandshrew',
          '|-fail|p2a: Sandshrew|slp',
          '|cant|p2a: Sandshrew|slp',
          '|turn|5',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Partial trapping move Mirror Move glitch', () => {
        const wrap = {key: ['Battle.durationCallback', 'Pokemon.addVolatile'], value: MIN};
        const battle = startBattle(
          [SRF, MISS, SRF, SRF, HIT, NO_CRIT, MAX_DMG, wrap, SRF],
          [{species: 'Pidgeot', evs, moves: ['Agility', 'Mirror Move']}],
          [{species: 'Moltres', evs, moves: ['Leer', 'Fire Spin']},
            {species: 'Drowzee', evs, moves: ['Pound']}]
        );

        const p2hp1 = battle.p2.pokemon[0].hp;
        const p2hp2 = battle.p2.pokemon[1].hp;

        battle.makeChoices('move 1', 'move 2');
        battle.makeChoices('move 2', 'move 1');
        battle.makeChoices('move 2', 'switch 2');

        expect(battle.p2.pokemon[0].hp).toEqual(p2hp2);
        expect(battle.p2.pokemon[1].hp).toEqual(p2hp1 - 5);

        expect(filter(battle.log)).toEqual([
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
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Rage and Thrash / Petal Dance accuracy bug', () => {
        const hit = (n: number) => ({key: HIT.key, value: ranged(n, 256) - 1});
        const miss = (n: number) => ({key: HIT.key, value: hit(n).value + 1});
        const battle = startBattle([
          SRF, SRF, hit(255), NO_CRIT, MIN_DMG, THRASH(4),
          SRF, SRF, SRF, hit(168), NO_CRIT, MIN_DMG,
          SRF, SRF, SRF, miss(84), NO_CRIT, MIN_DMG, // should miss!
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
        expect(battle.p2.pokemon[0].hp).toBe(p2hp -= 22);

        expectLog(battle, [
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
          '|move|p1a: Nidoking|Thrash|p2a: Onix|[from]Thrash',
          '|-resisted|p2a: Onix',
          '|-damage|p2a: Onix|207/273',
          '|move|p2a: Onix|Double Team|p2a: Onix',
          '|-boost|p2a: Onix|evasion|1',
          '|turn|4',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Substitute HP drain bug', () => {
        const battle = startBattle([SRF, HIT, NO_CRIT, MIN_DMG], [
          {species: 'Butterfree', evs, moves: ['Mega Drain']},
        ], [
          {species: 'Jolteon', evs, moves: ['Substitute']},
        ]);

        const p2hp = battle.p2.pokemon[0].hp;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p2.pokemon[0].hp).toBe(p2hp - 83);

        expectLog(battle, [
          '|move|p2a: Jolteon|Substitute|p2a: Jolteon',
          '|-start|p2a: Jolteon|Substitute',
          '|-damage|p2a: Jolteon|250/333',
          '|move|p1a: Butterfree|Mega Drain|p2a: Jolteon',
          '|-activate|p2a: Jolteon|Substitute|[damage]',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Substitute 1/4 HP glitch', () => {
        const battle = startBattle([], [
          {species: 'Pidgey', level: 3, moves: ['Substitute']},
        ], [
          {species: 'Rattata', level: 4, moves: ['Focus Energy']},
        ]);

        battle.p1.pokemon[0].hp = 4;

        battle.makeChoices('move 1', 'move 1');
        expect(battle.p1.pokemon[0].hp).toBe(0);

        expectLog(battle, [
          '|move|p2a: Rattata|Focus Energy|p2a: Rattata',
          '|-start|p2a: Rattata|move: Focus Energy',
          '|move|p1a: Pidgey|Substitute|p1a: Pidgey',
          '|-fail|p1a: Pidgey|move: Substitute|[weak]',
          '|faint|p1a: Pidgey',
          '|win|Player 2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });

      test('Substitute + Confusion glitch', () => {
        // Confused Pokémon has Substitute
        {
          const battle = startBattle([
            SRF, HIT, CFZ(5), CFZ_CAN, SRF, SRF, HIT, SRF, CFZ_CANT,
          ], [
            {species: 'Bulbasaur', level: 6, evs, moves: ['Substitute', 'Growl']},
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

          expectLog(battle, [
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
          ]);
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
        // Both Pokémon have Substitutes
        {
          const battle = startBattle([
            SRF, HIT, NO_CRIT, MIN_DMG, SRF, SRF, HIT, CFZ(5), CFZ_CANT, CFZ_CAN, SRF, CFZ_CANT,
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

          expectLog(battle, [
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
          expect((battle.prng as FixedRNG).exhausted()).toBe(true);
        }
      });

      test('Psywave infinite loop', () => {
        const PSY_MAX = {key: 'Battle.damageCallback', value: MAX};
        const battle = startBattle([SRF, SRF, SRF, HIT, HIT, PSY_MAX], [
          {species: 'Charmander', evs, level: 1, moves: ['Psywave']},
        ], [
          {species: 'Rattata', evs, level: 3, moves: ['Tail Whip']},
        ]);

        const p2hp = battle.p2.pokemon[0].hp;

        battle.makeChoices('move 1', 'move 1');

        expect(battle.p2.pokemon[0].hp).toEqual(p2hp);

        expectLog(battle, [
          '|move|p2a: Rattata|Tail Whip|p1a: Charmander',
          '|-unboost|p1a: Charmander|def|1',
          '|move|p1a: Charmander|Psywave|p2a: Rattata',
          '|turn|2',
        ]);
        expect((battle.prng as FixedRNG).exhausted()).toBe(true);
      });
    });
  }
}

interface Roll {
  key: string | string[];
  value: number;
}

class FixedRNG extends PRNG {
  private readonly rolls: Roll[];
  private index: number;

  constructor(rolls: Roll[]) {
    super([0, 0, 0, 0]);
    this.rolls = rolls;
    this.index = 0;
  }

  next(from?: number, to?: number): number {
    if (this.index >= this.rolls.length) throw new Error('Insufficient number of rolls provided');
    const roll = this.rolls[this.index++];
    const where = locations();
    const locs = where.join(', ');
    if (Array.isArray(roll.key)) {
      if (!roll.key.every(k => where.includes(k))) {
        throw new Error(`Expected roll for (${roll.key.join(', ')}) but got (${locs})`);
      }
    } else if (!where.includes(roll.key)) {
      throw new Error(`Expected roll for (${roll.key}) but got (${locs})`);
    }
    let result = roll.value;
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

const FILTER = new Set([
  '', 't:', 'gametype', 'player', 'teamsize', 'gen', 'message',
  'tier', 'rule', 'start', 'upkeep', '-message', '-hint',
]);

function filter(raw: string[]) {
  const log = Battle.extractUpdateForSide(raw.join('\n'), 'omniscient').split('\n');
  const filtered = [];
  for (const line of log) {
    const i = line.indexOf('|', 1);
    const arg = line.slice(1, i > 0 ? i : line.length);
    if (FILTER.has(arg)) continue;
    filtered.push(line);
  }

  return filtered;
}

const METHOD = /^ {4}at ((?:\w|\.)+) /;
const NON_TERMINAL = new Set([
  'FixedRNG.next', 'FixedRNG.randomChance', 'FixedRNG.sample', 'FixedRNG.shuffle',
  'Battle.random', 'Battle.randomChance', 'Battle.sample', 'locations',
]);

function locations() {
  const results = [];
  let last: string | undefined = undefined;
  for (const line of new Error().stack!.split('\n').slice(1)) {
    const match = METHOD.exec(line);
    if (!match) continue;
    const m = match[1];
    if (NON_TERMINAL.has(m)) {
      last = m;
      continue;
    }
    if (!results.length && last) results.push(last);
    results.push(m);
  }
  return results;
}

function expectLog(battle: Battle, expected: string[]) {
  const actual = filter(battle.log);
  try {
    expect(actual).toEqual(expected);
  } catch (err) {
    console.log(actual);
    throw err;
  }
}
