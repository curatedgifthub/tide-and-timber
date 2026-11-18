-- Authoritative match logic for online play. Pure Lua, no input/output: the host (the
-- Supabase Edge Function, or tests/mock_backend.py) authenticates the caller, loads the
-- stored match, calls Server.call, and stores what comes back.
--
-- A match is stored as a snapshot of the battle state taken while nothing is waiting for an
-- answer, plus "pending": the inputs applied since that snapshot when an ability has stopped
-- to ask a player something. A suspended ability cannot be stored, so those inputs are
-- replayed from the snapshot on the next request. The engine is deterministic, so the replay
-- reaches the same question.
local C=require('data.cards')
local B=require('battle')
local AI=require('ai')
local Decks=require('decks')
local Library=require('tabletop.library')
local Snap=require('online.snapshot')
local View=require('online.view')
local json=require('online.json')
local U=require('util')
local Server={protocol=1,version='dev',
  -- Computer turns resolved per request. The client asks again ("advance") while the
  -- computer still has the turn, which keeps every request short.
  ai_steps=3}

local function fail(code,message) return {ok=false,error=code,message=message} end
local function controllers(cfg)
  return cfg.mode=='solo' and {'Human','AI'} or {'Human','Human'}
end
local function deck_ok(faction,deck)
  if type(faction)~='string' or not Library.owned[faction] or Library.size(faction)==0 then return false,'Unknown faction.' end
  if type(deck)~='table' then return false,'A deck is required.' end
  local n=0
  for k,id in pairs(deck) do
    n=n+1
    if type(k)~='number' or type(id)~='string' or n>400 then return false,'Malformed deck.' end
  end
  if n~=#deck then return false,'Malformed deck.' end
  return Decks.validate_selection(deck,faction,Library.owned[faction])
end

local function save(s)
  return Snap.dump(s,C.by_id,{log=true,chooser=true,on_event=true,on_draw=true})
end
local function restore(text)
  if type(text)~='string' then error('The match has no stored state.') end
  local s=Snap.load(text,C.by_id)
  local rng=U.rng(1);rng.seed=s.rng.seed;s.rng=rng
  s.log={}
  return s
end

local function perform(s,action,difficulty)
  local p,t=s.active,action.type
  if t=='ai' then return AI.step(s,p,difficulty) end
  if t=='pass' then return B.pass(s,p) end
  if t=='end' then return B.end_extra(s,p) end
  if t=='school' then return B.school(s,p) end
  return B.play(s,p,action.index,action.row,action.pos)
end
local function step(run,value)
  local ok,a,b=coroutine.resume(run.co,value)
  if not ok then error(tostring(a),0) end
  if coroutine.status(run.co)=='suspended' then run.prompt=a
  else run.prompt=nil;run.ok=a;run.why=b end
end
-- Runs one action. Recorded answers are fed back in order; the first question without a
-- recorded answer suspends the action and becomes run.prompt.
local function drive(s,ctl,difficulty,action,choices)
  local run={used=0}
  s.chooser=function(_,actor,kind,options,context)
    if ctl[actor]=='AI' then return nil end
    if #options==1 and kind~='order' and not (context and (context.cards or context.optional)) then return 1 end
    run.used=run.used+1
    local recorded=choices[run.used]
    if recorded then return recorded end
    return coroutine.yield({actor=actor,kind=kind,options=options,context=context or {}})
  end
  run.co=coroutine.create(function() return perform(s,action,difficulty) end)
  step(run)
  return run
end

local function whole(v,max)
  if type(v)=='number' and v%1==0 and v>=1 and v<=max then return math.floor(v) end
end
local function clean(action)
  local t=action.type
  if t=='pass' or t=='end' or t=='school' then return {type=t} end
  if t~='play' then return nil end
  local index=whole(action.index,1000)
  if not index then return nil end
  return {type='play',index=index,row=whole(action.row,2),pos=whole(action.pos,1000)}
end

