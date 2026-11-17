-- Stable, human-editable Lua table persistence (loads in an empty environment).
local Save={}
local function serialize(value,depth)
  local typ=type(value); depth=depth or 0
  if depth>40 then error('Data nesting too deep') end
  if typ=='string' then return string.format('%q',value) end
  if typ=='number' or typ=='boolean' then return tostring(value) end
  if typ~='table' then error('Unsupported persisted data type: '..typ) end
  local entries={}
  local keys={};for k in pairs(value) do keys[#keys+1]=k end
  table.sort(keys,function(a,b)
    if type(a)==type(b) then return a<b end
    return type(a)<type(b)
  end)
  for _,key in ipairs(keys) do
    local k=(type(key)=='string' and key:match('^[%a_][%w_]*$')) and key or '['..serialize(key,depth+1)..']'
    entries[#entries+1]='['..string.format('%q',tostring(key))..']='..serialize(value[key],depth+1)
    if type(key)=='number' then entries[#entries]='['..tostring(key)..']='..serialize(value[key],depth+1) end
  end
  return '{'..table.concat(entries,',')..'}'
end
local function path(kind,name)
  if not name or not name:match('^[%w_%-]+$') or #name>80 then return nil,'Invalid save name (letters, numbers, _ and - only)' end
  return 'saves/'..kind..'_'..name..'.lua'
end
function Save.write(kind,name,data)
  local p,err=path(kind,name);if not p then return false,err end
  -- Save directory is included with the distribution; create it if missing.
  local keep=io.open('saves/.keep','a')
  if not keep then
    if package.config:sub(1,1)=='\\' then
      os.execute('mkdir saves >NUL 2>NUL')
    else
      os.execute('mkdir -p saves >/dev/null 2>&1')
    end
    keep=io.open('saves/.keep','a')
  end
  if keep then keep:close() end
  local file,e=io.open(p,'w');if not file then return false,e end
  local ok,msg=pcall(function() file:write('return ',serialize(data),'\n') end)
  file:close()
  if not ok then return false,msg end
  return true,p
end
function Save.read(kind,name)
  local p,err=path(kind,name);if not p then return nil,err end
  local file=io.open(p,'r')
  if not file then return nil,'No saved configuration: '..name end
  local src=file:read('*a');file:close()
  if #src>2000000 then return nil,'Save file too large' end
  local fun,parse_error=load(src,'@'..p,'t',{})
  if not fun then return nil,parse_error end
  local ok,result=pcall(fun)
  if not ok or type(result)~='table' then return nil,'Invalid save file' end
  return result
end
return Save
