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
    assert(m:act({type='play',index=index,row=row,pos=1}))
    local drew=row==2 and before>0
    assert(#pl.hand==(drew and 5 or 4) and #pl.deck==before-(drew and 1 or 0))
    if row==2 then
      local receipt=assert(m.draws[1])
      assert(receipt.seat==1 and receipt.source=='Halfling Courier' and receipt.before==before and receipt.remaining==#pl.deck)
      if drew then assert(pl.hand[#pl.hand]==top and receipt.cards[1]==top)
      else assert(#receipt.cards==0 and receipt.reason=='draw deck empty') end
      local record=table.concat(m.state.log,'\n')
      assert(record:find('Halfling Courier drew',1,true) and (drew or record:find('draw deck empty',1,true)))
    else assert(#m.draws==1 and m.draws[1].seat==2 and m.draws[1].source=="Turn draw") end
    integrity(m,c)
  end
end)
test("Printed-rank Bridge after insertion, once per deployment, chain attack bonus",function()
  local s=M.new(cfg(),77).state;s.active=2
  unit(s,2,'Water:2',1);local bridge=unit(s,2,'Water:21')
  local rank3=unit(s,2,'Water:28',2);rank3.mod=3
  s.players[2].hand={bridge,unit(s,2,'Water:1')}
  assert(not B.play(s,2,1,1,4));assert(#s.players[2].hand==2)
  assert(B.play(s,2,1,1,2));assert(Chains.qualify(s.players[2],bridge,3,true))
  assert(B.score(s,2)==3 and B.attack_power(s,bridge,rank3)==3+B.support(s,bridge) and s.stats.chain_activated[2]==1)
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
    s.players[1].hand={unit(s,1,id),unit(s,1,f..':7'),unit(s,1,f..':8')}
    return s
  end
  local allowed={}
  for _,f in ipairs(L.factions) do for _,card in ipairs(L.collection(f)) do
    local id,n=card.id,card.number
    local trig=A[f] and A[f][n] or {}
    local s=setup(f,n,id);local row,pos=card.type=='Unit' and 2 or nil,card.type=='Unit' and 5 or nil
    if id=='Fantasy:48' then row,pos=1,1 end
    if card.agent then pos=#s.players[2].rows[2]+1 end
    if not B.playable(s,1,1) then assert(allowed[id]=='unplayable',id..' '..card.name..' cannot be played')
    else
      assert(B.play(s,1,1,row,pos),id..' rejected')
      if trig.deploy or trig.play then
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
  assert(m:act({type='play',index=1,row=1,pos=1}))
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
  unit(s,1,'Water:2',2) -- light support keeps the deployment at full Health before Old Harpoon
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
  assert(B.pass(s,q) and s.round==2 and s.active==q)
  assert(#me.hand==5 and #foe.hand==5 and #foe.deck==15)
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
    unit(s,2,'Super:15',1)
    if scenario=='all' then pl.deck={hero};pl.hand[2]=heroine;pl.discard={gunner}
    elseif scenario=='partial' then pl.discard={heroine,gunner}
    elseif scenario=='prefer hand' then pl.hand[2]=gunner;pl.discard={unit(s,1,'Super:32')}
    else pl.discard={hero,heroine};unit(s,2,'Super:32',2) end
    local plays=s.stats.played[1]
    assert(B.play(s,1,1))
    assert(s.stats.played[1]==plays+1 and #Chains.find(pl)==0)
    assert(pl.discard[#pl.discard].card.id=='Super:57')
    local row=pl.rows[1]
    if scenario=='all' then assert(#row==3 and row[1]==hero and row[2]==heroine and row[3]==gunner)
    elseif scenario=='empty' then assert(#row==0 and #pl.discard==3)
    else assert(#row==1 and row[1]==gunner and #pl.discard==2) end
    if B.position(s,gunner) then
      B.damage(s,2,gunner,99)
      assert(not B.position(s,gunner) and pl.discard[#pl.discard]==gunner)
    end
  end
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
  unit(s,1,'Super:3',2) -- light support for Dan
  for i=1,2 do unit(s,2,'Fantasy:48',1).guard=20 end -- cover both measured Back positions
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
  unit(s,2,'Fantasy:1',1) -- cover the second Back unit
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
  assert(B.play(s,1,1,1,1));assert(pl.hand[#pl.hand]==brave and #pl.deck==2,"Scared first: Distress Call fetches Brave Sidekick")
  assert(m.draws[#m.draws].cards[1]==brave,"the fetch is reported like a draw")
  turn(s);assert(B.play(s,1,#pl.hand,1,2))
  assert(B.strength(s,scared)==5 and victim.hp==vhp-3 and brave.guard==0,"Brave second: +3 and 3 damage")
  m,s=fresh();pl=s.players[1];brave,scared=unit(s,1,'Super:74'),unit(s,1,'Super:75')
  pl.hand={brave,scared,unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,1,1));assert(brave.guard==3,"Brave first: guards itself")
  turn(s);assert(B.play(s,1,1,1,2))
  assert(brave.negate_damage and scared.negate_damage and #pl.deck==1 and B.strength(s,scared)==2,"Scared second: both turn ghostly")
  B.damage(s,2,scared,9);assert(B.position(s,scared) and not scared.negate_damage,"the next opposing damage effect is ignored once")
  m,s=fresh();pl=s.players[1];pl.hand={unit(s,1,'Super:75'),unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,1,1));assert(#pl.deck==0 and #pl.hand==2,"no Brave Sidekick in the deck: draw 1 instead")

  m,s=fresh();pl,foe=s.players[1],s.players[2]
  brave,scared=unit(s,1,'Super:74'),unit(s,1,'Super:75',1)
  victim=unit(s,2,'Fantasy:48',1);vhp=victim.hp
  B.damage(s,2,scared,99)
  pl.hand={brave,unit(s,1,'Super:12')}
  assert(B.play(s,1,1,1,1))
  assert(victim.hp==vhp-2 and not brave.hp,"a dead Scared Sidekick does not trigger the pair")
  m,s=fresh();pl=s.players[1]
  brave,scared=unit(s,2,'Super:74',1),unit(s,1,'Super:75')
  pl.hand={scared,unit(s,1,'Super:12')};pl.deck={unit(s,1,'Super:2')}
  assert(B.play(s,1,1,1,1))
  assert(not brave.negate_damage and not scared.negate_damage,"an opposing Sidekick does not count as your partner")

  -- Spy: deployed on the opposing battlefield, becomes the opponent's card.
  m,s=fresh();pl,foe=s.players[1],s.players[2]
  local spy=unit(s,1,'Super:78');pl.hand={spy,unit(s,1,'Super:12'),unit(s,1,'Super:12')}
  local loot=unit(s,2,'Fantasy:40');foe.discard={unit(s,2,'Fantasy:1'),loot};foe.hand={unit(s,2,'Fantasy:1'),unit(s,2,'Fantasy:39')}
  unit(s,2,'Fantasy:5',1)
  assert(not B.play(s,1,1,1,3),"positions are counted on the opposing row");assert(B.play(s,1,1,1,2))
  local ss,sr,si=B.position(s,spy);assert(ss==2 and sr==1 and si==2 and spy.owner==2 and spy.controller==2)
  assert(B.score(s,1)==0 and B.score(s,2)==2 and B.strength(s,spy)==spy.card.strength,"gifted Strength does not award a defeat")
  assert(pl.hand[#pl.hand]==loot and loot.owner==2 and loot.controller==1,"Vault Heist takes the chosen discard")
  B.damage(s,1,spy,9);assert(foe.discard[#foe.discard]==spy,"a Double Agent goes to its new owner's discard pile")
  -- Even a Fantasy deck can pull it back: Monochrome counts as every faction for discard abilities.
  s.active=2;s.plays_left=1;assert(B.playable(s,2,2));assert(B.play(s,2,2))
  assert(foe.hand[#foe.hand]==spy,"Fantasy recovery returns the Monochrome Unit")
  s.active=2;s.plays_left=1;assert(B.play(s,2,#foe.hand,2,1))
  ss,sr=B.position(s,spy);assert(ss==1 and sr==2 and spy.owner==1,"played back, it lands on the first player's battlefield")
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
  assert(B.play(s,1,1,2,1))
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
  assert(brave.hp==brave.card.health-math.floor(B.strength(s,guard)/2))
  assert(m:choose(3) and not m.prompt and back.hp==back.card.health-3 and s.active==2)
  assert(not m:act({type='attack',index=1,row=1,pos=1}))
end)
test("Rune Apprentice and High Elf Spellblade earn chain strikes during deployment",function()
  for _,id in ipairs({'Fantasy:16','Fantasy:42'}) do
    local m=M.new(cfg(),71);m.controllers={"Human","Human"}
    local s=m.state;s.active=1
    unit(s,1,'Fantasy:1',1)
    if id=='Fantasy:16' then unit(s,1,'Fantasy:9',1)
    else unit(s,1,'Fantasy:9',1);unit(s,1,'Fantasy:12',1) end
    local source=unit(s,1,id);s.players[1].hand={source}
    local wall=unit(s,2,'Fantasy:48',1);wall.guard=30
    local back=unit(s,2,'Fantasy:48',2)
    if id=='Fantasy:42' then back.guard=5 else wall.mod=12 end
    local pos=id=='Fantasy:16' and 3 or 4
    assert(m:act({type='play',index=1,row=1,pos=pos}))
    assert(m.prompt and m.prompt.context.op=='damage' and m.prompt.options[2]==back)
    if id=='Fantasy:16' then assert(not source.hp,'a lethal counter cannot erase the earned chain') end
    assert(m:choose(2) and back.hp==back.card.health-2 and s.active==2)
  end
end)
test("A wipe allows reinforcements and conceding redeals each selected deck",function()
  local c=cfg();local s=M.new(c,99).state;s.active=1
  local foe=unit(s,2,'Fantasy:12',1)
  local big=unit(s,1,'Fantasy:48');s.players[1].hand={big}
  local light=unit(s,1,'Fantasy:1',2)
  assert(B.deployment_health(s,1,big.card)==big.card.health)
  B.damage(s,2,light,99)
  assert(s.round==1 and B.playable(s,1,1))
  foe.hp=2
  assert(B.play(s,1,1,1,1) and not foe.hp and s.round==1 and s.active==2)
  assert(B.pass(s,2) and s.round_history[1].winner==1 and s.round_history[1].reason=='concession')
  assert(#s.players[1].hand==5 and #s.players[2].hand==5 and B.score(s,1)==0 and s.round==2)
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
    local blocked=unit(s,1,'Super:32');blocked.recovered=true;pl.discard[#pl.discard+1]=blocked
    local target=pl[zone][2]
    m.controllers[1]='Human';s.active=1;s.plays_left=1
    assert(m:act({type='play',index=1,row=2,pos=1}))
    assert(m.prompt.kind=='zone' and m.prompt.actor==1)
    assert(m:choose(zone=='discard' and 1 or 2))
    assert(m.prompt.context.op==(zone=='discard' and 'grave_recover' or 'grave_search'))
    assert(#m.prompt.options==3 and not View.prompt(m.prompt,2).options)
    local pick
    for i,c in ipairs(m.prompt.options) do if c==target then pick=i end end
    assert(m:choose(assert(pick)) and pl.hand[#pl.hand]==target and s.active==2)
    assert(not U.contains(pl[zone],target) and target.controller==1 and target.owner==1)
    B.damage(s,2,acolyte,99)
    assert(U.contains(foe.discard,acolyte) and acolyte.owner==2)
    assert(B.pass(s,2) and s.round==2)
    assert(U.contains(foe.deck,acolyte) or U.contains(foe.hand,acolyte))
    assert(spy.owner==1 and spy.controller==1)
  end
end)
test("Every Showdown retrieves one physical Gunner, including a repeat on a stolen Showdown",function()
  for side=1,2 do for _,zone in ipairs({'deck','hand','discard'}) do
    local s=M.new(cfg(),12).state;s.active=1
    local pl,foe=s.players[1],s.players[2]
    for _,p in ipairs(s.players) do p.deck={};p.hand={};p.discard={} end
    local owner=zone=='discard' and side or 2
    local gunner=unit(s,owner,'Super:32');gunner.home=owner;gunner.recovered=true
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
    play(first)
    assert(pl.rows[1][1]==gunner and not U.contains(pile,gunner) and occurrences()==1)
    assert(gunner.owner==owner and gunner.controller==1 and U.contains(foe.hand,other))
    B.damage(s,2,gunner,99)
    assert(U.contains(s.players[owner].discard,gunner) and gunner.recovered)
    play(spy);assert(U.contains(pl.hand,stolen) and not U.contains(pl.hand,gunner))
    play(stolen);assert(pl.rows[1][1]==gunner and occurrences()==1 and stolen.owner==2 and s.round==1)
    B.resolve(s,1,first,A.get(first.card,'play'))
    assert(#pl.rows[1]==1 and occurrences()==1)
    assert(B.pass(s,s.active) and s.round==2)
    local home=s.players[owner]
    assert(gunner.owner==owner and gunner.controller==owner and (U.contains(home.hand,gunner) or U.contains(home.deck,gunner)))
  end end
end)
test("Basic attacks use current column cover and halve only Back Strength before bonuses",function()
  local s=M.new(cfg(),43).state
  local f=unit(s,2,'Fantasy:48',1)
  local b1=unit(s,2,'Fantasy:48',2);local b2=unit(s,2,'Fantasy:48',2)
  local function exposed(...)
    local options=B.attack_targets(s,1);local wanted={...}
    assert(#options==#wanted)
    for i,c in ipairs(wanted) do assert(options[i]==c) end
  end
  exposed(f,b2)
  local attacker=unit(s,1,'Super:73',1)
  assert(B.attack_power(s,attacker,b2)==6)
  table.remove(s.players[1].rows[1]);table.insert(s.players[1].rows[2],attacker)
  assert(B.attack_power(s,attacker,b2)==3)
  attacker.mod=-1;unit(s,1,'Super:61',2)
  assert(B.attack_power(s,attacker,b2)==4,'ceil(5/2) then +1 support')
  B.damage(s,1,b1,99);exposed(f)
  B.damage(s,1,f,99);exposed(b2)
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
