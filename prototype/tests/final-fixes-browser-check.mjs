// Regressões F01–F07: navegador isolado, dados sintéticos, somente loopback.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../',import.meta.url));
const origin=new URL(process.argv[2]??'http://127.0.0.1:4174');
assert.ok(['127.0.0.1','localhost'].includes(origin.hostname));
const dir=`${root}/tmp/p04-final-fixes/after`,key='accio-hub-p0.3-studio';mkdirSync(dir,{recursive:true});
const args=['--namespace','accio-p04-fixes','--session',`fixes-${process.pid}`,'--json'];
if(process.env.ACCIO_BROWSER_NO_SANDBOX==='1')args.push('--args','--no-sandbox');
function b(...cmd){const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',env:{...process.env,XDG_RUNTIME_DIR:'/tmp'},timeout:45000}));assert.equal(r.success,true,JSON.stringify(r));return r.data;}
const ev=code=>b('eval','-b',Buffer.from(code).toString('base64')).result;
const save=(name,data)=>writeFileSync(`${dir}/${name}.json`,JSON.stringify(data,null,2));
let n=0;const snap=()=>save(`fixes-snapshot-${++n}`,b('snapshot','-i'));
const click=s=>{snap();b('click',s);};
const shot=name=>b('screenshot',`${dir}/${name}.png`);
const go=route=>{b('open',new URL(`/prototype/#/${route}`,origin).href);b('wait','.viewport');snap();};
const results=[],matrix=[];
function test(name,fn){fn();results.push({name,result:'PASS'});save('fixes-results',results);console.log('PASS '+name);}
function axe(name,selector,rules){const a=b('a11y',...(selector?['--selector',selector]:[]));save('axe-'+name,a);const relevant=rules?a.violations.filter(v=>rules.includes(v.id)):a.violations;assert.deepEqual(relevant,[],JSON.stringify(relevant));return a;}
const saved=()=>ev(`JSON.parse(localStorage.getItem('${key}'))`);
try{
 go('home');ev(`localStorage.clear();localStorage.setItem('${key}',${JSON.stringify(readFileSync(new URL('./fixtures/schema-3.json',import.meta.url),'utf8'))})`);b('reload');b('wait','.board');
 test('F03: tarefa global contém teclado, bloqueia atalhos sobrepostos e devolve foco em todos os fechamentos',()=>{
  for(const route of ['home','tasks'])for(const end of ['Escape','Cancelar','Fechar','scrim','Salvar']){
   go(route);const selector=route==='home'?'[data-modal=task]':'.add-row[data-modal=task]';click(selector);b('wait','#new-item');
   assert.equal(ev('document.activeElement.name'),'title');assert.equal(ev('document.querySelector(".shell").inert'),true);
   assert.equal(ev('document.querySelector("[role=dialog][aria-modal=true]").contains(document.querySelector("#new-item"))'),true);
   b('focus','#new-item button[type=submit]');b('press','Tab');assert.equal(ev('document.activeElement.dataset.action'),'close-modal');b('press','Shift+Tab');assert.equal(ev('document.activeElement.type'),'submit');
   b('press','Control+k');b('press','Control+Shift+n');assert.equal(ev('document.querySelectorAll(".search-modal,.knowledge-dialog").length'),0);
   if(end==='Salvar'){
    const count=saved().tasks.length;b('focus','#new-item button[type=submit]');b('press','Enter');assert.equal(ev('document.querySelector("#new-item input").validity.valueMissing'),true);assert.equal(saved().tasks.length,count);
    snap();b('fill','#new-item input[name=title]',`Tarefa sintética ${route}`);b('select','#new-item select','project-accio-hub');b('focus','#new-item input[name=title]');b('press','Enter');
    assert.equal(saved().tasks.length,count+1);assert.equal(saved().tasks[0].projectId,'project-accio-hub');assert.equal(ev('location.hash'),'#/tasks');
   }else if(end==='Escape'){for(const key of ['Tab','Shift+Tab'])for(let i=0;i<6;i++){b('press',key);assert.equal(ev('!!document.activeElement.closest(".global-dialog")'),true);}b('press','Escape');}
   else if(end==='scrim'){snap();b('mouse','move','1','1');b('mouse','down');b('mouse','up');}
   else{b('focus',end==='Cancelar'?'#new-item .tertiary':'#new-item .mini-control');b('press','Enter');}
   assert.equal(ev('document.querySelectorAll("#new-item").length'),0);assert.equal(ev('document.activeElement.dataset.modal'),'task');
   if(route==='tasks')assert.equal(ev('document.activeElement.classList.contains("add-row")'),true);
   assert.equal(ev('document.querySelector(".shell").inert'),false);
  }
 });
 for(const theme of ['dark','light'])for(const width of [320,390,768,1440,1920]){
  go('settings');snap();b('select','#theme-select',theme);b('set','viewport',String(width),'1000');
  go('settings');const title=ev('(()=>{const r=document.querySelector("h1").getBoundingClientRect();return {left:r.left,right:r.right,font:getComputedStyle(document.querySelector("h1")).fontFamily}})()');assert.ok(title.left>=0&&title.right<=width);assert.match(title.font,/Space Grotesk/);shot(`settings-${theme}-${width}`);axe(`settings-${theme}-${width}`);
  go('home');click('[data-action=open-customize]');b('wait','.drawer');assert.equal(ev('document.querySelectorAll(".drawer .setting-group").length'),4);
  assert.equal(ev('document.querySelectorAll("#theme-select").length'),0); // Origem home; IDs do painel são distintos.
  axe(`customize-${theme}-${width}`);shot(`customize-top-${theme}-${width}`);
  b('focus','.drawer [data-span=tasks]');assert.equal(ev('document.activeElement.dataset.span'),'tasks');assert.equal(ev('(()=>{const r=document.activeElement.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight})()'),true);shot(`customize-widgets-${theme}-${width}`);
  assert.equal(ev('document.querySelector("[data-span=tasks]").closest(".drawer")!==null'),true);
  b('press','Escape');go('projects');click('[data-project-action=new]');axe(`project-${theme}-${width}`,'.project-dialog');shot(`project-${theme}-${width}`);b('press','Escape');
  go('tasks');click('.add-row[data-modal=task]');axe(`task-${theme}-${width}`);shot(`task-${theme}-${width}`);b('press','Escape');
  matrix.push({theme,width,title,result:'PASS'});save('fixes-matrix',matrix);
 }
 test('F01/F04/F06: contraste confirmado e título íntegro nos dois temas e cinco larguras',()=>assert.equal(matrix.length,10));
 test('F02/F07: nome da busca e semântica do shell, configurações e painel',()=>{
  go('home');click('[data-action=search]');axe('search');shot('search-light-current');b('press','Escape');go('settings');click('[data-action=open-customize]');
  assert.equal(ev('new Set([...document.querySelectorAll("[id]")].map(e=>e.id)).size===document.querySelectorAll("[id]").length'),true);axe('customize-over-settings');b('press','Escape');
 });
 test('F05: controles existentes de Dock e Widgets funcionam a partir de Personalizar e persistem',()=>{
  go('home');click('[data-action=open-customize]');const before=saved();click('.drawer [data-dock-down=tasks]');assert.notDeepEqual(saved().dockOrder,before.dockOrder);
  snap();b('select','.drawer [data-span=tasks]','8');click('.drawer [data-down=tasks]');click('.drawer [data-visible=tasks]');click('.drawer [data-dock-visible=tasks]');
  assert.equal(saved().widgets.find(w=>w.id==='tasks').span,8);assert.equal(saved().widgets.find(w=>w.id==='tasks').visible,false);assert.ok(saved().dockHidden.includes('tasks'));const after=saved();
  b('press','Escape');b('reload');b('wait','.board');assert.deepEqual(saved().widgets,after.widgets);assert.deepEqual(saved().dockOrder,after.dockOrder);assert.deepEqual(saved().dockHidden,after.dockHidden);
 });
 test('Formulário global em 320×568: salvar alcançável por teclado e foco restaurado',()=>{
  go('tasks');b('set','viewport','320','568');click('.add-row[data-modal=task]');b('focus','#new-item button[type=submit]');assert.equal(ev('(()=>{const r=document.activeElement.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight})()'),true);shot('task-320x568-submit');b('press','Escape');assert.equal(ev('document.activeElement.dataset.modal'),'task');
 });
}finally{b('close');}
