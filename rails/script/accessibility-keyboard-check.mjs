import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const root = resolve(import.meta.dirname, '..'), workspace = readFileSync(resolve(root, 'tmp/p12e2-workspace'), 'utf8').trim();
assert.ok(workspace.startsWith(resolve(root, 'tmp/p12e2-browser-')));
const credentials = JSON.parse(readFileSync(resolve(workspace, 'credentials.json'))), ids = JSON.parse(readFileSync(resolve(workspace, 'state.json')));
const origin = 'http://127.0.0.1:3127', phase = process.env.ACCIO_QA_PHASE || 'before';
const evidence = resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root, '../docs/assets/p1.2f/f4', 'keyboard-' + phase));
mkdirSync(evidence, { recursive: true });
const args = ['--session', process.env.ACCIO_QA_SESSION || 'accio-f4-keyboard', '--json'];
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true, JSON.stringify(r)); return r.data; };
const ev = code => { const r = JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data.result; };
const wait = code => b('wait', '--fn', code), ready = () => { b('wait', '[data-ready=true]'); wait('!document.documentElement.hasAttribute("aria-busy")'); };
const open = path => { b('open', origin + path); ready(); }, click = selector => { b('snapshot', '-i'); b('click', selector); };
const results = [], active = () => ev('document.activeElement.id || document.activeElement.getAttribute("aria-label") || document.activeElement.tagName');
function check(name, fn) {
  try { fn(); results.push({ name, status: 'PASS' }); }
  catch (error) { results.push({ name, status: 'FAIL', error: error.message }); b('screenshot', resolve(evidence, 'failure-' + results.length + '.png')); }
  writeFileSync(resolve(evidence, 'results.json'), JSON.stringify(results, null, 2) + '\n'); console.log(results.at(-1).status + ' ' + name);
}
const controls = modal => ev(`Array.from(document.querySelector(${JSON.stringify(modal)}).querySelectorAll('a[href],button,input,select,textarea,[tabindex]')).filter(el=>!el.disabled&&el.tabIndex>=0&&el.getClientRects().length>0).map((el,i)=>{el.dataset.f4KeyIndex=i;return i})`);
function trap(modal) {
  const all = controls(modal); assert.ok(all.length > 1);
  b('focus', `${modal} [data-f4-key-index="${all.at(-1)}"]`); b('press', 'Tab');
  assert.equal(ev('document.activeElement.dataset.f4KeyIndex'), '0'); b('press', 'Shift+Tab');
  assert.equal(ev('document.activeElement.dataset.f4KeyIndex'), String(all.at(-1)));
}
b('--args', '--no-sandbox', 'open', origin + '/session/new'); b('snapshot', '-i');
if (ev('!!document.querySelector("#password")')) { b('fill', '#email_address', credentials.email); ev('document.querySelector("#password").value=' + JSON.stringify(credentials.password) + ';true'); click('.login-card [type=submit]'); }
ready(); b('set', 'viewport', '390', '844');
check('Skip link and logical keyboard entry', () => { open('/'); b('press', 'Tab'); assert.equal(ev('document.activeElement.className'), 'skip-link'); b('press', 'Enter'); wait('document.activeElement.id==="main-content"'); assert.equal(active(), 'main-content'); });
for (const [name, path, opener, modal, initial] of [
  ['project', '/projects', '#project-new', '[data-controller=project-form]', 'project-name'],
  ['task', '/tasks', '#task-new-top', '[data-task-dialog]', 'task-title'],
  ['reference', '/projects/' + ids.project + '?tab=references', '#reference-new', '[data-reference-dialog]', 'reference-title'],
]) {
  check(name + ' dialog Enter initial focus Tab ShiftTab Escape return', () => {
    open(path); b('focus', opener); b('press', 'Enter'); b('wait', modal + '[open]'); assert.equal(active(), initial);
    trap(modal); b('press', 'Escape'); wait('!document.querySelector("dialog:modal")'); assert.equal(active(), opener.slice(1));
  });
  check(name + ' dialog cancel and close by keyboard', () => {
    for (const which of ['cancel', 'close']) {
      open(path); b('focus', opener); b('press', 'Enter'); b('wait', modal + '[open]');
      b('focus', which === 'cancel' ? `${modal} .project-form-actions [type=button]` : `${modal} button[aria-label^="Fechar"]`);
      b('press', 'Space'); wait('!document.querySelector("dialog:modal")'); assert.equal(active(), opener.slice(1));
    }
  });
}
check('Drawer keyboard containment and return', () => { open('/'); b('focus', '[data-open=customize]'); b('press', 'Space'); b('wait', '#customize[open]'); trap('#customize'); b('press', 'Escape'); assert.equal(active(), 'Personalizar seu espaço'); });
check('Search shortcut focus results Enter Turbo and empty status', () => {
  open('/'); ev('window.__f4Turbo=0;document.addEventListener("turbo:load",()=>window.__f4Turbo++);true');
  b('press', 'Control+k'); b('wait', '#search[open]'); assert.equal(active(), 'command-search');
  b('fill', '#command-search', 'zzzinexistenteQA'); wait('!document.querySelector("[data-search-empty]").hidden&&document.querySelector("[data-search-empty]").getAttribute("aria-busy")!=="true"');
  const role = ev('document.querySelector("[data-search-empty]").getAttribute("role")');
  writeFileSync(resolve(evidence, 'empty-search-status.json'), JSON.stringify({ role, text: ev('document.querySelector("[data-search-empty]").textContent') }) + '\n');
  assert.equal(role, 'status', 'Dynamic no-results message must be an accessible status');
  b('fill', '#command-search', 'Projetos'); b('press', 'ArrowDown'); b('press', 'Enter'); ready();
  assert.equal(ev('location.pathname'), '/projects'); assert.ok(ev('window.__f4Turbo') >= 1);
});
check('Project tabs arrows Home End preserve focus after Turbo', () => {
  open('/projects/' + ids.project); b('focus', '#space-tab-overview'); b('press', 'ArrowRight'); ready(); wait('document.activeElement.id==="space-tab-tasks"');
  b('press', 'End'); ready(); wait('document.activeElement.id==="space-tab-references"'); b('press', 'Home'); ready(); wait('document.activeElement.id==="space-tab-overview"');
});
check('Pomodoro preset dialog trap Escape focus and no clock live region', () => {
  open('/apps/focus'); wait('!document.querySelector("[data-focus-preset]").disabled'); b('focus', '[data-focus-preset]'); b('press', 'Space'); b('wait', '.focus-dialog[open]'); trap('.focus-dialog'); b('press', 'Escape');
  assert.equal(ev('document.activeElement.hasAttribute("data-focus-preset")'), true);
  assert.equal(ev('document.querySelector("[data-focus-clock]").closest("[aria-live], [role=status]")'), null);
});
check('All interactive controls named and selected states present', () => {
  open('/apps/settings'); const axe = b('a11y');
  assert.equal(axe.violations.filter(v => ['button-name', 'link-name', 'label', 'select-name', 'aria-valid-attr-value'].includes(v.id)).length, 0);
  assert.equal(ev('document.querySelector(".rail [aria-current=page]").getAttribute("aria-label")'), 'Configurações');
});
check('Validation error preserved and exposed as alert', () => {
  open('/projects'); click('#project-new'); b('wait', '[data-controller=project-form][open]'); b('fill', '#project-name', 'Projeto foco QA');
  b('focus', '#project-form [type=submit]'); b('press', 'Enter'); wait('document.querySelector("#project-form [role=alert]").textContent.trim().length>0');
  assert.equal(ev('document.querySelector("#project-name").value'), 'Projeto foco QA'); assert.equal(ev('document.querySelector("dialog:modal").contains(document.activeElement)'), true);
  writeFileSync(resolve(evidence, 'validation-error-axe.json'), JSON.stringify(b('a11y'), null, 2) + '\n');
  b('screenshot', resolve(evidence, 'validation-error.png')); b('press', 'Escape');
});
for (const kind of ['project', 'task', 'reference']) check(kind + ' delayed error does not steal a newly moved focus', () => {
  open(kind === 'project' ? '/projects' : kind === 'task' ? '/tasks' : '/projects/' + ids.project + '?tab=references');
  click(kind === 'project' ? '#project-new' : kind === 'task' ? '#task-new-top' : '#reference-new'); b('wait', 'dialog[open]');
  if (kind === 'project') b('fill', '#project-name', 'Projeto foco QA');
  if (kind === 'task') { ev('document.querySelector("#task-title").removeAttribute("maxlength");true'); b('fill', '#task-title', 'X'.repeat(121)); }
  if (kind === 'reference') { b('fill', '#reference-title', 'Referência inválida QA'); b('fill', '#reference-url', 'https://user:pass@example.test'); }
  ev('window.__f4Fetch=fetch;window.__f4Held=false;window.fetch=async(url,options)=>{const response=await window.__f4Fetch(url,options);if(options?.method==="POST"){window.__f4Held=true;return new Promise(resolve=>window.__f4Release=()=>resolve(response))}return response};true');
  try {
    b('focus', '#' + kind + '-form [type=submit]'); b('press', 'Enter'); wait('window.__f4Held');
    b('focus', '#' + kind + (kind === 'project' ? '-name' : '-title'));
    ev('window.__f4Release();true'); wait('document.querySelector("dialog[open] [role=alert]").textContent.trim().length>0&&!document.querySelector("dialog[open] [type=submit]").disabled');
    assert.equal(active(), kind + (kind === 'project' ? '-name' : '-title'));
  } finally { ev('window.fetch=window.__f4Fetch;true'); b('press', 'Escape'); }
});
writeFileSync(resolve(evidence, 'console-errors.json'), JSON.stringify(b('errors'), null, 2) + '\n');
b('close');
if (results.some(r => r.status !== 'PASS')) process.exitCode = 1;
