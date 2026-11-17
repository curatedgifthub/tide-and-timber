local Cards = require('data.cards')
local Decks = require('decks')
-- The playable pool is exactly the set of cards with their own illustration.
-- A catalog entry without artwork is not part of the game: it never appears in
-- the workshop, cannot be drafted, and is removed (with a report) from old presets.
local Art = require('tabletop.card_art')
local Library = {cards=Cards, factions={}, specs=Decks.specs, owned={}, art=Art, pool={}}
local function enabled(spec,number)
  for _,entry in ipairs(spec.enabled) do
    local lo,hi=entry,entry
    if type(entry)=='table' then lo,hi=entry[1],entry[2] end
    if number>=lo and number<=hi then return true end
  end
  return false
end
for _,faction in ipairs(Decks.factions) do
  local spec=Library.specs[faction]
  local owned,pool={},{}
  for _,card in ipairs(Cards[faction]) do
    if Art[card.id] and enabled(spec,card.number) then
      owned[card.id]=card.copy_limit or 3;pool[#pool+1]=card
    end
  end
  for _,id in ipairs(spec.neutral_cards or {}) do
    local card=assert(Cards.by_id[id])
    assert(Decks.permits(faction,card))
    if Art[id] then owned[id]=card.copy_limit or 3;pool[#pool+1]=card end
  end
  Library.owned[faction]=owned;Library.pool[faction]=pool
  -- A faction with no illustrated cards has nothing to play and is not offered.
  if #pool>0 then Library.factions[#Library.factions+1]=faction end
end

function Library.collection(faction) return Library.pool[faction] or {} end
-- Maximum Battle Deck size: one of each design in the playable collection.
function Library.size(faction) return #(Library.pool[faction] or {}) end

-- Both ways to play run on the game server. Seat 1 is always this player's own draft;
-- seat 2 is the computer's deck in a single-player match and unused in a two-player one,
-- where the other person brings their own.
Library.modes={
  {name="Single Player (Online)",kind="solo",controllers={"Human","AI"},note="Play against the computer."},
  {name="Two Players (Online)",kind="duel",controllers={"Human","Human"},note="Play another person over the internet."},
}
-- The name shown for a faction ("Super" is presented as the Comic deck).
function Library.label(faction) return Library.specs[faction].label or faction end

function Library.new()
  return {mode=1, controllers={"Human","AI"}, factions={"Fantasy","Water"}, decks={{},{}},seed=nil,difficulty="normal"}
end

function Library.set_mode(cfg,i)
  cfg.mode=i
  local controllers=Library.modes[i].controllers
  cfg.controllers={controllers[1],controllers[2]}
end
-- The computer may be left without a deck: the server then gives it its faction's starter.
function Library.computer_ready(cfg)
  return #cfg.decks[2]==0 or Library.valid(cfg,2)
end

function Library.valid(cfg,p)
  return Decks.validate_selection(cfg.decks[p],cfg.factions[p],Library.owned[cfg.factions[p]],Library.size(cfg.factions[p]))
end

function Library.edit(cfg,p,id,delta)
  local deck=cfg.decks[p]
  if delta<0 then
    if Decks.remove(deck,id) then return true end
    return false,"This copy is outside your deck."
  end
  deck[#deck+1]=id
  local ok,why=Decks.validate_partial(deck,cfg.factions[p],Library.size(cfg.factions[p]),Library.owned[cfg.factions[p]])
  if not ok then table.remove(deck) end
  return ok,why
end

-- A suggested selection is applied only on request. Include the faction's
-- featured Unit and a mix of printed ranks, Bridge, recovery and combat.
function Library.starter(cfg,p,size)
  size=size or 30
  local f=cfg.factions[p]
  local deck,seen={},{}
  local spec=Library.specs[f]
  local order=spec.starter or {spec.featured,1,2,3,4,21,28,31,32,40,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,23,25,29,33,39}
  local function take(id)
    if #deck<size and Library.owned[f][id] and not seen[id] then
      deck[#deck+1]=id;seen[id]=true
    end
  end
  for _,n in ipairs(order) do take(f..':'..n) end
  for _,c in ipairs(Library.collection(f)) do take(c.id) end
  for _,c in ipairs(Library.collection(f)) do
    for _=2,Library.owned[f][c.id] or 0 do
      if #deck<size then deck[#deck+1]=c.id end
    end
  end
  cfg.decks[p]=deck
end

function Library.full(cfg,p)
  local f=cfg.factions[p]
  local deck={}
  for _,card in ipairs(Library.collection(f)) do deck[#deck+1]=card.id end
  cfg.decks[p]=deck
end

-- Fixed, non-executable text format. A preset includes both deck drafts. The seed and
-- controller lines remain from the local-play format; online they follow from the mode.
function Library.encode(c)
  local controllers=Library.modes[c.mode].controllers
  return table.concat({"TT2",c.mode,"random",controllers[1],controllers[2],
    c.factions[1],table.concat(c.decks[1],","),c.factions[2],table.concat(c.decks[2],",")},"\n").."\n"
end
function Library.decode(raw)
  if type(raw)~='string' or #raw>16000 then return nil,"Invalid preset file." end
  local l={}
  for line in raw:gmatch("([^\n]*)\n") do l[#l+1]=line end
  local c=Library.new();c.removed={}
  if l[1]=="TT1" and #l==10 then
    local oldSize=tonumber(l[2])
    if not oldSize or oldSize%1~=0 or oldSize<10 or oldSize>40 then return nil,"Invalid legacy size." end
    table.remove(l,2)
  elseif l[1]~="TT2" or #l~=9 then return nil,"Unsupported setup." end
  c.mode,c.seed=tonumber(l[2]),tonumber(l[3])
  if not c.mode or c.mode%1~=0 or c.mode<1 or c.mode>4 then return nil,"Unknown match format." end
  -- Presets saved before online play used four local formats; they load as single player.
  if not Library.modes[c.mode] then c.mode=1 end
  Library.set_mode(c,c.mode)
  if l[3]~="random" and (not c.seed or c.seed%1~=0 or c.seed<1 or c.seed>2147483646) then return nil,"Invalid seed." end
  c.seed=nil -- the server deals every online match
  for p=1,2 do
    local f=l[4+2*p]
    if not Library.owned[f] or Library.size(f)==0 or (l[3+p]~="Human" and l[3+p]~="AI") then return nil,"Unknown faction or controller." end
    c.factions[p]=f
    for id in l[5+2*p]:gmatch("[^,]+") do
      local card=Cards.by_id[id]
      if card and Decks.permits(f,card) and not Library.owned[f][id] then
        c.removed[#c.removed+1]=id
      else c.decks[p][#c.decks[p]+1]=id end
    end
    local ok,why=Decks.validate_partial(c.decks[p],f,Library.size(f),Library.owned[f])
    if not ok then return nil,why end
  end
  return c
end
return Library
