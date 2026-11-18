-- Describe the actual tagged deck. These are workshop hints, never deck restrictions.
local Cards=require('data.cards')
local Abilities=require('abilities')
local Chains=require('chains')
local Help={}
local partners={
  ['Fantasy:9']={'Fantasy:2'}, ['Fantasy:62']={'Fantasy:20','Fantasy:49'}, ['Fantasy:44']={'Fantasy:15','Fantasy:25'},
  ['Super:61']={'Super:66'}, ['Super:15']={'Super:57'}, ['Super:27']={'Super:57'}, ['Super:32']={'Super:57'},
}
local function is_orc(c) return c.type=='Unit' and c.name:find('Orc',1,true) end
local ally_conditions={
  ['Water:4']=function(c) return c.fish and c.strength<=2 end,
  ['Water:15']=function(c) return c.strength==2 end,
  ['Water:51']=function(c) return c.strength and c.strength<=2 end,
  ['Super:51']=function(c,source) return c.strength==source.strength end,
  ['Fantasy:22']=is_orc, ['Fantasy:50']=is_orc,
}
function Help.describe(card,deck)
  local counts,strengths={},{}
  for _,id in ipairs(deck) do
    counts[id]=(counts[id] or 0)+1
    local c=Cards.by_id[id]
    if c and c.strength and Chains.eligible(c) then strengths[c.strength]=true end
  end
  local names,seen={},{}
  local function add(id)
    if id and not seen[id] and id~=card.id then
      local c=Cards.by_id[id]
      names[#names+1]=(c.display_name or c.name)..' ×'..(counts[id] or 0)
      seen[id]=true
    end
  end
  for _,id in ipairs(partners[card.id] or {}) do add(id) end
  for _,id in ipairs(card.requires_units or {}) do add(id) end
  add(card.replaces)
  for _,trigger in ipairs({'deploy','play','chain'}) do
    for _,op in ipairs(Abilities.get(card,trigger) or {}) do
      add(op.if_ally or op.unless_ally);add(op.partner);add(op.id)
      for _,id in ipairs(op.characters or {}) do add(id) end
      for _,name in ipairs(op.names or {}) do
        for _,c in ipairs(Cards[card.faction]) do if c.name==name then add(c.id) end end
      end
      if op.op=='recover' and #names==0 then
        local n=0
        for _,id in ipairs(deck) do
          local c=Cards.by_id[id]
          if (op.target=='any' or op.target==c.faction..c.type or c.wild and op.target:sub(-#c.type)==c.type)
              and (not op.max_printed or c.strength<=op.max_printed) then n=n+1 end
        end
        return n..' tagged '..(n==1 and 'card matches' or 'cards match')..' this recovery.'
      end
    end
  end
  local matches=ally_conditions[card.id]
  if matches then
    local n,skipped=0,false
    for _,id in ipairs(deck) do
      if id==card.id and not skipped then skipped=true
      elseif matches(Cards.by_id[id],card) then n=n+1 end
    end
    return n..' other tagged '..(n==1 and 'unit matches' or 'units match')..' this ally condition.'
  end
  if #names>0 then return 'Tagged partners · '..table.concat(names,', ') end
  if card.chain then
    local lo,hi=card.strength,card.strength
    while strengths[lo-1] do lo=lo-1 end
    while strengths[hi+1] do hi=hi+1 end
    if hi-lo+1<card.chain then return 'Tag more consecutive base Strengths to reach Chain '..card.chain..'.' end
    return 'Chain '..card.chain..' is supported by tagged base Strengths '..lo..'–'..hi..'.'
  end
end
return Help
