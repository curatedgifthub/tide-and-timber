local Chains={}
local function groups(path, seam)
  local found={}
  for start=1,#path do
    local dir=nil
    for stop=start+1,#path do
      local previous=path[stop-1].card.strength
      local delta=path[stop].card.strength-previous
      if math.abs(delta)~=1 then break end
      if dir and delta~=dir then break end
      dir=delta
      if stop-start+1>=3 then
        local across=seam and start<=seam and stop>seam or false
        local units={}
        for k=start,stop do units[#units+1]=path[k] end
        found[#found+1]={units=units,length=#units,cross=across,direction=dir>0 and 'ascending' or 'descending'}
      end
    end
  end
  return found
end
function Chains.find(player)
  local out={}
  local front,back=player.rows[1],player.rows[2]
  for _,row in ipairs(player.rows) do
    for _,g in ipairs(groups(row)) do out[#out+1]=g end
  end
  if #front>0 and #back>0 then
    local f=front[#front];local b=back[#back]
    if (f.card.bridge and not f.disabled or b.card.bridge and not b.disabled) and math.abs(f.card.strength-b.card.strength)==1 then
      local path={}
      for _,u in ipairs(front) do path[#path+1]=u end
      for i=#back,1,-1 do path[#path+1]=back[i] end
      for _,g in ipairs(groups(path,#front)) do
        if g.cross then out[#out+1]=g end
      end
    end
  end
  return out
end
function Chains.qualify(player,unit,min_len,cross)
  local best=nil
  for _,g in ipairs(Chains.find(player)) do
    if g.length>=min_len and (not cross or g.cross) then
      for _,u in ipairs(g.units) do
        if u==unit and (not best or best.length<g.length) then best=g end
      end
    end
  end
  return best
end
return Chains
