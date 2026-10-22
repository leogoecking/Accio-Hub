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
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, 'docs/assets/p1.2f/f1c/browser')); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-f1c-check', origin = 'http://127.0.0.1:3127'
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'preset-browser-results.json'), 'utf8')).slice(0, resume))
function b(...cmd) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true, JSON.stringify(result)); return result.data }
function ev(code) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true); return result.data.result }
const focus = `window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`
const snapshot = () => ev(`${focus}.client.snapshot`)
const wait = code => b('wait', '--fn', code)
const settled = () => wait(`${focus}?.client.confirmed && !${focus}.client.sending && !${focus}.preparing && !${focus}.dialogPending && !${focus}.recoveryFlow.busy && !${focus}.presetFlow.busy`)
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
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'preset-browser-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
function appearance(key, value) { click('[data-open=customize]'); b('select', `#drawer-${key}`, value); wait('document.querySelector("[data-save-status]").hidden'); click('#customize [data-close]'); wait('!document.querySelector("#customize").open') }
function api(path, method, body) { return ev(`(async()=>{const r=await fetch(${JSON.stringify(path)},{method:${JSON.stringify(method)},headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(${JSON.stringify(body)})});return {status:r.status,data:await r.json()}})()`)}
const studio=`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio')`
const message=()=>ev(`${focus}.client.message`)
const restore=()=>ev('if(window.__presetOriginal)fetch=window.__presetOriginal;true')
function resetPage(){restore();b('reload');settled();cancel();if(snapshot().preset_seconds!==1500){click('[data-focus-preset]');confirm()}ev(`clearInterval(${focus}.poll);true`)}
function patch(){click('[data-focus-preset]');confirm()}
function fault(mode,offline=false){ev(`window.__presetOriginal=fetch;window.__presetBodies=[];window.__presetStatuses=[];window.__readOffline=${offline};window.__presetOnce=true;window.fetch=async(url,o)=>{
 if(String(url)==='/focus/state'&&window.__readOffline)throw new Error('GET indisponível sintético');
 if(String(url)==='/focus/preset'&&o?.method==='PATCH'){
  window.__presetBodies.push(o.body);
  if(window.__presetOnce){window.__presetOnce=false;
   if(${JSON.stringify(mode)}==='before')throw new Error('Resposta perdida antes de gravar');
   if(${JSON.stringify(mode)}==='timeout')return new Promise((resolve,reject)=>o.signal.addEventListener('abort',()=>reject(new Error('Timeout sintético'))));
   if(${JSON.stringify(mode)}==='503')return new Response(JSON.stringify({message:'SQLite ocupado sintético'}),{status:503,headers:{'Content-Type':'application/json'}});
   const r=await window.__presetOriginal(url,o);window.__presetStatuses.push(r.status);throw new Error('Resposta perdida após commit');
  }
  const r=await window.__presetOriginal(url,o);window.__presetStatuses.push(r.status);return r;
 }return window.__presetOriginal(url,o)};true`)}
