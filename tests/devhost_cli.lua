-- One HTTP request against the stand-in backend, for tests/mock_backend.py.
-- usage: lua tests/devhost_cli.lua <state file>   (request JSON on stdin, answer on stdout)
-- The state file holds every user and match between requests.
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local json=require('online.json')
local Host=require('tests.devhost')
local path=assert(arg[1],'state file required')
local request=assert(json.decode(io.read('*a')))
local host=Host.new({key=request.key,rules=request.rules,token_life=request.token_life})
local file=io.open(path,'rb')
if file then
  local saved=json.decode(file:read('*a'));file:close()
  if saved then
    for k,v in pairs(saved) do if k~='rng' then host[k]=v end end
    host.rng.seed=saved.rng
    -- JSON has no integer keys: seat numbers come back as strings.
    for _,m in pairs(host.matches) do
      local seen={};for k,v in pairs(m.seen or {}) do seen[tonumber(k)]=v end;m.seen=seen
    end
  end
end
host.clock=request.clock
local status,body=host:http(request.method,request.path,request.headers,request.body)
local keep={users=host.users,tokens=json.object(host.tokens),refresh=json.object(host.refresh),
  matches=json.object(host.matches),serial=host.serial,rng=host.rng.seed}
for _,m in pairs(host.matches) do m.seen=json.object(m.seen);m.views=json.object(m.views) end
file=assert(io.open(path,'wb'));file:write(json.encode(keep));file:close()
io.write(json.encode({status=status,body=body}))
