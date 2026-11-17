// Exercise the browser client directly against the Lua server used by the Mac client.
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, readFileSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {Api} from '../src/api.js'
import {Match} from '../src/session.js'

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
const deck = f => ({faction:f.id, deck:f.starters['30']})
try {
  let host=client(), guest=client()
  await host.open({op:'create',mode:'duel',player:deck(catalog.factions[0]),rules:catalog.rules})
  assert.equal(host.code.length,6)
  host=session(host.api)
  await host.resume()
  assert.equal(host.status,'waiting')
  await guest.open({op:'join',code:host.code,player:deck(catalog.factions[1]),rules:catalog.rules})
  await host.tick()
  assert.equal(host.view.seat,1)
  assert.equal(guest.view.seat,2)
  assert.equal(host.view.players[1].cards,undefined)
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
