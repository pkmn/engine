import {Generation} from '@pkmn/data';

import {Lookup} from './internal';
import * as gen1 from './gen1';

export class Battle {
  static create(gen: Generation, buf: ArrayBuffer) {
    return new gen1.Battle(Lookup.get(gen), new DataView(buf));
  }
}
