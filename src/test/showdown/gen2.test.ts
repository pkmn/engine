import {Battle, Dex, PRNG} from '@pkmn/sim';
import {Generations} from '@pkmn/data';

import {MIN, MAX, ROLLS, ranged, formatFor, createStartBattle, FixedRNG, verify} from './helpers';
// import * as gen2 from '../benchmark/gen2';

const gens = new Generations(Dex as any);
const gen = gens.get(2);
// const choices = gen2.Choices.sim;
const startBattle = createStartBattle(gen);

const {HIT, MISS, CRIT, NO_CRIT, MIN_DMG, MAX_DMG} = ROLLS.basic;
const {SS_MOD, SS_RES, SS_RUN, SS_EACH, INS, GLM} = ROLLS.nops;

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
  test.todo('start (first fainted)');
  test.todo('start (all fainted)');
  test.todo('switching (order)');
  test.todo('switching (reset)');
  test.todo('switching (brn/par)');
  test.todo('turn order (priority)');
  test.todo('turn order (basic speed tie)');
  test.todo('turn order (complex speed tie)');
  test.todo('turn order (switch vs. move)');
  test.todo('PP deduction');
  test.todo('accuracy (normal)');
  test.todo('damage calc');
  test.todo('fainting (single)');
  test.todo('fainting (double)');
  test.todo('end turn (turn limit)');
  test.todo('Endless Battle Clause (initial)');
  test.todo('Endless Battle Clause (basic)');
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
  test.todo('HighCritical effect');
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
  test.todo('OHKO effect');
  test.todo('SkyAttack effect');
  test.todo('SkullBash effect');
  test.todo('RazorWind effect');
  test.todo('Solarbeam effect');
  test.todo('Fly/Dig effect');
  test.todo('Gust/Earthquake effect');
  test.todo('Twister effect');
  test.todo('ForceSwitch effect');
  test.todo('Teleport effect');
  test.todo('Splash effect');
  test.todo('Trapping effect');
  test.todo('JumpKick effect');
  test.todo('RecoilHit effect');
  test.todo('Struggle effect');
  test.todo('Thrashing effect');
  test.todo('FixedDamage effect');
  test.todo('LevelDamage effect');
  test.todo('Psywave effect');
  test.todo('SuperFang effect');
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
