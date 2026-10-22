import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
const moduleUrl = source => 'data:text/javascript;base64,' + Buffer.from(source).toString('base64')
const clientUrl = moduleUrl(readFileSync(new URL('../app/javascript/controllers/focus_client.js', import.meta.url), 'utf8'))
const { FocusClient } = await import(clientUrl)
const { FocusRecovery } = await import(moduleUrl(readFileSync(new URL('../app/javascript/controllers/focus_recovery.js', import.meta.url), 'utf8').replace("'controllers/focus_client'", JSON.stringify(clientUrl))))
const copy = value => structuredClone(value)
function fixture(candidate = 1230) {
  const initial = { session: { uid: '42/á?%#项目', status: 'paused', version: 7, elapsed_seconds: 30, duration_seconds: 1500 }, recovery: { receipt_id: 42, version: 7, checkpoint_seconds: 30, candidate_seconds: candidate } }
  const f = { state: copy(initial), calls: [], receipts: new Map(), hooks: {} }
  f.client = new FocusClient(async (url, body) => {
    if (!body) { await f.hooks.read?.(); return copy(f.state) }
    f.calls.push(copy(body))
    await f.hooks.before?.(body)
    let result = f.receipts.get(body.command_id)
    const replayed = !!result
    if (!result) {
      if (body.version !== f.state.session?.version) { const error = new Error('Versão obsoleta'); error.status = 409; throw error }
      const session = f.state.session
      if (body.parameters.action === 'resolve') {
        session.elapsed_seconds = f.state.recovery.candidate_seconds
        session.status = session.elapsed_seconds === session.duration_seconds ? 'awaiting_confirmation' : 'paused'
        f.state.recovery = null
      } else session.status = 'running'
      session.version++
      result = { focus_contract: 1, session: copy(session), recovery: null,
        ...(body.parameters.action === 'resolve' ? { resolved_recovery_id: body.parameters.recovery_id, decision: 'accept_estimate' } : {}) }
      f.receipts.set(body.command_id, result)
    }
    await f.hooks.after?.(body)
    const response = { command_id: body.command_id, result: copy(result), current: copy(f.state), replayed }
    return f.hooks.response ? f.hooks.response(response) : response
  })
  f.client.apply(copy(initial), 0)
  let id = 0
  f.flow = new FocusRecovery(f.client, () => `synthetic-${++id}`)
  return f
}
const results = []
async function check(name, run) { await run(); results.push({ name, result: 'PASS' }) }
await check('Partial candidate accepts then resumes with two owned receipts and fixed versions', async () => {
  const f = fixture(); await f.flow.accept()
  assert.deepEqual(f.calls.map(x => [x.parameters.action, x.version]), [['resolve',7],['resume',8]])
  assert.notEqual(f.calls[0].command_id,f.calls[1].command_id); assert.equal(f.receipts.size,2)
  assert.equal(f.state.session.status,'running');assert.equal(f.state.session.elapsed_seconds,1230)
  assert.match(f.client.message,/Retomada confirmada/);assert.equal(f.flow.busy,false)
  assert.deepEqual(Object.keys(f.calls[0].parameters).sort(),['action','decision','recovery_id'])
  assert.deepEqual(f.calls[1].parameters,{action:'resume'})
})
await check('Integral candidate awaits explicit completion without resume or complete', async () => {
  const f=fixture(1500);await f.flow.accept();assert.equal(f.state.session.status,'awaiting_confirmation');assert.equal(f.calls.length,1);assert.match(f.client.message,/revise a conclusão/)
})
await check('Invalid or stale candidate cannot be accepted', async () => {
  for(const candidate of [null,29,1501,1.5]){const f=fixture(candidate);await f.flow.accept();assert.equal(f.calls.length,0)}
  const f=fixture();f.client.snapshot.recovery.version=6;await f.flow.accept();assert.equal(f.calls.length,0)
})
await check('Lost resolve response and similar GET do not authorize resume; explicit replay does', async () => {
  const f=fixture();let lost=true
  f.hooks.after=body=>{if(body.parameters.action==='resolve'&&lost){lost=false;throw new Error('Lost resolve')}}
  await f.flow.accept();assert.equal(f.state.session.elapsed_seconds,1230);assert.equal(f.state.session.status,'paused');assert.equal(f.calls.length,1);assert.ok(f.client.pending)
  await f.client.read();assert.equal(f.calls.length,1)
  await f.flow.retry();assert.equal(f.state.session.status,'running');assert.deepEqual(f.calls[0],f.calls[1]);assert.equal(f.receipts.size,2)
})
await check('Lost resume response replays only that same resume and never repeats resolve', async () => {
  const f=fixture();let lost=true
  f.hooks.after=body=>{if(body.parameters.action==='resume'&&lost){lost=false;throw new Error('Lost resume')}}
  await f.flow.accept();assert.equal(f.state.session.status,'running');assert.match(f.client.message,/Estimativa aceita.*ainda não confirmada/)
  const pending=f.client.pending;await f.flow.retry();assert.deepEqual(f.calls[1],f.calls[2]);assert.equal(f.calls.filter(x=>x.parameters.action==='resolve').length,1);assert.equal(f.receipts.size,2);assert.equal(f.client.pending,null);assert.equal(pending.body.version,8)
})
await check('503 or timeout before resume retains accepted checkpoint and identical envelope', async () => {
  for(const status of [undefined,503]){
    const f=fixture();let fail=true
    f.hooks.before=body=>{if(body.parameters.action==='resume'&&fail){fail=false;const error=new Error('Timeout or busy');error.status=status;throw error}}
    await f.flow.accept();assert.equal(f.state.session.status,'paused');assert.equal(f.state.session.elapsed_seconds,1230);assert.ok(f.client.pending);assert.match(f.client.message,/Estimativa aceita.*ainda não confirmada/)
    await f.client.read();assert.equal(f.calls.length,2);await f.flow.retry();assert.deepEqual(f.calls[1],f.calls[2]);assert.equal(f.state.session.status,'running')
  }
})
await check('Archived project or completed task rejects resume but keeps accepted time', async () => {
  for(const message of ['Projeto arquivado','Reabra a tarefa']){
    const f=fixture();f.hooks.before=body=>{if(body.parameters.action==='resume'){const error=new Error(message);error.status=409;throw error}}
    await f.flow.accept();assert.equal(f.state.session.status,'paused');assert.equal(f.state.session.elapsed_seconds,1230);assert.equal(f.client.pending,null);assert.equal(f.flow.operation,null);assert.match(f.client.message,/Estimativa aceita.*Retomada rejeitada/);assert.ok(f.client.message.includes(message));await f.flow.retry();assert.equal(f.calls.length,2)
  }
})
await check('Another tab changes version after own resolve: never borrow its version to resume', async () => {
  const f=fixture();f.hooks.read=()=>{if(f.state.session.version===8)f.state.session.version=9}
  await f.flow.accept();assert.equal(f.calls.length,1);assert.equal(f.state.session.status,'paused');assert.match(f.client.message,/estado mudou/);assert.equal(f.flow.operation,null)
})
await check('Another tab cancels or replaces session after own resolve: no continuation', async () => {
  for(const replacement of [null,{uid:'other',version:1,status:'paused',elapsed_seconds:1230}]){
    const f=fixture();f.hooks.read=()=>{f.state.session=copy(replacement)};await f.flow.accept();assert.equal(f.calls.length,1)
  }
})
await check('GET failure after own resolve does not start work on an unconfirmed snapshot', async () => {
  const f=fixture();f.hooks.read=()=>{throw new Error('Offline GET')};await f.flow.accept();assert.equal(f.calls.length,1);assert.equal(f.state.session.status,'paused');assert.match(f.client.message,/Estimativa aceita.*Retomada não solicitada/)
})
await check('A rejected resolve cannot be inferred from matching state from another operation', async () => {
  const f=fixture();f.hooks.before=()=>{f.state.session={...f.state.session,status:'paused',version:8,elapsed_seconds:1230};f.state.recovery=null;const e=new Error('Other tab');e.status=409;throw e}
  await f.flow.accept();assert.equal(f.calls.length,1);assert.equal(f.client.pending,null);assert.equal(f.flow.operation,null)
})
await check('Wrong receipt ID command ID version decision or result rejects acknowledgement and preserves retry', async () => {
  const mutations=[r=>r.command_id='other',r=>r.result.resolved_recovery_id=43,r=>r.result.session.version=9,r=>r.result.decision='keep_checkpoint',r=>r.result.focus_contract=2,r=>r.result.session.elapsed_seconds=1231,r=>delete r.current]
  for(const mutate of mutations){const f=fixture();f.hooks.response=r=>{mutate(r);return r};await f.flow.accept();assert.equal(f.calls.length,1);assert.ok(f.client.pending);assert.equal(f.flow.operation.phase,'resolve');assert.match(f.client.message,/Resposta desta recuperação não confirmada/)}
})
await check('Repeated activation while busy creates only one resolution and one resume', async () => {
  const f=fixture();await Promise.all([f.flow.accept(),f.flow.accept(),f.flow.retry()]);assert.equal(f.calls.length,2);assert.equal(f.receipts.size,2)
})
await check('Reload loses continuation and GET never automatically retries or resumes', async () => {
  const f=fixture();let fail=true;f.hooks.before=body=>{if(body.parameters.action==='resume'&&fail){fail=false;throw new Error('Timeout')}}
  await f.flow.accept();const before=f.calls.length
  const client=new FocusClient(async()=>copy(f.state)),flow=new FocusRecovery(client);await client.read();await flow.retry();assert.equal(f.calls.length,before);assert.equal(client.snapshot.session.status,'paused');assert.equal(flow.operation,undefined)
})
await check('Historical resume replay cannot regress current state or send another command', async () => {
  const f=fixture();let lost=true
  f.hooks.after=body=>{if(body.parameters.action==='resume'&&lost){lost=false;throw new Error('Lost')}}
  await f.flow.accept();f.state.session={...f.state.session,status:'paused',version:10};await f.flow.retry();assert.equal(f.client.snapshot.session.status,'paused');assert.equal(f.client.snapshot.session.version,10);assert.equal(f.calls.length,3);assert.match(f.client.message,/estado atual/)
})
console.log(JSON.stringify({passed:results.length,results},null,2))
