// https://github.com/pret/pokered/blob/master/constants/type_constants.asm
pub const TypeID = enum {
  Normal, Fighting, Flying, Poison, Ground, Rock, Bird, Bug, Ghost,
  Fire, Water, Grass, Electric, Psychic, Ice, Dragon,
};

// https://github.com/pret/pokered/blob/master/constants/battle_constants.asm#L52-L57
const SUPER = 20;
const NEUTRAL = 10;
const RESISTED = 5;
const IMMUNE = 0;

// https://github.com/pret/pokered/blob/master/data/types/type_matchups.asm
const TypeChart = [_][_]u8 {
  //     Normal   Fighting  Flying    Poison   Ground   Rock      Bird     Bug      Ghost   Fire     Water    Grass    Electric Psychic  Ice      Dragon
  [_]u8{ NEUTRAL, NEUTRAL,  NEUTRAL,  NEUTRAL, NEUTRAL, RESISTED, NEUTRAL, NEUTRAL, IMMUNE, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL }, // Normal
  // ...
};
