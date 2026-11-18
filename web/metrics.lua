-- Presentation data only. Use exactly the public-state helpers the LÖVE board uses.
local json = require('online.json')
local Mirror = require('online.mirror')
local Battle = require('battle')
local Chains = require('chains')
local Placement = require('tabletop.placement')

return function(receiver, payload)
  local view = assert(json.decode(payload or receiver))
  local state = Mirror.new():apply(view)
  local seat = view.seat
  local info = {scores={}, units=json.object({}), hand={}, school=Battle.can_school(state,seat)}
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
  for i, unit in ipairs(state.players[seat].hand) do
    local ok, reason = Battle.playable(state,seat,i)
    local side=Battle.deploy_side(seat,unit.card)
    info.hand[i] = {ok=ok, reason=reason, side=side}
    if ok and unit.uid==view.previewUid and unit.card.type=='Unit' and not unit.card.replaces then
      info.slots={{},{}}
      for r,row in ipairs(state.players[side].rows) do
        for pos=1,#row+1 do
          local ch=Placement.preview(state.players[side],r,pos,unit.card)
          info.slots[r][pos]={cross=ch and ch.cross,chain=ch and ch.length,
            bonus=Placement.bonus(unit.card,r),endpoint=unit.card.bridge and pos==#row+1}
        end
      end
    end
  end
  return json.encode(info)
end
