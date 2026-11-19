// Exercise the browser client directly against the Lua server used by the Mac client.
import assert from 'node:assert/strict'
import fengari from 'fengari-web'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, readFileSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {Api} from '../src/api.js'
import {Match} from '../src/session.js'
import {upgradeStarters} from '../src/draft.js'
import {board,choices} from '../src/board.js'
import {cardFace,inspect} from '../src/ui.js'

const catalog = JSON.parse(readFileSync(new URL('../dist/catalog.json', import.meta.url)))
const derive = fengari.load(readFileSync(new URL('../dist/public-rules.lua', import.meta.url), 'utf8'))()
const root = fileURLToPath(new URL('../../', import.meta.url))
const dir = mkdtempSync(join(tmpdir(), 'tt-protocol-'))
globalThis.location = new URL('https://example.github.io/tide-and-timber/')
let drop, posts=[], signups=0, refreshes=0
globalThis.fetch = async (url, init) => {
  const path = new URL(url).pathname
  const body = JSON.parse(init.body)
  if (body.op === 'act') {
    posts.push(body)
    if (drop === 'request') { drop=null; throw Error('Dropped request') }
  }
  if (path.endsWith('signup')) signups++
  if (path.endsWith('token')) refreshes++
  const request = {method:'POST', path, body:init.body, clock:1000, key:'test-key', rules:catalog.rules, token_life:3600,
    headers:Object.fromEntries(Object.entries(init.headers).map(([k,v])=>[k.toLowerCase(),v]))}
  const r = spawnSync('lua',['tests/devhost_cli.lua',join(dir,'state.json')], {cwd:root,input:JSON.stringify(request),encoding:'utf8'})
  assert.equal(r.status,0,r.stderr)
  const {status,body:reply} = JSON.parse(r.stdout)
  if (body.op === 'act' && drop === 'reply') { drop=null; throw Error('Dropped reply') }
  return new Response(reply,{status})
}
function client() {
  const values = new Map()
  const api = new Api({url:'https://example.invalid',key:'test-key'}, {
    getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)})
  return session(api)
}
function session(api) {
  const match=new Match(api,()=>{})
  match.schedule=()=>{} // Tests drive the production pump on demand.
  return match
}
const deck = f => ({faction:f.id, deck:f.starter})
try {
  for (const f of catalog.factions) {
    assert.equal(f.starter.length,30)
    assert.equal(new Set(f.starter).size,30)
    assert.equal(f.smallStarter.length,20)
  }
  for (const card of Object.values(catalog.cards)) {
    const face=cardFace(card,'catalog',card.id)
    assert.match(face,/<span class="card-image"><img[^>]+><\/span><span class="card-caption">/)
    const visible=(face+inspect(card)).replace(/<[^>]+>/g,'')
    assert.doesNotMatch(visible,/\b(?:rank|uncommon|rare|common)\b|(?:Super|Fantasy|Water):\d+/i)
    if (card.type==='Unit') {
      assert.match(card.designation,/^[FB](?:F|B|FB)$/)
      assert.ok(face.includes(card.designation) && visible.includes(card.health+'/'+card.health+' HP'))
    } else assert.equal(card.designation,undefined)
  }
  const oldComic=[66,61,15,27,32,57,71,72,73,74,75,78,2,11,20,21,62,8,12,14,24,30,47,49,51,61,57,15,27,30].map(n=>'Super:'+n)
  const custom=[...oldComic].reverse()
  const saved={starterVersion:4,seats:[{faction:'Super',deck:[...oldComic]},{faction:'Super',deck:[...custom]}]}
  upgradeStarters(saved,id=>catalog.factions.find(f=>f.id===id))
  assert.deepEqual(saved.seats[0].deck,catalog.factions.find(f=>f.id==='Super').starter)
  assert.deepEqual(saved.seats[1].deck,custom)
  assert.equal(saved.starterVersion,5)
  let host=client(), guest=client()
  await host.open({op:'create',mode:'duel',player:{faction:catalog.factions[0].id, deck:catalog.factions[0].starter},rules:catalog.rules})
  assert.equal(host.code.length,6)
  host=session(host.api)
  await host.resume()
  assert.equal(host.status,'waiting')
  await guest.open({op:'join',code:host.code,player:{faction:catalog.factions[1].id, deck:catalog.factions[1].smallStarter},rules:catalog.rules})
  await host.tick()
  assert.equal(host.view.seat,1)
  assert.equal(guest.view.seat,2)
  assert.equal(host.view.players[1].cards,undefined)
  for (const seat of [host,guest]) {
    assert.equal(seat.view.players[seat.view.seat-1].cards.length,5)
    assert.equal(seat.view.players[seat.view.seat-1].deck,seat===host?25:15)
  }
  // Render both real seat-view shapes in Node, with a wound on each battlefield.
  for (const seat of [host,guest]) {
    const view=structuredClone(seat.view)
    for (const [i,p] of view.players.entries()) {
      const c=catalog.factions[i].starter.map(id=>catalog.cards[id]).find(c=>c.health>3)
      const u={u:100+i,c:c.id,o:i+1,hp:c.health-i-1}
      p.rows[i]=[u]
    }
    const metrics=JSON.parse(derive(JSON.stringify(view)))
    assert.deepEqual(metrics.scores,view.players.map(p=>p.rows.flat()[0].hp))
    const html=board({view,ready:true,active:true,log:[]},catalog,metrics,null)
    const opts=view.players.map(p=>p.rows.flat()[0])
    view.prompt={kind:'unit',context:{op:'heal'},options:opts}
    const prompt=choices(view,catalog,metrics).body
    for (const u of opts) {
      const hp=u.hp+'/'+catalog.cards[u.c].health+' HP'
      assert.ok(html.includes(u.hp+' remaining HP'))
      assert.ok(html.includes(hp) && prompt.includes(hp),'battlefield and choice show wounded HP')
    }
    assert.doesNotMatch(html,/Attack with a unit|ready unit/i)
  }
  const actor=host.ready?host:guest, other=actor===host?guest:host
  // A selected unit gets insertion markers only in its printed row and on its deployment side.
  const preview=structuredClone(actor.view)
  for (const card of Object.values(catalog.cards).filter(c=>c.type==='Unit' && !c.replaces && !c.requires_units)) {
    const u={u:301,c:card.id,o:preview.seat}
    preview.players[preview.seat-1].cards=[u]
    preview.previewUid=u.u
    const info=JSON.parse(derive(JSON.stringify(preview)))
    const row=card.designation[0]==='F'?1:2
    assert.equal(info.hand[0].row,row)
    const markup=board({view:preview,ready:true,active:true,log:[]},catalog,info,u.u)
    const markers=Array.from(markup.matchAll(/aria-label="Deploy to ([^"]+)"/g),m=>m[1])
    assert.equal(markers.length,1)
    assert.ok(markers[0].startsWith((card.agent?'Opponent':'You')+' '+(row===1?'Front':'Back')+' position 1'))
  }
  const token=actor.api.read('auth')
  actor.api.save('auth',{...token,expires_at:0})
  const seq=actor.seq
  drop='request'
  await actor.act({type:'pass'})
  assert.equal(actor.recovering,true)
  const reopened=session(actor.api)
  await reopened.resume()
  assert.equal(reopened.seq,seq+1)
  assert.deepEqual(posts[0], posts[1], 'retry must carry the original sequence and move id')
  await other.tick()
  assert.equal(other.ready,true)
  const before=posts.length
  drop='reply'
  await other.act({type:'pass'})
  assert.equal(other.recovering,true)
  await other.tick()
  assert.equal(posts.length,before+1,'accepted input must not be resent at a later sequence')
  await reopened.tick()
  assert.deepEqual(other.log,reopened.log)
  assert.equal(signups,2)
  assert.equal(refreshes,1)
  await other.leave()
  await reopened.tick()
  assert.equal(reopened.status,'abandoned')
  assert.equal(reopened.api.read('match'),null)
  console.log('PASS duel, private seats, reload, token refresh, lost request and reply, leave')
  const solo=client()
  await solo.open({op:'create', mode:'solo', rules:catalog.rules, player:deck(catalog.factions[2]),
    ai:{...deck(catalog.factions[1]),difficulty:'easy'}})
  for (let i=0; i<120 && solo.active; i++) {
    if (solo.ready) await solo.act(solo.view.prompt ? {type:'choose',index:1}:{type:'pass'})
    else await solo.tick()
  }
  assert.equal(solo.status,'finished')
  assert.equal(solo.api.read('match'),null)
  console.log('PASS complete Comic vs Water solo match with AI advance and round scores')
} finally { rmSync(dir,{recursive:true,force:true}) }
