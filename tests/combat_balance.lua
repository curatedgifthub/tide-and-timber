-- Reproducible matchups. Alternate seats with identical decks for each seed.
-- lua tests/combat_balance.lua [seeds per matchup] [first seed]
package.path="card_battle_sim/?.lua;./?.lua;"..package.path
local B,L,AI,U=require('battle'),require('tabletop.library'),require('ai'),require('util')
local samples=tonumber(arg[1]) or 30
local first=tonumber(arg[2]) or 1
local function deck(f,style,seed)
  local cfg=L.new();cfg.factions[1]=f
  if style=="starter" then L.starter(cfg,1,30);return cfg.decks[1] end
  local pool={}
  for _,c in ipairs(L.collection(f)) do pool[#pool+1]=c end
  local rng=U.rng(seed);rng:shuffle(pool)
  if style=="heavy" then
    table.sort(pool,function(a,b)
      local function weight(c) return (c.strength or 0)+(c.health or 0)*0.35 end
      if weight(a)==weight(b) then return a.id<b.id end
      return weight(a)>weight(b)
    end)
  end
  local out={}
  for _,c in ipairs(pool) do
    local copies=style=="heavy" and L.owned[f][c.id] or 1
    for _=1,copies do out[#out+1]=c.id;if #out==30 then return out end end
  end
end
local function matchup(f,g,styles,levels)
  local wins={0,0};local draws,firstWins,attacks,rounds,ko=0,0,0,0,0
  for seed=first,first+samples-1 do
    local a,b=deck(f,styles[1],seed*271),deck(g,styles[2],seed*419)
    for swap=0,1 do
      local s=B.new(swap==0 and a or b,swap==0 and b or a,{seed=seed*97})
      while not s.finished do
        local p=s.active
        local move=AI.decision(s,p,levels[swap==0 and p or 3-p])
        if move.type=="attack" then
          attacks=attacks+1;assert(B.attack(s,p,move.attacker,move.target))
        elseif move.type=="play" then assert(B.play(s,p,move.index,move.row,move.pos))
        elseif move.type=="school" then assert(B.school(s,p))
        else assert(B.pass(s,p)) end
      end
      for _,r in ipairs(s.round_history) do rounds=rounds+1;ko=ko+r.scores[1]+r.scores[2] end
      if s.winner==0 then draws=draws+1
      else
        local side=swap==0 and s.winner or 3-s.winner;wins[side]=wins[side]+1
        if s.winner==s.first_round_starter then firstWins=firstWins+1 end
      end
    end
  end
  print(string.format("%s/%s vs %s/%s (%s/%s): %d-%d, %d draws; opener %d/%d; attacks %.1f/match; defeats %.1f/round",
    f,styles[1],g,styles[2],levels[1],levels[2],wins[1],wins[2],draws,firstWins,2*samples,attacks/(2*samples),ko/rounds))
end
for i,f in ipairs(L.factions) do
  for j=i+1,#L.factions do local g=L.factions[j]
    for _,style in ipairs({'starter','random','heavy'}) do matchup(f,g,{style,style},{'normal','normal'}) end
    matchup(f,g,{'starter','starter'},{'easy','normal'})
  end
  matchup(f,f,{'heavy','starter'},{'normal','normal'})
end
