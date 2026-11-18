local P=require('tabletop.paint')
local Lib=require('tabletop.library')
local Decks=require('decks')
local Rules=require('rules')
local View={}

-- Seat 1 is always this player. Seat 2 is the computer's deck in a single-player match.
local function seatName(cfg,p)
  if p==1 then return "You" end
  return "Computer"
end
local function factionPlate(app,p,x)
  local cfg=app.cfg
  local faction=cfg.factions[p]
  local spec=Lib.specs[faction]
  local featured=Lib.cards[faction][spec.featured]
  local y,w,h=202,359,386
  P.box(x+4,y+6,w,h,P.black);P.box(x,y,w,h,spec.ink);P.border(x,y,w,h,spec.color)
  P.plate(spec,x+8,y+8,w-16,246,true)
  P.border(x+15,y+15,w-30,232,spec.ink,.55)
  P.label(featured.rarity,x+27,y+23,spec.ink)
  P.icon(spec.emblem,x+w-37,y+36,12,spec.ink)
  P.art(featured,x+36,y+20,w-72,220)
  P.label(p==1 and "YOU" or "COMPUTER   /   "..cfg.difficulty,x+23,y+270,spec.color)
  P.text(Lib.label(faction),x+22,y+291,39,P.textColor,"serif")
  P.text(featured.display_name or featured.name,x+23,y+339,19,spec.color,"italic")
  P.button("faction-prev-"..p,"‹",x+w-95,y+305,32,35,function() app:cycleFaction(p,-1) end)
  P.button("faction-next-"..p,"›",x+w-55,y+305,32,35,function() app:cycleFaction(p,1) end)
  local count=#cfg.decks[p]
  local tagged=(p==2 and count==0) and "20-card starter" or count.." tagged"
  local title="Browse "..Lib.size(faction).." designs   ·   "..tagged
  P.button("edit-"..p,title,x,y+h+14,w,43,function() app:builder(p) end,"accent")
end
-- In a two-player match the other seat is filled by whoever joins the room.
local function opponentPlate(x)
  local y,w,h=202,359,386
  P.box(x+4,y+6,w,h,P.black);P.box(x,y,w,h,P.panel);P.border(x,y,w,h,P.rule)
  P.icon("cards",x+w/2,y+124,56,P.rule)
  P.label("OPPONENT",x+23,y+262,P.gold)
  P.text("Another player",x+22,y+281,39,P.textColor,"serif")
  P.text("Joins over the internet with their own faction and deck.",x+23,y+332,16,P.muted,"sans",w-46)
end
local dots={ok=P.gold,checking=P.muted,error=P.red,mismatch=P.red,unconfigured=P.red}

