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
const evidence=resolve(root,'tmp/p04-verification');mkdirSync(evidence,{recursive:true});
const baseline=resolve(root,'tmp/p04-baseline');mkdirSync(baseline,{recursive:true});
for(const file of ['index.html','style.css','app.js']) writeFileSync(resolve(baseline,file),execFileSync('git',['show',`0018bb4:prototype/${file}`],{cwd:root}));
const init=resolve(evidence,'init.js');
writeFileSync(init,`const NativeDate=Date;
window.Date=class extends NativeDate{constructor(...args){super(...(args.length?args:['2026-10-09T15:00:00Z']));}};
window.__qaErrors=[];window.addEventListener('error',e=>window.__qaErrors.push(e.message));
window.__failWrites=sessionStorage.getItem('accio-qa-fail-writes')==='yes';
const originalSetItem=Storage.prototype.setItem;
Storage.prototype.setItem=function(key,value){if(window.__failWrites&&this===localStorage)throw new DOMException('Synthetic quota failure','QuotaExceededError');return originalSetItem.call(this,key,value);};`);
const session=`accio-p04-qa-${process.pid}`;
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
function route(name){snap(`before-${name}`);browser('click',`.rail-icons [data-route="${name}"]`);browser('wait','--fn',`location.hash==='#/${name}'`);}
function scenario(name,check){check();assert.deepEqual(evaluate('window.__qaErrors'),[]);results.push({name,result:'PASS'});console.log(`PASS ${name}`);writeFileSync(resolve(evidence,'results.json'),JSON.stringify(results,null,2));}
const fixture=JSON.parse(readFileSync(new URL('./fixtures/legacy-p03.json',import.meta.url),'utf8'));
const typography=()=>evaluate(`Array.from(document.querySelectorAll('.panel-heading h3')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {text:el.textContent,x:r.x,y:r.y,width:r.width,height:r.height,font:s.font,fontWeight:s.fontWeight,letterSpacing:s.letterSpacing,color:s.color};})`);
const geometry=()=>evaluate(`Array.from(document.querySelectorAll('.rail,.app-dock,.music-zone,[data-widget]')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {key:el.dataset.widget??el.className,x:r.x,y:r.y,width:r.width,height:r.height,font:s.fontFamily,color:s.color};})`);

