-- One online match as the game screens see it. It owns the mirror of the server's view,
-- sends the player's inputs, plays back the computer's moves at a readable pace, polls
-- while the other player is to move, and recovers from failed requests.
-- No LÖVE dependency: tests drive it with a synchronous transport.
local Mirror=require('online.mirror')
local Session={}
Session.__index=Session
-- opts.pace: seconds between computer moves shown. opts.poll / opts.idle_poll: seconds between
-- polls while waiting for the other player / while it is this player's move.
-- opts.retry: seconds before a failed request is tried again. opts.remember(text or nil).
function Session.new(api,opts)
  opts=opts or {}
  return setmetatable({api=api,phase='idle',mirror=Mirror.new(),queue={},wait=0,pollWait=0,retryWait=0,
    pace=opts.pace or 1.35,poll=opts.poll or 1.5,idle_poll=opts.idle_poll or 4,retry=opts.retry or 2,
    remember=opts.remember or function() end,on_frame=opts.on_frame,serial=0,token=tostring(opts.token or os.time())},Session)
end
function Session:notify(message) self.notice=message end
function Session:fail(err)
  self.phase='failed';self.error=err and err.message or 'The match could not be started.'
  self.code_error=err and err.code
end
-- The fields the battlefield reads, as with a local match.
function Session:adopt(view)
  self.state=self.mirror:apply(view)
  self.prompt=self.mirror.prompt
  self.seat=view.seat;self.controllers=view.controllers;self.mode=view.mode
  if self.on_frame then self.on_frame(self,self.mirror.draws) end
