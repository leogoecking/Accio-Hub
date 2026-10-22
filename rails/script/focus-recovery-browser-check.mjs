// E3 integrated verification only. No application clock or data contract is changed.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const root = resolve(import.meta.dirname, '../..'), rails = resolve(root, 'rails')
const workspace = readFileSync(resolve(rails, 'tmp/p12e2-workspace'), 'utf8').trim()
assert.ok(workspace.startsWith(resolve(rails, 'tmp/p12e2-browser-')))
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json'), 'utf8'))
const ids = JSON.parse(readFileSync(resolve(workspace, 'state.json'), 'utf8'))
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, 'docs/assets/p1.2f/f1b/browser')); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-f1b-check', origin = 'http://127.0.0.1:3127'
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'f1b-browser-results.json'), 'utf8')).slice(0, resume))
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
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'f1b-browser-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
function appearance(key, value) { click('[data-open=customize]'); b('select', `#drawer-${key}`, value); wait('document.querySelector("[data-save-status]").hidden'); click('#customize [data-close]'); wait('!document.querySelector("#customize").open') }
function api(path, method, body) { return ev(`(async()=>{const r=await fetch(${JSON.stringify(path)},{method:${JSON.stringify(method)},headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(${JSON.stringify(body)})});return {status:r.status,data:await r.json()}})()`)}

