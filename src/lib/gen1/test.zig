// @test-only
// pub fn init(s: Species, ms: []const Moves) Pokemon {
//     assert(ms.len > 0 and ms.len <= 4);
//     const specie = Species.get(s);
//     const stats = Stats(u12){
//         .hp = Stats(u12).calc(.hp, specie.stats.hp, 0xF, 0xFFFF, 100),
//         .atk = Stats(u12).calc(.atk, specie.stats.atk, 0xF, 0xFFFF, 100),
//         .def = Stats(u12).calc(.def, specie.stats.def, 0xF, 0xFFFF, 100),
//         .spe = Stats(u12).calc(.spe, specie.stats.spe, 0xF, 0xFFFF, 100),
//         .spc = Stats(u12).calc(.spc, specie.stats.spc, 0xF, 0xFFFF, 100),
//     };

//     var slots = [_]MoveSlot{MoveSlot{}} ** 4;
//     var i: usize = 0;
//     while (i < ms.len) : (i += 1) {
//         slots[i].id = ms[i];
//         slots[i].pp = @truncate(u6, Moves.pp(ms[i]) / 5 * 8);
//     }

//     return Pokemon{
//         .stats = stats,
//         .position = 1,
//         .moves = slots,
//         .hp = stats.hp,
//         .species = s,
//         .types = specie.types,
//     };
// }

// test "Pokemon" {
//     const pokemon = Pokemon.init(Species.Gengar, &[_]Moves{ .Absorb, .Pound, .DreamEater, .Psychic });
//     try expect(!Status.any(pokemon.status));
//     // std.debug.print("{s}", .{pokemon});
//     util.debug(pokemon);
// }

// FIXME: move to mechanics (need to also apply burn/paralyze etc)
// pub fn switchIn(self: *Side, slot: u8) void {
//     assert(slot != self.active);
//     assert(self.team[self.active - 1].position == 1);

//     const active = self.get(slot);
//     self.team[self.active - 1].position = active.position;
//     active.position = 1;

//     inline for (std.meta.fieldNames(Stats(u16))) |stat| {
//         @field(self.pokemon.stats, stat) = @field(active.stats, stat);
//     }
//     var i = 0;
//     while (i < 4) : (i += 1) {
//         self.pokemon.moves[i] = active.pokemon.moves[i];
//     }
//     self.pokemon.volatiles.zero();
//     inline for (std.meta.fieldNames(Boosts(i4))) |boost| {
//         @field(self.pokemon.boosts, boost) = @field(active.boosts, boost);
//     }
//     self.pokemon.level = active.level;
//     self.pokemon.hp = active.hp;
//     self.pokemon.status = active.status;
//     self.pokemon.types = active.types;
//     self.active = slot;
// }

comptime {
    _ = @import("data.zig");
}
