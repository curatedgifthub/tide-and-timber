-- Client side: turns the view sent by the server into a table shaped like the engine's
-- battle state, so the battlefield screens and the rule helpers that only read public
-- information (Battle.strength, Battle.playable, Chains.find) work on it unchanged.
-- Hidden cards exist only as a count: the opposing hand and both draw decks are lists of
-- blank placeholders.
local C=require('data.cards')
local Mirror={}
Mirror.__index=Mirror
local blank={hidden=true}
function Mirror.new() return setmetatable({cache={},log={},state=nil,seat=nil},Mirror) end
-- One table per card instance for the whole match, so a selected card stays selected.
function Mirror:instance(t,side)
  local u=self.cache[t.u]
  local card=C.by_id[t.c]
  if not card then error('Unknown card '..tostring(t.c)..'. This copy of the game is out of date.') end
  if not u or u.card~=card then u={uid=t.u,card=card,activated={}};self.cache[t.u]=u end
  u.owner=t.o;u.controller=side or t.o
  u.hp=t.hp;u.mod=t.mod or 0;u.guard=t.g or 0
  u.negate_damage=t.nd or false;u.disabled=t.dis or false
  u.activated.chain=t.ch or nil
  return u
end
local function blanks(n)
  local t={};for i=1,n do t[i]=blank end;return t
end
function Mirror:option(v)
  if type(v)~='table' then return v end
  if v.units then
    local units={}
    for i,id in ipairs(v.units) do units[i]=self.cache[id] or self:instance(v.cards[i]) end
    return {units=units,length=v.length,cross=v.cross or false,direction=v.direction}
  end
  local u=self.cache[v.u] or self:instance(v)
  if v.chain then return {unit=u,chain=self:option(v.chain)} end
  return u
end
-- Applies a view. Returns the state table (the same one on every call).
function Mirror:apply(v)
  local s=self.state or {players={{},{}},max_hand=math.huge,log=self.log}
  self.state,self.seat=s,v.seat
  s.last_attack=v.lastAttack
  s.round,s.active,s.finished,s.winner=v.round,v.active,v.finished or false,v.winner
  s.plays_left,s.extra_turn=v.plays,v.extra or false
  s.school_used={[1]=v.school[1],[2]=v.school[2]}
  for p=1,2 do
    local t,pl=v.players[p],s.players[p]
    pl.name,pl.faction,pl.wins,pl.passed=t.name,t.faction,t.wins,t.passed or false
    pl.flood=t.flood;pl.search_notice=t.searchNotice
    pl.deck=blanks(t.deck)
    pl.rows={{},{}}
    for r=1,2 do for i,u in ipairs(t.rows[r]) do pl.rows[r][i]=self:instance(u,p) end end
    pl.discard={}
    for i,c in ipairs(t.discard) do pl.discard[i]=self:instance(c) end
    if t.cards then
      pl.hand={}
      for i,c in ipairs(t.cards) do pl.hand[i]=self:instance(c,p) end
    else pl.hand=blanks(t.hand) end
  end
  s.round_history={}
  for i,r in ipairs(v.history) do s.round_history[i]={round=r.round,scores=r.scores,winner=r.winner,reason=r.reason,passes=r.passes} end
  -- The last card played is usually on a battlefield or in a discard pile already.
  s.last_played=v.last and (self.cache[v.last.u] or self:instance(v.last)) or nil
  local q=v.prompt
  if q and q.kind then
    local options={}
    for i,o in ipairs(q.options) do options[i]=self:option(o) end
    local ctx={op=q.context.op,optional=q.context.optional,enemy=q.context.enemy,bottom=q.context.bottom,row=q.context.row,source=q.context.source,note=q.context.note,profile=q.context.profile}
    if q.context.cards then
      ctx.cards={}
      for i,c in ipairs(q.context.cards) do ctx.cards[i]=self.cache[c.u] or self:instance(c) end
    end
    if q.context.unit then ctx.unit=self.cache[q.context.unit.u] or self:instance(q.context.unit) end
    self.prompt={actor=q.actor,kind=q.kind,options=options,context=ctx}
  elseif q then self.prompt={actor=q.actor,waiting=true,options={},context={}}
  else self.prompt=nil end
  self.draws={}
  for i,d in ipairs(v.draws or {}) do
    local cards={}
    for j,c in ipairs(d.cards or {}) do cards[j]=self.cache[c.u] or self:instance(c) end
    self.draws[i]={seat=d.seat,source=d.source,count=d.n,cards=cards,before=d.before,remaining=d.remaining,
      reason=d.reason,requested=d.requested}
  end
  return s
end
function Mirror:append_log(lines)
  for _,line in ipairs(lines or {}) do self.log[#self.log+1]=line end
end
return Mirror
