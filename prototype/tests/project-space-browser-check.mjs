// QA com agent-browser em sessão própria, somente dados sintéticos e loopback.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {STATE_KEY} from '../state.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),origin=new URL(process.argv[2]??'http://127.0.0.1:4174');
assert.ok(['127.0.0.1','localhost'].includes(origin.hostname));
const evidence=resolve(root,'tmp/p04-space-verification');mkdirSync(evidence,{recursive:true});
const init=resolve(evidence,'init.js');writeFileSync(init,`window.__qaErrors=[];window.addEventListener('error',e=>window.__qaErrors.push(e.message));const original=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){if(window.__failWrites&&this===localStorage)throw new DOMException('QA quota','QuotaExceededError');return original.call(this,k,v)};`);
const args=['--namespace','accio-p04','--session',`accio-space-qa-${process.pid}`,'--json'];if(process.env.ACCIO_BROWSER_NO_SANDBOX==='1')args.push('--args','--no-sandbox');
function browser(...command){const result=JSON.parse(execFileSync('agent-browser',[...args,...command],{env:{...process.env,XDG_RUNTIME_DIR:'/tmp'},encoding:'utf8',timeout:45000}));assert.equal(result.success,true,JSON.stringify(result));return result.data;}
const evaluate=code=>browser('eval','-b',Buffer.from(code).toString('base64')).result;
const saved=()=>evaluate(`JSON.parse(localStorage.getItem(${JSON.stringify(STATE_KEY)}))`);
const capture=name=>browser('screenshot',resolve(evidence,name+'.png'));
const snapshot=name=>writeFileSync(resolve(evidence,name+'.json'),JSON.stringify(browser('snapshot','-i'),null,2));
const fixture=JSON.parse(readFileSync(new URL('./fixtures/schema-2.json',import.meta.url))),hub='project-accio-hub',cad='project-accio-cad';
const results=[];function scenario(name,check){check();assert.deepEqual(evaluate('window.__qaErrors'),[]);results.push({name,result:'PASS'});writeFileSync(resolve(evidence,'results.json'),JSON.stringify(results,null,2));console.log('PASS '+name);}
function seed(state=fixture){evaluate(`window.__failWrites=false;localStorage.clear();localStorage.setItem(${JSON.stringify(STATE_KEY)},${JSON.stringify(JSON.stringify(state))})`);browser('open',new URL('/prototype/#/home',origin).href);browser('reload');browser('wait','.board');}
function open(id=hub,tab='overview'){snapshot('before-open');browser('open',new URL(`/prototype/#/projects/${encodeURIComponent(id)}/${tab}`,origin).href);browser('wait','.project-space');}
function click(selector){snapshot('before-click');browser('click',selector);if(selector.startsWith('[href="#/projects/'))browser('wait','#space-title');if(selector==='.space-back')browser('wait','.project-library');}
function tab(name){click(`[data-space-tab="${name}"]`);browser('wait','--fn',`document.querySelector('[data-space-tab="${name}"]').getAttribute('aria-selected')==='true'`);}
const button=(action,id)=>`[data-space-action="${action}"]${id?`[data-space-id="${id}"]`:''}`;
const submit=()=>click('#space-form button[type="submit"]');
const active=()=>evaluate('document.activeElement?.id||document.activeElement?.dataset.spaceAction');
function audit(name,selector='.project-space'){const result=browser('a11y','--selector',selector);writeFileSync(resolve(evidence,'axe-'+name+'.json'),JSON.stringify(result,null,2));assert.deepEqual(result.violations,[],JSON.stringify(result.violations));}
try{
  browser('--init-script',init,'open',new URL('/prototype/',origin).href);browser('set','viewport','1440','1000');seed();
  scenario('Schema 2 migra para 3 sem alterar preferências, tarefas/notas ou origem',()=>{
    const state=saved();assert.equal(state.schemaVersion,3);assert.deepEqual(state.tasks,fixture.tasks);assert.deepEqual(state.notes,fixture.notes);assert.deepEqual(state.references,[]);
    for(const k of ['theme','wallpaper','accent','widgets','dockOrder','dockHidden','music','musicExpanded'])assert.deepEqual(state[k],fixture[k]);
    assert.equal(evaluate(`localStorage.getItem(${JSON.stringify(STATE_KEY+':backup:pre-schema-3')})`),JSON.stringify(fixture));
  });
  scenario('Biblioteca e widget abrem espaço por ID; abas, Voltar e projetos inexistentes',()=>{
    click('.rail-icons [data-route="projects"]');click(`[href="#/projects/${hub}/overview"]`);assert.match(evaluate('document.querySelector("#space-title").textContent'),/Accio Hub/);capture('overview-light-desktop');audit('overview-light');
    click('.space-back');browser('wait','.project-library');assert.equal(evaluate('document.activeElement.className'),'project-space-link');click('.rail-icons [data-route="home"]');click(`[data-open-project="${cad}"]`);assert.equal(evaluate('location.hash'),`#/projects/${cad}/overview`);
    open('missing');assert.match(evaluate('document.querySelector(".project-space").textContent'),/Projeto não encontrado/);assert.equal(saved().projectId,cad);capture('missing-project');open(hub);
    click('#space-tab-overview');browser('press','ArrowRight');assert.equal(active(),'space-tab-tasks');browser('press','End');assert.equal(active(),'space-tab-references');browser('press','Home');assert.equal(active(),'space-tab-overview');
  });
  let taskId,noteId,refId;
  scenario('Criar/editar/concluir tarefa mantém vínculo e não mostra tarefas de outros projetos',()=>{
    tab('tasks');assert.equal(evaluate('document.querySelectorAll("[data-space-task]").length'),fixture.tasks.filter(t=>t.projectId===hub).length);
    click(button('new-task'));assert.equal(active(),'space-item-title');browser('fill','#space-item-title','Revisar protótipo');browser('select','#space-priority','Alta');submit();taskId=saved().tasks.find(t=>t.title==='Revisar protótipo').id;assert.equal(saved().tasks.find(t=>t.id===taskId).projectId,hub);assert.equal(active(),'new-task');
    click(button('edit-task',taskId));browser('fill','#space-item-title','Revisar protótipo final');submit();click(`[data-task="${taskId}"]`);assert.equal(saved().tasks.find(t=>t.id===taskId).done,true);assert.equal(evaluate('document.activeElement.dataset.task'),taskId);open(cad,'tasks');assert.ok(!evaluate('document.querySelector("#space-content").textContent').includes('Revisar protótipo final'));open(hub,'tasks');browser('reload');browser('wait','[data-space-task]');assert.ok(evaluate('document.querySelector("#space-content").textContent').includes('Revisar protótipo final'));capture('tasks-desktop');audit('tasks');open(hub);click('[data-task="3"]');assert.equal(active(),'new-task');tab('tasks');
  });
  scenario('Notas compartilhadas: criar/editar entre projetos sem duplicar conteúdo ou ID',()=>{
    tab('knowledge');click(button('new-note'));browser('fill','#space-item-title','Nota compartilhada');browser('fill','#space-note-body','# Experimento\n\n**Markdown** <script>texto sem execução</script>');click(`input[name="projectIds"][value="${cad}"]`);submit();noteId=saved().notes.find(n=>n.title==='Nota compartilhada').id;assert.deepEqual(saved().notes.find(n=>n.id===noteId).projectIds.sort(),[hub,cad].sort());
    open(cad,'knowledge');click(button('edit-note',noteId));browser('fill','#space-item-title','Nota compartilhada revisada');browser('fill','#space-note-body','# Revisão\n\nMesmo conteúdo em dois espaços.');submit();open(hub,'knowledge');assert.match(evaluate(`document.querySelector('[data-space-note="${noteId}"]').textContent`),/Mesmo conteúdo em dois espaços/);assert.equal(saved().notes.filter(n=>n.id===noteId).length,1);
    click(`[data-space-note="${noteId}"] summary`);capture('knowledge-shared-desktop');audit('knowledge');browser('reload');browser('wait','[data-space-note]');assert.match(evaluate('document.querySelector("#space-content").textContent'),/Nota compartilhada revisada/);
  });
  scenario('Vincular nota existente e editar associação sem cópia; editor global atualiza o mesmo registro',()=>{
    const target=saved().notes.find(n=>!n.projectIds.includes(hub)),count=saved().notes.length;click(button('link-note'));browser('select','#space-note-link',String(target.id));submit();assert.equal(saved().notes.length,count);assert.ok(saved().notes.find(n=>n.id===target.id).projectIds.includes(hub));
    click(button('edit-note',noteId));click(`input[name="projectIds"][value="${cad}"]`);submit();assert.deepEqual(saved().notes.find(n=>n.id===noteId).projectIds,[hub]);
    click('.rail-icons [data-route="knowledge"]');click(`[data-note="${noteId}"]`);browser('fill','#note-editor','Texto atualizado no Conhecimento global');open(hub,'knowledge');assert.match(evaluate(`document.querySelector('[data-space-note="${noteId}"]').textContent`),/Texto atualizado no Conhecimento global/);
  });
  scenario('Referências: criar/editar link e material, impedir URL executável, persistir após recarga',()=>{
    tab('references');click(button('new-reference'));browser('fill','#space-item-title','Guia de interface');browser('fill','#space-reference-url','https://example.com/guia');browser('fill','#space-reference-description','Consulta de pesquisa');submit();refId=saved().references[0].id;
    assert.equal(evaluate('document.querySelector(".space-reference a").getAttribute("rel")'),'noopener noreferrer');click(button('edit-reference',refId));browser('fill','#space-reference-url','javascript:alert(1)');submit();assert.match(evaluate('document.querySelector("#space-form-error").textContent'),/http ou https/);assert.equal(saved().references[0].url,'https://example.com/guia');browser('fill','#space-reference-url','https://example.com/revisado');submit();
    click(button('new-reference'));browser('fill','#space-item-title','Livro de arquitetura');browser('select','#space-reference-kind','material');browser('fill','#space-reference-description','Livro impresso, capítulo 4.');submit();browser('reload');browser('wait','[data-space-reference]');assert.equal(saved().references.length,2);assert.equal(saved().references.find(r=>r.id===refId).url,'https://example.com/revisado');capture('references-desktop');audit('references');open(cad,'references');assert.equal(evaluate('document.querySelectorAll("[data-space-reference]").length'),0);open(hub);
  });
  scenario('Renomeação/arquivamento/restauração preservam IDs e todas relações; arquivado é consultável',()=>{
    const content=saved();click('[data-project-action="edit"]');browser('fill','#project-name','Hub de trabalho');click('#project-form button[type="submit"]');assert.match(evaluate('document.querySelector("#space-title").textContent'),/Hub de trabalho/);assert.equal(evaluate('location.hash'),`#/projects/${hub}/overview`);
    click('.space-back');click(`[data-project-action="pause"][data-project-id="${hub}"]`);click(`[data-project-action="archive"][data-project-id="${hub}"]`);click(`[href="#/projects/${hub}/overview"]`);assert.match(evaluate('document.querySelector(".space-archive").textContent'),/arquivado/);assert.equal(evaluate('document.querySelectorAll("[data-space-action],[data-task]").length'),0);tab('knowledge');assert.match(evaluate('document.querySelector("#space-content").textContent'),/Nota compartilhada revisada/);tab('references');assert.equal(evaluate('document.querySelectorAll("[data-space-reference]").length'),2);capture('archived-project');browser('reload');browser('wait','.space-archive');
    click('.space-back');click(`[data-project-action="restore"][data-project-id="${hub}"]`);assert.equal(saved().projects.find(p=>p.id===hub).status,'paused');assert.deepEqual(saved().tasks,content.tasks);assert.deepEqual(saved().notes,content.notes);assert.deepEqual(saved().references,content.references);open(hub);
  });
  scenario('Pomodoro é único: iniciar no projeto, navegar e recarregar mantém prazo; pausar global reflete projeto',()=>{
    click('[data-action="focus-toggle"]');const end=saved().focusEnd;assert.equal(saved().focusRunning,true);click('.rail-icons [data-route="home"]');assert.equal(saved().focusEnd,end);click('.rail-icons [data-route="focus"]');browser('reload');browser('wait','[data-timer]');assert.equal(saved().focusEnd,end);click('[data-action="focus-toggle"]');assert.equal(saved().focusRunning,false);open(hub);assert.equal(evaluate('document.querySelector("[data-action=focus-toggle]").title'),'Iniciar');
  });
  scenario('Formulários acessíveis: foco inicial, Tab/Shift Tab, Escape, atalhos, cancelamento e erro nativo',()=>{
    for(const kind of ['task','note','reference']){const tabName=kind==='task'?'tasks':kind==='note'?'knowledge':'references';tab(tabName);click(button('new-'+kind));assert.equal(active(),'space-item-title');assert.equal(evaluate('document.querySelector("#space-form").getAttribute("role")'),null);audit('form-'+kind,'.workspace-dialog');browser('focus','#space-form button[type="submit"]');browser('press','Tab');assert.equal(active(),'close');browser('press','Shift+Tab');assert.equal(evaluate('document.activeElement.type'),'submit');browser('press','Control+k');assert.equal(evaluate('document.querySelector(".search-modal")'),null);browser('press','Escape');assert.equal(active(),'new-'+kind);}
    click(button('new-reference'));submit();assert.equal(evaluate('document.querySelector("#space-item-title").validity.valueMissing'),true);click(button('close'));assert.equal(active(),'new-reference');
  });
  scenario('Falha de escrita mantém JSON anterior e informa alteração apenas na sessão',()=>{
    tab('tasks');const before=JSON.stringify(saved());evaluate('window.__failWrites=true');click(button('new-task'));browser('fill','#space-item-title','Tarefa só em memória');submit();assert.match(evaluate('document.querySelector(".space-feedback").textContent'),/somente nesta sessão/);assert.equal(JSON.stringify(saved()),before);evaluate('window.__failWrites=false');
  });
  scenario('Estados vazios; desktop/mobile claro/escuro, abas e formulários sem cortes e axe-core',()=>{
    seed({...fixture,tasks:[],notes:[],theme:'dark'});for(const theme of ['dark','light'])for(const width of [1440,390]){browser('set','viewport',String(width),'844');click('.rail-bottom [data-route="settings"]');browser('select','#theme-select',theme);open(hub);
      for(const tabName of Object.keys({overview:1,tasks:1,knowledge:1,references:1})){tab(tabName);assert.equal(evaluate('document.documentElement.scrollWidth<=innerWidth'),true);capture(`${tabName}-${theme}-${width}`);audit(`${tabName}-${theme}-${width}`);}
      tab('knowledge');click(button('new-note'));browser('fill','#space-item-title','Título longo '.repeat(9));browser('fill','#space-note-body','Markdown no celular');assert.equal(evaluate('document.querySelector(".workspace-dialog").scrollWidth<=document.querySelector(".workspace-dialog").clientWidth'),true);capture(`form-note-${theme}-${width}`);audit(`form-note-${theme}-${width}`,'.workspace-dialog');browser('press','Escape');
    }
  });
  console.log(JSON.stringify({result:'PASS',scenarios:results.length,evidence},null,2));
}finally{try{browser('close');}catch{}}
