love.filesystem.setRequirePath("?.lua;?/init.lua;card_battle_sim/?.lua")
local App=require('tabletop.app')
local Paint=require('tabletop.paint')
local app
local smoke
-- Options (after the game folder): --backend URL and --key KEY play on another server than
-- online/config.lua; --profile NAME keeps a separate sign-in so that two copies can run on
-- one computer; --ui-test SCENARIO runs tests/ui_smoke.lua.
function love.load(args)
  love.graphics.setDefaultFilter("linear","linear")
  local opts={}
  local scenario
  local i=1
  while i<=#args do
    local name,value=args[i],args[i+1]
    if name=="--backend" then opts.url=value;i=i+1
    elseif name=="--key" then opts.key=value;i=i+1
    elseif name=="--profile" then opts.profile="-"..tostring(value):gsub("[^%w]","");i=i+1
    elseif name=="--http" then opts.http=value;i=i+1
    elseif name=="--ui-test" then scenario=value or "solo";i=i+1 end
    i=i+1
  end
  if scenario then
    love.filesystem.setIdentity("tide-and-timber-ui-tests")
    love.errorhandler=function(msg)
      io.stderr:write(debug.traceback(tostring(msg),2).."\n")
      return function() return 1 end
    end
  end
  app=App.new(opts)
  if scenario then smoke=require('tests.ui_smoke').new(app,scenario) end
end
function love.update(dt)
  app:update(dt)
  if smoke then smoke:update() end
end
function love.draw() app:draw() end
function love.mousepressed(x,y,b)
  if b==1 then local mx,my=Paint.point(x,y);Paint.click(mx,my,b) end
end
function love.keypressed(k) app:key(k) end
function love.textinput(s) app:type(s) end
function love.quit() app:quit() end
