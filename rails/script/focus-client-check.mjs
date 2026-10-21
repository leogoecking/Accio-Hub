import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
const source = readFileSync(new URL('../app/javascript/controllers/focus_client.js', import.meta.url), 'utf8')
const { FocusClient, encodeUid, focusRequest } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'))
const state = (version, uid = 'a') => ({ session: uid ? { uid, version, status: 'running' } : null })
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b }); return { resolve, reject, promise } }
const results = []
async function check(name, test) { await test(); results.push({ name, result: 'PASS' }) }
await check('Delayed GET cannot replace newer snapshot', async () => {
  const first = deferred(), second = deferred(); let index = 0
  const client = new FocusClient(() => [first, second][index++].promise)
  const a = client.read(), b = client.read(); second.resolve(state(2)); await b; first.resolve(state(1)); await a
  assert.equal(client.snapshot.session.version, 2)
})
await check('Lower version of same UID cannot regress even on a later response', async () => {
  const client = new FocusClient(async () => state(1)); client.apply(state(3), 0); await client.read(); assert.equal(client.snapshot.session.version, 3)
})
await check('Lost response retains identical command ID payload URL and method; replay uses current', async () => {
  const calls = []; let lost = true
  const client = new FocusClient(async (url, body, method) => {
    if (!body) return { ...state(2), session: { ...state(2).session, status: 'paused' } }
    calls.push(JSON.stringify({ url, body, method })); if (lost) { lost = false; throw new Error('Lost') }
    return { replayed: true, result: state(1), current: { ...state(2), session: { ...state(2).session, status: 'paused' } } }
  })
  const envelope = { url: '/focus/a/commands', body: { command_id: 'stable', version: 1, kind: 'pause', parameters: { action: 'pause' } } }
  await client.execute(envelope); assert.equal(client.pending, envelope)
  await client.execute({ ...envelope }); assert.equal(calls.length, 1)
  await client.execute(client.pending); assert.equal(calls[0], calls[1]); assert.equal(client.pending, null); assert.equal(client.snapshot.session.status, 'paused')
})
await check('Command invalidates outstanding read; same client serializes writes', async () => {
  const read = deferred(), write = deferred(); let gets = 0, writes = 0
  const client = new FocusClient(async (_url, body) => {
    if (!body) return ++gets === 1 ? read.promise : state(5, 'new')
    ++writes; return write.promise
  })
  const a = client.read(), envelope = { url: '/focus/prepare', body: { command_id: 'x' } }, b = client.execute(envelope)
  await client.execute(envelope); assert.equal(writes, 1)
  read.resolve(state(0, 'old')); await a; assert.equal(client.snapshot, undefined)
  write.resolve({ current: state(5, 'new') }); await b; assert.equal(client.snapshot.session.uid, 'new')
})
await check('Definitive rejection releases intent; 401 and 503 preserve the identical retry', async () => {
  for (const status of [401, 409, 422, 503]) {
    const client = new FocusClient(async (_url, body) => { if (!body) return state(3); const error = new Error('failure'); error.status = status; throw error })
    const envelope = { url: '/focus/a/commands', body: { command_id: 'x' } }; await client.execute(envelope)
    assert.equal(!!client.pending, [401,503].includes(status))
  }
})
await check('Unicode and legacy route UIDs preserve UTF8 without changing stored ID', () => {
  const uid = '42/á?%#项目'; assert.equal(Buffer.from(encodeUid(uid).slice(2), 'base64url').toString('utf8'), uid)
})
await check('Successful reconnection clears a read failure without dropping a pending command', async () => {
  let offline = true
  const client = new FocusClient(async () => { if (offline) throw new Error('Offline synthetic'); return state(2) })
  await client.read(); assert.equal(client.confirmed,false); assert.equal(client.message,'Offline synthetic')
  offline=false; await client.read(); assert.equal(client.confirmed,true); assert.equal(client.message,'Estado confirmado pelo servidor.')
  client.pending={url:'/focus/a/commands',body:{command_id:'pending'}};offline=true;await client.read();offline=false;await client.read();assert.ok(client.pending);assert.equal(client.message,'Offline synthetic')
})
await check('Subscriptions disconnect without duplicate notifications', () => {
  const client = new FocusClient(async () => state(1)); let calls = 0
  const unsubscribe = client.subscribe(() => calls++); client.notify(); unsubscribe(); client.notify(); assert.equal(calls, 1)
})
const presentationSource = readFileSync(new URL('../app/javascript/controllers/focus_presenter.js', import.meta.url), 'utf8')
const { visualTime, primaryAction, actionInk } = await import('data:text/javascript;base64,' + Buffer.from(presentationSource).toString('base64'))
await check('Accent contrast preserves default ink and adapts purple and middle gray', () => {
  assert.equal(actionInk('#b1f07d'),'#10201c'); assert.equal(actionInk('#8050b0'),'#ffffff'); assert.equal(actionInk('#777777'),'#000000'); assert.equal(actionInk('#ffffff'),'#10201c')
})
await check('Monotonic interpolation is visual only and stops at zero or unconfirmed/hidden state', () => {
  const before = globalThis.document, old = globalThis.performance
  try {
    globalThis.document = { visibilityState: 'visible' }; globalThis.performance = { now: () => 4000 }
    const client = { confirmed: true, observedAt: 1000, snapshot: { session: { status: 'running', duration_seconds: 1500 }, timing: { nominal_seconds: 10 } } }
    const original = JSON.stringify(client.snapshot); assert.equal(visualTime(client).remaining, 1487)
    client.confirmed = false; assert.equal(visualTime(client).remaining, 1490)
    client.confirmed = true; document.visibilityState = 'hidden'; assert.equal(visualTime(client).remaining, 1490)
    document.visibilityState = 'visible'; performance.now = () => 2000000; assert.equal(visualTime(client).remaining, 0)
    assert.equal(JSON.stringify(client.snapshot), original)
    assert.equal(primaryAction(client, 0).action, 'reconcile')
    client.snapshot.session.status = 'awaiting_confirmation'; assert.equal(primaryAction(client, 0).action, 'confirm')
    client.snapshot.recovery = { receipt_id: 1 }; client.snapshot.session.status = 'paused'; assert.equal(primaryAction(client, 0).action, null)
  } finally { globalThis.document = before; globalThis.performance = old }
})
await check('Authenticated transport has CSRF no-store timeout cleanup and retains error status', async () => {
  const saved = { fetch: globalThis.fetch, document: globalThis.document, setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout }
  let created = 0, cleared = 0, timer, received
  try {
    globalThis.document = { querySelector: () => ({ content: 'synthetic-csrf' }) }
    globalThis.setTimeout = callback => { created++; timer = callback; return 7 }
    globalThis.clearTimeout = id => { assert.equal(id, 7); cleared++ }
    globalThis.fetch = async (_url, options) => { received = options; return { ok: true, json: async () => state(0) } }
    await focusRequest('/focus/state'); assert.equal(received.method, 'GET'); assert.equal(received.body, undefined); assert.equal(received.cache, 'no-store'); assert.equal(received.credentials, 'same-origin')
    await focusRequest('/focus/prepare', { command_id: 'x' }, 'POST'); assert.equal(received.headers['X-CSRF-Token'], 'synthetic-csrf'); assert.equal(received.body, '{"command_id":"x"}')
    globalThis.fetch = async () => ({ ok: false, status: 503, json: async () => ({ message: 'busy' }) })
    await assert.rejects(focusRequest('/focus/state'), error => error.status === 503)
    globalThis.fetch = (_url, options) => new Promise((_resolve, reject) => { options.signal.addEventListener('abort', () => reject(new Error('timeout'))); timer() })
    await assert.rejects(focusRequest('/focus/state'), /Resposta não confirmada/)
    assert.equal(created, 4); assert.equal(cleared, created)
  } finally { Object.assign(globalThis, saved) }
})
console.log(JSON.stringify({ passed: results.length, results }, null, 2))
