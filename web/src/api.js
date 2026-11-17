// These paths and payloads match online/api.lua. Only the publishable key ships.
export class GameError extends Error {
  constructor(code, message, temporary = false) {
    super(message)
    Object.assign(this, {code, temporary})
  }
}

export class Api {
  constructor({url, key}, storage = localStorage) {
    this.url = url
    this.key = key
    this.storage = storage
    this.prefix = 'tide-timber:' + new URL('.', location.href).pathname + ':' + url + ':'
  }

  read(key) {
    const value = this.storage.getItem(this.prefix + key)
    return value ? JSON.parse(value) : null
  }

  save(key, value) {
    if (value === null) this.storage.removeItem(this.prefix + key)
    else this.storage.setItem(this.prefix + key, JSON.stringify(value))
  }

  async post(path, body, token) {
    const abort = new AbortController()
    const timer = setTimeout(() => abort.abort(), 40000)
    try {
      const headers = {apikey: this.key, 'Content-Type': 'application/json'}
      if (token) headers.Authorization = 'Bearer ' + token
      const response = await fetch(this.url + path, {
        method: 'POST', headers, body: JSON.stringify(body), signal: abort.signal,
        credentials: 'omit', cache: 'no-store'
      })
      const data = await response.json()
      if (!response.ok) {
        throw new GameError(data.error_code || String(response.status),
          data.msg || data.message || data.error_description || 'Server returned HTTP ' + response.status,
          response.status >= 500 || [408, 429].includes(response.status))
      }
      if (!data || typeof data !== 'object') throw Error('Invalid response')
      return data
    } catch (error) {
      if (error instanceof GameError) throw error
      throw new GameError('network', 'Could not reach the game server.', true)
    } finally {
      clearTimeout(timer)
    }
  }

  authorize(rejectedToken) {
    if (this.authorizing) return this.authorizing
    const renew = async () => {
      const old = this.read('auth')
      if (old && old.expires_at > Date.now() + 60000 && old.access_token !== rejectedToken) return old.access_token
      const data = old
        ? await this.post('/auth/v1/token?grant_type=refresh_token', {refresh_token: old.refresh_token})
        : await this.post('/auth/v1/signup', {data: {}})
      if (!data.access_token || !data.refresh_token) throw new GameError('auth', 'Sign-in returned an incomplete session.')
      this.save('auth', {
        access_token: data.access_token, refresh_token: data.refresh_token,
        expires_at: Date.now() + (data.expires_in || 3600) * 1000
      })
      return data.access_token
    }
    // Coordinate token rotation with other tabs on modern mobile/desktop browsers.
    this.authorizing = (navigator.locks
      ? navigator.locks.request(this.prefix + 'authorize', renew)
      : renew()).finally(() => { this.authorizing = null })
    return this.authorizing
  }

  async request(path, body) {
    const token = await this.authorize()
    let data
    try {
      data = await this.post(path, body, token)
    } catch (error) {
      if (error.code !== '401') throw error
      data = await this.post(path, body, await this.authorize(token))
    }
    if (data.ok === false || data.error) throw new GameError(data.error, data.message || 'This match is no longer available.')
    return data
  }

  game(body) { return this.request('/functions/v1/game', body) }

  state(match, seq, log) {
    return this.request('/rest/v1/rpc/match_state', {p_match: match, p_seq: seq, p_log: log})
  }
}
