-- The game's side of the Supabase project: an anonymous sign-in that is kept between
-- launches, the "game" Edge Function (create, join, act, leave) and the match_state RPC
-- used for polling. Everything is asynchronous: each call takes done(result, err), where
-- err is {code=..., message=...} and code "network" means the request never got an answer.
local json=require('online.json')
local Api={}
Api.__index=Api
-- opts.url, opts.key: project URL and publishable (anon) key. Never a service-role key.
-- opts.transport(request, done): sends {method,url,headers,body,timeout}, calls done(status, body, err).
-- opts.load() / opts.save(text): where the sign-in is remembered. opts.clock(): seconds.
function Api.new(opts)
  local self=setmetatable({url=(opts.url or ''):gsub('/+$',''),key=opts.key,transport=opts.transport,
    load=opts.load or function() end,save=opts.save or function() end,clock=opts.clock or os.time,
    session=nil,waiting=nil},Api)
  local saved=json.decode(self.load() or '')
  if type(saved)=='table' and type(saved.access_token)=='string' and type(saved.refresh_token)=='string'
    and type(saved.expires_at)=='number' and saved.url==self.url then self.session=saved end
  return self
end
function Api:configured() return self.url:find('^https?://')~=nil and type(self.key)=='string' and self.key~='' end

local function explain(r)
  local d=type(r.data)=='table' and r.data or {}
  local text=d.msg or d.message or d.error_description or (type(d.error)=='string' and d.error) or nil
  if d.error_code=='anonymous_provider_disabled' then
    return 'Anonymous sign-ins are disabled for this Supabase project. Enable them under Authentication > Sign In / Providers.'
  end
  if r.status==404 then return 'The game server is not deployed on this Supabase project.' end
  if r.status==540 or r.status==503 and not text then return 'The Supabase project is paused or starting. Try again in a minute.' end
  return (text or 'The server did not answer properly')..' (HTTP '..tostring(r.status)..').'
end
function Api:send(path,body,auth,done,timeout)
  local headers={apikey=self.key,['Content-Type']='application/json'}
  if auth then headers.Authorization='Bearer '..self.session.access_token end
  self.transport({method='POST',url=self.url..path,headers=headers,body=json.encode(body),timeout=timeout or 25},
    function(status,text,err)
      if not status then return done(nil,{code='network',message=err or 'No connection to the server.'}) end
      done({status=status,data=json.decode(text or ''),text=text})
    end)
end
function Api:adopt(data)
  self.session={access_token=data.access_token,refresh_token=data.refresh_token,url=self.url,
    expires_at=self.clock()+(tonumber(data.expires_in) or 3600),user=type(data.user)=='table' and data.user.id or nil}
  self.save(json.encode(self.session))
end
-- Makes sure there is a sign-in that is valid for at least another minute.
-- Callers that arrive while a sign-in or refresh is in flight wait for it, so a refresh
-- token is never used twice.
function Api:authorize(done)
  local s=self.session
  if s and s.expires_at-self.clock()>60 then return done(true) end
  if self.waiting then self.waiting[#self.waiting+1]=done;return end
  self.waiting={done}
  local function finish(ok,err)
    local list=self.waiting;self.waiting=nil
    for _,fn in ipairs(list) do fn(ok,err) end
  end
  local function signup()
    self:send('/auth/v1/signup',json.object({data=json.object({})}),false,function(r,err)
      if not r then return finish(false,err) end
      if r.status==200 and type(r.data)=='table' and r.data.access_token then self:adopt(r.data);return finish(true) end
      finish(false,{code='auth',message=explain(r)})
    end)
  end
  if s and s.refresh_token then
    self:send('/auth/v1/token?grant_type=refresh_token',{refresh_token=s.refresh_token},false,function(r,err)
      if not r then return finish(false,err) end
      if r.status==200 and type(r.data)=='table' and r.data.access_token then self:adopt(r.data);return finish(true) end
      -- The saved sign-in was refused: start again as a new anonymous player.
      self.session=nil;signup()
    end)
  else signup() end
end
local function authorized(self,path,body,done,timeout,retried)
  self:authorize(function(ok,err)
    if not ok then return done(nil,err) end
    self:send(path,body,true,function(r,err2)
      if not r then return done(nil,err2) end
      if r.status==401 and not retried then
        self.session.expires_at=0
        return authorized(self,path,body,done,timeout,true)
      end
      if r.status~=200 or r.data==nil then return done(nil,{code='server',message=explain(r)}) end
      done(r.data)
    end,timeout)
  end)
end
-- body: {op="hello"|"create"|"join"|"act"|"leave", ...}
function Api:call(body,done,timeout)
  authorized(self,'/functions/v1/game',body,function(data,err)
    if not data then return done(nil,err) end
    if type(data)~='table' then return done(nil,{code='server',message='The server sent an unreadable answer.'}) end
    if data.ok==false then return done(nil,{code=data.error or 'server',message=data.message or 'The server refused the request.',data=data}) end
    done(data)
  end,timeout)
end
-- The cheap poll: answers with only the sequence number while nothing has changed.
function Api:state(match,seq,log,done)
  authorized(self,'/rest/v1/rpc/match_state',{p_match=match,p_seq=seq,p_log=log},function(data,err)
    if not data then return done(nil,err) end
    if type(data)~='table' or data.error then
      return done(nil,{code=type(data)=='table' and data.error or 'server',message='That match is no longer available.'})
    end
    done(data)
  end,12)
end
return Api
