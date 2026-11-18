local Chains=require('chains')
local Placement={}

Placement.guide={
  {title="Place, strike, resolve",detail="Playing a unit from hand places it and attacks an enemy in the same play. Its Deploy ability resolves next, then any eligible chain abilities. Summons resolve their own abilities. Double Agents infiltrate instead of striking."},
  {title="Front shields Back",detail="A basic attack must hit Front while it is occupied. A surviving defender counters for half its current Strength, rounded down. Special attacks use their own targets."},
  {title="Support from Back",detail="The rightmost other Back ally adds 1 attack damage per 3 current Strength, up to 2. Each member of a numerical chain also gains +1 deployment attack damage, counted once."},
  {title="Deploy heavy units with support",detail="Units of base Strength 5 or more enter at 2 Strength and 2 HP without a friendly base Strength 1–3 unit. Summons and replacements enter at full Strength and Health before their abilities."},
  {title="Reinforcements and recovery",detail="Draw one on subsequent turns. If you cannot play, wait for a draw or for the board to change. Each physical card can be recovered from discard once per round."},
  {title="Win a round",detail="Defeat an opponent who has no fielded units, no draw deck and no legal play. If neither can play or draw, more surviving units wins, with equal forces drawing. Conceding awards the round immediately. Each new round redeals the selected decks."},
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
