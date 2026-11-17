local B=require('battle')
local R={}
local function format_counts(t)
  local ks={};for k in pairs(t) do ks[#ks+1]=k end;table.sort(ks)
  local a={};for _,k in ipairs(ks) do a[#a+1]=k..'='..t[k] end
  return table.concat(a,', ')
end
function R.summary(s,reward)
  local x=B.report(s);local o={}
  o[#o+1]='Match winner: '..(x.winner==0 and 'Draw' or x.winner==1 and 'Player' or 'Opponent')
  for _,r in ipairs(x.rounds) do
    o[#o+1]=string.format('Round %d: Player %d - Opponent %d (%s)',r.round,r.scores[1],r.scores[2],r.winner==0 and 'tie' or r.winner==1 and 'Player' or 'Opponent')
  end
  o[#o+1]=string.format('Cards played: %d / %d',x.played[1],x.played[2])
  o[#o+1]=string.format('Cards in hand: %d / %d',x.hand_remaining[1],x.hand_remaining[2])
  o[#o+1]=string.format('Cards drawn (including opening 10): %d / %d',x.drawn[1],x.drawn[2])
  o[#o+1]=string.format('Cards discarded: %d / %d',x.discarded[1],x.discarded[2])
  o[#o+1]=string.format('Chain abilities activated: %d / %d',x.chains[1],x.chains[2])
  o[#o+1]=string.format('Chains completed: %d / %d',x.chains_completed[1],x.chains_completed[2])
  o[#o+1]='Completed chain lengths: '..format_counts(x.chain_completions_by_length)
  o[#o+1]='Chain lengths activated: '..format_counts(x.chain_sizes)
  o[#o+1]='Abilities used (card IDs): '..format_counts(x.abilities)
  o[#o+1]='Reward earned: '..(reward or 'none')
  return table.concat(o,'\n')
end
function R.batch(deck1,deck2,opts)
  opts=opts or {};local AI=require('ai')
  local count=assert(tonumber(opts.matches));assert(count>0 and count<=100000 and count%1==0)
  local results={wins={0,0},draws=0,rounds=0,chain={0,0},
    completed={0,0},completed_lengths={},activation_lengths={},abilities={},
    played={0,0},scores={0,0},seed=opts.seed or 12345}
  for i=1,count do
    local s=B.new(deck1,deck2,{seed=results.seed+i-1,deck_size=opts.deck_size,player_faction=opts.player_faction,ai_faction=opts.ai_faction})
    while not s.finished do
      local ok,err=AI.step(s,s.active,opts.difficulty)
      if not ok then error('Simulation failure on match '..i..': '..tostring(err)) end
    end
    if s.winner==0 then results.draws=results.draws+1 else results.wins[s.winner]=results.wins[s.winner]+1 end
    results.rounds=results.rounds+#s.round_history
    for p=1,2 do
      results.chain[p]=results.chain[p]+s.stats.chain_activated[p]
      results.completed[p]=results.completed[p]+s.stats.chains_completed[p]
      results.played[p]=results.played[p]+s.stats.played[p]
      for _,r in ipairs(s.round_history) do results.scores[p]=results.scores[p]+r.scores[p] end
    end
    for k,v in pairs(s.stats.chain_completions_by_length) do
      results.completed_lengths[k]=(results.completed_lengths[k] or 0)+v
    end
    for k,v in pairs(s.stats.chain_sizes) do results.activation_lengths[k]=(results.activation_lengths[k] or 0)+v end
    for k,v in pairs(s.stats.abilities) do results.abilities[k]=(results.abilities[k] or 0)+v end
  end
  results.matches=count
  return results
end
function R.batch_text(result)
  local n=result.matches
  return string.format(
    'Matches: %d | Initial seed: %d\nPlayer win rate: %.2f%% | Opponent win rate: %.2f%% | Draw rate: %.2f%%\nAverage rounds: %.3f\nAverage chain completions per match: %.3f / %.3f\nAverage chain activations per match: %.3f / %.3f\nAverage cards played: %.3f / %.3f\nAverage round score across all rounds: %.3f / %.3f\nCompleted chain lengths: %s\nActivated chain lengths: %s\nAbility counts (card IDs): %s',
    n,result.seed,100*result.wins[1]/n,100*result.wins[2]/n,100*result.draws/n,
    result.rounds/n,result.completed[1]/n,result.completed[2]/n,
    result.chain[1]/n,result.chain[2]/n,
    result.played[1]/n,result.played[2]/n,
    result.scores[1]/result.rounds,result.scores[2]/result.rounds,
    format_counts(result.completed_lengths),format_counts(result.activation_lengths),
    format_counts(result.abilities))
end
return R