function uncertainPatch(){click('[data-focus-preset]');click('[data-focus-target=dialogConfirm]');wait(`!${focus}.client.sending && !${focus}.dialogPending && !document.querySelector('.focus-dialog').open`);assert.ok(ev(`${focus}.client.pending`));assert.equal(ev(`${focus}.client.confirmed`),false)}
function holdPatch(){ev(`window.__presetOriginal=fetch;window.__presetBodies=[];window.fetch=(url,o)=>{if(String(url)==='/focus/preset'&&o?.method==='PATCH'){window.__presetBodies.push(o.body);window.__held=true;return new Promise(resolve=>window.__release=()=>resolve(window.__presetOriginal(url,o)))}return window.__presetOriginal(url,o)};true`);click('[data-focus-preset]');click('[data-focus-target=dialogConfirm]');wait('window.__held===true')}
function releasePatch(){ev('window.__release();true');wait('!document.querySelector(".focus-dialog").open');settled()}
function otherTab(operation){const first=b('tab','list').tabs.find(t=>t.active).tabId;b('tab','new',origin+'/apps/focus');settled();const second=b('tab','list').tabs.find(t=>t.active).tabId;operation();b('tab','close',second);b('tab',first)}
try{
 b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i')
 if(ev('!!document.querySelector("#password")')){b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);click('.login-card [type=submit]')}
 wait('document.querySelector("[data-controller=focus]")');nav('/apps/focus');b('set','viewport','1440','1000');settled()
 scenario('A: Normal PATCH acknowledges preset 45 and leaves focus history and appearance unchanged',()=>{
  resetPage();const before=counts(),prefs=ev(`${studio}.preferences`);patch();assert.equal(snapshot().preset_seconds,2700);assert.match(message(),/Resposta de sucesso confirmada.*45 min/);assert.deepEqual(counts(),before);assert.deepEqual(ev(`${studio}.preferences`),prefs);screen('confirmed-success')
 })
 scenario('B/E: Lost response before write confirms current 25 and requires a new explicit choice',()=>{
  resetPage();const before=counts();fault('before');patch();assert.equal(snapshot().preset_seconds,1500);assert.match(message(),/25 min.*Difere do solicitado \(45 min\).*nova escolha explícita/);assert.equal(ev(`${focus}.client.pending`),null);assert.equal(ev('window.__presetBodies.length'),1);assert.deepEqual(counts(),before);screen('lost-before-different');restore()
 })
 scenario('B/D: Lost response after commit confirms current 45 without asserting original authorship',()=>{
  resetPage();const before=counts(),appearanceVersion=ev(`${studio}.version`);fault('after');patch();assert.equal(snapshot().preset_seconds,2700);assert.match(message(),/45 min.*autoria da alteração não foi comprovada/);assert.doesNotMatch(message(),/sucesso confirmada/);assert.equal(ev(`${focus}.client.pending`),null);assert.equal(ev(`${studio}.version`),appearanceVersion);assert.deepEqual(counts(),before);screen('lost-after-equal-unproven');restore()
 })
 scenario('C/F: Lost committed response and unavailable GET preserve envelope; explicit retry gets 409',()=>{
  resetPage();fault('after',true);uncertainPatch();const envelope=ev(`JSON.stringify(${focus}.client.pending.body)`);assert.match(message(),/Operação incerta/);screen('offline-uncertain');ev('window.__readOffline=false;true');click('[data-focus-target=retry]');settled();assert.match(message(),/HTTP 409.*45 min.*autoria.*não foi comprovada/);assert.deepEqual(ev('window.__presetStatuses'),[200,409]);assert.equal(ev('window.__presetBodies[0]===window.__presetBodies[1]'),true);assert.equal(ev(`${focus}.client.pending`),null);assert.equal(ev('window.__presetBodies[0]'),envelope);screen('retry-409-reconciled');assert.equal(ev('document.activeElement.matches("[data-focus-primary],[data-focus-preset],[data-focus-target=retry]") && document.activeElement.getClientRects().length>0'),true);restore()
 })
 scenario('F: Read reconnect alone reconciles pending request with no automatic PATCH retry',()=>{
  resetPage();fault('after',true);uncertainPatch();ev('window.__readOffline=false;true');read();assert.equal(ev('window.__presetBodies.length'),1);assert.match(message(),/45 min.*autoria.*não foi comprovada/);assert.equal(ev(`${focus}.client.pending`),null);restore()
 })
 for(const mode of ['503','timeout'])scenario(`Uncertain ${mode} preserves stable PATCH and offline read until explicit retry`,()=>{
  resetPage();fault(mode,true);uncertainPatch();const body=ev('window.__presetBodies[0]');assert.match(message(),/Operação incerta/);ev('window.__readOffline=false;true');click('[data-focus-target=retry]');settled();assert.equal(ev('window.__presetBodies[1]'),body);assert.equal(snapshot().preset_seconds,2700);assert.match(message(),/sucesso confirmada/);restore()
 })
 scenario('Two tabs requesting same preset: first stale PATCH receives 409 and cannot claim authorship',()=>{
  resetPage();const before=counts();holdPatch();otherTab(()=>{patch();assert.equal(snapshot().preset_seconds,2700)});releasePatch();assert.match(message(),/HTTP 409.*45 min.*autoria.*não foi comprovada/);assert.equal(ev('window.__presetBodies.length'),1);assert.deepEqual(counts(),before);screen('two-tabs-same');restore()
 })
 for(const field of ['theme','wallpaper','dock','widgets','filters'])scenario(`G: Preset conflict preserves concurrent ${field} change in aggregate C`,()=>{
  resetPage();holdPatch();let expectedAppearance;otherTab(()=>{
   const current=snapshot(),appearance=ev(`${studio}.preferences`);let result
   if(field==='filters')result=api('/projects/filters','PATCH',{version:current.preference_version,filters:{project_library_favorites_only:true}})
   else{if(field==='theme')appearance.theme=appearance.theme==='dark'?'light':'dark';if(field==='wallpaper')appearance.wallpaper='ember';if(field==='dock')appearance.dockOrder.reverse();if(field==='widgets')appearance.widgets.reverse();result=api('/appearance','PATCH',{version:current.preference_version,appearance})}
   assert.equal(result.status,200);expectedAppearance=result.data.appearance
  });releasePatch();assert.equal(snapshot().preset_seconds,1500);assert.match(message(),/HTTP 409.*25 min.*nova escolha explícita/);assert.equal(ev('window.__presetBodies.length'),1);screen('concurrent-'+field);restore();b('reload');settled();assert.deepEqual(ev(`${studio}.preferences`),expectedAppearance);if(field==='filters')assert.equal(sql('puts UserPreference.first.project_library_favorites_only.to_json'),true)
 })
 scenario('Pending local appearance draft and its version survive acknowledged preset change',()=>{
  resetPage();const version=ev(`${studio}.version`);ev(`${studio}.preferences.theme=${studio}.preferences.theme==='dark'?'light':'dark';true`);const draft=ev(`${studio}.preferences`);patch();assert.match(message(),/sucesso confirmada/);assert.equal(ev(`${studio}.version`),version);assert.deepEqual(ev(`${studio}.preferences`),draft);b('reload');settled()
 })
 scenario('Turbo reconnect keeps envelope but reads reconcile it without another PATCH',()=>{
  resetPage();fault('after',true);uncertainPatch();ev('window.__readOffline=false;true');nav('/');assert.match(message(),/45 min.*autoria.*não foi comprovada/);assert.equal(ev('window.__presetBodies.length'),1);restore();nav('/apps/focus')
 })
 scenario('Reload with lost response reads confirmed value and never retries the old PATCH',()=>{
  resetPage();fault('after',true);uncertainPatch();b('reload');settled();assert.equal(snapshot().preset_seconds,2700);assert.equal(ev(`${focus}.client.pending==null`),true);assert.equal(ev(`${focus}.presetFlow.operation==null`),true)
 })
 scenario('Running and paused duration survive preset clicks and theme changes; ready reset stays explicit',()=>{
  resetPage();start();const original=snapshot().session;click('[data-focus-preset]');assert.match(message(),/Encerre ou cancele/);assert.equal(snapshot().session.duration_seconds,1500);click('[data-focus-primary]');state('paused');click('[data-focus-preset]');assert.match(message(),/Encerre ou cancele/);appearance('theme','light');assert.equal(snapshot().session.uid,original.uid);assert.equal(snapshot().session.duration_seconds,1500);cancel();click('[data-focus-primary]');state('running');click('[data-focus-reset]');confirm();state('ready');const ready=snapshot().session;click('[data-focus-preset]');b('press','Escape');assert.equal(snapshot().session.uid,ready.uid);assert.equal(snapshot().session.duration_seconds,ready.duration_seconds);cancel()
 })
 scenario('Feedback wraps at 320 and 390 in both themes with accessible status and keyboard focus',()=>{
  resetPage();for(const theme of ['light','dark']){resetPage();appearance('theme',theme);for(const width of [320,390]){b('set','viewport',String(width),'900');resetPage();fault('after');patch();assert.match(message(),/autoria.*não foi comprovada/);assert.equal(ev('document.documentElement.scrollWidth<=innerWidth'),true);assert.equal(ev('document.querySelector("[data-focus-target=transport]").getAttribute("role")'),'status');assert.equal(ev('document.activeElement.hasAttribute("data-focus-preset")'),true);screen(`feedback-${theme}-${width}`);writeFileSync(resolve(evidence,`axe-feedback-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2)+'\n');restore()}}
 })
 console.log(JSON.stringify({passed:results.length}))
}catch(error){console.error(error.stack);try{screen('failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')))}catch{}process.exitCode=1}
