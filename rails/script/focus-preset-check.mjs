import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
const url = source => 'data:text/javascript;base64,' + Buffer.from(source).toString('base64')
const clientUrl = url(readFileSync(new URL('../app/javascript/controllers/focus_client.js', import.meta.url), 'utf8'))
const { FocusClient } = await import(clientUrl)
const { FocusPreset } = await import(url(readFileSync(new URL('../app/javascript/controllers/focus_preset.js', import.meta.url), 'utf8')))
const copy = value => structuredClone(value)
const error = status => Object.assign(new Error(status ? 'HTTP '+status : 'Lost response'), status ? {status} : {})
function fixture() {
  const f = { state:{session:null,preset_seconds:1500,preference_version:0},calls:[],hooks:{},fields:{theme:'dark',wallpaper:'aurora',dock:['home','focus'],widgets:['tasks','focus'],filter:'all'} }
  f.client = new FocusClient(async (_url, body, method) => {
    if (!body) { await f.hooks.read?.(); return copy(f.state) }
    f.calls.push({body:copy(body),method})
    await f.hooks.before?.()
    if (body.version !== f.state.preference_version || f.state.session) throw error(409)
    f.state.preset_seconds = body.duration_seconds; f.state.preference_version++
    const reply={duration_seconds:body.duration_seconds,version:f.state.preference_version}
    await f.hooks.after?.(reply)
    return reply
  })
  f.client.snapshot=copy(f.state);f.client.confirmed=true
  f.flow = new FocusPreset(f.client)
  return f
}
const results=[]
async function check(name,test){await test();results.push({name,result:'PASS'})}
await check('A: Normal HTTP success confirms requested preset and changes only its field',async()=>{
 const f=fixture(),fields=copy(f.fields);assert.equal(await f.flow.save(2700,0),true)
 assert.match(f.client.message,/Resposta de sucesso confirmada/);assert.match(f.client.message,/atual confirmado no servidor: 45 min/);assert.equal(f.client.pending,null);assert.equal(f.state.session,null);assert.deepEqual(f.fields,fields);assert.equal(f.calls.length,1)
})
await check('B/E: Lost response before write reconciles different value without automatic reapply',async()=>{
 const f=fixture();f.hooks.before=()=>{throw error()};await f.flow.save(2700,0)
 assert.match(f.client.message,/25 min/);assert.match(f.client.message,/Difere do solicitado \(45 min\).*nova escolha explícita/);assert.equal(f.state.preference_version,0);assert.equal(f.calls.length,1);assert.equal(f.client.pending,null)
})
await check('B/D: Lost response after commit confirms equal current value without claiming authorship',async()=>{
 const f=fixture();f.hooks.after=()=>{throw error()};assert.equal(await f.flow.save(2700,0),false)
 assert.match(f.client.message,/45 min/);assert.match(f.client.message,/autoria da alteração não foi comprovada/);assert.doesNotMatch(f.client.message,/sucesso confirmada/);assert.equal(f.state.preference_version,1);assert.equal(f.calls.length,1);assert.equal(f.client.pending,null)
})
await check('C/F: Unavailable GET preserves original envelope; explicit retry gets 409 then confirms equal value',async()=>{
 const f=fixture();f.hooks.after=()=>{throw error()};f.hooks.read=()=>{throw error()};await f.flow.save(2700,0)
 const envelope=f.client.pending;assert.ok(envelope);assert.match(f.client.message,/Operação incerta/);assert.equal(f.client.confirmed,false)
 f.hooks.read=null;await f.flow.retry();assert.deepEqual(f.calls[0],f.calls[1]);assert.match(f.client.message,/HTTP 409/);assert.match(f.client.message,/autoria.*não foi comprovada/);assert.equal(f.state.preference_version,1);assert.equal(f.client.pending,null)
})
await check('409 plus failed reconciliation retains exact obsolete version until a read succeeds',async()=>{
 const f=fixture();f.state.preference_version=3;f.hooks.read=()=>{throw error()};await f.flow.save(2700,0)
 const envelope=f.client.pending;assert.equal(envelope.body.version,0);assert.match(f.client.message,/HTTP 409.*Operação incerta/)
 await f.flow.retry();assert.equal(f.calls.length,2);assert.deepEqual(f.calls[0],f.calls[1]);assert.equal(f.client.pending,envelope)
 f.hooks.read=null;await f.client.read();assert.equal(f.client.pending,null);assert.match(f.client.message,/25 min.*Difere/);assert.equal(f.state.preference_version,3)
})
await check('G: Other tab saves same requested value; 409 cannot prove original authorship',async()=>{
 const f=fixture();f.hooks.before=()=>{f.state.preset_seconds=2700;f.state.preference_version++};await f.flow.save(2700,0)
 assert.match(f.client.message,/HTTP 409/);assert.match(f.client.message,/autoria.*não foi comprovada/);assert.equal(f.state.preference_version,1)
})
await check('G: Concurrent theme Dock widgets or filters are never resent by preset reconciliation',async()=>{
 for(const field of ['theme','wallpaper','dock','widgets','filter']){
  const f=fixture();f.hooks.before=()=>{f.fields[field]='concurrent';f.state.preference_version++};await f.flow.save(2700,0)
  assert.equal(f.fields[field],'concurrent');assert.equal(f.state.preset_seconds,1500);assert.equal(f.calls.length,1);assert.deepEqual(Object.keys(f.calls[0].body).sort(),['duration_seconds','version']);assert.match(f.client.message,/nova escolha explícita/)
 }
})
await check('Timeout and 503 preserve envelope while GET fails; no automatic retry on reads',async()=>{
 for(const status of [undefined,503]){
  const f=fixture();f.hooks.before=()=>{throw error(status)};f.hooks.read=()=>{throw error()};await f.flow.save(2700,0)
  const envelope=f.client.pending;await f.client.read();assert.equal(f.calls.length,1);assert.equal(f.client.pending,envelope)
  f.hooks.before=null;f.hooks.read=null;await f.flow.retry();assert.deepEqual(f.calls[0],f.calls[1]);assert.match(f.client.message,/Resposta de sucesso confirmada/);assert.equal(f.state.preference_version,1)
 }
})
await check('HTTP success followed by failed GET distinguishes saved acknowledgement from unavailable current state',async()=>{
 const f=fixture();f.hooks.read=()=>{throw error()};await f.flow.save(2700,0)
 assert.match(f.client.message,/sucesso confirmada.*45 min salvos.*atual está indisponível/);assert.equal(f.client.pending,null)
 f.hooks.read=null;await f.client.read();assert.match(f.client.message,/atual confirmado no servidor: 45 min/)
})
await check('Success then concurrent change reports both acknowledged request and different current preset',async()=>{
 const f=fixture();f.hooks.after=()=>{f.state.preset_seconds=1500;f.state.preference_version++};await f.flow.save(2700,0)
 assert.match(f.client.message,/45 min salvos.*atual confirmado no servidor: 25 min.*mudou depois/);assert.equal(f.calls.length,1)
})
await check('Only 25 and 45 presets are sent; occupied sessions remain unchanged and reject PATCH',async()=>{
 for(const status of ['running','paused','ready']){
  const f=fixture();f.state.session={uid:'legacy/á',status,duration_seconds:1500};const before=copy(f.state.session)
  await f.flow.save(2700,0);assert.deepEqual(f.state.session,before);assert.equal(f.state.preset_seconds,1500);assert.match(f.client.message,/HTTP 409/)
 }
 const f=fixture();for(const duration of [0,60,1499,2701,'2700'])await f.flow.save(duration,0);assert.equal(f.calls.length,0)
})
await check('Reload loses pending envelope and GET does not create or retry PATCH',async()=>{
 const f=fixture();f.hooks.after=()=>{throw error()};f.hooks.read=()=>{throw error()};await f.flow.save(2700,0)
 const reloaded=new FocusClient(async()=>copy(f.state));new FocusPreset(reloaded);await reloaded.read();assert.equal(reloaded.pending,undefined);assert.equal(reloaded.snapshot.preset_seconds,2700);assert.equal(f.calls.length,1)
})
await check('Identical shared coordinator serializes duplicate activations and explicit retry',async()=>{
 const f=fixture();await Promise.all([f.flow.save(2700,0),f.flow.save(2700,0),f.flow.retry()]);assert.equal(f.calls.length,1)
 const oldMessage=f.client.message;f.client.message='Estimativa aceita e salva. Retomada confirmada.';await f.client.read();assert.notEqual(f.client.message,oldMessage);assert.match(f.client.message,/Retomada confirmada/)
})
await check('Incompatible HTTP success cannot masquerade as acknowledged write',async()=>{
 const f=fixture();f.hooks.after=reply=>{reply.version+=10};await f.flow.save(2700,0);assert.match(f.client.message,/autoria.*não foi comprovada/);assert.doesNotMatch(f.client.message,/sucesso confirmada/)
})
await check('Preset acknowledgement never updates detached missing pending or dirty appearance editors',async()=>{
 const source='const Controller=class {};\n'+readFileSync(new URL('../app/javascript/controllers/focus_controller.js',import.meta.url),'utf8').replace(/^import .*\n/gm,'')
 const {default:C}=await import(url(source)),previousWindow=globalThis.window
 try{
  const c=new C();c.client={confirmed:true,snapshot:{preference_version:2}};c.element={isConnected:false,closest:()=>null}
  globalThis.window={Stimulus:{getControllerForElementAndIdentifier:()=>null}}
  assert.doesNotThrow(()=>c.advancePreference(1));c.element.isConnected=true;assert.doesNotThrow(()=>c.advancePreference(1))
  for(const changed of ['pending','failed','draft','clean']){
   const editor={version:1,pending:changed==='pending'?1:0,failed:changed==='failed',preferences:{theme:changed==='draft'?'light':'dark'},confirmed:{theme:'dark'}}
   window.Stimulus.getControllerForElementAndIdentifier=()=>editor;c.advancePreference(1)
   assert.equal(editor.version,changed==='clean'?2:1)
  }
 }finally{globalThis.window=previousWindow}
})
console.log(JSON.stringify({passed:results.length,results},null,2))
