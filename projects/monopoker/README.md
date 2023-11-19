# Monopoker

A new game mixing two existing games - monopoly and poker.

:::toc

## Rules

### Defintions

Monopoly consists of "Rounds" (for each person in game, execute actions until it's the first persons turn again) called "Layer 1" from here on. Each rounds consists of an action performed by each player called "Layer 2".

The game could implement checks after a Layer 1 round for which if the check is truthy, a switch to another game occurs.

### Switches

Switching occurs if the check is truthy (this check happens after a "Layer 1" round). A switch on Layer 2 would probably be in-balanced and thus create quite some chaos, but should also be considered.

### Code

Play `n` rounds of monopoly and then `m` rounds of poker (with the same money).

> 10 LABEL: START
> 20 PLAY $n ROUNDS OF MONOPOLY
> 30 PLAY $m ROUNDS OF POKER
> 40 GOTO 10

## To try

- start the new game of poker after a "Layer 2" (explaiend in rules above) action instead of a "Layer 1" action.

## Futher ideas

- META add other games which also use money or other concepts from monopoly or poker (for example a card game added into poker).
- MONOPOLY: add more directions into monopoly (two boards with conditions for getting from one board to the next)
- MONOPOLY: add vehicles to monopoly (buy a car and get a multiplier on the places you move foward)
- META: add loans
- META time based switches (idea from @maride)
- MONOPOLY: add companies

