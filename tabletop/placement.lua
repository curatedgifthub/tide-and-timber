local Chains=require('chains')
local Placement={}

Placement.guide={
  {title="Play a unit",detail="Start at printed Health. Apply pre-attack Strength and add printed damage modifiers to one ordinary attack. Resolve other Deploy effects and earned chain abilities afterward. A summon uses its printed entry effects."},
  {title="Read the row code",detail="F means Front and B means Back. The first letter tells where to play the unit. The rest give its ordinary attack targets. FF, FB and FFB deploy in Front and attack Front, Back or either. BF, BB and BFB do the same from Back. Movement changes position. The printed code stays with the card."},
  {title="Choose your target",detail="Attack with current Attack Power in either row. Choose an opposing unit in any row named by your attacker. If none are eligible, continue with its abilities. Printed abilities use their own targets. Guard or other printed defenses can prevent damage. At zero Health a unit is defeated."},
  {title="Draw and pass",detail="Open the match with five. Keep your hand and deck order between rounds and draw up to two more. Surviving Units go to their owners’ discards. Draw one on later turns while cards remain."},
  {title="Score remaining Health",detail="When both sides pass or cannot continue, add the current Health of your surviving units in both rows. Higher Health wins. Equal Health draws. Win two rounds to win the match. After three rounds without two wins, the match is drawn."},
  {title="Put a Bridge at either right end",detail="Follow your Front row to the right, cross to the last Back card, then read Back to the left."},
  {title="Connect at least three units by base Strength",detail="Step up by one each time, or down by one. Playing a Unit into a chain of three or more gives it 1 Guard. Its printed Chain ability triggers once per deployment when it reaches its own threshold."},
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
      if member==unit and (not best or ch.length>best.length
        or ch.length==best.length and ch.cross and not best.cross) then best=ch end
    end
  end
  return best
end
return Placement
