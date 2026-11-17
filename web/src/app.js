import {Api} from './api.js'
import {Match} from './session.js'
import {board, choices} from './board.js'
import {esc, name, btn, art, cardFace, inspect} from './ui.js'

const root = document.querySelector('#app'), dialog = document.querySelector('#dialog')
let catalog, derive, api, match, draft, health = 'Checking server', healthOK = false
let screen = 'table', editing = 0, filter = 'All', selected = null, metrics, lastView
let lastPrompt, modalView, modalMatch, error = '', roomInput = '', toastTimer, renderKey, renderedView
let expiredSignIn = false
const factions = () => catalog.factions
const faction = id => factions().find(f => f.id === id)
const cards = () => catalog.cards
const defaultSeat = id => ({faction:id, deck:[...faction(id).starters['30']]})
const seat = () => draft.seats[editing]
function valid(s) {
  const f = faction(s?.faction)
  if (!f || !Array.isArray(s.deck) || s.deck.length > f.cards.length) return false
  const counts = new Map()
  return s.deck.every(id => {
    counts.set(id, (counts.get(id) || 0) + 1)
    return Object.hasOwn(f.limits,id) && counts.get(id) <= f.limits[id]
  })
}
const ready = s => valid(s) && s.deck.length >= catalog.minimum
function loadDraft() {
  const saved = api.read('draft')
  if (saved?.seats?.length === 2 && saved.seats.every(valid) && ['solo','duel'].includes(saved.mode)) return saved
  return {mode:'solo', difficulty:'normal', seats:[defaultSeat('Fantasy'),defaultSeat('Water')]}
}
function message(text) {
  const toast = document.querySelector('#toast')
  toast.textContent = text
  toast.classList.add('visible')
  clearTimeout(toastTimer)
  toastTimer = setTimeout(()=>toast.classList.remove('visible'),4000)
}
function updateHealth() {
  const el = document.querySelector('#health')
  el.textContent = health
  el.className = 'server ' + (healthOK ? 'connected' : 'unavailable')
}
async function checkHealth() {
  health = 'Checking server'; healthOK=false; expiredSignIn=false; updateHealth(); render()
  try {
    const reply = await api.game({op:'hello'})
    healthOK = reply.rules === catalog.rules
    health = healthOK ? 'Server online' : 'Rules update needed'
    error = healthOK ? '' : 'The server uses different rules. Refresh after the matching browser build is published.'
  } catch (e) {
    expiredSignIn=['refresh_token_not_found','refresh_token_already_used','session_not_found'].includes(e.code)
    health=expiredSignIn?'Sign-in expired':'Server unavailable'
    error=e.message
  }
  updateHealth(); render()
}
function modal(title, body) {
  modalView = match?.view
  modalMatch = match?.id
  document.querySelector('#dialog-body').innerHTML =
    `<div class="modal-head"><h2 id="dialog-title">${esc(title)}</h2>${btn('×','dismiss','','close').replace('<button ','<button aria-label="Close dialog" ')}</div>${body}`
  if (!dialog.open) dialog.showModal()
  dialog.scrollTop=0
}
const emblem = id => ({Fantasy:'♧',Water:'≈',Super:'ϟ'}[id] || '◇')
function plate(i) {
  const s=draft.seats[i], f=faction(s.faction), c=cards()[f.featured]
  const arrow=(dir,icon)=>btn(icon,'faction',i+','+dir,'arrow').replace('<button ',`<button aria-label="${dir===1?'Next':'Previous'} ${i?'computer':'player'} faction" `)
  return `<article class="plate f-${f.id}"><div class="plate-art"><span class="seat-label">${i?'Computer':'Your seat'}</span>
    <span class="sigil" aria-hidden="true">${emblem(f.id)}</span><div class="art-halo"></div>${art(c)}
    <span class="specimen">No. ${String(c.number).padStart(2,'0')} · ${esc(c.rarity)}</span></div>
    <div class="plate-info"><div class="section-line"><h2>${esc(f.label)}</h2><div class="arrows">${arrow(-1,'‹')}${arrow(1,'›')}</div></div>
      <p>${esc(name(c))}</p></div>
    ${btn('Edit deck · '+s.deck.length+' cards','workshop',i,'edit-deck')}</article>`
}
function lobby() {
  const solo=draft.mode==='solo', playable=ready(draft.seats[0])&&(!solo||ready(draft.seats[1]))
  const live = healthOK && playable && !match.busy
  const resume=api.read('match')
  const mode=(id,title,sub,icon)=>`<button class="mode ${draft.mode===id?'on':''}" data-action="mode" data-value="${id}" aria-pressed="${draft.mode===id}">
    <span class="mode-icon" aria-hidden="true">${icon}</span><span><b>${title}</b><small>${sub}</small></span><span class="radio"></span></button>`
  return `<div class="heading"><div><p class="eyebrow gold">Match setup</p><h1>The match table</h1><p class="intro">Choose your factions, prepare your decks, and take a seat.</p></div></div>
    ${resume ? '<div class="resume">'+btn('Return to your match in progress →','resume','','primary',match.busy || !healthOK)+'</div>' : ''}
    <div class="lobby-grid"><section class="seats"><div class="section-line section-cap"><h3>Factions at the table</h3><span>${solo?'Player vs. computer':'Player vs. player'}</span></div>
      <div class="portraits">${plate(0)}<div class="versus" aria-hidden="true">vs</div>${solo?plate(1):`<article class="open-seat"><span class="eyebrow">Opponent</span><div class="back-cards" aria-hidden="true">♜</div><h2>Open seat</h2><p>Your opponent brings their own faction and deck.</p></article>`}</div></section>
    <section class="settings"><p class="eyebrow gold">Play online</p><h2>Game mode</h2>
    ${mode('solo','Single player','Play against the computer.','♟')}${mode('duel','Two players','Share a room with a friend.','♟♟')}
    ${solo ? '<div class="level"><span>AI difficulty</span><div class="seg">'+['easy','normal'].map(d=>btn(d==='easy'?'Easy':'Normal','difficulty',d,d===draft.difficulty?'on':'')).join('')+'</div></div>' :
      `<label for="room">Room code</label><input id="room" placeholder="6-character code" maxlength="6" autocapitalize="characters" autocomplete="off" spellcheck="false" value="${esc(roomInput)}">`}
    ${!playable ? '<p class="warn">Each deck needs at least '+catalog.minimum+' cards.</p>' : ''}
    ${error?'<p class="warn" role="status">'+esc(error)+'</p>':''}
    ${expiredSignIn?btn('Create a new sign-in','replace-auth','','quiet'):!healthOK && health!=='Checking server'?btn('Retry connection','retry','','quiet'):''}
    ${solo?btn(match.busy?'Opening match…':'Start online match →','start','','primary',!live):
      btn('Create room →','create','','primary',!live)+btn('Join room','join','','full',!live || !/^[A-Z0-9]{6}$/.test(roomInput))}
    </section></div>
    <div class="facts"><div><small>Match format</small><strong>Best of three</strong></div><div><small>Opening hand</small><strong>${catalog.minimum} cards</strong></div><div><small>Chain</small><strong>3+ consecutive ranks</strong></div><div><small>Each turn</small><strong>Play or pass</strong></div></div>`
}
function workshop() {
  const s=seat(), f=faction(s.faction), counts={}
  s.deck.forEach(id=>counts[id]=(counts[id]||0)+1)
  const visible=f.cards.filter(id=>filter==='All'||filter==='Selected'&&counts[id]||cards()[id].type===filter)
  return `<div class="heading"><div><p class="eyebrow gold">Deck workshop · ${editing?'Computer':'Your seat'}</p><h1>${esc(f.label)} collection</h1></div>${btn('← Match table','table')}</div>
    <div class="builder-tools"><div class="section-line"><h2>${s.deck.length} / ${f.cards.length} cards</h2><span>${ready(s)?'Deck ready':'Select at least '+catalog.minimum}</span></div>
      <div class="actions">${btn('20-card starter','fill','20')}${btn('30-card starter','fill','30')}${btn('All '+f.cards.length+' designs','fill','all')}</div></div>
    <div class="tabs">${['All','Unit','Effect','Selected'].map(t=>btn(t==='Unit'?'Units':t==='Effect'?'Effects':t,'filter',t,t===filter?'on':'')).join('')}</div>
    <div class="collection">${visible.map(id=>`<div class="draft-card">${cardFace(cards()[id],'catalog',id)}
      <div class="counter">${btn('−','minus',id,'',!counts[id])}<span>${counts[id]||0} / ${f.limits[id]}</span>${btn('+','plus',id,'',counts[id]>=f.limits[id]||s.deck.length>=f.cards.length)}</div></div>`).join('') || '<p>No cards selected.</p>'}</div>`
}
function waiting() {
  return `<section class="room-panel"><p class="eyebrow gold">Two players · Online</p><h1>${match.status==='waiting'?'Your room is open':'Returning to your match'}</h1>
    ${match.code?`<p>Share this room code with your opponent.</p><strong class="room-code">${esc(match.code)}</strong><div class="actions">${btn('Copy code','copy')}${btn('Share room','share')}</div>`:''}
    <p role="status">${match.recovering?'Reconnecting to the server…':match.status==='waiting'?'Waiting for the other player to join…':'Fetching your seat…'}</p>
    ${btn('Leave match','leave','','quiet',match.busy)}</section>`
}
function render() {
  if (!match) return
  if (match.notice) {error=match.notice;message(error);match.notice=''}
  if (match.status==='error') {screen='table';match=new Match(api,render)}
  if (!match.active && !match.view && screen==='match') screen='table'
  if (match.active || match.view) screen='match'
  if (dialog.open && (modalView!==match.view || modalMatch!==match.id)) dialog.close()
  if (match.view!==lastView) {
    lastView=match.view
    selected=null
    if (lastView) metrics=JSON.parse(derive(JSON.stringify(lastView)))
  }
  // Compact polls must leave focus, horizontal scroll and open inspectors alone.
  if (screen==='match') {
    const key=[match.status,match.seq,match.busy,match.recovering,selected].join('/')
    if (renderKey===key && renderedView===match.view) return
    renderKey=key
    renderedView=match.view
  } else renderKey=null
  const scroll=new Map([...root.querySelectorAll('[data-scroll]')].map(el=>[el.dataset.scroll,el.scrollLeft]))
  const focus=document.activeElement, focusAction=focus?.dataset.action, focusValue=focus?.dataset.value
  root.innerHTML=screen==='match' ? (match.view ? board(match,catalog,metrics,selected) : waiting()) : screen==='workshop' ? workshop() : lobby()
  root.inert=screen!=='match' && match.busy
  root.querySelectorAll('[data-scroll]').forEach(el=>{el.scrollLeft=scroll.get(el.dataset.scroll)||0})
  if (focusAction && !dialog.open && !focus.isConnected) {
    const next=[...root.querySelectorAll('[data-action]')].find(el=>el.dataset.action===focusAction&&el.dataset.value===focusValue)
    next?.focus({preventScroll:true})
  }
  if (match.ready && match.view?.prompt?.kind && lastPrompt!==match.view) {
    lastPrompt=match.view;showChoice()
  }
}
function showChoice() {
  const {title,body}=choices(match.view,catalog,metrics)
  modal(title,body)
}
function goTable() {
  if (match.active) return
  screen='table';match=new Match(api,render);lastView=null;lastPrompt=null;selected=null
  dialog.close();render();window.scrollTo(0,0)
}
function saveDraft() { api.save('draft',draft);render() }
function play() { return match.act({type:'play',index:handIndex()+1}) }
function handIndex() { return match.view.players[match.view.seat-1].cards.findIndex(u=>u.u===selected) }

