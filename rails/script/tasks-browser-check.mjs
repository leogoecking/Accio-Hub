// Synthetic QA only. No browser profile, personal data or P0.4 storage is imported.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const workspace=readFileSync(resolve(root,'rails/tmp/p12d2-workspace'),'utf8').trim();
const credentials=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8'));
const output=resolve(process.env.ACCIO_QA_OUTPUT || resolve(root,'tmp/p12d2-verification'));mkdirSync(output,{recursive:true});
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,'docs/assets/p1.2d2'));mkdirSync(evidence,{recursive:true});
const session=process.env.ACCIO_QA_SESSION || `accio-p12d2-${process.pid}`;
const origin=process.env.ACCIO_QA_URL || 'http://127.0.0.1:3125';
assert.ok(['127.0.0.1','localhost'].includes(new URL(origin).hostname));
const args=['--session',session,'--json'];
const resume=Number(process.env.ACCIO_QA_RESUME || 0);let scenarioIndex=0;
const results=resume?JSON.parse(readFileSync(resolve(output,'results.json'),'utf8')).slice(0,resume):[];
const init=resolve(output,'init.js');writeFileSync(init,'window.__qaErrors=[];window.addEventListener("error",e=>window.__qaErrors.push(e.message));window.addEventListener("unhandledrejection",e=>window.__qaErrors.push(String(e.reason?.stack || e.reason)));');
function b(...cmd){const result=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(result.success,true,JSON.stringify(result));return result.data;}
const evaluate=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(r.success,true);return r.data.result;};
const enterPassword=()=>evaluate('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';document.querySelector("#password").dispatchEvent(new Event("input",{bubbles:true}));true');
const ready=()=>b('wait','--fn',"document.querySelector('[data-controller=studio][data-ready=true]')?.dataset.page === (location.pathname.startsWith('/projects') ? 'projects' : location.pathname.startsWith('/tasks') ? 'tasks' : (location.pathname.split('/')[2] || 'home')) && !document.documentElement.hasAttribute('data-turbo-preview') && !document.documentElement.hasAttribute('aria-busy')");
const saved=()=>b('wait','--fn',"document.querySelector('[data-save-status]').hidden");
const screenshot=name=>b('screenshot',resolve(evidence,`${name}.png`));
function scenario(name,check){if(scenarioIndex++<resume)return;check();assert.deepEqual(evaluate('window.__qaErrors || []'),[]);results.push({name,result:'PASS'});writeFileSync(resolve(output,'results.json'),JSON.stringify(results,null,2));console.log(`PASS ${name}`);}
const click=selector=>{
 b('snapshot','-i');b('scrollintoview',selector);
 evaluate('window.__qaStablePoint=null;true');
 b('wait','--fn',`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return false;const r=el.getBoundingClientRect(),key=[r.left,r.top,r.width,r.height].join('|'),old=window.__qaStablePoint;window.__qaStablePoint=key;return old===key && el.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()`);
 b('snapshot','-i');if(selector.startsWith('#task-check-')){b('focus',selector);b('press','Space');}else b('click',selector);
};
function nav(page){const path=page==='home'?'/':page==='projects'?'/projects':page==='tasks'?'/tasks':'/apps/'+page;click(`.rail-icons a[href='${path}']`);b('wait','--url',origin+path);ready();}
function drawer(){click('[data-open=customize]');b('wait','#customize[open]');}
function preference(selector,value){b('select',selector,value);saved();}

const formOpen=(selector='#task-new')=>{click(selector);b('wait','[data-task-dialog][open]');};
const formClose=()=>{b('press','Escape');b('wait','--fn',"!document.querySelector('[data-task-dialog][open]')");};
const submit=()=>{click('#task-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-task-dialog][open]')");};
const taskToken=title=>evaluate(`Array.from(document.querySelectorAll('[data-task-uid]')).find(el=>el.querySelector('.task-name').firstChild.textContent===${JSON.stringify(title)})?.dataset.taskUid`);
const newProject=name=>{nav('projects');click('#project-new');b('wait','[data-project-dialog][open]');b('fill','#project-name',name);click('#project-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-project-dialog][open]')");return evaluate(`Array.from(document.querySelectorAll('.project-card')).find(el=>el.innerText.includes(${JSON.stringify(name)})).querySelector('[data-project-opener]').pathname.split('/')[2]`);};
let personal, contextual, originProject, targetProject;
try {
 b('--args','--no-sandbox','--init-script',init,'open',origin);b('set','viewport','1440','1000');b('wait','#email_address');b('fill','#email_address',credentials.email);enterPassword();click('input[type=submit]');ready();saved();
 if(resume){nav('tasks');const state=JSON.parse(readFileSync(resolve(workspace,'browser-progress.json'),'utf8'));({personal,contextual,originProject,targetProject}=state);nav('home');}
 scenario('Dashboard e lista vazios sem tarefas fictícias',()=>{assert.equal(evaluate('document.querySelectorAll("[data-task-uid]").length'),0);assert.equal(evaluate('document.querySelector(".task-stat strong").textContent'),'00');nav('tasks');assert.match(evaluate('document.querySelector("#task-surface").innerText'),/Nenhuma tarefa/);});
 scenario('Diálogo inicial teclado Tab ShiftTab Escape X cancelar e foco',()=>{
  formOpen();assert.equal(evaluate('document.activeElement.id'),'task-title');
  click('#task-form [type=submit]');assert.equal(evaluate('!!document.querySelector("[data-task-dialog][open]")'),true);
  b('focus','#task-form [type=submit]');b('press','Tab');assert.equal(evaluate('document.activeElement.getAttribute("aria-label")'),'Fechar formulário de tarefa');b('press','Shift+Tab');assert.equal(evaluate('document.activeElement.type'),'submit');
  formClose();assert.equal(evaluate('document.activeElement.id'),'task-new');formOpen();click('[aria-label="Fechar formulário de tarefa"]');b('wait','--fn',"!document.querySelector('[data-task-dialog][open]')");assert.equal(evaluate('document.activeElement.id'),'task-new');formOpen();click('#task-form button[data-action="task-form#close"]:not(.mini-control)');b('wait','--fn',"!document.querySelector('[data-task-dialog][open]')");
 });
 scenario('Criação pessoal com resposta perdida retenta sem duplicar',()=>{
  formOpen();b('fill','#task-title','Preparar café QA');b('select','#task-priority','high');
  evaluate('window.__realFetch=fetch;window.__lose=true;window.fetch=async(url,options)=>{const response=await window.__realFetch(url,options);if(window.__lose && String(url).endsWith("/tasks") && options?.method==="POST"){window.__lose=false;throw new Error("Resposta perdida sintética")}return response};true');
  click('#task-form [type=submit]');b('wait','--fn',"document.querySelector('[data-task-dialog] [data-project-notice]').textContent.includes('perdida')");assert.equal(evaluate('document.querySelector("#task-title").value'),'Preparar café QA');screenshot('lost-response-draft');evaluate('window.fetch=window.__realFetch;true');submit();assert.equal(evaluate('document.querySelectorAll("[data-task-uid]").length'),1);personal=taskToken('Preparar café QA');assert.match(evaluate('document.querySelector(".task-name small").textContent'),/Pessoal/);
 });
 scenario('Projetos D1 criados e tarefa contextual vinculada pela rota',()=>{
  originProject=newProject('Origem tarefas QA');targetProject=newProject('Destino tarefas QA');
  click(`a[href='/projects/${originProject}']`);b('wait','#space-title');click('#space-tab-tasks');b('wait','--fn',"document.querySelector('#space-tab-tasks').getAttribute('aria-selected')==='true'");
  formOpen('#task-new-context');assert.equal(evaluate('document.querySelector("#task-project")'),null);b('fill','#task-title','Planejar projeto QA');submit();contextual=taskToken('Planejar projeto QA');assert.match(evaluate('document.querySelector(".task-name small").textContent'),/Origem tarefas QA/);
 });
 scenario('Mesmo UID na lista global no espaço e widget com contadores reais',()=>{
  nav('tasks');assert.ok(evaluate(`!!document.querySelector('[data-task-uid="${contextual}"]')`));assert.equal(evaluate('document.querySelectorAll("[data-task-uid]").length'),2);nav('home');assert.ok(evaluate(`!!document.querySelector('[data-task-uid="${contextual}"]')`));assert.equal(evaluate('document.querySelector(".task-stat strong").textContent'),'02');assert.match(evaluate('document.querySelector("#dashboard-projects").innerText'),/1 tarefa aberta/);
 });
 if(!resume)writeFileSync(resolve(workspace,'browser-progress.json'),JSON.stringify({personal,contextual,originProject,targetProject}));
 scenario('Conclusão no dashboard e reabertura global atualizam estado e contagens',()=>{
  b('wait','--fn',`!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#task-check-${contextual}').closest('form'),'task-command')`);click('#task-check-'+contextual);b('wait','--fn',"document.querySelector('.task-stat strong').textContent==='01'");assert.equal(evaluate(`!!document.querySelector('#task-check-${contextual}')`),false);nav('tasks');assert.equal(evaluate(`document.querySelector('#task-check-${contextual}').checked`),true);click('#task-check-'+contextual);b('wait','--fn',`document.querySelector('#task-check-${contextual}').checked===false && document.querySelector('#task-check-${contextual}').disabled===false`);b('wait','--fn',`document.activeElement.id==='task-check-${contextual}'`);assert.equal(evaluate('document.activeElement.id'),'task-check-'+contextual);
 });
 scenario('Editar título prioridade e mover entre projetos no editor global',()=>{
  formOpen('#task-edit-'+contextual);assert.equal(evaluate('document.querySelector("#task-title").value'),'Planejar projeto QA');b('fill','#task-title','Planejar atualizado QA');b('select','#task-priority','high');b('select','#task-project',targetProject);submit();assert.equal(taskToken('Planejar atualizado QA'),contextual);assert.match(evaluate(`document.querySelector('[data-task-uid="${contextual}"] small').textContent`),/Destino tarefas QA.*Alta/);
  nav('projects');click(`a[href='/projects/${originProject}']`);b('wait','#space-title');assert.equal(evaluate(`!!document.querySelector('[data-task-uid="${contextual}"]')`),false);nav('projects');click(`a[href='/projects/${targetProject}']`);b('wait','#space-title');assert.ok(evaluate(`!!document.querySelector('[data-task-uid="${contextual}"]')`));
 });
 scenario('Editor contextual preserva vínculo e nova tarefa não duplica listas',()=>{
  formOpen('#task-edit-'+contextual);assert.equal(evaluate('document.querySelector("#task-project")'),null);b('fill','#task-title','Planejar contextual QA');submit();assert.equal(taskToken('Planejar contextual QA'),contextual);nav('tasks');assert.equal(evaluate('document.querySelectorAll("[data-task-uid]").length'),2);
 });
 scenario('Conflito entre abas conserva campos e reaplicação exige ação explícita',()=>{
  const first=b('tab','list').tabs.find(t=>t.active).tabId;formOpen('#task-edit-'+personal);b('fill','#task-title','Edição local conservada QA');b('tab','new',origin+'/tasks');ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;formOpen('#task-edit-'+personal);b('fill','#task-title','Outra aba QA');submit();b('tab',first);click('#task-form [type=submit]');b('wait','[data-task-reapply]:not([hidden])');assert.equal(evaluate('document.querySelector("#task-title").value'),'Edição local conservada QA');screenshot('task-conflict');click('#task-form [data-task-reapply]');b('wait','--fn',"!document.querySelector('[data-task-dialog][open]')");assert.equal(taskToken('Edição local conservada QA'),personal);b('tab','close',second);
 });
 scenario('Contenção 503 e validação 422 preservam edição e intenção',()=>{
  formOpen('#task-edit-'+personal);b('fill','#task-title','Pessoal validada QA');
  evaluate('window.__realFetch=fetch;window.fetch=(url,options)=>String(url).includes("/tasks/")&&options?.method==="POST"?Promise.resolve(new Response(JSON.stringify({error:"database_busy",message:"Armazenamento ocupado; sua edição foi mantida."}),{status:503,headers:{"Content-Type":"application/json"}})):window.__realFetch(url,options);true');click('#task-form [type=submit]');b('wait','--fn',"document.querySelector('[data-task-dialog] [data-project-notice]').textContent.includes('ocupado')");assert.equal(evaluate('document.querySelector("#task-title").value'),'Pessoal validada QA');screenshot('task-busy-draft');evaluate('window.fetch=window.__realFetch;document.querySelector("#task-priority").add(new Option("Invalida","invalid"));true');b('select','#task-priority','invalid');click('#task-form [type=submit]');b('wait','--fn',"document.querySelector('[data-task-dialog] [data-project-notice]').textContent.includes('Priority')");assert.equal(evaluate('document.querySelector("#task-title").value'),'Pessoal validada QA');b('select','#task-priority','normal');submit();
 });
 scenario('Arquivamento entre abas bloqueia edição conclusão e retirada do projeto',()=>{
  formOpen('#task-edit-'+contextual);b('fill','#task-title','Não pode sobrescrever QA');const first=b('tab','list').tabs.find(t=>t.active).tabId;b('tab','new',origin+'/projects');ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;click('#project-archive-'+targetProject);b('wait','#project-restore-'+targetProject);b('tab',first);click('#task-form [type=submit]');b('wait','--fn',"document.querySelector('[data-task-dialog] [data-project-notice]').textContent.includes('arquivado')");assert.equal(evaluate('document.querySelector("#task-form [data-task-reapply]").hidden'),true);assert.equal(evaluate('document.querySelector("#task-title").value'),'Não pode sobrescrever QA');screenshot('archive-conflict');formClose();b('reload');ready();assert.equal(evaluate(`document.querySelector('#task-check-${contextual}').disabled`),true);assert.equal(evaluate(`!!document.querySelector('#task-edit-${contextual}')`),false);assert.match(evaluate(`document.querySelector('[data-task-uid="${contextual}"]').innerText`),/somente leitura/);b('tab',second);click('#project-restore-'+targetProject);b('wait','#project-archive-'+targetProject);b('tab',first);b('reload');ready();assert.equal(evaluate(`document.querySelector('#task-check-${contextual}').disabled`),false);b('tab','close',second);
 });
 scenario('Mover para Pessoal conserva UID e remove somente o vínculo',()=>{formOpen('#task-edit-'+contextual);b('select','#task-project','');submit();assert.equal(taskToken('Planejar contextual QA'),contextual);assert.match(evaluate(`document.querySelector('[data-task-uid="${contextual}"] small').textContent`),/Pessoal/);});
 scenario('Busca global pesquisa tarefa real navega e Escape retorna foco',()=>{
  b('press','Control+k');b('wait','#search[open]');b('fill','#command-search','Pessoal validada');b('wait','[data-task-search-results] a');assert.match(evaluate('document.querySelector("[data-task-search-results]").innerText'),/Pessoal validada QA/);b('press','Escape');assert.equal(evaluate('document.activeElement.dataset.open'),'search');b('press','Control+k');b('fill','#command-search','Pessoal validada');b('wait','[data-task-search-results] a');click('[data-task-search-results] a');b('wait','[data-task-dialog][open]');assert.equal(evaluate('document.querySelector("#task-title").value'),'Pessoal validada QA');formClose();b('wait','--fn',"location.search===''");assert.equal(new URL(evaluate('location.href')).search,'');
 });
 scenario('Endereço direto formulário mantém lista e cancelamento volta ao URL canônico',()=>{b('open',origin+'/tasks/new');b('wait','[data-task-dialog][open]');assert.ok(evaluate('!!document.querySelector("#task-surface")'));formClose();b('wait','--fn',"location.pathname+location.search==='/tasks'");assert.equal(evaluate('location.pathname+location.search'),'/tasks');});
 scenario('Recarga conserva tarefas sem duplicação e tema destaque preferências',()=>{drawer();preference('#drawer-theme','light');evaluate('document.querySelector("#drawer-accent").value="#a78bfa";document.querySelector("#drawer-accent").dispatchEvent(new Event("change",{bubbles:true}));true');saved();b('press','Escape');b('reload');ready();assert.equal(evaluate('document.documentElement.dataset.theme'),'light');assert.equal(evaluate('document.querySelectorAll("[data-task-uid]").length'),2);});
 scenario('Contexto com título longo conserva vínculo antes da matriz',()=>{nav('tasks');formOpen('#task-edit-'+contextual);b('fill','#task-title','Planejar contextual QA — conferir documentação e preservar relações em todas as telas e larguras');b('select','#task-project',targetProject);submit();});
 for(const theme of ['dark','light']) {
  drawer();preference('#drawer-theme',theme);b('press','Escape');
  for(const width of [320,390,768,1440,1920]) {
   b('set','viewport',String(width),'1000');nav('tasks');
   scenario(`Tarefas e formulário ${theme} ${width}px`,()=>{
    const m=evaluate("({body:document.body.scrollWidth,width:innerWidth,main:document.querySelector('main').scrollWidth,client:document.querySelector('main').clientWidth})");assert.ok(m.body<=width+1 && m.main<=m.client+1,JSON.stringify(m));screenshot(`tasks-${theme}-${width}`);writeFileSync(resolve(evidence,`axe-tasks-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));
    formOpen();screenshot(`form-${theme}-${width}`);assert.equal(evaluate('document.activeElement.id'),'task-title');assert.equal(evaluate('document.querySelector("[data-task-dialog]").scrollWidth>document.querySelector("[data-task-dialog]").clientWidth'),false);writeFileSync(resolve(evidence,`axe-form-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));formClose();
   });
   scenario(`Dashboard e espaço ${theme} ${width}px`,()=>{
    nav('home');screenshot(`dashboard-${theme}-${width}`);writeFileSync(resolve(evidence,`axe-dashboard-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));nav('projects');click(`a[href='/projects/${targetProject}']`);b('wait','#space-title');click('#space-tab-tasks');b('wait','--fn',"document.querySelector('#space-tab-tasks').getAttribute('aria-selected')==='true'");screenshot(`space-${theme}-${width}`);writeFileSync(resolve(evidence,`axe-space-${theme}-${width}.json`),JSON.stringify(b('a11y','--json'),null,2));
   });
  }
 }
 writeFileSync(resolve(workspace,'browser-state.json'),JSON.stringify({personal,contextual,originProject,targetProject}));
 writeFileSync(resolve(evidence,'d2-browser-results.json'),JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify({passed:results.length,session,workspace}));
} catch(error) { console.error(error.stack);try{screenshot('browser-failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')));}catch{}process.exitCode=1; }
finally { b('close'); }
