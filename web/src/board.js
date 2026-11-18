import {esc, name, rowName, btn, cardFace, art} from './ui.js'

export function board(match, catalog, metrics, selected) {
  const v = match.view, me = v.seat, foe = 3-me, cards = catalog.cards
  const hand = v.players[me-1].cards, index = hand.findIndex(u => u.u === selected)
  const picked = hand[index] && cards[hand[index].c], legal = metrics.hand[index]
  const can = match.ready && !v.prompt, placing = can && legal?.ok && picked?.type === 'Unit' && !picked.replaces
  const who = p => p === me ? 'You' : v.controllers[p-1] === 'AI' ? 'Computer' : 'Opponent'
  const draws = v.draws || [], fresh = new Set(draws.flatMap(d => (d.cards || []).map(c => c.u)))
  const closed = !match.active
  const turn = closed ? (match.status === 'abandoned' ? who(match.left)+' left the match' :
    v.finished ? (v.winner ? who(v.winner)+(v.winner===me?' win':' wins')+' the match' : 'Match drawn') : 'Match closed') :
    match.recovering ? 'Connection lost · reconnecting…' : match.busy ? 'Resolving the move…' :
    v.prompt ? (v.prompt.actor===me ? 'Your ability choice' : who(v.prompt.actor)+' is choosing') :
    match.mine ? 'Your turn' : who(foe)+(v.controllers[foe-1]==='AI'?' is playing…':'’s turn')
  const title = `<div class="heading"><div><p class="eyebrow">${v.mode==='solo'?'Single player':'Two players'} · ${match.code?'Room '+esc(match.code):'Online match'}</p><h1>Battlefield</h1></div>
    <div class="actions">${btn('Rows & Bridge','row-guide')}${btn('Round '+v.round+' / 3','scores')}${closed ? btn('Match table','table') : btn('Leave match','leave','','quiet',match.busy)}</div></div>`
  function row(p, r) {
    const units = v.players[p-1].rows[r-1], markers = placing && p === legal.side
    const slot = pos => {
      const preview=metrics.slots?.[r-1]?.[pos-1] || {}
      const label=preview.cross?'Bridge chain '+preview.chain:preview.endpoint?'Bridge end':
        preview.chain?'Chain '+preview.chain:''
      const hint=[label,preview.bonus].filter(Boolean).join(' · ')
      return btn(hint || (units.length?'+':'+ Deploy here'),'slot',r+','+pos,'slot'+(hint?' annotated':''))
        .replace('<button ', `<button aria-label="Deploy to ${who(p)} ${rowName(r)} position ${pos}${hint?' · '+hint:''}" `)
    }
    const content = units.map((u,i) => {
      const stat = metrics.units[u.u]
      return (markers ? slot(i+1) : '') + cardFace(cards[u.c], 'unit', u.u,
        stat.strength+' STR', false, stat.cross ? 'Bridge chain' : stat.chain ? 'Chain '+stat.chain : cards[u.c].bridge && !u.dis ? 'Bridge' : '', u.hp)
    }).join('') + (markers ? slot(units.length+1) : '')
    const total = units.reduce((n,u)=>n+metrics.units[u.u].strength,0)
    return `<div class="lane ${markers?'placing':''}"><div class="row-name"><strong>${rowName(r)}</strong><small>${total} STR</small></div>
      <div class="row-cards scroll" data-scroll="lane-${p}-${r}">${content || '<span class="empty">Empty row</span>'}</div></div>`
  }
  function markersHint(p) {
    if (!placing || p!==legal.side) return ''
    const text=picked.bridge?'Bridge joins the two right ends. Continue a run of 3 or more printed ranks, stepping up or down by one.':
      metrics.slots?.[1]?.[0]?.bonus?'Back row bonus · '+metrics.slots[1][0].bonus:
      'Both rows score. Units in the same row can be hit together.'
    return '<p class="placement-note">'+esc(text)+'</p>'
  }
  function side(p) {
    const pl=v.players[p-1], faction=catalog.factions.find(f=>f.id===pl.faction)
    const score=v.finished && v.history.length ? v.history.at(-1).scores[p-1] : metrics.scores[p-1]
    return `<section class="side f-${pl.faction}"><div class="side-head"><div><b>${who(p)}</b> · ${esc(faction.label)} <small>(${esc(pl.name)})</small></div>
      <b>${score} STR</b></div><div class="piles"><span>${pl.wins} round wins${pl.passed?' · Passed':''}</span><span>Deck ${pl.deck}</span><span>Hand ${pl.hand}</span></div>
      ${markersHint(p)}
      ${(p===me?[1,2]:[2,1]).map(r=>row(p,r)).join('')}
      <button class="discard-pile" data-action="pile" data-value="${p}" aria-label="${who(p)} discard pile, ${pl.discard.length} cards">
        <span class="discard-top">${pl.discard.length ? art(cards[pl.discard.at(-1).c]) : '<span aria-hidden="true">◇</span>'}</span>
        <span><strong>Discard pile · ${pl.discard.length}</strong><small>${pl.discard.length ? esc(name(cards[pl.discard.at(-1).c]))+' on top · Tap to view all' : 'Empty · Used and defeated cards go here'}</small></span>
        <span aria-hidden="true">→</span>
      </button></section>`
  }
  const drawText = draws.map(d => d.cards ? 'You drew '+d.cards.map(c=>name(cards[c.c])).join(', ') : who(d.seat)+' drew '+d.n+' card'+(d.n===1?'':'s')).join(' · ')
  const lastCard = v.last && cards[v.last.c]
  const recent = match.log.slice(-3).reverse().map(line=>'<li>'+esc(line)+'</li>').join('')
  return title+`<div class="battle-grid"><div class="battlefield">${side(foe)}<div class="battle-line"><span>Battle line</span></div>${side(me)}</div>
    <aside class="command"><p class="eyebrow">Round ${v.round}</p><h2 aria-live="polite">${esc(turn)}</h2>
    ${v.prompt?.kind && match.ready ? btn('Resolve ability','choice','','primary') : ''}
    ${placing ? '<p class="hint">Place '+esc(name(picked))+' on a gold marker in '+(legal.side===me?'your':'the opposing')+' rows.</p>' : ''}
    ${can && legal?.ok && (picked.type==='Effect'||picked.replaces) ? btn(picked.replaces?'Play onto '+name(cards[picked.replaces]):'Play effect','play','','primary') : ''}
    ${can && metrics.school ? btn('School of Goldfish','school') : ''}
    ${can && v.extra ? btn('End extra plays','end') : ''}
    ${can ? btn('Pass this round','pass') : ''}
    <hr><div class="section-line"><h3>Battle record</h3>${btn('View all','history','','text-button')}</div>
    ${lastCard ? '<p class="last-played">Last played · <b>'+esc(name(lastCard))+'</b></p>' : ''}
    <ul class="events" aria-live="polite">${recent}</ul>${drawText ? '<p class="hint">'+esc(drawText)+'</p>' : ''}</aside>
    <section class="hand"><div class="section-line"><h2>Your hand</h2><span>${hand.length} cards</span></div>
    <div class="hand-scroll scroll" data-scroll="hand">${hand.map(u=>cardFace(cards[u.c],'hand',u.u,'',u.u===selected,fresh.has(u.u)?'New draw':'')).join('') || '<p>Hand empty</p>'}</div></section></div>`
}

