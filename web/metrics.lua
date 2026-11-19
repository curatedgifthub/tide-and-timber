-- Presentation data only. Use exactly the public-state helpers the LÖVE board uses.
local json = require('online.json')
local Mirror = require('online.mirror')
local Battle = require('battle')
local Chains = require('chains')
local Placement = require('tabletop.placement')

return function(receiver, payload)
  local view = assert(json.decode(payload or receiver))
  if view.guideCard then
    return require("tabletop.deck_help").describe(require("data.cards").by_id[view.guideCard],view.deck) or ""
  end
  local mirror = Mirror.new()
  local state = mirror:apply(view)
  local seat = view.seat
  local info = {attackPreview=json.object({}),scores={}, units=json.object({}), hand={}, school=Battle.can_school(state,seat)}
  for p, player in ipairs(state.players) do
    info.scores[p] = Battle.score(state,p)
    for r, row in ipairs(player.rows) do
      for pos, unit in ipairs(row) do
        info.units[tostring(unit.uid)] = {strength=Battle.strength(state,unit),seat=p,row=r,pos=pos}
      end
    end
    for _, chain in ipairs(Chains.find(player)) do
      for _, unit in ipairs(chain.units) do
        local entry = info.units[tostring(unit.uid)]
        entry.chain = math.max(chain.length,entry.chain or 0)
        entry.cross = entry.cross or chain.cross
      end
    end
  end
  local prompt=mirror.prompt
  if prompt and prompt.context and prompt.context.op=='deploy_attack' then
    local source=prompt.context.unit
    if source then
      for _,target in ipairs(Battle.attack_targets(state,seat,source)) do
        info.attackPreview[tostring(target.uid)]=Battle.attack_power(state,source,target)
      end
    end
  end
  for i, unit in ipairs(state.players[seat].hand) do
    local ok, reason = Battle.playable(state,seat,i)
    local side=Battle.deploy_side(seat,unit.card)
    local r=Battle.placement_row(unit.card)
    info.hand[i] = {ok=ok, reason=reason, side=side, row=r}
    if ok and unit.uid==view.previewUid and unit.card.type=='Unit' and not unit.card.replaces then
      info.slots={{},{}}
      local last=#state.players[side].rows[r]+1
      for pos=1,last do
        local ch=Placement.preview(state.players[side],r,pos,unit.card)
        info.slots[r][pos]={cross=ch and ch.cross,chain=ch and ch.length,
          bonus=Placement.bonus(unit.card,r),endpoint=unit.card.bridge and pos==last}
      end
    end
  end
  return json.encode(info)
end
