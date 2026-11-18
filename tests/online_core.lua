-- From the source root: lua tests/online_core.lua
-- The online rules server, exercised without a network: JSON, snapshots, complete solo and
-- two-player matches through the same request/response path the Edge Function uses.
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local json=require('online.json')
local Snap=require('online.snapshot')
local View=require('online.view')
local Server=require('online.server')
local Mirror=require('online.mirror')
local Host=require('tests.devhost')
local L=require('tabletop.library')
local M=require('tabletop.match')
local B=require('battle')
local AI=require('ai')
local C=require('data.cards')
local U=require('util')
local cases={}
local function test(label,fn) cases[#cases+1]={label,fn} end
local function same(a,b,path)
  path=path or 'value'
  if type(a)~=type(b) then error(path..': '..type(a)..' vs '..type(b),0) end
  if type(a)~='table' then if a~=b then error(path..': '..tostring(a)..' vs '..tostring(b),0) end;return true end
  for k,v in pairs(a) do same(v,b[k],path..'.'..tostring(k)) end
  for k in pairs(b) do if a[k]==nil then error(path..'.'..tostring(k)..': missing on the left',0) end end
  return true
end
local function deck(faction)
  local c={factions={faction,faction},decks={{},{}}};L.starter(c,1,20);return c.decks[1]
end
-- A player that knows only what its view shows, and picks random legal inputs.
local function decide(mirror,seat,rng)
  local s,q=mirror.state,mirror.prompt
  if q then
    if q.waiting or q.actor~=seat then return nil end
    if q.context.optional then return {type='choose',index=rng:random(#q.options+1)-1} end
    return {type='choose',index=rng:random(#q.options)}
  end
  if s.finished or s.active~=seat then return nil end
  if B.can_school(s,seat) then return {type='school'} end
  local legal={}
  for i=1,#s.players[seat].hand do if B.playable(s,seat,i) then legal[#legal+1]=i end end
  if s.extra_turn and rng:random(4)==1 then return {type='end'} end
  if #legal==0 or rng:random(14)==1 then return {type='pass'} end
  local i=legal[rng:random(#legal)];local card=s.players[seat].hand[i].card
  if card.type=='Unit' and not card.replaces then
    local rows=s.players[B.deploy_side(seat,card)].rows;local row=rng:random(2)
    return {type='play',index=i,row=row,pos=rng:random(#rows[row]+1)}
  end
  return {type='play',index=i}
end
local function no_fractions(lines)
  for _,line in ipairs(lines) do assert(not line:find('%d%.0[^%d]') and not line:find('%d%.0$'),'number printed as a fraction: '..line) end
end

test("JSON round trips, escapes, arrays and objects",function()
  local value={text='Draw deck 10 → 9 "quoted" \\ back\nline\ttab',n=-12,f=1.5,yes=true,no=false,list={1,2,{a='b'}},empty={},
    map=json.object({}),nested={deck={'Water:1','Super:76'}}}
  local text=json.encode(value);local back=assert(json.decode(text))
  same(value,back)
  assert(text:find('"empty":[]',1,true) and text:find('"map":{}',1,true))
  assert(json.encode({school={false,false}})=='{"school":[false,false]}')
  same(json.decode('{"a":[1,null,3],"b":"\\u00e9\\ud83d\\ude00","c":-0.5e1}'),{a={1,nil,3},b='é😀',c=-5})
  for _,bad in ipairs({'','{','[1,]','{"a"}','{"a":1,}','"open','tru','[1] x','{a:1}'}) do
    local v,why=json.decode(bad);assert(v==nil and why,'accepted '..bad)
  end
  assert(json.encode(3)=='3' and json.encode(2^31)=='2147483648' and not pcall(json.encode,0/0))
end)

test("A snapshot taken after every action continues exactly like an uninterrupted match",function()
  for i=1,24 do
    local f1,f2=L.factions[i%3+1],L.factions[(i+1)%3+1]
    local d1,d2=deck(f1),deck(f2)
    local function new() return B.new(d1,d2,{seed=4100+i,player_faction=f1,ai_faction=f2}) end
    local plain,stored=new(),new();local turns=0
    while not plain.finished do
      assert(AI.step(plain,plain.active,i%4==0 and 'easy' or nil))
      local text=Snap.dump(stored,C.by_id,{log=true})
      assert(not text:find('function',1,true))
      local log=stored.log
      stored=Snap.load(text,C.by_id);local rng=U.rng(1);rng.seed=stored.rng.seed;stored.rng=rng;stored.log=log
      assert(AI.step(stored,stored.active,i%4==0 and 'easy' or nil))
      turns=turns+1;assert(turns<300)
    end
    assert(stored.finished and #plain.log==#stored.log)
    for n,line in ipairs(plain.log) do assert(line==stored.log[n],line..' / '..stored.log[n]) end
    same(B.report(plain),B.report(stored));no_fractions(plain.log)
    -- Card instances stay shared between zones after a restore.
    local seen={}
    for p=1,2 do local pl=stored.players[p]
      for _,zone in ipairs({pl.hand,pl.deck,pl.discard,pl.rows[1],pl.rows[2]}) do
        for _,u in ipairs(zone) do assert(not seen[u] and u.card==C.by_id[u.card.id]);seen[u]=true end
      end
    end
    assert(stored.last_played==nil or seen[stored.last_played])
  end
end)

-- What a seat is told must not depend on anything hidden from it.
local function scrambled(host,m,seat)
  local s=Server.restore(m.snapshot);local foe=s.players[3-seat]
  local rng=U.rng(m.seq+9)
  for i=1,math.min(#foe.hand,#foe.deck) do
    local j=rng:random(#foe.deck);foe.hand[i],foe.deck[j]=foe.deck[j],foe.hand[i]
  end
  rng:shuffle(foe.deck);rng:shuffle(foe.hand);rng:shuffle(s.players[seat].deck);s.rng.seed=12345
  return s
end
local function leaks(view,seat)
  local foe=view.players[3-seat]
  assert(foe.cards==nil and type(foe.hand)=='number' and type(foe.deck)=='number' and type(view.players[seat].deck)=='number')
  for _,d in ipairs(view.draws or {}) do assert(d.seat==seat or d.cards==nil,'opposing draws are named') end
  local text=json.encode(view)
  assert(not text:find('"seed"',1,true) and not text:find('"rng"',1,true) and not text:find('"decks"',1,true))
end

test("Single player online: complete matches against the computer, three computer moves per request",function()
  local finished,requests=0,0
  for i=1,18 do
    local host=Host.new({seed=300+i});local rng=U.rng(900+i)
    local f1,f2=L.factions[i%3+1],L.factions[(i+2)%3+1]
    local body={op='create',mode='solo',rules=host.rules,player={faction=f1,deck=deck(f1)},
      ai={faction=f2,deck=i%2==0 and deck(f2) or nil,difficulty=i%5==0 and 'easy' or 'normal'}}
    local r=host:game('u1',body);assert(r.ok and r.seat==1 and r.view,r.message)
    local m=host.matches[r.match];assert(m.config.difficulty==(i%5==0 and 'easy' or 'normal'))
    assert(#m.config.decks[2]==(i%2==0 and 20 or 30),'the computer brings its starter when no deck is sent')
    local mirror=Mirror.new();mirror:apply(r.view);mirror:append_log(r.log)
    local more,guard=r.more,0
    while m.status=='active' do
      guard=guard+1;assert(guard<600)
      local action=more and {type='advance'} or decide(mirror,1,rng)
      assert(action,'neither the player nor the computer can move')
      local seq=m.seq
      r=host:game('u1',{op='act',match=m.id,seq=seq,action=action,id='a'..guard});requests=requests+1
      if not r.ok then error(r.error..': '..tostring(r.message)..' for '..json.encode(action)) end
      assert(#r.frames>=1 and #r.frames<=Server.ai_steps+1 and r.seq==seq+1 and r.log_from==#mirror.log)
      for _,frame in ipairs(r.frames) do
        leaks(frame.view,1);assert(frame.view.seq==r.seq)
        mirror:apply(frame.view);mirror:append_log(frame.log)
      end
      more=r.more
      assert(#mirror.log==#m.log);same(m.views['1'],r.frames[#r.frames].view)
      -- With nothing pending the stored snapshot is the position the player sees.
      if not m.pending then
        local s=Server.restore(m.snapshot)
        for p=1,2 do assert(B.score(s,p)==B.score(mirror.state,p) and #s.players[p].hand==#mirror.state.players[p].hand) end
        assert(more==((not s.finished and s.active==2) or nil))
        same(View.build(s,1,{seq=m.seq,mode='solo',controllers={'Human','AI'}}),
          View.build(scrambled(host,m,1),1,{seq=m.seq,mode='solo',controllers={'Human','AI'}}))
      else assert(mirror.prompt and mirror.prompt.actor==1 and not more) end
    end
    assert(m.status=='finished' and mirror.state.finished and mirror.state.winner~=nil)
    assert(#mirror.state.round_history>=2 and #mirror.state.round_history<=3)
    no_fractions(m.log);finished=finished+1
    local late=host:game('u1',{op='act',match=m.id,seq=m.seq,action={type='pass'}})
    assert(not late.ok and late.error=='not_active')
  end
  print("      "..finished.." solo matches, "..requests.." requests")
end)

test("Two players online: complete matches, hidden hands, and the same result as the local engine",function()
  local prompts,for_other,total=0,0,0
  -- Smaller opening hands need more seeds to cover opponent-owned ability choices.
  for i=1,120 do
    local host=Host.new({seed=500+i});local rng=U.rng(1700+i)
    local f={L.factions[i%3+1],L.factions[(i+i%2+1)%3+1]}
    local decks={deck(f[1]),deck(f[2])}
    local seeds={};local core=host.core
    host.core=function(self,req,snap) seeds[#seeds+1]=req.seed;return core(self,req,snap) end
    local r=host:game('ann',{op='create',mode='duel',rules=host.rules,player={faction=f[1],deck=decks[1]}})
    assert(r.ok and r.status=='waiting' and #r.code==6 and not r.view)
    local m=host.matches[r.match]
    local waiting=host:state('ann',{p_match=m.id,p_seq=-1,p_log=0})
    assert(waiting.status=='waiting' and waiting.code==r.code and waiting.view==nil)
    local j=host:game('bob',{op='join',code=r.code:lower(),rules=host.rules,player={faction=f[2],deck=decks[2]}})
    assert(j.ok and j.seat==2 and j.match==m.id and m.status=='active',j.message)
    local mirrors={Mirror.new(),Mirror.new()};local users={'ann','bob'}
    mirrors[2]:apply(j.view);mirrors[2]:append_log(j.log)
    local function poll(seat)
      local st=host:state(users[seat],{p_match=m.id,p_seq=mirrors[seat].state and mirrors[seat].seq or -1,p_log=#mirrors[seat].log})
      assert(st.seat==seat and st.seq==m.seq)
      if st.view then
        leaks(st.view,seat);mirrors[seat]:apply(st.view);mirrors[seat].seq=st.seq
        assert(st.log_from==#mirrors[seat].log);mirrors[seat]:append_log(st.log)
      end
    end
    mirrors[2].seq=j.seq;poll(1)
    -- The same inputs go to a local match (tabletop.match), the pre-online way to run the rules.
    local c=L.new();L.set_mode(c,2);c.factions,c.decks=f,decks
    local localMatch=M.new(c,seeds[#seeds]);local guard=0
    while m.status=='active' do
      guard=guard+1;assert(guard<900)
      local seat,action
      for p=1,2 do local a=decide(mirrors[p],p,rng);if a then assert(not action,'both seats believe they can act');seat,action=p,a end end
      assert(action,'nobody can act')
      if action.type=='choose' then
        prompts=prompts+1;if mirrors[seat].state.active~=seat then for_other=for_other+1 end
        assert(localMatch.prompt and localMatch.prompt.actor==seat and #localMatch.prompt.options==#mirrors[seat].prompt.options)
        assert(localMatch:choose(action.index))
      else assert(not localMatch.prompt and localMatch.state.active==seat);assert(localMatch:act(action)) end
      local before=m.seq
      r=host:game(users[seat],{op='act',match=m.id,seq=before,action=action,id='x'..guard})
      if not r.ok then error(r.error..': '..tostring(r.message)..' for '..json.encode(action)) end
      assert(#r.frames==1 and r.seq==before+1 and not r.more)
      leaks(r.frames[1].view,seat);mirrors[seat]:apply(r.frames[1].view);mirrors[seat].seq=r.seq;mirrors[seat]:append_log(r.frames[1].log)
      poll(3-seat);total=total+1
      -- Both players and the local match agree on everything public.
      local a,b,ref=mirrors[1].state,mirrors[2].state,localMatch.state
      for p=1,2 do
        assert(B.score(a,p)==B.score(ref,p) and B.score(b,p)==B.score(ref,p))
        assert(#a.players[p].hand==#ref.players[p].hand and #b.players[p].deck==#ref.players[p].deck)
        for row=1,2 do for k,u in ipairs(ref.players[p].rows[row]) do
          local x,y=a.players[p].rows[row][k],b.players[p].rows[row][k]
          assert(x.uid==u.uid and y.uid==u.uid and x.hp==u.hp and y.mod==u.mod and x.controller==p and y.owner==u.owner)
        end end
        assert(#a.players[p].rows[1]==#ref.players[p].rows[1] and #b.players[p].rows[2]==#ref.players[p].rows[2])
        -- Each player sees its own hand exactly, and only the size of the other one.
        for k,u in ipairs(ref.players[p].hand) do assert(mirrors[p].state.players[p].hand[k].uid==u.uid) end
        assert(mirrors[3-p].state.players[p].hand[1]==nil or mirrors[3-p].state.players[p].hand[1].hidden)
      end
      assert(a.active==ref.active and b.round==ref.round and #mirrors[1].log==#ref.log and #mirrors[2].log==#m.log)
      if not m.pending then
        for p=1,2 do
          local extra={seq=m.seq,mode='duel',controllers={'Human','Human'}}
          same(View.build(Server.restore(m.snapshot),p,extra),View.build(scrambled(host,m,p),p,extra))
        end
      end
    end
    assert(m.status=='finished' and localMatch.state.finished)
    local report=B.report(localMatch.state)
    for p=1,2 do
      local s=mirrors[p].state
      assert(s.finished and s.winner==report.winner and s.players[1].wins==report.wins[1] and s.players[2].wins==report.wins[2])
      same(s.round_history,localMatch.state.round_history)
    end
    for n,line in ipairs(localMatch.state.log) do
      local expected=line:gsub('Seat (%d)','Player %1')
      assert(m.log[n]==expected,m.log[n]..' / '..expected)
    end
    no_fractions(m.log)
  end
  print("      "..total.." actions, "..prompts.." answered questions ("..for_other.." during the other player's turn)")
  assert(prompts>200 and for_other>0)
end)

test("Refused requests: wrong turn, stale or repeated moves, strangers, bad rooms and decks",function()
  local host=Host.new({seed=5})
  local good={faction='Water',deck=deck('Water')}
  local function create(body) body.op='create';body.rules=body.rules or host.rules;return host:game('ann',body) end
  local r=create({mode='duel',rules='older'});assert(not r.ok and r.error=='rules_mismatch' and r.rules==host.rules)
  assert(create({mode='ranked',player=good}).error=='bad_request')
  for _,bad in ipairs({{faction='Water',deck={}},{faction='Carnival',deck=good.deck},{faction='Water',deck=deck('Fantasy')},
      {faction='Water',deck={'Water:1',7}},{faction='Water',deck='all'},{faction='Fantasy',deck={'Fantasy:34','Fantasy:1'}},
      {faction='Water',deck={[1]='Water:1',[3]='Water:2'}},{deck=good.deck}}) do
    r=create({mode='duel',player=bad});assert(not r.ok and r.error=='invalid_deck',json.encode(bad))
  end
  for _,n in ipairs({19,31}) do
    local selected={}
    for i=1,n do selected[i]=L.collection('Water')[i].id end
    assert(create({mode='duel',player={faction='Water',deck=selected}}).error=='invalid_deck')
  end
  local tooMany={faction='Water',deck=deck('Water')};for _=1,4 do table.insert(tooMany.deck,'Water:1') end
  assert(create({mode='duel',player=tooMany}).error=='invalid_deck')
  assert(create({mode='solo',player=good,ai={faction='Nope'}}).error=='invalid_deck')
  assert(create({mode='solo',player=good,ai={faction='Water',deck={'Water:1'}}}).error=='invalid_deck')
  r=create({mode='duel',player=good});assert(r.ok);local m=host.matches[r.match]
  assert(host:game('bob',{op='join',code='ZZZZZZ',rules=host.rules,player=good}).error=='room_not_found')
  assert(host:game('ann',{op='join',code=r.code,rules=host.rules,player=good}).error=='own_room')
  assert(host:game('bob',{op='join',code=r.code,rules=host.rules,player={faction='Water',deck={}}}).error=='invalid_deck')
  assert(m.status=='waiting' and not m.guest,'a refused join leaves the room open')
  assert(host:game('ann',{op='act',match=m.id,seq=m.seq,action={type='pass'}}).error=='not_active')
  assert(host:game('bob',{op='join',code=r.code,rules=host.rules,player=good}).ok)
  assert(host:game('cat',{op='join',code=r.code,rules=host.rules,player=good}).error=='room_full')
  assert(host:game('cat',{op='act',match=m.id,seq=m.seq,action={type='pass'}}).error=='not_found')
  assert(host:state('cat',{p_match=m.id,p_seq=-1}).error=='not_found')
  assert(host:game('cat',{op='leave',match=m.id}).error=='not_found')
  local s=Server.restore(m.snapshot);local users={'ann','bob'}
  local mover,idle=users[s.active],users[3-s.active]
  local function act(user,action,seq,id) return host:game(user,{op='act',match=m.id,seq=seq or m.seq,action=action,id=id}) end
  local seq=m.seq
  assert(act(idle,{type='pass'}).error=='not_your_turn')
  assert(act(mover,{type='choose',index=1}).error=='no_choice')
  assert(act(mover,{type='advance'}).error=='not_computer_turn')
  assert(act(mover,{type='play',index=99,row=1,pos=1}).error=='illegal')
  local unitIndex
  for i,c in ipairs(s.players[s.active].hand) do
    if c.card.type=='Unit' then unitIndex=i;break end
  end
  assert(act(mover,{type='play',index=assert(unitIndex),row=1,pos=7}).error=='illegal')
  for _,bad in ipairs({{type='play'},{type='play',index='1'},{type='play',index=1.5,row=1,pos=1},{type='cheat'},{type='ai'},{}}) do
    local e=act(mover,bad).error;assert(e=='bad_request' or e=='illegal',json.encode(bad))
  end
  assert(m.seq==seq and not m.pending,'refused requests change nothing')
  assert(act(mover,{type='pass'},seq-1).error=='stale')
  r=act(mover,{type='pass'},seq,'once');assert(r.ok and m.seq==seq+1)
  r=act(mover,{type='pass'},seq,'once');assert(r.ok and r.duplicate and m.seq==seq+1,'a repeated request is not applied twice')
  assert(act(mover,{type='pass'},seq,'other').error=='stale')
  -- A question addressed to one player cannot be answered by the other, or with a value off the list.
  local asked
  for attempt=1,400 do
    local h=Host.new({seed=7000+attempt})
    local c=h:game('ann',{op='create',mode='duel',rules=h.rules,player={faction='Fantasy',deck=deck('Fantasy')}})
    h:game('bob',{op='join',code=c.code,rules=h.rules,player={faction='Fantasy',deck=deck('Fantasy')}})
    local mm=h.matches[c.match];local st=Server.restore(mm.snapshot);local hand=st.players[st.active].hand
    for i,u in ipairs(hand) do
      if u.card.id=='Fantasy:5' and #st.players[st.active].deck>=3 then
        local res=h:game(st.active==1 and 'ann' or 'bob',{op='act',match=mm.id,seq=mm.seq,action={type='play',index=i,row=2,pos=1}})
        local q=res.ok and res.frames[1].view.prompt
        if q and q.context.op=='search' then asked={h=h,m=mm,seat=st.active,q=q};break end
      end
    end
    if asked then break end
  end
  assert(asked,'no search question came up')
  local h,mm=asked.h,asked.m;local chooser,other=users[asked.seat],users[3-asked.seat]
  assert(mm.pending and #mm.pending==1 and asked.q.actor==asked.seat and asked.q.context.cards)
  local theirs=h:state(other,{p_match=mm.id,p_seq=-1}).view.prompt
  assert(theirs.actor==asked.seat and theirs.options==nil and theirs.context==nil,'the other player sees only who is choosing')
  local function answer(user,action) return h:game(user,{op='act',match=mm.id,seq=mm.seq,action=action}) end
  assert(answer(other,{type='choose',index=1}).error=='not_your_choice')
  assert(answer(chooser,{type='pass'}).error=='choice_pending')
  assert(answer(other,{type='pass'}).error=='choice_pending')
  for _,index in ipairs({0,#asked.q.options+1,-1,1.5,'1'}) do
    if not (index==0 and asked.q.context.optional) then assert(answer(chooser,{type='choose',index=index}).error=='invalid_choice') end
  end
  local before=mm.snapshot
  local res=answer(chooser,{type='choose',index=1});assert(res.ok)
  while mm.pending do
    assert(mm.snapshot==before,'the snapshot waits until the ability has finished')
    res=answer(chooser,{type='choose',index=1});assert(res.ok)
  end
  assert(mm.snapshot~=before)
  -- Leaving: an open room is removed, a running match is marked abandoned for both players.
  local h2=Host.new();local open=h2:game('ann',{op='create',mode='duel',rules=h2.rules,player=good})
  assert(h2:game('ann',{op='leave',match=open.match}).ok and not h2.matches[open.match])
  assert(h:game(other,{op='leave',match=mm.id}).ok and mm.status=='abandoned')
  local st=h:state(chooser,{p_match=mm.id,p_seq=mm.seq-1});assert(st.status=='abandoned' and st.left==3-asked.seat)
  assert(answer(chooser,{type='pass'}).error=='not_active')
end)

for _,v in ipairs(cases) do v[2]();print("PASS  "..v[1]) end
print(#cases.." online core tests passed.")
