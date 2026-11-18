-- Player-facing wording shared by the desktop views and the browser catalog.
local Text={}
function Text.event(line)
  return (line:gsub("#%d+",""))
end
function Text.stats(card,strength,hp)
  if card.type~="Unit" then return "Effect" end
  return (strength or card.strength).." STR   "..(hp or card.health).."/"..card.health.." HP"
end
return Text