local function views(s,cfg,seq,prompt,draws)
  local ctl=controllers(cfg);local out=json.object({})
  for seat=1,2 do
    if ctl[seat]=='Human' then
      out[tostring(seat)]=View.build(s,seat,{seq=seq,mode=cfg.mode,controllers=ctl,prompt=prompt,draws=draws})
    end
  end
  return out
end
local function slice(list,from)
  local out={}
  for i=from+1,#list do out[#out+1]=list[i] end
  return out
end

-- Deals a new battle. Used when a solo match is created and when the guest joins a room.
local function begin(cfg,req,seat)
  if type(req.seed)~='number' or req.seed%1~=0 or req.seed<1 or req.seed>2147483646 then error('The host must supply a seed.') end
  local names=cfg.mode=='solo' and {'Player','Computer'} or {'Player 1','Player 2'}
  local s=B.new(cfg.decks[1],cfg.decks[2],{seed=math.floor(req.seed),names=names,
    player_faction=cfg.factions[1],ai_faction=cfg.factions[2]})
  local lines=s.log;s.log={}
  local seq=(req.seq or 0)+1
  local all=views(s,cfg,seq)
  local ctl=controllers(cfg)
  return {ok=true,
    store={status=s.finished and 'finished' or 'active',config=cfg,pending=false,views=all,seq=seq},
    log=lines,
    reply={view=all[tostring(seat)],log=lines,seq=seq,
      more=(not s.finished and ctl[s.active]=='AI') or nil}},save(s)
end

local function create(req)
  local mode=req.mode
  if mode~='solo' and mode~='duel' then return fail('bad_request','Unknown mode.') end
  local me=type(req.player)=='table' and req.player or {}
  local ok,why=deck_ok(me.faction,me.deck)
  if not ok then return fail('invalid_deck',why) end
  local cfg={mode=mode,factions={me.faction},decks={me.deck}}
  if mode=='duel' then
    return {ok=true,store={status='waiting',config=cfg,pending=false,views=json.object({}),seq=(req.seq or 0)+1},
      log={},reply={status='waiting',seq=(req.seq or 0)+1}}
  end
  local ai=type(req.ai)=='table' and req.ai or {}
  if type(ai.faction)~='string' or not Library.owned[ai.faction] or Library.size(ai.faction)==0 then
    return fail('invalid_deck','Unknown faction for the computer.')
  end
  local deck=ai.deck
  if type(deck)~='table' or next(deck)==nil then
    -- No deck chosen for the computer: it brings the 30-card starter of its faction.
    local draft={factions={ai.faction,ai.faction},decks={{},{}}}
    Library.starter(draft,2);deck=draft.decks[2]
  end
  ok,why=deck_ok(ai.faction,deck)
  if not ok then return fail('invalid_deck','Computer deck: '..tostring(why)) end
  cfg.factions[2],cfg.decks[2]=ai.faction,deck
  cfg.difficulty=ai.difficulty=='easy' and 'easy' or 'normal'
  return begin(cfg,req,1)
end

local function join(req)
  local cfg=req.config
  if type(cfg)~='table' or cfg.mode~='duel' or cfg.factions[2] then return fail('room_unavailable','This room cannot be joined.') end
  local me=type(req.player)=='table' and req.player or {}
  local ok,why=deck_ok(me.faction,me.deck)
  if not ok then return fail('invalid_deck',why) end
  cfg.factions[2],cfg.decks[2]=me.faction,me.deck
  return begin(cfg,req,2)
end

