-- What one seat is entitled to know about a battle (server side).
-- Public: both battlefields, both discard piles, hand and draw-deck sizes, scores, the record.
-- Private to a seat: the cards in its own hand, the cards an ability lets it examine, and
-- the names of the cards it draws. Nobody receives draw-deck contents or order, or the seed.
local View={}
local function card(u) return {u=u.uid,c=u.card.id,o=u.owner} end
local function unit(u)
  local t=card(u)
  t.hp=u.hp
  if u.mod and u.mod~=0 then t.mod=u.mod end
  if (u.guard or 0)>0 then t.g=u.guard end
  if u.negate_damage then t.nd=true end
  if u.disabled then t.dis=true end
  if u.activated and u.activated.chain then t.ch=true end
  return t
end
local function chain(ch)
  local ids,cards={},{}
  for i,u in ipairs(ch.units) do ids[i]=u.uid;cards[i]=card(u) end
  return {units=ids,cards=cards,length=ch.length,cross=ch.cross or nil,direction=ch.direction}
end
local function option(v)
  if type(v)~='table' then return v end
  if v.unit and v.chain then local t=card(v.unit);t.chain=chain(v.chain);return t end
  if v.units then return chain(v) end
  return card(v)
end
-- The full prompt goes only to the seat that has to answer it.
function View.prompt(q,seat)
  if not q then return nil end
  if q.actor~=seat then return {actor=q.actor} end
  local ctx=q.context
  local out={actor=q.actor,kind=q.kind,options={},
    context={op=ctx.op,optional=ctx.optional or nil,enemy=ctx.enemy or nil,bottom=ctx.bottom or nil,row=ctx.row}}
  for i,v in ipairs(q.options) do out.options[i]=option(v) end
  if ctx.cards then
    out.context.cards={}
    for i,c in ipairs(ctx.cards) do out.context.cards[i]=card(c) end
  end
  if ctx.unit then out.context.unit=card(ctx.unit) end
  return out
end
-- extra: seq, mode, controllers, prompt (engine prompt or nil), draws (engine draw events).
function View.build(s,seat,extra)
  local v={seat=seat,seq=extra.seq,mode=extra.mode,controllers=extra.controllers,
    round=s.round,active=s.active,finished=s.finished or nil,winner=s.winner,
    plays=s.plays_left,extra=s.extra_turn or nil,school={s.school_used[1] or false,s.school_used[2] or false},
    players={},history={},lastAttack=s.last_attack,last=s.last_played and card(s.last_played) or nil,
    prompt=View.prompt(extra.prompt,seat)}
  for p=1,2 do
    local pl=s.players[p]
    local t={name=pl.name,faction=pl.faction,wins=pl.wins,passed=pl.passed or nil,
      deck=#pl.deck,hand=#pl.hand,discard={},rows={{},{}}}
    if p==seat then
      t.cards={}
      for i,c in ipairs(pl.hand) do t.cards[i]=card(c) end
    end
    for i,c in ipairs(pl.discard) do t.discard[i]=card(c) end
    for r=1,2 do for i,u in ipairs(pl.rows[r]) do t.rows[r][i]=unit(u) end end
    v.players[p]=t
  end
  for i,r in ipairs(s.round_history) do v.history[i]={round=r.round,scores={r.scores[1],r.scores[2]},winner=r.winner,reason=r.reason} end
  if extra.draws and #extra.draws>0 then
    v.draws={}
    for i,e in ipairs(extra.draws) do
      local d={seat=e.seat,source=e.source,n=#e.cards,before=e.before,remaining=e.remaining,reason=e.reason,requested=e.requested}
      if e.seat==seat then
        d.cards={}
        for j,c in ipairs(e.cards) do d.cards[j]=card(c) end
      end
      v.draws[i]=d
    end
  end
  return v
end
return View
