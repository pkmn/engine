const assert = @import("std").debug.assert;
const Pokemon = @import("pokemon").Pokemon;

pub const Side = struct {
    pokemon: []?Pokemon, // ??? (pret) & Side#pokemon (PS)
    active: u3, // wPlayerMonNumber (pret) & Side#active[0] (PS)
    fainted_last_turn: u3, // wInHandlePlayerMonFainted (pret) & Side#faintedThisTurn (PS)
    last_used_move: MoveID, // w{Player,Enemy}UsedMove (pret) & Side#lastMove (PS)
    last_selected_move: MoveID, // w{Player,Enemy}SelectedMove (pret) & Side#lastSelectedMove (PS)

    pub fn init(pokemon: []?Pokemon) Side {
        return Side{
            .pokemon = pokemon,
            .active = 1,
            .fainted_last_turn = 0,
            .last_used_move = 0,
            .last_selected_move = 0,
        };
    }

    pub inline fn active(self: *Side) *Pokemon {
        assert(self.active != 0);
        return self.pokemon[self.active - 1];
    }

    pub inline fn faintedLastTurn(self: *Side) ?*Pokemon {
        if (self.fainted_last_turn == 0) return null;
        return self.pokemon[self.fainted_last_turn - 1];
    }
};