function View.menu(app)
  local cfg=app.cfg;local solo=cfg.mode==1
  P.header("Match setup")
  P.button("presets","Deck presets",1097,18,151,36,function() app:presets() end)
  P.text("The match table",33,94,52,P.textColor,"serif")
  P.text(solo and "Choose your faction and the computer's, then assemble the decks they bring to battle."
    or "Choose your faction and assemble your deck, then open a room or join one.",37,158,19,P.muted)
  factionPlate(app,1,36)
  if solo then factionPlate(app,2,415) else opponentPlate(415) end
  local x,y,w=809,202,436
  P.box(x,y,w,443,P.panel);P.border(x,y,w,443,P.rule)
  P.text("Play online",x+22,y+15,29,P.textColor,"serif")
  for i,mode in ipairs(Lib.modes) do
    local yy=y+62+(i-1)*61;local active=cfg.mode==i
    P.box(x+16,yy,w-32,55,active and {.18,.215,.164} or P.inset)
    P.border(x+16,yy,w-32,55,active and P.gold or P.rule,active and .9 or .6)
    P.diamond(x+35,yy+28,6,active and P.gold or P.muted,active)
    P.text(mode.name,x+54,yy+4,19,active and P.textColor or P.muted,"bold")
    P.text(mode.note,x+54,yy+28,15,P.muted)
    P.hit("mode-"..i,x+16,yy,w-32,55,function() Lib.set_mode(cfg,i) end)
  end
  -- Server line: every match is dealt and refereed by the game server.
  local server=app.server
  P.diamond(x+29,y+207,5,dots[server.state],true)
  P.text(server.message,x+44,y+197,15,server.state=="ok" and P.muted or P.textColor,"sans",w-(server.state=="ok" and 66 or 150))
  if server.state=="error" then P.button("retry","Try again",x+w-100,y+193,84,28,function() app:connect() end) end
  P.line(x+21,y+243,x+w-21,y+243,P.rule)
  local ready=server.state=="ok"
  local mine=Lib.valid(cfg,1)
  if app.savedMatch and ready then
    P.button("resume","Return to your match in progress   →",x+17,y+254,w-34,36,function() app:online("resume") end,"accent")
  end
  if solo then
    P.label("Computer",x+22,y+308)
    for i,level in ipairs({"normal","easy"}) do
      P.button("difficulty-"..level,level=="normal" and "Normal" or "Easy",x+112+(i-1)*98,y+299,90,31,
        function() cfg.difficulty=level end,cfg.difficulty==level and "gold" or nil)
    end
    P.text("Easy plays any legal card.",x+22,y+340,15,P.muted)
    if not mine then P.button("build","Build your deck   →",x+17,y+377,w-34,49,function() app:builder(1) end,"gold")
    elseif not Lib.computer_ready(cfg) then P.button("build","Finish the computer's deck   →",x+17,y+377,w-34,49,function() app:builder(2) end,"gold")
    else P.button("start","Start online match   →",x+17,y+377,w-34,49,function() app:online("solo") end,ready and "gold" or nil,ready) end
  else
    P.text("One player opens a room and shares its code. The other joins with that code.",x+22,y+300,15,P.muted,"sans",w-44)
    if not mine then P.button("build","Build your deck   →",x+17,y+377,w-34,49,function() app:builder(1) end,"gold")
    else
      P.button("create-room","Create a room   →",x+17,y+349,w-34,44,function() app:online("host") end,ready and "gold" or nil,ready)
      P.button("join-room","Join with a room code",x+17,y+399,w-34,36,function() app:joinDialog() end,"accent",ready)
    end
  end
  P.line(36,689,1245,689,P.rule)
  local facts={{"MATCH","Best of three"},{"OPENING HAND",Rules.starting_hand.." random cards"},{"DECK",Rules.min_deck_size.."–"..Rules.max_deck_size.." tagged cards"},{"TURN","Draw 1 · play or pass"}}
  for i,v in ipairs(facts) do
    local xx=39+(i-1)*304
    if i>1 then P.line(xx-19,713,xx-19,761,P.rule) end
    P.label(v[1],xx,712,P.gold);P.text(v[2],xx,732,23,P.textColor,"serif")
  end
end

