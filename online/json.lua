-- Small JSON codec shared by the game client and the rules server. Pure Lua 5.1-5.4.
-- Encoding: a table with t[1] set (or an empty table) is an array, anything else an object.
-- json.object(t) forces an object. Decoding drops nulls.
local json={}
local object_mt={__name="json.object"}
function json.object(t) return setmetatable(t or {},object_mt) end

local escapes={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
local function escape(c) return escapes[c] or string.format('\\u%04x',c:byte()) end
local function quote(s) return '"'..s:gsub('[%c"\\]',escape)..'"' end
local floor,huge=math.floor,math.huge

local function write(v,out)
  local t=type(v)
  if t=='string' then out[#out+1]=quote(v)
  elseif t=='number' then
    if v~=v or v==huge or v==-huge then error('JSON cannot represent '..tostring(v)) end
    if v==floor(v) and v>-1e15 and v<1e15 then out[#out+1]=string.format('%d',v)
    else out[#out+1]=string.format('%.14g',v) end
  elseif t=='boolean' then out[#out+1]=v and 'true' or 'false'
  elseif t=='nil' then out[#out+1]='null'
  elseif t=='table' then
    if getmetatable(v)~=object_mt and (v[1]~=nil or next(v)==nil) then
      out[#out+1]='['
      for i=1,#v do
        if i>1 then out[#out+1]=',' end
        write(v[i],out)
      end
      out[#out+1]=']'
    else
      out[#out+1]='{'
      local first=true
      for k,x in pairs(v) do
        local kt=type(k)
        if kt~='string' and kt~='number' then error('JSON object key must be a string or number') end
        if not first then out[#out+1]=',' end
        first=false
        out[#out+1]=quote(kt=='number' and string.format('%d',k) or k);out[#out+1]=':'
        write(x,out)
      end
      out[#out+1]='}'
    end
  else error('JSON cannot represent a '..t) end
end
function json.encode(v)
  local out={};write(v,out);return table.concat(out)
end

local function fail(s,i,what) error(string.format('Invalid JSON at byte %d: %s',i,what),0) end
local function utf8(n)
  if n<0x80 then return string.char(n) end
  if n<0x800 then return string.char(0xC0+floor(n/0x40),0x80+n%0x40) end
  if n<0x10000 then return string.char(0xE0+floor(n/0x1000),0x80+floor(n/0x40)%0x40,0x80+n%0x40) end
  return string.char(0xF0+floor(n/0x40000),0x80+floor(n/0x1000)%0x40,0x80+floor(n/0x40)%0x40,0x80+n%0x40)
end
local unescapes={b='\b',f='\f',n='\n',r='\r',t='\t',['"']='"',['\\']='\\',['/']='/'}
local value
local function text(s,i)
  -- s:sub(i,i) is the opening quote.
  local j=i+1;local parts
  while true do
    local a,b=s:find('["\\]',j)
    if not a then fail(s,i,'unterminated string') end
    if s:sub(a,a)=='"' then
      if not parts then return s:sub(i+1,a-1),a+1 end
      parts[#parts+1]=s:sub(j,a-1);return table.concat(parts),a+1
    end
    parts=parts or {};parts[#parts+1]=s:sub(j,a-1)
    local c=s:sub(a+1,a+1)
    if c=='u' then
      local n=tonumber(s:sub(a+2,a+5),16);if not n then fail(s,a,'bad unicode escape') end
      j=a+6
      if n>=0xD800 and n<0xDC00 and s:sub(j,j+1)=='\\u' then
        local low=tonumber(s:sub(j+2,j+5),16)
        if low and low>=0xDC00 and low<0xE000 then n=0x10000+(n-0xD800)*0x400+(low-0xDC00);j=j+6 end
      end
      parts[#parts+1]=utf8(n)
    else
      local r=unescapes[c];if not r then fail(s,a,'bad escape') end
      parts[#parts+1]=r;j=a+2
    end
  end
end
local depth_limit=64
value=function(s,i,depth)
  i=s:find('%S',i) or fail(s,#s,'unexpected end')
  local c=s:sub(i,i)
  if c=='"' then return text(s,i) end
  if c=='{' then
    if depth>depth_limit then fail(s,i,'nested too deeply') end
    local t={};i=s:find('%S',i+1) or fail(s,i,'unexpected end')
    if s:sub(i,i)=='}' then return t,i+1 end
    while true do
      if s:sub(i,i)~='"' then fail(s,i,'expected a key') end
      local k;k,i=text(s,i)
      i=s:find('%S',i) or fail(s,#s,'unexpected end')
      if s:sub(i,i)~=':' then fail(s,i,'expected a colon') end
      t[k],i=value(s,i+1,depth+1)
      i=s:find('%S',i) or fail(s,#s,'unexpected end')
      c=s:sub(i,i)
      if c=='}' then return t,i+1 end
      if c~=',' then fail(s,i,'expected a comma') end
      i=s:find('%S',i+1) or fail(s,i,'unexpected end')
    end
  end
  if c=='[' then
    if depth>depth_limit then fail(s,i,'nested too deeply') end
    local t,n={},0;i=s:find('%S',i+1) or fail(s,i,'unexpected end')
    if s:sub(i,i)==']' then return t,i+1 end
    while true do
      n=n+1;t[n],i=value(s,i,depth+1)
      i=s:find('%S',i) or fail(s,#s,'unexpected end')
      c=s:sub(i,i)
      if c==']' then return t,i+1 end
      if c~=',' then fail(s,i,'expected a comma') end
      i=i+1
    end
  end
  if s:sub(i,i+3)=='true' then return true,i+4 end
  if s:sub(i,i+4)=='false' then return false,i+5 end
  if s:sub(i,i+3)=='null' then return nil,i+4 end
  local a,b=s:find('^-?%d+%.?%d*[eE]?[-+]?%d*',i)
  local n=a and tonumber(s:sub(a,b))
  if not n then fail(s,i,'unexpected character') end
  return n,b+1
end
-- Returns the value, or nil and a message.
function json.decode(s)
  if type(s)~='string' then return nil,'JSON text must be a string' end
  local ok,v,i=pcall(value,s,1,1)
  if not ok then return nil,v end
  if s:find('%S',i) then return nil,'Invalid JSON: trailing characters' end
  return v
end
return json
