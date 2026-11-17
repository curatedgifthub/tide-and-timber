-- Blocking HTTPS requests for the network thread (and for tests run with plain Lua).
-- LÖVE 11 has no HTTPS of its own, so this uses what the operating system ships:
--   1. the "https" module when one can be loaded (built into LÖVE 12, or lua-https beside the game),
--   2. the system libcurl through LuaJIT's FFI (macOS and Linux),
--   3. the curl command (also present on Windows 10 and later).
-- Each backend is a function(request) returning status, body or nil, message.
local Http={}

local function with_https()
  local ok,https=pcall(require,'https')
  if not ok or type(https)~='table' or not https.request then return nil end
  return function(req)
    local code,body=https.request(req.url,{method=req.method,headers=req.headers,data=req.body})
    if not code or code==0 then return nil,tostring(body or 'request failed') end
    return code,body or ''
  end
end

local function with_libcurl()
  local ok,ffi=pcall(require,'ffi')
  if not ok then return nil end
  local declared=pcall(ffi.cdef,[[
    void *curl_easy_init(void);
    int curl_easy_setopt(void *handle,int option,...);
    int curl_easy_perform(void *handle);
    void curl_easy_cleanup(void *handle);
    int curl_easy_getinfo(void *handle,int info,...);
    void *curl_slist_append(void *list,const char *text);
    void curl_slist_free_all(void *list);
    const char *curl_easy_strerror(int code);
    int curl_global_init(long flags);
    void *tmpfile(void);
    size_t fread(void *buffer,size_t size,size_t count,void *stream);
    int fseek(void *stream,long offset,int origin);
    long ftell(void *stream);
    int fclose(void *stream);
  ]])
  if not declared then return nil end
  local lib
  for _,name in ipairs({'curl','libcurl.so.4','libcurl-gnutls.so.4','/usr/lib/libcurl.4.dylib'}) do
    local loaded,l=pcall(ffi.load,name)
    if loaded then lib=l;break end
  end
  if not lib or not pcall(function() return lib.curl_easy_init end) then return nil end
  lib.curl_global_init(3)
  local C=ffi.C
  local long=function(n) return ffi.cast('long',n) end
  -- Option numbers from curl/curl.h.
  local WRITEDATA,URL,HTTPHEADER,USERAGENT,COPYPOSTFIELDS=10001,10002,10023,10018,10165
  local TIMEOUT,POST,POSTFIELDSIZE,CONNECTTIMEOUT,NOSIGNAL=13,47,60,78,99
  local RESPONSE_CODE=0x200002
  return function(req)
    local handle=lib.curl_easy_init()
    if handle==nil then return nil,'curl could not start' end
    -- Without a write callback libcurl writes the body to this FILE*, so no FFI callback is needed.
    local file=C.tmpfile()
    if file==nil then lib.curl_easy_cleanup(handle);return nil,'no temporary file for the response' end
    local list=nil
    for name,value in pairs(req.headers or {}) do list=lib.curl_slist_append(list,name..': '..value) end
    -- An empty Expect header stops curl from waiting for "100 Continue" on larger bodies.
    list=lib.curl_slist_append(list,'Expect:')
    lib.curl_easy_setopt(handle,URL,req.url)
    lib.curl_easy_setopt(handle,WRITEDATA,file)
    lib.curl_easy_setopt(handle,HTTPHEADER,list)
    lib.curl_easy_setopt(handle,USERAGENT,'tide-and-timber')
    lib.curl_easy_setopt(handle,NOSIGNAL,long(1))
    lib.curl_easy_setopt(handle,CONNECTTIMEOUT,long(10))
    lib.curl_easy_setopt(handle,TIMEOUT,long(req.timeout or 25))
    if req.method~='GET' then
      local body=req.body or ''
      lib.curl_easy_setopt(handle,POST,long(1))
      lib.curl_easy_setopt(handle,POSTFIELDSIZE,long(#body))
      lib.curl_easy_setopt(handle,COPYPOSTFIELDS,body)
    end
    local result=lib.curl_easy_perform(handle)
    local status,text,why
    if result==0 then
      local code=ffi.new('long[1]')
      lib.curl_easy_getinfo(handle,RESPONSE_CODE,code)
      -- 64-bit C integers arrive as boxed values; turn them into plain numbers first.
      local size=tonumber(C.ftell(file))
      C.fseek(file,0,0)
      local buffer=ffi.new('char[?]',math.max(1,size))
      local n=size>0 and tonumber(C.fread(buffer,1,size,file)) or 0
      status,text=tonumber(code[0]),ffi.string(buffer,n)
    else why=ffi.string(lib.curl_easy_strerror(result)) end
    C.fclose(file);lib.curl_slist_free_all(list);lib.curl_easy_cleanup(handle)
    if not status then return nil,why end
    return status,text
  end
end

-- env.scratch(name) returns a writable file path; env.windows says how to quote.
local function with_curl_command(env)
  env=env or {}
  local scratch=env.scratch or function(name) return os.tmpname() end
  local function quoted(text) return '"'..tostring(text):gsub('[\\"]','\\%0'):gsub('\r?\n',' ')..'"' end
  local function put(path,text)
    local f=io.open(path,'wb');if not f then return false end
    f:write(text);f:close();return true
  end
  local function get(path)
    local f=io.open(path,'rb');if not f then return nil end
    local text=f:read('*a');f:close();return text
  end
  return function(req)
    local config,bodyFile,outFile=scratch('request'),scratch('body'),scratch('answer')
    if not put(bodyFile,req.body or '') then return nil,'cannot write the request to disk' end
    -- Everything goes through a config file, so no header or token appears on a command line.
    local lines={'silent','show-error','url = '..quoted(req.url),'request = '..quoted(req.method or 'POST'),
      'max-time = '..(req.timeout or 25),'connect-timeout = 10','output = '..quoted(outFile),
      'write-out = "%{http_code}"','header = "Expect:"'}
    if req.method~='GET' then lines[#lines+1]='data-binary = '..quoted('@'..bodyFile) end
    for name,value in pairs(req.headers or {}) do lines[#lines+1]='header = '..quoted(name..': '..value) end
    if not put(config,table.concat(lines,'\n')..'\n') then return nil,'cannot write the request to disk' end
    local pipe=io.popen('curl -K '..quoted(config)..' 2>&1','r')
    if not pipe then return nil,'the curl command is not available' end
    local printed=pipe:read('*a') or '';pipe:close()
    local body=get(outFile) or ''
    os.remove(config);os.remove(bodyFile);os.remove(outFile)
    local status=tonumber(printed:match('(%d%d%d)%s*$'))
    if not status or status==0 then
      return nil,(printed:gsub('%d*%s*$',''):gsub('^curl: %(%d+%) ','')):sub(1,160)
    end
    return status,body
  end
end

Http.https,Http.libcurl,Http.command=with_https,with_libcurl,with_curl_command
-- prefer: optional backend name, for tests. Returns the request function and its name.
function Http.backend(env,prefer)
  for _,name in ipairs(prefer and {prefer} or {'https','libcurl','command'}) do
    local make=Http[name]
    local fn=make and make(env)
    if fn then return fn,name end
  end
  return nil,'none'
end
return Http