const focusBodies=()=>ev('window.__f1Bodies||[]')
const restoreFetch=()=>ev('if(window.__f1Fetch)window.fetch=window.__f1Fetch;true')
function recovery({context=null,integral=false,invalid=false}={}) {
 nav('/apps/focus');cancel()
 if(context==='project'){nav(`/projects/${ids.project}`);start();nav('/apps/focus')}
 else if(context==='task'){nav('/tasks');click('#task-focus-'+ids.task);state('running');nav('/apps/focus')}
 else start()
 advance(30);click('[data-focus-primary]');state('paused');click('[data-focus-primary]');state('running')
 advance(integral?1800:1200,invalid?0:integral?1800:1200);click('[data-focus-primary]');state('paused');return snapshot()
}
function recordWrites() {
 ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.fetch=(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST')window.__f1Bodies.push(JSON.parse(o.body));return window.__f1Fetch(url,o)};true`)
}
function holdResolve() {
 ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__heldResolve=null;window.fetch=async(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){window.__f1Bodies.push(JSON.parse(o.body));if(JSON.parse(o.body).parameters.action==='resolve'){const r=await window.__f1Fetch(url,o);window.__heldResolve=true;return new Promise(resolve=>window.__releaseResolve=()=>resolve(r))}}return window.__f1Fetch(url,o)};true`)
 click('[data-focus-resolve=accept_estimate]');wait('window.__heldResolve===true')
}
function releaseResolve(){ev('window.__releaseResolve();true');settled()}
try{
 b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i')
 if(ev('!!document.querySelector("#password")')){b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);click('.login-card [type=submit]')}
 wait('document.querySelector("[data-controller=focus]")');nav('/apps/focus');b('set','viewport','1440','1000');settled()
 scenario('20-minute absence recovers in two human actions with explicit accepted time and confirmed resume',()=>{
  cancel();start();advance(30);click('[data-focus-primary]');state('paused');click('[data-focus-primary]');state('running');const original=snapshot().session,before=counts()
  b('record','start',resolve(evidence,'two-actions-20min.webm'));screen('20min-before')
  ev(`Object.defineProperty(document,'visibilityState',{configurable:true,get:()=> 'hidden'});document.dispatchEvent(new Event('visibilitychange'));true`)
  const clockPath=resolve(workspace,'clock.json'),clock=JSON.parse(readFileSync(clockPath)),fraction=clock.wall.match(/\.(\d+)Z$/)?.[1]||'000';clock.wall=new Date(Date.parse(clock.wall)+1200000).toISOString().replace(/\.\d{3}Z$/,'.'+fraction+'Z');clock.monotonic+=1200;writeFileSync(clockPath,JSON.stringify(clock))
  ev(`delete document.visibilityState;document.dispatchEvent(new Event('visibilitychange'));true`);settled();assert.deepEqual(counts(),before);assert.equal(snapshot().session.elapsed_seconds,30);assert.equal(snapshot().timing.nominal_seconds,1230);screen('20min-return')
  click('[data-focus-primary]');state('paused');screen('20min-conferred');assert.equal(snapshot().recovery.candidate_seconds,1230);assert.match(ev('document.querySelector("[data-focus-checkpoint]").textContent'),/Tempo confirmado: 00:30/)
  recordWrites();click('[data-focus-resolve=accept_estimate]');state('running');assert.equal(snapshot().session.uid,original.uid);assert.equal(snapshot().session.elapsed_seconds,1230);assert.equal(counts().completed,before.completed);assert.equal(counts().occupants,1)
  const bodies=focusBodies();assert.deepEqual(bodies.map(x=>x.parameters.action),['resolve','resume']);assert.equal(bodies[1].version,bodies[0].version+1);assert.notEqual(bodies[0].command_id,bodies[1].command_id);assert.match(ev(`${focus}.client.message`),/Estimativa aceita.*Retomada confirmada/)
  assert.equal(ev('document.activeElement.hasAttribute("data-focus-primary")'),true);screen('20min-accepted-running');b('record','stop');restoreFetch()
  writeFileSync(resolve(evidence,'two-actions.json'),JSON.stringify({human_actions:['Conferir intervalo','Aceitar estimativa e continuar'],count:2,checkpoint:30,server_candidate:1230,remaining:270,same_uid:true,completed_automatically:false,commands:bodies},null,2)+'\n')
 })
 scenario('Reload while pending recovery does not accept or resume until one explicit action',()=>{
  const old=recovery(),before=counts();b('reload');settled();assert.deepEqual(counts(),before);assert.equal(snapshot().recovery.receipt_id,old.recovery.receipt_id);assert.equal(snapshot().session.status,'paused');click('[data-focus-resolve=accept_estimate]');state('running')
 })
 scenario('Integral estimate goes only to awaiting confirmation; invalid estimate cannot be accepted',()=>{
  recovery({integral:true});const before=counts();recordWrites();click('[data-focus-resolve=accept_estimate]');state('awaiting_confirmation');assert.deepEqual(focusBodies().map(x=>x.parameters.action),['resolve']);assert.equal(counts().completed,before.completed);screen('integral-review-required');restoreFetch()
  const invalid=recovery({invalid:true});assert.equal(invalid.recovery.candidate_seconds,null);assert.equal(ev('document.querySelector("[data-focus-resolve=accept_estimate]").disabled'),true);screen('invalid-estimate');click('[data-focus-resolve=keep_checkpoint]');state('paused');assert.equal(snapshot().session.elapsed_seconds,30)
 })
 scenario('Lost resolve response cannot infer acknowledgement from similar GET; explicit replay resumes once',()=>{
  const initial=recovery();const before=counts()
  ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__lost=false;window.fetch=async(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){const body=JSON.parse(o.body);window.__f1Bodies.push(body);const r=await window.__f1Fetch(url,o);if(body.parameters.action==='resolve'&&!window.__lost){window.__lost=true;throw new Error('Lost resolve after commit')}return r}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');settled();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.equal(focusBodies().length,1);assert.ok(ev(`${focus}.client.pending`));read();assert.equal(focusBodies().length,1);screen('lost-resolve-needs-replay')
  click('[data-focus-target=retry]');state('running');const bodies=focusBodies();assert.deepEqual(bodies[0],bodies[1]);assert.equal(bodies[2].parameters.action,'resume');assert.equal(counts().commands,before.commands+2);restoreFetch()
 })
 scenario('503 after resolve preserves paused accepted checkpoint and exact resume retry',()=>{
  const initial=recovery();ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__failed=false;window.fetch=(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){const body=JSON.parse(o.body);window.__f1Bodies.push(body);if(body.parameters.action==='resume'&&!window.__failed){window.__failed=true;return Promise.resolve(new Response(JSON.stringify({error:'database_busy',message:'Armazenamento ocupado sintético'}),{status:503,headers:{'Content-Type':'application/json'}}))}}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');settled();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.match(ev(`${focus}.client.message`),/Estimativa aceita.*ainda não confirmada/);screen('resume-503-paused');read();assert.equal(focusBodies().length,2)
  click('[data-focus-target=retry]');state('running');assert.deepEqual(focusBodies()[1],focusBodies()[2]);assert.equal(focusBodies().filter(x=>x.parameters.action==='resolve').length,1);restoreFetch()
 })
 scenario('Actual 15-second transport timeout after resolve preserves accepted time and retries resume only',()=>{
  const initial=recovery();ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__failed=false;window.fetch=(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){const body=JSON.parse(o.body);window.__f1Bodies.push(body);if(body.parameters.action==='resume'&&!window.__failed){window.__failed=true;return new Promise((resolve,reject)=>o.signal.addEventListener('abort',()=>reject(new Error('Synthetic timeout'))))}}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');settled();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.match(ev(`${focus}.client.message`),/Estimativa aceita.*ainda não confirmada/);assert.ok(ev(`${focus}.client.pending`));screen('resume-timeout-paused');click('[data-focus-target=retry]');state('running');assert.deepEqual(focusBodies()[1],focusBodies()[2]);restoreFetch()
 })
 scenario('Lost resume response acknowledges by replay without duplicating receipt or issuing resolve again',()=>{
  recovery();const before=counts();ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__failed=false;window.fetch=async(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){const body=JSON.parse(o.body);window.__f1Bodies.push(body);const r=await window.__f1Fetch(url,o);if(body.parameters.action==='resume'&&!window.__failed){window.__failed=true;throw new Error('Lost resume after commit')}return r}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');settled();assert.equal(snapshot().session.status,'running');assert.match(ev(`${focus}.client.message`),/ainda não confirmada/);assert.ok(ev(`${focus}.client.pending`));click('[data-focus-target=retry]');state('running');assert.deepEqual(focusBodies()[1],focusBodies()[2]);assert.equal(counts().commands,before.commands+2);assert.equal(counts().sessions,before.sessions);restoreFetch()
 })
 scenario('Second tab changes session after resolve: first tab stops rather than borrowing its version',()=>{
  recovery();const first=b('tab','list').tabs.find(t=>t.active).tabId;holdResolve();b('tab','new',origin+'/apps/focus');settled();const second=b('tab','list').tabs.find(t=>t.active).tabId
  click('[data-focus-primary]');state('running');click('[data-focus-primary]');state('paused');const otherVersion=snapshot().session.version
  b('tab',first);releaseResolve();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.version,otherVersion);assert.deepEqual(focusBodies().map(x=>x.parameters.action),['resolve']);assert.match(ev(`${focus}.client.message`),/estado mudou em outra aba/);screen('other-tab-continuation-stopped');restoreFetch();b('tab','close',second);b('tab',first)
 })
 scenario('Archived project between transactions accepts checkpoint but backend rejects resume',()=>{
  const initial=recovery({context:'project'});holdResolve();const version=sql("puts Project.find_by!(uid:'42/á?%#项目').lock_version.to_json")
  assert.equal(api(`/projects/${ids.project}/command`,'PATCH',{operation:'archive',version}).status,200);releaseResolve();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.match(ev(`${focus}.client.message`),/Estimativa aceita.*rejeitada.*arquivado/);assert.equal(ev(`${focus}.client.pending`),null);screen('archived-after-accept');restoreFetch()
  const current=sql("puts Project.find_by!(uid:'42/á?%#项目').lock_version.to_json");assert.equal(api(`/projects/${ids.project}/command`,'PATCH',{operation:'restore',version:current}).status,200)
 })
 scenario('Completed task between transactions remains completed and prevents resume',()=>{
  const initial=recovery({context:'task'});holdResolve();sql("t=Task.find_by!(uid:'task/á%?#');t.update!(status:'completed',completed_at:Time.current);puts true.to_json");releaseResolve();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.match(ev(`${focus}.client.message`),/Estimativa aceita.*rejeitada.*Reabra/);assert.equal(sql("puts Task.find_by!(uid:'task/á%?#').status.to_json"),'completed');restoreFetch();cancel();sql("t=Task.find_by!(uid:'task/á%?#');t.update!(status:'pending',completed_at:nil);puts true.to_json")
 })
 scenario('Moving task to editable project preserves historical focus context and allows validated resume',()=>{
  const initial=recovery({context:'task'});holdResolve();sql(`t=Task.find_by!(uid:'task/á%?#');t.update!(project:User.first.projects.find_by!(uid:PublicUid.decode(${JSON.stringify(ids.other)})));puts true.to_json`);releaseResolve();state('running');assert.equal(snapshot().session.project_uid,initial.session.project_uid);assert.equal(snapshot().session.task_uid,initial.session.task_uid);assert.equal(sql("puts Task.find_by!(uid:'task/á%?#').status.to_json"),'pending');restoreFetch();cancel();sql("t=Task.find_by!(uid:'task/á%?#');t.update!(project:User.first.projects.find_by!(uid:'42/á?%#项目'));puts true.to_json")
 })
 scenario('Reload between accepted resolve and unsent resume discards continuation without automatic retry',()=>{
  const initial=recovery();ev(`window.__f1Fetch=fetch;window.__resumeHeld=false;window.fetch=(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'&&JSON.parse(o.body).parameters.action==='resume'){window.__resumeHeld=true;return new Promise((resolve,reject)=>o.signal.addEventListener('abort',()=>reject(new Error('Document discarded'))))}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');wait('window.__resumeHeld');const before=counts();b('reload');settled();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.equal(ev(`${focus}.client.pending||null`),null);assert.equal(ev(`${focus}.recoveryFlow.operation||null`),null);assert.deepEqual(counts(),before);screen('reload-does-not-resume')
 })
 const geometry=[]
 for(const theme of ['dark','light']){
  scenario(`Recovery layout keyboard and accessibility ${theme} at five widths`,()=>{
   recovery();appearance('theme',theme)
   for(const width of [320,390,768,1440,1920]){
    b('set','viewport',String(width),'1000')
    for(const[name,path]of[['dashboard','/'],['focus','/apps/focus'],['project',`/projects/${ids.project}`]]){
     nav(path);const result=ev(`(()=>{const d=document.querySelector('.dial'),r=d.getBoundingClientRect(),m=document.querySelector('main');return{circle:[r.width,r.height],body:document.body.scrollWidth,viewport:innerWidth,main:m.scrollWidth,client:m.clientWidth,background:getComputedStyle(d.closest('.panel-focus')).backgroundImage}})()`)
     assert.deepEqual(result.circle,[170,170]);assert.ok(result.body<=width+1&&result.main<=result.client+1);if(theme==='light')assert.match(result.background,/238, 232, 251/);geometry.push({theme,width,name,...result});screen(`recovery-${name}-${theme}-${width}`)
     if(name==='focus')writeFileSync(resolve(evidence,`axe-recovery-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2)+'\n')
    }
   }
   nav('/apps/focus');b('set','viewport','1440','1000');click('[data-focus-cancel]');assert.equal(ev('document.activeElement.hasAttribute("autofocus")'),true);b('focus','[data-focus-target=dialogConfirm]');b('press','Tab');assert.equal(ev('document.activeElement.getAttribute("aria-label")'),'Fechar diálogo do Pomodoro');b('press','Shift+Tab');assert.equal(ev('document.activeElement.dataset.focusTarget'),'dialogConfirm');b('press','Escape');assert.equal(ev('document.activeElement.hasAttribute("data-focus-cancel")'),true)
  })
 }
 writeFileSync(resolve(evidence,'geometry.json'),JSON.stringify(geometry,null,2)+'\n')
 console.log(JSON.stringify({passed:results.length}))
}catch(error){console.error(error.stack);try{screen('failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')));b('record','stop')}catch{}process.exitCode=1}
