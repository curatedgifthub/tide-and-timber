-- A stand-in for the Supabase backend, for tests. It implements the same HTTP surface as
-- the real project (anonymous auth, the "game" Edge Function, the match_state RPC) on top of
-- the real server core in online/server.lua, with matches kept in a Lua table.
-- supabase/functions/game/index.ts and the SQL migration are the production equivalents.
local json=require('online.json')
local Server=require('online.server')
local U=require('util')
local Host={}
Host.__index=Host
local alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
function Host.new(opts)
  opts=opts or {}
  return setmetatable({key=opts.key or 'test-key',rules=opts.rules or 'test-rules',token_life=opts.token_life or 3600,
    clock=opts.clock or 1000,rng=U.rng(opts.seed or 77),users={},tokens={},refresh={},matches={},serial=0},Host)
end
function Host:id(prefix) self.serial=self.serial+1;return prefix..'-'..self.serial end
function Host:issue(user)
  local at,rt=self:id('at'),self:id('rt')
  self.tokens[at]={user=user,expires=self.clock+self.token_life};self.refresh[rt]=user
  return {access_token=at,refresh_token=rt,expires_in=self.token_life,token_type='bearer',user={id=user,is_anonymous=true}}
end
function Host:user(headers)
  local token=(headers.authorization or ''):match('^Bearer (.+)$')
  local t=token and self.tokens[token]
  if t and t.expires>self.clock then return t.user end
end
local function seat_of(m,user) return m.host==user and 1 or m.guest==user and 2 or nil end
function Host:code()
  while true do
    local code=''
    for _=1,6 do local i=self.rng:random(#alphabet);code=code..alphabet:sub(i,i) end
    local taken=false
    for _,m in pairs(self.matches) do if m.code==code then taken=true end end
    if not taken then return code end
  end
end
-- The Lua server core takes and returns JSON, as it does inside the Edge Function.
function Host:core(request,snapshot)
  local text,snap=Server.call(json.encode(request),snapshot)
  return assert(json.decode(text)),snap
end
function Host:game(user,body)
  local op=body.op
  if op=='hello' then return {ok=true,rules=self.rules,protocol=Server.protocol} end
  if op=='create' or op=='join' then
    if body.rules~=self.rules then
      return {ok=false,error='rules_mismatch',message='This copy of the game uses different rules from the server.',rules=self.rules}
    end
  end
  if op=='create' then
    local resp,snap=self:core({op='create',seq=0,seed=self.rng:random(2147483646),mode=body.mode,player=body.player,ai=body.ai})
    if not resp.ok then return resp end
    local id=self:id('match')
    local m={id=id,host=user,mode=body.mode,status=resp.store.status,config=resp.store.config,pending=nil,
      views=resp.store.views,snapshot=snap,log=resp.log,seq=resp.store.seq,rules=self.rules,seen={}}
    if body.mode=='duel' then m.code=self:code() end
    self.matches[id]=m
    local reply=resp.reply;reply.ok=true;reply.match=id;reply.code=m.code;reply.seat=1;reply.log_from=0
    return reply
  elseif op=='join' then
    local code=type(body.code)=='string' and body.code:upper():gsub('%s','') or ''
    local m
    for _,x in pairs(self.matches) do if x.code==code and x.mode=='duel' then m=x end end
    if not m then return {ok=false,error='room_not_found',message='No open room has that code.'} end
    if m.status~='waiting' then return {ok=false,error='room_full',message='That room already has two players.'} end
    if m.host==user then return {ok=false,error='own_room',message='You cannot join your own room.'} end
    local resp,snap=self:core({op='join',seq=m.seq,seed=self.rng:random(2147483646),config=m.config,player=body.player})
    if not resp.ok then return resp end
    m.guest,m.status,m.config,m.views,m.snapshot,m.seq=user,resp.store.status,resp.store.config,resp.store.views,snap,resp.store.seq
    for _,line in ipairs(resp.log) do m.log[#m.log+1]=line end
    local reply=resp.reply;reply.ok=true;reply.match=m.id;reply.seat=2;reply.log_from=0
    return reply
  end
  local m=self.matches[body.match]
  local seat=m and seat_of(m,user)
  if not seat then return {ok=false,error='not_found',message='Match not found.'} end
  if op=='leave' then
    if m.status=='waiting' then self.matches[m.id]=nil
    elseif m.status=='active' then m.status,m.left,m.seq='abandoned',seat,m.seq+1 end
    return {ok=true}
  elseif op=='act' then
    if m.status~='active' then return {ok=false,error='not_active',message='This match is not in progress.',status=m.status} end
    if type(body.id)=='string' and m.last_action and m.last_action.id==body.id and m.last_action.seat==seat then
      return {ok=true,duplicate=true,seq=m.seq}
    end
    if body.seq~=m.seq then return {ok=false,error='stale',message='The match has moved on.',seq=m.seq} end
    local resp,snap=self:core({op='act',seq=m.seq,seat=seat,config=m.config,pending=m.pending or false,action=body.action},m.snapshot)
    if not resp.ok then return resp end
    local reply=resp.reply;reply.ok=true;reply.log_from=#m.log
    m.status,m.pending,m.views,m.seq=resp.store.status,resp.store.pending or nil,resp.store.views,resp.store.seq
    if snap then m.snapshot=snap end
    for _,line in ipairs(resp.log) do m.log[#m.log+1]=line end
    m.last_action=type(body.id)=='string' and {id=body.id,seat=seat} or nil
    return reply
  end
  return {ok=false,error='bad_request',message='Unknown operation.'}
end
function Host:state(user,args)
  local m=self.matches[args.p_match]
  local seat=m and seat_of(m,user)
  if not seat then return {error='not_found'} end
  m.seen[seat]=self.clock
  local other=m.seen[3-seat]
  local out={seq=m.seq,status=m.status,left=m.left,code=m.code,seat=seat,
    opponent_seen=other and self.clock-other or nil}
  if m.seq~=args.p_seq then
    out.view=m.views[tostring(seat)]
    out.log_from=math.min(args.p_log or 0,#m.log);out.log={}
    for i=out.log_from+1,#m.log do out.log[#out.log+1]=m.log[i] end
  end
  return out
end
-- headers: lower-case names. Returns the status code and the response body text.
function Host:http(method,path,headers,body)
  if headers.apikey~=self.key then return 401,json.encode({message='Invalid API key'}) end
  local data=body and body~='' and json.decode(body) or {}
  if path=='/auth/v1/signup' then
    return 200,json.encode(self:issue(self:id('user')))
  elseif path:find('^/auth/v1/token') then
    local user=self.refresh[data.refresh_token]
    if not user then return 400,json.encode({error_code='refresh_token_not_found',msg='Invalid Refresh Token'}) end
    self.refresh[data.refresh_token]=nil
    return 200,json.encode(self:issue(user))
  end
  local user=self:user(headers)
  if not user then return 401,json.encode({message='JWT expired'}) end
  if path=='/functions/v1/game' then return 200,json.encode(self:game(user,data))
  elseif path=='/rest/v1/rpc/match_state' then return 200,json.encode(self:state(user,data)) end
  return 404,json.encode({message='Not found'})
end
return Host
