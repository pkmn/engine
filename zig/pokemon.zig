// References:
//  - https://bulbapedia.bulbagarden.net/wiki/Pokémon_data_structure_(Generation_I)
//  - https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/PKM/PK1.cs
//  - https://github.com/pret/pokered/blob/master/macros/wram.asm

const assert = @import("std").debug.assert;

const Stat = @import("data").Stat;
const Stats = @import("data").Stats;
const Boosts = @import("data").Boosts;
const Moves = @import("moves").Moves;

// battle_struct::Moves (pret) & Pokemon#moveSlot (PS)
const MoveSlot = struct {
  id: MoveID, // w{Player,Enemy}Move* (pret)
  pp: u6, // battle_struct::PP (pret)
  pp_ups: u2,

  pub inline fn init(id: MoveID) MoveSlot {
    assert(id != 0);
    const move = Moves.get(id);
    return MoveSlot {
      .id = id,
      .pp = move.pp,
      .pp_ups = 3,
    };
  }

  pub inline fn maxpp(self: *MoveSlot) u8 {
     return (5 + self.pp_ups) / 5 * Moves.get(self.id).pp;
  }
};

const NICKNAME_LENGTH = 18; // NAME_LEN = 11 (pret) & Pokemon#getName = 18 (PS)

// w{Battle,Enemy}Mon battle_struct (pret) & Pokemon (PS)
const Pokemon = struct {
  name: *const[NICKNAME_LENGTH:0]u8, // w{Battle,Enemy}MonNick (pret) & Pokemon#name (PS)
  species: SpeciesID,
  types: [2]TypeID,
  stored: struct {
    level: u8, // w{Player,Enemy}MonUnmodifiedLevel / battle_struct::Level (pret) && Pokemon#level (PS)
    stats: Stats(u16), // w{Player,Enemy}MonUnmodified* (pret) & Pokemon#storedStats (PS)
    moves: [4]MoveSlot, // Pokemon#baseMoveSlots (PS)
    dvs: u16, // TODO
    evs: Stats(u16), // TODO
  },
  stats: Stats(u16),
    // w{Player,Enemy}Mon*Mod (pret) & Pokemon#boosts (PS)
  boosts: Boosts(i4), // -6 <-> 6 (NOTE: pret = 1 <-> 13)
  hp: u16,
  status: u8, // Status
  volatiles: u18, // w{Player,Enemy}BattleStatus* (pret) & Pokemon#volatiles (PS)
  volatiles_data: struct {
    bide: u16, // w{Player,Enemy}BideAccumulatedDamage (pret) & volatiles.bide.totalDamage (PS)
    confusion: u3, // w{Player,Enemy}ConfusedCounter (pret) & volatiles.confusion.duration (PS)
    toxic: u8, // w{Player,Enemy}ToxicCounter (pret) & volatiles.residualdmg.counter (PS)
    substitute: u8, // w{Player,Enemy}SubstituteHP (pret) & volatiles.substitute.hp (PS)
    multihit: struct {
      hits: u3, // w{Player,Enemy}NumHits (pret)
      left: u3, // w{Player,Enemy}NumAttacksLeft (pret)
    },
  },
  moves = [4]MoveSlot,
  // w{Player,Enemy}DisabledMove (pret) & MoveSlot#disabled
  disabled = struct {
    move: u3,
    duration: u3,
  },

  pub inline fn level(self: *Pokemon) u8 {
    return self.stored.level;
  }

  pub fn dv(self: *Pokemon, stat: Stat) u4 {

  }
};

// https://github.com/pret/pokered/blob/master/constants/battle_constants.asm#L73
const Volatile = enum {
  Bide,         //  STORING_ENERGY           / bide
  Locked,       //  TRASHING_ABOUT           / lockedmove
  MultiHit,     //  ATTACKING_MULTIPLE_TIMES / Move#multihit
  Flinch,       //  FLINCHED                 / flinched
  Charging,     //  CHARGING_UP              / twoturnmove
  PartialTrap,  //  USING_TRAPPING_MOVE      / partiallytrapped & partialtrappinglock
  Invulnerable, //  INVULNERABLE             / Move#onLockMove
  Confusion,    //  CONFUSED                 / confusion
  Mist,         //  PROTECTED_BY_MIST        / mist
  FocusEnergy,  //  GETTING_PUMPED           / focusenergy
  Substitute,   //  HAS_SUBSTITUTE_UP        / substitute
  Recharging,   //  NEEDS_TO_RECHARGE        / mustrecharge & recharege
  Rage,         //  USING_RAGE               / rage
  LeechSeed,    //  SEEDED                   / leechseed
  Toxic,        //  BADLY_POISONED           / toxic
  LightScreen,  //  HAS_LIGHT_SCREEN_UP      / lightscreen
  Reflect,      //  HAS_REFLECT_UP           / reflect
  Transform,    //  TRANSFORMED              / transform
};


// FIXME party pokemon vs. battle pokemon!
// FIXME ???
// wPlayerMonNumber: u8 ; index in party of currently battling mon
// wMoveDidntMiss / wMoveMissed: u8
// wBattleMonSpecies2 / wEnemyMonSpecies2: u8  ???
// wPlayerMoveListIndex / wEnemyMoveListIndex: u8
