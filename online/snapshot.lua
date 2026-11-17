-- Saves and restores a battle state between server requests.
-- The state is a graph of plain tables (card instances are shared between zones), so the
-- snapshot records every table once and keeps references intact. Catalog cards are stored
-- by id, functions are dropped (the server re-attaches them), and the result is a Lua chunk
-- of plain assignments, which the Lua parser reads far faster than a JSON decoder written
-- in Lua. Snapshots are written and read only by the server.
local Snap={}
local ident='^[%a_][%w_]*$'
local reserved={}
for word in ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while'):gmatch('%a+') do
  reserved[word]=true
end
local function scalar(v)
  local t=type(v)
  if t=='number' then
    if v~=v then error('snapshot cannot hold NaN') end
    if v==math.huge then return '1/0' end
    if v==-math.huge then return '-1/0' end
    if v==math.floor(v) and v>-1e15 and v<1e15 then return string.format('%d',v) end
    return string.format('%.17g',v)
  elseif t=='string' then return (string.format('%q',v):gsub('\\\n','\\n'))
  elseif t=='boolean' then return v and 'true' or 'false' end
end
-- by_id: the card catalog index. skip: keys of the root table to leave out.
function Snap.dump(root,by_id,skip)
  local ids,count,out={},0,{}
  local function ref(v)
    if by_id[v.id]==v then return 'C['..scalar(v.id)..']' end
    return 'T['..ids[v]..']'
  end
  local function visit(t,top)
    count=count+1;ids[t]=count
    local me=count
    local keys={}
    for k in pairs(t) do
      if type(k)~='string' and type(k)~='number' then error('snapshot keys must be strings or numbers') end
      keys[#keys+1]=k
    end
    table.sort(keys,function(a,b)
      if type(a)==type(b) then return a<b end
      return type(a)=='number'
    end)
    local pending={}
    for _,k in ipairs(keys) do
      local v=t[k];local tv=type(v)
      if not (top and skip and skip[k]) and tv~='function' then
        local key=(type(k)=='string' and k:match(ident) and not reserved[k]) and '.'..k or '['..scalar(k)..']'
        if tv=='table' then
          if by_id[v.id]~=v and not ids[v] then visit(v) end
          pending[#pending+1]='T['..me..']'..key..'='..ref(v)
        else
          local text=scalar(v);if not text then error('snapshot cannot hold a '..tv) end
          pending[#pending+1]='T['..me..']'..key..'='..text
        end
      end
    end
    for _,line in ipairs(pending) do out[#out+1]=line end
  end
  visit(root,true)
  return 'local T,C=... for i=1,'..count..' do T[i]={} end\n'..table.concat(out,'\n')..'\n'
end
function Snap.load(text,by_id)
  local chunk,why=load(text,'=snapshot','t',{})
  if not chunk then error('Unreadable snapshot: '..tostring(why)) end
  local T={}
  chunk(T,by_id)
  return T[1]
end
return Snap
