-- Drives the real window through the normal LÖVE callbacks: hit tests, dialogs, text entry.
-- Scenarios (love . --ui-test NAME, see tests/run_ui.py):
--   solo   build decks, save and load a preset, play a whole match against the computer
--   host   open a room, write its code to $TT_ROOM_FILE, play the match from seat 1
--   guest  read the code from $TT_ROOM_FILE, join, play the match from seat 2
local P=require('tabletop.paint')
local B=require('battle')
local Lib=require('tabletop.library')
local U=require('util')
local Smoke={}
function Smoke.new(app,scenario)
  local smoke={}
  local function frame() coroutine.yield() end
  local function wait(done,what,limit)
    local n=0
    while not done() do
      frame();n=n+1
      if n>(limit or 5400) then error("Timed out waiting for "..what) end
    end
  end
  local function find(id)
    for _,q in ipairs(P.hits) do if q.id==id then return q end end
  end
  local function click(id)
    frame()
    local q=find(id)
    if not q then error("Missing clickable control "..id.." on "..app.screen) end
    love.mousepressed(P.ox+(q.x+q.w/2)*P.scale,P.oy+(q.y+q.h/2)*P.scale,1)
  end
  local function capture(name)
    local dir=os.getenv("TT_CAPTURE_DIR")
    if dir then
      frame()
      local done=false
      love.graphics.captureScreenshot(function(image)
        local data=image:encode("png");local f=assert(io.open(dir.."/"..scenario.."-"..name..".png","wb"))
        f:write(data:getString());f:close();done=true
      end)
      repeat frame() until done
    end
  end
  local function handcard(index)
    local seat=app.match.seat
    local page=math.ceil(index/app.handPageSize)
    while app.handPages[seat]~=page do
      click(app.handPages[seat]<page and "hand-next" or "hand-prev")
    end
    click("handcard-"..index)
  end
  -- Plays the match on screen to its end with random legal moves.
  local function play(seed)
    local m=app.match;local rng=U.rng(seed);local moves,asked,shots=0,0,0
    m.pace=0.05;m.poll=0.25;m.idle_poll=1
    assert(m.state.players[3-m.seat].hand[1].hidden,"the other hand must not be on this computer")
    click("hand-"..(3-m.seat));frame()
    assert(app.modal and #app.modal.items==0 and app.modal.subtitle:find("Face down",1,true));click("close")
    click("pile-"..m.seat);click("close");click("rounds");click("close");click("full-log");click("close")
    click("match-menu");click("option-1")
    while m.phase=="playing" do
      frame()
      -- The other player's last move can end the match between two frames.
      if m.phase~="playing" then break end
      assert(not app.modal,"unexpected dialog: "..tostring(app.modal and app.modal.title))
      if m:ready() then
        local s,me=m.state,m.seat;local hand=s.players[me].hand
        if m.prompt then
          asked=asked+1;assert(asked<600,"endless questions")
          if asked==1 then capture("question") end
          click("option-1")
        else
          moves=moves+1;assert(moves<300,"endless match")
          local legal={}
          for i=1,#hand do if B.playable(s,me,i) then legal[#legal+1]=i end end
          if B.can_school(s,me) then click("school")
          elseif #legal==0 or rng:random(14)==1 then click("pass");click("option-2")
          else
            local i=legal[rng:random(#legal)];local card=hand[i].card
            handcard(i);assert(app.selected==i,"card not selected")
            if card.type=="Effect" or card.replaces then click("play-effect")
            else
              local side=B.deploy_side(me,card)
              if shots<1 or (card.agent and shots<2) then shots=shots+1;capture(card.agent and "agent" or "placing") end
              click("slot-"..side.."-"..rng:random(2).."-1")
            end
          end
        end
        wait(function() return not m.sending and not m.pending_action end,"the server to answer")
        if moves==6 then capture("battle") end
      end
    end
    wait(function() return app.modal~=nil and app.resultShown end,"the result")
    assert(m.state.finished and #m.state.round_history>=2,"the match should be played to the end")
    capture("result")
    click("option-2");frame();assert(not app.modal and find("result"));click("result")
    click("option-1");assert(app.screen=="menu" and not app.match)
    print(scenario..": match complete, "..moves.." moves, "..asked.." questions, winner seat "..tostring(m.state.winner)..
      ", HTTP through "..app.transport.backend)
  end
  local function connected()
    wait(function() return app.server.state~="checking" end,"the server check")
    assert(app.server.state=="ok",app.server.message)
  end

  local scenarios={}
  function scenarios.solo()
    love.filesystem.remove("table-preset-5.txt")
    connected();capture("setup")
    click("faction-next-1");assert(app.cfg.factions[1]=="Water")
    click("faction-next-1");assert(app.cfg.factions[1]=="Super" and Lib.label("Super")=="Comic")
    click("faction-next-1");assert(app.cfg.factions[1]=="Fantasy")
    click("mode-2");frame();assert(app.cfg.mode==2 and find("create-room") and not find("faction-next-2"))
    capture("setup-two-players")
    click("mode-1");click("edit-1");assert(app.screen=="builder" and #app.cfg.decks[1]==30);click("clear")
    click("add-Fantasy:1");click("remove-Fantasy:1");click("starter-20")
    click("remove-Fantasy:1");click("add-Fantasy:3")
    assert(Lib.valid(app.cfg,1));capture("builder")
    click("seat-2");frame();assert(find("done"),"the computer may keep its automatic starter deck")
    click("starter-20");click("presets");click("option-5");click("option-1")
    click("clear");click("presets");click("option-5");click("option-1")
    assert(#app.cfg.decks[2]==20 and app.cfg.mode==1 and app.side==1)
    click("done");assert(app.screen=="menu")
    -- The computer plays the Comic deck, so its new cards appear on a real battlefield.
    click("faction-next-2");assert(app.cfg.factions[2]=="Super" and #app.cfg.decks[2]==30)
    click("edit-2");click("random");click("done")
    click("difficulty-easy");assert(app.cfg.difficulty=="easy");click("difficulty-normal")
    click("start")
    wait(function() return app.screen=="board" end,"the match to start")
    local m=app.match
    assert(m.mode=="solo" and m.seat==1 and m.controllers[2]=="AI" and #m.state.players[1].hand==5)
    assert(m.state.players[2].faction=="Super" and #m.state.players[2].deck==15)
    play(41)
  end
  local function ownDeck(faction)
    connected()
    click("mode-2")
    while app.cfg.factions[1]~=faction do click("faction-next-1") end
    click("edit-1");click("starter-20");click("done")
    assert(app.screen=="menu" and Lib.valid(app.cfg,1))
  end
  local roomFile=os.getenv("TT_ROOM_FILE")
  function scenarios.host()
    ownDeck("Super")
    click("create-room")
    wait(function() return app.match and app.match.phase=="waiting" and app.match.code end,"the room to open")
    capture("room")
    local f=assert(io.open(roomFile,"w"));f:write(app.match.code);f:close()
    wait(function() return app.screen=="board" end,"the other player to join",18000)
    assert(app.match.seat==1 and app.match.mode=="duel" and app.match.controllers[2]=="Human")
    play(7)
  end
  function scenarios.guest()
    ownDeck("Water")
    local code
    wait(function()
      local f=io.open(roomFile,"r")
      if f then code=f:read("*a");f:close() end
      return code and #code==6
    end,"the room code",18000)
    -- A wrong code is refused with an explanation, and the table is still usable.
    click("join-room");love.textinput("zz-zz zz");love.keypressed("return")
    wait(function() return app.match and app.match.phase=="failed" end,"the refusal")
    assert(app.match.error:find("code",1,true));capture("refused");click("option-1");assert(not app.match)
    click("join-room");love.textinput(code:sub(1,3):lower());love.textinput(code:sub(4));assert(app.modal.input==code)
    click("apply-input")
    wait(function() return app.screen=="board" end,"the match to start")
    assert(app.match.seat==2 and app.match.mode=="duel")
    play(8)
  end
  smoke.task=coroutine.create(function()
    assert(scenarios[scenario],"unknown UI scenario "..tostring(scenario))()
    love.event.quit(0)
  end)
  function smoke:update()
    if coroutine.status(self.task)=="dead" then return end
    local ok,why=coroutine.resume(self.task)
    if not ok then error(debug.traceback(self.task,tostring(why)),0) end
  end
  return smoke
end
return Smoke
