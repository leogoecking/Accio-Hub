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
const phase = process.env.ACCIO_QA_PHASE || 'errors';
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
b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i');if(ev('!!document.querySelector("#password")'))loggedIn();ready();
const originalCSS=execFileSync('git',['show','HEAD:rails/app/assets/stylesheets/foundation.css'],{cwd:repo,encoding:'utf8'});
const comparisons=[];
for(const theme of ['dark','light']){
 appearance(theme);
 for(const width of [320,1440]){
 b('set','viewport',String(width),'1000');
 for(const [name,path]of[['dashboard','/'],['focus','/apps/focus']]){
  open(path);settled();
  if(ev('document.querySelector("[data-music-expand]").getAttribute("aria-expanded")==="true"')){click('[data-music-expand]');saveSettled();}
  const id=`controlled-${theme}-${width}-${name}`;
  ev('document.fonts.ready.then(()=>true)');ev('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
  const after=ev(sample);b('screenshot',resolve(evidence,id+'-after.png'));
  ev(`(()=>{document.querySelectorAll('link[rel=stylesheet]').forEach(el=>{if(el.href.includes('/foundation-')||el.href.includes('/foundation.')){el.dataset.f4Disabled='true';el.disabled=true}});const s=document.createElement('style');s.id='f4-original-css';s.textContent=${JSON.stringify(originalCSS)};document.head.append(s);return true})()`);
  const before=ev(sample);b('screenshot',resolve(evidence,id+'-before.png'));
  assert.deepEqual(after.geometry,before.geometry,'CSS must preserve fonts and geometry');comparisons.push({id,geometryIdentical:true,wallpaper:after.wallpaper,method:'HEAD foundation CSS temporarily applied in synthetic DOM; all other markup/assets/data identical'});
  ev('document.querySelector("#f4-original-css").remove();document.querySelectorAll("[data-f4-disabled]").forEach(el=>{el.disabled=false;delete el.dataset.f4Disabled});true');
 }
 for(const kind of ['project','task','reference']){
  open(kind==='project'?'/projects':kind==='task'?'/tasks':'/projects/'+ids.project+'?tab=references');click(kind==='project'?'#project-new':kind==='task'?'#task-new-top':'#reference-new');b('wait','dialog[open]');
  if(kind==='project')b('fill','#project-name','Projeto foco QA');
  if(kind==='task'){ev('document.querySelector("#task-title").removeAttribute("maxlength");true');b('fill','#task-title','X'.repeat(121));}
  if(kind==='reference'){b('fill','#reference-title','Referência inválida QA');b('fill','#reference-url','https://user:pass@example.test');}
  b('focus','#'+kind+'-form [type=submit]');b('press','Enter');
  wait('document.querySelector("dialog[open] [role=alert]").textContent.trim().length>0&&!document.querySelector("dialog[open] [type=submit]").disabled');
  wait('document.querySelector("dialog:modal").contains(document.activeElement)');
  capture(`error-${kind}-${theme}-${width}`);b('press','Escape');
 }
 }
}
writeFileSync(resolve(evidence,'controlled-geometry.json'),JSON.stringify(comparisons,null,2)+'\n');
writeFileSync(resolve(evidence,'browser-errors.json'),JSON.stringify(b('errors'),null,2)+'\n');b('close');console.log('12 validation-error states and 8 controlled visual pairs.');
