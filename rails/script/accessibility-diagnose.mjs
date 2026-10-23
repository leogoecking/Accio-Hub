// Before/after diagnostics; temporary native-link comparison is DOM-only.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const root = resolve(import.meta.dirname, '..'), workspace = readFileSync(resolve(root, 'tmp/p12e2-workspace'), 'utf8').trim();
assert.ok(workspace.startsWith(resolve(root, 'tmp/p12e2-browser-')));
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json'))), ids = JSON.parse(readFileSync(resolve(workspace, 'state.json')));
const evidence = resolve(root, '../docs/assets/p1.2f/f4/diagnose-' + (process.env.ACCIO_QA_PHASE || 'before')); mkdirSync(evidence, { recursive: true });
const args = ['--session', 'accio-f4-diagnose', '--json'];
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data; };
const ev = code => { const r = JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data.result; };
const wait = code => b('wait', '--fn', code), open = path => { b('open', 'http://127.0.0.1:3127' + path); b('wait', '[data-ready=true]'); };
const click = selector => { b('snapshot', '-i'); b('click', selector); };
const focus = () => ev('({active:document.activeElement.tagName,id:document.activeElement.id,modal:!!document.querySelector("dialog:modal"),within:document.querySelector("dialog:modal")?.contains(document.activeElement),hash:location.hash})');
const data = {};
b('--args', '--no-sandbox', 'open', 'http://127.0.0.1:3127/session/new'); b('snapshot', '-i');
if (ev('!!document.querySelector("#password")')) { b('fill', '#email_address', credentials.email); ev('document.querySelector("#password").value=' + JSON.stringify(credentials.password) + ';true'); click('.login-card [type=submit]'); }
b('wait', '[data-ready=true]');
for (const native of [false, true]) {
  open('/'); b('set', 'viewport', '390', '844');
  if (native) ev('document.querySelector(".skip-link").dataset.turbo="false";true');
  b('record', 'start', resolve(evidence, 'skip-' + native + '.webm')); b('press', 'Tab'); b('screenshot', resolve(evidence, 'skip-' + native + '-before.png')); b('press', 'Enter');
  wait('location.hash==="#main-content"'); ev('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
  data['skip_native_' + native] = focus(); b('screenshot', resolve(evidence, 'skip-' + native + '-after.png')); b('record', 'stop');
}
for (const kind of ['project', 'task', 'reference']) {
  open(kind === 'project' ? '/projects' : kind === 'task' ? '/tasks' : '/projects/' + ids.project + '?tab=references');
  click(kind === 'project' ? '#project-new' : kind === 'task' ? '#task-new-top' : '#reference-new'); b('wait', 'dialog[open]');
  if (kind === 'project') b('fill', '#project-name', 'Projeto foco QA');
  if (kind === 'task') { ev('document.querySelector("#task-title").removeAttribute("maxlength");true'); b('fill', '#task-title', 'X'.repeat(121)); }
  if (kind === 'reference') { b('fill', '#reference-title', 'Referência inválida QA'); b('fill', '#reference-url', 'https://user:pass@example.test'); }
  b('record', 'start', resolve(evidence, kind + '-error.webm'));
  b('focus', '#' + kind + '-form [type=submit]'); b('screenshot', resolve(evidence, kind + '-submit-before.png')); b('press', 'Enter');
  wait('document.querySelector("dialog[open] [role=alert]").textContent.trim().length>0&&!document.querySelector("dialog[open] [type=submit]").disabled');
  ev('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
  data[kind + '_error'] = focus(); b('screenshot', resolve(evidence, kind + '-error-after.png')); b('record', 'stop'); b('press', 'Escape');
}
writeFileSync(resolve(evidence, 'observations.json'), JSON.stringify(data, null, 2) + '\n'); console.log(JSON.stringify(data)); b('close');
