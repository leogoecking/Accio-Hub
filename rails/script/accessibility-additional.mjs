// Local synthetic Chromium QA. No production URL, dependency or application mutation.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root = resolve(import.meta.dirname, '..'), repo = resolve(root, '..');
const workspace = readFileSync(resolve(root, 'tmp/p12e2-workspace'), 'utf8').trim();
assert.ok(workspace.startsWith(resolve(root, 'tmp/p12e2-browser-')));
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json')));
const ids = JSON.parse(readFileSync(resolve(workspace, 'state.json')));
const origin = process.env.ACCIO_QA_URL || 'http://127.0.0.1:3127';
assert.ok(['127.0.0.1', 'localhost'].includes(new URL(origin).hostname));
const phase = process.env.ACCIO_QA_PHASE || (process.env.ACCIO_QA_HOVER === '1' ? 'hover' : 'additional');
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(repo, 'docs/assets/p1.2f/f4', phase));
mkdirSync(evidence, { recursive: true });
const session = process.env.ACCIO_QA_SESSION || 'accio-f4-investigation';
const args = ['--session', session, '--json'];
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 60000 })); assert.equal(r.success, true, JSON.stringify(r)); return r.data; };
const ev = code => { const r = JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data.result; };
const wait = fn => b('wait', '--fn', fn);
const ready = () => { b('wait', '[data-ready=true]'); wait('!document.documentElement.hasAttribute("aria-busy")&&!document.documentElement.hasAttribute("data-turbo-preview")'); ev('document.fonts.ready.then(()=>true)'); };
const open = path => { b('open', origin + path); ready(); };
const click = selector => { b('snapshot', '-i'); b('click', selector); };
const sample = readFileSync(resolve(root, 'script/accessibility-sample.js'), 'utf8');
const results = [];
function capture(name) {
  ev('document.fonts.ready.then(()=>true)');
  ev('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
  wait(`(()=>{const key=[...document.querySelectorAll('.viewport,.drawer,.search-results,dialog[open]')].map(el=>el.scrollTop+':'+el.getBoundingClientRect().top).join('|');const previous=window.__f4ScrollPosition;window.__f4ScrollPosition=key;return previous===key})()`);
  const data = ev(sample);
  writeFileSync(resolve(evidence, name + '.json'), JSON.stringify(data, null, 2) + '\n');
  b('screenshot', resolve(evidence, name + '.png'));
  // Keep color/currentColor/backgrounds/geometry intact; hide only glyphs/strokes.
  ev(`(()=>{const s=document.createElement('style');s.id='f4-hidden-ink';s.textContent='*{-webkit-text-fill-color:transparent!important;text-shadow:none!important;caret-color:transparent!important}*::placeholder{-webkit-text-fill-color:transparent!important;color:transparent!important}svg *{stroke:transparent!important;fill:transparent!important}';document.head.append(s);return true})()`);
  try { b('screenshot', resolve(evidence, name + '-background.png')); } finally { ev('document.querySelector("#f4-hidden-ink").remove();true'); }
  const axe = b('a11y');
  writeFileSync(resolve(evidence, 'axe-' + name + '.json'), JSON.stringify(axe, null, 2) + '\n');
  results.push({ name, viewport: data.viewport, theme: data.theme, wallpaper: data.wallpaper, accent: data.accent, overflow: data.overflow,
    axe: axe.counts, violations: axe.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes?.map(n => n.target) })) });
  writeFileSync(resolve(evidence, 'matrix.json'), JSON.stringify(results, null, 2) + '\n');
  execFileSync('python3', [resolve(root, 'script/accessibility-contrast.py'), resolve(evidence, name)], { encoding: 'utf8' });
  console.log('CAPTURE ' + name + ' axe=' + axe.counts.violations);
}

