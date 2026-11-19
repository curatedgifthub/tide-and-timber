-- Player-facing wording shared by the desktop views and the browser catalog.
local Text={}
function Text.event(line)
  return (line:gsub("#%d+",""))
end
function Text.rows(card)
  if not card.designation then return "" end
  local code=card.designation
  local names={F="Front",B="Back",FB="either row"}
  return code.." · Deploy "..names[code:sub(1,1)].." · Attack "..names[code:sub(2)]
end
function Text.stats(card,strength,hp)
  if card.type~="Unit" then return "Effect" end
  return (strength or card.strength).." ATK   "..(hp or card.health).."/"..card.health.." HP"
end
return Text
