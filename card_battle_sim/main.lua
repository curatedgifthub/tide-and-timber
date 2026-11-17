-- Run from this directory: lua main.lua
-- Optional noninteractive mode: lua main.lua --batch 100 Super Fantasy --seed 12345
local function usage()
  print('Usage: lua main.lua [--batch MATCHES PLAYER_FACTION OPPONENT_FACTION [--seed INTEGER] [--size INTEGER]]')
end
local args=arg or {}
if args[1]=='--batch' then
  local Decks=require('decks')
  local Report=require('report')
  local count=tonumber(args[2]);local f1=args[3];local f2=args[4]
  if not count or count%1~=0 or count<1 or count>100000 or not Decks.starter then usage();os.exit(2) end
  local seed=12345;local size=30
  for i=5,#args,2 do
    if args[i]=='--seed' then seed=tonumber(args[i+1])
    elseif args[i]=='--size' then size=tonumber(args[i+1])
    else usage();os.exit(2) end
  end
  if not seed or seed%1~=0 or not size or size<10 or size>40 or size%1~=0 then usage();os.exit(2) end
  local ok,r=pcall(function()
    return Report.batch(Decks.starter(f1,size),Decks.starter(f2,size),{
      matches=count,seed=seed,deck_size=size,player_faction=f1,ai_faction=f2})
  end)
  if not ok then io.stderr:write(tostring(r)..'\n');os.exit(1) end
  print(Report.batch_text(r))
elseif args[1]=='--help' then usage()
elseif #args>0 then usage();os.exit(2)
else
  local ok,err=pcall(function() require('console').main() end)
  if not ok then io.stderr:write('Stopped: '..tostring(err)..'\n');os.exit(1) end
end
