// QA real via agent-browser, somente em sessão própria e origem loopback.
// Execute com o servidor da RAIZ do repositório, não apenas de prototype/.
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {STATE_KEY} from '../state.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const origin=new URL(process.argv[2]??'http://127.0.0.1:4174');
assert.ok(['127.0.0.1','localhost'].includes(origin.hostname),'Somente loopback é permitido');
const evidence=resolve(root,'tmp/p04-projects-verification');mkdirSync(evidence,{recursive:true});
const baseline=resolve(root,'tmp/p04-baseline');mkdirSync(baseline,{recursive:true});
for(const file of ['index.html','style.css','app.js']) writeFileSync(resolve(baseline,file),execFileSync('git',['show',`0018bb4:prototype/${file}`],{cwd:root}));
const init=resolve(evidence,'init.js');
writeFileSync(init,`const NativeDate=Date;
window.Date=class extends NativeDate{constructor(...args){super(...(args.length?args:['2026-10-09T15:00:00Z']));}};
window.__qaErrors=[];window.addEventListener('error',e=>window.__qaErrors.push(e.message));
window.__failWrites=sessionStorage.getItem('accio-qa-fail-writes')==='yes';
const originalSetItem=Storage.prototype.setItem;
Storage.prototype.setItem=function(key,value){if(window.__failWrites&&this===localStorage)throw new DOMException('Synthetic quota failure','QuotaExceededError');return originalSetItem.call(this,key,value);};`);
const session=`accio-p04-projects-qa-${process.pid}`;
const env={...process.env,XDG_RUNTIME_DIR:'/tmp'};
const args=['--namespace','accio-p04','--session',session,'--json'];
if(process.env.ACCIO_BROWSER_NO_SANDBOX==='1')args.push('--args','--no-sandbox');
const results=[];
function browser(...command){
  const result=JSON.parse(execFileSync('agent-browser',[...args,...command],{env,encoding:'utf8',timeout:45000}));
  assert.equal(result.success,true,JSON.stringify(result));return result.data;
}
const evaluate=code=>browser('eval','-b',Buffer.from(code).toString('base64')).result;
const saved=()=>evaluate(`JSON.parse(localStorage.getItem(${JSON.stringify(STATE_KEY)}))`);
const raw=()=>evaluate(`localStorage.getItem(${JSON.stringify(STATE_KEY)})`);
function snap(name){writeFileSync(resolve(evidence,`${name}.json`),JSON.stringify(browser('snapshot','-i'),null,2));}
function capture(name){browser('screenshot',resolve(evidence,`${name}.png`));}
function current(){browser('open',new URL('/prototype/#/home',origin).href);browser('reload');browser('wait','.board');}
function seed(value){
  evaluate(`window.__failWrites=false;sessionStorage.removeItem('accio-qa-fail-writes');localStorage.clear();${value===null?'':`localStorage.setItem(${JSON.stringify(STATE_KEY)},${JSON.stringify(typeof value==='string'?value:JSON.stringify(value))});`}`);
  current();
}
function route(name){snap(`before-${name}`);browser('click',`${name==='settings'?'.rail-bottom':'.rail-icons'} [data-route="${name}"]`);browser('wait','--fn',`location.hash==='#/${name}'`);}
function scenario(name,check){check();assert.deepEqual(evaluate('window.__qaErrors'),[]);results.push({name,result:'PASS'});console.log(`PASS ${name}`);writeFileSync(resolve(evidence,'results.json'),JSON.stringify(results,null,2));}
const fixture=JSON.parse(readFileSync(new URL('./fixtures/legacy-p03.json',import.meta.url),'utf8'));
const geometry=()=>evaluate(`Array.from(document.querySelectorAll('.rail,.app-dock,.music-zone,[data-widget]')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {key:el.dataset.widget??el.className,x:r.x,y:r.y,width:r.width,height:r.height,font:s.fontFamily,color:s.color};})`);

