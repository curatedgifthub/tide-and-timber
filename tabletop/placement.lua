local Chains=require('chains')
local Placement={}

Placement.guide={
  {title="Deploy, attack or pass",detail="Each side has up to eight turns per round. On your turn play a card or make one basic attack. Passing gives up your remaining turns."},
  {title="Front protects Back",detail="Both rows can attack once per unit per round for current Strength. Target Front first. A surviving Front defender counters for half its Strength, rounded down. Back defenders do not counter."},
  {title="Deploy heavy units with support",detail="Units with base Strength 5 or higher enter at half Health, rounded up, unless you have an ally of base Strength 1–3 on the field. Summons and replacements enter at full Health."},
  {title="Use abilities for extra damage and protection",detail="Card abilities follow their own target rules. They can reach behind Front. Guard absorbs damage, healing restores Health, and zero Health defeats the unit. Abilities can grant up to two extra card plays per turn."},
  {title="Win the fight",detail="When both sides finish, more enemy units defeated wins. Break ties by enemy Health removed, then by being the only side with units. Otherwise draw. An empty row or battlefield never ends a round early."},
  {title="Chains add one damage",detail="A Tide or Timber unit in a chain gains +1 basic attack damage. Multiple chains give the bonus only once. Comic cards use named combinations."},
  {title="Put a Bridge at either right end",detail="Follow your Front row to the right, cross to the last Back card, then read Back to the left."},
  {title="Connect at least three units by base Strength",detail="Step up by one each time, or down by one. Matching Chain abilities can then trigger."},
  {title="Try Minnow (1) then Seahorse (2) in Front",detail="Place a unit with base Strength 3 at the right end of Back. Seahorse bridges 1 → 2 → 3 and Minnow draws."},
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
