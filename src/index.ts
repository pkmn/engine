import {ID, TypeName} from '@pkmn/data';

// FIXME only where not equal to @pkmn/dex.num!!!
export interface IDs {
  '1': {
    moves: ID[];
    species: ID[];
    types: TypeName[];

  };
  '2': {
    items: ID[];
    moves: ID[];
    species: ID[];
    types: TypeName[];

  };
  '3': {
    species: ID[];
    moves: ID[];
  };
}
