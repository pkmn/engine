import * as addon from './addon';

describe('AddOn', () => {
  test('check', () => {
    expect(() => addon.check(true)).not.toThrow();
    expect(() => addon.check(false))
      .toThrow('@pkmn/engine has only been configured to support Pokémon Showdown');
  });

  test('supports', () => {
    const showdown = true;
    const trace = true;

    expect(addon.supports(!showdown)).toBe(false);
    expect(addon.supports(!showdown, trace)).toBe(false);
    expect(addon.supports(!showdown, !trace)).toBe(false);

    expect(addon.supports(showdown)).toBe(true);
    expect(addon.supports(showdown, trace)).toBe(false);
    expect(addon.supports(showdown, !trace)).toBe(true);
  });
});
