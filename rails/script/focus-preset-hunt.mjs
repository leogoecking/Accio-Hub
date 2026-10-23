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
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, 'docs/assets/p1.2f/f1c/hunt')); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-f1c-check', origin = 'http://127.0.0.1:3127'
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'preset-hunt-results.json'), 'utf8')).slice(0, resume))
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
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'preset-hunt-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
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
 scenario('Incompatible HTTP 200 acknowledgement and matching GET never prove authorship',()=>{
  resetPage();ev(`window.__presetOriginal=fetch;window.__presetBodies=[];window.fetch=async(url,o)=>{const r=await window.__presetOriginal(url,o);if(String(url)==='/focus/preset'&&o?.method==='PATCH'){window.__presetBodies.push(o.body);const data=await r.json();data.version+=20;return new Response(JSON.stringify(data),{status:200,headers:{'Content-Type':'application/json'}})}return r};true`);patch();assert.match(message(),/45 min.*autoria.*não foi comprovada/);assert.doesNotMatch(message(),/sucesso confirmada/);assert.equal(ev('window.__presetBodies.length'),1);screen('incompatible-ack');restore()
 })
 scenario('Appearance edit after uncertain preset keeps draft and requires explicit C conflict resolution',()=>{
  resetPage();const savedTheme=ev(`${studio}.preferences.theme`);fault('after');patch();restore();const value=savedTheme==='light'?'dark':'light',old=ev(`${studio}.version`);click('[data-open=customize]');b('select','#drawer-theme',value);wait(`${studio}.failed&&${studio}.blocked`);assert.equal(ev(`${studio}.preferences.theme`),value);assert.equal(ev(`${studio}.version`),old);assert.equal(sql('puts UserPreference.first.theme.to_json'),savedTheme);assert.match(ev('document.querySelector("[data-save-message]").textContent'),/Outra aba salvou/);screen('appearance-draft-preserved');click('[data-recovery=apply]');wait('document.querySelector("[data-save-status]").hidden');assert.equal(sql('puts UserPreference.first.theme.to_json'),value);click('#customize [data-close]');read();assert.equal(snapshot().preset_seconds,2700)
 })
 scenario('Turbo navigation during pending PATCH uses shared coordinator without stale controller errors or duplicate write',()=>{
  resetPage();const before=counts();b('record','start',resolve(evidence,'turbo-pending.webm'));screen('turbo-before');holdPatch();screen('turbo-held');ev(`window.__oldShell=document.querySelector('.shell');Turbo.visit('/');true`);wait('location.pathname==="/"&&document.querySelector(".shell")!==window.__oldShell&&document.querySelector("[data-controller=studio][data-ready=true]")?.dataset.page==="home"');screen('turbo-new-page');ev('window.__release();true');settled();assert.equal(snapshot().preset_seconds,2700);assert.match(message(),/sucesso confirmada/);assert.equal(ev('window.__presetBodies.length'),1);assert.deepEqual(counts(),before);screen('turbo-acknowledged');b('record','stop');restore();nav('/apps/focus')
 })
 console.log(JSON.stringify({passed:results.length,classification:'Expected behavior in explored cases'}))
}catch(error){console.error(error.stack);try{b('record','stop');screen('failure-'+Date.now());console.error(JSON.stringify(b('errors')))}catch{}process.exitCode=1}