async function dispatch(action,value) {
  if (action==='dismiss') return dialog.close()
  if (action==='table') return goTable()
  if (action==='retry') return checkHealth()
  if (action==='replace-auth') return modal('Replace expired sign-in?', '<p>The server has rejected your saved identity. A new anonymous player will have a different seat and cannot return to that match.</p>'+btn('Create new player','reset-auth','','primary'))
  if (action==='reset-auth') {
    api.save('auth',null);api.save('match',null);dialog.close();return checkHealth()
  }
  if (action==='resume') {error='';return match.resume()}
  if (action==='mode' || action==='difficulty') {draft[action]=value;error='';return saveDraft()}
  if (action==='faction') {
    const [side,delta]=value.split(',').map(Number), fs=factions(), i=fs.findIndex(f=>f.id===draft.seats[side].faction)
    draft.seats[side]=defaultSeat(fs[(i+delta+fs.length)%fs.length].id);return saveDraft()
  }
  if (action==='workshop') {screen='workshop';editing=Number(value);filter='All';render();window.scrollTo(0,0);return}
  if (action==='filter') {filter=value;return render()}
  if (action==='fill') {
    const f=faction(seat().faction);seat().deck=[...(value==='all'?f.cards:f.starters[value])];return saveDraft()
  }
  if (action==='plus' || action==='minus') {
    const s=seat(), deck=[...s.deck], i=deck.indexOf(value)
    if (action==='plus') deck.push(value)
    else if (i!==-1) deck.splice(i,1)
    if (valid({...s,deck})) s.deck=deck
    return saveDraft()
  }
  if (action==='catalog') {const c=cards()[value];return modal(name(c),inspect(c))}
  if (['start','join','create'].includes(action)) {
    if (api.read('match') && !dialog.open) {
      return modal('Start a new match?', '<p>Starting or joining a new match closes your current match for both players.</p>'+btn('Continue',action,'','primary'))
    }
    dialog.close();error=''
    const base={player:draft.seats[0],rules:catalog.rules}
    const body=action==='start'?{op:'create',mode:'solo',ai:{...draft.seats[1],difficulty:draft.difficulty}}:
      action==='create'?{op:'create',mode:'duel'}:{op:'join',code:roomInput}
    await match.open({...base,...body});window.scrollTo(0,0);return
  }
  if (action==='copy' || action==='share') {
    if (action==='share' && navigator.share) {
      const url=new URL('./',location.href);url.searchParams.set('room',match.code)
      try {await navigator.share({title:'Tide & Timber',text:'Join room '+match.code,url:url.href})}
      catch(e) {if(e.name!=='AbortError') throw e}
    } else if (navigator.clipboard) {await navigator.clipboard.writeText(match.code);message('Room code copied')}
    else modal('Copy room code','<p class="room-code">'+esc(match.code)+'</p>')
    return
  }
  if (action==='leave') return modal('Leave this match?', '<p>This ends the match for both players.</p>'+btn('Leave match','confirm-leave','','primary'))
  if (action==='confirm-leave') {dialog.close();await match.leave();if(!match.active) goTable();return}
  const v=match.view
  if (!v) return
  const myHand=v.players[v.seat-1].cards
  if (action==='hand') {
    const u=myHand.find(u=>String(u.u)===value), c=cards()[u.c], legal=metrics.hand[myHand.indexOf(u)]
    const available=match.ready && !v.prompt
    const pick=available && legal.ok
    const text=c.replaces?'Play onto '+name(cards()[c.replaces]):c.type==='Effect'?'Play effect':'Choose placement'
    return modal(name(c), inspect(c,u,metrics)+(pick?btn(text,'select',u.u,'primary'):available?'<p class="warn">'+esc(legal.reason)+'</p>':''))
  }
  if (action==='select') {
    const u=myHand.find(u=>String(u.u)===value)
    if (!match.ready || !u || v.prompt) return
    selected=u.u;dialog.close()
    if (cards()[u.c].type==='Effect'||cards()[u.c].replaces) return play()
    render();root.querySelector('.placing')?.scrollIntoView({block:'center',behavior:'smooth'});return
  }
  if (action==='unit') {
    const u=v.players.flatMap(p=>p.rows.flat().concat(p.discard)).find(u=>String(u.u)===value)
    return modal(name(cards()[u.c]),inspect(cards()[u.c],u,metrics))
  }
  if (action==='slot' && handIndex()>=0) {
    const [row,pos]=value.split(',').map(Number)
    return match.act({type:'play',index:handIndex()+1,row,pos})
  }
  if (action==='play' && handIndex()>=0) return play()
  if (['pass','end','school'].includes(action)) return match.act({type:action})
  if (action==='choice' && v.prompt?.kind) return showChoice()
  if (action==='answer' && v.prompt?.kind && modalView===v && match.ready) {
    dialog.close();return match.act({type:'choose',index:Number(value)})
  }
  if (action==='pile') {
    const pile=v.players[Number(value)-1].discard
    return modal((Number(value)===v.seat?'Your':'Opponent’s')+' discard pile',pile.length ?
      '<div class="pile-grid">'+pile.map(u=>cardFace(cards()[u.c],'unit',u.u)).join('')+'</div>':'<p>The pile is empty.</p>')
  }
  if (action==='history') return modal('Event history','<ol class="history">'+match.log.map(l=>'<li>'+esc(l)+'</li>').join('')+'</ol>')
  if (action==='scores') return modal('Round scores',`<p>You are ${esc(v.players[v.seat-1].name)}.</p>`+
    (v.history.length ? v.history.map(r=>`<div class="score-entry"><b>Round ${r.round}</b><span>${esc(v.players[0].name)} · ${r.scores[0]} / ${esc(v.players[1].name)} · ${r.scores[1]}</span>
    <strong>${r.winner ? esc(v.players[r.winner-1].name)+' won' : 'Draw'}</strong></div>`).join('') : '<p>No completed rounds yet.</p>'))
}