const labels = {damage:'Deal damage',debuff:'Reduce strength',buff:'Increase strength',heal:'Restore health',
  guard:'Protect a unit',destroy:'Destroy a unit',move:'Reposition a unit',row:'Choose a row',card:'Choose a card',
  chain:'Choose a chain',resurrect:'Redeploy a unit',peek:'Order the top cards',search:'Search the draw deck',
  bottom_order:'Order remaining cards',chain_activation:'Choose the next trigger',disable:'Suppress an ability',
  copy_deploy:'Copy a deploy ability',beacon:'Guiding Beam',summon:'Summon a unit',replace:'Choose a unit to replace',
  give:'Choose the unit to give',take:'Choose the unit to take',reveal:'Reveal opposing cards',reverse:'Reverse a row',maelstrom:'Choose a row'}

export function choices(view, catalog, metrics) {
  const q=view.prompt, ctx=q.context, cards=catalog.cards
  const known=new Map(view.players.flatMap(p=>p.rows.flat()).map(u=>[u.u,u]))
  const label=c=>name(cards[c.c])
  const chain=ids=>ids.map(id=>label(known.get(id))+' #'+id).join(' → ')
  const title=labels[ctx.op] || 'Resolve ability'
  const subtitle=[ctx.unit && label(ctx.unit), ctx.cards && (ctx.bottom?'From the bottom · ':'Examined · ')+ctx.cards.map(label).join(', '),
    q.kind==='bottom_order' && 'Choose the next card in bottom-of-deck draw order.',ctx.row && rowName(ctx.row)+' row'].filter(Boolean).join(' · ')
  const options=q.options.map((o,i)=>{
    let text, detail='', image=''
    if (o.c) {
      text=label(o)+' #'+o.u
      const pos=metrics.units[o.u]
      detail=pos ? (pos.seat===view.seat?'Your':'Opposing')+' '+rowName(pos.row)+' · Position '+pos.pos+' · '+pos.strength+' STR · '+known.get(o.u).hp+' HP' : cards[o.c].text
      if (o.chain) detail+=' · '+chain(o.chain.units)
      image=art(cards[o.c])
    } else if (o.units) { text=chain(o.units); detail=o.cross?'Bridge chain':o.direction+' chain' }
    else if (q.kind==='row') { text=rowName(o)+' row'; detail=ctx.enemy?'Opposing battlefield':'' }
    else if (q.kind==='side') text=o===view.seat?'Your battlefield':'Opposing battlefield'
    else if (q.kind==='order') { text=(o===1?ctx.cards:[...ctx.cards].reverse()).map(label).join(' → ');detail='Next draw first' }
    else if (q.kind==='beacon') text=(o===1?'Keep on top · ':'Send to bottom · ')+label(ctx.cards[0])
    else if (q.kind==='amount') text=o+(ctx.op==='heal'?' HP':' cards')
    else text='Position '+o
    return `<button class="option" data-action="answer" data-value="${i+1}">${image}<span><strong>${esc(text)}</strong><small>${esc(detail)}</small></span></button>`
  }).join('')
  return {title, body:'<p>'+esc(subtitle)+'</p>'+options+(ctx.optional?btn('Done choosing','answer',0):'')}
}
