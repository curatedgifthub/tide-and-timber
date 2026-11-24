-- Run from project root: lua tests/run.lua
package.path='./?.lua;./?/init.lua;'..package.path
local Cards=require('data.cards')
local Decks=require('decks')
local Chains=require('chains')
local Battle=require('battle')
local Abilities=require('abilities')
local Progression=require('progression')
local Setup=require('setup')
local Save=require('save')
local Report=require('report')
local tests={}
local function check(condition,reason) assert(condition,reason or 'assertion failed') end
local function eq(actual,expected,reason)
  if actual~=expected then error((reason or 'unexpected value')..': '..tostring(actual)..' instead of '..tostring(expected),2) end
end
local function fresh(f,g)
  f=f or 'Water';g=g or 'Fantasy'
  return Battle.new(Decks.starter(f,30),Decks.starter(g,30),{
    player_faction=f,ai_faction=g,deck_size=30,seed=8879})
end
local function summon(s,p,id,row,pos)
  local c=assert(Cards.by_id[id]);assert(c.type=='Unit')
  s.next_id=s.next_id+1
  local u={uid=s.next_id,card=c,owner=p,controller=p,hp=c.health,mod=0,
    guard=0,activated={},disabled=false}
  local list=s.players[p].rows[row or 1]
  table.insert(list,pos or #list+1,u)
  return u
end
local function hand(s,p,id)
  local c=assert(Cards.by_id[id]);s.next_id=s.next_id+1
  local u={uid=s.next_id,card=c,owner=p,controller=p,mod=0,activated={}}
  s.players[p].hand[#s.players[p].hand+1]=u
  return u
end
local function t(name,fn) tests[#tests+1]={name=name,fn=fn} end

-- Entries 1-70 are the Version 1.0 catalog. Later numbers are documented additions
-- (Water 71-74 and the Comic edition's Super 71-78, designed from supplied artwork).
local additions={Fantasy=0,Water=4,Super=8}
t('exact faction catalogs: 70 Version 1.0 entries and correct rarity/type counts',function()
  for _,f in ipairs(Decks.factions) do
    eq(#Cards[f],70+additions[f])
    local rarity={Common=0,Uncommon=0,Rare=0}
    for i,c in ipairs(Cards[f]) do
      eq(c.id,f..':'..i);check(c.name~='');check(c.text~='')
      if i>70 then goto continue end
      rarity[c.rarity]=rarity[c.rarity]+1
      ::continue::
      if c.type=='Unit' then check(type(c.strength)=='number' and type(c.health)=='number')
      else eq(c.type,'Effect') end
    end
    eq(rarity.Common,40);eq(rarity.Uncommon,20);eq(rarity.Rare,10)
  end
  eq(Cards.by_name['blue whale'].strength,4)
  eq(Cards.by_name['goldfish'].type,'Effect')
end)
t('legal decks, duplicate caps, factions, and collections',function()
  for _,f in ipairs(Decks.factions) do
    check(Decks.validate(Decks.starter(f),f,30))
  end
  local x=Decks.starter('Water')
  x[1]='Super:1';check(not Decks.validate(x,'Water',30))
  x=Decks.starter('Water');for i=1,4 do x[i]='Water:1' end
  check(not Decks.validate(x,'Water',30))
  x=Decks.starter('Water');for i=1,7 do x[i]='Water:31' end
  check(Decks.validate(x,'Water',30))
  x[8]='Water:31';check(not Decks.validate(x,'Water',30))
  x=Decks.starter('Fantasy')
  check(not Decks.validate(x,'Fantasy',30,{}))
  local partial=Decks.starter('Fantasy');table.remove(partial)
  check(Decks.validate_partial(partial,'Fantasy',30))
  check(not Decks.validate(partial,'Fantasy',30))
end)
t('ascending, descending, and reversed-direction chain rules',function()
  local s=fresh()
  summon(s,1,'Water:2',1);summon(s,1,'Water:5',1);summon(s,1,'Water:8',1)
  local chain=Chains.find(s.players[1]);eq(#chain,1)
  eq(chain[1].length,3);eq(chain[1].direction,'ascending')
  local before=s.stats.drawn[1]
  Battle.check_chains(s)
  eq(s.stats.chain_activated[1],1);eq(s.stats.drawn[1],before+1)
  Battle.check_chains(s)
  eq(s.stats.chain_activated[1],1)
  local q=fresh();summon(q,1,'Water:66',1);summon(q,1,'Water:26',1);summon(q,1,'Water:13',1)
  local descending=Chains.find(q.players[1]);eq(descending[1].direction,'descending')
  local r=fresh();summon(r,1,'Water:2',1);summon(r,1,'Water:5',1)
  summon(r,1,'Water:8',1);summon(r,1,'Water:5',1)
  for _,group in ipairs(Chains.find(r.players[1])) do check(group.length<4) end
end)
t('cross-row Bridge uses front L->R and back R->L',function()
  local s=fresh()
  local front={summon(s,1,'Water:2',1),summon(s,1,'Water:5',1),summon(s,1,'Water:8',1)}
  summon(s,1,'Water:66',2);summon(s,1,'Water:26',2)
  local bridge=summon(s,1,'Water:53',2)
  local chain=Chains.qualify(s.players[1],bridge,6,true)
  check(chain,'Cross-row bridge chain not detected')
  eq(chain.length,6);eq(chain.units[1],front[1]);eq(chain.units[6],s.players[1].rows[2][1])
  bridge.card=Cards.by_id['Water:13']
  check(not Chains.qualify(s.players[1],bridge,6,true))
end)
t('chain 4 triggered only once, even after checking twice',function()
  local s=fresh()
  summon(s,1,'Water:2');summon(s,1,'Water:5');summon(s,1,'Water:8');summon(s,1,'Water:11')
  Battle.check_chains(s)
  eq(s.stats.chain_activated[1],2)
  Battle.check_chains(s);eq(s.stats.chain_activated[1],2)
end)
t('damage and zero-health destruction enter the owner discard',function()
  local s=fresh()
  s.active=1
  hand(s,1,'Water:19')
  local victim=summon(s,2,'Fantasy:2',1)
  local enemy_score=Battle.score(s,2)
  check(Battle.play(s,1,#s.players[1].hand,1,1))
  eq(victim.hp,nil);eq(#s.players[2].rows[1],0)
  eq(Battle.score(s,2),enemy_score-victim.card.health)
  eq(s.players[2].discard[#s.players[2].discard],victim)
end)
t('direct Strength changes, area immunity, and printed Strength',function()
  local s=fresh()
  local guppy=summon(s,1,'Water:1')
  local whale=summon(s,2,'Water:61')
  local target=summon(s,2,'Fantasy:1')
  local allwet=Cards.by_id['Water:67']
  Battle.resolve(s,1,{card=allwet},Abilities.get(allwet,'play'),{})
  eq(Battle.strength(s,whale),whale.card.strength)
  eq(Battle.strength(s,target),0)
  eq(target.card.strength,1)
  local goldfish=Cards.by_id['Water:31']
  Battle.resolve(s,1,{card=goldfish},Abilities.get(goldfish,'play'),{})
  eq(Battle.strength(s,guppy),4)
  eq(guppy.card.strength,1)
end)
t('King Champion conditional strength bonus',function()
  local s=fresh('Fantasy','Super')
  local champ=summon(s,1,'Fantasy:41')
  Battle.resolve(s,1,champ,Abilities.get(champ.card,'pre_attack'),{})
  eq(Battle.strength(s,champ),5)
  local ally=summon(s,1,'Fantasy:1')
  local champ2=summon(s,1,'Fantasy:41')
  Battle.resolve(s,1,champ2,Abilities.get(champ2.card,'pre_attack'),{})
  eq(Battle.strength(s,champ2),7)
end)
t('Goldfish combination consumes hand, reshuffles discard, draws and grants play',function()
  local s=fresh('Water','Fantasy')
  s.active=1;s.players[1].hand={}
  local fish=summon(s,1,'Water:1')
  for _=1,3 do hand(s,1,'Water:31') end
  check(Battle.can_school(s,1))
  local original=Battle.strength(s,fish)
  local ok,err=Battle.school(s,1);check(ok,err)
  eq(Battle.strength(s,fish),original+9)
  check(s.school_used[1]);check(not Battle.can_school(s,1))
  check(#s.players[1].hand<=10)
  eq(s.plays_left,1)
end)
t('passing requires both players, retains hands and draws from existing decks, best of three ties',function()
  local s=fresh()
  for round=1,3 do
    local p=s.active
    check(Battle.pass(s,p))
    check(not s.finished)
    local beforeHand,beforeDeck=#s.players[1].hand,#s.players[1].deck
    check(Battle.pass(s,s.active))
    eq(#s.round_history,round)
    eq(s.round_history[round].winner,0)
    if round<3 then
      eq(s.round,round+1)
      eq(#s.players[1].hand,beforeHand+2)
      eq(#s.players[1].deck,beforeDeck-2)
    end
  end
  check(s.finished);eq(s.winner,0)
end)
t('reward only on player win and must be in opponent battle deck',function()
  local p=Progression.new(30)
  local ai=Decks.starter('Fantasy',30)
  local old=ai[1]
  ai[1]='Fantasy:41'
  local before=p.collections.Fantasy['Fantasy:41'] or 0
  local ok=Progression.award(p,'Fantasy:41',ai,2);check(not ok)
  eq(p.collections.Fantasy['Fantasy:41'] or 0,before)
  ok=Progression.award(p,'Fantasy:41',Decks.starter('Fantasy'),1);check(not ok)
  ok=Progression.award(p,'Fantasy:41',ai,1);check(ok)
  eq(p.collections.Fantasy['Fantasy:41'],before+1)
  eq(ai[1],'Fantasy:41');check(old~='Fantasy:41')
end)
t('progression collection limits and scenario reward validator',function()
  local p=Progression.new()
  local config=Setup.new('Super','Fantasy',30,'progression')
  check(Setup.validate(config,p))
  local ok=Setup.adjust(config,1,'Super:1','Super:61',p)
  check(not ok,'Unowned rare card was allowed in progression')
  config.mode='sandbox'
  check(Setup.adjust(config,1,'Super:1','Super:61',p))
  check(Setup.validate(config,p))
  config.reward='Fantasy:61'
  check(not Setup.validate(config,p))
  config.reward=config.ai_deck[1];check(Setup.validate(config,p))
end)
t('saves round-trip progress and scenario data',function()
  local p=Progression.new()
  p.collections.Super['Super:61']=2
  local ok,err=Progression.save(p,'test_simulator_temp');check(ok,err)
  local loaded=Progression.load('test_simulator_temp')
  eq(loaded.collections.Super['Super:61'],2)
  local c=Setup.new('Super','Water',30,'sandbox')
  c.reward=c.ai_deck[1]
  ok,err=Setup.save(c,'test_simulator_temp');check(ok,err)
  local r=Setup.load('test_simulator_temp',p)
  eq(r.reward,c.reward);eq(r.ai_faction,'Water')
  os.remove('saves/progress_test_simulator_temp.lua')
  os.remove('saves/scenario_test_simulator_temp.lua')
end)
t('AI batch deterministic and completes all matches',function()
  local a,b=Decks.starter('Super',30), Decks.starter('Fantasy',30)
  local opts={matches=12,seed=42,player_faction='Super',ai_faction='Fantasy',deck_size=30}
  local x=Report.batch(a,b,opts)
  local y=Report.batch(a,b,opts)
  eq(x.wins[1],y.wins[1]);eq(x.wins[2],y.wins[2]);eq(x.draws,y.draws)
  eq(x.rounds,y.rounds)
  eq(x.wins[1]+x.wins[2]+x.draws,12)
  check(x.rounds>=24 and x.rounds<=36)
end)

local pass=0
for i,test in ipairs(tests) do
  local ok,err=pcall(test.fn)
  if ok then print(string.format('[PASS] %02d %s',i,test.name));pass=pass+1
  else print(string.format('[FAIL] %02d %s: %s',i,test.name,tostring(err))) end
end
print(string.format('RESULT: %d/%d passed',pass,#tests))
if pass~=#tests then os.exit(1) end