end
function Session:enqueue(view,log,delay)
  self.queue[#self.queue+1]={view=view,log=log or {},delay=delay or 0}
end
local function begin(self,reply)
  self.match,self.seq,self.code=reply.match,reply.seq,reply.code
  self.remember(reply.match)
  if reply.view then
    self.phase='playing';self.mirror:append_log(reply.log);self:adopt(reply.view)
  else self.phase='waiting';self.pollWait=self.poll end
end
local function open(self,body)
  self.phase='connecting';self.error=nil
  self.api:call(body,function(reply,err)
    if self.phase~='connecting' then return end
    if not reply then return self:fail(err) end
    begin(self,reply)
  end,40)
end
function Session:start_solo(player,ai,rules)
  open(self,{op='create',mode='solo',player=player,ai=ai,rules=rules})
end
function Session:open_room(player,rules)
  open(self,{op='create',mode='duel',player=player,rules=rules})
end
function Session:join_room(code,player,rules)
  open(self,{op='join',code=code,player=player,rules=rules})
end
-- Picks up a match from an earlier launch, or after the connection was lost for good.
function Session:resume(match)
  self.phase='connecting';self.error=nil;self.match=match;self.seq=-1
  self.api:state(match,-1,0,function(st,err)
    if self.phase~='connecting' then return end
    if not st then self.remember(nil);return self:fail(err) end
    if st.status=='waiting' then self.seq,self.code,self.phase=st.seq,st.code,'waiting';return end
    if not st.view then self.remember(nil);return self:fail({message='That match has ended.'}) end
    self.seq=st.seq;self.mirror:append_log(st.log);self:adopt(st.view);self:settle(st)
  end)
end
-- Applies the status the server reports for the match as a whole.
function Session:settle(st)
  if st.status=='abandoned' then
    self.phase='over';self.abandoned=true;self.left=st.left;self.remember(nil)
  elseif st.status=='finished' then
    -- The final position may still be waiting to be shown; showing it ends the match.
    self.remember(nil)
    if #self.queue==0 and self.state and self.state.finished then self.phase='over'
    elseif self.phase~='over' then self.phase='playing' end
  elseif st.status=='active' then self.phase='playing'
  elseif st.status=='waiting' then self.phase='waiting' end
  self.opponent_seen=st.opponent_seen
end
function Session:mine()
  local s=self.state
  if not s or self.phase~='playing' or s.finished then return false end
  local q=self.prompt
  if q then return q.actor==self.seat and not q.waiting end
  return s.active==self.seat
end
-- True while the player may give an input right now.
function Session:ready()
  return self:mine() and not self.sending and not self.pending_action and #self.queue==0
end
function Session:computer_to_move()
  local s=self.state
  return self.phase=='playing' and s and not s.finished and not self.prompt and self.controllers[s.active]=='AI'
end
local function absorb(self,reply)
  self.seq=reply.seq
  local have=#self.mirror.log+0
  for _,q in ipairs(self.queue) do have=have+#q.log end
  if reply.log_from and reply.log_from~=have then
    -- The record has a gap or an overlap: take the whole position from the server instead.
    self.queue={};self.seq=-1;self.pollWait=0;return
  end
  for i,frame in ipairs(reply.frames or {}) do
    local computer=self.pending_action.type=='advance' or i>1
    self:enqueue(frame.view,frame.log,computer and self.pace or 0)
  end
end
local function transmit(self)
  self.sending=true
  local action,id=self.pending_action,self.pending_id
  self.api:call({op='act',match=self.match,seq=self.seq,action=action,id=id},function(reply,err)
    if self.pending_id~=id then return end
    self.sending=false
    if reply then
      self.offline=false
      if reply.duplicate then self.seq=-1;self.pollWait=0 else absorb(self,reply) end
      self.pending_action,self.pending_id=nil,nil
    elseif err.code=='network' or err.code=='server' or err.code=='auth' then
      -- Unknown whether the server applied it. Ask for the position first, then decide.
      self.offline=true;self.retryWait=self.retry;self.resync=true
    else
      self.pending_action,self.pending_id=nil,nil
      if err.code=='stale' or err.code=='conflict' or err.code=='not_active' or err.code=='not_found' then
        self.seq=-1;self.pollWait=0
        if err.code=='not_found' then self.phase='over';self.abandoned=true;self.remember(nil) end
      elseif err.code=='rules_mismatch' then
        -- The server's rules were replaced during the match; it cannot be continued.
        self:notify(err.message);self.queue={};self.phase='over';self.abandoned=true;self.remember(nil)
      else self:notify(err.message) end
    end
  end,40)
end
-- action: {type="play",index=,row=,pos=} | {type="pass"|"end"|"school"} | {type="choose",index=}
function Session:act(action)
  if not self:ready() then return false,self.sending and 'Still sending your last move.' or 'It is not your move.' end
  self.serial=self.serial+1
  self.pending_action,self.pending_id=action,self.token..'-'..self.serial
  transmit(self)
  return true
end
function Session:choose(index) return self:act({type='choose',index=index}) end
function Session:leave()
  if self.match and (self.phase=='waiting' or self.phase=='playing' or self.phase=='connecting') then
    self.api:call({op='leave',match=self.match},function() end)
  end
  self.remember(nil);self.phase='idle';self.pending_action,self.pending_id=nil,nil
end
local function refresh(self)
  if self.polling then return end
  self.polling=true
  local asked=self.seq
  self.api:state(self.match,self.seq,#self.mirror.log,function(st,err)
    self.polling=false
    if self.phase=='idle' then return end
    if not st then
      if err.code=='not_found' then self.phase='over';self.abandoned=true;self.remember(nil);return end
      self.offline=true;self.retryWait=self.retry;return
    end
    self.offline=false
    local resync=self.resync;self.resync=false
    if st.seq~=asked and st.view then
      -- Something happened that this client has not shown yet.
      if asked==-1 then self.queue={} end
      local log=st.log or {}
      if st.log_from and st.log_from<#self.mirror.log then
        local skip=#self.mirror.log-st.log_from;local rest={}
        for i=skip+1,#log do rest[#rest+1]=log[i] end
        log=rest
      end
      self.seq=st.seq;self:enqueue(st.view,log,0)
      if resync then self.pending_action,self.pending_id=nil,nil end
    elseif st.seq~=asked then self.seq=st.seq
    elseif resync and self.pending_action then transmit(self) end
    self.code=st.code or self.code
    self:settle(st)
  end)
end
function Session:update(dt)
  if self.phase~='waiting' and self.phase~='playing' and self.phase~='over' then return end
  -- Show what has arrived, one step at a time.
  if #self.queue>0 then
    self.wait=self.wait+dt
    local nextFrame=self.queue[1]
    if self.wait>=nextFrame.delay then
      table.remove(self.queue,1);self.wait=0
      self.mirror:append_log(nextFrame.log);self:adopt(nextFrame.view)
      if self.state.finished then self.phase='over';self.remember(nil) end
    end
  else self.wait=0 end
  if self.phase=='over' then return end
  if self.offline then
    self.retryWait=self.retryWait-dt
    if self.retryWait<=0 then self.retryWait=self.retry;refresh(self) end
    return
  end
  if self.sending then return end
  if self.seq==-1 then return refresh(self) end
  if self.phase=='playing' and self.mode=='solo' then
    -- The computer moves in short batches; ask for the next one as soon as the last arrived.
    local last=self.queue[#self.queue]
    local pending=last and last.view or nil
    local computer
    if pending then computer=not pending.finished and not pending.prompt and pending.controllers[pending.active]=='AI'
    else computer=self:computer_to_move() end
    if computer and not self.pending_action then
      self.serial=self.serial+1
      self.pending_action,self.pending_id={type='advance'},self.token..'-'..self.serial
      transmit(self)
    end
    return
  end
  -- Two players: poll, quickly while waiting for the other side.
  self.pollWait=self.pollWait-dt
  if self.pollWait<=0 then
    self.pollWait=(self.phase=='waiting' or not self:mine()) and self.poll or self.idle_poll
    refresh(self)
  end
end
return Session
