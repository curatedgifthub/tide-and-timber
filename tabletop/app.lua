local Text=require('tabletop.card_text')
local P=require('tabletop.paint')
local Lib=require('tabletop.library')
local SetupView=require('tabletop.setup_view')
local BoardView=require('tabletop.board_view')
local B=require('battle')
local Api=require('online.api')
local Session=require('online.session')
local Transport=require('online.transport')
local Rules=require('online.rules')
local Config=require('online.config')
local App={}
App.__index=App
local function item(title,action,detail,card)
  return {title=title,action=action,detail=detail,card=card}
end
-- opts.url / opts.key: another server than online/config.lua (tests).
-- opts.profile: keeps a separate sign-in, so two copies can run on one computer.
function App.new(opts)
  opts=opts or {}
  local self=setmetatable({cfg=Lib.new(),screen="menu",page=1,filter="All",profile=opts.profile or ""},App)
  for p=1,2 do Lib.starter(self.cfg,p) end
  local signIn="online-session"..self.profile..".json"
  self.matchFile="online-match"..self.profile..".txt"
  self.transport=Transport.new(opts.http)
  self.api=Api.new({url=opts.url or Config.url,key=opts.key or Config.key,transport=self.transport.send,
    load=function() return (love.filesystem.read(signIn)) end,
    save=function(text) love.filesystem.write(signIn,text) end})
  self.rules=Rules.version(function(path) return (love.filesystem.read(path)) end,
    function(text) return love.data.encode("string","hex",love.data.hash("sha256",text)):lower() end)
  self:connect()
  return self
end
function App:notice(message) self.toast=message;self.toastTime=3.4 end
function App:list(title,subtitle,items,locked)
  self.modal={title=title,subtitle=subtitle,items=items,page=1,locked=locked}
end

-- Server ------------------------------------------------------------------------------
-- Checks that the server is reachable and plays by the same rules as this copy.
function App:connect()
  if not self.api:configured() then
    self.server={state="unconfigured",message="No game server is configured (online/config.lua)."};return
  end
  self.server={state="checking",message="Connecting to the game server…"}
  self.api:call({op="hello"},function(reply,err)
    if not reply then self.server={state="error",message=err.message};return end
    if reply.rules~=self.rules then
      self.server={state="mismatch",message="This copy of the game has different rules from the server. Update the game."}
      return
    end
    self.server={state="ok",message="Connected to the game server."}
    local saved=love.filesystem.read(self.matchFile)
    self.savedMatch=saved and saved:match("^[%w%-]+") or nil
  end)
end
function App:newSession()
  return Session.new(self.api,{token=self.profile..os.time(),
    remember=function(id)
      self.savedMatch=nil
      if id then love.filesystem.write(self.matchFile,id) else love.filesystem.remove(self.matchFile) end
    end,
    on_frame=function(session,draws) if session==self.match then self:frame(draws) end end})
