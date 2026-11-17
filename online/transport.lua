-- Main-thread side of the network worker (LÖVE only).
local Transport={}
Transport.__index=Transport
function Transport.new(prefer)
  local self=setmetatable({pending={},serial=0,backend='starting'},Transport)
  self.requests,self.answers=love.thread.newChannel(),love.thread.newChannel()
  self.thread=love.thread.newThread('online/http_thread.lua')
  self.thread:start(self.requests,self.answers,love.filesystem.getSaveDirectory(),prefer)
  -- The function handed to Api.new.
  self.send=function(req,done)
    self.serial=self.serial+1;self.pending[self.serial]=done
    self.requests:push({id=self.serial,method=req.method,url=req.url,headers=req.headers,body=req.body,timeout=req.timeout})
  end
  return self
end
-- Call once per frame: delivers finished requests to their callbacks.
function Transport:update()
  while true do
    local answer=self.answers:pop()
    if not answer then break end
    if answer.ready then self.backend=answer.backend
    else
      local done=self.pending[answer.id];self.pending[answer.id]=nil
      if done then done(answer.status,answer.body,answer.error) end
    end
  end
  local crashed=self.thread:getError()
  if crashed then
    for id,done in pairs(self.pending) do self.pending[id]=nil;done(nil,nil,'The network worker stopped: '..crashed) end
  end
end
function Transport:close() self.requests:push('quit') end
return Transport
