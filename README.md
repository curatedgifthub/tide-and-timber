# Tide & Timber

A graphical LÖVE card battle based on the Two-Row Chain System v1.1 and the Version 1.0 faction catalogs. It is played online: every match is dealt and refereed by a game server on Supabase, either against the computer or against another person on their own computer. Three decks are playable: **Fantasy** (Timber), **Water** (Tide) and **Comic** (the Super faction, from the artwork in `comics/`).

## Play

[Play Tide & Timber in your browser](https://curatedgifthub.github.io/tide-and-timber/). Phone, tablet, and desktop players share the same online matches and room codes as LÖVE. See [the browser build and GitHub Pages instructions](web/README.md).

On this Mac, open **Tide and Timber.app** in the project folder. The app includes LÖVE 11.5. The portable **Tide and Timber.love** file opens with [LÖVE 11.5](https://love2d.org/) on other desktops. To run the editable source, launch LÖVE with the folder that contains `main.lua`:

```sh
love .
```

The match table shows whether the game server is reachable. Both ways to play need it.

### Single Player (Online)

1. Choose **Single Player (Online)**. Use the arrows on the two faction portraits to choose your faction and the computer's.
2. Open **Browse** beneath a faction portrait. Click a card to inspect it and use **+** or **−** to select copies. Browse every illustrated design in your faction and tag 20–30 cards to bring to the match. The workshop offers **20-card starter**, **30-card starter**, and **Random 20**. Every 30-card starter contains 30 distinct designs. Custom decks can include multiple copies within the usual limits.
3. The computer brings its faction's 30-card starter unless you build a deck for it (the **Computer** tab in the workshop). **Normal** plays the best move it finds; **Easy** plays any legal card.
4. **Start online match**. The server shuffles both decks, deals five cards each, and plays the computer's turns. You see each computer move one at a time.

### Two Players (Online)

1. Both players choose **Two Players (Online)** and build their own deck. Nobody sees the other deck.
2. One player clicks **Create a room** and gets a six-character room code to share (**Copy the code** puts it on the clipboard).
3. The other player clicks **Join with a room code** and types or pastes it. The match starts as soon as they join; the server decides who acts first.
4. Each player sees the table from their own seat: own rows and hand at the bottom, the opponent on top. The opposing hand and both draw decks are shown only as counts.

A match in progress survives closing the game: the match table offers **Return to your match in progress**. **Match menu → Leave the match** ends it for both players. If a request fails, the battlefield says *Connection lost. Trying again…* and repeats it until it gets through; a move is never applied twice.

### On the battlefield

- Click a hand card. For a Unit, click a gold marker before, between, or after existing Units, or the highlighted space in an empty row. For an Effect, click **Play effect**. Choose any requested targets, positions, trigger order, or deck order in the dialog. Crowded rows have page arrows.
- **Read a unit.** Under its illustration are its name, current Attack Power (ATK, called Strength in card text) and current/maximum Health. Tap it to read its abilities. Both players see wounds immediately.
- **Play a unit.** Choose a position. It enters at its printed stats. Choose a legal enemy for its ordinary attack. In either row, the attack deals current Attack Power, subject to printed abilities such as Formation or Guard. With one target the attack resolves automatically. With an empty enemy field, proceed to Deploy. Damage removes Health, healing restores it up to maximum, and zero Health defeats the unit.
- **Choose a target.** Every Front enemy and every Back enemy without a Front unit in the matching position can be attacked. Positions close up after units leave. A printed ability follows its own target text. A Double Agent enters the opposing field and can strike another eligible enemy of the player who played it.
- **Resolve the card.** After its ordinary attack, resolve its Deploy text and earned chain abilities as part of the same play. The controller orders simultaneous friendly triggers. Free summons use their printed entry effects. **End extra plays** declines remaining plays granted by a card.
- **Build a chain.** Three or more adjacent Tide or Timber units can form a sequence of consecutive base Attack Powers, increasing or decreasing. A Bridge at either rightmost endpoint can connect Front left-to-right with Back right-to-left. A printed Chain ability triggers the first time the unit qualifies during that deployment. Comic combinations name their partners.
- **Finish the round.** Passing commits you to stop playing for the round. The other player can continue. Score when both pass, when neither can play or draw, or when the remaining active player cannot play or draw after the opponent passed. A player who has lost all units and has no legal play or draw on their turn can also end the round against an occupied field. An empty field with a legal play or a draw available stays in play.
- **Score remaining Health.** Add the current HP of the surviving units you control in both rows. For example, two units with 1 HP each lose to one unit with 3 HP. Higher HP wins the round. Equal HP gives neither player a win. Two round wins take the match. If neither player has two wins after round three, the match is a draw.
- Each round opens with five cards from each original tagged deck. The opening seat alternates between rounds. Each subsequent turn draws one if available. Open the round number for scores, a discard pile for used cards, or **View all** for the event history.
- **Deck presets** saves your deck, the computer's deck and the play mode into five slots in the LÖVE save directory (on macOS `~/Library/Application Support/LOVE/tide-and-timber/`).

Earlier simulation results are archived by release. [Historical playtest](docs/combat-playtest.md).

## Playable catalog: only cards with artwork

**A card is in the game only if it has its own illustration.** The pool is generated from `scripts/card_art.json` into `tabletop/card_art.lua`. A catalog entry with no illustration never appears in the workshop and cannot be drafted, dealt or drawn.

| Deck | Cards in the game | Catalog entries left out (no artwork yet) |
| --- | ---: | --- |
| Fantasy | 61 | 34 Root Snare, 53 Hill Troll Matriarch, 57 Restoration Circle, 59 Wizard's Gateway, 60 Hexbreaker, 61 Ancient Dragon, 63 Worldroot Guardian, 66 Archwizard of the Spire, 67 Dragonfire |
| Water | 74 | none (70 catalog cards + 4 new cards, 71–74) |
| Comic (Super) | 31 | the other 47 Super entries |
| Carnival | 0 | catalog definitions pending |

The left-out entries keep their rules and text in `card_battle_sim/data/cards.lua`, so a card enters the game as soon as its illustration is mapped.

Grave Acolyte can choose a unit of any faction with base Strength 3 or less from the acting player’s discard or draw deck. A draw-deck search shuffles the remaining cards. If neither pile has a legal target, draw one. A stolen Acolyte resolves for its current player.

### The Comic deck

The Comic deck has 31 illustrated designs. Its combinations depend on the characters named on each card. Water and Fantasy retain their numerical chains.

| Cards | What they do |
| --- | --- |
| **Dinosaur Dan** (4) + **Dan the Dinosaur** (5) → **Roaring T-Rex** (6) | When the second Dan is deployed while you control the other, a Roaring T-Rex comes straight into play from your draw deck (or else your hand), free, in a row and position you choose. Its Deploy deals 2 damage to every Unit in one opposing row. Comic cards use named combinations only. One T-Rex per deck. |
| **Building Showdown** | Summons one Grapple Hero, Grapple Heroine and Alien Gunner together from your deck or hand into your Front row. Summon whichever are available. Each Showdown may retrieve Alien Gunner from either player’s draw deck, hand or discard, even after a previous recovery. Ownership stays with the physical card. |
| **Cosmic Warden** (4 STR, 4 HP) → **Multiverse Phantom** (9 STR, 10 HP) | The Phantom can only be played *onto* a Cosmic Warden you control. It takes the Warden's exact position, deals 3 damage to every opposing Unit and draws a card. The Warden cannot be moved or weakened by the opponent, but it can be killed before the Phantom arrives, and then the Phantom is a dead card. |
| **Scared Sidekick** (2) and **Brave Sidekick** (5) | Whichever is played second decides the effect. Scared first: it fetches Brave Sidekick from your draw deck (or draws 1); Brave played after it gives Scared +3 Strength and deals 3 damage. Brave first: it shields itself from the next 3 damage; Scared played after it makes both ignore the next opposing damage effect. |
| **Hood** (1), **Spy** (2), **Vigilante** (3) | *Double Agents*: you deploy them on the **opponent's** battlefield, the card becomes theirs and its remaining Health counts toward their round score. In return: the Hood puts the top 3 cards of the opposing draw deck into its discard pile; the Spy takes a card of your choice from the opposing discard pile into your hand; the Vigilante swaps one of your Units with an opposing Unit of printed Strength 5 or less (they trade places and controllers). Once in the opponent's discard pile, a Double Agent can be pulled back by *any* deck's recovery ability and played against you. |

## How online play works

The server is the only place a match exists. It holds both decks, the shuffle, both hands and the draw order, decides whether a move is legal, applies it, and gives each player only the part of the result they may see.

- **One set of rules.** The server runs the same Lua files as the game (`online/manifest.lua` lists them: the battle engine, card data, abilities, the computer opponent, deck validation). They are uploaded to the Supabase project with `scripts/publish_rules.py` and executed inside the `game` Edge Function by fengari, a Lua virtual machine written in JavaScript. There is no second implementation of the rules. Client and server compare a hash of those files, and a copy of the game with different card data is told to update instead of playing with different rules.
- **Authoritative state.** A match is one row in `public.matches`: a snapshot of the battle state, the per-player views, and the battle record. A move carries the sequence number the player last saw. The row is only updated if it is still at that number, so a late, repeated or conflicting request changes nothing. A retry of a move that did arrive is recognised by its id and answered without being applied again.
- **Abilities that ask questions.** A suspended ability cannot be stored, so the server keeps the last quiet snapshot plus the inputs since then and replays them when the answer arrives. The engine is deterministic (its own seeded generator), so the replay reaches the same question.
- **Hidden information.** Clients never read the tables: Row Level Security is on with no policies, and nothing is published to Realtime. A player gets their own *view* from the server: both battlefields, both discard piles, scores and the record, their own hand, and only the size of the other hand and of both draw decks. The seed, deck order and deck lists never leave the server. Cards an ability lets a player look at are sent to that player alone.
- **The computer opponent** is the existing heuristic in `card_battle_sim/ai.lua`, run by the server right after the player's move, up to three computer actions per request. The game shows them one at a time at the old pace.
- **Synchronisation** is HTTPS only (LÖVE 11 has no WebSocket client). A player whose turn it is not polls a small database function (`match_state`) every 1.5 seconds; it answers with a few bytes until something has changed. Single-player matches do not poll at all. Requests run on a background thread, so the window never blocks.
- **Players** are anonymous Supabase Auth users. The sign-in is created on first launch and kept in the LÖVE save directory. The game contains only the project URL and the publishable key.

## Setting up the server

The game talks to the Supabase project named in `online/config.lua` (`url` and the publishable `key`). It is currently the project **tide-and-timber** (`tourlytmhcioxjiwsnxi`, US East, free plan) in the CausalScience organization, where everything below is already done. To set up another project:

1. In the Supabase dashboard, enable **Authentication → Sign In / Providers → Allow anonymous sign-ins** and press **Save changes**.
2. Run the files in `supabase/migrations/` in order (SQL editor, or `supabase db push`).
3. Deploy the function: `supabase functions deploy game` (settings in `supabase/config.toml`).
4. Put the project URL and publishable key into `online/config.lua`.
5. Allow this computer to publish rules, once: run `python3 scripts/publish_rules.py --digest` and insert the printed value with `insert into public.deploy_keys (digest) values ('…');`. The secret itself stays in `supabase/.publish_secret`; do not share or commit it.
6. Publish the rules: `python3 scripts/publish_rules.py`.

**After changing any card, ability or rule file, run `python3 scripts/publish_rules.py` again** and repackage the game. Until then the server and the edited copy disagree, and the game refuses to start a match (it says the rules differ). Matches in progress when the rules change are ended.

The security advisor in the dashboard lists three notices, all intended: the tables have Row Level Security with no policies (nobody but the server reads them), `match_state` runs with the owner's rights for signed-in players (it checks that the caller sits at the match), and `publish_rules` can be called without a sign-in (it does nothing without the publish secret).

Free tier: a match is one small row, kept for a week. An Edge Function call happens once per move; polling goes to the database API. A free project pauses after a week without use; the match table then shows that the server is not answering until the project is resumed in the dashboard.

## Source and assets

| File or directory | Responsibility |
| --- | --- |
| `main.lua`, `conf.lua` | Native window, input callbacks and entry point |
| `card_battle_sim/data/factions.lua`, `card_battle_sim/data/cards.lua` | Faction registration, edition eligibility, copy limits, stable card IDs, printed text and statistics |
| `card_battle_sim/decks.lua`, `tabletop/library.lua` | Faction and copy validation, drafts, starter suggestions and preset serialization |
| `card_battle_sim/battle.lua`, `abilities.lua`, `chains.lua`, `ai.lua` | The rules: trigger/operation mapping, numerical chains and the legal-action computer opponent |
| `online/server.lua`, `snapshot.lua`, `view.lua` | Server side: match logic, state snapshots, what each seat may see |
| `online/api.lua`, `session.lua`, `mirror.lua`, `http.lua`, `transport.lua` | Client side: sign-in and requests, one match with polling and recovery, the view as a battle state, HTTPS backends, the network thread |
| `online/json.lua`, `manifest.lua`, `rules.lua`, `config.lua` | JSON codec, the list of rule files, the rules version, the server address |
| `supabase/` | Database migration and the `game` Edge Function |
| `tabletop/setup_view.lua`, `board_view.lua`, `paint.lua`, `app.lua` | Match table, workshop, battlefield, artwork and dialogs |
| `tabletop/match.lua` | A local match driver without a server, used by the rule tests and available to an overworld host |
| `lovegame/fantasy art/`, `lovegame/water factor art/`, `comics/` | Supplied original artwork |
| `tabletop/assets/` | Sized transparent gameplay images and bundled fonts with licenses |

### Card artwork (no substitutes)

Each card shows only the illustration mapped to its own ID. The thumbnail is `tabletop/assets/<faction>/<number>.png`, listed in `tabletop/card_art.lua`. There is no fallback image. `python3 scripts/prepare_art.py --check` fails in each of these cases:

- an illustration is assigned to two IDs
- a thumbnail has no source mapping
- the generated pool is out of date

Images are matched to catalog cards by theme, as with the earlier mappings (for example *Deep-Sea Anglerfish Lunge* is Underwater Ambush). These nine were matched in the second pass:

| Card | Image |
| --- | --- |
| Fantasy:50 Orc Warlord | Fleeing Orc Trio Pixel Sprite |
| Fantasy:54 Shadow Assassin | Polished Pixel-Art Drider Warrior |
| Fantasy:55 Griffin Rider | Pixel Griffin Holding Fish |
| Fantasy:64 Troll King | Sumo Troll Defensive Push Stance |
| Fantasy:69 King's Decree | knight |
| Fantasy:70 Eclipse of the Black Keep | Broken Regal Crown Sprite |
| Water:35 Rip Current | Pixel-Art Portuguese Man o' War |
| Water:59 Current Reversal | Pixel Art Koi with Teal Fins |
| Water:70 School of the Deep | Megalodon Fossil Water Relic |

### New Water cards (71–74)

Four supplied images had no catalog entry, so they became new cards. Each one plays off its picture and an existing Water theme:

| ID | Card | Type | STR / HP | Ability | Design intent |
| --- | --- | --- | --- | --- | --- |
| Water:71 | **Lighthouse** (Uncommon) | Unit | 3 / 9 | Bridge. *Guiding Beam:* at the start of each of your turns, look at the top card of your draw deck; you may put it on the bottom. | A sturdy beacon that links your rows and steers what your draw abilities find next. |
| Water:72 | **Deep-Sea Diver** (Common) | Unit | 2 / 3 | *Deploy - Salvage Dive:* look at the bottom 3 cards of your draw deck, add one to your hand, put the rest back on the bottom in any order. | The only card that reaches the bottom of the deck, where Bait and Switch, Fishing Net and Scout-style searches leave cards. |
| Water:73 | **The White Whale** (Rare) | Unit | 7 / 12 | *Deploy - Old Harpoon:* takes 4 unpreventable damage. *Relentless:* whenever an opponent damages it and it survives, +2 Strength this round. | Arrives wounded; healing (Trout, Tide Pool, Whale Shark) makes it safer, and the opponent hesitates to hurt it. |
| Water:74 | **Bleached Reef** (Uncommon) | Effect | none | *Coral Bleaching:* choose an opposing row; its Units lose all Strength boosts gained this round. If none lost a boost, draw 1. Area-immune Units are unaffected. | Drains the colour from opposing buffs (War Horn, King's Decree, Goldfish) and still draws a card when there is nothing to strip. |

The Diver and Whale images had opaque painted backgrounds: plain white, and a drawn checkerboard. `prepare_art.py` clears background pixels connected to the image border when it builds their thumbnails. The supplied files are not modified.

Still not a card: *Regal Dark Fantasy Drider Sprite*, which is nearly identical to the Drider Warrior used for Shadow Assassin.

To add a card, add its `"Faction:Number": "path/to/image.png"` line to `scripts/card_art.json` and run `python3 scripts/prepare_art.py`. A card with no catalog entry also needs a definition in `card_battle_sim/data/cards.lua` and, if it has an ability, in `abilities.lua`.

To add a card, add its `"Faction:Number": "path/to/image.png"` line to `scripts/card_art.json` and run `python3 scripts/prepare_art.py`. A card with no catalog entry also needs a definition in `card_battle_sim/data/cards.lua` and, if it has an ability, in `abilities.lua`. Then publish the rules (see above).

An optional `display_name` changes the card face while `id` and canonical `name` remain available for rules. Give new cards trigger definitions with `abilities.define(faction, number, trigger, ...operations)`. Existing operations support targets, filters and conditions; new ones are added in `Battle.resolve`.

## Verification and packaging

```sh
(cd card_battle_sim && lua tests/run.lua)     # rules and catalog
lua tests/tabletop.lua                        # every card, the Comic edition, 180 seeded matches
lua tests/online_core.lua                     # the server: snapshots, hidden information, refusals
lua tests/online_client.lua                   # sign-in, polling, lost requests and replies
lua tests/online_live.lua                     # whole matches against the real server
python3 tests/run_ui.py --love /path/to/love  # the real window; add --live for the real server
```

`tests/online_core.lua` plays single-player and two-player matches through the server's request path and checks, after every move, that each player's view is unchanged when the other hand and the deck order are scrambled, and that the result is identical to the same inputs played on the local engine. `tests/mock_backend.py` is a local stand-in for the Supabase project (`love . --backend http://127.0.0.1:8787 --key test-key`); `--profile NAME` gives a second window its own sign-in so two copies can play each other on one computer.

Rebuild the portable game after editing source or assets with `python3 scripts/package_game.py`. To create a fresh local Mac app as well, supply `--mac-runtime /path/to/love.app`. The bundled game is a snapshot of the source at packaging time.

## Known limitations

- HTTPS uses the system's libcurl (macOS, Linux) or the `curl` command. On Windows only the `curl` command path exists (Windows 10 and later ship it); it has not been tested there, and may flash a console window per request. LÖVE 12, or a `https` library placed beside the game, is used automatically when present.
- A move takes about a third of a second to come back, and up to about a second when the computer answers with several plays. The first request after the server has been idle takes two to three seconds while it loads the rules.
- A player who closes the game during a two-player match does not forfeit; the other player sees when they were last seen and can leave. There is no turn timer.
- Anonymous players are per computer. Deleting the save directory loses the sign-in and with it a match in progress.
- The computer opponent is the same heuristic as before: legal and reasonable, not strong. Its handling of the new Comic cards is simple.