local filters={"All","Units","Effects","Selected"}
function View.builder(app)
  local cfg,p=app.cfg,app.side
  local seats=cfg.mode==1 and 2 or 1
  local f=cfg.factions[p];local spec=Lib.specs[f];local counts=Decks.counts(cfg.decks[p])
  P.header("Deck workshop")
  P.button("setup","Match setup",925,18,151,36,function() app.screen="menu" end)
  P.button("presets","Deck presets",1092,18,153,36,function() app:presets() end)
  P.text(Lib.label(f).." collection",35,88,43,P.textColor,"serif")
  for n=1,seats do
    local xx=758+(n-1)*245
    P.button("seat-"..n,seatName(cfg,n).."  ·  "..Lib.label(cfg.factions[n]).."    "..#cfg.decks[n].." cards",
      xx,97,238,38,function() app:builder(n) end,n==p and "gold" or nil)
  end
  local cards={}
  for _,card in ipairs(Lib.collection(f)) do
    if (app.filter=="All" or app.filter=="Units" and card.type=="Unit" or
       app.filter=="Effects" and card.type=="Effect" or app.filter=="Selected" and counts[card.id]) then
      cards[#cards+1]=card
    end
  end
  for i,title in ipairs(filters) do
    local x=36+(i-1)*108
    P.button("filter-"..title,title=="Selected" and "Tagged" or title,x,151,101,34,function() app.filter=title;app.page=1 end,title==app.filter and "accent" or nil)
    if title==app.filter then P.box(x,183,101,2,P.gold) end
  end
  local pages=math.max(1,math.ceil(#cards/8))
  app.page=math.min(pages,app.page)
  P.one(#cards.." of "..Lib.size(f).." designs",625,157,245,15,P.muted,"sans","right")
  if #cards==0 then P.text("No cards in this view.",36,239,25,P.muted,"italic") end
  for k=1,8 do
    local c=cards[(app.page-1)*8+k]
    if c then
      local x=36+(k-1)%4*213;local y=204+math.floor((k-1)/4)*246
      local qty=counts[c.id] or 0;local enabled=Lib.owned[f][c.id]
      P.card(c,x,y,195,188,{selected=app.inspected==c})
      P.hit("inspect-"..c.id,x,y,195,188,function() app.inspected=c end)
      P.button("remove-"..c.id,"−",x,y+193,43,32,function() app:edit(c,-1) end,nil,qty>0)
      P.box(x+46,y+193,103,32,P.inset);P.one(qty.." / "..enabled,x+46,y+199,103,15,P.muted,"bold","center")
      P.button("add-"..c.id,"+",x+152,y+193,43,32,function() app:edit(c,1) end,"accent",qty<enabled and #cfg.decks[p]<Rules.max_deck_size)
    end
  end
  P.button("prev","‹",36,703,40,36,function() app.page=app.page-1 end,nil,app.page>1)
  P.text("Page "..app.page.." of "..pages,88,711,16,P.muted)
  P.button("next","›",195,703,40,36,function() app.page=app.page+1 end,nil,app.page<pages)
  P.button("starter-30","30-card starter",440,703,149,36,function() Lib.starter(cfg,p,Rules.max_deck_size) end)
  P.button("starter-20","20-card starter",282,703,149,36,function() Lib.starter(cfg,p) end)
  P.button("random","Random 20",598,703,151,36,function() Lib.random(cfg,p) end,"accent")
  P.button("clear","Clear deck",758,703,112,36,function() cfg.decks[p]={} end)
  local x,w=901,344
  P.box(x,151,w,589,P.panel);P.border(x,151,w,589,P.rule)
  local c=app.inspected or Lib.cards[f][spec.featured]
  P.label("Card inspection",x+18,166,P.gold)
  P.plate(spec,x+18,191,w-36,149);P.art(c,x+27,197,w-54,137)
  P.one(c.display_name or c.name,x+18,350,w-36,30,P.textColor,"serif")
  P.text(c.id.."  ·  "..c.rarity.."  ·  "..c.type,x+18,390,17,spec.color)
  if c.strength then P.text("Printed "..c.strength.." STR     "..c.health.." HP",x+18,417,16,P.textColor,"bold") end
  -- Long rules text shrinks to stay inside the panel.
  local top=c.strength and 446 or 419
  local size=17
  while size>12 do
    local _,lines=P.font(size):getWrap(c.text,w-36)
    if top+#lines*P.font(size):getHeight()<=578 then break end
    size=size-1
  end
  P.text(c.text,x+18,top,size,P.muted,"sans",w-36)
  P.line(x+18,583,x+w-18,583,P.rule)
  P.label("Tag "..Rules.min_deck_size.."–"..Rules.max_deck_size.."   ·   Open with "..Rules.starting_hand,x+18,598,P.gold)
  local ready=true
  for n=1,seats do
    local count=#cfg.decks[n]
    local ok=Lib.valid(cfg,n)
    local automatic=n==2 and count==0
    ready=ready and (ok or automatic)
    P.text(seatName(cfg,n).."  ·  "..Lib.label(cfg.factions[n]),x+18,616+(n-1)*21,16,P.textColor)
    local status=automatic and "20-card starter" or ok and (count.." tagged  /  "..(count-Rules.starting_hand).." in draw deck") or (count.." tagged / need "..Rules.min_deck_size.."–"..Rules.max_deck_size)
    P.one(status,x+146,616+(n-1)*21,182,16,(ok or automatic) and spec.color or P.muted,"bold","right")
  end
  if ready then P.button("done","Deck ready   →",x+18,675,w-36,46,function() app.screen="menu" end,"gold")
  elseif Lib.valid(cfg,p) or (p==2 and #cfg.decks[2]==0) then
    local other=3-p
    P.button("other","Build "..(other==1 and "your" or "the computer's").." deck   →",x+18,675,w-36,46,function() app:builder(other) end,"gold")
  else P.button("done","Deck ready",x+18,675,w-36,46,nil,nil,false) end
end
return View
