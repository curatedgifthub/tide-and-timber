local C=require('data.cards')
local Rules=require('rules')
local D={}
D.factions={}
D.specs={}
for _,spec in ipairs(require('data.factions')) do
  if spec.primary~=false then D.factions[#D.factions+1]=spec.id end
  D.specs[spec.id]=spec
end
function D.permits(faction,card)
  if card.faction==faction then return true end
  for _,neutral in ipairs(D.specs[faction].neutral or {}) do
    if card.faction==neutral then return true end
  end
  return false
end
-- Provisional starting lists: 24 Common Units and 6 Common Effects, one copy each.
function D.starter(faction,size)
  assert(C[faction], 'Unknown faction: '..tostring(faction))
  size=size or 30; local deck={}
  local options={}
  for i=1,40 do options[#options+1]=faction..':'..i end
  local order={}
  for i=1,24 do order[#order+1]=options[i] end
  for i=31,40 do order[#order+1]=options[i] end
  for i=25,30 do order[#order+1]=options[i] end
  for i=1,40 do if not (i<=24 or i>=31) then order[#order+1]=options[i] end end
  for i=1,size do
    local id=order[(i-1)%#order+1]
    deck[#deck+1]=id
  end
  local valid,msg=D.validate(deck,faction,size)
  if not valid then error('No valid provisional starter for size '..size..': '..msg) end
  return deck
end
function D.validate_partial(deck,faction,size,collection)
  size=size or 30
  if type(deck)~='table' or type(size)~='number' or size<10 or size%1~=0 then
    return false,'Deck must be a table and size must be an integer >= 10'
  end
  if not D.specs[faction] or D.specs[faction].primary==false then return false,'Unknown primary faction' end
  if #deck>size then return false,string.format('Deck has %d cards; maximum %d',#deck,size) end
  local counts={}
  for _,id in ipairs(deck) do
    local card=C.by_id[id]
    if not card then return false,'Undefined card: '..tostring(id) end
    if not D.permits(faction,card) then return false,'Off-faction card: '..id end
    counts[id]=(counts[id] or 0)+1
    local limit=card.copy_limit or 3
    if counts[id]>limit then return false,'Duplicate limit exceeded for '..card.name end
    if collection and counts[id]>(collection[id] or 0) then return false,'Not owned: '..card.name end
  end
  return true
end
function D.validate(deck,faction,size,collection)
  size=size or 30
  local ok,err=D.validate_partial(deck,faction,size,collection)
  if not ok then return false,err end
  if #deck~=size then return false,string.format('Deck has %d cards; expected %d',#deck,size) end
  return true
end
function D.collection_size(faction)
  local spec=D.specs[faction]
  if not spec or spec.primary==false then return 0 end
  return #C[faction]+#(spec.neutral_cards or {})
end
function D.validate_selection(deck,faction,collection)
  return D.validate(deck,faction,Rules.deck_size,collection)
end
function D.counts(deck)
  local c={};for _,id in ipairs(deck) do c[id]=(c[id] or 0)+1 end;return c
end
function D.remove(deck,id)
  for i,v in ipairs(deck) do if v==id then table.remove(deck,i);return true end end
  return false
end
function D.replace(deck,old_id,new_id,faction,size,collection)
  local d={}; for i,id in ipairs(deck) do d[i]=id end
  if not D.remove(d,old_id) then return nil,'Old card not in deck' end
  d[#d+1]=new_id
  local ok,err=D.validate_partial(d,faction,size,collection)
  if not ok then return nil,err end
  return d
end
return D
