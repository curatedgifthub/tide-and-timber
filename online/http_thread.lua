-- Network worker. Requests arrive on one channel and answers leave on another, so the
-- game window keeps drawing while a request is in flight.
local requests,answers,saveDirectory,prefer=...
require('love.filesystem')
local Http=require('online.http')
local counter=0
local request,name=Http.backend({scratch=function(kind)
  counter=counter+1
  love.filesystem.createDirectory('net')
  return saveDirectory..'/net/'..kind..'-'..counter..'.tmp'
end},prefer)
answers:push({ready=true,backend=name})
while true do
  local req=requests:demand()
  if req=='quit' then break end
  if not request then
    answers:push({id=req.id,error='This computer has no way to make HTTPS requests (libcurl or the curl command is needed).'})
  else
    local ok,status,body=pcall(request,req)
    if ok and status then answers:push({id=req.id,status=status,body=body})
    else answers:push({id=req.id,error=tostring(body or status or 'request failed')}) end
  end
end