document.addEventListener('click',async e=>{
  const b=e.target.closest('button[data-action]')
  if (!b || b.disabled) return
  try {await dispatch(b.dataset.action,b.dataset.value)}
  catch(err) {error=err.message;message(error);render()}
})
document.addEventListener('input',e=>{
  if (e.target.id==='room') {
    roomInput=e.target.value=e.target.value.toUpperCase().replace(/[^A-Z0-9]/g,'')
    const join=root.querySelector('[data-action="join"]')
    join.disabled=!healthOK || !ready(draft.seats[0]) || roomInput.length!==6 || match.busy
  }
})
window.addEventListener('online',()=>{if(match?.active)match.schedule(0);else if(api)checkHealth()})
document.addEventListener('visibilitychange',()=>{if(!document.hidden && match?.active)match.schedule(0)})
async function boot() {
  const load=async path=>{const r=await fetch(path);if(!r.ok)throw Error('Missing '+path);return r}
  const [data,lua]=await Promise.all([load('./catalog.json').then(r=>r.json()),load('./public-rules.lua').then(r=>r.text())])
  catalog=data
  derive=window.fengari.load(lua,'@public-rules.lua')()
  api=new Api(catalog.config);draft=loadDraft()
  const code=new URLSearchParams(location.search).get('room')?.toUpperCase()
  if (/^[A-Z0-9]{6}$/.test(code||'')) {roomInput=code;draft.mode='duel'}
  match=new Match(api,render);render();await checkHealth()
}
boot().catch(e=>{root.innerHTML='<h1>Could not open the table</h1><p>'+esc(e.message)+'</p><p>Reload the page to try again.</p>'})
