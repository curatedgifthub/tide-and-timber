local Decks=require('decks')
local Cards=require('data.cards')
local Save=require('save')
local P={}
local function add(collection,id,n) collection[id]=(collection[id] or 0)+(n or 1) end
function P.new(size)
  size=size or 30
  local profile={deck_size=size,collections={Super={},Fantasy={},Water={}},decks={},rewards={},scenarios={}}
  -- The simulator initializes a provisional owned starter inventory for EACH faction,
  -- unlike the future RPG's Super/Fantasy-only starting-faction restriction.
  for _,f in ipairs(Decks.factions) do
    profile.decks[f]=Decks.starter(f,size)
    for _,id in ipairs(profile.decks[f]) do add(profile.collections[f],id) end
  end
  return profile
end
function P.collection(profile,f) return profile.collections[f] end
function P.add(profile,id,amount)
  local c=Cards.by_id[id]
  if not c then return false,'Undefined reward' end
  if not profile.collections[c.faction] then profile.collections[c.faction]={} end
  add(profile.collections[c.faction],id,amount)
  profile.rewards[#profile.rewards+1]={id=id,amount=amount or 1}
  return true
end
function P.award(profile,reward_id,opponent_deck,result)
  if not reward_id then return false,'No reward set' end
  if result~=1 then return false,'No reward: player did not win' end
  if not Cards.by_id[reward_id] then return false,'Undefined reward' end
  if not Decks.counts(opponent_deck)[reward_id] then return false,'Opponent deck does not contain the reward' end
  P.add(profile,reward_id,1)
  return true,reward_id
end
function P.can_use(profile,deck,faction)
  return Decks.validate(deck,faction,profile.deck_size,profile.collections[faction])
end
function P.save(profile,name) return Save.write('progress',name,profile) end
function P.load(name)
  local profile,err=Save.read('progress',name)
  if not profile then return nil,err end
  if type(profile.collections)~='table' or type(profile.decks)~='table' or type(profile.deck_size)~='number' then
    return nil,'Malformed saved profile'
  end
  return profile
end
return P
