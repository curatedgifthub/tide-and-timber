-- Virtual tabletop coordinates. The same transform is used for pointer input.
local Lib=require('tabletop.library')
local G=love.graphics
local P={
  W=1280,H=800, bg={.065,.092,.090},panel={.095,.129,.123},
  inset={.075,.106,.101},rule={.245,.290,.246}, muted={.62,.67,.60},
  textColor={.925,.92,.832}, gold={.83,.685,.405}, bright={.895,.765,.489},
  dark={.12,.145,.105}, red={.91,.56,.44}, black={.04,.058,.054},
  fonts={}, images={}, hits={},time=0,
}
local fontPaths={serif="serif",italic="italic",sans="sans",bold="bold"}
function P.font(size,face)
  face=face or "sans"
  local key=face..size
  if not P.fonts[key] then P.fonts[key]=G.newFont("tabletop/assets/fonts/"..fontPaths[face]..".ttf",size) end
  return P.fonts[key]
end
function P.color(c,a) G.setColor(c[1],c[2],c[3],a or c[4] or 1) end
function P.box(x,y,w,h,c,a) P.color(c,a);G.rectangle("fill",x,y,w,h) end
function P.border(x,y,w,h,c,a) P.color(c,a);G.setLineWidth(1);G.rectangle("line",x+.5,y+.5,w-1,h-1) end
function P.line(x1,y1,x2,y2,c,a) P.color(c,a);G.setLineWidth(1);G.line(x1+.5,y1+.5,x2+.5,y2+.5) end
function P.text(s,x,y,size,c,face,w,align)
  G.setFont(P.font(size,face));P.color(c or P.textColor)
  if w then G.printf(tostring(s),x,y,w,align or "left") else G.print(tostring(s),x,y) end
end
function P.one(s,x,y,w,size,c,face,align)
  s=tostring(s);local f=P.font(size,face)
  local scale=math.min(1,w/math.max(1,f:getWidth(s)))
  local offset=align=="center" and (w-f:getWidth(s)*scale)/2 or align=="right" and w-f:getWidth(s)*scale or 0
  P.color(c or P.textColor);G.setFont(f);G.print(s,x+offset,y+(1-scale)*size/2,0,scale,scale)
end
function P.label(s,x,y,c) P.text(s:upper(),x,y,12,c or P.muted,"bold") end
function P.diamond(x,y,r,c,fill)
  P.color(c);G.polygon(fill and "fill" or "line",x,y-r,x+r,y,x,y+r,x-r,y)
