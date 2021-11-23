/* eslint-disable @typescript-eslint/no-shadow */
import {MoveName, PokemonHPStatus, PokemonIdent, PokemonDetails} from '@pkmn/protocol';
import {StatsTable, SideID, ID, MoveTarget} from '@pkmn/data';

export type Request = MoveRequest | SwitchRequest | TeamRequest | WaitRequest;

export interface MoveRequest {
  side: Request.SideInfo;
  active: Array<Request.ActivePokemon | null>;
  noCancel?: boolean;
}

export interface SwitchRequest {
  side: Request.SideInfo;
  forceSwitch: [true] & boolean[];
  noCancel?: boolean;
}

export interface TeamRequest {
  teamPreview: true;
  side: Request.SideInfo;
  maxTeamSize?: number;
  noCancel?: boolean;
}

export interface WaitRequest {
  wait: true;
  side: undefined;
  noCancel?: boolean;
}

export namespace Request {
  export interface SideInfo {
    name: string;
    id: SideID;
    pokemon: Pokemon[];
  }

  export interface ActivePokemon {
    moves: Array<{
      move: MoveName;
      pp: number;
      maxpp: number;
      target: MoveTarget;
      disabled?: boolean;
    }>;
    maxMoves?: {
      gigantamax?: boolean;
      maxMoves: Array<{
        move: string;
        target: MoveTarget;
        disabled?: boolean;
      }>;
    };
    canZMove?: Array<{
      move: MoveName;
      target: MoveTarget;
    } | null>;
    canDynamax?: boolean;
    canMegaEvo?: boolean;
    canUltraBurst?: boolean;
    trapped?: boolean;
    maybeTrapped?: boolean;
    maybeDisabled?: boolean;
    fainted?: boolean;
  }

  export interface Pokemon {
    active?: boolean;
    details: PokemonDetails;
    ident: PokemonIdent;
    pokeball: ID;
    ability?: ID;
    baseAbility?: ID;
    condition: PokemonHPStatus;
    item: ID;
    moves: ID[];
    stats: Omit<StatsTable, 'hp'>;
  }
}

export type Choice = MoveChoice | SwitchChoice | TeamChoice | ShiftChoice;

interface MoveChoice {
  type: 'move';
  choice: string;
  isZ: boolean;
  changed: boolean;
}

interface SwitchChoice {
  type: 'switch';
  slot: number;
}

interface TeamChoice {
  type: 'team';
  slot: number;
}

interface ShiftChoice {
  choiceType: 'shift';
}

