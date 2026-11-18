-- Plays whole matches against a running game server, with the same client code the game
-- uses (online/api.lua, online/session.lua) and real HTTP requests through the curl command.
--
--   lua tests/online_live.lua                       the project in online/config.lua
--   lua tests/online_live.lua URL KEY               another server (tests/mock_backend.py)
--
-- It signs in three anonymous players, plays one match against the computer and one
-- two-player match through a room code, and checks what the server refuses.
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local json=require('online.json')
local Api=require('online.api')
local Session=require('online.session')
local Http=require('online.http')
local Rules=require('online.rules')
local L=require('tabletop.library')
local B=require('battle')
local U=require('util')
local config=require('online.config')
local url,key=arg[1] or config.url,arg[2] or config.key
assert(url~='' and key~='','No server: fill in online/config.lua or pass URL and KEY.')
local request=assert(Http.backend(nil,'command'))
local requests,bytes=0,0
local function transport(req,done)
  requests=requests+1
  local status,body=request(req)
  if status then bytes=bytes+#body end
  done(status,body,not status and body or nil)
end
local function read(path) local f=io.open(path,'rb');if not f then return nil end;local t=f:read('*a');f:close();return t end
local function sha256(text)
  local path=os.tmpname();local f=assert(io.open(path,'wb'));f:write(text);f:close()
  local pipe=assert(io.popen('shasum -a 256 "'..path..'"'));local out=pipe:read('*a');pipe:close();os.remove(path)
  return assert(out:match('^%x+'))
end
local rules=assert(Rules.version(read,sha256))
local function player() return Api.new({url=url,key=key,transport=transport}) end
local function deck(faction)
  local c={factions={faction,faction},decks={{},{}}};L.starter(c,1);return c.decks[1]
