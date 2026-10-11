// Isolated synthetic QA; credentials never leave the ignored local file.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root = resolve(import.meta.dirname, '../..');
const output = resolve(root, 'tmp/p11-verification');
const evidence = resolve(root, 'docs/assets/p1.1');
const credentials = JSON.parse(readFileSync(resolve(root, 'rails/tmp/p11-browser-credentials.json')));
const session = `accio-p11-additional-${process.pid}`;
const results = [];
function b(...args) {
  const response = JSON.parse(execFileSync('agent-browser', ['--session', session, '--json', ...args], { encoding: 'utf8', timeout: 45000, env: { ...process.env, XDG_RUNTIME_DIR: '/tmp' } }));
  assert.ok(response.success, JSON.stringify(response));
  return response.data;
}
const evaluate = source => b('eval', '-b', Buffer.from(source).toString('base64')).result;
const ready = () => b('wait', '--fn', "document.querySelector('[data-ready=true]')?.dataset.page === (location.pathname.split('/')[2] || 'home') && !document.documentElement.hasAttribute('aria-busy')");
const saved = () => b('wait', '--fn', "document.querySelector('[data-save-status]').hidden");
const shot = name => b('screenshot', resolve(evidence, `${name}.png`));
const audit = name => writeFileSync(resolve(output, `axe-${name}.json`), JSON.stringify(b('a11y', '--json'), null, 2));
function scenario(name, check) { check(); results.push({ name, result: 'PASS' }); writeFileSync(resolve(output, 'additional-results.json'), JSON.stringify(results, null, 2)); console.log(`PASS ${name}`); }
function drawer() { b('click', '.headbar [data-open=customize]'); b('wait', '#customize[open]'); }
function theme(value) { drawer(); b('select', '#drawer-theme', value); saved(); b('press', 'Escape'); }
try {
  b('--args', '--no-sandbox', 'open', 'http://127.0.0.1:3111/');
  b('wait', '#email_address');
  b('set', 'viewport', '320', '1000');
  audit('login-dark-320'); shot('login-dark-320');
  b('fill', '#email_address', credentials.email); b('fill', '#password', credentials.password); b('click', 'input[type=submit]'); ready();
  writeFileSync(resolve(output, 'browser-environment.json'), JSON.stringify(evaluate('({userAgent:navigator.userAgent,locale:navigator.language})'), null, 2));
  b('set', 'viewport', '1440', '1000');
  scenario('Arraste real do Dock e widgets, tamanho e persistência', () => {
    b('click', '[data-edit]');
    b('drag', '[data-dock=calendar]', '[data-dock=tasks]'); saved();
    assert.equal(evaluate('document.querySelector(".app-dock").firstElementChild.dataset.dock'), 'calendar');
    b('drag', '[data-widget=focus]', '[data-widget=tasks]'); saved();
    assert.equal(evaluate('document.querySelector("#widget-grid").firstElementChild.dataset.widget'), 'focus');
    b('click', '[data-zoom=tasks]'); saved();
    assert.ok(evaluate('document.querySelector("[data-widget=tasks]").classList.contains("span-6")'));
    b('click', '[data-edit]'); b('reload'); ready();
    assert.equal(evaluate('document.querySelector("#widget-grid").firstElementChild.dataset.widget'), 'focus');
    drawer(); b('click', '#customize [data-reset-widgets]'); saved();
    b('click', '#customize [data-order=dock][data-id=tasks][data-direction="-1"]'); saved();
    b('press', 'Escape');
  });
  scenario('Todos os fundos e foco após reordenação por teclado', () => {
    drawer();
    for (const wallpaper of ['ember', 'ocean', 'graphite', 'northern']) {
      b('click', `#customize [data-wallpaper=${wallpaper}]`); saved();
      assert.equal(evaluate('document.documentElement.dataset.wallpaper'), wallpaper);
    }
    b('focus', '#customize [data-order=widgets][data-id=focus][data-direction="-1"]'); b('press', 'Enter'); saved();
    assert.equal(evaluate('document.activeElement.dataset.id'), 'focus');
    b('click', '#customize [data-reset-widgets]'); saved(); b('press', 'Escape');
    assert.equal(evaluate('document.activeElement.dataset.open'), 'customize');
  });
  for (const value of ['dark', 'light']) {
    theme(value);
    scenario(`Busca ${value}: Meta K, região, Tab e fechamento pelo fundo`, () => {
      b('press', 'Meta+k'); b('wait', '#search[open]');
      assert.equal(evaluate('document.activeElement.id'), 'command-search');
      b('press', 'Shift+Tab'); assert.equal(evaluate('document.activeElement.dataset.searchResult'), 'E-mails');
      b('press', 'Tab'); assert.equal(evaluate('document.activeElement.id'), 'command-search');
      shot(`search-${value}-1440`); audit(`search-${value}-1440`);
      b('mouse', 'move', '10', '900'); b('mouse', 'down'); b('mouse', 'up');
      b('wait', '--fn', "!document.querySelector('#search').open");
      assert.equal(evaluate('document.activeElement.dataset.open'), 'search');
    });
    b('click', '.rail-bottom a'); b('wait', '#page-theme'); ready();
    for (const width of [320, 390, 768, 1440, 1920]) {
      b('set', 'viewport', String(width), '1000');
      scenario(`Configurações ${value} ${width}px`, () => {
        const dimensions = evaluate('({body:document.body.scrollWidth,width:innerWidth,main:document.querySelector("main").scrollWidth,client:document.querySelector("main").clientWidth,title:document.querySelector("main h1").getBoundingClientRect().width})');
        assert.ok(dimensions.body <= width + 1); assert.ok(dimensions.main <= dimensions.client + 1);
        shot(`settings-${value}-${width}`); audit(`settings-${value}-${width}`);
      });
    }
    b('click', '.rail-icons a[href="/"]'); ready(); b('set', 'viewport', '1440', '1000');
  }
  scenario('Login preserva tema claro depois do logout', () => {
    b('click', 'button[aria-label="Sair da conta local"]'); b('wait', '#email_address');
    assert.equal(evaluate('document.documentElement.dataset.theme'), 'light');
    b('set', 'viewport', '320', '1000'); audit('login-light-320'); shot('login-light-320');
  });
  console.log(`${results.length} cenários adicionais PASS`);
} finally { b('close'); }
