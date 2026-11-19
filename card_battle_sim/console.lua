-- Console menus. The battle engine never reads from stdin or prints to stdout.
local Cards=require('data.cards')
local Decks=require('decks')
local Setup=require('setup')
local Progression=require('progression')
local Save=require('save')
local Battle=require('battle')
local AI=require('ai')
local Report=require('report')
local Console={}

local function ask(prompt)
  io.write(prompt..' ');io.flush()
  local v=io.read('*l')
  if v==nil then error('Input closed (EOF)') end
  return v:match('^%s*(.-)%s*$')
end
local function integer(prompt,lo,hi,allow_blank)
  while true do
    local s=ask(prompt)
    if allow_blank and s=='' then return nil end
    local n=tonumber(s)
    if n and n%1==0 and (not lo or n>=lo) and (not hi or n<=hi) then return n end
    print('Enter an integer between '..tostring(lo or '-infinity')..' and '..tostring(hi or 'infinity')..'.')
  end
end
local function choice(prompt,items)
  print(prompt)
  for i,v in ipairs(items) do print(string.format('  %2d) %s',i,v)) end
  return integer('Selection:',1,#items)
end
local function faction(prompt)
  local n=choice(prompt,Decks.factions)
  return Decks.factions[n]
end
local function read_name(prompt)
  while true do
    local name=ask(prompt)
    if name:match('^[%w_%-]+$') and #name<=80 then return name end
    print('Use letters, digits, hyphens or underscores only (maximum 80).')
  end
end
local function stats(card)
  return card.strength and (card.designation.."   "..card.strength.." ATK   "..card.health.."/"..card.health.." HP") or "Effect"
end
local function catalogue(f,filter)
  print("\n"..f.." catalog")
  for _,c in ipairs(Cards[f]) do
    if not filter or c.type==filter or filter=='Bridge' and c.bridge then
      print(string.format("  %-27s %s",c.display_name or c.name,stats(c)))
    end
  end
end
local function card_info(card)
  if not card then print('Unknown card');return end
  print(card.display_name or card.name)
  print(stats(card))
  print(card.text)
end
local function card_id(prompt,filter)
  while true do
    local raw=ask(prompt..' (card name, or blank to cancel):')
    if raw=='' then return nil end
    local c=Cards.by_id[raw] or Cards.by_name[raw:lower()]
    if not c then
      for _,candidate in pairs(Cards.by_id) do
        if candidate.display_name and candidate.display_name:lower()==raw:lower() then c=candidate;break end
      end
    end
    if c and (not filter or filter(c)) then return c.id end
    print('Card not found or not eligible. Use the catalog to inspect valid names.')
  end
end
local function show_deck(deck)
  local counts=Decks.counts(deck)
  local keys={};for id in pairs(counts) do keys[#keys+1]=id end
  table.sort(keys,function(a,b)
    local ca,cb=Cards.by_id[a],Cards.by_id[b]
    if ca.number~=cb.number then return ca.number<cb.number end
    return a<b
  end)
  print('Battle Deck ('..#deck..' cards):')
  for _,id in ipairs(keys) do
    local c=Cards.by_id[id]
    print(string.format('  x%-2d %-26s %s',counts[id],c.display_name or c.name,stats(c)))
  end
end
local function collection_menu(profile,f)
  print('Collection: '..f)
  local entries={};for id,num in pairs(profile.collections[f] or {}) do
    if num>0 then entries[#entries+1]={id=id,n=num} end
  end
  table.sort(entries,function(a,b)return Cards.by_id[a.id].number<Cards.by_id[b.id].number end)
  if #entries==0 then print('No owned cards.') end
  for _,entry in ipairs(entries) do
    print(string.format('  x%-2d %s',entry.n,Cards.by_id[entry.id].display_name or Cards.by_id[entry.id].name))
  end
end
local function deck_menu(config,profile,side)
  local dk=side==1 and 'player_deck' or 'ai_deck'
  local fk=side==1 and 'player_faction' or 'ai_faction'
  while true do
    local f=config[fk]
    print('\nEditing '..(side==1 and 'Player' or 'Opponent')..' '..f..' Battle Deck')
    local action=choice('Deck editor:',{
      'Show deck','Show all faction cards','Show units',
      'Show effects','Show Bridges','Inspect a card',
      'Replace a card','Remove a card (draft)','Add card to free slot',
      'Save deck','Load deck','Back'})
    if action==12 then return end
    if action==1 then show_deck(config[dk])
    elseif action>=2 and action<=5 then
      catalogue(f,({[3]='Unit',[4]='Effect',[5]='Bridge'})[action])
    elseif action==6 then
      card_info(Cards.by_id[card_id('Card to inspect',function(c)return c.faction==f end) or ''])
    elseif action==7 then
      show_deck(config[dk])
      local existing=Decks.counts(config[dk])
      local old=card_id('Remove/replace which card?',function(c)return existing[c.id]~=nil end)
      if old then
        local new=card_id('Add which card?',function(c)return c.faction==f end)
        if new then
          local ok,err=Setup.adjust(config,side,old,new,profile)
          if ok then print('Replacement saved in current match configuration.') else print('Not allowed: '..err) end
        end
      end
    elseif action==8 then
      local existing=Decks.counts(config[dk])
      local id=card_id('Remove which card?',function(c)return existing[c.id]~=nil end)
      if id and Decks.remove(config[dk],id) then
        if side==2 and config.reward==id and not Decks.counts(config.ai_deck)[id] then config.reward=nil end
        print('Card removed. Deck now has '..#config[dk]..'/'..config.deck_size..' cards.')
      end
    elseif action==9 then
      if #config[dk]>=config.deck_size then print('Deck is full: remove or replace a card first.')
      else
        local id=card_id('Add which card?',function(c)return c.faction==f end)
        if id then
          local new={table.unpack(config[dk])};new[#new+1]=id
          local owned=side==1 and config.mode=='progression' and profile.collections[f] or nil
          local ok,err=Decks.validate_partial(new,f,config.deck_size,owned)
          if ok then config[dk]=new;print('Card added. Deck now has '..#new..'/'..config.deck_size..' cards.')
          else print('Not allowed: '..err) end
        end
      end
    elseif action==10 then
      local name=read_name('Save deck as:')
      local ok,path=Save.write('deck',name,{faction=f,cards=config[dk],size=config.deck_size})
      print(ok and ('Saved '..path) or ('Save failed: '..path))
    elseif action==11 then
      local name=read_name('Load deck named:')
      local value,err=Save.read('deck',name)
      if value and type(value)=='table' and value.faction==f and value.size==config.deck_size then
        local owned=side==1 and config.mode=='progression' and profile.collections[f] or nil
        local ok,reason=Decks.validate_partial(value.cards,f,config.deck_size,owned)
        if ok then
          config[dk]=value.cards
          if side==2 and config.reward and not Decks.counts(config.ai_deck)[config.reward] then config.reward=nil end
          print('Deck loaded.')
        else print('Deck rejected: '..reason) end
      else print('Load failed: '..(err or 'Saved deck faction/size mismatch')) end
    end
  end
end
local function setup_menu(config,profile)
  while true do
    print(string.format('\nMATCH SETUP | %s | size %d | %s vs %s | reward %s',
      config.mode,config.deck_size,config.player_faction,config.ai_faction,
      config.reward and (Cards.by_id[config.reward] and Cards.by_id[config.reward].name or config.reward) or 'none'))
    local action=choice('Configure:',{
      'Choose player faction (resets player deck)','Edit player deck',
      'Choose opponent faction (resets opponent deck)','Edit opponent deck',
      'Set victory reward from opponent deck','Set AI difficulty','Set random seed',
      'Save current scenario','Load scenario','View my faction collection',
      'Start match','Back to main menu'})
    if action==12 then return false end
    if action==1 or action==3 then
      local side=action==1 and 1 or 2
      local f=faction('Choose faction:')
      local ok,err=Setup.change_faction(config,side,f)
      if not ok then print(err) end
    elseif action==2 then deck_menu(config,profile,1)
    elseif action==4 then deck_menu(config,profile,2)
    elseif action==5 then
      show_deck(config.ai_deck)
      local reward=card_id('Choose reward already in opponent deck',
        function(c)return Decks.counts(config.ai_deck)[c.id]~=nil end)
      config.reward=reward
    elseif action==6 then
      config.difficulty=choice('AI difficulty:',{'easy','normal'})==1 and 'easy' or 'normal'
    elseif action==7 then
      config.seed=integer('Seed (blank for current time):',nil,nil,true)
    elseif action==8 then
      local name=read_name('Scenario name:')
      local ok,path=Setup.save(config,name,profile)
      print(ok and ('Saved '..path) or ('Save failed: '..path))
    elseif action==9 then
      local name=read_name('Scenario name to load:')
      local scenario,err=Setup.load(name,profile)
      if scenario then for k in pairs(config) do config[k]=nil end
        for k,v in pairs(scenario) do config[k]=v end
        print('Scenario loaded.')
      else print('Load failed: '..err) end
    elseif action==10 then collection_menu(profile,config.player_faction)
    elseif action==11 then
      local ok,err=Setup.validate(config,profile)
      if ok then return true end
      print('Cannot start: '..err)
    end
  end
end
local function view_board(s)
  print(string.rep('=',78))
  print(string.format('ROUND %d/3 | wins: Player %d, Opponent %d | remaining HP: %d-%d | turn: %s',
    s.round,s.players[1].wins,s.players[2].wins,Battle.score(s,1),Battle.score(s,2),s.players[s.active].name))
  local function show_row(p,r)
    local row=s.players[p].rows[r]
    local label=s.players[p].name..' '..(r==1 and 'FRONT' or 'BACK')
    print(label..':')
    if #row==0 then print('  (empty)') end
    for pos,u in ipairs(row) do
      print(string.format('  [%d] %-23s ATK %-2d HP %d/%d',
        pos,(u.card.display_name or u.card.name)..' '..u.card.designation,Battle.strength(s,u),u.hp,u.card.health))
    end
  end
  show_row(2,2);show_row(2,1)
  print(string.rep('-',78))
  show_row(1,1);show_row(1,2)
  for p=1,2 do
    local pl=s.players[p]
    print(string.format('%s: hand %d, draw %d, discard %d%s',pl.name,#pl.hand,#pl.deck,#pl.discard,
      pl.passed and ' (PASSED)' or ''))
  end
  print('YOUR HAND:')
  for i,c in ipairs(s.players[1].hand) do
    local st=stats(c.card)
    local legal=Battle.playable(s,1,i)
    print(string.format('  [%2d] %-26s %-14s %s',i,c.card.display_name or c.card.name,st,legal and '' or ' [not playable]'))
  end
  print(string.rep('=',78))
end
local function human_chooser(s,actor,kind,options,context)
  if actor~=1 then return nil end
  print('\nChoose '..kind..' target for '..(context and context.op or 'ability')..':')
  for i,item in ipairs(options) do
    local label
    if kind=='unit' then
      local p,r,pos=Battle.position(s,item)
      label=string.format('%s | %s %s[%d] | ATK %d HP %d/%d',
        item.card.display_name or item.card.name,p==1 and 'Player' or 'Opponent',r==1 and 'Front' or 'Back',pos,
        Battle.strength(s,item),item.hp,item.card.health)
    elseif kind=='card' or kind=='bottom_order' then label=item.card.display_name or item.card.name
    elseif kind=='chain' then
      local names={};for _,u in ipairs(item.units) do names[#names+1]=u.card.name end
      label=table.concat(names,' > ')
    elseif kind=='chain_activation' then
      label=item.unit.card.name..' (Chain '..item.unit.card.chain..', length '..item.chain.length..')'
    elseif kind=='row' then label=item==1 and 'Front row' or 'Back row'
    elseif kind=='side' then label=item==1 and 'Player' or 'Opponent'
    elseif kind=='position' then label='Position '..item
    elseif kind=='order' then label=item==1 and 'Leave current order' or 'Reverse top two'
    else label=tostring(item) end
    print('  ['..i..'] '..label)
  end
  return integer('Target:',1,#options)
end
local function match(config,profile)
  local s=Battle.new(config.player_deck,config.ai_deck,{
    player_faction=config.player_faction,ai_faction=config.ai_faction,
    deck_size=config.deck_size,seed=config.seed or os.time(),chooser=human_chooser,
    on_event=function(message) print('  -> '..message) end})
  while not s.finished do
    if s.active==2 then
      local ok,err=AI.step(s,2,config.difficulty)
      if not ok then error('AI: '..err) end
    else
      if #Battle.legal_indices(s,1)==0 and not Battle.can_school(s,1) then
        print('Player has no playable cards and automatically passes.')
        local ok,err=Battle.pass(s,1)
        if not ok then error(err) end
      else
      view_board(s)
      local actions={'Play a hand card','Inspect a card','Inspect battlefield','Inspect discard piles','Pass'}
      if Battle.can_school(s,1) then actions[#actions+1]='School of Goldfish' end
      local a=choice('Action:',actions)
      if a==1 then
        if #Battle.legal_indices(s,1)==0 then print('No playable cards. Pass instead.')
        else
          local index=integer('Hand card number (0 to cancel):',0,#s.players[1].hand)
          if index>0 then
            local card=s.players[1].hand[index]
            local row,pos
            if card.card.type=='Unit' and not card.card.replaces then
              row=Battle.placement_row(card.card)
              local last=#s.players[Battle.deploy_side(1,card.card)].rows[row]+1
              pos=integer((row==1 and 'Front' or 'Back')..' position (1 to '..last..'):',1,last)
            end
            local ok,err=Battle.play(s,1,index,row,pos)
            if not ok then print('Illegal action: '..err) end
          end
        end
      elseif a==2 then
        local id=card_id('Card to inspect')
        if id then card_info(Cards.by_id[id]) end
      elseif a==3 then view_board(s)
      elseif a==4 then
        for p=1,2 do
          print(s.players[p].name..' discard pile:')
          for i,c in ipairs(s.players[p].discard) do print('  '..i..': '..(c.card.display_name or c.card.name)) end
        end
      elseif a==5 then
        local ok,err=Battle.pass(s,1);if not ok then print(err) end
      elseif a==6 and Battle.can_school(s,1) then
        local ok,err=Battle.school(s,1);if not ok then print(err) end
      end
      end
    end
  end
  local awarded=nil
  local reward_note=nil
  if config.reward and config.mode=='progression' then
    local ok,reward=Progression.award(profile,config.reward,config.ai_deck,s.winner)
    if ok then awarded=Cards.by_id[reward].display_name or Cards.by_id[reward].name
    else reward_note='Reward not granted: '..tostring(reward) end
  elseif config.reward then
    reward_note='Sandbox match: reward is for testing only; no collection changed.'
  end
  print('\n'..Report.summary(s,awarded))
  if awarded then print('NEW COLLECTIBLE REWARD: '..awarded) end
  if reward_note then print(reward_note) end
  if config.mode=='progression' then
    local ok,err=Progression.save(profile,'default')
    if not ok then print('Warning: progress not saved: '..err) end
  end
  return s
end
function Console.main()
  local profile=Progression.load('default')
  if not profile then profile=Progression.new(30) end
  local config=Setup.new('Super','Fantasy',profile.deck_size,'sandbox')
  while true do
    print('\nTWO-ROW CARD BATTLE SIMULATOR')
    local action=choice('Main menu:',{
      'Human vs AI: sandbox match','Human vs AI: progression match',
      'AI vs AI batch experiment','View faction collections',
      'Save progress','Load progress','Reset to starter collections',
      'Change standard Battle Deck size','Exit'})
    if action==9 then return end
    if action==1 or action==2 then
      local mode=action==1 and 'sandbox' or 'progression'
      if config.mode~=mode then
        config=Setup.new(config.player_faction,config.ai_faction,profile.deck_size,mode)
      end
      config.mode=mode
      if setup_menu(config,profile) then
        local ok,err=pcall(match,config,profile)
        if not ok then print('MATCH ERROR: '..tostring(err)) end
      end
    elseif action==3 then
      config.mode='sandbox'
      print('Batch experiments ignore progression collections and rewards.')
      if setup_menu(config,profile) then
        local matches=integer('Number of AI-vs-AI matches (1 to 100000):',1,100000)
        local ok,res=pcall(Report.batch,config.player_deck,config.ai_deck,
          {matches=matches,seed=config.seed or 12345,deck_size=config.deck_size,
           player_faction=config.player_faction,ai_faction=config.ai_faction,
           difficulty=config.difficulty})
        if ok then print(Report.batch_text(res)) else print('BATCH ERROR: '..tostring(res)) end
      end
    elseif action==4 then collection_menu(profile,faction('Faction:'))
    elseif action==5 then
      local name=read_name('Save progress as:')
      local ok,v=Progression.save(profile,name);print(ok and ('Saved '..v) or v)
    elseif action==6 then
      local name=read_name('Load progress named:')
      local loaded,err=Progression.load(name)
      if loaded then profile=loaded;config=Setup.new('Super','Fantasy',profile.deck_size,'sandbox');print('Progress loaded.')
      else print('Load failed: '..err) end
    elseif action==7 then
      if ask('Type RESET to confirm:')=='RESET' then
        profile=Progression.new(profile.deck_size)
        local ok,msg=Progression.save(profile,'default')
        print(ok and 'Starter inventory restored.' or ('Save error: '..msg))
        config=Setup.new('Super','Fantasy',profile.deck_size,'sandbox')
      end
    elseif action==8 then
      local n=integer('New standard deck size (10 to 40):',10,40)
      local new_profile=Progression.new(n)
      profile=new_profile;config=Setup.new('Super','Fantasy',n,'sandbox')
      print('Started a new in-memory starter profile with deck size '..n..'. Existing saved profiles are unchanged.')
    end
  end
end
return Console