const schema1=JSON.parse(readFileSync(new URL('./fixtures/schema-1.json',import.meta.url),'utf8'));
const project=id=>saved().projects.find(p=>p.id===id);
const cards=()=>evaluate('Array.from(document.querySelectorAll("[data-project-card]")).map(el=>el.dataset.projectCard)');
const clickAction=(action,id)=>browser('click',`[data-project-action="${action}"][data-project-id="${id}"]`);
const filter=value=>browser('click',`[data-project-filter="${value}"]`);
const submit=()=>browser('click','#project-form button[type="submit"]');
const focus=()=>evaluate('document.activeElement?.id||document.activeElement?.dataset.projectAction');
function auditDialog(name){
  const audit=browser('a11y','--selector','.project-dialog');
  writeFileSync(resolve(evidence,`post-audit-axe-${name}.json`),JSON.stringify(audit,null,2));
  // Contraste do eyebrow no tema claro é um achado anterior, fora das ISSUE-01/02.
  // Salvar a varredura completa e rejeitar qualquer outra violação.
  const unexpected=audit.violations.filter(v=>!(v.id==='color-contrast'&&v.nodes.every(n=>n.target.join()==='.block-top > div > .eyebrow')));
  assert.deepEqual(unexpected,[],JSON.stringify(unexpected));
}
try{
  browser('--init-script',init,'open',new URL('/prototype/',origin).href);browser('set','viewport','1440','1000');
  scenario('Pós-auditoria: concordância 0/1/3 e semântica do diálogo com axe-core',()=>{
    seed(schema1);
    const s=saved(),id=s.projects[0].id;
    s.tasks=s.tasks.filter(t=>t.projectId!==id);
    const labels=[];
    for(const count of [0,1,3]){
      const tasks=Array.from({length:count},(_,i)=>({...schema1.tasks[0],id:`qa-open-${i}`,projectId:id,done:false}));
      seed({...s,tasks:[...s.tasks,...tasks,{...schema1.tasks[0],id:'qa-done',projectId:id,done:true}]});
      labels.push(evaluate(`document.querySelector('[data-open-project="${id}"] small').textContent`));
    }
    route('projects');browser('click','[data-project-action="new"]');snap('post-audit-dialog');
    capture('post-audit-dialog');
    writeFileSync(resolve(evidence,'post-audit-dialog-geometry.json'),JSON.stringify(evaluate(`Array.from(document.querySelectorAll('.project-dialog,#project-form input,#project-form textarea,#project-form select,#project-form button')).map(el=>{const r=el.getBoundingClientRect();return {id:el.id,text:el.textContent,x:r.x,y:r.y,width:r.width,height:r.height};})`),null,2));
    auditDialog('create');
    writeFileSync(resolve(evidence,'post-audit-widget-labels.json'),JSON.stringify(labels,null,2));
    assert.deepEqual(labels,['0 tarefas abertas','1 tarefa aberta','3 tarefas abertas']);
    assert.equal(evaluate('document.querySelector("#project-form").getAttribute("role")'),null);
    assert.equal(evaluate('document.querySelector("[role=dialog][aria-modal=true]").contains(document.querySelector("#project-form"))'),true);
    browser('press','Escape');
  });
  scenario('Schema 1 real migra sem perda de dados e biblioteca mostra registros existentes',()=>{
    seed(schema1);assert.equal(saved().schemaVersion,2);assert.deepEqual(saved().tasks,schema1.tasks);assert.deepEqual(saved().notes,schema1.notes);assert.equal(evaluate(`localStorage.getItem(${JSON.stringify(STATE_KEY+':backup:pre-schema-2')})`),JSON.stringify(schema1));route('projects');assert.equal(cards().length,4);snap('library-migrated-light');capture('library-migrated-light');
  });
  scenario('Criação por formulário e persistência após recarga',()=>{
    browser('click','[data-project-action="new"]');assert.equal(focus(),'project-name');browser('fill','#project-name','Laboratório orbital');browser('fill','#project-description','Exploração de ideias e astronomia');browser('select','#project-icon','code');browser('fill','#project-color-hex','#799cdb');submit();
    const p=saved().projects.find(p=>p.name==='Laboratório orbital');assert.match(p.id,/^[0-9a-f-]{36}$/);assert.equal(p.color,'#799cdb');assert.equal(p.icon,'code');assert.equal(cards().length,5);browser('reload');browser('wait','[data-project-card]');assert.deepEqual(project(p.id),p);
  });
  scenario('Duplicação acidental bloqueada e formulário recuperável',()=>{
    const before=saved().projects;browser('click','[data-project-action="new"]');browser('fill','#project-name',' LABORATÓRIO   ORBITAL ');submit();assert.match(evaluate('document.querySelector("#project-form-error").textContent'),/Já existe/);assert.deepEqual(saved().projects,before);browser('press','Escape');assert.equal(focus(),'new');
  });
  scenario('Editar e renomear mantém IDs, tarefas e notas vinculadas',()=>{
    const before=saved();clickAction('edit','project-accio-hub');browser('fill','#project-name','Hub renovado');browser('fill','#project-description','Meu espaço de ideias');browser('select','#project-icon','target');submit();assert.equal(project('project-accio-hub').name,'Hub renovado');assert.deepEqual(saved().tasks,before.tasks);assert.deepEqual(saved().notes,before.notes);assert.match(evaluate(`document.querySelector('[data-project-card="project-accio-hub"] .project-relations').innerText`),/1\s+aberta\s+1\s+nota/);browser('reload');browser('wait','[data-project-card]');assert.equal(project('project-accio-hub').name,'Hub renovado');
  });
  scenario('Pesquisa por nome/descrição, sem resultados e foco preservado',()=>{
    browser('fill','#project-search','astronomia');assert.equal(cards().length,1);assert.equal(focus(),'project-search');browser('fill','#project-search','HUB RENOVADO');assert.deepEqual(cards(),['project-accio-hub']);browser('fill','#project-search','inexistente');assert.equal(cards().length,0);assert.match(evaluate('document.querySelector(".project-empty").innerText'),/Nenhum projeto/);browser('click','[data-project-action="clear"]');assert.equal(cards().length,5);
  });
  scenario('Favoritos, ordenação e preferências persistentes',()=>{
    clickAction('favorite','project-accio-hub');browser('click','[data-project-action="favorites"]');assert.deepEqual(cards(),['project-accio-hub']);browser('select','#project-sort','recent');browser('reload');browser('wait','[data-project-card]');assert.deepEqual(cards(),['project-accio-hub']);assert.deepEqual(saved().projectLibrary,{status:'all',sort:'recent',favoritesOnly:true});clickAction('favorite','project-accio-hub');assert.equal(cards().length,0);browser('click','[data-project-action="favorites"]');assert.equal(cards()[0],'project-accio-hub');browser('select','#project-sort','name');assert.deepEqual(cards(),saved().projects.slice().sort((a,b)=>a.name.localeCompare(b.name,'pt-BR',{sensitivity:'base',numeric:true})).map(p=>p.id));
  });
  scenario('Pausar, arquivar e restaurar preserva dados e status anterior',()=>{
    const before=saved();clickAction('pause','project-accio-hub');filter('active');assert.ok(!cards().includes('project-accio-hub'));filter('paused');assert.deepEqual(cards(),['project-accio-hub']);clickAction('archive','project-accio-hub');assert.equal(cards().length,0);filter('archived');assert.deepEqual(cards(),['project-accio-hub']);assert.deepEqual(saved().tasks,before.tasks);assert.deepEqual(saved().notes,before.notes);browser('reload');browser('wait','[data-project-card]');assert.equal(project('project-accio-hub').status,'archived');clickAction('restore','project-accio-hub');assert.equal(project('project-accio-hub').status,'paused');filter('paused');clickAction('activate','project-accio-hub');filter('all');
  });
  scenario('Widgets, contagens por ID e preferências da P0.3 preservadas',()=>{
    const s=saved();for(const key of ['theme','wallpaper','accent','density','music','musicExpanded','widgets','dockOrder','dockHidden'])assert.deepEqual(s[key],schema1[key],key);
    route('home');assert.match(evaluate('document.querySelector(".project-strip").innerText'),/Hub renovado\s+1 tarefa/);route('projects');clickAction('archive','project-accio-hub');route('home');assert.ok(!evaluate('document.querySelector(".project-strip").innerText').includes('Hub renovado'));browser('click','[data-open-project="project-accio-cad"]');assert.equal(saved().projectLibrary.status,'all');assert.equal(saved().projectLibrary.favoritesOnly,false);assert.equal(focus(),'edit');filter('archived');clickAction('restore','project-accio-hub');filter('all');
  });
  scenario('Teclado: Tab/Shift Tab, Escape e retorno de foco',()=>{
    browser('click','[data-project-action="new"]');browser('press','Shift+Tab');assert.equal(focus(),'close');browser('press','Shift+Tab');assert.equal(evaluate('document.activeElement.type'),'submit');browser('press','Tab');assert.equal(focus(),'close');browser('press','Escape');assert.equal(focus(),'new');browser('press','Enter');assert.equal(focus(),'project-name');browser('press','Control+k');assert.equal(evaluate('document.querySelectorAll(".search-modal").length'),0);browser('press','Escape');
  });
  scenario('Biblioteca vazia e criação explícita sem demonstrações adicionais',()=>{
    seed({...schema1,projects:[],tasks:[],notes:[],projectId:null});route('projects');assert.equal(cards().length,0);assert.match(evaluate('document.querySelector(".project-empty").innerText'),/Seu próximo projeto/);capture('library-empty');browser('click','[data-project-action="new"]');browser('fill','#project-name','Primeiro espaço');submit();assert.equal(saved().projects.length,1);assert.deepEqual(saved().tasks,[]);assert.deepEqual(saved().notes,[]);
  });
  scenario('Falha de gravação informa que projeto não foi persistido',()=>{
    const before=raw();evaluate('window.__failWrites=true');browser('click','[data-project-action="new"]');browser('fill','#project-name','Somente em memória');submit();assert.equal(raw(),before);assert.match(evaluate('document.querySelector("#project-feedback").textContent'),/não foi persistida/);assert.equal(cards().length,2);capture('library-write-failure');evaluate('window.__failWrites=false');const id=evaluate('document.querySelectorAll("[data-project-card]")[1].dataset.projectCard');clickAction('favorite',id);assert.equal(saved().projects.length,2);
  });
  scenario('Desktop e mobile: temas, grade, formulário e ausência de cortes',()=>{
    seed(null);route('projects');evaluate('document.fonts.ready');capture('library-desktop-dark');snap('library-desktop-dark');
    browser('click','[data-project-action="new"]');browser('fill','#project-name','Um nome de projeto muito extenso que precisa caber no card e no atalho do board');browser('fill','#project-description','Texto com <tags> literais e descrição extensa para verificar quebra de linhas.');submit();assert.equal(evaluate('document.activeElement.getBoundingClientRect().bottom<=innerHeight'),true);browser('set','viewport','390','844');browser('scrollintoview','.project-library-heading');capture('library-mobile-dark');snap('library-mobile-dark');assert.equal(evaluate('getComputedStyle(document.querySelector(".project-library-grid")).gridTemplateColumns.split(" ").length'),1);
    for(const width of [390,320]){browser('set','viewport',String(width),'844');assert.equal(evaluate(`Array.from(document.querySelectorAll('.project-library [data-project-action],.project-library input,.project-library select,.project-card')).every(el=>{const r=el.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth;})`),true);browser('click','[data-project-action="new"]');assert.equal(evaluate(`document.querySelector('#project-form').getBoundingClientRect().right<=innerWidth`),true);if(width===390)capture('project-form-mobile');browser('press','Escape');}
    const longId=saved().projects.find(p=>p.name.startsWith('Um nome')).id;browser('set','viewport','390','844');browser('scrollintoview',`[data-project-card="${longId}"]`);browser('wait','--fn',`document.querySelector('[data-project-card="${longId}"]').getBoundingClientRect().bottom<=innerHeight`);capture('library-mobile-long-name');assert.equal(evaluate(`document.querySelector('[data-project-card="${longId}"] .project-description').textContent.includes('<tags>')`),true);assert.equal(evaluate(`document.querySelectorAll('[data-project-card="${longId}"] img').length`),0);
    route('settings');browser('select','#theme-select','light');browser('click','[data-wallpaper="ocean"]');route('projects');browser('set','viewport','390','844');browser('scrollintoview','.project-library-heading');capture('library-mobile-light');browser('set','viewport','1440','1000');capture('library-desktop-light');
  });
  scenario('Pós-auditoria: criação/edição, axe-core e foco em desktop/mobile e claro/escuro',()=>{
    for(const theme of ['light','dark'])for(const width of [1440,390,320])for(const mode of ['create','edit']){
      browser('set','viewport',String(width),'844');seed({...schema1,theme});route('projects');
      const id='project-accio-hub',before=raw();
      if(mode==='create')browser('click','[data-project-action="new"]');else clickAction('edit',id);
      snap(`post-audit-${mode}-${theme}-${width}`);
      assert.equal(focus(),'project-name');assert.equal(evaluate('document.querySelector(".shell").inert'),true);
      assert.equal(evaluate('document.querySelector("#project-form").getAttribute("role")'),null);
      auditDialog(`${mode}-${theme}-${width}`);capture(`post-audit-${mode}-${theme}-${width}`);
      assert.equal(evaluate(`(()=>{const r=document.querySelector('.project-dialog').getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight;})()`),true);
      browser('press','Shift+Tab');assert.equal(focus(),'close');browser('press','Shift+Tab');assert.equal(evaluate('document.activeElement.type'),'submit');
      browser('press','Tab');assert.equal(focus(),'close');browser('press','Tab');assert.equal(focus(),'project-name');
      browser('fill','#project-name','Alteração descartada');browser('press','Escape');
      assert.equal(focus(),mode==='create'?'new':'edit');
      assert.equal(evaluate('document.querySelector(".shell").inert'),false);
      assert.equal(evaluate('document.querySelector("[role=dialog]")'),null);
      assert.deepEqual(saved().projects,JSON.parse(before).projects);
    }
  });
  scenario('Pós-auditoria: validação nativa, envio por Enter e fechamento por botões',()=>{
    browser('set','viewport','1440','1000');seed(schema1);route('projects');
    browser('click','[data-project-action="new"]');browser('press','Enter');
    assert.equal(focus(),'project-name');assert.equal(evaluate('document.querySelector("#project-name").validity.valueMissing'),true);
    browser('fill','#project-name','Projeto via teclado');browser('press','Enter');
    const p=saved().projects.find(p=>p.name==='Projeto via teclado');assert.ok(p);assert.equal(focus(),'edit');
    clickAction('edit',p.id);browser('fill','#project-name','Edição via teclado');browser('press','Enter');assert.equal(project(p.id).name,'Edição via teclado');assert.equal(focus(),'edit');
    clickAction('edit',p.id);browser('click','#project-form .project-form-actions [data-project-action="close"]');assert.equal(focus(),'edit');
    clickAction('edit',p.id);browser('click','#project-form .project-close');assert.equal(focus(),'edit');
    browser('reload');browser('wait','[data-project-card]');assert.equal(project(p.id).name,'Edição via teclado');
  });
  console.log(JSON.stringify({result:'PASS',scenarios:results.length,evidence},null,2));
}finally{try{browser('close');}catch{}}
