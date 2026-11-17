-- Match configurations, scenario validation, and portable deck editing.
local Cards=require('data.cards')
local Decks=require('decks')
local Save=require('save')
local Setup={}

function Setup.new(player_faction,opponent_faction,size,mode)
  size=size or 30
  return {name='New match',mode=mode or 'sandbox',deck_size=size,
    player_faction=player_faction or 'Super',ai_faction=opponent_faction or 'Fantasy',
    player_deck=Decks.starter(player_faction or 'Super',size),
    ai_deck=Decks.starter(opponent_faction or 'Fantasy',size),
    reward=nil,difficulty='normal',seed=nil}
end
function Setup.validate(config,profile)
  if type(config)~='table' then return false,'Scenario is not a table' end
  if config.mode~='sandbox' and config.mode~='progression' then return false,'Unknown scenario mode' end
  if type(config.deck_size)~='number' or config.deck_size%1~=0 or config.deck_size<10 then
    return false,'Deck size must be an integer at least 10'
  end
  if config.difficulty~='easy' and config.difficulty~='normal' then return false,'Unknown AI difficulty' end
  local collection=nil
  if config.mode=='progression' then
    if not profile then return false,'Progression scenario requires a profile' end
    if profile.deck_size~=config.deck_size then return false,'Scenario size differs from progression profile size' end
    collection=profile.collections[config.player_faction] or {}
  end
  local ok,err=Decks.validate(config.player_deck,config.player_faction,config.deck_size,collection)
  if not ok then return false,'Player: '..err end
  ok,err=Decks.validate(config.ai_deck,config.ai_faction,config.deck_size)
  if not ok then return false,'Opponent: '..err end
  if config.reward then
    local card=Cards.by_id[config.reward]
    if not card then return false,'Reward card is undefined' end
    if not Decks.counts(config.ai_deck)[config.reward] then
      return false,'The specified reward must already occur in the opponent Battle Deck'
    end
  end
  if config.seed~=nil and (type(config.seed)~='number' or config.seed%1~=0) then
    return false,'Random seed must be an integer'
  end
  return true
end
function Setup.change_faction(config,side,faction)
  if not Cards[faction] then return false,'Unknown faction' end
  local fk=side==1 and 'player_faction' or 'ai_faction'
  local dk=side==1 and 'player_deck' or 'ai_deck'
  config[fk]=faction
  config[dk]=Decks.starter(faction,config.deck_size)
  if side==2 then config.reward=nil end
  return true
end
function Setup.adjust(config,side,old_id,new_id,profile)
  local dk=side==1 and 'player_deck' or 'ai_deck'
  local fk=side==1 and 'player_faction' or 'ai_faction'
  local collection=side==1 and config.mode=='progression' and profile.collections[config[fk]] or nil
  local replacement,error_message=Decks.replace(config[dk],old_id,new_id,config[fk],config.deck_size,collection)
  if not replacement then return false,error_message end
  config[dk]=replacement
  if side==2 and config.reward and not Decks.counts(config.ai_deck)[config.reward] then config.reward=nil end
  return true
end
function Setup.save(config,name,profile)
  local ok,err=Setup.validate(config,profile)
  if not ok then return false,err end
  return Save.write('scenario',name,config)
end
function Setup.load(name,profile)
  local config,err=Save.read('scenario',name)
  if not config then return nil,err end
  local ok,why=Setup.validate(config,profile)
  if not ok then return nil,why end
  return config
end
return Setup
