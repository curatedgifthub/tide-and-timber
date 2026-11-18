local Chains=require('chains')
local Placement={}

Placement.guide={
  {title="Front and Back both score",detail="Every surviving unit adds its current Strength. Swordfish can hit only the Front."},
  {title="Choose a row for its abilities",detail="Halfling Courier draws in Back. Night Wraith can weaken a unit in Back."},
  {title="Put a Bridge at either right end",detail="Follow your Front row to the right, cross to the last Back card, then read Back to the left."},
  {title="Connect three or more printed ranks",detail="Step up by one each time, or down by one. Matching Chain abilities can then trigger."},
  {title="Try Minnow (1) then Seahorse (2) in Front",detail="Put a rank 3 at the right end of Back. Seahorse bridges 1 → 2 → 3 and Minnow draws."},
}
function Placement.bonus(card,row)
  if row~=2 then return end
  if card.id=='Fantasy:4' then return 'Draw 1' end
  if card.id=='Water:30' then return '+1 STR' end
end
-- Inspect the board immediately after insertion, before any Deploy abilities resolve.
function Placement.preview(player,row,pos,card)
  if not Chains.eligible(card) then return end
  local clone={rows={{},{}}}
  for r,lane in ipairs(player.rows) do for i,u in ipairs(lane) do clone.rows[r][i]=u end end
  local unit={card=card}
  table.insert(clone.rows[row],pos,unit)
  local best
  for _,ch in ipairs(Chains.find(clone)) do
    for _,member in ipairs(ch.units) do
      if member==unit and (not best or ch.cross and not best.cross
        or ch.cross==best.cross and ch.length>best.length) then best=ch end
    end
  end
  return best
end
return Placement
