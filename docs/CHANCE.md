https://gist.github.com/scheibo/cd721e33d15be80de8cc4742d7431b16

https://gist.github.com/scheibo/68dabaac2f0e866c5302e5be69e20678

```py
# Determine probabilities of all possible transitions from the initial battle state
# given Player 1's choice c1 and Player 2's choice c2 an all possible actions taken
# by the Chance player
def transitions(battle, c1, c2):
    # Results get collected in a list here but instead of appending to a list one might
    # want to directly insert nodes into a game search tree. The "frontier" here represents
    # unexplored chance actions that need to be exhaustively perturbed
    results, frontier = [], []
    # Start by performing an update without supplying any direction as to what the Chance
    # player should do to determine where we should begin iterating. We need to ensure we
    # only update a *copy* of the original battle so as not to mutate our input
    result, chance = battle.copy().update(c1, c2)
    results.append((result, chance))
    frontier.append(chance.actions)

    # Iterate through all possible variations of Chance actions discovered by "perturbing" a
    # Chance action from the frontier. If any of these perturbed values cause us to encounter
    # stochasticity not previously accounted for by the Chance actions we're currently
    # iterating over it will get added to the frontier for us to explore after
    for actions in frontier:
        # The perturb function is hiding a lot of the complexity here - really this abstracts over
        # multiple nested loops which check to see whether a field of the Chance actions is set
        # and if so, produces further actions that contain all possible combinations of values
        # within the range of that field (plus special treatment of fields like damage or durations)
        for perturbed in perturb(actions):
            # Perform the battle update (once again on a copy of the battle), but this time we also
            # provide directions as to the actions the Chance player should take when encountering
            # the same set of decisions as when it performed the update that produced the Chance
            # actions from our frontier
            result, chance = battle.copy().update(c1, c2, perturbed)

            # If the actual output chance actions "match" the input actions (ie. have equal key sets
            # or "shape") then we track the result, otherwise we add it to the frontier if it is a
            # completely new shape (if it matches but is not equivalent to our perturbed input
            # actions, it means our directions to the Chance player were not sufficient - i.e.
            # additional or alternative RNG was encountered)
            if matches(actions, chance.actions):
               if perturbed != chance.actions: continue
               results.append((result, chance))
            elif matches(frontier, chance.actions):
               frontier.append(chance.actions)

            # If it is neither the correct shape or a new shape we simply ignore the update as it
            # was either handled or will be handled when we process that area of the frontier. If we
            # can afford to track all visited states then we could add a check at the start of this
            # loop to see if we are about to visit a state we've already encountered and skip it,
            # though this is not necessary for correctness (but might improve performance)

    return results
```