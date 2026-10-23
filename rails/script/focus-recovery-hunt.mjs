// F1b adversarial browser verification. Synthetic clock and database only.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const root = resolve(import.meta.dirname, '../..'), rails = resolve(root, 'rails')
const workspace = readFileSync(resolve(rails, 'tmp/p12e2-workspace'), 'utf8').trim()
assert.ok(workspace.startsWith(resolve(rails, 'tmp/p12e2-browser-')))
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json'), 'utf8'))
const ids = JSON.parse(readFileSync(resolve(workspace, 'state.json'), 'utf8'))
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, 'docs/assets/p1.2f/f1b/hunt')); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-f1b-check', origin = 'http://127.0.0.1:3127'
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'f1b-hunt-results.json'), 'utf8')).slice(0, resume))
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
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'f1b-hunt-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
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
 scenario('Turbo navigation while resolve response is held preserves exactly one owned continuation',()=>{
  const initial=recovery();holdResolve();const pending=ev(`JSON.stringify(${focus}.client.pending.body)`)
  ev(`window.__oldShell=document.querySelector('.shell');Turbo.visit('/tasks');true`)
  wait(`location.pathname==='/tasks'&&document.querySelector('.shell')!==window.__oldShell&&document.querySelector('[data-controller=studio][data-ready=true]')?.dataset.page==='tasks'`)
  assert.equal(ev(`JSON.stringify(${focus}.client.pending.body)`),pending);assert.equal(focusBodies().length,1);releaseResolve();assert.equal(snapshot().session.status,'running');assert.equal(snapshot().session.uid,initial.session.uid);assert.deepEqual(focusBodies().map(x=>x.parameters.action),['resolve','resume']);screen('turbo-owned-continuation');restoreFetch();nav('/apps/focus')
 })
 scenario('Incompatible HTTP 200 receipt cannot be mistaken for success despite a matching GET',()=>{
  const initial=recovery(),before=counts();ev(`window.__f1Fetch=fetch;window.__f1Bodies=[];window.__badReceipt=true;window.fetch=async(url,o)=>{if(String(url).includes('/commands')&&o?.method==='POST'){const body=JSON.parse(o.body);window.__f1Bodies.push(body);const r=await window.__f1Fetch(url,o);if(body.parameters.action==='resolve'&&window.__badReceipt){window.__badReceipt=false;const data=await r.json();data.result.resolved_recovery_id+=1;return new Response(JSON.stringify(data),{status:200,headers:{'Content-Type':'application/json'}})}return r}return window.__f1Fetch(url,o)};true`)
  click('[data-focus-resolve=accept_estimate]');settled();assert.equal(snapshot().session.status,'paused');assert.equal(snapshot().session.elapsed_seconds,initial.recovery.candidate_seconds);assert.equal(focusBodies().length,1);assert.ok(ev(`${focus}.client.pending`));assert.match(ev(`${focus}.client.message`),/Resposta desta recuperação não confirmada/);screen('bad-receipt-preserved');click('[data-focus-target=retry]');state('running');assert.deepEqual(focusBodies()[0],focusBodies()[1]);assert.equal(counts().commands,before.commands+2);restoreFetch()
 })
 scenario('Escape during recovery does not cancel the timer or trigger an extra command',()=>{
  const initial=recovery();holdResolve();const before=counts();b('press','Escape');assert.deepEqual(counts(),before);assert.equal(focusBodies().length,1);releaseResolve();assert.equal(snapshot().session.status,'running');assert.equal(snapshot().session.uid,initial.session.uid);assert.equal(counts().completed,before.completed);assert.equal(counts().occupants,1);assert.equal(focusBodies().length,2);restoreFetch()
 })
 console.log(JSON.stringify({passed:results.length,classification:'Expected behavior in all explored cases'}))
}catch(error){console.error(error.stack);try{screen('failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')))}catch{}process.exitCode=1}
