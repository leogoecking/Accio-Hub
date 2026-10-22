// E3 integrated verification only. No application clock or data contract is changed.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
const runId = randomUUID()
const root = resolve(import.meta.dirname, '../..'), rails = resolve(root, 'rails')
const workspace = readFileSync(resolve(rails, 'tmp/p12e2-workspace'), 'utf8').trim()
assert.ok(workspace.startsWith(resolve(rails, 'tmp/p12e2-browser-')))
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json'), 'utf8'))
const ids = JSON.parse(readFileSync(resolve(workspace, 'state.json'), 'utf8'))
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, 'docs/assets/p1.2e3/integrated')); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-p12e3-integrated', origin = 'http://127.0.0.1:3127'
const geometryResults = []
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'integrated-results.json'), 'utf8')).slice(0, resume))
function b(...cmd) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true, JSON.stringify(result)); return result.data }
function ev(code) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true); return result.data.result }
const focus = `window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`
const snapshot = () => ev(`${focus}.client.snapshot`)
const wait = code => b('wait', '--fn', code)
const settled = () => wait(`${focus}?.client.confirmed && !${focus}.client.sending && !${focus}.preparing && !${focus}.dialogPending && !${focus}.recoveryFlow.busy`)
const state = status => { settled(); wait(`${focus}.client.snapshot.session?.status===${JSON.stringify(status)}`) }
const screen = name => b('screenshot', resolve(evidence, `${name}.png`))
const click = selector => {
 b('snapshot', '-i');
 if (selector.startsWith('[data-focus-')) { b('focus', selector); b('press', 'Enter'); return }
 b('scrollintoview', selector); ev('window.__stablePoint=null;true')
 wait(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return false;const r=el.getBoundingClientRect(),key=[r.left,r.top,r.width,r.height].join('|'),old=window.__stablePoint;window.__stablePoint=key;return old===key && el.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()`)
 b('snapshot', '-i'); b('click', selector)
}
const nav = path => { const page = path.startsWith('/projects') ? 'projects' : path.startsWith('/tasks') ? 'tasks' : path.split('/')[2] || 'home'; ev(`window.__oldShell=document.querySelector('.shell');Turbo.visit(${JSON.stringify(path)});true`); wait(`location.pathname===${JSON.stringify(path)} && document.querySelector('.shell')!==window.__oldShell && !document.documentElement.hasAttribute('aria-busy') && !document.documentElement.hasAttribute('data-turbo-preview') && document.querySelector('[data-controller=studio][data-ready=true]')?.dataset.page===${JSON.stringify(page)}`); settled() }
const read = () => { ev(`${focus}.client.read().then(()=>true)`); settled() }
function advance(seconds, mono = seconds) { const path = resolve(workspace, 'clock.json'), data = JSON.parse(readFileSync(path)); const fraction = data.wall.match(/\.(\d+)Z$/)?.[1] || "000"; data.wall = new Date(Date.parse(data.wall) + seconds * 1000).toISOString().replace(/\.\d{3}Z$/, "." + fraction + "Z"); data.monotonic += mono; writeFileSync(path, JSON.stringify(data)); read() }
const confirm = () => { click('[data-focus-target=dialogConfirm]'); wait('!document.querySelector(".focus-dialog").open'); settled() }
const cancel = () => { if (snapshot().session) { click('[data-focus-cancel]'); confirm(); assert.equal(snapshot().session, null) } }
const start = () => { click('[data-focus-primary]'); state('running') }
function sql(code) { return JSON.parse(execFileSync('bin/rails', ['runner', `require 'json'; raise 'Synthetic only' unless ActiveRecord::Base.connection_db_config.database == File.join(ENV.fetch('E2_WORKSPACE'),'synthetic.sqlite3'); ${code}`], { cwd: rails, env: { ...process.env, RAILS_ENV: 'development', E2_WORKSPACE: workspace, ACCIO_DATABASE_PATH: resolve(workspace, 'synthetic.sqlite3') }, encoding: 'utf8', timeout: 45000 }).trim()) }
const counts = () => sql('puts JSON.generate({sessions:FocusSession.count, commands:FocusCommand.count,versions:FocusSession.order(:id).pluck(:lock_version),occupants:FocusSession.occupying.count,completed:FocusSession.where(status:"completed").count})')
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'integrated-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
function appearance(key, value) { click('[data-open=customize]'); b('select', `#drawer-${key}`, value); wait('document.querySelector("[data-save-status]").hidden'); click('#customize [data-close]'); wait('!document.querySelector("#customize").open') }
function api(path, method, body) { return ev(`(async()=>{const r=await fetch(${JSON.stringify(path)},{method:${JSON.stringify(method)},headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(${JSON.stringify(body)})});return {status:r.status,data:await r.json()}})()`)}

// Advance only the private server fixture; deliberately do not observe the gap.
function clockOnly(seconds) {
 const path=resolve(workspace,'clock.json'),clock=JSON.parse(readFileSync(path)),fraction=clock.wall.match(/\.(\d+)Z$/)?.[1]||'000'
 clock.wall=new Date(Date.parse(clock.wall)+seconds*1000).toISOString().replace(/\.\d{3}Z$/,'.'+fraction+'Z');clock.monotonic+=seconds
 writeFileSync(path,JSON.stringify(clock))
}
const hide=()=>ev(`Object.defineProperty(document,'visibilityState',{configurable:true,get:()=> 'hidden'});document.dispatchEvent(new Event('visibilitychange'));true`)
const show=()=>{ev(`delete document.visibilityState;document.dispatchEvent(new Event('visibilitychange'));true`);settled()}
const route=uid=>'u-'+Buffer.from(uid).toString('base64url')
let background,historyBefore
try {
 b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i')
 if(ev('!!document.querySelector("#password")')){b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);click('.login-card [type=submit]')}
 wait('document.querySelector("[data-controller=focus]")');nav('/apps/focus');b('set','viewport','1440','1000');settled()
 scenario('Integrated authentication preset 25 global start and checkpoint',()=>{
  cancel();if(snapshot().preset_seconds!==1500){click('[data-focus-preset]');confirm()}
  historyBefore=counts().completed;start();advance(30);click('[data-focus-primary]');state('paused');assert.equal(snapshot().session.elapsed_seconds,30)
  click('[data-focus-primary]');state('running');background={uid:snapshot().session.uid,checkpoint:30}
  writeFileSync(resolve(workspace,'e3-integrated-context.json'),JSON.stringify({background,historyBefore}))
 })
 if(!background){({background,historyBefore}=JSON.parse(readFileSync(resolve(workspace,'e3-integrated-context.json'))))}
 scenario('Integrated Turbo reload personalization and second-tab concurrency',()=>{
  for(const path of ['/', '/apps/focus',`/projects/${ids.project}`]){nav(path);assert.equal(snapshot().session.uid,background.uid)}
  b('reload');settled();appearance('theme','light');click('[data-open=customize]');click('[data-wallpaper=ember]');wait('document.querySelector("[data-save-status]").hidden');b('press','Escape');assert.equal(snapshot().session.uid,background.uid)
  nav('/apps/focus');const s=snapshot().session,first=b('tab','list').tabs.find(t=>t.active).tabId
  b('tab','new',origin+'/apps/focus');settled();const second=b('tab','list').tabs.find(t=>t.active).tabId
  const responses=ev(`(async()=>{const body={version:${s.version},kind:'pause',parameters:{action:'pause'}};return await Promise.all(['a','b'].map(async suffix=>{const r=await fetch('/focus/${route(s.uid)}/commands',{method:'POST',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({...body,command_id:${JSON.stringify(runId)}+'-simultaneous-'+suffix})});return r.status}))})()`)
  assert.deepEqual(responses.sort(),[200,409]);read();state('paused');b('tab',first);read();state('paused');assert.equal(counts().occupants,1)
  b('tab','close',second);b('tab',first);click('[data-focus-primary]');state('running')
  screen('integrated-running-light')
 })
 scenario('Background equivalent 20 minutes preserves checkpoint and requires no automatic completion',()=>{
  b('record','start',resolve(evidence,'background-20-minutes.webm'));screen('background-step-1-running')
  const before=counts(),s=snapshot().session;hide();clockOnly(1200)
  // A blank tab represents other activity; no real OS application or clock is altered.
  const first=b('tab','list').tabs.find(t=>t.active).tabId;b('tab','new','about:blank');const other=b('tab','list').tabs.find(t=>t.active).tabId
  b('tab',first);show();state('running');const returned=snapshot()
  assert.equal(returned.session.uid,s.uid);assert.equal(returned.session.elapsed_seconds,30);assert.equal(returned.timing.nominal_seconds,1230);assert.equal(returned.timing.continuity,'unknown');assert.equal(returned.timing.estimate_valid,true);assert.deepEqual(counts(),before)
  screen('background-step-2-return');click('[data-focus-primary]');state('paused');assert.equal(snapshot().recovery.checkpoint_seconds,30);assert.equal(snapshot().recovery.candidate_seconds,1230)
  const receipt=snapshot().recovery.receipt_id;screen('background-step-3-recovery');writeFileSync(resolve(evidence,'axe-recovery.json'),JSON.stringify(b('a11y','--json'),null,2)+'\n');b('reload');settled();assert.equal(snapshot().recovery.receipt_id,receipt)
  assert.match(ev('document.querySelector("[data-focus-recovery]").textContent'),/Tempo confirmado: 00:30.*Estimativa disponível do servidor: 20:30/s)
  click('[data-focus-resolve=accept_estimate]');state('running');assert.equal(snapshot().session.elapsed_seconds,1230);assert.equal(snapshot().recovery,null);screen('background-step-4-accepted')
  assert.equal(snapshot().session.status,'running');assert.equal(snapshot().session.uid,s.uid);assert.equal(counts().completed,before.completed);assert.equal(counts().occupants,1);screen('background-step-5-resumed');b('record','stop')
  b('tab','close',other);b('tab',first)
  writeFileSync(resolve(evidence,'background-usability.json'),JSON.stringify({synthetic_hidden_seconds:1200,checkpoint_seconds:30,server_candidate_seconds:1230,remaining_after_accept_seconds:270,automatic_completion:false,occupants:1,decision_actions_after_return:['Conferir intervalo','Aceitar estimativa e continuar'],action_count:2,reload_added_only_for_recovery_verification:true,real_os_suspension_or_other_application_tested:false,thresholds_unchanged:[15,60,5]},null,2)+'\n')
 })
 scenario('Integrated explicit completion preserves one terminal history and preferences',()=>{
  for(const seconds of [60,60,60,60,30])advance(seconds)
  assert.equal(snapshot().session.status,'running');assert.equal(counts().completed,historyBefore);click('[data-focus-primary]');state('awaiting_confirmation');click('[data-focus-primary]');confirm();assert.equal(snapshot().session,null)
  const terminal=sql(`puts FocusSession.find_by!(uid:${JSON.stringify(background.uid)}).slice(:uid,:status,:elapsed_seconds,:duration_seconds,:completed_at,:ended_at).to_json`)
  assert.equal(terminal.status,'completed');assert.equal(terminal.elapsed_seconds,1500);assert.ok(terminal.completed_at);assert.equal(counts().completed,historyBefore+1)
  b('reload');settled();assert.equal(snapshot().session,null);assert.equal(ev('document.documentElement.dataset.theme'),'light')
  writeFileSync(resolve(evidence,'integrated-history.json'),JSON.stringify(terminal,null,2)+'\n')
 })
 scenario('Committed preset with lost response and unavailable GET retries exact CAS payload then reconciles 409',()=>{
  cancel();const before=snapshot(),appearanceBefore=ev(`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio').preferences`)
  ev(`window.__presetFetch=fetch;window.__presetAttempts=[];window.__presetStatuses=[];window.__presetOffline=true;window.fetch=async(url,options)=>{if(String(url)==='/focus/state'&&window.__presetOffline)throw new Error('GET offline sintético');if(String(url)==='/focus/preset'&&options?.method==='PATCH'){window.__presetAttempts.push(options.body);const r=await window.__presetFetch(url,options);window.__presetStatuses.push(r.status);if(window.__presetAttempts.length===1)throw new Error('Resposta perdida depois do commit sintético');return r}return window.__presetFetch(url,options)};true`)
  click('[data-focus-preset]');click('[data-focus-target=dialogConfirm]');wait(`!${focus}.client.sending&&!${focus}.dialogPending&&!document.querySelector('.focus-dialog').open`);assert.ok(ev(`${focus}.client.pending`));assert.match(ev(`${focus}.client.message`),/Operação incerta/);assert.equal(snapshot().preset_seconds,before.preset_seconds)
  screen('preset-lost-response');ev('window.__presetOffline=false;true');click('[data-focus-target=retry]');settled();const committed=snapshot();assert.notEqual(committed.preset_seconds,before.preset_seconds);assert.equal(committed.preference_version,before.preference_version+1);assert.match(ev(`${focus}.client.message`),/HTTP 409.*autoria.*não foi comprovada/);assert.equal(ev(`${focus}.client.pending`),null);assert.equal(snapshot().preset_seconds,committed.preset_seconds);assert.equal(snapshot().preference_version,committed.preference_version)
  assert.equal(ev('window.__presetAttempts[0]===window.__presetAttempts[1]'),true);assert.deepEqual(ev('window.__presetStatuses'),[200,409]);assert.deepEqual(ev(`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio').preferences`),appearanceBefore)
  writeFileSync(resolve(evidence,'preset-lost-response.json'),JSON.stringify({statuses:[200,409],same_payload:true,preset_seconds:committed.preset_seconds,root_version_increment:1,appearance_preserved:true,session_created:false},null,2)+'\n');ev('window.fetch=window.__presetFetch;true');b('reload');settled();if(snapshot().preset_seconds!==1500){click('[data-focus-preset]');confirm()}
 })
 scenario('Keeping checkpoint after 20-minute gap discards unconfirmed interval explicitly',()=>{
  cancel();start();advance(20);click('[data-focus-primary]');state('paused');click('[data-focus-primary]');state('running');hide();clockOnly(1200);show();click('[data-focus-primary]');state('paused')
  const old=snapshot();assert.equal(old.recovery.candidate_seconds,1220);click('[data-focus-resolve=keep_checkpoint]');state('paused');assert.equal(snapshot().session.elapsed_seconds,20);assert.equal(snapshot().recovery,null)
  const response=api('/focus/'+route(old.session.uid)+'/commands','POST',{command_id:runId+'-late-resolution',version:old.session.version,kind:'pause',parameters:{action:'resolve',recovery_id:old.recovery.receipt_id,decision:'accept_estimate'}})
  assert.equal(response.status,409);assert.equal(snapshot().session.elapsed_seconds,20);cancel()
 })
 scenario('Task completed during focus blocks resume without changing historical links',()=>{
  nav('/tasks');click('#task-focus-'+ids.personal);state('running');const s=snapshot().session
  sql(`t=Task.find_by!(uid:${JSON.stringify(s.task_uid)});t.update!(status:'completed',completed_at:Time.current);puts true.to_json`)
  nav('/apps/focus');click('[data-focus-primary]');state('paused');click('[data-focus-primary]');settled();assert.equal(snapshot().session.status,'paused');assert.match(ev(`${focus}.client.message`),/Reabra a tarefa/)
  assert.equal(snapshot().session.task_uid,s.task_uid);assert.equal(snapshot().session.project_uid,null);nav('/apps/focus');cancel()
  sql(`t=Task.find_by!(uid:${JSON.stringify(s.task_uid)});t.update!(status:'pending',completed_at:nil);puts true.to_json`)
 })
 scenario('Final synthetic SQLite integrity and read-only history inspection',()=>{
  const result=sql(`c=FocusSession.connection;puts({integrity:c.select_value('PRAGMA integrity_check'),foreign_keys:c.select_all('PRAGMA foreign_key_check').to_a,triggers:c.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger'"),occupants:FocusSession.occupying.count,history:FocusSession.group(:status).count}.to_json)`)
  assert.equal(result.integrity,'ok');assert.deepEqual(result.foreign_keys,[]);assert.equal(result.triggers,25);assert.equal(result.occupants,0)
  writeFileSync(resolve(evidence,'sqlite-integrity.json'),JSON.stringify(result,null,2)+'\n')
 })
 console.log(JSON.stringify({passed:results.length}))
} catch(error){console.error(error.stack);try{screen('failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')));b('record','stop')}catch{}process.exitCode=1}
