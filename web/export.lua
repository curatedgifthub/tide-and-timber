-- Run from the project root. Use the same collection, validation and starter
-- routines as the desktop workshop, including edition and artwork eligibility.
package.path = "card_battle_sim/?.lua;" .. package.path

local library = require("tabletop.library")
local json = require("online.json")
local config = require("online.config")
local catalog = {
  config = {url = config.url, key = config.key},
  deckSize = require("rules").deck_size,
  opening = require("rules").starting_hand,
  cards = json.object({}),
  factions = {},
}

for _, id in ipairs(library.factions) do
  local spec = library.specs[id]
  local draft = library.new()
  draft.factions[1] = id
  library.starter(draft, 1)
  assert(library.valid(draft, 1))
  local faction = {
    id = id, label = library.label(id), featured = library.cards[id][spec.featured].id,
    emblem = spec.emblem, color = spec.color, ink = spec.ink, paper = spec.paper,
    cards = {}, limits = library.owned[id], starter = draft.decks[1],
  }
  catalog.factions[#catalog.factions + 1] = faction
  for _, card in ipairs(library.collection(id)) do
    faction.cards[#faction.cards+1] = card.id
    local exported = {}
    for key, value in pairs(card) do exported[key] = value end
    exported.art = assert(library.art[card.id])
    catalog.cards[card.id] = exported
  end
end
io.write(json.encode(catalog))