try{
  browser('--init-script',init,'open',new URL('/tmp/p04-baseline/',origin).href);
  browser('set','viewport','1440','1000');evaluate('localStorage.clear()');browser('reload');browser('wait','.board');evaluate('document.fonts.ready');snap('baseline-desktop');capture('baseline-desktop');const baselineGeometry=geometry();
  scenario('Inicialização vazia e baseline desktop',()=>{
    seed(null);evaluate('document.fonts.ready');snap('current-desktop');capture('current-desktop');
    assert.equal(saved().schemaVersion,2);assert.equal(saved().tasks.length,4);assert.equal(saved().notes.length,2);
    assert.deepEqual(geometry(),baselineGeometry);
    assert.equal(evaluate('document.querySelector("#storage-notice").hidden'),true);
  });
  scenario('Migração P0.3, cópia recuperável e personalização',()=>{
    seed(fixture);const s=saved();
    assert.equal(s.schemaVersion,2);assert.deepEqual(s.widgets,fixture.widgets);assert.deepEqual(s.dockOrder,fixture.dockOrder);assert.deepEqual(s.dockHidden,fixture.dockHidden);
    assert.equal(evaluate('document.documentElement.dataset.theme'),'light');assert.equal(evaluate('document.documentElement.dataset.wallpaper'),'ember');
    assert.equal(evaluate('document.querySelectorAll(".music-zone").length'),0);
    assert.equal(evaluate('document.querySelectorAll("[data-widget]").length'),3);
    assert.equal(evaluate(`localStorage.getItem(${JSON.stringify(STATE_KEY+':backup:pre-schema-2')})`),JSON.stringify(fixture));
    assert.equal(s.notes[0].body,fixture.notes[0].body);snap('migrated-light');capture('migrated-light');
  });
  scenario('Recargas repetidas sem duplicações',()=>{
    const before=raw();browser('reload');browser('wait','.board');browser('reload');browser('wait','.board');assert.equal(raw(),before);
  });
  scenario('Projeto renomeado mantém contagem e vínculos',()=>{
    evaluate(`const s=JSON.parse(localStorage.getItem(${JSON.stringify(STATE_KEY)}));s.projects.find(p=>p.name==='Accio Hub').name='Hub renomeado';s.projects.reverse();localStorage.setItem(${JSON.stringify(STATE_KEY)},JSON.stringify(s));`);
    browser('reload');browser('wait','.board');
    assert.match(evaluate('document.querySelector(".project-strip").innerText'),/Hub renomeado\s+1 tarefa/);
    route('tasks');assert.match(evaluate('document.querySelector(".viewport").innerText'),/Hub renomeado/);
    route('home');assert.match(evaluate('document.querySelector(".notes-grid").innerText'),/Hub renomeado/);
    route('projects');browser('click','[data-project-action="edit"][data-project-id="project-accio-hub"]');browser('click','[aria-label="Fechar formulário de projeto"]');assert.equal(saved().projectId,'project-accio-hub');
  });
  scenario('Criar tarefa e nota com UUID, editar, buscar e recarregar',()=>{
    route('tasks');snap('new-task');browser('click','[data-modal="task"]');snap('task-form');browser('fill','input[name="title"]','Tarefa QA persistente');assert.equal(evaluate('document.querySelector("input[name=title]").value'),'Tarefa QA persistente');browser('select','select[name="project"]','project-accio-hub');assert.equal(evaluate('document.querySelector("input[name=title]").value'),'Tarefa QA persistente');
    browser('click','#new-item button[type="submit"]');
    const task=saved().tasks.find(t=>t.title==='Tarefa QA persistente');assert.match(task.id,/^[0-9a-f-]{36}$/);assert.equal(task.projectId,'project-accio-hub');
    browser('check',`input[data-task="${task.id}"]`);assert.equal(saved().tasks.find(t=>t.id===task.id).done,true);
    route('knowledge');snap('new-note');browser('click','[data-modal="note"]');browser('fill','input[name="title"]','Nota QA persistente');browser('select','select[name="project"]','project-accio-hub');browser('click','#new-item button[type="submit"]');
    const note=saved().notes.find(n=>n.title==='Nota QA persistente');assert.match(note.id,/^[0-9a-f-]{36}$/);assert.deepEqual(note.projectIds,['project-accio-hub']);
    browser('fill','#note-editor','# Texto editado\n\nPersistência **verificada**.');assert.equal(saved().notes.find(n=>n.id===note.id).body,'# Texto editado\n\nPersistência **verificada**.');
    browser('reload');browser('wait','#note-editor');assert.equal(evaluate('document.querySelector("#note-editor").value'),'# Texto editado\n\nPersistência **verificada**.');
    browser('press','Control+k');snap('search');browser('fill','#command-search','Nota QA persistente');browser('click',`[data-result="note:${note.id}"]`);assert.equal(saved().noteId,note.id);capture('note-editor');
  });
  scenario('Navegação pelos dez destinos preserva dados e player global',()=>{
    seed(null);const ids=saved().notes.map(n=>n.id);
    for(const page of ['tasks','calendar','focus','projects','knowledge','feed','backup','email','home']){route(page);assert.equal(evaluate('document.querySelectorAll(".music-zone").length'),1);assert.deepEqual(saved().notes.map(n=>n.id),ids);}
    snap('settings');browser('click','.rail-bottom [data-route="settings"]');browser('wait','#theme-select');assert.equal(saved().page,'settings');
    browser('select','#theme-select','light');browser('click','[data-wallpaper="ocean"]');browser('uncheck','[data-dock-visible="email"]');browser('select','[data-span="tasks"]','8');
    browser('reload');browser('wait','#theme-select');assert.equal(saved().theme,'light');assert.equal(saved().wallpaper,'ocean');assert.ok(saved().dockHidden.includes('email'));assert.equal(saved().widgets.find(w=>w.id==='tasks').span,8);
  });
  scenario('Pomodoro migra, conclui uma vez, inicia, pausa e reinicia',()=>{
    const old={...fixture,music:true,focusRuns:3,focusRunning:true,focusEnd:Date.now()+3500,focusLeft:4};seed(old);route('focus');
    browser('wait','--fn',`JSON.parse(localStorage.getItem('${STATE_KEY}')).focusRuns===4`);
    assert.equal(saved().focusRunning,false);assert.equal(saved().focusLeft,0);
    browser('reload');browser('wait','[data-timer]');assert.equal(saved().focusRuns,4);
    browser('click','[data-action="focus-reset"]');browser('click','[data-action="focus-length"]');assert.equal(saved().focusMin,45);
    browser('click','[data-action="focus-toggle"]');const end=saved().focusEnd;assert.ok(end>Date.now());
    route('home');route('focus');browser('wait','--fn',`document.querySelector('[data-timer]').textContent!=='45:00'`);
    browser('click','[data-action="focus-toggle"]');assert.equal(saved().focusRunning,false);assert.ok(saved().focusLeft<2700&&saved().focusLeft>0);
    browser('click','[data-action="focus-reset"]');assert.equal(saved().focusLeft,2700);assert.equal(saved().focusEnd,null);snap('pomodoro');capture('pomodoro');
  });
  scenario('Legado incompleto e widgets desconhecidos permanecem utilizáveis',()=>{
    seed({tasks:[{title:'Tarefa sem ID',project:'Meu projeto'}],notes:[{title:'Nota sem ID'}],widgets:[{id:'__proto__',span:4,visible:true},{id:'tasks'}]});assert.equal(saved().tasks.length,1);assert.equal(saved().notes.length,1);assert.equal(saved().widgets.length,2);route('knowledge');browser('fill','#note-editor','Nota recuperada');assert.equal(saved().notes[0].body,'Nota recuperada');route('projects');
  });
  scenario('JSON inválido e schema futuro protegidos com aviso visível',()=>{
    for(const invalid of ['{JSON inválido','{"schemaVersion":99,"opaque":"preservar"}']){
      seed(invalid);assert.equal(raw(),invalid);assert.equal(evaluate('document.querySelector("#storage-notice").hidden'),false);
      assert.match(evaluate('document.querySelector("#storage-notice").textContent'),/não serão persistidas/);
      route('knowledge');route('projects');route('tasks');assert.equal(raw(),invalid);
    }
    snap('protected-storage');capture('protected-storage');
  });
  scenario('Falha de gravação visível, memória editável e recuperação sem perda',()=>{
    seed(fixture);route('knowledge');const before=raw();evaluate('window.__failWrites=true');browser('fill','#note-editor','Texto ainda não persistido');assert.equal(raw(),before);
    assert.match(evaluate('document.querySelector("#storage-notice").textContent'),/Alterações não foram persistidas/);assert.equal(evaluate('document.querySelector("#note-editor").value'),'Texto ainda não persistido');
    snap('write-failure');capture('write-failure');evaluate('window.__failWrites=false');browser('fill','#note-editor','Texto persistido após recuperação');assert.equal(saved().notes[0].body,'Texto persistido após recuperação');assert.equal(evaluate('document.querySelector("#storage-notice").hidden'),true);
  });
  scenario('Falha durante migração preserva origem até backup poder ser gravado',()=>{
    seed(null);evaluate(`localStorage.clear();localStorage.setItem('${STATE_KEY}',${JSON.stringify(JSON.stringify(fixture))});sessionStorage.setItem('accio-qa-fail-writes','yes');`);browser('reload');browser('wait','.board');assert.equal(raw(),JSON.stringify(fixture));
    assert.match(evaluate('document.querySelector("#storage-notice").textContent'),/não foram persistidas/);
    evaluate('window.__failWrites=false;sessionStorage.removeItem("accio-qa-fail-writes")');route('tasks');assert.equal(saved().schemaVersion,2);assert.equal(saved().notes[0].body,fixture.notes[0].body);
  });
  scenario('Baseline mobile preservada e editor responsivo',()=>{
    seed(null);browser('set','viewport','390','844');evaluate('document.fonts.ready');snap('current-mobile');capture('current-mobile');const currentGeometry=geometry(),currentTypography=typography();writeFileSync(resolve(evidence,'current-mobile-typography.json'),JSON.stringify(currentTypography,null,2));
    evaluate('localStorage.clear()');browser('open',new URL('/tmp/p04-baseline/',origin).href);browser('wait','.board');evaluate('document.fonts.ready');capture('baseline-mobile');assert.deepEqual(geometry(),currentGeometry);const baselineTypography=typography();writeFileSync(resolve(evidence,'baseline-mobile-typography.json'),JSON.stringify(baselineTypography,null,2));assert.deepEqual(baselineTypography,currentTypography);
    seed(null);route('knowledge');assert.ok(evaluate('document.querySelector("#note-editor").getBoundingClientRect().right<=innerWidth'));
    capture('mobile-editor');
  });
  console.log(`${results.length}/${results.length} cenários PASS; evidências: ${evidence}`);
}catch(error){
  try{console.error(JSON.stringify(evaluate('({errors:window.__qaErrors,notice:document.querySelector("#storage-notice")?.textContent})')));}catch{}
  try{snap('failure');capture('failure');}catch{}
  throw error;
}finally{browser('close');}
