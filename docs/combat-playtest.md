# Combat playtest

A unit can spend one turn on one basic attack per round. Its current Strength determines damage. A surviving Front defender counters for half its current Strength, rounded down. Front protects Back against basic attacks. Printed abilities can reach other targets. A unit at zero Health goes to its owner's discard pile unless its ability says otherwise.

Both seats get up to eight turns per round. A player can deploy after losing every unit. When both seats finish, compare enemies defeated, then enemy Health removed after protection, then sole control of the battlefield. A remaining tie is a draw. Round cleanup, friendly damage and replaced units earn no defeats. Two round wins or the completion of round three ends the match.

## Changes informed by simulation

The first pass let expensive units attack at full Strength without a meaningful deployment tradeoff. In 24 paired-seat games per matchup, stacked Tide swept its own starter and the Comic starter swept the original Tide starter.

The revised starters bring attackers, protection, healing and support. A heavy unit played from hand needs a friendly unit of base Strength 1–3 to enter at full Health. Without support it enters at half Health, rounded up. Summons and named replacements enter at full Health before their abilities resolve. This lets players bring a heavy deck and gives the opposing player a reason to target its support.

Small units with at most two original Health gained one Health. The Kraken now deals one damage across the enemy battlefield and two against wounded targets. Megalodon can finish a wounded unit at three or less Health. Front-line Forest Treant gains Guard, and Frost Giant punishes an enemy who crowds three units into a row. Extra card plays from all sources share a two-per-turn limit.

## Validation

Run from the repository root.

```sh
lua tests/combat_balance.lua 100 4001
lua tests/tabletop.lua
lua tests/online_core.lua
```

The balance run used 100 fresh seeds with both seat assignments in 15 scenarios, for 3,000 complete matches. Each faction pairing used full starters, random 30-design decks and decks filled with the highest Strength plus 0.35 times Health, up to existing copy limits. Additional scenarios compared heavy and starter decks within each faction and compared Easy and Normal policies. The simulation uses the same battle engine and AI as multiplayer.

| Normal AI starter matchup | First faction wins | Second faction wins | Draws | Basic attacks per match |
| --- | ---: | ---: | ---: | ---: |
| Timber vs Tide | 103 | 90 | 7 | 13.7 |
| Timber vs Comic | 102 | 92 | 6 | 15.7 |
| Tide vs Comic | 78 | 113 | 9 | 15.6 |

The opening seat won 296 of those 600 starter matches. Comic has a measurable advantage against Tide in this sample. The artificial heavy Timber list lost 180 of 200 against its own starter, while heavy Comic won 131 of 200 against its starter. Card mix and support availability still matter. The next human playtest should check whether the first attack is easy to find, whether the heavy deployment preview explains the Health loss, and whether eight turns feels right for a round. The simulation measures outcomes under these policies and cannot establish how enjoyable those decisions feel.
