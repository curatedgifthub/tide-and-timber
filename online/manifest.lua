-- The Lua files that make up the rules of the game, as the server runs them.
-- scripts/publish_rules.py uploads exactly these files, and both sides derive the rules
-- version from them, so a client with different card data or rules is told to update.
-- One entry per line: {module name, path from the project root}.
return {
  {'util','card_battle_sim/util.lua'},
  {'rules','card_battle_sim/rules.lua'},
  {'data.cards','card_battle_sim/data/cards.lua'},
  {'data.factions','card_battle_sim/data/factions.lua'},
  {'abilities','card_battle_sim/abilities.lua'},
  {'chains','card_battle_sim/chains.lua'},
  {'decks','card_battle_sim/decks.lua'},
  {'battle','card_battle_sim/battle.lua'},
  {'ai','card_battle_sim/ai.lua'},
  {'tabletop.card_art','tabletop/card_art.lua'},
  {'tabletop.library','tabletop/library.lua'},
  {'online.json','online/json.lua'},
  {'online.snapshot','online/snapshot.lua'},
  {'online.view','online/view.lua'},
  {'online.server','online/server.lua'},
}
