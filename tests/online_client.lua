-- From the source root: lua tests/online_client.lua
-- The game-side networking (online/api.lua, online/session.lua) against the stand-in backend,
-- with a transport that answers at once and can lose requests or replies on demand.
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local json=require('online.json')
local Api=require('online.api')
local Session=require('online.session')
local Host=require('tests.devhost')
local L=require('tabletop.library')
local B=require('battle')
local U=require('util')
local cases={}
local function test(label,fn) cases[#cases+1]={label,fn} end
local function deck(faction)
  local c={factions={faction,faction},decks={{},{}}};L.starter(c,1,20);return c.decks[1]
end
-- net.lose_request / net.lose_reply: how many of the next requests to drop on each side.
local function network(host)
  local net={sent=0,lose_request=0,lose_reply=0,paths={}}
  net.send=function(req,done)
    net.sent=net.sent+1
    local path=req.url:match('^https://test%.invalid(/.*)$');assert(path,req.url)
    net.paths[#net.paths+1]=path
    if net.down or net.lose_request>0 then net.lose_request=math.max(0,net.lose_request-1);return done(nil,nil,'offline') end
    local headers={}
    for k,v in pairs(req.headers) do headers[k:lower()]=v end
    local status,body=host:http(req.method,path:gsub('%?.*$',''),headers,req.body)
    if net.lose_reply>0 and path=='/functions/v1/game' then net.lose_reply=net.lose_reply-1;return done(nil,nil,'timed out') end
    done(status,body)
  end
  return net
end
local function client(host,store)
  local net=network(host);store=store or {}
  local api=Api.new({url='https://test.invalid/',key=host.key,transport=net.send,clock=function() return host.clock end,
    load=function() return store.text end,save=function(text) store.text=text end})
  return api,net,store
end
local function decide(session,rng)
  local s,q=session.state,session.prompt
  local seat=session.seat
  if q then
    if q.context.optional then return {type='choose',index=rng:random(#q.options+1)-1} end
    return {type='choose',index=rng:random(#q.options)}
  end
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

test("Anonymous sign-in is remembered, refreshed when it expires, and never refreshed twice at once",function()
  local host=Host.new({token_life=600})
  local api,net,store=client(host)
  assert(api:configured() and not api.session)
  local answers={}
  for i=1,3 do api:call({op='hello'},function(r,err) answers[i]=assert(r,err and err.message) end) end
  assert(#answers==3 and answers[1].rules==host.rules)
  local signups=0;for _,p in ipairs(net.paths) do if p=='/auth/v1/signup' then signups=signups+1 end end
  assert(signups==1 and api.session.user and store.text)
  -- A second launch reuses the same player.
  local again=client(host,store);assert(again.session.user==api.session.user)
  local before=again.session.access_token
  host.clock=host.clock+700
  local ok;again:call({op='hello'},function(r) ok=r end)
  assert(ok and again.session.access_token~=before and again.session.user==api.session.user,'expired sign-in is refreshed')
  assert(json.decode(store.text).access_token==again.session.access_token)
  -- A refresh token refused by the server falls back to a new anonymous player.
  local third=client(host,{text=json.encode({access_token='x',refresh_token='gone',expires_at=0,url='https://test.invalid'})})
  local r3;third:call({op='hello'},function(r) r3=r end);assert(r3 and third.session.user~=api.session.user)
  -- A sign-in saved for another project is ignored.
  local other=client(host,{text=json.encode({access_token='x',refresh_token='y',expires_at=9e9,url='https://elsewhere'})})
  assert(not other.session)
  local down=client(host);local net2
  down,net2=client(host);net2.down=true
  local err;down:call({op='hello'},function(r,e) err=e end);assert(err.code=='network')
  local bad=Api.new({url='https://test.invalid',key='wrong',transport=network(host).send})
  bad:call({op='hello'},function(r,e) err=e end);assert(err.code=='auth' and err.message:find('401',1,true))
end)

test("Single player online through the session: paced computer moves, complete matches",function()
  for i=1,6 do
    local host=Host.new({seed=40+i});local api=client(host);local rng=U.rng(60+i)
    local frames,waited=0,0
    local s=Session.new(api,{pace=1,on_frame=function() frames=frames+1 end,token='t'..i})
    local f1,f2=L.factions[i%3+1],L.factions[(i+1)%3+1]
    s:start_solo({faction=f1,deck=deck(f1)},{faction=f2,difficulty=i%2==0 and 'easy' or 'normal'},host.rules)
    assert(s.phase=='playing' and s.seat==1 and s.mode=='solo' and s.controllers[2]=='AI',s.error)
    local guard=0
    while s.phase=='playing' do
      guard=guard+1;assert(guard<6000,'stuck')
      if s:ready() then assert(s:act(decide(s,rng)))
      else
        assert(not s:act({type='pass'}),'input is refused while the computer moves or a move is in flight')
        local shown=frames;s:update(0.5);waited=waited+0.5
        if frames>shown and s.state.active==1 then assert(true) end
      end
      assert(not s.notice,s.notice)
    end
    assert(s.phase=='over' and s.state.finished and not s.abandoned)
    local m=host.matches[s.match];assert(m.status=='finished' and #s.mirror.log==#m.log)
    for n,line in ipairs(m.log) do assert(s.mirror.log[n]==line) end
    assert(frames>10 and waited>=1,'computer moves are shown one at a time')
  end
end)

test("Two players online through two sessions: room code, polling, both screens agree",function()
  for i=1,6 do
    local host=Host.new({seed=140+i});local rng=U.rng(10+i)
    local a,netA=client(host);local b,netB=client(host)
    local ann,bob=Session.new(a,{poll=1,idle_poll=3,token='a'}),Session.new(b,{poll=1,idle_poll=3,token='b'})
    local f1,f2=L.factions[i%3+1],L.factions[(i+2)%3+1]
    ann:open_room({faction=f1,deck=deck(f1)},host.rules)
    assert(ann.phase=='waiting' and #ann.code==6 and not ann.state)
    local sent=netA.sent;ann:update(0.4);assert(netA.sent==sent,'polls are spaced out')
    ann:update(1);assert(netA.sent==sent+1 and ann.phase=='waiting')
    local wrong=Session.new(b);wrong:join_room('NOPE00',{faction=f2,deck=deck(f2)},host.rules)
    assert(wrong.phase=='failed' and wrong.code_error=='room_not_found' and wrong.error:find('code',1,true))
    bob:join_room(ann.code,{faction=f2,deck=deck(f2)},host.rules)
    assert(bob.phase=='playing' and bob.seat==2)
    ann:update(1);ann:update(0);assert(ann.phase=='playing' and ann.seat==1 and ann.state,'the host learns of the guest by polling')
    local guard=0
    while ann.phase=='playing' or bob.phase=='playing' do
      guard=guard+1;assert(guard<8000,'stuck')
      local mover
      for _,s in ipairs({ann,bob}) do if s:ready() then assert(not mover,'both players may act');mover=s end end
      if mover then assert(mover:act(decide(mover,rng))) end
      ann:update(0.5);bob:update(0.5)
      assert(not ann.notice and not bob.notice,ann.notice or bob.notice)
      -- A player never holds the other player's hand.
      for _,s in ipairs({ann,bob}) do
        local foe=s.state.players[3-s.seat].hand
        assert(foe[1]==nil or foe[1].hidden)
      end
    end
    local m=host.matches[ann.match]
    assert(ann.phase=="over" and bob.phase=="over" and m.status=="finished",ann.phase.." "..bob.phase.." "..m.status.." i="..i.." guard="..guard.." q="..#ann.queue.."/"..#bob.queue.." seq="..tostring(ann.seq).."/"..tostring(bob.seq).."/"..m.seq)
    assert(ann.state.winner==bob.state.winner and #ann.mirror.log==#m.log and #bob.mirror.log==#m.log)
    for p=1,2 do assert(ann.state.players[p].wins==bob.state.players[p].wins) end
  end
end)

test("Lost requests and lost replies: every move is applied exactly once",function()
  local host=Host.new({seed=9});local rng=U.rng(3)
  local a,netA=client(host);local b,netB=client(host)
  local ann,bob=Session.new(a,{poll=1,retry=1,token='a'}),Session.new(b,{poll=1,retry=1,token='b'})
  ann:open_room({faction='Water',deck=deck('Water')},host.rules)
  bob:join_room(ann.code,{faction='Super',deck=deck('Super')},host.rules)
  ann:update(1);ann:update(0)
  local m=host.matches[ann.match];local guard,lost=0,0
  local recovered={}
  while ann.phase=='playing' or bob.phase=='playing' do
    guard=guard+1;assert(guard<20000,'stuck')
    for _,pair in ipairs({{ann,netA},{bob,netB}}) do
      local s,net=pair[1],pair[2]
      if s:ready() then
        local before=m.seq;local kind=lost%3+1
        if kind==1 then net.lose_request=1 elseif kind==2 then net.lose_reply=1 elseif kind==3 then net.lose_request=2;net.lose_reply=1 end
        assert(s:act(decide(s,rng)))
        if kind>=1 and kind<=3 then
          lost=lost+1;assert(s.offline and not s:ready())
          assert(m.seq==before+(kind==2 and 1 or 0),'a lost request is not applied, a lost reply is')
          local spins=0
          while s.offline or s.pending_action do s:update(1);spins=spins+1;assert(spins<20) end
          assert(m.seq==before+1,'after recovery the move counts once')
          recovered[kind]=true
        end
      end
    end
    ann:update(0.5);bob:update(0.5)
  end
  assert(recovered[1] and recovered[2] and recovered[3],"must recover a lost request, lost reply, and repeated loss")
  assert(m.status=='finished' and #ann.mirror.log==#m.log and #bob.mirror.log==#m.log)
  for n,line in ipairs(m.log) do assert(ann.mirror.log[n]==line and bob.mirror.log[n]==line) end
  -- While the connection is down the session keeps trying and says so.
  local host2=Host.new({seed=2});local c,netC=client(host2)
  local solo=Session.new(c,{pace=0,retry=1,token='c'})
  solo:start_solo({faction='Fantasy',deck=deck('Fantasy')},{faction='Water'},host2.rules)
  local spins=0
  while not solo:ready() do solo:update(1);spins=spins+1;assert(spins<50) end
  netC.down=true;assert(solo:act({type='pass'}));assert(solo.offline)
  for _=1,5 do solo:update(1) end
  assert(solo.offline and solo.pending_action and not solo:ready())
  netC.down=false;spins=0
  while solo.offline or solo.pending_action do solo:update(1);spins=spins+1;assert(spins<30) end
  assert(not solo.offline and host2.matches[solo.match].seq>=2)
end)

test("Leaving, resuming after a restart, refused starts",function()
  local host=Host.new({seed=21});local rng=U.rng(8)
  local a=client(host);local b=client(host)
  local saved={}
  local ann=Session.new(a,{poll=1,token='a',remember=function(id) saved.match=id end})
  local bob=Session.new(b,{poll=1,token='b'})
  ann:open_room({faction='Fantasy',deck=deck('Fantasy')},host.rules);assert(saved.match==ann.match)
  bob:join_room(ann.code,{faction='Water',deck=deck('Water')},host.rules)
  for _=1,3 do ann:update(1) end
  for _=1,40 do
    for _,s in ipairs({ann,bob}) do if s:ready() then assert(s:act(decide(s,rng))) end end
    ann:update(0.5);bob:update(0.5)
    if #ann.mirror.log>5 and ann.seq==bob.seq and #ann.queue==0 and #bob.queue==0 then break end
  end
  assert(ann.phase=='playing' and #ann.mirror.log>5)
  -- A new launch picks the match up again with the whole record and the same seat.
  local back=Session.new(a,{poll=1,token='a2'});back:resume(saved.match)
  assert(back.phase=='playing' and back.seat==1 and back.seq==ann.seq and #back.mirror.log==#ann.mirror.log)
  for p=1,2 do assert(B.score(back.state,p)==B.score(ann.state,p) and #back.state.players[p].hand==#ann.state.players[p].hand) end
  assert(back:ready()==ann:ready())
  -- The other player leaves: this one is told, and the match no longer accepts moves.
  bob:leave();assert(bob.phase=='idle')
  for _=1,6 do ann:update(1) end
  assert(ann.phase=='over' and ann.abandoned and ann.left==2 and saved.match==nil)
  local gone=Session.new(a);gone:resume('match-missing');assert(gone.phase=='failed')
  -- Closing an open room removes it.
  local c=client(host);local lone=Session.new(c)
  lone:open_room({faction='Water',deck=deck('Water')},host.rules);local id=lone.match
  lone:leave();assert(not host.matches[id])
  -- Refused starts explain themselves.
  local s=Session.new(c);s:start_solo({faction='Water',deck={}},{faction='Water'},host.rules)
  assert(s.phase=='failed' and s.code_error=='invalid_deck' and s.error:find('at least 20',1,true))
  s=Session.new(c);s:start_solo({faction='Water',deck=deck('Water')},{faction='Water'},'old-rules')
  assert(s.phase=='failed' and s.code_error=='rules_mismatch')
end)

for _,v in ipairs(cases) do v[2]();print("PASS  "..v[1]) end
print(#cases.." online client tests passed.")