end
local function seatDeck(cfg,p) return {faction=cfg.factions[p],deck=cfg.decks[p]} end
-- kind: "solo", "host", "join" (with a room code) or "resume".
function App:online(kind,code)
  if self.server.state~="ok" then self:notice(self.server.message);return end
  local c=self.cfg
  if kind~="resume" then
    local ok,why=Lib.valid(c,1)
    if not ok then self:notice("Your deck   ·   "..why);return end
    if kind=="solo" and not Lib.computer_ready(c) then
      self:notice("Computer deck   ·   "..select(2,Lib.valid(c,2)));return
    end
  end
  self.modal=nil;self.match=self:newSession()
  if kind=="solo" then
    self.match:start_solo(seatDeck(c,1),{faction=c.factions[2],deck=#c.decks[2]>0 and c.decks[2] or nil,difficulty=c.difficulty},self.rules)
  elseif kind=="host" then self.match:open_room(seatDeck(c,1),self.rules)
  elseif kind=="join" then self.match:join_room(code,seatDeck(c,1),self.rules)
  else self.match:resume(self.savedMatch) end
end
function App:joinDialog()
  self.modal={title="Join a room",subtitle="Type the six-character room code the other player gave you.",input="",
    placeholder="Room code",button="Join room",
    accept=function(text) return (text:upper():gsub("[^A-Z0-9]","")) end,limit=6,
    submit=function()
      local code=self.modal.input
      if #code~=6 then self:notice("A room code has six letters or digits.");return end
      self:online("join",code)
    end}
end
function App:closeMatch()
  if self.match then self.match:leave() end
  self.match=nil;self.modal=nil;self.screen="menu"
end

-- Setup -------------------------------------------------------------------------------
function App:builder(p)
  self.screen="builder";self.side=p;self.page=1;self.filter="All";self.modal=nil
  local f=self.cfg.factions[p];self.inspected=Lib.cards[f][Lib.specs[f].featured]
end
function App:cycleFaction(p,delta)
  local f=self.cfg.factions[p]
  local i=1;while Lib.factions[i]~=f do i=i+1 end
  self.drafts=self.drafts or {{},{}}
  self.drafts[p][f]=self.cfg.decks[p]
  local nextFaction=Lib.factions[(i-1+delta)%#Lib.factions+1]
  self.cfg.factions[p]=nextFaction
  if self.drafts[p][nextFaction] then self.cfg.decks[p]=self.drafts[p][nextFaction]
  else Lib.starter(self.cfg,p) end
end
function App:edit(c,delta)
  self.inspected=c
  local ok,why=Lib.edit(self.cfg,self.side,c.id,delta)
  if not ok then self:notice(why) end
end
function App:presets()
  local entries={}
  for i=1,5 do
    local file="table-preset-"..i..".txt"
    local raw=love.filesystem.read(file)
    local saved,why=Lib.decode(raw)
    local detail=saved and (Lib.label(saved.factions[1]).." "..#saved.decks[1].."   /   "..Lib.label(saved.factions[2]).." "..#saved.decks[2].."   ·   "..Lib.modes[saved.mode].name
      ..(#saved.removed>0 and "   ·   "..#saved.removed.." card(s) without artwork will be removed" or ""))
      or raw and why or "Empty slot"
    entries[#entries+1]=item("Preset "..i,function()
      local actions={}
      if saved then actions[#actions+1]=item("Load these decks",function()
        local removed=saved.removed or {};saved.removed=nil
        self.cfg=saved;self.drafts=nil;self:builder(1)
        if #removed>0 then
          local names={};for _,id in ipairs(removed) do names[#names+1]=Lib.cards.by_id[id].name end
          self:notice("Loaded preset "..i..". Removed "..#removed.." card(s) without artwork: "..table.concat(names,", "))
          self.toastTime=8
        else self:notice("Loaded preset "..i..".") end
      end,detail) end
      actions[#actions+1]=item(saved and "Replace with current setup" or "Save current setup",function()
        local ok,err=love.filesystem.write(file,Lib.encode(self.cfg))
        self.modal=nil;self:notice(ok and "Your deck, the computer's deck and the play mode saved in preset "..i.."." or tostring(err))
      end,"Both deck drafts and the play mode")
      actions[#actions+1]=item("Back to presets",function() self:presets() end)
      self:list("Preset "..i,detail,actions)
    end,detail)
  end
  self:list("Deck presets","Save or load your deck and the computer's deck together.",entries)
end

-- Battlefield -------------------------------------------------------------------------
-- "You", "Computer" or "Opponent": every player sees the table from their own seat.
function App:who(p)
  local m=self.match
  if p==m.seat then return "You" end
  return m.controllers[p]=="AI" and "Computer" or "Opponent"
end
function App:roundEnding(r)
  if not r.passes then return "" end
  local first,last=r.passes[1],r.passes[2]
  if last then return self:who(first).." passed, then "..self:who(last).." passed." end
  if first then return self:who(first).." passed. "..self:who(3-first).." ran out of plays and draws." end
  return "Both sides ran out of plays and draws."
end
function App:visible(p) return p==self.match.seat end
function App:snapshot()
  local vals={};local s=self.match.state
  for p=1,2 do for _,u in ipairs(B.units(s,p)) do vals[u.uid]=p.."/"..B.strength(s,u).."/"..u.hp.."/"..tostring(u.activated.chain) end end
  return vals
end
App.handPageSize=8
function App:enterBoard()
  self.screen="board";self.modal=nil;self.board=self.match
  self.inspected=nil;self.selected=nil;self.toast=nil;self.flash={};self.flashTime=0;self.rowPages={}
  self.handPages={1,1};self.freshCards={{},{}};self.drawReceipt=nil;self.before=nil;self.lastPlayed=nil
  self.roundSeen=self.match.state.round;self.promptPage=1;self.resultShown=false
end
-- Called for every position the session shows: the player's own move, each computer
-- move, and whatever the other player did since the last poll.
function App:frame(draws)
  local m=self.match;local s=m.state
  if self.board~=m then self:enterBoard() end
  local now=self:snapshot()
  self.flash={}
  if self.before then
    for id,value in pairs(now) do if self.before[id]~=value then self.flash[id]=true end end
    self.flashTime=1.6
  end
  self.before=now;self.selected=nil;self.previewUnit=nil;self.promptPage=1
  if s.last_played~=self.lastPlayed then self.lastPlayed=s.last_played;self.inspected=s.last_played end
  for _,event in ipairs(draws) do
    self.drawReceipt=event
    for _,u in ipairs(event.cards) do self.freshCards[event.seat][u.uid]=true end
    if #event.cards>0 then
      local hand=s.players[event.seat].hand
      for j=#hand,1,-1 do
        if self.freshCards[event.seat][hand[j].uid] then
          self.handPages[event.seat]=math.ceil(j/self.handPageSize)
          break
        end
      end
    end
  end
  if s.round~=self.roundSeen and #s.round_history>0 then
    local r=s.round_history[#s.round_history];self.roundSeen=s.round
    local me=m.seat
    self:notice("Round "..r.round.."   ·   You "..r.scores[me].." to "..r.scores[3-me].."   ·   "..
      (r.winner==0 and "Tied round" or r.winner==me and "You win the round" or self:who(3-me).." wins the round").." · "..self:roundEnding(r))
  end
end
function App:drawMessage()
  local event=self.drawReceipt
  if not event then return end
  local text=self:who(event.seat).."   ·   "..event.source
  if event.count==0 then return text.."   ·   No card drawn ("..tostring(event.reason)..")." end
  local result=event.count.." card(s)"
  if #event.cards>0 then
    local names={}
    for _,u in ipairs(event.cards) do names[#names+1]=u.card.name end
    result=table.concat(names,", ")
  end
  return text.." drew "..result.."   ·   Draw deck "..event.before.." → "..event.remaining..
    (event.reason and "   ·   "..event.reason or "")
end
-- Sends a move (action) or the answer to a question (index) to the server.
function App:action(action,index)
  local m=self.match
  local ok,why
  if index then ok,why=m:choose(index) else ok,why=m:act(action) end
  if not ok then self:notice(why);return end
  self.toast=nil;self.selected=nil;self.modal=nil
  if not index then self.freshCards[m.seat]={} end
end
function App:matchMenu()
  local m=self.match
  local items={item("Back to the battlefield",function() self.modal=nil end)}
  if m.phase=="playing" then
    items[#items+1]=item("Leave the match",function()
      self:list("Leave this match?",m.mode=="duel" and "The other player is told that you left, and the match ends without a winner."
        or "The match against the computer ends without a result.",{
        item("Leave the match",function() self:closeMatch() end,"Return to the match table"),
        item("Keep playing",function() self.modal=nil end)})
    end,"End the match now")
  else items[#items+1]=item("Back to the match table",function() self:closeMatch() end,"Choose decks and start another match") end
  self:list("Match menu",Lib.modes[m.mode=="duel" and 2 or 1].name..(m.code and "   ·   Room "..m.code or ""),items)
end
function App:rounds()
  local m=self.match;local s=m.state;local me=m.seat;local entries={}
  for _,r in ipairs(s.round_history) do
    entries[#entries+1]=item("Round "..r.round.."   ·   "..r.scores[me].." to "..r.scores[3-me],nil,
      self:roundEnding(r).." "..(r.winner==0 and "Tied round" or self:who(r.winner).." won"..(r.reason and " by "..r.reason or "")))
  end
  if not s.finished then entries[#entries+1]=item("Round "..s.round.."   ·   "..B.score(s,me).." to "..B.score(s,3-me),nil,"In progress · total current Health") end
  self:list("Remaining Health","You to "..self:who(3-me):lower().."   ·   "..s.players[me].wins.." to "..s.players[3-me].wins.." round wins",entries)
end
function App:result()
  local m=self.match;local s=m.state;local me=m.seat
  local title
  if m.abandoned then title=m.left and m.left~=me and self:who(m.left).." left the match" or "The match was closed"
  elseif s.winner==0 then title="The match is drawn"
  elseif s.winner==me then title="You win the match"
  else title=self:who(3-me).." wins the match" end
  local entries={
    item("Back to the match table",function() self:closeMatch() end,"Keep your deck and start another match"),
    item("Review battlefield",function() self.modal=nil end,"Inspect the record, both discard piles, and round scores")}
  for _,r in ipairs(s.round_history) do
    entries[#entries+1]=item("Round "..r.round.." · "..r.scores[me].." to "..r.scores[3-me],nil,self:roundEnding(r))
  end
  self:list(title,"Round scores show your remaining HP first.",entries)
end
function App:log()
  local entries={}
  local log=self.match.state.log
  for i=#log,1,-1 do
    local msg=Text.event(log[i]);entries[#entries+1]=item("Event "..i,function()
      self:list("Event "..i,msg,{item("Back to battle record",function() self:log() end)})
    end,msg)
  end
  self:list("Battle record","Most recent event first.",entries)
end
function App:pile(p,zone)
  local pl=self.match.state.players[p];local allowed=zone~="hand" or self:visible(p)
  local entries={}
  if allowed then for _,u in ipairs(pl[zone]) do
    local fresh=zone=="hand" and self.freshCards[p][u.uid]
    local entry=item(u.card.name..(fresh and "   ·   NEW DRAW" or ""),function()
      self:list(u.card.name,(u.card.designation and Text.rows(u.card).." · " or "")..u.card.text,{item("Back to "..zone,function() self:pile(p,zone) end,
        Text.stats(u.card),u.card)})
    end,Text.stats(u.card),u.card)
    if fresh then table.insert(entries,1,entry) else entries[#entries+1]=entry end
  end end
  self:list(self:who(p).."   /   "..(zone=="hand" and "Hand" or "Discard pile"),
    #pl[zone].." cards   ·   "..(allowed and Lib.label(pl.faction) or "Face down"),entries)
end
local verbs={grave_zone="Grave Whisper · choose a pile",grave_search="Draw deck → hand",grave_recover="Discard pile → hand",deploy_attack="Deployment attack · choose an eligible enemy",damage="Deal damage",debuff="Reduce Strength",buff="Increase Strength",heal="Restore Health",guard="Protect a Unit",
  destroy="Destroy a Unit",move="Reposition",row="Choose a row",card="Choose a card",chain="Choose a chain",resurrect="Discard pile → battlefield",recover="Discard pile → hand",
  bottom_from_hand="Hand → bottom of draw deck",discard_from_hand="Hand → owner’s discard pile",
  steal_hand="Opposing hand → your hand",steal_discard="Opposing discard → your hand",echo_effect="Copy an Effect in discard",
  peek="Order the top cards",search="Add an examined card to hand",bottom_order="Place remaining cards on the bottom",
  chain_activation="Resolve a chain ability",disable="Suppress an ability",copy_deploy="Copy a Deploy ability",
  beacon="Lighthouse · Guiding Beam",summon="Bring the Unit into play",replace="Choose the Unit to replace",
  give="Trade · choose the Unit you give",take="Trade · choose the Unit you take",reveal="Reveal opposing cards",
  reverse="Reverse a row",maelstrom="Choose a row"}
-- The question the server is waiting for this player to answer, as a dialog.
function App:promptDialog()
  local m=self.match
  if not m or self.screen~="board" or not m.prompt or m.prompt.waiting or not m:ready() then return end
  local q=m.prompt;local ctx=q.context;local items={}
  for i,v in ipairs(q.options) do
    local u=type(v)=="table" and (v.unit or v.card and v)
    local title,detail,card
    if u then
      card=u.card;title=card.name
      local p,r,pos=B.position(m.state,u)
      detail=p and (self:who(p).."   ·   "..(r==1 and "Front" or "Back").." position "..pos.."   ·   "..Text.stats(card,B.strength(m.state,u),u.hp))
        or card.text
      if ctx.op=="search" then title="Add to hand · "..title end
      if ctx.op=="bottom_order" then title="Place on bottom · "..title end
      if ctx.op=="deploy_attack" then
        detail=detail.." · Attack for "..B.attack_power(m.state,ctx.unit,u,Lib.cards.by_id[ctx.profile]).." before protection"
      end
    elseif q.kind=="chain" then
      local nums={};local names={}
      for _,member in ipairs(v.units) do
        local _,row,pos=B.position(m.state,member)
        nums[#nums+1]=member.card.strength
        names[#names+1]=member.card.name.." ("..(row==1 and "Front " or "Back ")..pos..")"
      end
      title=table.concat(nums," – ")..(v.cross and "   ·   Bridge" or "");detail=table.concat(names," / ")
    elseif q.kind=="zone" then title=v=="deck" and "Draw deck" or "Discard pile"
    elseif q.kind=="row" then title=v==1 and "Front row" or "Back row";detail=ctx.enemy and "Opposing battlefield" or "Select this row"
    elseif q.kind=="amount" then title=tostring(v)..(ctx.op=="heal" and " HP" or " cards")
    elseif q.kind=="side" then title=v==m.seat and "Your battlefield" or self:who(v).."'s battlefield"
    elseif q.kind=="beacon" then
      card=ctx.cards[1].card
      title=v==1 and ("Keep "..card.name.." on top") or ("Send "..card.name.." to the bottom")
      detail=v==1 and "It stays on top for your next draw" or "The card below it becomes the next draw"
    elseif q.kind=="order" then
      local a,b=ctx.cards[1].card,ctx.cards[2].card;if v==2 then a,b=b,a end
      title=a.name.."   →   "..b.name;detail="Next draw first";card=a
    else title="Position "..tostring(v) end
    items[#items+1]=item(title,function() self:action(nil,i) end,detail,card)
  end
  if ctx.optional then
    items[#items+1]=item("Done choosing",function() self:action(nil,0) end,"Continue with the choices made so far")
  end
  local desc="Your choice   ·   "..Lib.label(m.state.players[q.actor].faction)
  if ctx.op=="deploy_attack" then
    desc=Text.rows(ctx.unit.card)
  elseif ctx.op=="search" then
    local eligible,names={},{}
    for _,c in ipairs(q.options) do eligible[c.uid]=true end
    for _,c in ipairs(ctx.cards) do
      names[#names+1]=c.card.name..(eligible[c.uid] and " (eligible)" or " (ineligible)")
    end
    desc=(ctx.source or "Search").." · Examined "..(ctx.bottom and "from the bottom · " or "")..table.concat(names,", ")
  elseif ctx.op=="bottom_order" then desc=(ctx.note or "").." Choose which of these bottom cards will be drawn first."
  elseif ctx.unit then desc=desc.."   ·   "..ctx.unit.card.name end
  return {title=verbs[ctx.op] or "Resolve ability",subtitle=desc,items=items,page=self.promptPage,locked=true}
end
-- Starting, waiting for the other player, and failures, before a battlefield exists.
function App:lobbyDialog()
  local m=self.match
  if not m or self.screen=="board" then return end
  if m.phase=="connecting" then
    return {title="Contacting the game server",subtitle="Setting up your match…",locked=true,page=1,
      items={item("Cancel",function() self:closeMatch() end)}}
  elseif m.phase=="waiting" then
    return {title="Your room is open",code=m.code,locked=true,page=1,
      subtitle=m.offline and "Connection lost. Trying again…" or "Give this code to the other player. The match starts as soon as they join.",
      items={item("Copy the code",function() love.system.setClipboardText(m.code);self:notice("Room code copied.") end,"Paste it into a message"),
        item("Close the room",function() self:closeMatch() end,"Return to the match table")}}
  elseif m.phase=="failed" then
    return {title="The match could not start",subtitle=m.error,locked=true,page=1,
      items={item("Back to the match table",function() self.match=nil end)}}
  end
end
function App:drawDialog(mod)
  P.hits={};P.box(0,0,1280,800,P.black,.86)
  local x,y,w,h=239,76,802,648
  P.box(x,y,w,h,P.panel);P.border(x,y,w,h,P.gold,.8)
  P.label(self.screen=="board" and "Battle table" or "Match table",x+26,y+21,P.gold)
  P.one(mod.title,x+25,y+43,w-104,36,P.textColor,"serif")
  P.text(mod.subtitle or "",x+26,y+95,17,P.muted,"sans",w-52)
  if not mod.locked then P.button("close","×",x+w-61,y+17,41,35,function() self.modal=nil end) end
  local yy=y+158
  if mod.input then
    P.box(x+27,yy,w-54,62,P.inset);P.border(x+27,yy,w-54,62,P.gold)
    P.text(mod.input=="" and mod.placeholder or mod.input,x+43,yy+12,28,mod.input=="" and P.muted or P.textColor,"serif")
    P.button("apply-input",mod.button,x+27,yy+87,w-54,45,function() mod.submit() end,"gold");return
  end
  if mod.code then
    P.box(x+27,yy,w-54,118,P.inset);P.border(x+27,yy,w-54,118,P.gold)
    P.label("Room code",x+43,yy+12,P.gold)
    P.one(mod.code:gsub("."," %0 "),x+27,yy+34,w-54,56,P.bright,"serif","center")
    yy=yy+140
  end
  local items=mod.items or {};local per=mod.code and 4 or 6;local pages=math.max(1,math.ceil(#items/per))
  if #items==0 then P.text((mod.subtitle or ""):find("Face down",1,true) and "This hand is hidden." or "No cards here.",x+27,yy+72,27,P.muted,"italic") end
  for j=1,per do
    local i=(mod.page-1)*per+j;local v=items[i];local top=yy+(j-1)*67
    if v then
      local hot=v.action and P.inside(x+26,top,w-52,60)
      P.box(x+26,top,w-52,60,hot and P.rule or P.inset);P.border(x+26,top,w-52,60,P.rule)
      local xx=x+41
      if v.card then
        local spec=Lib.specs[v.card.faction];P.box(xx,top+4,54,52,spec.paper);P.art(v.card,xx+2,top+6,50,48);xx=xx+69
      end
      local space=x+w-74-xx
      P.one(v.title,xx,top+(v.detail and 3 or 15),space,22,P.textColor,"serif")
      if v.detail then
        local f=P.font(15);local _,lines=f:getWrap(v.detail,space)
        P.text((lines[1] or "")..(#lines>1 and " …" or ""),xx,top+33,15,P.muted)
      end
      if v.action then P.text("›",x+w-52,top+11,28,P.gold,"serif");P.hit("option-"..i,x+26,top,w-52,60,v.action) end
    end
  end
  if pages>1 then
    local function page(n) if self.modal then self.modal.page=n else self.promptPage=n end end
    P.button("dialog-prev","‹",x+26,y+h-62,42,34,function() page(mod.page-1) end,nil,mod.page>1)
    P.text("Page "..mod.page.." of "..pages,x+86,y+h-56,16,P.muted)
    P.button("dialog-next","›",x+226,y+h-62,42,34,function() page(mod.page+1) end,nil,mod.page<pages)
  end
end
function App:draw()
  P.begin()
  if self.screen=="menu" then SetupView.menu(self) elseif self.screen=="builder" then SetupView.builder(self) else BoardView.draw(self) end
  local mod=self.modal or self:lobbyDialog() or self:promptDialog()
  if mod then self:drawDialog(mod) end
  if self.toast and self.toastTime>0 then
    P.box(28,767,1224,29,P.panel);P.box(28,767,3,29,P.gold);P.one(self.toast,40,771,1199,16,P.textColor)
  end
  P.finish()
end
function App:update(dt)
  self.toastTime=math.max(0,(self.toastTime or 0)-dt);self.flashTime=math.max(0,(self.flashTime or 0)-dt)
  self.transport:update()
  local m=self.match
  if not m then return end
  m:update(dt)
  if m.notice then self:notice(m.notice);m.notice=nil end
  if m.phase=="over" and self.screen=="board" and #m.queue==0 and not self.resultShown then
    self.resultShown=true;self.selected=nil;self:result()
  elseif m.phase=="over" and self.screen~="board" then
    -- The match ended before a battlefield was shown (a resumed match that had been closed).
    self:notice("That match has ended.");self.match=nil
  end
end
function App:key(k)
  local mod=self.modal
  if mod then
    if mod.input then
      if k=="backspace" then mod.input=mod.input:sub(1,-2) end
      if k=="return" or k=="kpenter" then mod.submit() end
      if k=="v" and love.keyboard.isDown("lgui","rgui","lctrl","rctrl") then self:type(love.system.getClipboardText() or "") end
    end
    if k=="escape" and not mod.locked then self.modal=nil end
    return
  end
  if self:lobbyDialog() or self:promptDialog() then return end
  if k=="escape" then
    if self.screen=="builder" then self.screen="menu" elseif self.screen=="board" then
      if self.selected then self.selected=nil else self:matchMenu() end
    end
  end
end
-- Text typed or pasted into a dialog's input line.
function App:type(text)
  local mod=self.modal
  if mod and mod.input then mod.input=(mod.input..mod.accept(text)):sub(1,mod.limit) end
end
-- Closes an open room when the game quits, so nobody joins a host who has gone.
function App:quit()
  local m=self.match
  if m and m.phase=="waiting" then
    m:leave()
    local waited=0
    while next(self.transport.pending) and waited<2 do
      love.timer.sleep(0.05);waited=waited+0.05;self.transport:update()
    end
  end
  self.transport:close()
end
return App