end
local function decide(session,rng)
  local s,q,seat=session.state,session.prompt,session.seat
  if q then
    if q.context.optional then return {type='choose',index=rng:random(#q.options+1)-1} end
    return {type='choose',index=rng:random(#q.options)}
  end
  if B.can_school(s,seat) then return {type='school'} end
  local legal={}
  for i=1,#s.players[seat].hand do if B.playable(s,seat,i) then legal[#legal+1]=i end end
  if s.extra_turn and rng:random(4)==1 then return {type='end'} end
  local targets=B.attack_targets(s,seat)
  if #targets>0 and (#legal==0 or rng:random(3)==1) then
    for _,u in ipairs(B.units(s,seat)) do
      if B.ready(s,seat,u) then return {type='attack',attacker=u.uid,target=targets[rng:random(#targets)].uid} end
    end
  end
  if #legal==0 or rng:random(14)==1 then return {type='pass'} end
  local i=legal[rng:random(#legal)];local card=s.players[seat].hand[i].card
  if card.type=='Unit' and not card.replaces then
    local rows=s.players[B.deploy_side(seat,card)].rows;local row=rng:random(2)
    return {type='play',index=i,row=row,pos=rng:random(#rows[row]+1)}
  end
  return {type='play',index=i}
end
local function call(api,body)
  local reply,err
  api:call(body,function(r,e) reply,err=r,e end)
  return reply,err
end
local function step(label,fn)
  local t=os.clock();local before=requests
  fn()
  print(string.format('PASS  %s  (%d requests)',label,requests-before))
end

local ann,bob,cat=player(),player(),player()
step('The server answers and runs the same rules as this checkout ('..rules..')',function()
  local hello,err=call(ann,{op='hello'})
  assert(hello,err and err.message)
  assert(hello.rules==rules,'server rules '..tostring(hello.rules)..' differ from local '..rules..': run scripts/publish_rules.py')
  assert(call(bob,{op='hello'}) and call(cat,{op='hello'}))
  assert(ann.session.user and ann.session.user~=bob.session.user and bob.session.user~=cat.session.user)
end)

step('Single player: a complete match against the computer',function()
  local rng=U.rng(11)
  local s=Session.new(ann,{pace=0,retry=1,token='live-solo'})
  s:start_solo({faction='Fantasy',deck=deck('Fantasy')},{faction='Super',difficulty='normal'},rules)
  assert(s.phase=='playing',s.error)
  assert(s.seat==1 and #s.state.players[1].hand==5 and s.state.players[2].hand[1].hidden)
  local guard=0
  while s.phase=='playing' do
    guard=guard+1;assert(guard<3000,'stuck')
    if s:ready() then assert(s:act(decide(s,rng))) else s:update(1) end
    assert(not s.notice,s.notice);assert(not s.offline,'connection lost')
  end
  assert(s.state.finished and #s.state.round_history>=2,'the match should reach its end')
  print('      winner seat '..s.state.winner..', '..#s.mirror.log..' record lines')
end)

local room
step('Two players: room code, a complete match, both sides agree',function()
  local rng=U.rng(12)
  local a=Session.new(ann,{poll=0,idle_poll=3,retry=1,token='live-a'})
  local b=Session.new(bob,{poll=0,idle_poll=3,retry=1,token='live-b'})
  a:open_room({faction='Water',deck=deck('Water')},rules)
  assert(a.phase=='waiting' and #a.code==6,a.error)
  local wrong=Session.new(cat);wrong:join_room('ZZZZZZ',{faction='Water',deck=deck('Water')},rules)
  assert(wrong.phase=='failed' and wrong.code_error=='room_not_found')
  local own=Session.new(ann);own:join_room(a.code,{faction='Water',deck=deck('Water')},rules)
  assert(own.phase=='failed' and own.code_error=='own_room')
  b:join_room(a.code:lower(),{faction='Super',deck=deck('Super')},rules)
  assert(b.phase=='playing' and b.seat==2,b.error)
  local late=Session.new(cat);late:join_room(a.code,{faction='Water',deck=deck('Water')},rules)
  assert(late.phase=='failed' and late.code_error=='room_full')
  a:update(1);a:update(1);assert(a.phase=='playing' and a.seat==1,'the host sees the guest arrive')
  room=a.match
  -- What the server refuses, checked once at the start with raw requests.
  local mover,idle=a.state.active==1 and ann or bob,a.state.active==1 and bob or ann
  local function raw(api,action,seq,id) return select(2,call(api,{op='act',match=room,seq=seq or a.seq,action=action,id=id})) end
  assert(raw(idle,{type='pass'}).code=='not_your_turn')
  assert(raw(cat,{type='pass'}).code=='not_found')
  assert(raw(mover,{type='play',index=99,row=1,pos=1}).code=='illegal')
  assert(raw(mover,{type='cheat'}).code=='bad_request')
  assert(raw(mover,{type='pass'},a.seq-1).code=='stale')
  local state,denied
  cat:state(room,-1,0,function(st,err) state,denied=st,err end)
  assert(not state and denied.code=='not_found','a stranger cannot read the match')
  local guard=0
  while a.phase=='playing' or b.phase=='playing' do
    guard=guard+1;assert(guard<6000,'stuck')
    for _,s in ipairs({a,b}) do
      if s:ready() then
        local action=decide(s,rng);local before=s.seq
        assert(s:act(action))
        -- The same request again (a retry after a lost answer) must not count twice.
        if guard%9==0 then
          local again=call(s.api,{op='act',match=room,seq=before,action=action,id=s.token..'-'..s.serial})
          assert(again and again.duplicate,'a repeated move was applied again')
        end
      end
    end
    a:update(1);b:update(1)
    for _,s in ipairs({a,b}) do
      assert(not s.notice,s.notice)
      local foe=s.state.players[3-s.seat].hand
      assert(foe[1]==nil or foe[1].hidden,'the other hand reached this client')
    end
  end
  assert(a.state.finished and b.state.finished and a.state.winner==b.state.winner)
  assert(#a.mirror.log==#b.mirror.log and #a.state.round_history==#b.state.round_history)
  for p=1,2 do assert(a.state.players[p].wins==b.state.players[p].wins) end
  print('      winner seat '..a.state.winner..', '..#a.mirror.log..' record lines')
end)

step('Private data cannot be read around the game: tables are closed, views are per seat',function()
  -- Signed-in players asking the database directly for matches, rules and publish keys.
  for _,path in ipairs({'/rest/v1/matches?select=*','/rest/v1/rules?select=version','/rest/v1/deploy_keys?select=*'}) do
    local status,body
    transport({method='GET',url=url..path,timeout=20,headers={apikey=key,Authorization='Bearer '..bob.session.access_token}},
      function(s,b) status,body=s,b end)
    local rows=json.decode(body or '')
    assert(status and (status>=400 or (type(rows)=='table' and next(rows)==nil)),path..' returned data: '..tostring(body):sub(1,120))
  end
  -- Each player's stored view holds their own hand and only the size of the other one.
  for _,api in ipairs({ann,bob}) do
    local st
    api:state(room,-1,0,function(s) st=s end)
    assert(st and st.view and st.view.players[st.seat].cards and not st.view.players[3-st.seat].cards)
    local text=json.encode(st)
    assert(not text:find('"snapshot"',1,true) and not text:find('"decks"',1,true) and not text:find('"seed"',1,true))
  end
  -- Without a sign-in nothing answers.
  local status
  transport({method='POST',url=url..'/functions/v1/game',timeout=20,body='{"op":"hello"}',
    headers={apikey=key,['Content-Type']='application/json'}},function(s) status=s end)
  assert(status==401,'the game function answered without a sign-in: '..tostring(status))
  transport({method='POST',url=url..'/rest/v1/rpc/publish_rules',timeout=20,
    body=json.encode({p_secret=string.rep('x',40),p_version=rules,p_modules=json.object({['online.server']='x'})}),
    headers={apikey=key,['Content-Type']='application/json'}},function(s) status=s end)
  assert(status and status>=400,'rules could be published without the secret')
end)

step('Leaving: the other player is told, and the match takes no more moves',function()
  local a=Session.new(ann,{poll=0,token='live-c'});local b=Session.new(bob,{poll=0,token='live-d'})
  a:open_room({faction='Fantasy',deck=deck('Fantasy')},rules)
  b:join_room(a.code,{faction='Fantasy',deck=deck('Fantasy')},rules)
  a:update(1);a:update(1);assert(a.phase=='playing' and b.phase=='playing')
  b:leave()
  for _=1,4 do a:update(5) end
  assert(a.phase=='over' and a.abandoned and a.left==2)
  local refused=select(2,call(ann,{op='act',match=a.match,seq=a.seq,action={type='pass'}}))
  assert(refused.code=='not_active')
end)
print(string.format('Live server tests passed: %d requests, %.0f KB received.',requests,bytes/1024))
