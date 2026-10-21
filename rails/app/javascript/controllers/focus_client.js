// Ephemeral transport only. SQLite snapshots are authoritative. No storage APIs.
export function encodeUid(uid) {
  return 'u-' + btoa(String.fromCharCode(...new TextEncoder().encode(uid))).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '')
}

export class FocusClient {
  constructor(transport) {
    this.transport = transport
    this.sequence = 0
    this.listeners = new Set()
    this.confirmed = false
  }
  subscribe(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) }
  notify() { this.listeners.forEach(listener => listener()) }
  apply(snapshot, sequence) {
    if (sequence !== this.sequence) return
    const previous = this.snapshot?.session, next = snapshot.session
    if (previous && next?.uid === previous.uid && next.version < previous.version) return
    if (this.readFailure && this.message === this.readFailure && !this.pending) this.message = 'Estado confirmado pelo servidor.'
    this.readFailure = null
    this.snapshot = snapshot
    this.observedAt = performance.now()
    this.confirmed = true
    this.notify()
  }
  async read() {
    if (this.sending) return
    const sequence = ++this.sequence
    try { this.apply(await this.transport('/focus/state'), sequence) }
    catch (error) {
      if (sequence !== this.sequence) return
      this.confirmed = false
      this.readFailure = error.message
      this.message = error.message
      this.notify()
    }
  }
  async execute(envelope) {
    if (this.sending || (this.pending && envelope !== this.pending)) return
    this.pending = envelope
    this.sending = true
    this.confirmed = false
    ++this.sequence // Invalidate reads started before this command.
    this.message = 'Confirmando ação no servidor…'
    this.notify()
    let accepted = false
    try {
      const data = await this.transport(envelope.url, envelope.body, envelope.method || 'POST')
      accepted = true
      this.pending = null
      this.message = envelope.success || 'Ação confirmada.'
      if (data.current) this.apply(data.current, this.sequence) // Never render the historical receipt.
    } catch (error) {
      // Unknown responses and 503 retain the exact serialized intent for retry.
      if (error.status && error.status < 500 && error.status !== 401) this.pending = null
      this.message = error.message
    } finally {
      this.sending = false
      this.notify()
      await this.read()
    }
    return accepted
  }
}

export async function focusRequest(url, body, method = 'GET') {
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 15000)
  try {
    const response = await fetch(url, { method, signal: controller.signal, credentials: 'same-origin', cache: 'no-store', headers: {
      Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content } : {})
    }, ...(body ? { body: JSON.stringify(body) } : {}) })
    const data = await response.json()
    if (!response.ok) {
      const error = new Error(response.status === 401 ? 'Sessão expirada. Entre novamente antes de tentar a mesma ação.' : data.message || 'Ação não confirmada.')
      error.status = response.status
      throw error
    }
    return data
  } catch (error) {
    if (error.status) throw error
    throw new Error('Resposta não confirmada. Confira a conexão e tente novamente a mesma ação.')
  } finally { clearTimeout(timeout) }
}

const clients = new Map()
export function sharedFocus(key) {
  if (!clients.has(key)) clients.set(key, new FocusClient(focusRequest))
  return clients.get(key)
}
