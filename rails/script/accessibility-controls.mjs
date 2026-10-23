import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const root = resolve(import.meta.dirname, '..'), w = readFileSync(resolve(root, 'tmp/p12e2-workspace'), 'utf8').trim();
assert.ok(w.startsWith(resolve(root, 'tmp/p12e2-browser-')));
const c = JSON.parse(readFileSync(resolve(w, 'credentials.json'))), args = ['--session', 'accio-f4-controls', '--json'];
const phase = process.env.ACCIO_QA_PHASE || 'before', evidence = resolve(root, '../docs/assets/p1.2f/f4/controls-' + phase); mkdirSync(evidence, { recursive: true });
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data; };
const ev = code => { const r = JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data.result; };
const original = process.env.ACCIO_QA_BASELINE_CSS === '1' ? execFileSync('git', ['show', 'HEAD:rails/app/assets/stylesheets/foundation.css'], { cwd: root, encoding: 'utf8' }) : null;
const wait = fn => b('wait', '--fn', fn), click = s => { b('snapshot', '-i'); b('click', s); }, open = p => {
  b('open', 'http://127.0.0.1:3127' + p); b('wait', '[data-ready=true]');
  if (original) ev(`(()=>{document.querySelectorAll('link[href*="foundation"]').forEach(el=>el.disabled=true);const s=document.createElement('style');s.textContent=${JSON.stringify(original)};document.head.append(s);return true})()`);
};
const observations = [];
function capture(name, selectors) {
  b('press', 'Tab'); b('focus', selectors[0]);
  ev('document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>r(true)))))');
  const sample = ev(readFileSync(resolve(root, 'script/accessibility-sample.js'), 'utf8'));
  const selected = sample.nodes.filter(n => n.kind === 'boundary' && selectors.includes(n.selector));
  const focus = sample.nodes.filter(n => n.kind === 'focus');
  b('screenshot', resolve(evidence, name + '.png'));
  ev(`(()=>{const s=document.createElement('style');s.id='f4-borders';s.textContent='*{-webkit-text-fill-color:transparent!important;text-shadow:none!important;border-color:transparent!important;outline-color:transparent!important}svg *{stroke:transparent!important;fill:transparent!important}';document.head.append(s);return true})()`);
  b('screenshot', resolve(evidence, name + '-background.png')); ev('document.querySelector("#f4-borders").remove();true');
  const result = { name, viewport: sample.viewport, theme: sample.theme, controls: selected, focus };
  writeFileSync(resolve(evidence, name + '.json'), JSON.stringify(result, null, 2) + '\n'); observations.push(name);
}
b('--args', '--no-sandbox', 'open', 'http://127.0.0.1:3127/session/new'); b('snapshot', '-i');
if (ev('!!document.querySelector("#password")')) { b('fill', '#email_address', c.email); ev('document.querySelector("#password").value=' + JSON.stringify(c.password) + ';true'); click('.login-card [type=submit]'); }
b('wait', '[data-ready=true]');
for (const theme of ['dark', 'light']) for (const width of [320, 1440]) {
  b('set', 'viewport', String(width), '1000'); open('/apps/settings'); b('select', '#page-theme', theme); wait('document.querySelector("[data-save-status]").hidden');
  ev('(()=>{const el=document.querySelector("#page-accent");el.value="#b1f07d";el.dispatchEvent(new Event("change",{bubbles:true}));return true})()'); wait('document.querySelector("[data-save-status]").hidden');
  capture(theme + '-' + width + '-settings', ['#page-theme']);
  open('/projects'); capture(theme + '-' + width + '-library', ['#project-search', '#project-order']); click('#project-new'); b('wait', 'dialog[open]');
  capture(theme + '-' + width + '-form', ['#project-name', '#project-description', '#project-icon', '#project-color-hex']); b('press', 'Escape');
}
writeFileSync(resolve(evidence, 'captures.json'), JSON.stringify(observations, null, 2) + '\n'); b('close');
