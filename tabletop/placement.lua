local Chains=require('chains')
local Placement={}

Placement.guide={
  {title="Play a unit",detail="Place it at its printed Attack Power (ATK, called Strength on cards) and full Health. Choose an eligible enemy for its ordinary attack. Resolve the card’s Deploy text and earned chain abilities in the same play. A summon uses its printed entry effects."},
  {title="Read the row code",detail="F means Front and B means Back. The first letter tells where to play the unit. The rest give its ordinary attack targets. FF, FB and FFB deploy in Front and attack Front, Back or either. BF, BB and BFB do the same from Back. Movement changes position. The printed code stays with the card."},
  {title="Choose your target",detail="Attack with current Attack Power in either row. Choose an opposing unit in any row named by your attacker. If none are eligible, continue with its abilities. Printed abilities use their own targets. Guard or other printed defenses can prevent damage. At zero Health a unit is defeated."},
  {title="Draw and pass",detail="Start with five cards. Draw one on later turns while your deck has cards. Pass to stop playing for this round. An empty field can still receive reinforcements."},
  {title="Score remaining Health",detail="When both sides pass or cannot continue, add the current Health of your surviving units in both rows. Higher Health wins. Equal Health draws. Win two rounds to win the match. After three rounds without two wins, the match is drawn."},
  {title="Put a Bridge at either right end",detail="Follow your Front row to the right, cross to the last Back card, then read Back to the left."},
  {title="Connect at least three units by base Strength",detail="Step up by one each time, or down by one. A printed Chain ability triggers the first time its unit qualifies each deployment."},
  {title="Try Minnow (1) then Seahorse (2) in Front",detail="Place a unit with base Strength 3 at the right end of Back. Seahorse bridges 1 → 2 → 3 and Minnow draws."},
}
function Placement.bonus(card,row)
  if row~=2 then return end
  if card.id=='Fantasy:4' then return 'Draw 1' end
  if card.id=='Water:30' then return '+1 ATK' end
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