local function act(req,snapshot)
  local cfg,seat,action=req.config,req.seat,req.action
  if type(cfg)~='table' or (seat~=1 and seat~=2) then error('The host sent an incomplete match.') end
  if type(action)~='table' or type(action.type)~='string' then return fail('bad_request','Missing action.') end
  local ctl=controllers(cfg)
  if ctl[seat]~='Human' then return fail('bad_request','That seat is played by the computer.') end
  local s=restore(snapshot)
  local draws={}
  s.on_draw=function(event) draws[#draws+1]=event end
  local script=type(req.pending)=='table' and req.pending or {}
  local run
  for i,entry in ipairs(script) do
    run=drive(s,ctl,cfg.difficulty,entry.action,entry.choices)
    if (run.prompt~=nil)~=(i==#script) then error('The stored inputs no longer replay to the same question.') end
  end
  local seq=req.seq+1
  local frames,logMark,drawMark={},#s.log,#draws
  local logFrom,drawFrom=logMark,drawMark
  local function frame()
    frames[#frames+1]={log=slice(s.log,logMark),
      view=View.build(s,seat,{seq=seq,mode=cfg.mode,controllers=ctl,prompt=run and run.prompt,draws=slice(draws,drawMark)})}
    logMark,drawMark=#s.log,#draws
  end
  if run then
    -- An ability is waiting for an answer.
    local q=run.prompt
    if action.type~='choose' then return fail('choice_pending','Finish the pending choice first.') end
    if q.actor~=seat then return fail('not_your_choice','Waiting for the other player to choose.') end
    local index=action.index
    if type(index)~='number' or index%1~=0 or not (q.options[index] or index==0 and q.context.optional) then
      return fail('invalid_choice','Choose a listed option.')
    end
    index=math.floor(index)
    local entry=script[#script];entry.choices[#entry.choices+1]=index
    step(run,index)
    frame()
  elseif action.type=='choose' then return fail('no_choice','No choice is pending.')
  elseif action.type=='advance' then
    if s.finished or ctl[s.active]~='AI' then return fail('not_computer_turn','The computer is not to move.') end
  else
    if s.finished then return fail('finished','The match is over.') end
    if s.active~=seat then return fail('not_your_turn','It is not your turn.') end
    local entry={action=clean(action),choices={}}
    if not entry.action then return fail('bad_request','Unknown action.') end
    run=drive(s,ctl,cfg.difficulty,entry.action,entry.choices)
    -- A refused action changes nothing, so nothing is stored.
    if not run.prompt and not run.ok then return fail('illegal',run.why or 'That play is not allowed.') end
    script[#script+1]=entry
    frame()
  end
  if not (run and run.prompt) then
    local steps=0
    while not s.finished and ctl[s.active]=='AI' and steps<Server.ai_steps do
      local entry={action={type='ai'},choices={}}
      run=drive(s,ctl,cfg.difficulty,entry.action,entry.choices)
      if not run.prompt and not run.ok then error('The computer could not move: '..tostring(run.why)) end
      script[#script+1]=entry;steps=steps+1
      frame()
      if run.prompt then break end
    end
  end
  local prompt=run and run.prompt
  -- Stored views are what a seat receives when it polls: the acting seat's last frame, and
  -- for the other seat the same position with the draws of this request.
  local stored=json.object({})
  for other=1,2 do
    if other==seat then stored[tostring(other)]=frames[#frames].view
    elseif ctl[other]=='Human' then
      stored[tostring(other)]=View.build(s,other,{seq=seq,mode=cfg.mode,controllers=ctl,prompt=prompt,draws=slice(draws,drawFrom)})
    end
  end
  local store={status=s.finished and 'finished' or 'active',pending=prompt and script or false,seq=seq,views=stored}
  local reply={frames=frames,seq=seq,more=(not prompt and not s.finished and ctl[s.active]=='AI') or nil}
  return {ok=true,store=store,log=slice(s.log,logFrom),reply=reply},(not prompt) and save(s) or nil
end

-- For tests: rebuild the battle state from a stored snapshot.
Server.restore=restore
function Server.handle(req,snapshot)
  if req.op=='create' then return create(req) end
  if req.op=='join' then return join(req) end
  if req.op=='act' then return act(req,snapshot) end
  return fail('bad_request','Unknown operation.')
end
-- request_json: {op=..., seq=..., seed=..., seat=..., config=..., pending=..., ...}.
-- Returns the response as JSON and, when the stored snapshot must be replaced, the new one.
function Server.call(request_json,snapshot)
  local req,why=json.decode(request_json)
  if type(req)~='table' then return json.encode(fail('bad_request',why or 'Malformed request.')) end
  local ok,resp,snap=pcall(Server.handle,req,snapshot)
  if not ok then return json.encode(fail('engine',tostring(resp))) end
  return json.encode(resp),snap
end
return Server
