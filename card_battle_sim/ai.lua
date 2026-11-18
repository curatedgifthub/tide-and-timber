-- Heuristic opponent with the same play/pass actions and information limits as players.
local C=require('data.cards')
local Chains=require('chains')
local A=require('abilities')
local B=require('battle')
local AI={}
local function chain_value(row,index,card)
  if not Chains.eligible(card) then return 0 end
  local temp={}
  for i,v in ipairs(row) do temp[i]=Chains.eligible(v.card) and v.card.strength or math.huge end
  table.insert(temp,index,card.strength)
  local points=0
  for dir=-1,1,2 do
    local len=1;local j=index-1
    while j>=1 and temp[j+1]-temp[j]==dir do len=len+1;j=j-1 end
    j=index+1
    while j<=#temp and temp[j]-temp[j-1]==dir do len=len+1;j=j+1 end
    if len>=3 then points=math.max(points,3+len*1.3)
    elseif len==2 then points=math.max(points,1.6) end
  end
  return points
end
local function controls(s,p,id)
  for _,u in ipairs(B.units(s,p)) do if u.card.id==id then return true end end
  return false
end
local function holds(pile,id)
  for _,c in ipairs(pile) do if c.card.id==id then return true end end
  return false
end
local function evaluate(s,p,index,row,pos)
  local card=s.players[p].hand[index].card
  local me=B.score(s,p);local foe=B.score(s,3-p)
  local n=(card.type=='Unit') and card.strength or 0
  local val=n*1.1
  local mine,theirs=s.players[p],s.players[3-p]
  if card.agent then
    -- A Double Agent hands its Strength, and any chain it completes, to the opponent.
    val=-n*1.1-chain_value(theirs.rows[row],pos,card)
    if card.id=='Super:76' then
      local give,take
      for _,u in ipairs(B.units(s,p)) do local v=B.strength(s,u);if not give or v<give then give=v end end
      for _,u in ipairs(B.tradeable(s,p,5)) do local v=B.strength(s,u);if not take or v>take then take=v end end
      if give and take then val=val+2.2*(take-give) end
    elseif card.id=='Super:77' then val=val+(#theirs.deck>0 and 1.5 or 0)
    elseif card.id=='Super:78' then val=val+(#theirs.discard>0 and 4.5 or 0) end
  elseif card.replaces then
    local host=B.hosts(s,p,card)[1]
    val=(n-(host and host.card.strength or 0))*1.1+2*#B.units(s,3-p)+3
  elseif card.type=='Unit' then
    if card.id=='Super:61' and holds(mine.hand,'Super:66') then val=val+3 end
    if card.id=='Super:71' or card.id=='Super:72' then
      local partner=card.id=='Super:71' and 'Super:72' or 'Super:71'
      if controls(s,p,partner) and (holds(mine.deck,'Super:73') or holds(mine.hand,'Super:73')) then val=val+7
      elseif holds(mine.hand,partner) then val=val+1 end
    end
    if card.id=='Super:74' then val=val+(controls(s,p,'Super:75') and 5 or 1) end
    if card.id=='Super:75' then val=val+1.5 end
    val=val+chain_value(s.players[p].rows[row],pos,card)
    if card.chain then val=val+card.chain*0.1 end
    if row==2 and (card.id=='Fantasy:4' or card.id=='Water:30') then val=val+2 end
    if card.bridge then
      val=val+1.5
      if row==1 and pos==#s.players[p].rows[1]+1 or row==2 and pos==#s.players[p].rows[2]+1 then
        local front=s.players[p].rows[1];local back=s.players[p].rows[2]
        local f=row==1 and card.strength or (#front>0 and front[#front].card.strength)
        local b=row==2 and card.strength or (#back>0 and back[#back].card.strength)
        if f and b and math.abs(f-b)==1 then val=val+4 end
      end
    end
  else
    local id=card.id
    if id=='Super:39' or id=='Fantasy:40' or id=='Water:37' then val=6 end
    if id=='Water:31' or id=='Super:33' or id=='Fantasy:32' then val=2+#B.units(s,p) end
    if id=='Super:38' or id=='Water:56' or id=='Fantasy:31' then val=2+#B.units(s,3-p) end
    if id=='Super:57' then
      for _,character in ipairs(A.get(card,'play')[1].characters) do
        local unit=C.by_id[character]
        if holds(mine.deck,character) or holds(mine.hand,character) or unit.repel and holds(mine.discard,character) then
          val=val+unit.strength*1.1
        end
      end
    elseif #B.units(s,p)==0 and #B.units(s,3-p)==0 then val=val-5 end
  end
  if s.combat and card.type=='Unit' and not card.agent then
    local health=B.deployment_health(s,p,card)
    val=val-(card.health-health)*0.65
    if card.strength<=3 and #B.units(s,p)==0 then
      for _,ally in ipairs(mine.hand) do
        if ally.card.strength and ally.card.strength>=5 then val=val+2.5;break end
      end
    end
    if row==1 and card.health>=5 and #mine.rows[1]==0 then val=val+1.8 end
    if row==2 and #mine.rows[1]>0 and card.health<=4 then val=val+1.8 end
  end
  if s.round==1 then val=val-(foe-me>8 and 1.0 or 0) end
  return val
end
function AI.decision(s,p,difficulty)
  if B.can_school(s,p) then return {type='school'} end
  local legal=B.legal_indices(s,p)
  if not s.combat and #legal==0 then return {type='pass'} end
  local me=B.score(s,p);local opponent=B.score(s,3-p)
  local theirs=s.players[3-p];local mine=s.players[p]
  if s.combat then
    if theirs.passed and B.round_result(s)==p then return {type='pass'} end
  else
    if theirs.passed and (me>opponent or me==opponent and #mine.hand<=2) then return {type='pass'} end
    -- Budget the opening hand across the remaining rounds. Hand counts are public.
    local can_concede=s.round<3 and theirs.wins==0
    if can_concede and not theirs.passed and #mine.hand<=5 and
        (me>=opponent+3 or (me<opponent and #mine.hand<=#theirs.hand)) then
      return {type='pass'}
    end
    if #mine.hand<=2 and me>opponent+5 and s.round<3 then return {type='pass'} end
    if s.round==1 and not theirs.passed and me+8<opponent and #mine.hand<=4 then return {type='pass'} end
  end
  local moves={}
  for _,index in ipairs(legal) do
    local card=mine.hand[index].card
    if card.type=='Unit' and not card.replaces then
      local rows=s.players[B.deploy_side(p,card)].rows
      for row=1,2 do
        for pos=1,#rows[row]+1 do
          moves[#moves+1]={type='play',index=index,row=row,pos=pos,value=evaluate(s,p,index,row,pos)}
        end
      end
    else moves[#moves+1]={type='play',index=index,value=evaluate(s,p,index,1,1)} end
  end
  if s.combat then
    for _,u in ipairs(B.units(s,p)) do if B.ready(s,p,u) then
      for _,target in ipairs(B.attack_targets(s,p)) do
        local damage=math.max(0,B.attack_power(s,u,target)-(target.guard or 0))
        if target.negate_damage then damage=0 end
        local lethal=damage>=target.hp
        local value=3+math.min(damage,target.hp)+(lethal and 10 or 0)
        if not lethal and #theirs.rows[1]>0 then value=value-math.floor(B.strength(s,target)/2)*0.75 end
        if not target.spent then value=value+math.min(6,B.strength(s,target))*.3 end
        moves[#moves+1]={type='attack',attacker=u.uid,target=target.uid,value=value}
      end
    end end
  end
  if #moves==0 then return {type='pass'} end
  local best=moves[1]
  for _,move in ipairs(moves) do
    if move.value>best.value then best=move end
  end
  if difficulty=='easy' and (not s.combat or s.rng:random(3)~=1) then
    local random=moves[s.rng:random(#moves)]
    -- Count legal attacks independently of the number of deployment slots.
    if s.combat and s.rng:random(2)==1 then
      local attacks={}
      for _,move in ipairs(moves) do if move.type=='attack' then attacks[#attacks+1]=move end end
      if #attacks>0 then random=attacks[s.rng:random(#attacks)] end
    end
    best=random
  end
  -- Pass when the likely value of playing a card would not justify spending it.
  if not s.combat and theirs.passed and me==opponent and #mine.hand>1 and s.round<3 and best.value<3 then return {type='pass'} end
  return best
end
function AI.step(s,p,difficulty)
  if s.active~=p or s.finished then return false,'Not active' end
  local move=AI.decision(s,p,difficulty)
  if move.type=='attack' then return B.attack(s,p,move.attacker,move.target) end
  if move.type=='pass' then return B.pass(s,p) end
  if move.type=='school' then return B.school(s,p) end
  return B.play(s,p,move.index,move.row,move.pos)
end
return AI