end
function P.inside(x,y,w,h) return P.mx>=x and P.mx<x+w and P.my>=y and P.my<y+h end
function P.hit(id,x,y,w,h,fn,hover)
  P.hits[#P.hits+1]={id=id,x=x,y=y,w=w,h=h,fn=fn}
  if hover and P.inside(x,y,w,h) then hover() end
end
function P.button(id,title,x,y,w,h,fn,style,enabled)
  local on=enabled~=false
  local hovered=on and P.inside(x,y,w,h)
  local fill=style=="gold" and (hovered and P.bright or P.gold) or hovered and P.rule or P.panel
  if not on then fill=P.inset end
  P.box(x,y,w,h,fill);P.border(x,y,w,h,style=="gold" and on and P.gold or P.rule)
  P.one(title,x+7,y+(h-22)/2,w-14,17,
    not on and P.muted or style=="gold" and P.dark or style=="accent" and P.gold or P.textColor,"bold","center")
  if on then P.hit(id,x,y,w,h,fn) end
end
function P.icon(kind,x,y,r,c)
  P.color(c);G.setLineWidth(math.max(1,r/12))
  if kind=="wave" then
    for j=-1,1 do
      local v={}
      for i=0,16 do v[#v+1]=x-r+i*r/8;v[#v+1]=y+j*r*.44+math.sin(i/16*math.pi*2)*r*.25 end
      G.line(v)
    end
  elseif kind=="leaf" then
    G.polygon("line",x-r*.63,y+r*.73,x-r*.72,y-r*.18,x-r*.12,y-r*.78,x+r*.75,y-r*.88,x+r*.65,y+r*.02,x+r*.10,y+r*.54)
    G.line(x-r*.78,y+r*.88,x+r*.50,y-r*.62)
    G.line(x-r*.38,y+r*.36,x-r*.43,y-r*.16)
    G.line(x-r*.05,y+r*.02,x+r*.43,y+r*.03)
  elseif kind=="bolt" then
    G.polygon("line",x+r*.22,y-r,x-r*.74,y+r*.15,x-r*.08,y+r*.1,x-r*.26,y+r,x+r*.74,y-r*.25,x+r*.05,y-r*.18)
  else
    G.polygon("line",x-r*.84,y-r*.60,x+r*.24,y-r*.94,x+r*.70,y+r*.55,x-r*.43,y+r*.89)
    G.polygon("line",x-r*.57,y-r*.79,x+r*.55,y-r*.7,x+r*.43,y+r*.79,x-r*.67,y+r*.7)
    P.diamond(x,y,r*.25,c)
  end
  G.setLineWidth(1)
end
function P.image(path)
  if P.images[path]==nil then
    P.images[path]=love.filesystem.getInfo(path,"file") and G.newImage(path) or false
  end
  return P.images[path]
end
local availableArt={}
-- Artwork comes only from the card's own ID in tabletop/card_art.lua (or an explicit
-- card.art path). There is no substitute image: a card outside the playable pool, or a
-- mapped file that fails to load, is drawn as a labelled ART MISSING error tile.
function P.artPath(card)
  local path=card.art or Lib.art[card.id]
  if not path then return nil end
  if availableArt[path]==nil then availableArt[path]=love.filesystem.getInfo(path,"file")~=nil end
  return availableArt[path] and path or nil
end
function P.art(card,x,y,w,h)
  local spec=Lib.specs[card.faction]
  local path=P.artPath(card)
  if path then
    local image=P.image(path)
    local scale=math.min(w/image:getWidth(),h/image:getHeight())
    G.setColor(1,1,1);G.draw(image,x+(w-image:getWidth()*scale)/2,y+(h-image:getHeight()*scale)/2,0,scale,scale)
  else
    local cy=y+h/2
    local size=math.min(w,h)>90 and 17 or 12
    P.box(x+w*.06,cy-4,w*.88,size*2+5,P.red)
    P.one("ART MISSING",x+3,cy-4,w-6,size,P.black,"bold","center")
    P.one(card.id,x+3,cy+size-2,w-6,size-2,P.black,"sans","center")
  end
end
-- Ruled fields and engraved rings give the original sprites a common print frame.
function P.plate(spec,x,y,w,h,hero)
  P.box(x,y,w,h,spec.paper)
  local cx,cy=x+w*.5,y+h*.51
  local r=math.min(w*.40,h*.42)
  P.color(spec.ink,.24);G.setLineWidth(1)
  G.circle("line",cx,cy,r);G.circle("line",cx,cy,r*.94);G.circle("line",cx,cy,r*.72)
  for i=0,(hero and 79 or 39) do
    local a=i*2*math.pi/(hero and 80 or 40);local rr=(i%5==0 and .86 or .96)*r
    G.line(cx+math.cos(a)*rr,cy+math.sin(a)*rr,cx+math.cos(a)*r,cy+math.sin(a)*r)
  end
  for i=0,8 do
    local len=(9-i)*math.min(w,h)*.021
    P.line(x+4,y+4+i*4,x+4+len,y+4+i*4,spec.ink,.20)
    P.line(x+w-4-len,y+h-4-i*4,x+w-4,y+h-4-i*4,spec.ink,.20)
  end
  if hero then
    for i=1,12 do
      local coords={}
      for j=0,56 do
        local t=j/56
        local yy=math.sin(t*7+i*.20)*3+math.cos(t*13+i*.13)*4
        coords[#coords+1]=x+t*(w-8)+4;coords[#coords+1]=y+h-11-i*3+yy
      end
      P.color(spec.ink,.20);G.line(coords)
    end
  end
end
function P.card(card,x,y,w,h,opt)
  opt=opt or {}
  local spec=Lib.specs[card.faction]
  local tiny=h<120
  local foot=tiny and 20 or math.max(30,math.floor(h*.24))
  local lip=tiny and 2 or 4
  local edge=opt.selected and P.bright or opt.chain and spec.color or P.rule
  P.box(x+2,y+3,w,h,P.black,.7);P.box(x,y,w,h,spec.ink);P.border(x,y,w,h,edge)
  local ax,ay,aw,ah=x+lip,y+lip,w-2*lip,h-foot-lip
  P.plate(spec,ax,ay,aw,ah)
  P.art(card,ax+3,ay+3,aw-6,ah-6)
  local sz=tiny and 18 or 24
  P.box(ax,ay,sz,sz,spec.ink)
  if card.strength then
    P.one(opt.strength or card.strength,ax,ay+1,sz,tiny and 15 or 19,
      opt.strength and opt.strength~=card.strength and P.bright or P.textColor,"bold","center")
  else P.diamond(ax+sz/2,ay+sz/2,sz*.23,P.gold) end
  if opt.strength and opt.strength~=card.strength then
    P.box(ax,ay+sz,sz,15,P.black)
    P.one("R"..card.strength,ax,ay+sz,sz,11,P.gold,"bold","center")
  end
  if opt.hp and opt.hp~=card.health then
    P.box(ax+aw-23,ay,23,18,P.black);P.one(opt.hp.."♥",ax+aw-23,ay,23,13,P.red,"bold","center")
  end
  local ty=y+h-foot
  P.one(card.display_name or card.name,x+5,ty+(tiny and 1 or 4),w-10,tiny and 13 or 18,P.textColor,"serif","center")
  if not tiny and foot>=41 then
    P.one(card.type:upper()..(card.health and "   ·   "..card.health.." HP" or ""),x+4,ty+24,w-8,11,spec.color,"bold","center")
  end
  if opt.selected or opt.chain then P.box(x,y+h-3,w,3,edge) end
  if opt.activated then P.diamond(x+w-9,y+h-10,4,P.gold,true) end
end
function P.header(section)
  P.box(0,0,1280,70,P.inset);P.line(0,69,1280,69,P.rule)
  P.icon("cards",46,34,19,P.gold)
  P.text("Tide & Timber",80,12,36,P.textColor,"serif")
  P.line(319,21,319,49,P.rule)
  P.label(section,341,29,P.gold)
end
function P.transform()
  local w,h=G.getDimensions()
  P.scale=math.min(w/P.W,h/P.H);P.ox=(w-P.W*P.scale)/2;P.oy=(h-P.H*P.scale)/2
end
function P.point(x,y) return (x-P.ox)/P.scale,(y-P.oy)/P.scale end
function P.begin()
  P.transform();P.mx,P.my=P.point(love.mouse.getPosition())
  P.hits={};G.clear(P.black);G.push();G.translate(P.ox,P.oy);G.scale(P.scale)
  P.box(0,0,1280,800,P.bg)
end
function P.finish() G.pop() end
function P.click(x,y,b)
  for i=#P.hits,1,-1 do
    local q=P.hits[i]
    if x>=q.x and x<q.x+q.w and y>=q.y and y<q.y+q.h then
      P.hits={};q.fn(b);return true
    end
  end
end
return P
