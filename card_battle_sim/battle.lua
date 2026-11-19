-- Pure Lua battle engine. No input/output or Love2D dependency.
local C = require('data.cards')
local A = require('abilities')
local Chains = require('chains')
local Decks = require('decks')
local Rules = require('rules')
local U = require('util')
local B = {}

-- Optional simulation observations. Only actual resource changes are counted.
local function measure(s,u,event,n)
  if s.observe and u and n~=0 then s.observe(u.card.id,event,n or 1) end
end
local function other(p) return 3-p end
local function emit(s,msg)
  if #s.log<30000 then s.log[#s.log+1]=msg end
  if s.on_event then s.on_event(msg,s) end
end
local function owner_discard(s,unit)
  unit.hp=nil;unit.mod=0;unit.guard=0;unit.negate_damage=false
  unit.disabled=false;unit.activated={};unit.controller=unit.owner
  s.players[unit.owner].discard[#s.players[unit.owner].discard+1]=unit
end
local function all_units(s,p)
  local t={}
  for _,row in ipairs(s.players[p].rows) do for _,u in ipairs(row) do t[#t+1]=u end end
  return t
end
local function has_unit(s,p,id)
  for _,unit in ipairs(all_units(s,p)) do
    if unit.card.id==id then return true end
  end
  return false
end
local function is_deployed(s,u)
  if not u then return false end
  for p=1,2 do for _,row in ipairs(s.players[p].rows) do for _,x in ipairs(row) do if x==u then return true,p end end end end
  return false
end
function B.position(s,u)
  for p=1,2 do for r,row in ipairs(s.players[p].rows) do
    for i,x in ipairs(row) do if x==u then return p,r,i end
  end end end
end
local function adjacent(s,u)
  local p,r,i=B.position(s,u); local a={}
  if not p then return a end
  local row=s.players[p].rows[r]
  if row[i-1] then a[#a+1]=row[i-1] end
  if row[i+1] then a[#a+1]=row[i+1] end
  return a
end
local function immune_area(u) return u.card.id=='Water:61' and not u.disabled end
local function immune_reduction(s,u,actor)
  if actor==u.controller then return false end
  if not u.disabled and (u.card.id=='Water:27' or u.card.id=='Super:22' or u.card.id=='Super:61') then return true end
  for _,a in ipairs(adjacent(s,u)) do
    if a.card.id=='Water:44' and not a.disabled then return true end
  end
  return false
end
local function immune_move(u,actor)
  return actor~=u.controller and not u.disabled and ({['Fantasy:23']=true,['Fantasy:48']=true,['Water:54']=true,['Super:14']=true,['Super:61']=true})[u.card.id]
end
local function combo(s,p,names)
  local found={}
  for _,u in ipairs(all_units(s,p)) do found[u.card.name]=true end
  for _,name in ipairs(names) do if not found[name] then return false end end
  return true
end
local function base_strength(s,u)
  local v=u.card.strength+(u.mod or 0)
  if not u.disabled then
    local id=u.card.id
    if id=='Water:4' then
      for _,a in ipairs(adjacent(s,u)) do if a.card.fish and a.card.strength<=2 then v=v+1;break end end
    elseif id=='Water:15' then
      for _,a in ipairs(adjacent(s,u)) do if a.card.strength==2 then v=v+1;break end end
    elseif id=='Water:51' then
      local count=0
      for _,a in ipairs(all_units(s,u.controller)) do if a~=u and a.card.strength<=2 then count=count+1 end end
      v=v+math.min(2,count)
    elseif id=='Fantasy:9' then
      for _,a in ipairs(adjacent(s,u)) do if a.card.name=='Goblin Sneak' then v=v+1;break end end
    elseif id=='Fantasy:44' then
      for _,a in ipairs(adjacent(s,u)) do if a.card.name=='Stone Troll' or a.card.name=='Trollkin Brawler' then v=v+2;break end end

    end
  end
  -- Only Orcs receive the two continuous Orc support auras.
  if not u.card.name:find("Orc",1,true) or immune_area(u) then return v end
  for _,source in ipairs(all_units(s,u.controller)) do
    if source~=u and not source.disabled and not immune_area(u) then
      local id=source.card.id
      if id=='Fantasy:22' and U.contains(adjacent(s,source),u) and u.card.name:find('Orc',1,true) then v=v+1 end
      if id=='Fantasy:50' and u.card.name:find('Orc',1,true) then v=v+1 end
    end
  end
  return v
end
local function current_strength(s,u)
  local base=base_strength(s,u)
  if u.card.id~='Super:46' or u.disabled then return math.max(0,base) end
  -- A pair of opposing Marauders can depend on each other's bonus. Resolve the
  -- two capped bonuses to a stable pair, giving the active seat first priority.
  local gaps={{},{}}
  local weak={0,0}
  for p=1,2 do
    for _,v in ipairs(all_units(s,p)) do
      local gap=v.card.strength-base_strength(s,v)
      if gap>0 then
        if v.card.id=='Super:46' and not v.disabled then table.insert(gaps[p],gap)
        else weak[p]=weak[p]+1 end
      end
    end
  end
  local function below(p,bonus)
    local n=weak[p]
    for _,gap in ipairs(gaps[p]) do if gap>bonus then n=n+1 end end
    return math.min(3,n)
  end
  local first=s.active
  local second=other(first)
  local bonus={0,0}
  repeat
    local previous=bonus[second]
    bonus[first]=below(second,previous)
    bonus[second]=below(first,bonus[first])
  until previous==bonus[second]
  return math.max(0,base+bonus[u.controller])
end
B.strength=current_strength
function B.score(s,p)
  local result=0
  for _,u in ipairs(all_units(s,p)) do result=result+u.hp end
  return result
end
function B.units(s,p) return all_units(s,p) end
local function location(u)
  return u.card.display_name or u.card.name
end
function B.choose(s,actor,kind,options,context)
  if #options==0 then return nil end
  if s.chooser then
    local index=s.chooser(s,actor,kind,options,context)
    if index==0 and context and context.optional then return nil end
    if type(index)=='number' and index>=1 and index<=#options and index%1==0 then return options[index] end
  end
  if kind=='row' and context and (context.enemy or context.op=='maelstrom') then
    local rows=s.players[other(actor)].rows
    return #rows[2]>#rows[1] and 2 or 1
  end
  if kind=='unit' then
    if context and (context.op=='damage' or context.op=='deploy_attack' or context.op=='destroy') then
      local best=options[1]
      for _,u in ipairs(options) do if u.hp<=best.hp then best=u end end
      return best
    end
    if context and context.op=='heal' then
      local best=options[1]
      for _,u in ipairs(options) do if u.card.health-u.hp>best.card.health-best.hp then best=u end end
      return best
    end
    if context and (context.op=='debuff' or context.op=='take') then
      local best=options[1]
      for _,u in ipairs(options) do if current_strength(s,u)>current_strength(s,best) then best=u end end
      return best
    end
    if context and context.op=='give' then
      local best=options[1]
      for _,u in ipairs(options) do if current_strength(s,u)<current_strength(s,best) then best=u end end
      return best
    end
  end
  return options[1]
end
local function pick_unit(s,actor,candidates,context)
  if #candidates==0 then return nil end
  return B.choose(s,actor,'unit',candidates,context)
end
local function targets(s,actor,source,target,op)
  local mine=all_units(s,actor); local enemy=all_units(s,other(actor));local out={}
  if target=='self' then return source and {source} or {} end
  if target=='ally' then
    for _,u in ipairs(mine) do if u~=source and u.card.id==op.ally then out[#out+1]=u end end
    return out
  end
  if target=='friend' or target=='friends' or target=='two_friends' or target=='two_debuffed_friends' or target=='other_friend' then
    for _,u in ipairs(mine) do if (target~='other_friend' or u~=source) and (target~='two_debuffed_friends' or current_strength(s,u)<u.card.strength) then out[#out+1]=u end end
  elseif target=='enemy' or target=='enemies' then out=enemy
  elseif target=='enemy_front' or target=='enemy_back' then
    for _,u in ipairs(s.players[other(actor)].rows[target=='enemy_front' and 1 or 2]) do out[#out+1]=u end
  elseif target=='adjacent' then out=source and adjacent(s,source) or {}
  elseif target=='friend_row' or target=='other_friendly_row' then
    local row= B.choose(s,actor,'row',{1,2},{op='row'}) or 1
    for _,u in ipairs(s.players[actor].rows[row]) do if target~='other_friendly_row' or u~=source then out[#out+1]=u end end
  elseif target=='enemy_row' then
    local row=B.choose(s,actor,'row',{1,2},{op='row',enemy=true}) or 1
    for _,u in ipairs(s.players[other(actor)].rows[row]) do out[#out+1]=u end
  elseif target=='chain' then
    if source then
      local chain=Chains.qualify(s.players[actor],source,3,false)
      if chain then out=chain.units end
    else
      local chains=Chains.find(s.players[actor]); if #chains>0 then
        local ch=B.choose(s,actor,'chain',chains,{op='chain'}) or chains[1]
        out=ch.units
      end
    end
  end
  return out
end
local function discard_card(s,card)
  owner_discard(s,card)
  s.stats.discarded[card.owner]=s.stats.discarded[card.owner]+1
end
local function draw(s,p,n,source,turn_draw)
  local pl=s.players[p]
  local before=#pl.deck
  local cards={}
  while #cards<n and #pl.deck>0 and #pl.hand<s.max_hand do
    local card=table.remove(pl.deck)
    card.controller=p
    pl.hand[#pl.hand+1]=card
    cards[#cards+1]=card
  end
  measure(s,source,"drawn",#cards)
  if #cards==0 then measure(s,source,'empty_draws') end
  s.stats.drawn[p]=s.stats.drawn[p]+#cards
  local reason
  if #cards<n then reason=#pl.deck==0 and 'draw deck empty' or 'hand full' end
  local label=source and source.card.name or pl.name
  local message=string.format('%s drew %d of %d (draw deck %d → %d).',label,#cards,n,before,#pl.deck)
  if reason then message=message..' '..reason..'.' end
  emit(s,message)
  if s.on_draw and (source or turn_draw) then
    s.on_draw({seat=p,source=source and source.card.name or "Turn draw",cards=cards,before=before,remaining=#pl.deck,reason=reason,requested=n})
  end
  return #cards
end
B.draw=draw
local function choose_card(s,actor,kind,pile,predicate,optional)
  local choices={}
  for _,card in ipairs(pile) do if not predicate or predicate(card) then choices[#choices+1]=card end end
  return B.choose(s,actor,kind,choices,{op=kind,optional=optional})
end
local function recover(s,p,n,predicate,optional)
  local count=0
  for i=1,n do
    if #s.players[p].hand>=s.max_hand then break end
    local pile=s.players[p].discard
    local card=choose_card(s,p,'card',pile,predicate,optional)
    if not card then break end
    U.remove(pile,card);card.controller=p
    s.players[p].hand[#s.players[p].hand+1]=card;count=count+1
    emit(s,s.players[p].name..' recovers '..card.card.name..'.')
  end
  return count
end
local function kill(s,u,actor,method)
  local p,r,i=B.position(s,u)
  if not p then return false end
  table.remove(s.players[p].rows[r],i)
  emit(s,location(u)..' is removed ('..method..').')
  local id=u.card.id
  if (method=='damage' or method=='destroy') and actor and actor~=p then
    for _,shark in ipairs(all_units(s,actor)) do
      if shark.card.id=='Water:50' and not shark.disabled and not shark.fed then
        shark.fed=true;shark.mod=shark.mod+2;emit(s,location(shark)..' gains +2 Strength (Blood in the Water).')
      end
    end
  end
  if method~='round_end' and method~='return' and id=='Fantasy:65' and not u.rebirth_used then
    u.rebirth_used=true
    if #s.players[u.owner].hand<s.max_hand then
      u.hp=nil;u.mod=0;u.controller=u.owner;u.guard=0;u.activated={}
      s.players[u.owner].hand[#s.players[u.owner].hand+1]=u
      emit(s,'Phoenix of Ash returns to its owner hand (once per match).')
      return true
    end
  end
  discard_card(s,u)
  if method~='round_end' and method~='return' and (id=='Water:16' or id=='Water:43' or id=='Fantasy:20' or id=='Super:53') then
    if id=='Fantasy:20' then draw(s,p,1,u)
    else
      local effect=A.get(u.card,'death')
      if effect then B.resolve(s,p,u,effect,{last_breath=true}) end
    end
  end
  return true
end
local function damage(s,actor,u,amount,flags)
  if not is_deployed(s,u) then return false end
  if amount<=0 then return false end
  flags=flags or {}
  if flags.area and immune_area(u) then measure(s,u,'prevented',math.min(amount,u.hp));return false end
  local prevented=0
  if not flags.piercing then
    if u.negate_damage and actor~=u.controller then u.negate_damage=false;measure(s,u,'prevented',math.min(amount,u.hp));emit(s,location(u)..' avoids the opposing damage effect.');return false end
    if u.card.id=='Water:17' and not u.disabled and not u.shell_used then
      prevented=math.min(amount,2);u.shell_used=true
    end
    if u.guard and u.guard>0 then
      local n=math.min(amount-prevented,u.guard); prevented=prevented+n;u.guard=u.guard-n
    end
  end
  measure(s,u,'prevented',math.min(amount,u.hp)-math.min(amount-prevented,u.hp))
  local controller=u.controller
  local spines=u.card.id=='Water:23' and not u.disabled and actor~=controller
  local dealt=math.max(0,amount-prevented)
  if dealt>0 then
    local before=u.hp;u.hp=math.max(0,u.hp-dealt)
    measure(s,flags.source,flags.kind or 'special_damage',before-u.hp)
    if flags.source and flags.kind==nil and actor==controller then measure(s,flags.source,'friendly_damage',before-u.hp) end
    emit(s,location(u)..' takes '..dealt..' damage (HP '..before..' -> '..u.hp..').')
    if u.hp==0 then kill(s,u,actor,'damage') end
    if u.card.id=='Water:73' and is_deployed(s,u) and not u.disabled and actor~=controller then
      local before=current_strength(s,u);u.mod=u.mod+2
      emit(s,location(u)..' is Relentless (Strength '..before..' -> '..current_strength(s,u)..').')
    end
    if spines then
      local t=pick_unit(s,controller,all_units(s,actor),{op='damage'})
      if t then damage(s,controller,t,1,{source=u}) end
    end
  elseif prevented>0 then emit(s,location(u)..' prevents '..prevented..' damage.') end
  return dealt>0
end
B.damage=damage
local function buff(s,actor,u,n,area)
  if not is_deployed(s,u) or (area and immune_area(u)) then return false end
  if n<0 and immune_reduction(s,u,actor) then
    emit(s,location(u)..' is immune to Strength reduction.');return false
  end
  local before=current_strength(s,u)
  -- Printed Strength and current Strength are distinct; penalties cannot push below zero.
  u.mod=u.mod+n
  emit(s,location(u)..' Strength '..before..' -> '..current_strength(s,u)..'.')
  return true
end
local function move_unit(s,actor,u,dest_row,dest_pos)
  local p,row,pos=B.position(s,u)
  if not p or immune_move(u,actor) then return false end
  local old=s.players[p].rows[row]
  table.remove(old,pos)
  local new=s.players[p].rows[dest_row]
  dest_pos=math.max(1,math.min(#new+1,dest_pos))
  table.insert(new,dest_pos,u)
  emit(s,location(u)..' moves to '..(dest_row==1 and 'Front' or 'Back')..' position '..dest_pos..'.')
  return true
end
-- The top of a draw deck is its last element; from_bottom examines deck[1], deck[2], ...
local function search_deck(s,actor,n,filter,full,from_bottom,source)
  local pl=s.players[actor];local peek={}
  local count=math.min(n,#pl.deck)
  for i=1,count do peek[#peek+1]=from_bottom and pl.deck[i] or pl.deck[#pl.deck-i+1] end
  local function qualifies(instance)
    local card=instance.card
    return filter=='any' or filter==card.faction..card.type
  end
  local eligible={}
  for _,card in ipairs(peek) do if qualifies(card) then eligible[#eligible+1]=card end end
  local chosen
  if #pl.hand<s.max_hand then chosen=B.choose(s,actor,'card',eligible,{op='search',cards=peek,bottom=from_bottom}) end
  local where=from_bottom and 'the bottom of the draw deck' or 'the draw deck'
  if chosen then
    measure(s,source,'searched')
    U.remove(pl.deck,chosen);chosen.controller=actor;pl.hand[#pl.hand+1]=chosen
    emit(s,pl.name..' searches '..where..' and takes a card.')
  elseif count==0 then emit(s,pl.name..' searches '..where..', but it is empty.')
  else emit(s,pl.name..' searches '..where..' but takes no card.') end
  if full then s.rng:shuffle(pl.deck) else
    if chosen then U.remove(peek,chosen) end
    for _,card in ipairs(peek) do U.remove(pl.deck,card) end
    while #peek>0 do
      local card=B.choose(s,actor,'bottom_order',peek,{op='bottom_order'})
      U.remove(peek,card)
      table.insert(pl.deck,1,card)
    end
  end
end
local function play_extra(s,actor,n)
  if actor~=s.active then
    local pl=s.players[actor]
    pl.bonus_next=(pl.bonus_next or 0)+n
    emit(s,pl.name..' earns '..n..' additional card play(s) for their next turn.')
    return
  end
  s.plays_left=s.plays_left+n
  emit(s,s.players[actor].name..' gains '..n..' additional card play(s) this turn.')
end
local showdown
local function op_predicate(card,kind,operation)
  local c=card.card
  if kind=='any' then return true end
  if c.wild then
    if kind:sub(-#c.type)~=c.type then return false end
  elseif kind~=c.faction..c.type then return false end
  if operation and operation.max_printed and c.strength>operation.max_printed then return false end
  if operation and operation.exact_printed and c.strength~=operation.exact_printed then return false end
  return true
end
-- Puts a Unit that did not come from a normal card play onto the battlefield.
-- A Double Agent always lands on the battlefield opposite the player who deploys it.
local function prepare_unit(s,c,side)
  c.hp=c.card.health;c.mod=0;c.guard=0;c.negate_damage=false;c.activated={}
  c.disabled=false;c.controller=side
  if c.card.agent then c.owner=side end
end
local function enter(s,actor,c,opname,verb)
  local side=c.card.agent and other(actor) or actor
  prepare_unit(s,c,side)
  local row=B.choose(s,actor,'row',{1,2},{op=opname,enemy=side~=actor or nil}) or 2
  local lane=s.players[side].rows[row]
  local positions={};for i=1,#lane+1 do positions[i]=i end
  local pos=B.choose(s,actor,'position',positions,{op=opname,row=row,unit=c})
  table.insert(lane,pos,c)
  emit(s,location(c)..' '..verb..' '..(side~=actor and s.players[side].name..' ' or '')..(row==1 and 'Front' or 'Back')..'.')
  B.resolve(s,actor,c,A.get(c.card,'deploy'),{})
end
local function take_named(piles,id)
  for _,pile in ipairs(piles) do
    for i,unit in ipairs(pile) do
      if unit.card.id==id then return table.remove(pile,i),pile end
    end
  end
end
-- Only the controller receives these options. A deck search discloses eligible
-- designs, never the shuffle order, and moves the selected physical copy.
local function grave_whisper(s,actor,source,op)
  local pl=s.players[actor]
  if #pl.hand>=s.max_hand then return end
  local choices={discard={},deck={}}
  local zones={}
  for _,zone in ipairs({'discard','deck'}) do
    for _,u in ipairs(pl[zone]) do
      if u.card.type=='Unit' and u.card.strength<=op.max_printed then
        table.insert(choices[zone],u)
      end
    end
    if #choices[zone]>0 then zones[#zones+1]=zone end
  end
  if #zones==0 then draw(s,actor,1,source);return end
  local zone=#zones==1 and zones[1] or B.choose(s,actor,'zone',zones,{op='grave_zone'})
  if zone=='deck' then
    table.sort(choices.deck,function(a,b)
      if a.card.name==b.card.name then return a.uid<b.uid end
      return a.card.name<b.card.name
    end)
  end
  local chosen=B.choose(s,actor,'card',choices[zone],{op=zone=='deck' and 'grave_search' or 'grave_recover'})
  U.remove(pl[zone],chosen)
  chosen.controller=actor
  pl.hand[#pl.hand+1]=chosen
  if zone=='deck' then
    s.rng:shuffle(pl.deck)
    measure(s,source,'searched')
    s.stats.drawn[actor]=s.stats.drawn[actor]+1
    emit(s,source.card.name..' takes a unit from the draw deck and shuffles.')
    if s.on_draw then s.on_draw({seat=actor,source=source.card.name,cards={chosen},before=#pl.deck+1,remaining=#pl.deck,requested=1}) end
  else
    measure(s,source,'recovered')
    emit(s,source.card.name..' recovers '..chosen.card.name..'.')
  end
end
function B.resolve(s,actor,source,operations,context)
  context=context or {};local last_target=nil
  if operations and #operations>0 and source and source.card then
    measure(s,source,'resolutions')
    local id=source.card.id
    s.stats.abilities[id]=(s.stats.abilities[id] or 0)+1
  end
  for _,op in ipairs(operations or {}) do
    s.activation_count=s.activation_count+1
    if s.activation_count>Rules.max_activations_per_action then
      s.error='Exceeded the activation safety limit';error(s.error)
    end
    local name=op.op;local amount=op.n or 0
    local allowed=true
    measure(s,source,'operations')
    if op.requires=='no_wounds' then
      for _,u in ipairs(all_units(s,actor)) do if u.hp<u.card.health then allowed=false;break end end
    end
    if op.requires=='frontrow' then local _,r=B.position(s,source);allowed=(r or context.entry_row)==1 end
    if op.requires=='backrow' then local _,r=B.position(s,source);allowed=(r or context.entry_row)==2 end
    if op.requires=='back_ally' then
      allowed=false
      for _,u in ipairs(s.players[actor].rows[2]) do if u~=source then allowed=true;break end end
    end
    if op.requires=='friend_str4' then
      allowed=false;for _,u in ipairs(all_units(s,actor)) do if u~=source and u.card.strength>=4 then allowed=true end end
    end
    if op.requires=='other_str1' then
      allowed=false;for _,u in ipairs(all_units(s,actor)) do if u~=source and u.card.strength==1 then allowed=true end end
    end
    if op.requires=='three_strengths' then
      local found={};for _,u in ipairs(all_units(s,actor)) do found[u.card.strength]=true end
      allowed=U.count(found)>=3
    end
    if op.requires=='friend_same_printed' then
      allowed=false;for _,u in ipairs(all_units(s,actor)) do if u~=source and u.card.strength==source.card.strength then allowed=true end end
    end
    if op.requires=='chain4' then allowed=#Chains.find(s.players[actor])>0
      if allowed then allowed=false;for _,ch in ipairs(Chains.find(s.players[actor])) do if ch.length>=4 then allowed=true end end end
    end
    if op.requires=='long_chain' then allowed=context.chain and context.chain.length>=5 end
    if op.requires=='cross_chain' then allowed=context.chain and context.chain.cross or false end
    if op.requires=='behind' then
      -- Last Stand is stronger only if the caster is behind BEFORE it resolves.
      if B.score(s,actor)>=B.score(s,other(actor)) then amount=op.fallback_n or 1 end
    end
    if op.requires=='undead_friendly' then
      allowed=false;for _,u in ipairs(all_units(s,actor)) do
        if u.card.name=='Crypt Skeleton' or u.card.name=='Night Wraith' then allowed=true end
      end
    end
    if op.only_survivor then allowed=last_target and is_deployed(s,last_target)~=false end
    if op.if_ally or op.unless_ally then
      local id,found=op.if_ally or op.unless_ally,false
      for _,u in ipairs(all_units(s,actor)) do if u~=source and u.card.id==id then found=true end end
      allowed=allowed and found==(op.if_ally~=nil)
    end
    if op.other_friends then
      local count=0
      for _,u in ipairs(all_units(s,actor)) do if u~=source then count=count+1 end end
      amount=math.min(op.other_friends,count)
    end
    if allowed then
      measure(s,source,'conditions_met')
      if op.if_ally and op.if_ally=='Super:75' and name=='damage' then measure(s,source,'named_bonus') end
      if op.if_ally and op.if_ally=='Super:74' and op.target=='self' then measure(s,source,'named_bonus') end
      if name=='draw' then draw(s,actor,amount,source)
      elseif name=='buff' or name=='debuff' or name=='damage' or name=='heal' or name=='guard' then
        local which=op.target
        local choices={}
        if which=='chain' and not source.card.chain then
          local eligible={}
          for _,ch in ipairs(Chains.find(s.players[actor])) do
            if ch.length >= (op.min_chain or 3) then eligible[#eligible+1]=ch end
          end
          local chosen=B.choose(s,actor,'chain',eligible,{op='chain'})
          choices=chosen and chosen.units or {}
        elseif which=='chain' and context.chain then choices=context.chain.units
        elseif which=='last_target' then choices=last_target and {last_target} or {}
        else choices=targets(s,actor,source,which,op) end
        if name=='heal' then
          local wounded={}
          for _,u in ipairs(choices) do if u.hp and u.hp<u.card.health then wounded[#wounded+1]=u end end
          choices=wounded
          if #choices==0 then measure(s,source,'empty_heals') end
        end
        local area=which=='friends' or which=='enemies' or which=='enemy_row' or which=='friend_row' or which=='other_friendly_row' or which=='chain'
        local multi=area or which=='two_friends' or which=='two_debuffed_friends'
        local selected={}
        if multi then
          if which=='two_friends' or which=='two_debuffed_friends' then
            for j=1,2 do local t=pick_unit(s,actor,choices,{op=name,optional=op.optional})
              if not t then break end
              selected[#selected+1]=t;U.remove(choices,t)
            end
          else selected=choices end
        else
          local filtered={}
          for _,u in ipairs(choices) do if is_deployed(s,u) and (not op.min_printed or u.card.strength>=op.min_printed) then filtered[#filtered+1]=u end end
          local t=pick_unit(s,actor,filtered,{op=name})
          if t then selected={t} end
        end
        if #selected==0 and not multi and name~='heal' then emit(s,'No eligible Unit for '..name..'.') end
        for _,u in ipairs(selected) do
          if is_deployed(s,u) then
            if name=='buff' then buff(s,actor,u,amount,area)
            elseif name=='debuff' then buff(s,actor,u,-amount,area)
            elseif name=='damage' then
              local hit=amount
              if op.wounded_bonus and u.hp<u.card.health then hit=hit+op.wounded_bonus end
              if op.back_bonus and (select(2,B.position(s,source)) or context.entry_row)==2 then hit=hit+op.back_bonus end
              if op.crowded_bonus then
                local side,row=B.position(s,u)
                if (area and #selected or #s.players[side].rows[row])>=(op.crowd_size or 2) then hit=hit+op.crowded_bonus end
              end
              damage(s,actor,u,hit,{area=area,piercing=op.piercing,source=source})
            elseif name=='heal' then
              if not area or not immune_area(u) then
                local before=u.hp
                local hp=amount
                if op.optional then
                  local values={}
                  for n=math.min(amount,u.card.health-u.hp),0,-1 do values[#values+1]=n end
                  hp=B.choose(s,actor,'amount',values,{op='heal',unit=u})
                end
                u.hp=math.min(u.card.health,u.hp+hp)
                measure(s,source,'healed',u.hp-before)
                if u.hp>before then emit(s,location(u)..' heals '..(u.hp-before)..' HP ('..before..' -> '..u.hp..').') end
              end
            elseif name=='guard' then
              if not area or not immune_area(u) then
                if op.damage_only then u.negate_damage=true else u.guard=(u.guard or 0)+amount end
                emit(s,location(u)..' gains damage protection.')
              end
            end
            last_target=u
          end
        end
        if op.draw_if_printed_le and last_target and last_target.card.strength<=op.draw_if_printed_le then draw(s,actor,1,source) end
        if op.draw_if_destroyed and last_target and not is_deployed(s,last_target) then draw(s,actor,op.draw_if_destroyed,source) end
      elseif name=='search' then search_deck(s,actor,amount,op.target,op.shuffle or amount>=9999,op.from_bottom,source)
      elseif name=='grave_whisper' then grave_whisper(s,actor,source,op)
      elseif name=='recover' then
        local n=recover(s,actor,amount,function(c)return op_predicate(c,op.target,op)end,op.optional)
        measure(s,source,'recovered',n)
        if n==0 then measure(s,source,'empty_recoveries') end
        if n==0 and op.fallback_draw then draw(s,actor,1,source) end
      elseif name=='move' then
        local kind=op.n;local tkind=op.target
        if kind=='swap' then
          local units=all_units(s,actor);local a=pick_unit(s,actor,units,{op='move'})
          if a then U.remove(units,a);local b=pick_unit(s,actor,units,{op='move'})
            if b then local pa,ra,ia=B.position(s,a);local pb,rb,ib=B.position(s,b)
              s.players[pa].rows[ra][ia]=b;s.players[pb].rows[rb][ib]=a
              emit(s,location(a)..' swaps with '..location(b)..'.') end end
        elseif kind=='reverse' then
          local p=B.choose(s,actor,'side',{actor,other(actor)},{op='reverse'}) or actor
          local r=B.choose(s,actor,'row',{1,2},{op='reverse'}) or 1
          local row=s.players[p].rows[r]
          local movable={}
          for i,u in ipairs(row) do
            if not immune_area(u) and not immune_move(u,actor) then movable[#movable+1]=i end
          end
          for i=1,math.floor(#movable/2) do
            local a,b=movable[i],movable[#movable-i+1]
            row[a],row[b]=row[b],row[a]
          end
          emit(s,'Reverses '..s.players[p].name..' '..(r==1 and 'Front' or 'Back')..' row.')
        else
          local options=targets(s,actor,source,tkind=='any_row' and 'friend' or tkind)
          local eligible={}
          for _,v in ipairs(options) do
            local p,r=B.position(s,v)
            if not immune_move(v,actor) and (kind~='same' or #s.players[p].rows[r]>1) then eligible[#eligible+1]=v end
          end
          for i=1,op.count or 1 do
            local u=pick_unit(s,actor,eligible,{op='move',optional=op.optional and kind~='swap_adjacent'})
            if not u then break end
            U.remove(eligible,u)
            local p,r,pos=B.position(s,u)
            local dest=kind=='other' and 3-r or r
            if kind=='swap_adjacent' then
              local a=pick_unit(s,actor,adjacent(s,u),{op='move',optional=op.optional})
              if a then
                local _,_,j=B.position(s,a)
                s.players[p].rows[r][pos],s.players[p].rows[r][j]=a,u
                emit(s,location(u)..' swaps with '..location(a)..'.')
              end
            else
              local positions={}
              for j=1,#s.players[p].rows[dest]+(dest==r and 0 or 1) do
                if dest~=r or j~=pos then positions[#positions+1]=j end
              end
              local chosen=B.choose(s,actor,'position',positions,{op='move',unit=u,row=dest})
              if chosen then move_unit(s,actor,u,dest,chosen) end
            end
            last_target=u
          end
        end
      elseif name=='peek' then
        local deck=s.players[actor].deck
        local cards={};for i=1,math.min(op.n,#deck) do cards[#cards+1]=deck[#deck-i+1] end
        if #cards==1 then B.choose(s,actor,'card',cards,{op='peek',cards=cards}) end
        if #cards>=2 then
          local ordered=B.choose(s,actor,'order',{1,2},{op='peek',cards=cards}) or 1
          if ordered==2 then deck[#deck],deck[#deck-1]=deck[#deck-1],deck[#deck] end
        end
        emit(s,s.players[actor].name..' examines '..#cards..' top draw-deck cards.')
      elseif name=='beacon' then
        -- Lighthouse: look at the top card, optionally move it to the bottom.
        -- The log does not name the card, because the opponent can read the log.
        local deck=s.players[actor].deck
        if #deck==0 then emit(s,source.card.name..' finds an empty draw deck.')
        else
          local top=deck[#deck]
          local keep=B.choose(s,actor,'beacon',{1,2},{op='beacon',cards={top}}) or 1
          if keep==2 then table.remove(deck);table.insert(deck,1,top)
            emit(s,source.card.name..' sends the top card of the draw deck to the bottom.')
          else emit(s,source.card.name..' leaves the top card of the draw deck in place.') end
        end
      elseif name=='bleach' then
        local row=B.choose(s,actor,'row',{1,2},{op='row',enemy=true}) or 1
        local lost=0
        for _,u in ipairs(s.players[other(actor)].rows[row]) do
          if not immune_area(u) and (u.mod or 0)>0 then
            local before=current_strength(s,u);u.mod=0;lost=lost+1
            emit(s,location(u)..' loses its boosts (Strength '..before..' -> '..current_strength(s,u)..').')
          end
        end
        if lost==0 then emit(s,'No boosted Unit in that row; '..source.card.name..' draws instead.');draw(s,actor,1,source) end
      elseif name=='reveal' then
        local hand=s.players[other(actor)].hand;local seen={}
        local count=math.min(op.n,#hand)
        if op.optional then
          local values={}
          for n=count,0,-1 do values[#values+1]=n end
          count=B.choose(s,actor,'amount',values,{op='reveal'})
        end
        for i=1,count do
          local candidates={};for _,c in ipairs(hand) do if not seen[c] then candidates[#candidates+1]=c end end
          if #candidates>0 then local card=candidates[s.rng:random(#candidates)];seen[card]=true
            emit(s,s.players[actor].name..' reveals '..card.card.name..' from opponent hand.') end
        end
      elseif name=='bottom_from_hand' or name=='discard_from_hand' then
        local hand=s.players[actor].hand
        local c=choose_card(s,actor,'card',hand)
        if c then U.remove(hand,c)
          if name=='bottom_from_hand' then table.insert(s.players[actor].deck,1,c);emit(s,s.players[actor].name..' returns a card from hand to the bottom of the draw deck.')
          else discard_card(s,c);emit(s,'Discards '..c.card.name..'.') end
        end
      elseif name=='destroy' then
        local options={};for _,u in ipairs(all_units(s,other(actor))) do if u.hp<=op.max_health and (not op.wounded or u.hp<u.card.health) then options[#options+1]=u end end
        local t=pick_unit(s,actor,options,{op='destroy'})
        if t then measure(s,source,'executions');kill(s,t,actor,'destroy') end
      elseif name=='maelstrom' then
        local row=B.choose(s,actor,'row',{1,2},{op='maelstrom'}) or 1
        local rev={};for _,u in ipairs(s.players[other(actor)].rows[row]) do rev[#rev+1]=u end
        for _,u in ipairs(rev) do
          if u.card.strength<=3 and not immune_area(u) and not immune_move(u,actor) then
            local own=s.players[u.owner]
            local p,r,i=B.position(s,u)
            table.remove(s.players[p].rows[r],i)
            if #own.hand<s.max_hand then
              u.hp=nil;u.mod=0;u.controller=u.owner;u.activated={}
              own.hand[#own.hand+1]=u
              emit(s,location(u)..' returns to owner hand.')
            else
              emit(s,location(u)..' cannot enter a full hand and goes to its owner discard pile.')
              discard_card(s,u)
            end
          end
        end
      elseif name=='resurrect' then
        for j=1,op.count do
          local pile=s.players[actor].discard
          local c=choose_card(s,actor,'card',pile,function(v)return op_predicate(v,op.filter,op) end,true)
          if not c then break end
          U.remove(pile,c);measure(s,source,'recovered')
          enter(s,actor,c,'resurrect','resurrects into')
        end
      elseif name=='team' then
        if combo(s,actor,op.names) then
          for _,name in ipairs(op.names) do
            local named={}
            for _,u in ipairs(all_units(s,actor)) do if u.card.name==name then named[#named+1]=u end end
            buff(s,actor,pick_unit(s,actor,named,{op='buff'}),op.n,false)
          end
          if op.draw then draw(s,actor,op.draw,source) end
        end
      elseif name=='steal_hand' or name=='steal_draw' or name=='steal_discard' then
        local enemy=s.players[other(actor)]
        local pool=(name=='steal_hand' and enemy.hand) or (name=='steal_draw' and enemy.deck) or enemy.discard
        if #s.players[actor].hand<s.max_hand and #pool>0 then
          local c
          if op.random or name=='steal_draw' then c=pool[name=='steal_draw' and #pool or s.rng:random(#pool)]
          else c=choose_card(s,actor,'card',pool) end
          if c then U.remove(pool,c);c.controller=actor
            if name=='steal_discard' then measure(s,source,'recovered') end
            s.players[actor].hand[#s.players[actor].hand+1]=c
            emit(s,s.players[actor].name..' takes a card from the opposing '..(name=='steal_draw' and 'draw deck' or name=='steal_hand' and 'hand' or 'discard pile')..'.') end
        end
      elseif name=='disable' then
        local t=pick_unit(s,actor,all_units(s,other(actor)),{op='disable'})
        if t then t.disabled=true;emit(s,location(t)..' continuous abilities disabled.') end
      elseif name=='copy_deploy' then
        local opts={};for _,u in ipairs(all_units(s,actor)) do
          if u~=source and u.card.id~='Super:44' and A.get(u.card,'deploy') then opts[#opts+1]=u end end
        local target=pick_unit(s,actor,opts,{op='copy_deploy'})
        if target then emit(s,location(source)..' copies '..location(target)..' deploy ability.')
          B.resolve(s,actor,source,A.get(target.card,'deploy'),{}) end
      elseif name=='echo_effect' then
        local card=choose_card(s,actor,'card',s.players[actor].discard,function(v)return v.card.faction=='Super' and v.card.type=='Effect' end)
        if card then emit(s,'Echoes '..card.card.name..' Effect ability.')
          B.resolve(s,actor,source,A.get(card.card,'play'),{}) end
      elseif name=='extras' then play_extra(s,actor,op.n)
      elseif name=='showdown' then
        showdown(s,actor,source,op.characters,context.earned)
      elseif name=='summon' then
        if source.card.id==op.caller and B.position(s,source)==actor and has_unit(s,actor,op.partner) then
          local pl=s.players[actor]
          local found=take_named({pl.deck,pl.hand},op.id)
          if found then measure(s,source,'summon_plays');measure(s,source,'named_summons');enter(s,actor,found,'summon','charges into')
          else emit(s,location(source)..' finds no '..C.by_id[op.id].name..' in the draw deck or hand.') end
        end
      elseif name=='fetch' then
        local pl=s.players[actor];local found
        for _,c in ipairs(pl.deck) do if c.card.id==op.id then found=c;break end end
        if found and #pl.hand<s.max_hand then
          local before=#pl.deck
          measure(s,source,'searched')
          U.remove(pl.deck,found);found.controller=actor;pl.hand[#pl.hand+1]=found
          s.stats.drawn[actor]=s.stats.drawn[actor]+1
          emit(s,string.format('%s takes %s from the draw deck (draw deck %d → %d).',location(source),found.card.name,before,#pl.deck))
          if s.on_draw then s.on_draw({seat=actor,source=source.card.name,cards={found},before=before,remaining=#pl.deck,requested=1}) end
        else draw(s,actor,1,source) end
      elseif name=='mill' then
        local foe=s.players[other(actor)];local names={}
        for _=1,math.min(op.n,#foe.deck) do
          local c=table.remove(foe.deck);names[#names+1]=c.card.name;discard_card(s,c)
        end
        if #names==0 then emit(s,location(source)..' finds the opposing draw deck empty.')
        else emit(s,location(source)..' sends '..table.concat(names,', ')..' from the top of the opposing draw deck to its discard pile.') end
      elseif name=='trade' then
        local theirs=B.tradeable(s,actor,op.max_printed);U.remove(theirs,source)
        local give=#theirs>0 and pick_unit(s,actor,all_units(s,actor),{op='give'})
        local take=give and pick_unit(s,actor,theirs,{op='take'})
        if take then
          local pa,ra,ia=B.position(s,give);local pb,rb,ib=B.position(s,take)
          s.players[pa].rows[ra][ia]=take;s.players[pb].rows[rb][ib]=give
          give.controller=pb;take.controller=pa
          emit(s,location(give)..' and '..location(take)..' trade sides.')
        else emit(s,'No pair of Units to trade.') end
      elseif A.handlers[name] then A.handlers[name](s,actor,source,op,context)
      else error('Unknown ability operation: '..tostring(name)) end
    end
  end
end
local function collect_triggers(s,p,pending)
  local seen={}
  for _,entry in ipairs(pending) do seen[entry.unit]=true end
  for _,u in ipairs(all_units(s,p)) do
    if u.card.chain and not u.activated.chain and not seen[u] then
      local ch=Chains.qualify(s.players[p],u,u.card.chain,false)
      if ch then pending[#pending+1]={unit=u,chain=ch} end
    end
  end
end
local function record_chains(s)
  -- Report maximal, distinct sequences; overlapping subchains are not double-counted.
  if not s.chain_seen then s.chain_seen={} end
  for p=1,2 do
    local groups=Chains.find(s.players[p])
    for _,ch in ipairs(groups) do
      local maximal=true
      for _,larger in ipairs(groups) do
        if larger.length>ch.length then
          for start=1,larger.length-ch.length+1 do
            local contains=true
            for i=1,ch.length do
              if larger.units[start+i-1]~=ch.units[i] then contains=false;break end
            end
            if contains then maximal=false;break end
          end
          if not maximal then break end
        end
      end
      if maximal then
        local ids,names={},{}
        for _,u in ipairs(ch.units) do
          ids[#ids+1]=tostring(u.uid)
          names[#names+1]=location(u)..' ('..u.card.strength..')'
        end
        local signature=p..':'..table.concat(ids,':')
        if not s.chain_seen[signature] then
          s.chain_seen[signature]=true
          s.stats.chains_completed[p]=s.stats.chains_completed[p]+1
          s.stats.chain_completions_by_length[ch.length]=(s.stats.chain_completions_by_length[ch.length] or 0)+1
          emit(s,'Sequence completed: '..ch.length..' '..ch.direction..(ch.cross and ' Bridge' or '')..': '..table.concat(names,' -> '))
        end
      end
    end
  end
end
function B.check_chains(s,earned)
  earned=earned or {{},{}}
  record_chains(s)
  -- Re-evaluate both sides after every resolution. An opposing death can
  -- close a gap and create a new chain for the original active player.
  while true do
    local resolved=false
    for _,p in ipairs({s.active,other(s.active)}) do
      local pending=earned[p]
      collect_triggers(s,p,pending)
      if #pending>0 then
        local selected=B.choose(s,p,'chain_activation',pending,{op='chain_activation'})
        U.remove(pending,selected)
        local u,ch=selected.unit,selected.chain
        local effects=A.get(u.card,'chain')
        for _,op in ipairs(effects or {}) do
          if op.requires=='cross_chain' then
            ch=Chains.qualify(s.players[p],u,u.card.chain,true) or ch
            break
          end
        end
        measure(s,u,'chain_triggers')
        u.activated.chain=true
        s.stats.chain_activated[p]=s.stats.chain_activated[p]+1
        s.stats.chain_sizes[ch.length]=(s.stats.chain_sizes[ch.length] or 0)+1
        local names={}
        for _,member in ipairs(ch.units) do names[#names+1]=location(member) end
        emit(s,'CHAIN '..ch.length..' ('..ch.direction..(ch.cross and ', Bridge' or '')..'): '..table.concat(names,' -> '))
        emit(s,location(u)..' activates Chain '..u.card.chain..'.')
        B.resolve(s,p,u,effects,{chain=ch})
        record_chains(s)
        resolved=true
        break
      end
    end
    if not resolved then return end
  end
end
local auto_pass
local function init_player(index,name,faction,deck,s)
  local p={name=name,faction=faction,deck={},hand={},discard={},rows={{},{}},passed=false,wins=0}
  for _,id in ipairs(deck) do
    s.next_id=s.next_id+1
    p.deck[#p.deck+1]={uid=s.next_id,card=C.by_id[id],home=index,owner=index,controller=index,mod=0,activated={}}
  end
  s.rng:shuffle(p.deck)
  return p
end
function B.new(deck1,deck2,opts)
  opts=opts or {}
  local factions={opts.player_faction or C.by_id[deck1[1]].faction,opts.ai_faction or C.by_id[deck2[1]].faction}
  local opening=Rules.starting_hand
  local max_hand=math.huge
  for p,deck in ipairs({deck1,deck2}) do
    if opts.deck_size then
      assert(Decks.validate(deck,factions[p],opts.deck_size))
    else assert(Decks.validate_selection(deck,factions[p])) end
  end
  local s={rng=U.rng(opts.seed or os.time()),next_id=0,players={},log={},round=1,max_hand=max_hand,on_draw=opts.on_draw,
    round_history={},active=1,turns=0,plays_left=1,finished=false,winner=nil,
    chooser=opts.chooser,on_event=opts.on_event,school_used={[1]=false,[2]=false},
    activation_count=0,observe=opts.observe,
    stats={played={0,0},drawn={0,0},discarded={0,0},chain_activated={0,0},chain_sizes={},
      chains_completed={0,0},chain_completions_by_length={},abilities={}}}
  local names=opts.names or {'Player','Opponent'}
  s.players[1]=init_player(1,names[1],opts.player_faction or C.by_id[deck1[1]].faction,deck1,s)
  s.players[2]=init_player(2,names[2],opts.ai_faction or C.by_id[deck2[1]].faction,deck2,s)
  draw(s,1,opening);draw(s,2,opening)
  s.active=s.rng:random(2);s.first_round_starter=s.active;s.current_round_starter=s.active
  emit(s,'Round 1 begins. '..s.players[s.active].name..' acts first.')
  auto_pass(s)
  return s
end
-- First letter: hand deployment row. Remaining letters: ordinary attack targets.
function B.placement_row(card)
  if card.type=='Unit' then return card.designation:sub(1,1)=='F' and 1 or 2 end
end
-- Friendly Units that a replacing Unit (card.replaces) can be played onto.
function B.hosts(s,p,card)
  local out={}
  for _,u in ipairs(s.players[p].rows[B.placement_row(card)]) do if u.card.id==card.replaces then out[#out+1]=u end end
  return out
end
-- Opposing Units that player p may take with a trade ability (printed Strength cap).
function B.tradeable(s,p,max_printed)
  local out={}
  for _,u in ipairs(all_units(s,other(p))) do
    if u.card.strength<=(max_printed or math.huge) and not immune_move(u,p) then out[#out+1]=u end
  end
  return out
end
-- The battlefield a Unit card is deployed on when player p plays it.
function B.deploy_side(p,card) return card.agent and other(p) or p end
function B.can_school(s,p)
  if s.finished or s.active~=p or s.players[p].passed or s.plays_left<=0 or s.school_used[p] or #s.players[p].hand<3 or #all_units(s,p)==0 then return false end
  for _,c in ipairs(s.players[p].hand) do if c.card.id~='Water:31' then return false end end
  return true
end
local function eligible_card(s,p,index)
  local card=s.players[p].hand[index];if not card then return false,'Invalid hand index' end
  for _,id in ipairs(card.card.requires_units or {}) do
    if not has_unit(s,p,id) then return false,'Requires '..C.by_id[id].name..' on your battlefield' end
  end
  local ability=(A.get(card.card,'play') or {})[1]
  if ability and ability.requires_team and not combo(s,p,ability.names) then return false,'Required team missing' end
  if card.card.id=='Water:60' and #Chains.find(s.players[p])==0 then return false,'Requires an existing chain' end
  if card.card.replaces and #B.hosts(s,p,card.card)==0 then
    return false,'Requires a '..C.by_id[card.card.replaces].name..' in your '..(B.placement_row(card.card)==1 and 'Front' or 'Back')..' row'
  end
  if card.card.id=='Water:70' then
    local valid=false;for _,ch in ipairs(Chains.find(s.players[p])) do if ch.length>=5 then valid=true end end
    if not valid then return false,'Requires a Chain 5' end
  end
  if card.card.type=='Effect' then
    local op=(A.get(card.card,'play') or {})[1]
    local target=op and op.target
    if target=='friend' or target=='enemy' or target=='two_friends' then
      local candidates=targets(s,p,nil,target)
      local count=0
      for _,u in ipairs(candidates) do
        local side,r=B.position(s,u)
        if (not op.min_printed or u.card.strength>=op.min_printed) and (op.op~='heal' or u.hp<u.card.health)
          and (op.op~='move' or not immune_move(u,p) and (op.n~='same' or #s.players[side].rows[r]>1)) then count=count+1 end
      end
      if not op.optional and count<(target=='two_friends' and 2 or 1) then return false,'Needs an eligible '..(target=='enemy' and 'opposing' or 'friendly')..' Unit target' end
    elseif op and op.op=='recover' and op.n==1 then
      local found=false
      for _,u in ipairs(s.players[p].discard) do if op_predicate(u,op.target,op) then found=true end end
      if not found then return false,'Needs an eligible card in your discard pile' end
    elseif op and op.op=='bottom_from_hand' and #s.players[p].hand<2 then
      return false,'Needs another card in hand'
    elseif op and op.op=='steal_hand' and #s.players[other(p)].hand==0 then
      return false,'The opposing hand is empty'
    end
  end
  return true
end
function B.playable(s,p,index)
  if s.finished or s.active~=p or s.players[p].passed or s.plays_left<=0 then return false,'Not your turn' end
  return eligible_card(s,p,index)
end
local function can_reinforce(s,p)
  if #s.players[p].deck>0 then return true end
  for i=1,#s.players[p].hand do if eligible_card(s,p,i) then return true end end
  return false
end
function B.attack_targets(s,p,attacker)
  local targets={}
  local allowed=attacker.card.designation:sub(2)
  for r,row in ipairs(s.players[other(p)].rows) do
    if allowed:find(r==1 and 'F' or 'B',1,true) then
      for _,u in ipairs(row) do
        if u~=attacker then targets[#targets+1]=u end
      end
    end
  end
  return targets
end
function B.attack_power(s,u,target)
  local power=current_strength(s,u)
  if u.disabled then return power end
  local trait=u.card.strike
  if trait=='hunter' and target.hp<target.card.health
    or trait=='duelist' and current_strength(s,target)>current_strength(s,u)
    or trait=='formation' and #adjacent(s,u)>0 then power=power+1 end
  return power
end
local function redeal(s)
  local packs={{},{}}
  for _,pl in ipairs(s.players) do
    for _,zone in ipairs({pl.deck,pl.hand,pl.discard,pl.rows[1],pl.rows[2]}) do
      for _,u in ipairs(zone) do
        local home=u.home or u.owner
        u.owner=home;u.controller=home;u.hp=nil;u.mod=0;u.guard=0
        u.disabled=false;u.negate_damage=false;u.activated={};u.shell_used=false;u.fed=false
        packs[home][#packs[home]+1]=u
      end
    end
  end
  for p,pl in ipairs(s.players) do
    pl.deck=packs[p];pl.hand={};pl.discard={};pl.rows={{},{}}
    s.rng:shuffle(pl.deck);draw(s,p,Rules.starting_hand)
  end
end
local function finish_round(s)
  local first,second=B.score(s,1),B.score(s,2)
  local winner=first==second and 0 or first>second and 1 or 2
  local reason='remaining Health'
  if winner>0 then s.players[winner].wins=s.players[winner].wins+1 end
  s.round_history[#s.round_history+1]={round=s.round,scores={first,second},winner=winner,reason=reason}
  emit(s,string.format('Round %d ends: %s %d, %s %d. %s',s.round,s.players[1].name,first,s.players[2].name,second,winner==0 and 'Tie.' or s.players[winner].name..' wins by '..reason..'.'))
  for _,pl in ipairs(s.players) do
    pl.passed=false;pl.bonus_next=nil
  end
  s.chain_seen={};s.last_played=nil;s.last_attack=nil
  if s.round==3 or s.players[1].wins==2 or s.players[2].wins==2 then
    s.finished=true
    s.winner=s.players[1].wins==2 and 1 or s.players[2].wins==2 and 2 or 0
    emit(s,'Match finished: '..(s.winner==0 and 'draw' or s.players[s.winner].name..' wins')..'.')
    return
  end
  local prior_starter=s.current_round_starter
  s.round=s.round+1;s.active=other(prior_starter)
  s.current_round_starter=s.active
  s.plays_left=1
  redeal(s)
  emit(s,'Round '..s.round..' begins. '..s.players[s.active].name..' goes first.')
end
local function next_turn(s)
  s.extra_turn=false
  if s.players[1].passed and s.players[2].passed then
    finish_round(s)
    if not s.finished then return auto_pass(s) end
    return
  elseif not s.players[other(s.active)].passed then
    s.active=other(s.active)
  end
  s.plays_left=1;s.turns=s.turns+1
  local p=s.active
  local bonus=s.players[p].bonus_next or 0
  s.players[p].bonus_next=nil;s.plays_left=1+bonus
  emit(s,s.players[p].name..' takes the turn.')
  if #s.players[p].deck>0 then draw(s,p,1,nil,true) end
  s.activation_count=0
  for _,u in ipairs(all_units(s,p)) do B.resolve(s,p,u,A.get(u.card,'turn'),{}) end
  B.check_chains(s)
  return auto_pass(s)
end
auto_pass=function(s)
  local p=s.active
  if #B.legal_indices(s,p)>0 or B.can_school(s,p) then return end
  local pl=s.players[p]
  local opponent=other(p)
  local exhausted=#pl.deck==0
  if exhausted and (s.players[opponent].passed or not can_reinforce(s,opponent)) then
    finish_round(s)
    if not s.finished then return auto_pass(s) end
  else
    emit(s,pl.name..' has no legal play and waits for reinforcements.')
    return next_turn(s)
  end
end
local function deployment_attack(s,p,attacker)
  local eligible=B.attack_targets(s,p,attacker)
  if #eligible==0 then
    emit(s,location(attacker)..' has no eligible ordinary attack target.')
    return
  end
  local target=pick_unit(s,p,eligible,{op='deploy_attack',unit=attacker})
  local power=B.attack_power(s,attacker,target)
  emit(s,location(attacker)..' attacks '..location(target)..' for '..power..'.')
  measure(s,attacker,'attacks');measure(s,attacker,'modified_attacks',current_strength(s,attacker)~=attacker.card.strength and 1 or 0)
  damage(s,p,target,power,{source=attacker,kind='attack_damage'})
  local result=target.hp and target.hp..'/'..target.card.health..' HP' or 'defeated'
  s.last_attack=location(attacker)..' attacked '..location(target)..' ('..result..').'
end
local function strike_and_deploy(s,actor,unit,row)
  deployment_attack(s,actor,unit)
  B.resolve(s,actor,unit,A.get(unit.card,'deploy'),{entry_row=row})
end

showdown=function(s,actor,source,characters,earned)
  local pl,foe=s.players[actor],s.players[other(actor)]
  local arrived,placements={},{}
  -- Finish moving all physical copies before any attack or player choice.
  for _,id in ipairs(characters) do
    local piles={pl.deck,pl.hand}
    if C.by_id[id].repel then
      piles={pl.deck,pl.hand,pl.discard,foe.discard,foe.hand,foe.deck}
    end
    local unit,origin=take_named(piles,id)
    if unit then
      if origin==pl.discard or origin==foe.discard then measure(s,source,'recovered') end
      local row=B.placement_row(unit.card)
      prepare_unit(s,unit,actor)
      table.insert(pl.rows[row],unit)
      arrived[#arrived+1]=unit
      placements[#placements+1]=location(unit)..' ('..(row==1 and 'Front' or 'Back')..')'
    end
  end
  if #arrived==0 then emit(s,source.card.name..' finds no available characters.');return end
  emit(s,source.card.name..' summons '..table.concat(placements,', ')..'.')
  measure(s,source,'named_summons',#arrived);measure(s,source,'summon_plays')
  for _,unit in ipairs(arrived) do
    if B.position(s,unit)==actor then
      strike_and_deploy(s,actor,unit,B.placement_row(unit.card))
      -- A defeat can close a gap and earn a chain before the next strike.
      if earned then
        for seat=1,2 do collect_triggers(s,seat,earned[seat]) end
      end
    end
  end
end

function B.play(s,p,index,row,pos)
  local ok,why=B.playable(s,p,index);if not ok then return false,why end
  local hand=s.players[p].hand;local card=hand[index]
  local side=B.deploy_side(p,card.card);local host
  local earned={{},{}}
  if card.card.replaces then
    host=B.choose(s,p,'unit',B.hosts(s,p,card.card),{op='replace'})
    if not host then return false,'Choose the Unit to replace' end
  elseif card.card.type=='Unit' then
    if row~=B.placement_row(card.card) then
      return false,'Deploy this Unit in '..(B.placement_row(card.card)==1 and 'Front' or 'Back')
    end
    local units=s.players[side].rows[row]
    if not pos or pos%1~=0 or pos<1 or pos>#units+1 then return false,'Invalid insertion position' end
  end
  measure(s,card,'plays')
  s.last_played=card;s.last_attack=nil
  table.remove(hand,index);s.plays_left=s.plays_left-1;s.activation_count=0
  s.stats.played[p]=s.stats.played[p]+1
  if card.card.type=='Unit' then
    prepare_unit(s,card,side)
    if host then
      measure(s,card,'replacements')
      -- The host leaves play without being destroyed, so no Last Breath or kill trigger applies.
      local _,r,i=B.position(s,host)
      row,pos=r,i
      table.remove(s.players[p].rows[r],i);discard_card(s,host)
      table.insert(s.players[p].rows[r],i,card)
      emit(s,string.format('%s plays %s onto %s in %s position %d. %s goes to the discard pile.',s.players[p].name,
        location(card),location(host),r==1 and 'Front' or 'Back',i,host.card.name))
    else
      table.insert(s.players[side].rows[row],pos,card)
      emit(s,string.format('%s plays %s into %s%s position %d.',s.players[p].name,location(card),
        side~=p and s.players[side].name..' ' or '',row==1 and 'Front' or 'Back',pos))
    end
    collect_triggers(s,side,earned[side])
    strike_and_deploy(s,p,card,row)
  else
    emit(s,s.players[p].name..' plays '..card.card.name..' (Effect).')
    B.resolve(s,p,card,A.get(card.card,'play'),{earned=earned})
    discard_card(s,card)
  end
  B.check_chains(s,earned)
  if s.plays_left<=0 or #B.legal_indices(s,p)==0 then next_turn(s) else s.extra_turn=true end
  return true
end
function B.school(s,p)
  if s.active~=p or not B.can_school(s,p) then return false,'School of Goldfish not available' end
  s.last_attack=nil;s.school_used[p]=true;s.plays_left=s.plays_left-1;s.activation_count=0
  local hand=s.players[p].hand
  local cards={};for _,c in ipairs(hand) do cards[#cards+1]=c end
  s.players[p].hand={}
  for _,c in ipairs(cards) do
    s.stats.played[p]=s.stats.played[p]+1
    B.resolve(s,p,c,A.get(c.card,'play'),{})
    discard_card(s,c)
  end
  local pl=s.players[p]
  for _,c in ipairs(pl.discard) do pl.deck[#pl.deck+1]=c end
  pl.discard={};s.rng:shuffle(pl.deck)
  emit(s,'School of Goldfish activates with '..#cards..' Goldfish; discard shuffled into draw deck.')
  draw(s,p,10,cards[1]);play_extra(s,p,1)
  if #B.legal_indices(s,p)==0 then next_turn(s) else s.extra_turn=true end
  return true
end
function B.end_extra(s,p)
  if s.finished or s.active~=p or not s.extra_turn then return false,'No additional play to decline' end
  emit(s,s.players[p].name..' ends the extra plays.')
  next_turn(s)
  return true
end
function B.pass(s,p)
  if s.active~=p or s.finished or s.players[p].passed then return false,'Cannot pass' end
  s.players[p].passed=true;s.plays_left=0
  emit(s,s.players[p].name..' passes the round.')
  next_turn(s)
  return true
end
function B.legal_indices(s,p)
  local choices={}
  for i=1,#s.players[p].hand do local ok=B.playable(s,p,i);if ok then choices[#choices+1]=i end end
  return choices
end
function B.report(s)
  return {winner=s.winner,rounds=s.round_history,wins={s.players[1].wins,s.players[2].wins},
    played=s.stats.played,hand_remaining={#s.players[1].hand,#s.players[2].hand},
    drawn=s.stats.drawn,discarded=s.stats.discarded,chains=s.stats.chain_activated,
    chain_sizes=s.stats.chain_sizes,chains_completed=s.stats.chains_completed,
    chain_completions_by_length=s.stats.chain_completions_by_length,abilities=s.stats.abilities}
end
return B
