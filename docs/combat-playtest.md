# Play-driven combat

This report records the simulations from release `543f826`. Its mechanics and balance measurements describe that historical release. [Current rules](../README.md#on-the-battlefield)

## One card play

1. Choose a hand card and its position. Replacements take their named host’s position. Pay one play. Placing a unit captures any numerical chain triggers it earns.
2. The deployed unit strikes. Choose among enemy Front units while any remain, then among Back units. A lone target resolves automatically. An empty enemy field skips this step. Start with current Strength, add one for being in a numerical chain, add support from the rightmost other Back ally (one per three current Strength, up to two), and apply the card’s printed attack condition.
3. Apply damage protection and reduce Health. Zero Health resolves destruction and Last Breath immediately. A surviving defender counters a surviving attacker for half its current Strength, rounded down. Back defenders can counter when exposed. Healing repairs real wounds up to maximum Health.
4. Resolve the played card’s Deploy text, including choices, even if a counter defeated the attacker. A self-buff still needs its recipient on the field. A special attack that names any enemy can hit either row. An ability that names a row uses its own row restriction. Free summons enter with their printed effects. Double Agents enter the enemy field and resolve their infiltration abilities.
5. Resolve earned chains, with the active side first and each controller choosing their trigger order. A counter that disrupts the placement cannot erase an already earned trigger. Resolve follow-on formations. A numerical chain reward can trigger once per unit deployment. Comic uses named combinations.
6. Finish any earned extra plays or decline them. Then the next player draws one if possible, resolves turn-start effects and takes their turn. The first player of each round starts with the five-card deal.

Buffs and debuffs change counters and Back support after the initial strike. The workshop and hand inspection explain heavy deployment. A hand-played unit with base Strength 5+ needs a friendly unit of base Strength 1–3 to enter at printed stats. Otherwise it starts at 2 Strength and 2 HP. Healing and buffs can improve it afterward. Summons and named replacements are exempt.

## Winning and recovery

A cleared field can be reinforced. A player with no legal play waits while either side can still change the position. An empty field loses on its owner's turn when the draw pile is empty, there is no legal play and the opponent has surviving units. When both sides can neither play nor draw, compare surviving unit counts. Equal counts draw. Conceding the round immediately awards it to the opponent.

Each new round shuffles every originally tagged copy back into its owner's deck and deals five fresh cards. The opening player alternates. Two round wins end a match early. After round three the greater number of round wins takes the match, and equal wins draw. Each physical card can be recovered individually from discard once per round. School of Goldfish can recycle the pile once per match. These limits bound recovery loops.

## What changed in the card collection

The audit includes every illustrated design, its rules text, starter inclusion, applicable deck hints, and measured outcomes. The three 30-card starters include light support and their intended partners. Opening an older custom list preserves its choices. Inspect a card in the workshop to see tagged partner counts, eligible recovery targets or the available range of consecutive Strengths. [Full 166-card audit](card-balance-audit.csv)

| Card | Design decision | Outcome in 1,500 simulated matches |
|---|---|---|
| Grave Acolyte | Recover a Timber unit of base Strength 1–3. Draw one if none can return. | 1,445 recoveries and 103 fallback draws. On 12 attempts both resources were unavailable. |
| Rune Apprentice | Keep the Chain 3 special strike against either row. | 897 triggers removed 1,016 enemy HP after protection and overkill. |
| High Elf Spellblade | Chain 4 deals two damage through protection. | 293 triggers removed 286 HP. Some chains found an empty board or a nearly defeated target. |
| Smelt | Heal a wound, or protect an ally when all are healthy. | 727 chains restored 1,139 HP. |
| Dolphin and Nautilus | Dolphin earns an extra play alongside its draw. Nautilus can draw if it cannot recover a Tide Effect. | Dolphin triggered 390 times and drew 327 cards. Nautilus recovered 136 Effects and drew 307 fallback cards in 470 triggers. |
| Veteran Ranger and Dragonkin Sorcerer | Ranger protects an ally in addition to drawing. Sorcerer protects the same ally it strengthens. | Ranger drew 229 cards in 272 triggers. Sorcerer drew 61 in 95 triggers. |
| Colossal Squid | Keep Chain 5, unrestricted recovery and the three-point enemy Strength reduction. The reduction affects counters and Back support. | 212 chain triggers returned 212 cards. The simulator does not attribute prevented counters to a particular debuffer. |
| Giant Oarfish | Chain 4 draws two. A length-five formation also protects each surviving member against two damage. | Lowering the draw threshold raised activations from 13 to 54 on the same seeds. It drew 50 cards. The longer protection condition was met five times. |
| Frost Giant and the Trolls | Frozen Earth deals one to a row, two per unit if at least three remain. Stone Troll and Ogre Chieftain have six HP. | Before tuning, Frost Giant dealt 26,279 special-damage HP and stacked Timber beat its starter 92–5 with three draws. After card and starter revisions, that matchup finished 10–78 with 12 draws. |
| Tide utility and Timber’s Fellowship | Rip Current punishes wounded enemies. Shallow Waters protects the relocated ally. Tide Pool heals two across the field. Unlikely Fellowship gives the assembled trio Strength, two draws and two extra plays. | Fellowship was legally played just once in this sample and its draw deck was empty. Its human value is unresolved. |

**Named Comic combinations.** Brave checks for Scared after the ordinary strike. A surviving friendly Scared gains three Strength and Brave chooses an enemy for three additional damage. In the opposite order, Scared shields both. The Dans summoned Roaring T-Rex 1,163 times. Multiverse Phantom replaced Cosmic Warden 1,509 times. Building Showdown retrieved 6,785 characters across 2,759 successful plays, including 1,233 Gunner recoveries. Neither grappler is a prerequisite. The grapplers have five HP each and Gunner has four so the summoned Front can screen allies. The artwork and named characters are unchanged.

## Matchup results

The final rules completed **2,250 automated matches** across 15 scenarios. The main run used 50 seeds (201–250), with seats swapped for every seed and scenario. The additional run used 25 separate seeds (701–725). Both used complete matches to combat exhaustion. Each normal AI used the same public targeting and placement heuristics. Easy varied move selection. Random lists sampled 30 distinct designs. Stacked lists selected the highest Strength-plus-durability designs up to their legal copy limits. These decks intentionally stress the rules and can omit named prerequisites.

| Normal starters, first faction listed first | Main run W–L–D | Additional seeds W–L–D |
|---|---:|---:|
| Timber vs Tide | 56–30–14 | 31–16–3 |
| Timber vs Comic | 48–37–15 | 28–17–5 |
| Tide vs Comic | 37–53–10 | 19–26–5 |

In the main run, the opener won 112 of the 300 normal starter matches and 39 matches drew. Starter matches averaged 123–132 ordinary attacks over the whole match. The opener's disadvantage and the number of decisions in a full match deserve attention in human play.

| Other scenarios, 100 matches each | First faction wins | Second faction wins | Draws |
|---|---:|---:|---:|
| Random Timber / Tide | 78 | 20 | 2 |
| Random Timber / Comic | 67 | 26 | 7 |
| Random Tide / Comic | 33 | 64 | 3 |
| Stacked Timber / Tide | 97 | 1 | 2 |
| Stacked Timber / Comic | 100 | 0 | 0 |
| Stacked Tide / Comic | 92 | 3 | 5 |
| Stacked / starter Timber | 10 | 78 | 12 |
| Stacked / starter Tide | 0 | 100 | 0 |
| Stacked / starter Comic | 0 | 100 | 0 |
| Easy Timber / Normal Tide, starters | 15 | 76 | 9 |
| Easy Timber / Normal Comic, starters | 28 | 57 | 15 |
| Easy Tide / Normal Comic, starters | 31 | 60 | 9 |

Timber retains an advantage in random and stacked cross-faction matchups. Dedicated starter support reversed the stacked decks’ initial sweeps against their own factions. A three-copy-heavy deck differs substantially from a custom deck deliberately built around a named pair. No exhaustive search of custom decks or optimal strategies was performed.

## Interpreting the audit

The main run recorded 178,539 ordinary attacks removing 446,392 HP, counters removing 102,236 HP, 30,353 HP restored, and 26,003 HP actually spared by protection. A modified Strength changed the calculated power of 6,008 counters compared with the printed value. Attributed special damage includes self-damage, identified separately in the CSV. Destruction effects have their own count.

The CSV counts hand plays separately from free entries. T-Rex entered through the Dans throughout the sample. Draws, searches and recoveries count actual cards moved. Protection is credited to the recipient when it actually spares HP. Conditions met count individual operations passing their prerequisites. Many cards have several operations. Empty draws, recoveries and heals identify specific missed benefits. A shield granted, a card revealed, or a chain activation alone cannot establish a successful tactical outcome. Deck win counts include every deck containing the design, so they do not isolate the effect of adding that card. The simulation does not measure player comprehension, enjoyment, or how a human would choose among targets.

## Reproduce

Run from the repository root with Lua and the web build dependencies installed.

```sh
lua tests/combat_balance.lua 50 201 /tmp/tide-timber-observations.json docs/card-balance-audit.csv
lua tests/combat_balance.lua 25 701
(cd card_battle_sim && lua tests/run.lua)
lua tests/tabletop.lua
lua tests/online_core.lua
lua tests/online_client.lua
python3 web/build.py
node web/tests/protocol.mjs
```

The local online protocol suite completed 18 solo matches and 120 duels, comparing each seat’s state with the engine and checking private data. In the duel run, 6,000 actions included 2,078 answered choices, 65 by the other player during the active player's turn. Regression cases cover separate ordinary and special targets, a chain earned before a lethal counter, healing eligibility, drawing after a wipe, exhaustion and concession. The browser modules were tested in Node, including wounded Health on both battlefields, reloading a seat and replaying a lost request once. Verification used code and simulation only.
