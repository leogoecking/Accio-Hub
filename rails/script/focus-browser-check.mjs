// UI QA with agent-browser. Synthetic-only clock lives in the private server workspace.
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
const evidence = resolve(root, 'docs/assets/p1.2e2'); mkdirSync(evidence, { recursive: true })
const session = process.env.ACCIO_QA_SESSION || 'accio-p12e2-check', origin = 'http://127.0.0.1:3127'
const geometryResults = []
const results = [], resume = Number(process.env.ACCIO_QA_RESUME || 0); let index = 0
if (resume) results.push(...JSON.parse(readFileSync(resolve(evidence, 'browser-results.json'), 'utf8')).slice(0, resume))
function b(...cmd) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true, JSON.stringify(result)); return result.data }
function ev(code) { const result = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(result.success, true); return result.data.result }
const focus = `window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`
const snapshot = () => ev(`${focus}.client.snapshot`)
const wait = code => b('wait', '--fn', code)
const settled = () => wait(`${focus}?.client.confirmed && !${focus}.client.sending && !${focus}.preparing && !${focus}.dialogPending`)
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
function scenario(name, test) { if (index++ < resume) return; test(); const errors = b('errors'); assert.ok(!errors?.errors?.length, JSON.stringify(errors)); results.push({ name, result: 'PASS' }); writeFileSync(resolve(evidence, 'browser-results.json'), JSON.stringify(results, null, 2) + '\n'); console.log('PASS ' + name) }
function appearance(key, value) { click('[data-open=customize]'); b('select', `#drawer-${key}`, value); wait('document.querySelector("[data-save-status]").hidden'); b('press', 'Escape') }
function api(path, method, body) { return ev(`(async()=>{const r=await fetch(${JSON.stringify(path)},{method:${JSON.stringify(method)},headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(${JSON.stringify(body)})});return {status:r.status,data:await r.json()}})()`)}
try {
 b('--args', '--no-sandbox', 'open', origin + '/session/new'); b('snapshot', '-i')
 if (ev('!!document.querySelector("#password")')) { b('fill', '#email_address', credentials.email); ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`); click('.login-card [type=submit]') }
 wait('document.querySelector("[data-controller=focus]")'); nav('/apps/focus'); settled(); b('set', 'viewport', '1440', '1000')
 scenario('Read-only navigation and reload never create or start a session', () => { cancel(); if (ev(`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio').preferences.musicExpanded`)) { click('[data-music-expand]'); wait('document.querySelector("[data-save-status]").hidden') } if (snapshot().preset_seconds !== 1500) { click('[data-focus-preset]'); confirm() } const before = counts(); nav('/apps/focus'); b('reload'); settled(); nav('/'); assert.deepEqual(counts(), before); assert.equal(ev('localStorage.length'), 0); screen('ready-dashboard-dark') })
 scenario('Preset dialog initial focus Tab Shift+Tab Escape and return focus', () => {
  click('[data-focus-preset]'); assert.equal(ev('document.activeElement.hasAttribute("autofocus")'), true)
  b('focus', '[data-focus-target=dialogConfirm]'); b('press', 'Tab'); assert.equal(ev('document.activeElement.getAttribute("aria-label")'), 'Fechar diálogo do Pomodoro')
  b('press', 'Shift+Tab'); assert.equal(ev('document.activeElement.dataset.focusTarget'), 'dialogConfirm'); b('press', 'Escape'); assert.equal(ev('document.activeElement.hasAttribute("data-focus-preset")'), true)
 })
 scenario('Preset 45 and 25 persist without overwriting appearance', () => {
  for (const preset of [2700, 1500]) { click('[data-focus-preset]'); confirm(); assert.equal(snapshot().preset_seconds, preset) }
  appearance('theme', 'light'); assert.equal(ev('document.documentElement.dataset.theme'), 'light'); assert.equal(ev('document.querySelector("[data-save-status]").hidden'), true)
 })
 scenario('Start pause resume with confirmed checkpoint and immutable start timestamp', () => { start(); const original = snapshot().session; advance(20); click('[data-focus-primary]'); state('paused'); assert.equal(snapshot().session.elapsed_seconds, 20); click('[data-focus-primary]'); state('running'); assert.equal(snapshot().session.uid, original.uid); assert.equal(snapshot().session.started_at, original.started_at); screen('running-light') })
 scenario('Theme and accent during active focus preserve UID duration and state', () => {
  const original = snapshot().session; appearance('theme', 'dark'); click('[data-open=customize]'); ev(`const e=document.querySelector('#drawer-accent');e.value='#8050b0';e.dispatchEvent(new Event('change',{bubbles:true}));true`); wait('document.querySelector("[data-save-status]").hidden'); b('press', 'Escape'); read(); assert.equal(snapshot().session.uid, original.uid); assert.equal(snapshot().session.duration_seconds, original.duration_seconds); assert.equal(snapshot().session.status, 'running')
 })
 scenario('Active preset changes are refused visibly without modifying duration', () => { const original = snapshot().session; click('[data-focus-preset]'); assert.match(ev('document.querySelector("[data-focus-target=message]").textContent'), /Encerre ou cancele/); assert.equal(snapshot().session.duration_seconds, original.duration_seconds) })
 scenario('Dashboard Focus and project show same global session without context reassignment', () => { const uid = snapshot().session.uid; for (const path of ['/apps/focus', `/projects/${ids.project}`, `/projects/${ids.other}`, '/']) { nav(path); assert.equal(snapshot().session.uid, uid); assert.equal(snapshot().session.project_uid, null) } })
 scenario('Explicit reset preserves history creates new ready UID and does not start automatically', () => { const original = snapshot().session.uid; click('[data-focus-reset]'); b('press', 'Escape'); assert.equal(snapshot().session.uid, original); click('[data-focus-reset]'); confirm(); state('ready'); assert.notEqual(snapshot().session.uid, original); const before = counts(); nav('/apps/focus'); assert.deepEqual(counts(), before); assert.equal(sql('puts FocusSession.order(:id).second_to_last.end_reason.to_json'), 'reset') })
 scenario('Ready preset replacement is explicit and atomic', () => { const original = snapshot().session.uid; click('[data-focus-preset]'); confirm(); state('ready'); assert.equal(snapshot().session.duration_seconds, 2700); assert.equal(snapshot().preset_seconds, 2700); assert.notEqual(snapshot().session.uid, original); cancel(); click('[data-focus-preset]'); confirm(); assert.equal(snapshot().preset_seconds, 1500) })
 scenario('Lost HTTP response retains envelope and replay reconciles current state', () => {
  ev(`window.__e2Fetch=fetch;window.__e2Bodies=[];window.fetch=async(url,options)=>{if(String(url)==='/focus/prepare'&&options?.method==='POST'){window.__e2Bodies.push(options.body);const r=await window.__e2Fetch(url,options);if(window.__e2Bodies.length===1)throw new Error('Resposta perdida sintética');return r}return window.__e2Fetch(url,options)};true`)
  click('[data-focus-primary]'); settled(); assert.ok(ev(`${focus}.client.pending`)); const one = counts(); assert.equal(one.occupants, 1); nav('/tasks'); nav('/apps/focus'); assert.ok(ev(`${focus}.client.pending`))
  const s = snapshot().session; const r = api(`/focus/${ev(`'u-'+btoa(${JSON.stringify(s.uid)}).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')`)}/commands`, 'POST', { command_id: runId + '-other-tab-pause', version: s.version, kind: 'pause', parameters: { action: 'pause' } }); assert.equal(r.status, 200)
  click('[data-focus-target=retry]'); state('paused'); assert.equal(ev('window.__e2Bodies[0]===window.__e2Bodies[1]'), true); assert.equal(counts().sessions, one.sessions); ev('window.fetch=window.__e2Fetch;true'); screen('lost-response-reconciled')
 })
 scenario('Long interruption preserves checkpoint and pending recovery across reload', () => { click('[data-focus-primary]'); state('running'); const checkpoint = snapshot().session.elapsed_seconds; advance(85); assert.equal(snapshot().timing.continuity, 'unknown'); click('[data-focus-primary]'); state('paused'); assert.equal(snapshot().session.elapsed_seconds, checkpoint); assert.ok(snapshot().recovery); const id = snapshot().recovery.receipt_id; b('reload'); settled(); assert.equal(snapshot().recovery.receipt_id, id); screen('recovery-pending') })
 scenario('Accept only server estimate then resume; old recovery ID cannot apply twice', () => { const recovery = snapshot().recovery, s = snapshot().session; click('[data-focus-resolve=accept_estimate]'); settled(); wait(`${focus}.client.snapshot.recovery===null`); assert.equal(snapshot().session.elapsed_seconds, recovery.candidate_seconds); const result = api(`/focus/${ev(`'u-'+btoa(${JSON.stringify(s.uid)}).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')`)}/commands`, 'POST', { command_id: runId + '-obsolete-recovery', version: s.version, kind: 'pause', parameters: { action: 'resolve', recovery_id: recovery.receipt_id, decision: 'keep_checkpoint' } }); assert.equal(result.status, 409); click('[data-focus-primary]'); state('running') })
 scenario('Invalid server clock estimate is not offered; keeping checkpoint preserves time', () => { const e = snapshot().session.elapsed_seconds; advance(20, 0); click('[data-focus-primary]'); state('paused'); assert.equal(snapshot().recovery.candidate_seconds, null); assert.equal(ev('document.querySelector("[data-focus-resolve=accept_estimate]").disabled'), true); click('[data-focus-resolve=keep_checkpoint]'); settled(); wait(`${focus}.client.snapshot.recovery===null`); assert.equal(snapshot().session.elapsed_seconds, e); cancel() })
 scenario('Nominal expiry never completes automatically; explicit reconcile and confirmation', () => { start(); const before = counts().completed; for (let n = 0; n < 25; n++) advance(60); assert.equal(snapshot().session.status, 'running'); assert.equal(counts().completed, before); click('[data-focus-primary]'); state('awaiting_confirmation'); screen('completion-pending'); click('[data-focus-primary]'); b('press', 'Escape'); assert.equal(counts().completed, before); click('[data-focus-primary]'); confirm(); assert.equal(snapshot().session, null); assert.equal(counts().completed, before + 1) })
 scenario('Expiry with browser observation gap requires recovery before completion', () => { start(); advance(3000); click('[data-focus-primary]'); state('paused'); assert.equal(snapshot().recovery.candidate_seconds, 1500); click('[data-focus-resolve=accept_estimate]'); state('awaiting_confirmation'); click('[data-focus-primary]'); confirm(); assert.equal(snapshot().session, null) })
 scenario('Contextual task Unicode UID starts once; task controls still work', () => { nav('/tasks'); click('#task-focus-' + ids.task); state('running'); assert.equal(snapshot().session.task_uid, 'task/á%?#'); assert.equal(snapshot().session.project_uid, '42/á?%#项目'); assert.ok(ev(`document.querySelector('#task-edit-${ids.task}')`)); nav('/apps/focus'); assert.match(ev('document.querySelector("[data-focus-context-label]").textContent'), /Tarefa contextual QA.*Projeto foco QA/); cancel() })
 scenario('Personal task and project-only context remain global across navigation', () => { nav('/tasks'); click('#task-focus-' + ids.personal); state('running'); assert.equal(snapshot().session.project_uid, null); assert.ok(snapshot().session.task_uid); nav('/apps/focus'); cancel(); nav(`/projects/${ids.project}`); start(); assert.equal(snapshot().session.project_uid, '42/á?%#项目'); assert.equal(snapshot().session.task_uid, null); nav('/'); cancel() })
 scenario('Completed task cannot start focus; reopening restores action', () => { nav('/tasks'); b('focus', '#task-check-' + ids.personal); b('press', 'Space'); wait(`document.querySelector('#task-check-${ids.personal}').checked && !document.querySelector('#task-check-${ids.personal}').disabled`); assert.equal(ev(`!!document.querySelector('#task-focus-${ids.personal}')`), false); b('focus', '#task-check-' + ids.personal); b('press', 'Space'); wait(`!!document.querySelector('#task-focus-${ids.personal}')`); nav('/apps/focus') })
 scenario('Two tabs reconcile and stale commands cannot duplicate or silently toggle history', () => {
  start(); const uid = snapshot().session.uid, first = b('tab','list').tabs.find(t=>t.active).tabId
  b('tab', 'new', origin + '/apps/focus'); settled(); const second=b('tab','list').tabs.find(t=>t.active).tabId
  state('running'); click('[data-focus-primary]'); state('paused'); b('tab', first); read(); state('paused')
  click('[data-focus-primary]'); state('running'); assert.equal(snapshot().session.uid,uid)
  b('tab', second); read(); state('running'); b('tab','close',second); b('tab',first); settled()
  const s=snapshot().session, encoded=ev(`'u-'+btoa(${JSON.stringify(s.uid)}).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')`)
  assert.equal(api(`/focus/${encoded}/commands`,'POST',{command_id:runId+'-stale-pause-source',version:s.version,kind:'pause',parameters:{action:'pause'}}).status,200)
  click('[data-focus-primary]'); state('paused'); assert.match(ev(`${focus}.client.message`),/lock|vers|Tentativa|Ação|stale/i)
  assert.equal(snapshot().session.uid,uid); assert.equal(counts().occupants,1); cancel()
 })
 scenario('Concurrent preference changes cause 409 without appearance overwrite', () => {
  const old = snapshot().preference_version; const remote = api('/appearance', 'PATCH', { version: old, appearance: { ...ev(`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio').preferences`), theme: 'light' } }); assert.equal(remote.status, 200)
  click('[data-focus-preset]'); confirm(); assert.match(ev(`${focus}.client.message`), /Preferências alteradas/); assert.equal(snapshot().preset_seconds, 1500); b('reload'); settled(); assert.equal(ev('document.documentElement.dataset.theme'), 'light')
 })
 scenario('Archived project blocks start and resume but permits pause and cancellation', () => {
  nav(`/projects/${ids.project}`); start(); const s = snapshot().session; const r = api(`/projects/${ids.project}/command`, 'PATCH', { operation: 'archive', version: ev(`JSON.parse(document.querySelector('[data-controller=focus]').dataset.focusCatalogValue).projects.find(p=>p.uid==='42/á?%#项目').version`) }); assert.equal(r.status, 200); click('[data-focus-primary]'); state('paused'); click('[data-focus-primary]'); settled(); assert.equal(snapshot().session.status, 'paused'); assert.match(ev(`${focus}.client.message`), /arquivado/); nav(`/projects/${ids.project}`); cancel(); assert.equal(ev('document.querySelector("[data-focus-primary]").disabled'), true); const p = ev(`JSON.parse(document.querySelector('[data-controller=focus]').dataset.focusCatalogValue).projects.find(p=>p.uid==='42/á?%#项目')`); assert.equal(api(`/projects/${ids.project}/command`, 'PATCH', { operation: 'restore', version: p.version }).status, 200); nav('/apps/focus')
 })
 scenario('Polling and ticks do not write sessions commands or versions', () => {
  start(); const before = counts(); ev('window.__reads=0;window.__pollFetch=fetch;window.fetch=(u,o)=>{if(String(u)==="/focus/state")window.__reads++;return window.__pollFetch(u,o)};true'); wait('window.__reads>=1'); assert.deepEqual(counts(), before); ev('window.fetch=window.__pollFetch;true'); assert.equal(ev('localStorage.length'), 0); screen('polling-no-writes'); cancel()
 })
 scenario('Rapid Turbo navigation keeps one controller and no clock writes', () => { const before = counts(); for (const path of ['/', '/apps/focus', '/tasks', '/apps/focus', '/', '/apps/focus']) nav(path); assert.equal(ev('document.querySelectorAll("[data-controller=focus]").length'), 1); assert.deepEqual(counts(), before) })
 scenario('Network loss visibly unconfirmed and reconnect reads current state', () => { cancel(); start(); ev('window.__netFetch=fetch;window.fetch=(u,o)=>String(u).startsWith("/focus/")?Promise.reject(new Error("Rede indisponível sintética")):window.__netFetch(u,o);true'); ev(`${focus}.client.read().then(()=>true)`); wait(`${focus}.client.confirmed===false`); assert.match(ev('document.querySelector("[data-focus-feedback]").textContent'), /não confirmado/); ev('window.fetch=window.__netFetch;window.dispatchEvent(new Event("online"));true'); settled(); state('running'); assert.equal(ev(`${focus}.client.message.includes('Resposta não confirmada')`),false); cancel() })
 scenario('Repeated Turbo lifecycle and hidden-page polling have no duplicate timers or listeners', () => {
  ev(`window.__intervals=new Map();window.__realInterval=setInterval;window.__realClear=clearInterval;window.setInterval=(f,ms,...a)=>{const id=window.__realInterval(f,ms,...a);window.__intervals.set(id,ms);return id};window.clearInterval=id=>{window.__intervals.delete(id);window.__realClear(id)};window.__visibilityHandlers=new Set();window.__realAdd=document.addEventListener.bind(document);window.__realRemove=document.removeEventListener.bind(document);document.addEventListener=(type,fn,...a)=>{if(type==='visibilitychange')window.__visibilityHandlers.add(fn);return window.__realAdd(type,fn,...a)};document.removeEventListener=(type,fn,...a)=>{if(type==='visibilitychange')window.__visibilityHandlers.delete(fn);return window.__realRemove(type,fn,...a)};true`)
  for (const path of ['/', '/tasks', '/apps/focus', '/', '/apps/focus']) nav(path)
  assert.deepEqual(ev('[...window.__intervals.values()].sort((a,b)=>a-b)'),[1000,1000,15000]); assert.equal(ev('window.__visibilityHandlers.size'),1)
  ev(`Object.defineProperty(document,'visibilityState',{configurable:true,get:()=> 'hidden'});document.dispatchEvent(new Event('visibilitychange'));true`)
  assert.deepEqual(ev('[...window.__intervals.values()].sort((a,b)=>a-b)'),[1000,1000])
  ev(`delete document.visibilityState;document.dispatchEvent(new Event('visibilitychange'));true`); settled()
  assert.deepEqual(ev('[...window.__intervals.values()].sort((a,b)=>a-b)'),[1000,1000,15000]); assert.equal(ev('window.__visibilityHandlers.size'),1)
  ev('window.setInterval=window.__realInterval;window.clearInterval=window.__realClear;document.addEventListener=window.__realAdd;document.removeEventListener=window.__realRemove;true')
 })
 scenario('Two confirmation dialogs converge without duplicate completed history', () => {
  cancel(); start(); for(let n=0;n<25;n++)advance(60); click('[data-focus-primary]'); state('awaiting_confirmation')
  const first=b('tab','list').tabs.find(t=>t.active).tabId, before=counts().completed
  click('[data-focus-primary]'); b('tab','new',origin+'/apps/focus'); settled(); const second=b('tab','list').tabs.find(t=>t.active).tabId
  click('[data-focus-primary]'); confirm(); assert.equal(snapshot().session,null)
  b('tab',first); read(); click('[data-focus-target=dialogConfirm]'); assert.match(ev('document.querySelector("[data-focus-target=dialogFeedback]").textContent'),/estado mudou/)
  b('press','Escape'); b('tab','close',second); b('tab',first); assert.equal(counts().completed,before+1); assert.equal(snapshot().session,null)
 })
 scenario('Completed focus does not complete its task and moved tasks preserve historical project', () => {
  nav('/tasks'); click('#task-focus-'+ids.task); state('running'); const original=snapshot().session
  sql(`const_task=Task.find_by!(uid:'task/á%?#');const_task.update!(project:User.first.projects.find_by!(uid:PublicUid.decode(${JSON.stringify(ids.other)})));puts true.to_json`)
  nav('/apps/focus'); assert.equal(snapshot().session.project_uid,original.project_uid); assert.equal(snapshot().session.task_uid,original.task_uid)
  for(let n=0;n<25;n++)advance(60); click('[data-focus-primary]'); state('awaiting_confirmation'); click('[data-focus-primary]'); confirm()
  assert.equal(sql("puts Task.find_by!(uid:'task/á%?#').status.to_json"),'pending')
  sql(`t=Task.find_by!(uid:'task/á%?#');t.update!(project:User.first.projects.find_by!(uid:'42/á?%#项目'));puts true.to_json`)
 })
 for (const theme of ['dark', 'light']) {
  appearance('theme', theme)
  for (const width of [320, 390, 768, 1440, 1920]) {
   b('set', 'viewport', String(width), '1000')
   scenario(`Visual ${theme} ${width}px Dashboard Focus Project and dialog`, () => {
    for (const [name, path] of [['dashboard', '/'], ['focus', '/apps/focus'], ['project', `/projects/${ids.project}`]]) {
     nav(path); const geometry = ev(`(()=>{const d=document.querySelector('.dial'),m=document.querySelector('main'),r=d.getBoundingClientRect();return {width:r.width,height:r.height,body:document.body.scrollWidth,view:innerWidth,main:m.scrollWidth,client:m.clientWidth,background:getComputedStyle(d.closest('.panel-focus')).backgroundImage}})()`)
     assert.equal(geometry.width, 170); assert.equal(geometry.height, 170); assert.ok(geometry.body <= width + 1 && geometry.main <= geometry.client + 1, JSON.stringify(geometry)); if (theme === 'light') assert.match(geometry.background, /238, 232, 251/)
     geometryResults.push({name,theme,width,...geometry}); writeFileSync(resolve(evidence,'focus-geometry.json'),JSON.stringify(geometryResults,null,2)+'\n')
     screen(`${name}-${theme}-${width}`)
     if (name === 'focus') { writeFileSync(resolve(evidence, `axe-focus-${theme}-${width}.json`), JSON.stringify(b('a11y', '--json'), null, 2) + '\n'); click('[data-focus-preset]'); screen(`dialog-${theme}-${width}`); assert.equal(ev('document.querySelector(".focus-dialog").scrollWidth>document.querySelector(".focus-dialog").clientWidth'), false); b('press', 'Escape') }
    }
   })
  }
 }
 sql('raise "Triggers" unless FocusSession.connection.select_value("SELECT count(*) FROM sqlite_master WHERE type=\'trigger\'")==25; raise "FK" unless FocusSession.connection.select_all("PRAGMA foreign_key_check").empty?; puts({triggers:25,foreign_keys:true,task_pending:Task.where(status:"pending").count}.to_json)')
 console.log(JSON.stringify({ passed: results.length }))
} catch (error) { console.error(error.stack); try { screen('failure-' + Date.now()); console.error(JSON.stringify(b('snapshot', '-i'))); } catch {} process.exitCode = 1 }
