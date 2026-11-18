// Exercise the browser client directly against the Lua server used by the Mac client.
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, readFileSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {Api} from '../src/api.js'
import {Match} from '../src/session.js'
import {board,choices} from '../src/board.js'
import {cardFace,inspect} from '../src/ui.js'

const catalog = JSON.parse(readFileSync(new URL('../dist/catalog.json', import.meta.url)))
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
    assert.equal(f.smallStarter.length,20)
  }
  for (const card of Object.values(catalog.cards)) {
    const face=cardFace(card,'catalog',card.id)
    assert.match(face,/<span class="card-image"><img[^>]+><\/span><span class="card-caption">/)
    const visible=(face+inspect(card)).replace(/<[^>]+>/g,'')
    assert.doesNotMatch(visible,/\b(?:rank|uncommon|rare|common)\b|(?:Super|Fantasy|Water):\d+/i)
    if (card.type==='Unit') assert.ok(visible.includes(card.health+'/'+card.health+' HP'))
  }
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
    const metrics={scores:[1,1],units:{},hand:[],attackPreview:{}}
    for (const [i,p] of view.players.entries()) {
      const c=catalog.factions[i].starter.map(id=>catalog.cards[id]).find(c=>c.health>3)
      const u={u:100+i,c:c.id,hp:c.health-i-1}
      p.rows[i]=[u]
      metrics.units[u.u]={seat:i+1,row:i+1,pos:1,strength:c.strength}
    }
    const html=board({view,ready:true,active:true,log:[]},catalog,metrics,null)
    const opts=view.players.map(p=>p.rows.flat()[0])
    view.prompt={kind:'unit',context:{op:'heal'},options:opts}
    const prompt=choices(view,catalog,metrics).body
    for (const u of opts) {
      const hp=u.hp+'/'+catalog.cards[u.c].health+' HP'
      assert.ok(html.includes(hp) && prompt.includes(hp),'battlefield and choice show wounded HP')
    }
    assert.doesNotMatch(html,/Attack with a unit|ready unit/i)
  }
  const actor=host.ready?host:guest, other=actor===host?guest:host
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
