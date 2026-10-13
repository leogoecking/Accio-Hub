// Synthetic QA only. No browser profile, personal data or P0.4 storage is imported.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const workspace=readFileSync(resolve(root,'rails/tmp/p12d-workspace'),'utf8').trim();
const credentials=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8'));
const output=resolve(process.env.ACCIO_QA_OUTPUT || resolve(root,'tmp/p12d-verification'));mkdirSync(output,{recursive:true});
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,'docs/assets/p1.2d1'));mkdirSync(evidence,{recursive:true});
const session=process.env.ACCIO_QA_SESSION || `accio-p12d-${process.pid}`;
const origin=process.env.ACCIO_QA_URL || 'http://127.0.0.1:3124';
assert.ok(['127.0.0.1','localhost'].includes(new URL(origin).hostname));
const args=['--session',session,'--json'];
const results=[];
const init=resolve(output,'init.js');writeFileSync(init,'window.__qaErrors=[];window.addEventListener("error",e=>window.__qaErrors.push(e.message));window.addEventListener("unhandledrejection",e=>window.__qaErrors.push(String(e.reason?.stack || e.reason)));');
function b(...cmd){const result=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(result.success,true,JSON.stringify(result));return result.data;}
const evaluate=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(r.success,true);return r.data.result;};
const enterPassword=()=>evaluate('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';document.querySelector("#password").dispatchEvent(new Event("input",{bubbles:true}));true');
const ready=()=>b('wait','--fn',"document.querySelector('[data-controller=studio][data-ready=true]')?.dataset.page === (location.pathname.startsWith('/projects') ? 'projects' : (location.pathname.split('/')[2] || 'home')) && !document.documentElement.hasAttribute('data-turbo-preview') && !document.documentElement.hasAttribute('aria-busy')");
const saved=()=>b('wait','--fn',"document.querySelector('[data-save-status]').hidden");
const screenshot=name=>b('screenshot',resolve(evidence,`${name}.png`));
function scenario(name,check){check();assert.deepEqual(evaluate('window.__qaErrors || []'),[]);results.push({name,result:'PASS'});writeFileSync(resolve(output,'results.json'),JSON.stringify(results,null,2));console.log(`PASS ${name}`);}
const click=selector=>{
 b('snapshot','-i');b('scrollintoview',selector);
 evaluate('window.__qaStablePoint=null;true');
 b('wait','--fn',`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return false;const r=el.getBoundingClientRect(),key=[r.left,r.top,r.width,r.height].join('|'),old=window.__qaStablePoint;window.__qaStablePoint=key;return old===key && el.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()`);
 b('snapshot','-i');b('click',selector);
};
function nav(page){const path=page==='home'?'/':page==='projects'?'/projects':'/apps/'+page;click(`.rail-icons a[href='${path}']`);b('wait','--url',origin+path);ready();}
function drawer(){click('[data-open=customize]');b('wait','#customize[open]');}
function preference(selector,value){b('select',selector,value);saved();}

const formOpen = () => {click('#project-new');b('wait','[data-project-dialog][open]');};
const formDone = () => b('wait','--fn',"!document.querySelector('[data-project-dialog][open]') && document.querySelector('.project-card')");
const firstCard = () => '.project-card:first-child';
const action = operation => {click(`${firstCard()} [name=operation][value=${operation}] ~ button[type=submit]`);b('wait','--fn',"!document.querySelector('.project-command button[disabled]')");};
let projectPath;
try {
 b('--args','--no-sandbox','--init-script',init,'open',origin);b('set','viewport','1440','1000');b('wait','#email_address');
 b('fill','#email_address',credentials.email);enterPassword();click('input[type=submit]');ready();saved();nav('projects');
 scenario('Biblioteca apresenta registros reais sem fixtures da P0.4',()=>{assert.ok(!evaluate('document.querySelector(".project-library").innerText').includes('AccioCAD'));});
 scenario('Formulário: foco inicial, Tab/Shift Tab, Escape, X e cancelar',()=>{
  formOpen();assert.equal(evaluate('document.activeElement.id'),'project-name');
  evaluate("document.querySelector('[data-project-dialog] [type=submit]').focus()");b('press','Tab');assert.equal(evaluate('document.activeElement.getAttribute("aria-label")'),'Fechar formulário de projeto');b('press','Shift+Tab');assert.equal(evaluate('document.activeElement.type'),'submit');
  b('press','Escape');b('wait','--fn',"document.activeElement.id === 'project-new'");
  formOpen();click('[aria-label="Fechar formulário de projeto"]');b('wait','--fn',"document.activeElement.id === 'project-new'");
  formOpen();click('[data-project-dialog] .project-form-actions button[type=button]');b('wait','--fn',"document.activeElement.id === 'project-new'");
 });
 scenario('Criação com resposta perdida confirma retentativa sem duplicação',()=>{
  formOpen();b('fill','#project-name','Projeto Navegador QA');b('fill','#project-description','Café, organização e testes sintéticos');b('select','#project-icon','book');b('fill','#project-color-hex','#af9cf8');
  evaluate("window.__fetch = window.fetch;window.fetch = async (...args) => {const response=await window.__fetch(...args);if(args[0].endsWith('/projects') && args[1]?.method === 'POST'){window.fetch=window.__fetch;throw new Error('Resposta perdida após commit sintético')}return response}");
  click('#project-form [type=submit]');b('wait','--fn',"document.querySelector('[data-project-dialog] [data-project-notice]').textContent.includes('Resposta perdida')");
  assert.equal(evaluate('document.querySelector("#project-name").value'),'Projeto Navegador QA');screenshot('lost-response-draft');
  click('#project-form [type=submit]');formDone();b('wait','--fn',"document.activeElement.id === 'project-new'");
  assert.equal(evaluate("Array.from(document.querySelectorAll('.project-card h2')).filter(e=>e.textContent.includes('Projeto Navegador QA')).length"),1);
 });
 scenario('Pesquisa insensível a acentos, estados vazios e ordenação',()=>{
  b('fill','#project-search','zzzinexistente');b('press','Enter');b('wait','.project-empty');assert.match(evaluate('document.querySelector(".project-empty").textContent'),/Nenhum resultado/);
  b('fill','#project-search','cafe');b('press','Enter');b('wait','.project-card');assert.match(evaluate('document.querySelector(".project-card").textContent'),/Café/);
  b('fill','#project-search','Navegador');b('press','Enter');b('wait','--fn',"document.querySelectorAll('.project-card').length===1");b('select','#project-order','recent');b('wait','--fn',"document.activeElement.id==='project-order'");
 });
 projectPath=evaluate('document.querySelector(".project-space-link").getAttribute("href")');
 scenario('Edição preserva UID, campos e apresenta conflitos entre abas',()=>{
  const first=b('tab','list').tabs.find(t=>t.active).tabId;
  const editSelector=firstCard()+' a[data-project-opener]';click(editSelector);b('wait','[data-project-dialog][open]');b('fill','#project-name','Projeto Navegador QA local');
  b('tab','new',origin+projectPath);ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;click('a[data-project-opener]');b('wait','[data-project-dialog][open]');b('fill','#project-description','Versão remota sintética');click('#project-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-project-dialog][open]')");
  b('tab',first);click('#project-form [type=submit]');b('wait','[data-project-reapply]:not([hidden])');assert.equal(evaluate('document.querySelector("#project-name").value'),'Projeto Navegador QA local');screenshot('edit-conflict');
  click('[data-project-dialog] [data-project-reapply]');formDone();assert.equal(evaluate('document.querySelector(".project-space-link").getAttribute("href")'),projectPath);b('tab','close',second);
 });
 scenario('Favoritos, pausa, arquivamento somente leitura e restauração',()=>{
  action('favorite');assert.equal(evaluate('document.querySelector(".project-favorite").getAttribute("aria-pressed")'),'true');
  click('#project-favorites');b('wait','--fn',"document.querySelector('#project-favorites').getAttribute('aria-pressed')==='true'");action('status');b('wait','.status-paused');action('archive');b('wait','.is-archived');
  assert.equal(evaluate('document.querySelectorAll(".is-archived [data-project-opener],.is-archived .project-favorite").length'),0);screenshot('archived-library');
  click('.project-space-link');b('wait','.space-archive');assert.equal(evaluate('document.querySelectorAll(".project-space [data-project-opener]").length'),0);
  click('.space-back');ready();b('wait','.is-archived');action('restore');b('wait','.status-paused');action('status');b('wait','.status-active');click('#project-favorites');b('wait','--fn',"document.querySelector('#project-favorites').getAttribute('aria-pressed')==='false'");
 });
 scenario('Filtros versus aparência em abas distintas não sobrescrevem configurações',()=>{
  const first=b('tab','list').tabs.find(t=>t.active).tabId;const old=evaluate('document.documentElement.dataset.theme');
  b('tab','new',origin);ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;drawer();preference('#drawer-theme',old==='light'?'dark':'light');b('press','Escape');
  b('tab',first);click('#project-filter-active');b('wait','--fn',"document.querySelector('.project-feedback').textContent.includes('Outra aba')");assert.match(evaluate('document.querySelector(".project-feedback").textContent'),/mantida/);screenshot('filter-appearance-conflict');click('.project-feedback button');b('wait','--fn',"document.querySelector('#project-filter-active').getAttribute('aria-pressed')==='true'");assert.equal(evaluate('document.documentElement.dataset.theme'),old==='light'?'dark':'light');
  drawer();evaluate('document.querySelector("#drawer-accent").value="#a78bfa";document.querySelector("#drawer-accent").dispatchEvent(new Event("change",{bubbles:true}))');saved();b('press','Escape');b('reload');ready();assert.equal(evaluate('document.documentElement.dataset.theme'),old==='light'?'dark':'light');click('#project-filter-all');b('wait','--fn',"document.querySelector('#project-filter-all').getAttribute('aria-pressed')==='true'");b('tab','close',second);
 });
 scenario('Espaço real: abas por teclado e escopo de tarefas referências Vault e foco',()=>{
  click('.project-space-link');b('wait','#space-title');click('#space-tab-tasks');b('wait','--fn',"document.querySelector('#space-tab-tasks').getAttribute('aria-selected')==='true' && document.activeElement.id==='space-tab-tasks'");assert.match(evaluate('document.querySelector("#space-content").innerText'),/Nenhuma tarefa/);
  b('press','ArrowRight');b('wait','--fn',"document.activeElement.id==='space-tab-knowledge'");assert.match(evaluate('document.querySelector("#space-content").innerText'),/P1.3/);b('press','End');b('wait','--fn',"document.activeElement.id==='space-tab-references'");assert.match(evaluate('document.querySelector("#space-content").innerText'),/P1.2D3/);b('press','Home');b('wait','--fn',"document.activeElement.id==='space-tab-overview'");
  click('[data-demo=focus]');b('wait','#demo[open]');assert.match(evaluate('document.querySelector("[data-demo-message]").textContent'),/referência visual/);b('press','Escape');
 });
 scenario('Navegação Turbo, dashboard e recarga usam o mesmo projeto',()=>{
  evaluate('window.__turboMarker="persistent"');nav('home');assert.equal(evaluate('window.__turboMarker'),'persistent');assert.match(evaluate('document.querySelector(".project-strip").innerText'),/Navegador QA local/);click('.project-strip a.mini-project:last-of-type');b('wait','#space-title');b('reload');ready();assert.match(evaluate('document.querySelector("#space-title").innerText'),/Navegador/);
 });
 for(const theme of ['dark','light']) {
  drawer();preference('#drawer-theme',theme);b('press','Escape');
  for(const width of [320,390,768,1440,1920]) {
   b('set','viewport',String(width),'1000');nav('projects');
   scenario(`Biblioteca ${theme} ${width}px`,()=>{const metrics=evaluate("({body:document.body.scrollWidth,width:innerWidth,main:document.querySelector('main').scrollWidth,client:document.querySelector('main').clientWidth})");assert.ok(metrics.body<=width+1 && metrics.main<=metrics.client+1,JSON.stringify(metrics));screenshot(`library-${theme}-${width}`);});
   writeFileSync(resolve(evidence,`axe-library-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));
   formOpen();screenshot(`form-${theme}-${width}`);writeFileSync(resolve(evidence,`axe-form-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));assert.equal(evaluate('document.querySelector("[data-project-dialog]").scrollWidth > document.querySelector("[data-project-dialog]").clientWidth'),false);b('press','Escape');
   click('.project-space-link');b('wait','#space-title');
   scenario(`Espaço ${theme} ${width}px`,()=>{const m=evaluate("({body:document.body.scrollWidth,width:innerWidth,main:document.querySelector('main').scrollWidth,client:document.querySelector('main').clientWidth})");assert.ok(m.body<=width+1 && m.main<=m.client+1,JSON.stringify(m));screenshot(`space-${theme}-${width}`);});
   writeFileSync(resolve(evidence,`axe-space-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));
  }
 }
 writeFileSync(resolve(evidence,'d1-browser-results.json'),JSON.stringify(results,null,2));console.log(`${results.length} cenários D1 PASS`);
} catch(error) {screenshot('failure');console.log('UI',evaluate('document.body.innerText'));throw error} finally {b('close')}
