-- The host can supply a configuration and receive Battle.report on completion.
-- A suspended chooser retains the resolution stack while the UI gathers input.
local B=require('battle')
local AI=require('ai')
local Library=require('tabletop.library')
local Match={}
Match.__index=Match
function Match.new(cfg,seed,on_finish)
  for p=1,2 do local ok,why=Library.valid(cfg,p);assert(ok,why) end
  local m=setmetatable({controllers={cfg.controllers[1],cfg.controllers[2]},
    seed=seed or cfg.seed or os.time(),mode=cfg.mode,on_finish=on_finish},Match)
  m.draws={}
  m.state=B.new(cfg.decks[1],cfg.decks[2],{seed=m.seed,
    on_draw=function(event) m.draws[#m.draws+1]=event end,
    player_faction=cfg.factions[1],ai_faction=cfg.factions[2],names={"Seat 1","Seat 2"},
    chooser=function(_,actor,kind,options,context)
      if m.controllers[actor]=="AI" then return nil end
      if #options==1 and kind~="order" and not (context and (context.cards or context.optional)) then return 1 end
      return coroutine.yield({actor=actor,kind=kind,options=options,context=context or {}})
    end})
  if m.state.finished and on_finish then on_finish(B.report(m.state)) end
  return m
end
function Match:resume(index)
  local ok,value,why=coroutine.resume(self.task,index)
  if not ok then error(debug.traceback(self.task,tostring(value))) end
  if coroutine.status(self.task)=="suspended" then self.prompt=value;return true end
  self.task,self.prompt=nil,nil
  if self.state.finished and self.on_finish then self.on_finish(B.report(self.state)) end
  return value,why
end
function Match:act(action)
  if self.task or self.state.finished then return false,"Finish the pending choice first." end
  local s,p=self.state,self.state.active
  self.task=coroutine.create(function()
    if action.type=="ai" then return AI.step(s,p) end
    if action.type=="pass" then return B.pass(s,p) end
    if action.type=="end" then return B.end_extra(s,p) end
    if action.type=="school" then return B.school(s,p) end
    return B.play(s,p,action.index,action.row,action.pos)
  end)
  return self:resume()
end
function Match:choose(index)
  if not self.prompt or not (self.prompt.options[index] or index==0 and self.prompt.context.optional) then return false,"Choose a listed target." end
  self.prompt=nil
  return self:resume(index)
end
return Match
