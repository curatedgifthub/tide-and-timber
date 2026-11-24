-- From the source root: lua tests/tabletop.lua
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local L=require('tabletop.library')
local M=require('tabletop.match')
local B=require('battle')
local A=require('abilities')
local Chains=require('chains')
local U=require('util')
local cases={}
local function test(label,fn) cases[#cases+1]={label,fn} end
local function cfg()
  -- Both seats computer-controlled, for matches run through tabletop.match.
  local c=L.new();c.controllers={"AI","AI"}
  L.starter(c,1,20);L.starter(c,2,20);return c
end
-- Every selected copy exists exactly once. Ownership is fixed, except that a Double Agent
-- (card.agent) becomes the property of the player it is deployed against.
local function integrity(m,c)
  local seen,counts,agents={},{{},{}},{}
  for p,pl in ipairs(m.state.players) do
    assert(#pl.hand<=#c.decks[1]+#c.decks[2])
    for _,zone in ipairs({pl.rows[1],pl.rows[2],pl.hand,pl.deck,pl.discard}) do
      for _,u in ipairs(zone) do
        assert(not seen[u.uid],"duplicate instance");seen[u.uid]=true
        local t=u.card.agent and agents or counts[u.owner];t[u.card.id]=(t[u.card.id] or 0)+1
        if zone==pl.discard then assert(u.owner==p and not u.hp) end
        if zone==pl.rows[1] or zone==pl.rows[2] then assert(u.controller==p and u.hp,"Unit controller must match its battlefield") end
      end
    end
  end
  for p=1,2 do for _,id in ipairs(c.decks[p]) do
    local t=L.cards.by_id[id].agent and agents or counts[p]
    t[id]=assert(t[id],"outside selection")-1
  end end
  for _,t in ipairs({counts[1],counts[2],agents}) do for _,n in pairs(t) do assert(n==0) end end
end
local function unit(s,p,id,row)
  local c=L.cards.by_id[id];s.next_id=s.next_id+1
  local u={card=c,uid=s.next_id,owner=p,controller=p,hp=c.health,mod=0,guard=0,activated={}}
  if row then table.insert(s.players[p].rows[row],u) end
  return u
end
test("The card pool is exactly the cards with their own artwork",function()
  local C=L.cards;local total=0
  assert(#L.factions==3 and L.factions[1]=="Fantasy" and L.factions[2]=="Water" and L.factions[3]=="Super")
  for _,f in ipairs({"Fantasy","Water","Super"}) do
    local inPool={}
    for _,card in ipairs(L.collection(f)) do inPool[card.id]=true end
    for _,card in ipairs(C[f]) do
      local art=L.art[card.id]
      assert((art~=nil)==(inPool[card.id]==true),card.id.." pool membership must match artwork")
      assert((art~=nil)==(L.owned[f][card.id]~=nil),card.id.." draftability must match artwork")
      if art then
        local file=assert(io.open(art,"rb"),card.id.." thumbnail missing: "..art);file:close()
        assert(art=="tabletop/assets/"..f:lower().."/"..card.number..".png");total=total+1
      end
    end
  end
  for id in pairs(L.art) do assert(C.by_id[id],"artwork for unknown card "..id) end
  assert(L.size("Fantasy")==61 and L.size("Water")==74 and L.size("Super")==31 and total==166)
  local c=L.new()
  for _,id in ipairs({'Fantasy:34','Fantasy:59','Fantasy:61','Fantasy:67'}) do
    assert(not L.edit(c,1,id,1),id.." has no artwork but was accepted")
  end
end)
test("Explicit editable collections, copy limits and 20–30 tagged cards",function()
  local c=L.new();assert(not L.valid(c,1))
  assert(not L.edit(c,1,'Fantasy:71',1));assert(not L.edit(c,1,'Water:1',1))
  for _=1,3 do assert(L.edit(c,1,'Fantasy:1',1)) end
  assert(not L.edit(c,1,'Fantasy:1',1));assert(L.edit(c,1,'Fantasy:1',-1))
  for _=1,8 do assert(L.edit(c,2,'Water:31',1)) end
  assert(not L.edit(c,2,'Water:31',1))
  for _,f in ipairs(L.factions) do
    c.factions[1]=f
    L.starter(c,1,20);assert(#c.decks[1]==20 and L.valid(c,1))
    local pool=L.collection(f)
    local i=#pool
    for n=21,30 do
      while U.contains(c.decks[1],pool[i].id) do i=i-1 end
      assert(L.edit(c,1,pool[i].id,1))
      assert(#c.decks[1]==n and L.valid(c,1))
    end
    assert(not L.edit(c,1,pool[1].id,1) and #c.decks[1]==30)
    L.starter(c,1,30);assert(#c.decks[1]==30 and L.valid(c,1))
    L.random(c,1);assert(#c.decks[1]==20 and L.valid(c,1))
    table.remove(c.decks[1]);assert(not L.valid(c,1))
  end
end)
test("Preset round trip, draft isolation and invalid input rejection",function()
  local c=cfg();c.mode=2
  local raw=L.encode(c);local other=assert(L.decode(raw));assert(L.encode(other)==raw and other.mode==2)
  assert(other.controllers[1]=="Human" and other.controllers[2]=="Human" and other.seed==nil)
  assert(L.valid(other,1));assert(L.valid(other,2));other.decks[1][1]="";assert(c.decks[1][1]~="")
  assert(not L.decode(raw:gsub('Fantasy:48','Water:48')))
  assert(not L.decode(raw:gsub('TT2','new format')))
  assert(not L.decode(raw:gsub('\nrandom\n','\n-9\n')))
  -- A preset from before online play (local format 4, fixed seed) loads as single player.
  local legacy=assert(L.decode((raw:gsub('^TT2\n2\nrandom\nHuman\nHuman\n','TT2\n4\n1194\nAI\nAI\n'))))
  assert(legacy.mode==1 and legacy.seed==nil and legacy.controllers[2]=="AI" and #legacy.decks[2]==20)
  assert(not L.decode((raw:gsub('^TT2\n2\n','TT2\n9\n'))))
  -- A preset saved before the art-only pool keeps its other cards and reports the removed ones.
  local old=assert(L.decode(raw:gsub('Fantasy:1,','Fantasy:61,Fantasy:1,',1)))
  assert(#old.removed==1 and old.removed[1]=='Fantasy:61' and #old.decks[1]==#other.decks[1])
  assert(not L.decode(raw:gsub('Fantasy\n','Super\n',1)),"a deck cannot be loaded under another faction")
end)
test("Separate shuffled instances, deterministic hands and selected-copy conservation",function()
  local c=cfg();local saved=L.encode(c);local m=M.new(c,702);local n=M.new(c,702);local different=M.new(c,703)
  for p=1,2 do
    local a,b=m.state.players[p],n.state.players[p];assert(#a.hand==5 and #a.deck==15)
    local diff=false
    for i=1,5 do
      assert(a.hand[i]~=b.hand[i] and a.hand[i].uid==b.hand[i].uid)
      diff=diff or a.hand[i].uid~=different.state.players[p].hand[i].uid
    end
    assert(diff)
  end
  integrity(m,c);B.draw(m.state,1,80);assert(#m.state.players[1].hand==20 and #m.state.players[1].deck==0)
  assert(saved==L.encode(c));integrity(m,c)
end)
test("Older over-limit drafts remain editable and short decks cannot start",function()
  local c=cfg()
  L.starter(c,1,30);c.decks[1][31]='Fantasy:1';assert(not L.valid(c,1))
  local over=assert(L.decode(L.encode(c)));assert(#over.decks[1]==31 and not L.valid(over,1))
  assert(L.edit(over,1,'Fantasy:1',-1) and L.valid(over,1))
  c=cfg();table.remove(c.decks[1]);assert(not L.valid(c,1))
  assert(not pcall(M.new,c,1));local old=L.encode(c):gsub("TT2","TT1\n30")
  local loaded=assert(L.decode(old));assert(#loaded.decks[1]==19 and not L.valid(loaded,1))
end)
test("Halfling Courier automatically draws the exact top copy in Back only",function()
  for row=1,2 do
    local c=cfg();local m
    -- Find a real dealt hand containing Courier with Fantasy acting first.
    for seed=1,100 do
      local candidate=M.new(c,seed)
      if candidate.state.active==1 then
        for _,u in ipairs(candidate.state.players[1].hand) do
          if u.card.id=='Fantasy:4' then m=candidate;break end
        end
      end
      if m then break end
    end
    local pl=assert(m).state.players[1];local before=#pl.deck;local top=pl.deck[before]
    local index;for i,u in ipairs(pl.hand) do if u.card.id=='Fantasy:4' then index=i end end
    if row==1 then
      assert(not m:act({type='play',index=index,row=row,pos=1}))
      assert(#pl.hand==5 and #pl.deck==before)
    else
      assert(m:act({type='play',index=index,row=row,pos=1}))
      assert(#pl.hand==5 and #pl.deck==before-1)
      local receipt=assert(m.draws[1])
      assert(receipt.seat==1 and receipt.source=='Halfling Courier' and receipt.before==before)
      assert(pl.hand[#pl.hand]==top and receipt.cards[1]==top)
    end
    integrity(m,c)
  end
end)
test("Printed-rank Bridge after insertion, once per deployment, printed effect only",function()
  local s=M.new(cfg(),77).state;s.active=2
  unit(s,2,'Water:2',1);local bridge=unit(s,2,'Water:21')
  local rank3=unit(s,2,'Water:28',2);rank3.mod=3
  s.players[2].hand={bridge,unit(s,2,'Water:1')}
  assert(not B.play(s,2,1,1,4));assert(#s.players[2].hand==2)
  assert(B.play(s,2,1,1,2));assert(Chains.qualify(s.players[2],bridge,3,true))
  assert(B.score(s,2)==s.players[2].rows[1][1].hp+bridge.hp+rank3.hp and B.attack_power(s,bridge,rank3)==bridge.card.strength and s.stats.chain_activated[2]==1)
  B.check_chains(s);assert(s.stats.chain_activated[2]==1)
end)
test("Nested search choices allow explicit bottom order and find only deck cards",function()
  local m=M.new(cfg(),12);m.controllers[1]="Human";local s=m.state;s.active=1
  local pl=s.players[1]
  pl.deck={unit(s,1,'Fantasy:1'),unit(s,1,'Fantasy:40'),unit(s,1,'Fantasy:6'),unit(s,1,'Fantasy:32')}
  pl.hand={unit(s,1,'Fantasy:5'),unit(s,1,'Fantasy:1')}
  assert(m:act({type="play",index=1,row=2,pos=1}));assert(m.prompt.context.op=='search')
  assert(#m.prompt.options==2 and #m.prompt.context.cards==3)
  assert(m:choose(2));assert(m.prompt.kind=="bottom_order")
  assert(m:choose(2));assert(not m.prompt);assert(pl.hand[2].card.id=='Fantasy:40')
  assert(pl.deck[1].card.id=='Fantasy:32' and pl.deck[2].card.id=='Fantasy:6')
end)
test("Theft, discard ownership, required targets and optional extra plays",function()
  local m=M.new(cfg(),42);local s=m.state;s.active=1
  local hunter=unit(s,1,'Super:55');local fish=unit(s,2,'Water:43');s.players[2].deck={fish}
  B.resolve(s,1,hunter,A.get(hunter.card,'deploy'));assert(fish.owner==2 and fish.controller==1)
  assert(B.play(s,1,#s.players[1].hand,1,1))
  B.damage(s,2,fish,99);assert(s.players[2].discard[#s.players[2].discard]==fish)
  s.active=1;s.players[1].hand={unit(s,1,'Fantasy:31'),unit(s,1,'Super:70'),unit(s,1,'Fantasy:1')}
  assert(not B.playable(s,1,1));assert(B.play(s,1,2));assert(s.active==1 and s.plays_left==2)
  assert(B.end_extra(s,1));assert(s.active==2 and not s.players[1].passed)
end)
test("Chosen team copies, rooted Treant, and selectable Chain 5 buffs",function()
  local s=M.new(cfg(),13).state
  local a=unit(s,1,'Super:1',1);local b=unit(s,1,'Super:1',1)
  unit(s,1,'Super:13',1);unit(s,1,'Super:30',1)
  s.chooser=function(_,_,_,options) return #options end
  local team=unit(s,1,'Super:58');B.resolve(s,1,team,A.get(team.card,'play'))
  assert(a.mod==0 and b.mod==2)
  local tree=unit(s,2,'Fantasy:48',1);local move=unit(s,1,'Water:47')
  B.resolve(s,1,move,A.get(move.card,'deploy'));local _,row=B.position(s,tree);assert(row==1)
  s.players[1].rows={{},{}}
  for r=1,2 do for _,id in ipairs({1,5,8,13,26}) do unit(s,1,'Water:'..id,r) end end
  local deep=unit(s,1,'Water:70');B.resolve(s,1,deep,A.get(deep.card,'play'))
  for r=1,2 do for _,u in ipairs(s.players[1].rows[r]) do assert(u.mod==(r==2 and 2 or 0)) end end
end)
test("Auto-passing without targets and tied empty rounds terminate at three rounds",function()
  -- Fantasy has only six illustrated Effects that need a target, too few for 20 cards,
  -- so both seats use Water (Goldfish allows eight copies).
  local c=L.new();c.factions={"Water","Water"}
  local targets={{31,32,57,36,38,39,58},{31,32,57,36,38,39,58}}
  for p=1,2 do
    for i=1,20 do assert(L.edit(c,p,c.factions[p]..':'..targets[p][(i-1)%7+1],1)) end
  end
  local result;local m=M.new(c,2,function(r) result=r end)
  assert(m.state.finished and result.winner==0 and #result.rounds==3);integrity(m,c)
end)
-- Every design in the playable pool is played into a crowded board twice: once normally and once
-- with its own Deploy/Effect definition removed. The two results must differ.
test("Every card in the pool plays legally and its Deploy or Effect ability changes the game",function()
  local base=cfg();local realget=A.get
  local function snap(s)
    local t={'plays'..s.plays_left..tostring(s.extra_turn),'log'..#s.log}
    for p=1,2 do local pl=s.players[p]
      for _,z in ipairs({'hand','deck','discard'}) do
        local ids={};for _,u in ipairs(pl[z]) do ids[#ids+1]=u.uid end;t[#t+1]=z..p..':'..table.concat(ids,',')
      end
      for r=1,2 do for i,u in ipairs(pl.rows[r]) do
        t[#t+1]=table.concat({u.uid,p,r,i,B.strength(s,u),u.hp,u.guard or 0,tostring(u.negate_damage),tostring(u.disabled)},'/')
      end end
    end
    return table.concat(t,'|')
  end
  local function setup(f,n,id)
    local s=M.new(base,n).state;s.active=1;s.plays_left=1;s.extra_turn=nil
    for p=1,2 do local pl=s.players[p];pl.rows={{},{}};pl.hand={};pl.deck={};pl.discard={};pl.passed=false end
    -- The Comic front row holds each pair partner: both Dans, a Warden to replace, both Sidekicks.
    local front={Water={1,4,8,11,26},Fantasy={1,5,11,17,41},Super={12,71,72,61,74,75}}
    for _,k in ipairs(front[f]) do unit(s,1,f..':'..k,1) end
    for _,x in ipairs({'Fantasy:19','Fantasy:26','Fantasy:15','Fantasy:12'}) do unit(s,1,x,2).mod=-1 end
    for _,x in ipairs({'Water:12','Water:49','Water:7','Fantasy:17'}) do unit(s,2,x,1) end
    for _,x in ipairs({'Water:2','Water:61','Water:27'}) do unit(s,2,x,2) end
    for p=1,2 do for r=1,2 do for _,u in ipairs(s.players[p].rows[r]) do if u.hp>2 then u.hp=u.hp-2 end end end end
    for i=1,6 do s.players[1].deck[i]=unit(s,1,f..':'..(i*3));s.players[2].deck[i]=unit(s,2,'Water:'..(i*4)) end
    for _,k in ipairs({1,2,31,33,10}) do table.insert(s.players[1].discard,unit(s,1,f..':'..k)) end
    table.insert(s.players[2].discard,unit(s,2,'Water:3'))
    if f=='Super' then table.insert(s.players[1].deck,1,unit(s,1,'Super:73')) end
    for i=1,3 do s.players[2].hand[i]=unit(s,2,'Water:'..(i+20)) end
    -- Amount prompts list the largest value first; the last entry would be "none".
    s.chooser=function(_,_,kind,options) return kind=='amount' and 1 or #options end
    -- Keep a legal high-rank target alive so overkill cannot mask a strike modifier.
    if A[f][n] and A[f][n].strike then
      for r=1,2 do unit(s,2,'Fantasy:65',r).guard=12 end
    end
    s.players[1].hand={unit(s,1,id),unit(s,1,f..':7'),unit(s,1,f..':8')}
    return s
  end
  local allowed={}
  for _,f in ipairs(L.factions) do for _,card in ipairs(L.collection(f)) do
    local id,n=card.id,card.number
    local trig=A[f] and A[f][n] or {}
    local s=setup(f,n,id);local row=B.placement_row(card)
    local pos=row and #s.players[B.deploy_side(1,card)].rows[row]+1
    if not B.playable(s,1,1) then assert(allowed[id]=='unplayable',id..' '..card.name..' cannot be played')
    else
      assert(B.play(s,1,1,row,pos),id..' rejected')
      if trig.deploy or trig.pre_attack or trig.strike or trig.play then
        local plain=setup(f,n,id)
        A.get=function(c,t) if c.id==id then return nil end return realget(c,t) end
        local ok=pcall(B.play,plain,1,1,row,pos);A.get=realget;assert(ok)
        assert(snap(s)~=snap(plain) or allowed[id]=='quiet',id..' '..card.name..' ability had no effect')
      end
    end
  end end
end)
test("New Water cards: Lighthouse, Deep-Sea Diver, The White Whale, Bleached Reef",function()
  local function fresh()
    local m=M.new(cfg(),31);local s=m.state;s.active=1;s.plays_left=1;s.extra_turn=nil
    for p=1,2 do local pl=s.players[p];pl.rows={{},{}};pl.hand={};pl.deck={};pl.discard={};pl.passed=false end
    s.players[2].hand={unit(s,2,"Water:1")}
    return m,s
  end
  -- Lighthouse: Bridge rank 3; at the start of each of its controller's turns, top card may go to the bottom.
  local m,s=fresh();local pl=s.players[1]
  local a,b,c=unit(s,1,'Water:1'),unit(s,1,'Water:7'),unit(s,1,'Water:12');pl.deck={a,b,c}
  local light=unit(s,1,'Water:71');pl.hand={light,unit(s,1,'Water:1')}
  assert(light.card.bridge and light.card.strength==3)
  s.players[2].hand={unit(s,2,'Water:1')}
  assert(m:act({type='play',index=1,row=2,pos=1}))
  assert(s.active==2);m.controllers[1]="Human";m.controllers[2]="AI"
  assert(m:act({type='ai'}))
  assert(m.prompt and m.prompt.kind=='beacon' and m.prompt.context.cards[1]==b and pl.hand[#pl.hand]==c)
  assert(m:choose(2));assert(pl.deck[1]==b and pl.deck[2]==a,"top card moved to the bottom")
  assert(table.concat(s.log,'\n'):find('sends the top card',1,true))
  -- Deep-Sea Diver: looks at the bottom 3, takes one, rest stay at the bottom in the chosen order.
  m,s=fresh();pl=s.players[1];m.controllers[1]="Human"
  local d1,d2,d3,top=unit(s,1,'Water:61'),unit(s,1,'Water:31'),unit(s,1,'Water:40'),unit(s,1,'Water:2')
  pl.deck={d1,d2,d3,top}
  pl.hand={unit(s,1,'Water:72'),unit(s,1,'Water:1')}
  assert(m:act({type='play',index=1,row=2,pos=1}))
  assert(m.prompt.context.op=='search' and m.prompt.context.bottom and #m.prompt.options==3)
  assert(m.prompt.context.cards[1]==d1 and m.prompt.context.cards[3]==d3)
  assert(m:choose(1));assert(pl.hand[#pl.hand]==d1,"Blue Whale from the bottom is in hand")
  assert(m.prompt.kind=='bottom_order');assert(m:choose(2))
  assert(not m.prompt and #pl.deck==3 and pl.deck[3]==top,"top card untouched")
  -- The White Whale: enters with 4 unpreventable damage; opposing damage it survives gives +2.
  m,s=fresh();pl=s.players[1]
  local whale=unit(s,1,'Water:73');pl.hand={whale,unit(s,1,'Water:1')};whale.guard=5
  assert(B.play(s,1,1,1,1));assert(whale.hp==8 and B.strength(s,whale)==7,"self-damage does not trigger Relentless")
  B.damage(s,2,whale,3);assert(whale.hp==5 and B.strength(s,whale)==9)
  B.damage(s,1,whale,1);assert(whale.hp==4 and B.strength(s,whale)==9,"own damage is not opposing")
  B.damage(s,2,whale,4);assert(not B.position(s,whale),"no bonus once destroyed")
  -- Bleached Reef: strips positive boosts in the chosen opposing row; otherwise draws 1.
  m,s=fresh();pl=s.players[1];s.chooser=function(_,_,kind,options) return 1 end
  local boosted,weak,plain,whaleBack=unit(s,2,'Water:8',1),unit(s,2,'Water:12',1),unit(s,2,'Water:7',1),unit(s,2,'Water:61',2)
  boosted.mod=3;weak.mod=-2;whaleBack.mod=2
  pl.deck={unit(s,1,'Water:1')};pl.hand={unit(s,1,'Water:74'),unit(s,1,'Water:1')}
  assert(B.play(s,1,1));assert(boosted.mod==0 and weak.mod==-2 and plain.mod==0 and whaleBack.mod==2)
  assert(#pl.deck==1,"no draw when a boost was removed")
  s.active=1;s.plays_left=1;pl.hand={unit(s,1,'Water:74'),unit(s,1,'Water:1')}
  assert(B.play(s,1,1));assert(#pl.deck==0 and #pl.hand==2,"draws when nothing was bleached")
  -- Blue Whale ignores the area effect, so bleaching the Back row draws instead.
  s.active=1;s.plays_left=1;s.chooser=function(_,_,kind) return kind=='row' and 2 or 1 end
  pl.deck={unit(s,1,'Water:2')};pl.hand={unit(s,1,'Water:74'),unit(s,1,'Water:1')}
  assert(B.play(s,1,1));assert(whaleBack.mod==2 and #pl.deck==0)
end)
test("A turn draws one card, extra plays share the turn, and exhausted decks stay empty",function()
  local s=M.new(cfg(),13).state
  local p=s.active;local q=3-p
  local me,foe=s.players[p],s.players[q]
  local extra=unit(s,p,'Super:70')
  me.hand[1]=extra;me.hand[2]=unit(s,p,'Water:1')
  assert(B.play(s,p,1));assert(s.extra_turn and #me.deck==15 and #foe.hand==5)
  assert(B.end_extra(s,p));assert(s.active==q and #foe.hand==6 and #foe.deck==14)
  assert(B.pass(s,q) and s.round==1 and B.pass(s,p) and s.round==2 and s.active==q)
  assert(#me.hand==7 and #foe.hand==8 and #foe.deck==12)
  foe.deck={};local count=#foe.hand
  assert(B.draw(s,q,1)==0 and #foe.hand==count)
end)
test("Sardine checks immediate friendly fish neighbors and their printed strength",function()
  local s=M.new(cfg(),13).state
  local sardine=unit(s,1,'Water:4',1)
  unit(s,2,'Water:4',1);unit(s,1,'Water:2',2)
  assert(B.strength(s,sardine)==2)
  local crab=unit(s,1,'Water:17',1);local fish=unit(s,1,'Water:5',1);fish.mod=5
  assert(B.strength(s,sardine)==2)
  B.damage(s,2,crab,99);assert(B.strength(s,sardine)==3)
  local big=unit(s,1,'Water:8');big.mod=-2
  table.insert(s.players[1].rows[1],2,big);assert(B.strength(s,sardine)==2)
end)
test("Showdown retrieves available characters together and Repel only recovers Gunner",function()
  for _,scenario in ipairs({'all','partial','empty','prefer hand'}) do
    local s=M.new(cfg(),13).state;s.active=1
    local pl=s.players[1];local hero=unit(s,1,'Super:15')
    local heroine,gunner=unit(s,1,'Super:27'),unit(s,1,'Super:32')
    pl.hand={unit(s,1,'Super:57')};pl.deck={};pl.discard={}
    local target=unit(s,2,'Fantasy:48',1)
    if scenario=='all' then pl.deck={hero};pl.hand[2]=heroine;pl.discard={gunner}
    elseif scenario=='partial' then pl.discard={heroine,gunner}
    elseif scenario=='prefer hand' then pl.hand[2]=gunner;pl.discard={unit(s,1,'Super:32')}
    else pl.discard={hero,heroine};unit(s,2,'Super:32',2) end
    local plays=s.stats.played[1]
    assert(B.play(s,1,1))
    assert(s.stats.played[1]==plays+1 and #Chains.find(pl)==0)
    assert(pl.discard[#pl.discard].card.id=='Super:57')
    local front,back=pl.rows[1],pl.rows[2]
    if scenario=='all' then
      assert(#front==2 and front[1]==hero and front[2]==heroine and #back==1 and back[1]==gunner)
      assert(target.hp==target.card.health-6,'Heroine skips Front, but Gunner still attacks')
    elseif scenario=='empty' then
      assert(#front==0 and #back==0 and #pl.discard==3 and target.hp==target.card.health)
    else
      assert(#front==0 and #back==1 and back[1]==gunner and #pl.discard==2)
      assert(target.hp==target.card.health-3)
    end
    if B.position(s,gunner) then
      B.damage(s,2,gunner,99)
      assert(not B.position(s,gunner) and pl.discard[#pl.discard]==gunner)
    end
  end
end)
test("Showdown deploys together and prompts for each attack using the current battlefield",function()
  local View=require('online.view');local json=require('online.json')
  local metrics=assert(loadfile('web/metrics.lua'))()
  for _,gunnerTarget in ipairs({'Front','Back'}) do
    local m=M.new(cfg(),121);m.controllers={'Human','Human'}
    local s=m.state;s.active=1
    local pl=s.players[1]
    local effect=unit(s,1,'Super:57')
    local hero,heroine,gunner=unit(s,1,'Super:15'),unit(s,1,'Super:27'),unit(s,2,'Super:32')
    pl.hand={effect,heroine};pl.deck={hero};s.players[2].discard={gunner}
    local fragile=unit(s,2,'Fantasy:1',1);fragile.hp=1
    local front=unit(s,2,'Fantasy:48',1)
    local weakBack=unit(s,2,'Fantasy:21',2)
    local back=unit(s,2,'Fantasy:48',2)
    local start=s.turns
    local function prompt(attacker,...)
      local q=m.prompt;local expected={...}
      assert(q and q.actor==1 and q.context.op=='deploy_attack' and q.context.unit==attacker)
      assert(s.active==1 and s.turns==start and s.plays_left==0 and not U.contains(pl.discard,effect))
      assert(#q.options==#expected)
      local view=View.build(s,1,{seq=1,mode='duel',controllers=m.controllers,prompt=q})
      local preview=json.decode(metrics(json.encode(view))).attackPreview
      assert(view.last.c==effect.card.id and view.prompt.context.unit.u==attacker.uid)
      assert(U.count(preview)==#expected)
      for i,u in ipairs(expected) do
        assert(q.options[i]==u and preview[tostring(u.uid)]==attacker.card.strength)
      end
    end
    assert(m:act({type='play',index=1}))
    assert(pl.rows[1][1]==hero and pl.rows[1][2]==heroine and pl.rows[2][1]==gunner)
    assert(not U.contains(s.players[2].discard,gunner) and gunner.owner==2)
    prompt(hero,fragile,front,weakBack,back)
    assert(m:choose(1) and not fragile.hp)
    prompt(heroine,weakBack,back)
    assert(m:choose(1) and not weakBack.hp)
    prompt(gunner,front,back)
    local target=gunnerTarget=='Front' and front or back
    assert(m:choose(gunnerTarget=='Front' and 1 or 2))
    assert(target.hp==target.card.health-3 and front.hp+back.hp==front.card.health+back.card.health-3)
    assert(s.active==2 and s.turns==start+1 and not m.prompt and pl.discard[1]==effect)
    assert(s.stats.played[1]==1 and s.stats.played[2]==0)
    local attacks={}
    for _,line in ipairs(s.log) do
      local name=line:match('^(.-) attacks ')
      if name then attacks[name]=(attacks[name] or 0)+1 end
    end
    for _,u in ipairs({hero,heroine,gunner}) do assert(attacks[u.card.name]==1) end
  end
end)
test("A chain earned between Showdown attacks resolves before the turn changes",function()
  local s=M.new(cfg(),55).state;s.active=1
  local effect=unit(s,1,'Super:57');s.players[1].hand={effect}
  s.players[1].deck={unit(s,1,'Super:15'),unit(s,1,'Super:27'),unit(s,1,'Super:32')}
  local minnow=unit(s,2,'Water:2',1)
  local blocker=unit(s,2,'Super:15',1);blocker.hp=1
  unit(s,2,'Water:5',1);unit(s,2,'Water:8',1)
  local back=unit(s,2,'Super:27',2)
  s.chooser=function(_,_,_,options,ctx)
    if ctx.op=='deploy_attack' then
      local target=ctx.unit.card.id=='Super:15' and blocker or ctx.unit.card.id=='Super:27' and back or minnow
      for i,u in ipairs(options) do if u==target then return i end end
      error('Required target was missing')
    end
    return 1
  end
  local drew=false
  s.on_draw=function(event)
    if event.source=='Minnow' then
      assert(s.active==1 and U.contains(s.players[1].discard,effect))
      assert(not blocker.hp and not minnow.hp and back.hp==back.card.health-3)
      drew=true
    end
  end
  assert(B.play(s,1,1) and drew and s.active==2 and s.stats.chain_activated[2]==1)
end)
test("Placement previews use unmodified ranks and only link the right ends",function()
  local preview=require('tabletop.placement').preview
  local s=M.new(cfg(),13).state
  local pl=s.players[1]
  local minnow=unit(s,1,'Water:2',1);minnow.mod=4
  local seahorse=unit(s,1,'Water:21',1)
  local three=L.cards.by_id['Water:12']
  local ch=assert(preview(pl,2,1,three))
  assert(ch.cross and ch.length==3 and #pl.rows[2]==0,"preview must leave the board untouched")
  seahorse.disabled=true;assert(not preview(pl,2,1,three))
  seahorse.disabled=false
  unit(s,1,'Water:7',1)
  assert(not preview(pl,2,1,three),"a Bridge in the middle cannot link the rows")
end)
test("Comic cards never form numerical chains, including in another faction's rows",function()
  local s=M.new(cfg(),13).state
  for p=1,2 do s.players[p].rows={{},{}} end
  for _,id in ipairs({'Super:74','Super:73','Super:62'}) do unit(s,1,id,1) end
  assert(#Chains.find(s.players[1])==0,"Brave, T-Rex and Neon Comet are unrelated")
  s.players[1].rows={{},{}}
  for _,id in ipairs({'Super:15','Super:61','Super:74'}) do unit(s,1,id,1) end
  assert(#Chains.find(s.players[1])==0,"Warden only participates in its named pairing")
  s.players[1].rows={{},{}}
  unit(s,1,'Fantasy:1',1);unit(s,1,'Super:78',1);unit(s,1,'Fantasy:6',1)
  assert(#Chains.find(s.players[1])==0,"a stolen Comic card cannot bridge numerical ranks")
  s.players[1].rows={{},{}}
  unit(s,1,'Water:1',1);unit(s,1,'Water:4',1);unit(s,1,'Water:8',1)
  assert(#Chains.find(s.players[1])==1,"Water's numerical chains still resolve")
end)
test("Comic edition: Dinosaur trio, Warden and Phantom, Sidekick order, Monochrome double agents",function()
  local function fresh()
    local c=cfg();c.factions={"Super","Fantasy"};L.starter(c,1,20);L.starter(c,2,20)
    local m=M.new(c,31);local s=m.state;s.active=1;s.plays_left=1;s.extra_turn=nil
    for p=1,2 do local pl=s.players[p];pl.rows={{},{}};pl.hand={};pl.deck={};pl.discard={};pl.passed=false end
    s.chooser=function(_,_,_,options) return #options end
    s.players[2].hand={unit(s,2,"Water:1")}
    return m,s
  end
  local function turn(s) s.active=1;s.plays_left=1;s.players[1].passed=false end
  -- A T-Rex in hand cannot bypass the pair requirement.
  local m,s=fresh();local pl=s.players[1]
  pl.hand={unit(s,1,'Super:73'),unit(s,1,'Super:71'),unit(s,1,'Super:72')}
  assert(not B.playable(s,1,1),"T-Rex needs both Dans deployed")
  assert(not B.play(s,1,1,1,1),"direct play cannot bypass the requirement")
  local dan=unit(s,1,'Super:71',1)
  assert(not B.playable(s,1,1),"one Dan on the board is insufficient")
  unit(s,2,'Super:72',1)
  assert(not B.playable(s,1,1),"an opposing Dan is insufficient")
  unit(s,1,'Super:72',2)
  assert(B.playable(s,1,1),"both controlled Dans allow entry")
  B.damage(s,2,dan,99)
  assert(not B.playable(s,1,1),"a dead Dan cannot enable entry")
  -- Dinosaur Dan + Dan the Dinosaur pull the T-Rex from the draw deck, free of charge.
  m,s=fresh();local foe;pl,foe=s.players[1],s.players[2]
  local rex=unit(s,1,'Super:73');pl.deck={unit(s,1,'Super:2'),rex,unit(s,1,'Super:3')}
  local e1,e2=unit(s,2,'Fantasy:1',2),unit(s,2,'Fantasy:5',2);local hp1,hp2=e1.hp,e2.hp
  for i=1,2 do unit(s,2,'Fantasy:48',1).guard=20 end -- ordinary targets for the two Dans
  pl.hand={unit(s,1,'Super:71'),unit(s,1,'Super:72'),unit(s,1,'Super:12'),unit(s,1,'Super:12')}
  assert(B.play(s,1,1,1,1));assert(#pl.deck==3 and not B.position(s,rex),"one Dan alone summons nothing")
  turn(s);assert(B.play(s,1,1,1,2))
  local side,row=B.position(s,rex);assert(side==1 and row==2 and #pl.deck==2 and #pl.hand==2,"T-Rex enters from the deck without a card play")
  assert(e1.hp==hp1-2 and e2.hp==hp2-2,"its Deploy ability resolves on entry")
  assert(s.stats.played[1]==2 and rex.controller==1 and rex.hp==8)
  -- From the hand when no copy is in the draw deck; nothing when there is no copy at all.
  m,s=fresh();pl=s.players[1];rex=unit(s,1,'Super:73')
  unit(s,1,'Super:72',1);pl.hand={unit(s,1,'Super:71'),rex,unit(s,1,'Super:12')}
  assert(B.play(s,1,1,1,1));assert(B.position(s,rex)==1 and #pl.hand==1)
  m,s=fresh();pl=s.players[1];unit(s,1,'Super:72',1);pl.hand={unit(s,1,'Super:71'),unit(s,1,'Super:12')}
  assert(B.play(s,1,1,1,1));assert(#B.units(s,1)==2 and table.concat(s.log,'\n'):find('finds no Roaring T-Rex',1,true))
  -- The summon is a named pair interaction. T-Rex has no numerical chain bonus.
  m,s=fresh();pl=s.players[1];rex=unit(s,1,'Super:73');pl.deck={rex}
  unit(s,1,'Super:71',1);pl.hand={unit(s,1,'Super:72'),unit(s,1,'Super:12')}
  s.chooser=function(_,_,kind,options) return kind=='row' and 1 or #options end
  assert(B.play(s,1,1,1,2));assert(not rex.activated.chain and B.strength(s,rex)==6,"summoned T-Rex keeps its printed strength")

  -- Multiverse Phantom is played only onto a Cosmic Warden and takes its exact position.
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local phantom,warden=unit(s,1,'Super:66'),unit(s,1,'Super:61')
  pl.hand={phantom,warden,unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  local ok,why=B.playable(s,1,1);assert(not ok and why:find('Cosmic Warden',1,true))
  unit(s,1,'Super:12',1);unit(s,1,'Super:24',1)
  assert(B.play(s,1,2,1,2));turn(s)
  local a,b,big=unit(s,2,'Fantasy:1',1),unit(s,2,'Fantasy:5',2),unit(s,2,'Fantasy:48',2);local bigHp=big.hp
  unit(s,2,'Fantasy:1',1)
  s.chooser=function(_,_,_,options,ctx) return ctx.op=='deploy_attack' and 1 or #options end
  assert(B.playable(s,1,1));assert(B.play(s,1,1))
  local ps,pr,pi=B.position(s,phantom);assert(ps==1 and pr==1 and pi==2,"takes the Warden's place")
  assert(not B.position(s,warden) and pl.discard[#pl.discard]==warden and not warden.hp)
  assert(not B.position(s,a) and big.hp==bigHp-3 and #pl.deck==0 and B.strength(s,phantom)==9)
  -- The risk: once the Warden is destroyed the Phantom cannot be played.
  m,s=fresh();pl=s.players[1];phantom=unit(s,1,'Super:66');warden=unit(s,1,'Super:61',1)
  pl.hand={phantom,unit(s,1,'Super:12')};assert(B.playable(s,1,1))
  B.damage(s,2,warden,4);assert(not B.position(s,warden) and not B.playable(s,1,1))

  -- Sidekicks: the second one played decides the effect.
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local brave,scared=unit(s,1,'Super:74'),unit(s,1,'Super:75')
  pl.deck={unit(s,1,'Super:2'),brave,unit(s,1,'Super:3')};pl.hand={scared,unit(s,1,'Super:12'),unit(s,1,'Super:12')}
  local victim=unit(s,2,'Fantasy:48',2);local vhp=victim.hp
  unit(s,2,'Fantasy:1',1).guard=20
  assert(B.play(s,1,1,2,1));assert(pl.hand[#pl.hand]==brave and #pl.deck==2,"Scared first: Distress Call fetches Brave Sidekick")
  assert(m.draws[#m.draws].cards[1]==brave,"the fetch is reported like a draw")
  turn(s);assert(B.play(s,1,#pl.hand,1,1))
  assert(B.strength(s,scared)==5 and victim.hp==vhp-3 and brave.guard==0,"Brave second: +3 and 3 damage")
  m,s=fresh();pl=s.players[1];brave,scared=unit(s,1,'Super:74'),unit(s,1,'Super:75')
  pl.hand={brave,scared,unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,1,1));assert(brave.guard==3,"Brave first: guards itself")
  turn(s);assert(B.play(s,1,1,2,1))
  assert(brave.negate_damage and scared.negate_damage and #pl.deck==1 and B.strength(s,scared)==2,"Scared second: both turn ghostly")
  B.damage(s,2,scared,9);assert(B.position(s,scared) and not scared.negate_damage,"the next opposing damage effect is ignored once")
  m,s=fresh();pl=s.players[1];pl.hand={unit(s,1,'Super:75'),unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,2,1));assert(#pl.deck==0 and #pl.hand==2,"no Brave Sidekick in the deck: draw 1 instead")

  m,s=fresh();pl,foe=s.players[1],s.players[2]
  brave,scared=unit(s,1,'Super:74'),unit(s,1,'Super:75',1)
  victim=unit(s,2,'Fantasy:48',1);vhp=victim.hp
  B.damage(s,2,scared,99)
  pl.hand={brave,unit(s,1,'Super:12')}
  assert(B.play(s,1,1,1,1))
  assert(victim.hp==vhp-brave.card.strength and brave.hp==brave.card.health and brave.guard==3,"a dead Scared Sidekick does not trigger the pair")
  m,s=fresh();pl=s.players[1]
  brave,scared=unit(s,2,'Super:74',1),unit(s,1,'Super:75')
  pl.hand={scared,unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,2,1))
  assert(not brave.negate_damage and not scared.negate_damage,"an opposing Sidekick does not count as your partner")

  -- Spy: deployed on the opposing battlefield, becomes the opponent's card.
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local spy=unit(s,1,'Super:78');pl.hand={spy,unit(s,1,'Super:12'),unit(s,1,'Super:12')}
  local loot=unit(s,2,'Fantasy:40');foe.discard={unit(s,2,'Fantasy:1'),loot};foe.hand={unit(s,2,'Fantasy:1'),unit(s,2,'Fantasy:39')}
  local sentry=unit(s,2,'Fantasy:5',1)
  table.insert(foe.rows[2],table.remove(foe.rows[1]))
  assert(not B.play(s,1,1,1,3),"positions are counted on the opposing row");assert(B.play(s,1,1,1,1))
  local ss,sr,si=B.position(s,spy);assert(ss==2 and sr==1 and si==1 and spy.owner==2 and spy.controller==2)
  assert(B.score(s,1)==0 and sentry.hp==sentry.card.health-spy.card.strength and B.score(s,2)==spy.hp+sentry.hp and B.strength(s,spy)==spy.card.strength,"the Spy attacks once and its remaining HP counts for its new controller")
  assert(pl.hand[#pl.hand]==loot and loot.owner==2 and loot.controller==1,"Vault Heist takes the chosen discard")
  B.damage(s,1,spy,9);assert(foe.discard[#foe.discard]==spy,"a Double Agent goes to its new owner's discard pile")
  -- Even a Fantasy deck can pull it back: Monochrome counts as every faction for discard abilities.
  s.active=2;s.plays_left=1;assert(B.playable(s,2,2));assert(B.play(s,2,2))
  assert(foe.hand[#foe.hand]==spy,"Fantasy recovery returns the Monochrome Unit")
  s.active=2;s.plays_left=1;assert(B.play(s,2,#foe.hand,1,1))
  ss,sr=B.position(s,spy);assert(ss==1 and sr==1 and spy.owner==1,"played back, it lands on the first player's battlefield")
  -- Hood: the top three cards of the opposing draw deck go to its discard pile.
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local d1,d2,d3,d4=unit(s,2,'Fantasy:1'),unit(s,2,'Fantasy:2'),unit(s,2,'Fantasy:3'),unit(s,2,'Fantasy:4')
  foe.deck={d1,d2,d3,d4};pl.hand={unit(s,1,'Super:77'),unit(s,1,'Super:12')}
  assert(B.play(s,1,1,2,1));assert(#foe.deck==0 and foe.hand[#foe.hand]==d1 and #foe.discard==3 and foe.discard[1]==d4)
  -- Vigilante: trade one of your Units for an opposing one (printed 5 or less, movable).
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local weak,strong=unit(s,1,'Super:2',1),unit(s,1,'Super:30',1)
  local five,treant,giant=unit(s,2,'Fantasy:41',1),unit(s,2,'Fantasy:48',1),unit(s,2,'Fantasy:64',2)
  assert(five.card.strength<=5 and giant.card.strength>5,"fixture ranks")
  local vig=unit(s,1,'Super:76');pl.hand={vig,unit(s,1,'Super:12')}
  s.chooser=nil
  assert(B.play(s,1,1,1,3))
  local ws,wr,wi=B.position(s,weak);local fs,fr,fi=B.position(s,five)
  assert(ws==2 and wr==1 and wi==1 and weak.controller==2 and weak.owner==1,"the weakest friendly Unit crosses over")
  assert(fs==1 and fr==1 and fi==1 and five.controller==1 and five.owner==2,"the strongest eligible opposing Unit comes back")
  assert(B.position(s,treant)==2 and B.position(s,giant)==2 and B.position(s,vig)==2,"immovable, high-rank and the agent itself stay")
  B.damage(s,2,five,99);assert(foe.discard[#foe.discard]==five,"a traded Unit still returns to its owner's discard pile")
  -- The computer plays every new card to a finish from both seats.
  for seed=1,12 do
    local c=cfg();c.factions={seed%2==0 and "Super" or "Water","Super"};L.starter(c,1,20);L.starter(c,2,20)
    local match=M.new(c,900+seed);local turns=0
    while not match.state.finished do assert(match:act({type='ai'}));integrity(match,c);turns=turns+1;assert(turns<200) end
  end
end)
test("A card play chooses basic and printed targets before passing control",function()
  local c=cfg();local m=M.new(c,23);m.controllers={"Human","Human"}
  local s=m.state;s.active=1
  local scared=unit(s,1,'Super:75',1)
  local guard=unit(s,2,'Fantasy:23',1);guard.guard=4
  unit(s,2,'Water:1',1)
  local back=unit(s,2,'Fantasy:48',2)
  local brave=unit(s,1,'Super:74')
  s.players[1].hand={brave};local start=s.turns
  assert(m:act({type='play',index=1,row=1,pos=2}))
  assert(m.prompt.context.op=='deploy_attack' and #m.prompt.options==2 and s.active==1 and s.plays_left==0)
  assert(m.prompt.options[1]==guard and guard.hp==guard.card.health)
  assert(m:choose(1) and m.prompt.context.op=='damage' and #m.prompt.options==3)
  assert(s.turns==start and B.strength(s,scared)==5 and guard.hp==guard.card.health-1)
  assert(brave.hp==brave.card.health)
  assert(m:choose(3) and not m.prompt and back.hp==back.card.health-3 and s.active==2)
  assert(not m:act({type='attack',index=1,row=1,pos=1}))
end)
test("Rune Apprentice and High Elf Spellblade earn chain strikes during deployment",function()
  for _,id in ipairs({'Fantasy:16','Fantasy:42'}) do
    local m=M.new(cfg(),71);m.controllers={"Human","Human"}
    local s=m.state;s.active=1
    local row=B.placement_row(L.cards.by_id[id])
    unit(s,1,'Fantasy:1',row)
    if id=='Fantasy:16' then unit(s,1,'Fantasy:9',row)
    else unit(s,1,'Fantasy:9',1);unit(s,1,'Fantasy:12',1) end
    local source=unit(s,1,id);s.players[1].hand={source}
    local wall=unit(s,2,'Fantasy:48',1);wall.guard=30
    local back=unit(s,2,'Fantasy:48',2)
    if id=='Fantasy:42' then back.guard=5 else wall.mod=12 end
    local pos=id=='Fantasy:16' and 3 or 4
    assert(m:act({type='play',index=1,row=row,pos=pos}))
    assert(m.prompt and m.prompt.context.op=='damage' and m.prompt.options[2]==back)
    assert(source.hp==source.card.health)
    assert(m:choose(2) and back.hp==back.card.health-2 and s.active==2)
  end
end)
test("A wipe allows reinforcements and round cleanup preserves the existing piles",function()
  local c=cfg();local s=M.new(c,99).state;s.active=1
  local foe=unit(s,2,'Fantasy:12',1)
  local big=unit(s,1,'Fantasy:48');s.players[1].hand={big}
  local light=unit(s,1,'Fantasy:1',2)
  B.damage(s,2,light,99)
  assert(s.round==1 and B.playable(s,1,1))
  foe.hp=2
  assert(B.play(s,1,1,1,1) and not foe.hp and s.round==1 and s.active==2)
  assert(big.hp==big.card.health and B.strength(s,big)==big.card.strength)
  assert(B.pass(s,2) and s.round==1 and B.pass(s,1))
  assert(s.round_history[1].winner==1 and s.round_history[1].scores[1]==big.card.health)
  assert(U.contains(s.players[1].discard,big) and U.contains(s.players[2].discard,foe))
  assert(#s.players[1].hand==3 and #s.players[2].hand==8 and B.score(s,1)==0 and s.round==2)
end)
test("Wounded heal targets, recovery fallback, and an exhausted seat waiting for a legal draw",function()
  local s=M.new(cfg(),194).state;s.active=1
  local healthy=unit(s,1,'Water:1',1);local hurt=unit(s,1,'Fantasy:23',2)
  local healer=unit(s,1,'Fantasy:10');hurt.hp=1
  s.chooser=function(_,_,kind,options,ctx)
    if ctx.op=='heal' then assert(#options==1 and options[1]==hurt and hurt.hp==1) end
    return 1
  end
  B.resolve(s,1,healer,A.get(healer.card,'deploy'))
  assert(hurt.hp==4 and healthy.hp==healthy.card.health)
  local acolyte=unit(s,1,'Fantasy:21');local top=unit(s,1,'Fantasy:31');s.players[1].deck={top}
  B.resolve(s,1,acolyte,A.get(acolyte.card,'deploy'))
  assert(s.players[1].hand[#s.players[1].hand]==top)
  local q=s.players[2];q.hand={unit(s,2,'Super:66')};q.deck={unit(s,2,'Super:61'),unit(s,2,'Super:66')}
  s.players[1].hand={unit(s,1,'Fantasy:1'),unit(s,1,'Fantasy:1')}
  assert(B.play(s,1,1,1,1) and s.round==1 and s.active==1 and #q.deck==1)
  assert(B.play(s,1,1,1,1) and s.active==2 and s.round==1 and #q.deck==0)
  assert(B.playable(s,2,#q.hand),'the Warden draw lets the empty field recover')
end)
test("No turn cutoff or KO tiebreak and both deck builders use actual tagged partners",function()
  local s=M.new(cfg(),13).state
  for i=1,18 do
    local p=s.active;s.players[p].hand={unit(s,p,'Water:1')}
    assert(B.play(s,p,1,1,1) and s.round==1)
  end
  local help=require('tabletop.deck_help')
  assert(help.describe(L.cards.by_id['Super:66'],{'Super:61'}):find('Cosmic Warden ×1',1,true))
  assert(help.describe(L.cards.by_id['Water:4'],{'Water:4','Water:2','Water:6'}):find('2 other',1,true))
  assert(help.describe(L.cards.by_id['Water:66'],{'Water:31'}):find('Tag more',1,true))
  assert(help.describe(L.cards.by_id['Fantasy:21'],{'Fantasy:31','Fantasy:16'}):find('1 tagged',1,true))
end)
test("Spy's stolen Grave Acolyte chooses either personal pile across factions",function()
  local View=require('online.view')
  for _,zone in ipairs({'discard','deck'}) do
    local m=M.new(cfg(),43);local s=m.state;local pl,foe=s.players[1],s.players[2]
    local acolyte=unit(s,2,'Fantasy:21');acolyte.home=2
    local spy=unit(s,1,'Super:78');spy.home=1
    pl.hand={spy};foe.discard={acolyte}
    s.active=1;assert(B.play(s,1,1,1,1))
    assert(pl.hand[1]==acolyte and acolyte.owner==2 and acolyte.controller==1)
    local function pile()
      return {unit(s,1,'Super:15'),unit(s,1,'Water:1'),unit(s,1,'Fantasy:1'),unit(s,1,'Super:70'),unit(s,1,'Super:66')}
    end
    pl.deck=pile();pl.discard=pile()
    pl.discard[#pl.discard+1]=unit(s,1,'Super:32')
    local target=pl[zone][2]
    m.controllers[1]='Human';s.active=1;s.plays_left=1
    assert(m:act({type='play',index=1,row=2,pos=1}))
    assert(m.prompt.kind=='zone' and m.prompt.actor==1)
    assert(m:choose(zone=='discard' and 1 or 2))
    assert(m.prompt.context.op==(zone=='discard' and 'grave_recover' or 'grave_search'))
    assert(#m.prompt.options==(zone=='discard' and 4 or 3) and not View.prompt(m.prompt,2).options)
    local pick
    for i,c in ipairs(m.prompt.options) do if c==target then pick=i end end
    assert(m:choose(assert(pick)) and pl.hand[#pl.hand]==target and s.active==2)
    assert(not U.contains(pl[zone],target) and target.controller==1 and target.owner==1)
    B.damage(s,2,acolyte,99)
    assert(U.contains(foe.discard,acolyte) and acolyte.owner==2)
    assert(B.pass(s,2) and B.pass(s,1) and s.round==2)
    assert(U.contains(foe.discard,acolyte))
    assert(spy.owner==2 and spy.controller==2 and U.contains(foe.discard,spy))
  end
end)
test("Every Showdown retrieves one physical Gunner, including a repeat on a stolen Showdown",function()
  for side=1,2 do for _,zone in ipairs({'deck','hand','discard'}) do
    local s=M.new(cfg(),12).state;s.active=1
    local pl,foe=s.players[1],s.players[2]
    for _,p in ipairs(s.players) do p.deck={};p.hand={};p.discard={} end
    local owner=zone=='discard' and side or 2
    local gunner=unit(s,owner,'Super:32');gunner.home=owner
    gunner.controller=side
    local pile=s.players[side][zone];pile[#pile+1]=gunner
    local other=unit(s,2,'Fantasy:48');foe.hand[#foe.hand+1]=other
    local first=unit(s,1,'Super:57');pl.hand[#pl.hand+1]=first
    local spy=unit(s,1,'Super:78');pl.hand[#pl.hand+1]=spy
    local stolen=unit(s,2,'Super:57');foe.discard[#foe.discard+1]=stolen
    local function play(copy)
      s.active=1;s.plays_left=1
      for i,u in ipairs(pl.hand) do if u==copy then return assert(B.play(s,1,i,1,1)) end end
      error('missing hand card')
    end
    local function occurrences()
      local n=0
      for _,p in ipairs(s.players) do
        for _,z in ipairs({p.deck,p.hand,p.discard,p.rows[1],p.rows[2]}) do
          for _,u in ipairs(z) do if u==gunner then n=n+1 end end
        end
      end
      return n
    end
    local defender=unit(s,2,'Fantasy:48',1)
    play(first)
    assert(defender.hp==defender.card.health-3)
    assert(pl.rows[2][1]==gunner and not U.contains(pile,gunner) and occurrences()==1)
    assert(gunner.owner==owner and gunner.controller==1 and U.contains(foe.hand,other))
    B.damage(s,2,gunner,99)
    assert(U.contains(s.players[owner].discard,gunner))
    play(spy);assert(U.contains(pl.hand,stolen) and not U.contains(pl.hand,gunner))
    local before=defender.hp
    s.chooser=function(_,_,_,options,ctx)
      if ctx.op=='deploy_attack' then for i,u in ipairs(options) do if u==defender then return i end end end
      return 1
    end
    play(stolen);assert(defender.hp==before-3)
    assert(pl.rows[2][1]==gunner and occurrences()==1 and stolen.owner==2 and s.round==1)
    B.resolve(s,1,first,A.get(first.card,'play'))
    assert(#pl.rows[2]==1 and occurrences()==1 and defender.hp==before-3)
    assert(B.pass(s,s.active))
    if s.round==1 then assert(B.pass(s,s.active)) end
    assert(s.round==2)
    local home=s.players[owner]
    assert(gunner.owner==owner and gunner.controller==owner and U.contains(home.discard,gunner))
  end end
end)
test("All six printed codes use the target’s current row even after movement",function()
  local s=M.new(cfg(),43).state
  local f=unit(s,2,'Fantasy:48',1);local b=unit(s,2,'Fantasy:48',2)
  local seen={}
  for _,faction in ipairs(L.factions) do
    for _,card in ipairs(L.cards[faction]) do
      if card.type=='Effect' then assert(not card.designation)
      else
        local code=assert(card.designation)
        assert(({FF=true,FB=true,FFB=true,BF=true,BB=true,BFB=true})[code])
        local row=B.placement_row(card)
        assert(row==(code:sub(1,1)=='F' and 1 or 2))
        local attacker=unit(s,1,card.id,row)
        for _,r in ipairs({row,3-row}) do
          if r~=row then
            table.remove(s.players[1].rows[row]);table.insert(s.players[1].rows[r],attacker)
          end
          local legal=B.attack_targets(s,1,attacker)
          assert(U.contains(legal,f)==(code:sub(2):find('F',1,true)~=nil))
          assert(U.contains(legal,b)==(code:sub(2):find('B',1,true)~=nil))
          local bonus={['Water:49']=2,['Water:18']=1,['Water:19']=3,['Water:41']=2,
            ['Fantasy:6']=r==2 and 2 or 1,['Fantasy:25']=2,['Fantasy:30']=1,['Fantasy:54']=4,
            ['Super:21']=2,['Super:30']=2}
          assert(attacker.card.designation==code and B.attack_power(s,attacker,b)==card.strength+(bonus[card.id] or 0)+
            (card.strike=='duelist' and b.card.strength>card.strength and 1 or 0))
        end
        table.remove(s.players[1].rows[3-row])
        if L.art[card.id] then seen[code]=true end
      end
    end
  end
  assert(U.count(seen)==6)
end)
test("Movement changes the target row but keeps printed permissions and wounds",function()
  local s=M.new(cfg(),55).state;s.active=1
  local scout=unit(s,1,'Fantasy:1',1);scout.hp=2
  local enemy=unit(s,2,'Water:47',1);local back=unit(s,2,'Water:17',2)
  local hp,power=scout.hp,B.strength(s,scout)
  B.resolve(s,2,enemy,A.get(enemy.card,'deploy')) -- Giant Squid moves the Squire to Back.
  assert(select(2,B.position(s,scout))==2 and scout.hp==hp and B.strength(s,scout)==power)
  assert(B.placement_row(scout.card)==1 and scout.card.designation=='FF')
  local targets=B.attack_targets(s,1,scout)
  assert(#targets==1 and targets[1]==enemy and not U.contains(targets,back))
  local warden=unit(s,1,'Super:61',2)
  local phantom=unit(s,1,'Super:66');s.players[1].hand={phantom}
  assert(not B.playable(s,1,1))
  local shift=unit(s,1,'Water:39')
  s.chooser=function(_,_,kind,options)
    for i,u in ipairs(options) do if kind=='unit' and u==warden then return i end end
    return 1
  end
  B.resolve(s,1,shift,A.get(shift.card,'play'))
  assert(B.playable(s,1,1) and B.play(s,1,1) and select(2,B.position(s,phantom))==1)
end)
test("A deployment attack modifier cannot hit an ineligible row",function()
  local s=M.new(cfg(),76).state;s.active=1
  local caster=unit(s,1,'Fantasy:25');local target=unit(s,2,'Water:61',2)
  s.players[1].hand={caster}
  assert(B.play(s,1,1,1,1))
  assert(target.hp==target.card.health and caster.hp==caster.card.health)
  assert(s.last_attack==nil and s.active==2)
end)
test("An empty exhausted seat waits while the opponent can play or draw",function()
  local s=M.new(cfg(),91).state;s.active=1
  local pl,foe=s.players[1],s.players[2]
  pl.hand={unit(s,1,'Super:15')};pl.deck={unit(s,1,'Fantasy:48')}
  foe.hand={};foe.deck={}
  assert(B.play(s,1,1,1,1))
  assert(s.round==1 and s.active==1 and #pl.hand==1 and #pl.deck==0)
  assert(B.play(s,1,1,1,2))
  assert(s.finished and s.round_history[1].scores[1]==15 and s.round_history[2].winner==0 and s.round_history[3].winner==0)
end)
test("Remaining current Health alone decides rounds and two wins decide the match",function()
  local function round(s,first,second)
    -- Seat 1 controls two wounded high-power units, including one borrowed copy.
    local a=unit(s,1,'Super:66',1);local b=unit(s,1,'Fantasy:48',2)
    a.owner=2;a.hp=1;b.hp=first-1;a.mod=10
    local c=unit(s,2,'Super:15',2);c.hp=second
    assert(B.score(s,1)==first and B.score(s,2)==second)
    local r=s.round
    assert(B.pass(s,s.active) and s.round==r and not s.finished)
    assert(B.pass(s,s.active))
    local result=s.round_history[r]
    assert(result.scores[1]==first and result.scores[2]==second)
    assert(result.winner==(first==second and 0 or first>second and 1 or 2))
  end
  local s=M.new(cfg(),18).state
  round(s,2,3);round(s,3,3);round(s,2,2)
  assert(s.finished and s.players[2].wins==1 and s.winner==0)
  s=M.new(cfg(),19).state
  round(s,2,3);round(s,3,2);round(s,2,3)
  assert(s.finished and s.winner==2 and s.players[2].wins==2)
  s=M.new(cfg(),20).state
  round(s,4,2);round(s,3,2)
  assert(s.finished and s.winner==1 and #s.round_history==2)
end)
test("Exhaustion scores wounds and healing in both rows",function()
  local s=M.new(cfg(),32).state;s.active=1
  local a=unit(s,1,'Fantasy:48',1);a.hp=1
  local b=unit(s,1,'Super:15',2);b.hp=1
  local c=unit(s,2,'Super:27',1);c.hp=4
  s.players[1].hand={unit(s,1,'Fantasy:33')};s.players[2].hand={}
  s.players[1].deck={};s.players[2].deck={}
  assert(B.play(s,1,1))
  local result=s.round_history[1]
  assert(result.scores[1]==5 and result.scores[2]==4 and result.winner==1)
end)
test("Printed reactions, extra plays, recovery, and once-per-round Shell use",function()
  local s=M.new(cfg(),24).state;s.active=1
  local urchin=unit(s,2,'Water:23',1)
  local striker=unit(s,1,'Super:15')
  s.players[1].hand={striker};s.players[2].hand={unit(s,2,'Water:1')}
  assert(B.play(s,1,1,1,1) and striker.hp==striker.card.health-1)
  assert((urchin.hp or 0)==math.max(0,urchin.card.health-striker.card.strength))
  s.active=1;s.plays_left=1
  s.players[1].hand={unit(s,1,'Super:70'),unit(s,1,'Super:70'),unit(s,1,'Super:15')}
  assert(B.play(s,1,1) and B.play(s,1,1) and s.plays_left==3)
  local crab=unit(s,1,'Water:17',1);local reunion=unit(s,1,'Water:58')
  assert(not B.damage(s,2,crab,2) and crab.hp==crab.card.health)
  for i=1,2 do
    B.damage(s,2,crab,99)
    B.resolve(s,1,reunion,A.get(reunion.card,'play'))
    local pl=s.players[1]
    assert(pl.hand[#pl.hand]==crab and B.play(s,1,#pl.hand,1,1))
    assert(B.damage(s,2,crab,1) and crab.hp==crab.card.health-1)
  end
end)
test("Only an explicitly required team blocks playing a team card",function()
  local s=M.new(cfg(),14).state;s.active=1
  s.players[1].hand={unit(s,1,'Super:58'),unit(s,1,'Fantasy:58')}
  local n=#s.players[1].deck
  assert(not B.playable(s,1,1) and B.play(s,1,2))
  assert(#s.players[1].deck==n-2 and s.plays_left==2 and s.active==1)
end)
test("Apex Bite and Pursuit modify one chosen Front attack and trigger Spines once",function()
  for _,wound in ipairs({0,1}) do
    local m=M.new(cfg(),49);m.controllers={"Human","Human"}
    local s=m.state;s.active=1
    local shark=unit(s,1,'Water:49');s.players[1].hand={shark}
    local urchin=unit(s,2,'Water:23',1);urchin.hp=urchin.hp-wound;urchin.guard=6
    local other=unit(s,2,'Water:23',1);local back=unit(s,2,'Fantasy:48',2)
    assert(m:act({type='play',index=1,row=1,pos=1}))
    local q=m.prompt
    assert(q.context.op=='deploy_attack' and #q.options==2 and q.options[1]==urchin)
    assert(B.attack_power(s,shark,urchin)==(wound==0 and 7 or 10))
    assert(m:choose(1) and not m.prompt and s.active==2)
    assert(urchin.hp==(wound==0 and 2 or nil) and shark.hp==shark.card.health-1)
    assert(other.hp==other.card.health and back.hp==back.card.health)
  end
end)
test("Copycat checks another unit's printed Strength before the attack",function()
  for _,ally in ipairs({'none','Super:32','Super:75'}) do
    local s=M.new(cfg(),51).state;s.active=1
    if ally~='none' then
      local u=unit(s,1,ally,2);u.mod=ally=='Super:75' and 1 or -1
    end
    local cat=unit(s,1,'Super:51');s.players[1].hand={cat}
    local target=unit(s,2,'Fantasy:48',1)
    local power=ally=='Super:32' and 5 or 3
    assert(B.play(s,1,1,1,1) and B.strength(s,cat)==power and target.hp==target.card.health-power)
    assert(B.pass(s,2) and B.pass(s,1) and cat.mod==0 and U.contains(s.players[1].discard,cat))
  end
end)
test("Dragon Magic at four and reversed Bridge segments give the paid unit one Guard",function()
  for _,length in ipairs({3,4,5}) do
    local s=M.new(cfg(),52).state;s.active=1
    local first
    if length==5 then
      first=unit(s,1,'Fantasy:65',1);unit(s,1,'Fantasy:55',1)
    elseif length==4 then first=unit(s,1,'Fantasy:4',2) end
    local witch=unit(s,1,'Fantasy:8',2);first=first or witch
    unit(s,1,'Fantasy:13',2)
    local dragon=unit(s,1,'Fantasy:52');s.players[1].hand={dragon}
    local draw=#s.players[1].deck
    assert(B.play(s,1,1,2,#s.players[1].rows[2]+1))
    assert(Chains.qualify(s.players[1],dragon,3,false).length==length and dragon.guard==1)
    assert(s.stats.chains_completed[1]==1 and s.stats.chain_completions_by_length[length]==1)
    local earns=length>=4
    assert((dragon.activated.chain~=nil)==earns and #s.players[1].deck==draw-(earns and 1 or 0))
    B.check_chains(s)
    assert(s.stats.chain_activated[1]==(earns and 1 or 0) and dragon.guard==1)
    assert(first.guard==(earns and 2 or 0) and first.mod==first.guard)
  end
end)
test("All Wet applies to arrivals and respects immunities, controller changes and round expiry",function()
  local s=M.new(cfg(),67).state;s.active=1
  local mine=unit(s,1,'Fantasy:48',1)
  local whale=unit(s,2,'Water:61',1);local turtle=unit(s,2,'Water:27',2)
  local victim=unit(s,2,'Fantasy:25',2)
  s.players[1].hand={unit(s,1,'Water:67'),unit(s,1,'Water:67')}
  local shrimp=unit(s,2,'Water:19');s.players[2].hand={shrimp}
  assert(B.play(s,1,1) and B.strength(s,victim)==victim.card.strength-2)
  assert(B.play(s,2,1,1,2) and mine.hp==mine.card.health-4)
  assert(B.play(s,1,1) and B.strength(s,shrimp)==0 and B.strength(s,victim)==0)
  assert(B.strength(s,whale)==whale.card.strength and B.strength(s,turtle)==turtle.card.strength)
  local trader=unit(s,1,'Super:76')
  s.chooser=function(_,_,_,opts,ctx)
    if ctx.op=='take' then for i,u in ipairs(opts) do if u==shrimp then return i end end end
    return 1
  end
  B.resolve(s,1,trader,A.get(trader.card,'deploy'))
  assert(shrimp.controller==1 and B.strength(s,shrimp)==3 and mine.controller==2 and B.strength(s,mine)==1)
  assert(B.pass(s,2) and B.pass(s,1) and not s.players[2].flood)
  assert(U.contains(s.players[2].discard,shrimp) and U.contains(s.players[1].discard,mine))
end)
test("Starfish grows on controller turns and scores excess HP while ordinary healing stays capped",function()
  local s=M.new(cfg(),22).state;s.active=2
  local star=unit(s,1,'Water:22',2);local troll=unit(s,1,'Fantasy:15',1);troll.hp=5
  s.players[1].hand={unit(s,1,'Fantasy:13'),unit(s,1,'Super:15')}
  assert(B.pass(s,2) and star.hp==5 and troll.hp==6)
  assert(B.play(s,1,1,2,2) and s.active==1 and star.hp==6 and troll.hp==6)
  local score=B.score(s,1)
  assert(score==star.hp+troll.hp+s.players[1].rows[2][2].hp)
  assert(B.pass(s,1) and s.round_history[1].scores[1]==score and not star.hp)
end)
test("Round cleanup keeps card identity, pile order and match flags",function()
  local s=M.new(cfg(),81).state;s.active=2
  local pl=s.players[1];local held=pl.hand[1];local front=unit(s,1,'Fantasy:65',1)
  local back=unit(s,1,'Water:17',2);back.shell_used=true
  local stolen=unit(s,2,'Super:32',1);stolen.owner=1
  local old=unit(s,1,'Water:1');old.hp=nil;pl.discard={old}
  s.school_used[1]=true
  local deck={};for i,u in ipairs(pl.deck) do deck[i]=u end
  assert(B.pass(s,2) and B.pass(s,1) and s.round==2)
  assert(pl.hand[1]==held and pl.hand[#pl.hand-2]==deck[#deck] and pl.hand[#pl.hand]==deck[#deck-2])
  for i,u in ipairs(pl.deck) do assert(u==deck[i]) end
  assert(pl.discard[1]==old and pl.discard[2]==front and pl.discard[3]==back and pl.discard[4]==stolen)
  assert(stolen.controller==1 and not back.shell_used and s.school_used[1])
end)
test("180 seeded full matches conserve selected copies across every action",function()
  local rng=U.rng(2026);local played={}
  for i=1,180 do
    local c=cfg()
    for p=1,2 do
      local f=L.factions[(i+p*math.floor(i/3))%#L.factions+1]
      c.factions[p]=f;c.decks[p]={};local pool={}
      for _,card in ipairs(L.collection(f)) do pool[#pool+1]=card.id end
      while #c.decks[p]<20 do L.edit(c,p,pool[rng:random(#pool)],1) end
    end
    local m=M.new(c,5000+i);local turns=0
    while not m.state.finished do
      assert(m:act({type='ai'}));integrity(m,c);turns=turns+1;assert(turns<350)
      if m.state.last_played then played[m.state.last_played.card.id]=true end
    end
    assert(#m.state.round_history>=2 and #m.state.round_history<=3)
  end
  print("      distinct cards played across 180 matches: "..U.count(played).." of 166")
  assert(U.count(played)>150)
end)
for _,v in ipairs(cases) do v[2]();print("PASS  "..v[1]) end
print(#cases.." tabletop tests passed.")
