local Text=require('tabletop.card_text')
local P=require('tabletop.paint')
local Lib=require('tabletop.library')
local B=require('battle')
local Chains=require('chains')
local V={}
-- The battlefield is always drawn from the player's own seat: their rows and hand at the
-- bottom, the other side on top. The state is the mirror of the server's view, so the
-- other hand and both draw decks are only counts.
local Placement=require('tabletop.placement')
-- The hand card the player has picked up, if it is a Unit that still needs a position.
local function picked(app)
  local m=app.match
  local u=app.selected and m.state.players[m.seat].hand[app.selected]
  if u and u.card.type=="Unit" and not u.card.replaces and m:ready() and not m.prompt then return u end
end
local function row(app,p,r,y,chains)
  local m=app.match;local s=m.state;local pl=s.players[p];local spec=Lib.specs[pl.faction]
  local cards=pl.rows[r];local x,w,h=28,876,88
  local key=p.."-"..r
  local page=math.max(1,math.min(math.max(1,math.ceil(#cards/7)),app.rowPages[key] or 1))
  local start=(page-1)*7+1
  local stop=math.min(#cards,start+6)
  local unit=picked(app)
  -- A Double Agent is deployed on the other player's rows.
  local placing=unit and B.deploy_side(m.seat,unit.card)==p and B.placement_row(unit.card)==r
  local gift=placing and p~=m.seat
  P.box(x,y,w,h,P.panel);P.border(x,y,w,h,placing and P.gold or P.rule,placing and .82 or .65)
  P.box(x,y,4,h,spec.color)
  P.label(app:who(p),x+14,y+10,spec.color)
  P.text(r==1 and "Front" or "Back",x+14,y+28,24,P.textColor,"serif")
  P.line(x+94,y+9,x+94,y+79,P.rule)
  local left=x+119;local available=w-145
  if placing and app.previewUnit~=unit then
    app.previewUnit,app.previews=unit,{{},{}}
    for ri,lane in ipairs(pl.rows) do for i=1,#lane+1 do
      app.previews[ri][i]=Placement.preview(pl,ri,i,unit.card)
    end end
  end
  local function hint(i)
    local ch=app.previews[r][i]
    local preview=ch and (ch.cross and "Bridge chain " or "Chain ")..ch.length or Placement.bonus(unit.card,r)
    if ch then preview=preview.." · +1 Guard" end
    if unit.card.chain then
      preview=(preview and preview.." · " or "")..(ch and ch.length>=unit.card.chain and "Activates Chain " or "Needs Chain ")..unit.card.chain
    end
    if not preview and unit.card.bridge and i==#cards+1 then preview="Bridge end" end
    if gift then return "Position "..i.."   ·   "..(preview and "Gives the other side a "..preview or unit.card.name.." joins the other side") end
    return "Position "..i.."   ·   "..(preview or "Deploy "..unit.card.name)
  end
  if #cards==0 then
    if placing then
      local hot=P.inside(left,y,available,h)
      P.box(left,y+9,available-5,h-18,spec.color,hot and .16 or .05)
      local ch=app.previews[r][1]
      local target=ch and ch.cross and "+   Bridge chain "..ch.length or unit.card.bridge and "+   Bridge end" or Placement.bonus(unit.card,r)
      P.text(target or (gift and "+   Send your agent here" or "+   Deploy here"),left,y+30,20,hot and P.bright or P.gold,"serif",available,"center")
      if hot then app.placeHint=hint(1) end
      P.hit("slot-"..key.."-1",left,y,available,h,function() app:action({type="play",index=app.selected,row=r,pos=1}) end)
    else
      P.line(left+available*.34,y+44,left+available*.48,y+44,P.rule,.65)
      P.diamond(left+available*.50,y+44,4,P.rule)
      P.line(left+available*.52,y+44,left+available*.66,y+44,P.rule,.65)
    end
  else
    local columns=math.min(7,math.max(#pl.rows[1],#pl.rows[2]))
    local pitch=math.min(139,(available-16)/columns)
    local cw=pitch-19
    for i=start,stop do
      local u=cards[i];local xx=left+10+(i-start)*pitch
      P.card(u.card,xx,y+3,cw,82,{chain=chains[u],linked=app.bridgeEnds[u],disabled=u.disabled,
        strength=B.strength(s,u),hp=u.hp,selected=app.inspected==u})
      if app.flash[u.uid] and app.flashTime>0 then P.border(xx-1,y+2,cw+2,84,P.bright,math.min(1,app.flashTime)) end
      if i>start and app.chainEdges[cards[i-1].uid.."/"..u.uid] then
        P.line(xx-18,y+44,xx-2,y+44,spec.color)
        P.diamond(xx-10,y+44,3,spec.color,true)
      end
      P.hit("unit-"..u.uid,xx,y+4,cw,80,function() app.inspected=u end,
        function() app.hovered=u end)
    end
    if placing then
      for i=start,stop+1 do
        local xx=left-7+(i-start)*pitch
        local hot=P.inside(xx,y+3,17,82);P.box(xx+6,y+8,hot and 4 or 2,h-16,P.gold,hot and 1 or .55)
        P.diamond(xx+7,y+44,hot and 8 or 5,P.gold,true)
        local ch=app.previews[r][i]
        local label=ch and ch.cross and "LINK" or unit.card.bridge and i==#cards+1 and "END"
        if label then
          P.one(label,xx-2,y+58,22,10,P.gold,"bold","center")
        end
        if hot then app.placeHint=hint(i) end
        P.hit("slot-"..key.."-"..i,xx,y+3,17,82,function() app:action({type="play",index=app.selected,row=r,pos=i}) end)
      end
    end
    if #cards>7 then
      local bx=x+w-27
      P.button("row-back-"..key,"‹",bx,y+5,24,35,function() app.rowPages[key]=page-1 end,nil,page>1)
      P.button("row-more-"..key,"›",bx,y+46,24,35,function() app.rowPages[key]=page+1 end,nil,stop<#cards)
    end
  end
end
local function scoreBar(app,p,x)
  local m=app.match;local s=m.state;local pl=s.players[p];local spec=Lib.specs[pl.faction]
  P.icon(spec.emblem,x+16,102,12,spec.color)
  -- pl.name is how the battle record refers to this seat.
  P.label(app:who(p).."   /   "..pl.name,x+38,80,spec.color)
  P.one(Lib.label(pl.faction)..(pl.flood and " · Flood −"..pl.flood or ""),x+38,94,133,22,P.textColor,"serif")
  local score=s.finished and #s.round_history>0 and s.round_history[#s.round_history].scores[p] or B.score(s,p)
  P.one(score,x+165,83,51,41,P.textColor,"serif","right")
  P.text("HP",x+223,107,12,P.muted,"bold")
  for i=1,2 do P.diamond(x+270+(i-1)*16,104,5,i<=pl.wins and P.gold or P.rule,i<=pl.wins) end
  P.text("Draw "..#pl.deck,x+7,139,15,P.muted)
  P.button("pile-"..p,"Discard "..#pl.discard,x+78,134,99,26,function() app:pile(p,"discard") end)
  P.button("hand-"..p,"Hand "..#pl.hand,x+184,134,85,26,function() app:pile(p,"hand") end)
  local top=pl.discard[#pl.discard]
  P.box(x+311,84,48,48,P.inset);P.border(x+311,84,48,48,P.rule)
  if top then P.art(top.card,x+314,87,42,42)
  else P.icon("cards",x+335,108,14,P.rule) end
  P.hit("discard-art-"..p,x+311,84,48,48,function() app:pile(p,"discard") end)
  if pl.passed then P.label("Passed",x+283,140,P.gold) end
end
local function inspector(app,u)
  local x,y,w=925,84,328
  P.box(x,y,w,328,P.panel);P.border(x,y,w,328,P.rule)
  P.label("Card inspection",x+15,y+12,P.gold)
  if not u then
    P.icon("cards",x+w/2,y+105,43,P.rule)
    P.text("Inspect a card",x+14,y+179,27,P.textColor,"serif",w-28,"center")
    P.text("Select a face-up card to read its abilities and current statistics.",x+34,y+222,18,P.muted,"sans",w-68,"center");return
  end
  local c=u.card;local spec=Lib.specs[c.faction]
  P.box(x+14,y+33,w-28,103,spec.paper);P.art(c,x+18,y+36,w-36,97)
  P.one(c.display_name or c.name,x+15,y+140,w-30,23,P.textColor,"serif")
  local value=u.hp and B.strength(app.match.state,u) or c.strength
  local stats=Text.stats(c,value,u.hp)
  if c.strength and value~=c.strength then stats=stats.."   (base "..c.strength.." ATK)" end
  P.one(stats,x+15,y+170,w-30,16,P.textColor,"bold")
  local ability=c.designation and Text.rows(c).."\n"..c.text or c.text
  local top=y+197;local size=16
  while size>11 do
    local _,lines=P.font(size):getWrap(ability,w-30)
    if top+#lines*P.font(size):getHeight()<=y+296 then break end
    size=size-1
  end
  P.text(ability,x+15,top,size,P.textColor,"sans",w-30)
  local tags={}
  if c.chain and u.hp then
    local chain=Chains.qualify(app.match.state.players[u.controller],u,3,false)
    tags[#tags+1]=u.activated.chain and "Chain used" or ((chain and "Chain "..chain.length or "No chain").." · needs "..c.chain)
  end
  if (u.guard or 0)>0 then tags[#tags+1]="Guard "..u.guard end
  if u.negate_damage then tags[#tags+1]="Barrier" end
  if u.disabled then tags[#tags+1]="Suppressed" end
  if u.hp and u.mod~=0 then tags[#tags+1]=string.format("%+d ATK",u.mod) end
  if u.hp and u.owner~=u.controller then tags[#tags+1]="Traded" end
  if #tags>0 then P.one(table.concat(tags,"  ·  "),x+15,y+303,w-30,15,P.gold,"bold") end
end
local function battleLog(app)
  local log=app.match.state.log;local x,y,w=925,423,328
  P.box(x,y,w,184,P.panel);P.border(x,y,w,184,P.rule)
  P.label("Battle record",x+15,y+13,P.gold)
  P.button("full-log","View all",x+w-88,y+7,74,26,function() app:log() end)
  local yy=y+46
  if app.match.state.last_attack then
    local _,lines=P.font(15):getWrap(app.match.state.last_attack,w-49)
    P.text(app.match.state.last_attack,x+15,yy,15,P.gold,"sans",w-49)
    yy=yy+#lines*P.font(15):getHeight()+6
  end
  for i=#log,math.max(1,#log-3),-1 do
    local msg=Text.event(log[i]); P.diamond(x+19,yy+9,3,i==#log and P.gold or P.rule,true)
    local font=P.font(15);local _,lines=font:getWrap(msg,w-49)
    for j=1,math.min(#lines,2) do
      if yy+18>y+181 then return end
      P.text(lines[j],x+33,yy,15,i==#log and P.textColor or P.muted);yy=yy+18
    end
    yy=yy+6
  end
end
-- What the player is waiting for, when it is not their move.
local function waiting(app)
  local m=app.match;local s=m.state
  if m.phase=="over" then return m.abandoned and "Match closed" or "Match complete" end
  if m.offline then return "Connection lost. Trying again…" end
  if m.sending or m.pending_action then return "Sending your move…" end
  if #m.queue>0 then return "Resolving…" end
  local q=m.prompt
  local other=q and q.actor or s.active
  if other==m.seat then return nil end
  if m.controllers[other]=="AI" then return "Computer is considering its play…" end
  return q and "Your opponent is making a choice…" or "Waiting for your opponent…"
end

function V.draw(app)
  local m=app.match;local s=m.state;local me=m.seat;local foe=3-me
  app.hovered,app.placeHint=nil,nil
  P.header("Battlefield")
  P.one(Lib.modes[m.mode=="duel" and 2 or 1].name..(m.code and "   ·   Room "..m.code or ""),455,29,268,13,P.muted,"bold","right")
  P.button("rounds","Round "..s.round.." / 3",738,18,140,36,function() app:rounds() end)
  P.button("row-guide","Combat & Bridge",884,18,147,36,function()
    app:list("Combat & Bridge","Choose where to deploy a unit.",Placement.guide)
  end)
  P.button("match-menu","Match menu",1044,18,209,36,function() app:matchMenu() end)
  scoreBar(app,foe,34);scoreBar(app,me,535)
  P.one("vs",432,95,57,25,P.gold,"italic","center")
  local chainMap={{},{}}
  local longest=0;local bridge=false
  app.chainEdges,app.bridgeEnds={},{}
  for p=1,2 do
    for _,ch in ipairs(Chains.find(s.players[p])) do
      longest=math.max(longest,ch.length);bridge=bridge or ch.cross
      for i,u in ipairs(ch.units) do
        chainMap[p][u]=true
        local previous=ch.units[i-1]
        if previous then
          app.chainEdges[previous.uid.."/"..u.uid]=true
          app.chainEdges[u.uid.."/"..previous.uid]=true
        end
      end
      if ch.cross then
        for _,lane in ipairs(s.players[p].rows) do app.bridgeEnds[lane[#lane]]=true end
      end
    end
  end
  row(app,foe,2,172,chainMap[foe]);row(app,foe,1,265,chainMap[foe])
  P.line(28,367,346,367,P.rule);P.line(592,367,904,367,P.rule)
  P.one(longest>0 and ("CHAIN "..longest..(bridge and "   /   BRIDGE" or "")) or "◆     BATTLE LINE     ◆",351,358,235,13,longest>0 and P.gold or P.muted,"bold","center")
  row(app,me,1,381,chainMap[me]);row(app,me,2,474,chainMap[me])
  local hand=s.players[me].hand
  local mine=m:ready() and not m.prompt
  local chosen=mine and app.selected and hand[app.selected]
  P.label("Your "..Lib.label(s.players[me].faction).." hand   ·   "..#hand.." cards",30,581,P.gold)
  local guidance=app.placeHint or waiting(app)
    or chosen and (chosen.card.type=="Effect" and "Choose Play effect to resolve."
      or chosen.card.replaces and "Choose Play onto "..Lib.cards.by_id[chosen.card.replaces].name.." to resolve."
      or chosen.card.agent and "Choose a gold marker on the opposing battlefield."
      or chosen.card.bridge and "Place at a right end to link Front and Back."
      or Placement.bonus(chosen.card,2) and "Back row bonus · "..Placement.bonus(chosen.card,2)
      or Text.rows(chosen.card))
    or "Play a unit to place it and attack."
  local perPage=app.handPageSize
  local pages=math.max(1,math.ceil(#hand/perPage))
  local page=math.min(pages,app.handPages[me])
  app.handPages[me]=page
  local first=(page-1)*perPage+1
  local last=math.min(first+perPage-1,#hand)
  P.one(guidance,343,577,pages>1 and 355 or 559,17,P.textColor,"sans","right")
  if pages>1 then
    P.button("hand-prev","‹",715,571,34,30,function() app.handPages[me]=page-1 end,nil,page>1)
    P.one(first.."–"..last.." / "..#hand,752,578,110,14,P.muted,"bold","center")
    P.button("hand-next","›",869,571,34,30,function() app.handPages[me]=page+1 end,nil,page<pages)
  end
  for i=first,last do
    local u=hand[i]
    local x=29+(i-first)*110;local selected=mine and app.selected==i;local yy=selected and 607 or 614
    local cw=104
    P.card(u.card,x,yy,cw,146,{selected=selected,fresh=app.freshCards[me][u.uid]})
    P.hit("handcard-"..i,x,yy,cw,146,function()
      app.inspected=u
      if mine then
        local ok,why=B.playable(s,me,i)
        if ok then app.selected=app.selected~=i and i or nil else app.selected=nil;app:notice(why) end
      end
    end,function() app.hovered=u end)
  end
  if #hand==0 then P.text("Hand empty",30,649,23,P.muted,"italic") end
  if s.players[me].search_notice then
    P.box(28,767,1225,29,P.panel)
    P.one(s.players[me].search_notice,40,771,1199,16,P.gold)
  elseif app.drawReceipt then
    local event=app.drawReceipt
    local inspect=#event.cards>0
    P.box(28,767,1225,29,P.panel);P.box(28,767,3,29,P.gold)
    P.one(app:drawMessage(),40,771,inspect and 1050 or 1199,16,P.textColor)
    if inspect then P.button("inspect-draw","View hand   ›",1113,769,137,25,function() app:pile(event.seat,"hand") end,"accent") end
  end
  inspector(app,app.hovered or app.inspected)
  battleLog(app)
  local x,y=925,622
  local actor=m.prompt and m.prompt.actor or s.active
  local passStatus=s.players[foe].passed and (app:who(foe).." passed. Play on or pass to score.")
    or s.players[me].passed and ("You passed. "..app:who(foe).." may keep playing.")
  P.one(passStatus or ("Turn   /   "..app:who(actor)),x,y,328,passStatus and 18 or 15,P.gold,"bold")
  local previous=s.round_history[#s.round_history]
  if previous and previous.passes then
    P.one("Round "..previous.round.." · "..app:roundEnding(previous),x,y+128,328,13,P.muted)
  end
  if not passStatus and m.mode=="duel" and m.phase=="playing" and (m.opponent_seen or 0)>30 then
    P.one("Opponent last seen "..math.floor(m.opponent_seen).." s ago",x+120,y,208,12,P.red,"bold","right")
  end
  if m.phase=="over" then
    P.button("result","Match result",x,y+27,328,48,function() app:result() end,"gold")
  elseif mine then
    if B.can_school(s,me) then P.button("school","School of Goldfish",x,y+27,328,44,function() app:action({type="school"}) end,"gold")
    elseif chosen and chosen.card.type=="Effect" then P.button("play-effect","Play effect   →",x,y+27,328,44,function() app:action({type="play",index=app.selected}) end,"gold")
    elseif chosen and chosen.card.replaces then
      P.button("play-effect","Play onto "..Lib.cards.by_id[chosen.card.replaces].name.."   →",x,y+27,328,44,function() app:action({type="play",index=app.selected}) end,"gold")
    elseif s.extra_turn then P.button("end-extra","End extra plays",x,y+27,328,44,function() app:action({type="end"}) end)
    else P.button("manual-help",chosen and "Choose a row position" or "Select a hand card",x,y+27,328,44,nil,nil,false) end
    P.button("pass","Pass round",x,y+80,328,44,function()
      app:list("Pass for this round?","Your opponent can keep playing. Remaining Health decides the round.",{
        {title="Keep playing",action=function() app.modal=nil end},
        {title="Pass round",action=function() app:action({type="pass"}) end}})
    end,"accent")
  else
    P.button("manual-help",waiting(app) or "Answer the question",x,y+27,328,44,nil,nil,false)
    P.one(m.mode=="duel" and "Every move is checked and dealt by the game server." or "The computer plays on the game server.",x,y+85,328,14,P.muted,"sans")
  end
end
return V
