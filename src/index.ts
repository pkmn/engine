import {ID, TypeName} from '@pkmn/data';
import json from './ids.json';

export interface IDs {
  1: {
    types: TypeName[];
  };
  2: {
    items: ID[];
    types: TypeName[];
  };
  3: {
    items: ID[];
  };
}

export const IDS = json as IDs;
