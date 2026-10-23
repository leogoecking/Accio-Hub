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
const phase = process.env.ACCIO_QA_PHASE || 'before';
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
function theme(value) {
  open('/apps/settings'); b('select', '#page-theme', value);
  wait('document.querySelector("[data-save-status]").hidden');
  click('[data-wallpaper="northern"]'); wait('document.querySelector("[data-save-status]").hidden');
  ev(`(()=>{const el=document.querySelector('#page-accent');el.value='#b1f07d';el.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
  wait('document.querySelector("[data-save-status]").hidden');
  assert.equal(ev('document.documentElement.dataset.theme'), value);
}

b('--args', '--no-sandbox', 'open', origin + '/session/new'); b('snapshot', '-i');
if (ev('!!document.querySelector("#password")')) {
  b('fill', '#email_address', credentials.email); ev('document.querySelector("#password").value=' + JSON.stringify(credentials.password) + ';true'); click('.login-card [type=submit]');
}
ready();
const widths = (process.env.ACCIO_QA_WIDTHS || (phase === 'before' ? '320,1440' : '320,390,768,1440,1920')).split(',').map(Number);
if (process.env.ACCIO_QA_PALETTE === '1') {
  for (const color of ['dark', 'light']) {
    for (const width of [320, 1440]) {
      b('set', 'viewport', String(width), '1000'); theme(color);
      for (const wallpaper of ['northern', 'ember', 'ocean', 'graphite']) {
        const accents = wallpaper === 'northern' ? ['#b1f07d', '#d498e7', '#888888', '#000000', '#ffffff'] : ['#b1f07d', '#d498e7', '#888888'];
        for (const accent of accents) {
          open('/apps/settings'); click(`[data-wallpaper="${wallpaper}"]`);
          wait('document.querySelector("[data-save-status]").hidden');
          ev(`(()=>{const el=document.querySelector('#page-accent');el.value=${JSON.stringify(accent)};el.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
          wait('document.querySelector("[data-save-status]").hidden');
          const name = `${color}-${width}-${wallpaper}-${accent.slice(1)}`;
          open('/');
          if (ev('document.querySelector(".music-button[data-music-expand]").getAttribute("aria-expanded")==="true"')) { click('.music-button[data-music-expand]'); wait('document.querySelector("[data-save-status]").hidden'); }
          capture(name + '-dashboard');
          open('/apps/focus'); capture(name + '-focus');
        }
      }
    }
  }
} else for (const color of ['dark', 'light']) {
  theme(color);
  for (const width of widths) {
    b('set', 'viewport', String(width), '1000');
    const prefix = color + '-' + width;
    open('/');
    if (ev('document.querySelector(".music-button[data-music-expand]").getAttribute("aria-expanded")==="true"')) { click('.music-button[data-music-expand]'); wait('document.querySelector("[data-save-status]").hidden'); }
    capture(prefix + '-dashboard');
    ev(`(()=>{window.__f4ScrollDone=false;document.querySelector('.viewport').addEventListener('scrollend',()=>window.__f4ScrollDone=true,{once:true});return true})()`);
    b('scroll', 'down', '690', '--selector', '.viewport'); wait('window.__f4ScrollDone'); capture(prefix + '-widgets');
    open('/apps/focus'); capture(prefix + '-focus');
    click('[data-focus-preset]'); b('wait', '.focus-dialog[open]'); capture(prefix + '-focus-dialog'); b('press', 'Escape');
    open('/projects'); capture(prefix + '-library');
    click('#project-new'); b('wait', '[data-project-dialog][open]'); capture(prefix + '-project-form'); b('press', 'Escape');
    open('/tasks'); capture(prefix + '-tasks');
    click('#task-new-top'); b('wait', '[data-task-dialog][open]'); capture(prefix + '-task-form'); b('press', 'Escape');
    open('/projects/' + ids.project); capture(prefix + '-project');
    open('/projects/' + ids.project + '?tab=references'); capture(prefix + '-references');
    click('#reference-new'); b('wait', '[data-reference-dialog][open]'); capture(prefix + '-reference-form'); b('press', 'Escape');
    open('/projects/' + ids.other + '?tab=references'); capture(prefix + '-empty');
    open('/apps/settings'); capture(prefix + '-settings');
    click('[data-open=customize]'); b('wait', '#customize[open]'); capture(prefix + '-customize'); b('press', 'Escape');
    click('[data-open=search]'); b('wait', '#search[open]'); capture(prefix + '-search'); b('press', 'Escape');
    click('[data-music-expand]'); capture(prefix + '-music');
  }
}
writeFileSync(resolve(evidence, 'browser-errors.json'), JSON.stringify(b('errors'), null, 2) + '\n');
console.log('Completed ' + results.length + ' states; incomplete is not PASS.');