const studio = `window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio')`;
const focus = `window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`;
const settled = () => wait(`${focus}?.client.confirmed&&!${focus}.client.sending&&!${focus}.preparing&&!${focus}.recoveryFlow.busy`);
const loggedIn = () => { b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);click('.login-card [type=submit]');ready();settled(); };
const saveSettled = () => wait(`${studio}?.pending===0&&!${studio}.failed`);
function appearance(theme, accent='#b1f07d') {
 open('/apps/settings');b('select','#page-theme',theme);saveSettled();
 ev(`(()=>{const el=document.querySelector('#page-accent');el.value=${JSON.stringify(accent)};el.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);saveSettled();
 assert.equal(ev('document.documentElement.dataset.theme'),theme);
 assert.equal(ev('getComputedStyle(document.documentElement).getPropertyValue("--accent").trim()'),accent);
}
function confirm() {click('[data-focus-target=dialogConfirm]');wait('!document.querySelector(".focus-dialog").open');settled();}
function cancel() {if(ev(`${focus}.client.snapshot.session!==null`)){click('[data-focus-cancel]');confirm();}}
function advance(seconds) {
 const path=resolve(workspace,'clock.json'), clock=JSON.parse(readFileSync(path));
 const fraction=clock.wall.match(/\.(\d+)Z$/)?.[1]||'000';clock.wall=new Date(Date.parse(clock.wall)+seconds*1000).toISOString().replace(/\.\d{3}Z$/,'.'+fraction+'Z');clock.monotonic+=seconds;writeFileSync(path,JSON.stringify(clock));
 ev(`${focus}.client.read().then(()=>true)`);settled();
}
b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i');if(ev('!!document.querySelector("#password")'))loggedIn();ready();
if (process.env.ACCIO_QA_HOVER === '1') {
 for (const theme of ['dark', 'light']) for (const accent of ['#b1f07d', '#d498e7', '#888888', '#000000', '#ffffff']) {
  appearance(theme, accent);
  for (const width of [320, 1440]) {
   open('/');b('set', 'viewport', String(width), '1000');b('hover', '[data-edit]');
   ev('Promise.all(document.getAnimations().map(animation=>animation.finished.catch(()=>null))).then(()=>true)');
   assert.equal(ev('getComputedStyle(document.querySelector("[data-edit]")).filter'), 'none');
   capture(`hover-${theme}-${accent.slice(1)}-${width}`);
  }
 }
 b('close');console.log('20 actual hover states across five accents and two themes / widths.');process.exit(0);
}
for(const theme of ['dark','light']) for(const accent of ['#000000','#b1f07d']){
 appearance(theme,accent);click('button.rail-avatar');b('wait','#password');
 wait('!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller=login-contrast]"),"login-contrast")');
 for(const width of [320,390,768,1440,1920]){b('set','viewport',String(width),'1000');capture(`login-${theme}-${accent.slice(1)}-${width}`);}
 loggedIn();
}
open('/apps/focus');settled();cancel();
if(ev(`${focus}.client.snapshot.preset_seconds!==1500`)){click('[data-focus-preset]');confirm();}
click('[data-focus-primary]');settled();advance(30);click('[data-focus-primary]');settled();click('[data-focus-primary]');settled();advance(1200);click('[data-focus-primary]');settled();
assert.equal(ev(`${focus}.client.snapshot.session.status`),'paused');assert.ok(ev(`${focus}.client.snapshot.recovery?.receipt_id`));
for(const theme of ['dark','light']){
 appearance(theme);open('/apps/focus');settled();
 for(const width of [320,390,768,1440,1920]){b('set','viewport',String(width),'1000');capture(`recovery-${theme}-${width}`);}
}
click('[data-focus-resolve=accept_estimate]');settled();assert.equal(ev(`${focus}.client.snapshot.session.status`),'running');
capture('estimate-accepted');cancel();
b('set','media','light','reduced-motion');assert.equal(ev('matchMedia("(prefers-reduced-motion: reduce)").matches'),true);
const reduced=ev(`(()=>{const dial=getComputedStyle(document.querySelector('.dial'));return {reduce:matchMedia('(prefers-reduced-motion: reduce)').matches,dialTransition:dial.transitionDuration,scroll:getComputedStyle(document.querySelector('.viewport')).scrollBehavior,clockLive:document.querySelector('[data-focus-clock]').closest('[aria-live]')?.getAttribute('aria-live')||null}})()`);
assert.equal(reduced.clockLive,null);writeFileSync(resolve(evidence,'reduced-motion.json'),JSON.stringify(reduced,null,2)+'\n');
writeFileSync(resolve(evidence,'browser-errors.json'),JSON.stringify(b('errors'),null,2)+'\n');
b('close');console.log('Completed '+results.length+' supplemental states, real login/logout and explicit recovery.');
