// Exactly one poll, action (including frame playback), or leave may be in flight.
const pause = ms => new Promise(resolve => setTimeout(resolve, ms))
export class Match {
  constructor(api, update) {
    this.api = api
    this.update = update
    this.status = 'idle'
    this.log = []
    this.seq = -1
  }

  get active() { return ['waiting', 'active', 'resuming'].includes(this.status) }
  get mine() {
    const v = this.view
    return this.status === 'active' && v && (v.prompt?.actor ?? v.active) === v.seat
  }
  get ready() { return this.mine && (!this.busy || this.backgroundPoll) && !this.pending && !this.recovering }

  remember() {
    if (this.active) this.api.save('match', this.id)
    else if (this.api.read('match') === this.id) this.api.save('match', null)
  }

  async open(body) {
    if (this.busy || this.active) return
    this.busy = true
    this.update()
    try {
      const r = await this.api.game(body)
      this.id = r.match
      this.status = r.view ? 'active' : 'waiting'
      this.code = r.code
      this.log = r.log || []
      this.view = r.view
      this.seq = r.seq
      this.remember()
    } finally { this.finish() }
  }

  async resume() {
    this.id = this.api.read('match')
    if (!this.id || this.busy) return
    this.status = 'resuming'
    this.recovering = true
    this.update()
    await this.tick()
  }

  schedule(delay) {
    clearTimeout(this.timer)
    if (this.active) this.timer = setTimeout(() => this.tick(), delay)
  }

  finish() {
    this.busy = false
    this.update()
    if (!this.active) return
    if (this.recovering || this.pending) this.schedule(this.retryDelay || 1500)
    else if (this.view?.mode !== 'solo') this.schedule(this.mine ? 4000 : 1500)
    else if (!this.view.prompt && this.view.controllers[this.view.active - 1] === 'AI') this.schedule(250)
  }

  async refresh(full = false) {
    const st = await this.api.state(this.id, full ? -1 : this.seq, full ? 0 : this.log.length)
    if (st.view) {
      this.log = this.log.slice(0, st.log_from).concat(st.log || [])
      this.view = st.view
    }
    this.code = st.code || this.code
    this.status = st.status
    this.left = st.left
    this.seq = st.seq
    this.remember()
    if (this.pending && (!this.active || (this.pending.op === 'act' && this.pending.seq !== this.seq))) this.clearPending()
  }

  clearPending() {
    const key = 'move:' + this.id
    if (this.pending && this.api.read(key)?.id === this.pending.id) this.api.save(key, null)
    this.pending = null
  }

  tick() {
    if (this.busy || !this.active) return
    this.pump = this.sync()
    return this.pump
  }

  async sync() {
    const isResume = this.status === 'resuming'
    this.backgroundPoll = !this.recovering && !this.pending && (this.status === 'waiting' || this.view?.mode === 'duel')
    this.busy = true
    try {
      if (isResume) this.pending = this.api.read('move:' + this.id)
      if (this.recovering || this.view?.mode !== 'solo') await this.refresh(isResume || this.needFull)
      this.recovering = false
      this.needFull = false
      this.retryDelay = 0
      if (this.active && this.pending) await this.transmit()
      else if (this.status === 'active' && this.view?.mode === 'solo' && !this.view.prompt
          && this.view.controllers[this.view.active - 1] === 'AI') {
        this.prepare({op:'act', action:{type:'advance'}})
        await this.transmit()
      }
    } catch (e) { this.fail(e) }
    finally { this.backgroundPoll = false; this.finish() }
  }

  prepare(body) {
    const id = Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16).padStart(8,'0')).join('')
    this.pending = {...body, match:this.id, seq:this.seq, id}
    this.api.save('move:' + this.id, this.pending)
  }

  async act(action) {
    if (this.backgroundPoll) {
      const seq = this.seq
      await this.pump
      if (seq !== this.seq) return
    }
    if (!this.ready) return
    clearTimeout(this.timer)
    this.busy = true
    this.notice = ''
    try {
      this.prepare({op:'act', action})
      this.update()
      await this.transmit()
    } catch (e) { this.fail(e) }
    finally { this.finish() }
  }

  async transmit() {
    const r = await this.api.game(this.pending)
    if (this.pending.op === 'leave') {
      this.status = 'closed'
    } else if (r.duplicate || r.log_from !== this.log.length) {
      this.needFull = true
      await this.refresh(true)
      this.needFull = false
    } else {
      this.seq = r.seq
      for (const [i, frame] of r.frames.entries()) {
        if (i || this.pending.action.type === 'advance') await pause(850)
        this.view = frame.view
        this.log.push(...frame.log)
        this.update()
      }
      if (this.view.finished) this.status = 'finished'
    }
    this.clearPending()
    this.remember()
  }

  fail(e) {
    if (e.temporary) {
      this.recovering = true
      this.retryDelay = Math.min((this.retryDelay || 750) * 2, 10000)
      return
    }
    if (['stale','conflict','not_active','not_your_turn','no_choice','not_your_choice'].includes(e.code)) {
      this.recovering = this.needFull = true
    } else if (['not_found','rules_mismatch'].includes(e.code)) {
      this.status = 'closed'
      this.remember()
      this.notice = e.message
    } else {
      this.notice = e.message
      if (this.status === 'resuming' || !this.pending) this.status = 'error'
    }
    this.clearPending()
  }

  async leave() {
    if (this.backgroundPoll) await this.pump
    if (this.busy || !this.active) return
    this.busy = true
    clearTimeout(this.timer)
    try {
      this.prepare({op:'leave'})
      this.update()
      await this.transmit()
    } catch (e) { this.fail(e) }
    finally { this.finish() }
  }
}