export function choices(request: Request): string[] { // DEBUG
  // WaitRequest
  if ('wait' in request) return [];

  // TeamRequest
  if ('teamPreview' in request) {
    // BUG: technically more permutations are relevant for Illusion
    const choices: string[] = [];
    for (let slot = 1; slot < request.side.pokemon.length; slot++) {
      choices.push(`team ${slot}`);
    }
    return choices;
  }

  return [];

  // const pokemon = request.side.pokemon;

  // // SwitchRequest
  // if ('forceSwitch' in request) {
  //   let choices: string[] = [];

  //   let partial: string[] = [];
  //   for (const mustSwitch of request.forceSwitch) {
  //     if (!mustSwitch) continue;

  //     // [true, true, true]
  //     // 456,465,  546,564,   645,654


  //     const options = [];
  //     for (let slot = 1; slot <= pokemon.length; slot++) {
  //       if (pokemon[slot - 1] &&
  //         // not active
  //         slot > request.forceSwitch.length &&
  //         // not chosen for a simultaneous switch
  //         !chosen.includes(slot) &&
  //         // not fainted
  //         !pokemon[slot - 1].condition.endsWith(' fnt')) {
  //         options.push(`switch ${slot}`);
  //       }
  //     }

  //     if (!options.length) {
  //       choices.push('pass');
  //     } else {
  //       choices.push(`switch ${choice.slot}`);
  //       chosen.push(choice.slot);
  //     }
  //   }

  //   return choices.join(', ');
  // }

  // // MoveRequest
  // let [canMegaEvo, canUltraBurst, canZMove, canDynamax] = [true, true, true, true];
  // for (let i = 0; i <= request.active.length; i++) {
  //   const active = request.active[i];
  //   if (!active || active.fainted || pokemon[i].condition.endsWith(' fnt')) {
  //     choices.push('pass');
  //     continue;
  //   }

  //   canMegaEvo = canMegaEvo && !!active.canMegaEvo;
  //   canUltraBurst = canUltraBurst && !!active.canUltraBurst;
  //   canZMove = canZMove && !!active.canZMove;
  //   canDynamax = canDynamax && !!active.canDynamax;

  //   const options: Array<SwitchChoice | MoveChoice> = [];

  //   // moves
  //   const hasAlly = pokemon.length > 1 && !pokemon[i ^ 1].condition.endsWith(' fnt');
  //   const canChange = canMegaEvo || canUltraBurst || canDynamax;
  //   for (const changed of canChange ? [false] : [false, true]) {
  //     const useMaxMoves = (!active.canDynamax && active.maxMoves) || (changed && canDynamax);
  //     const possibleMoves = useMaxMoves ? active.maxMoves!.maxMoves : active.moves;

  //     const filtered = [];
  //     const canMove = [];
  //     for (let j = 1; j <= possibleMoves.length; j++) {
  //       if (possibleMoves[j - 1].disabled) continue;
  //       // NOTE: we don't actually check for whether we have PP or not because the
  //       // simulator will mark the move as disabled if there is zero PP and there are
  //       // situations where we actually need to use a move with 0 PP (Gen 1 Wrap).
  //       const move = {
  //         slot: j,
  //         move: possibleMoves[j - 1].move,
  //         target: possibleMoves[j - 1].target,
  //         zMove: false,
  //       };
  //       canMove.push(move);
  //       if (move.target !== 'adjacentAlly' || hasAlly) filtered.push(move);
  //     }
  //     if (canZMove) {
  //       for (let j = 1; j <= active.canZMove!.length; j++) {
  //         const zmove = active.canZMove![j - 1];
  //         if (!zmove) continue;
  //         const move = {
  //           slot: j,
  //           move: zmove.move,
  //           target: zmove.target,
  //           zMove: true,
  //         };
  //         canMove.push(move);
  //         if (move.target !== 'adjacentAlly' || hasAlly) filtered.push(move);
  //       }
  //     }

  //     for (const move of filtered.length ? filtered : canMove) {
  //       let targets = [0];
  //       if (request.active.length > 1) {
  //         switch (move.target) {
  //         case 'normal': case 'any': case 'adjacentFoe':
  //           targets = [1, 2];
  //           break;
  //         case 'adjacentAlly':
  //           targets = [-((i ^ 1) + 1)];
  //           break;
  //         case 'adjacentAllyOrSelf':
  //           targets = hasAlly ? [-1, -2] : [-(i + 1)];
  //           break;
  //         }
  //       }
  //       const choice = `move ${move.slot}`;
  //       for (const target of targets) {
  //         options.push({
  //           type: 'move' as const,
  //           choice: target ? `${choice} ${target}` : choice,
  //           isZ: move.zMove,
  //           changed,
  //         });
  //       }
  //     }
  //   }

  //   // switches
  //   if (!active.trapped) {
  //     for (let slot = 1; slot <= pokemon.length; slot++) {
  //       if (pokemon[slot - 1] &&
  //         // not active
  //         !pokemon[slot - 1].active &&
  //         // not chosen for a simultaneous switch
  //         !chosen.includes(slot) &&
  //         // not fainted
  //         !pokemon[slot - 1].condition.endsWith(' fnt')) {
  //         options.push({type: 'switch' as const, slot: slot});
  //       }
  //     }
  //   }

  //   const choice = this.makeChoice(options);
  //   if (choice.type === 'switch') {
  //     choices.push(`switch ${choice.slot}`);
  //     chosen.push(choice.slot);
  //   } else {
  //     if (choice.isZ) {
  //       canZMove = false;
  //       choices.push(`${choice.choice} zmove`);
  //     } else if (choice.changed) {
  //       if (canDynamax) {
  //         canDynamax = false;
  //         choices.push(`${choice.choice} dynamax`);
  //       } else if (canMegaEvo) {
  //         canMegaEvo = false;
  //         choices.push(`${choice.choice} mega`);
  //       } else {
  //         canUltraBurst = false;
  //         choices.push(`${choice.choice} ultra`);
  //       }
  //     } else {
  //       choices.push(choice.choice);
  //     }
  //   }
  // }

  // return choices;
}
