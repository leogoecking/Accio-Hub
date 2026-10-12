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
const session=`accio-p12d-extra-${process.pid}`;
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
function scenario(name,check){check();assert.deepEqual(evaluate('window.__qaErrors || []'),[]);results.push({name,result:'PASS'});writeFileSync(resolve(output,'additional-results.json'),JSON.stringify(results,null,2));console.log(`PASS ${name}`);}
const click=selector=>{
 b('snapshot','-i');b('scrollintoview',selector);
 evaluate('window.__qaStablePoint=null;true');
 b('wait','--fn',`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return false;const r=el.getBoundingClientRect(),key=[r.left,r.top,r.width,r.height].join('|'),old=window.__qaStablePoint;window.__qaStablePoint=key;return old===key && el.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()`);
 b('click',selector);
};
function nav(page){const path=page==='home'?'/':page==='projects'?'/projects':'/apps/'+page;click(`.rail-icons a[href='${path}']`);b('wait','--url',origin+path);ready();}
function drawer(){click('[data-open=customize]');b('wait','#customize[open]');}
function preference(selector,value){b('select',selector,value);saved();}


const uidToken='u-'+Buffer.from('42/á?%#项目').toString('base64url');
const legacyPath='/projects/'+uidToken;
const protoSession=`accio-p12d-prototype-${process.pid}`;
const proto=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',['--session',protoSession,'--json',...cmd],{encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(r.success,true);return r.data;};
const protoEval=code=>{const r=JSON.parse(execFileSync('agent-browser',['--session',protoSession,'--json','eval','--stdin'],{input:code,encoding:'utf8',env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(r.success,true);return r.data.result;};
try {
 b('--args','--no-sandbox','--init-script',init,'open',origin);b('wait','#email_address');b('fill','#email_address',credentials.email);enterPassword();click('input[type=submit]');ready();saved();nav('projects');
 scenario('Nome equivalente é rejeitado com todos os campos preservados',()=>{click('#project-new');b('wait','[data-project-dialog][open]');b('fill','#project-name','  PROJETO NAVEGADOR QA LOCAL  ');b('fill','#project-description','Descrição mantida após erro');click('#project-form [type=submit]');b('wait','--fn',"document.querySelector('[data-project-dialog] [data-project-notice]').textContent.length>0");assert.equal(evaluate('document.querySelector("#project-description").value'),'Descrição mantida após erro');screenshot('invalid-equivalent-name');b('press','Escape');});
 scenario('UID legado especial navega por URL e relações reais aparecem somente para consulta',()=>{b('open',origin+legacyPath);ready();assert.match(evaluate('document.querySelector("#space-title").innerText'),/Legado Unicode QA/);assert.match(evaluate('document.querySelector("#space-content").innerText'),/Tarefa vinculada QA/);assert.equal(evaluate('document.querySelectorAll("#space-content input[type=checkbox],#space-content form").length'),0);click('#space-tab-references');b('wait','--fn',"document.activeElement.id==='space-tab-references' && document.querySelector('#space-tab-references').getAttribute('aria-selected')==='true'");assert.match(evaluate('document.querySelector("#space-content").innerText'),/Material QA/);assert.equal(evaluate('document.querySelector(".space-reference a").getAttribute("href")'),'https://example.test/material');});
 scenario('Arquivamento e restauração preservam tarefas e referências visíveis',()=>{nav('projects');click('#project-archive-'+uidToken);b('wait','#project-restore-'+uidToken);b('open',origin+legacyPath+'?tab=tasks');ready();assert.match(evaluate('document.querySelector("#space-content").innerText'),/Tarefa vinculada QA/);assert.match(evaluate('document.querySelector(".space-archive").innerText'),/registros preservados/);click('#space-tab-references');b('wait','--fn',"document.activeElement.id==='space-tab-references' && document.querySelector('#space-tab-references').getAttribute('aria-selected')==='true'");assert.equal(evaluate('document.querySelectorAll(".space-reference").length'),2);nav('projects');click('#project-restore-'+uidToken);b('wait','#project-archive-'+uidToken);});
 scenario('503 mantém edição e retentativa conserva cor herdada de projeto legado',()=>{click('#project-edit-'+uidToken);b('wait','[data-project-dialog][open]');assert.equal(evaluate('document.querySelector("#project-color-value").value'),'');b('fill','#project-description','Descrição persistida QA');evaluate('window.__real=window.fetch;window.fetch=(url,options)=>url.includes("/projects/") && options?.method==="POST"?Promise.resolve(new Response(JSON.stringify({error:"database_busy",message:"O armazenamento está ocupado. Sua edição foi mantida; tente novamente."}),{status:503,headers:{"Content-Type":"application/json"}})):window.__real(url,options)');click('#project-form [type=submit]');b('wait','--fn',"document.querySelector('[data-project-dialog] [data-project-notice]').textContent.includes('ocupado')");assert.equal(evaluate('document.querySelector("#project-description").value'),'Descrição persistida QA');screenshot('project-busy-draft');evaluate('window.fetch=window.__real');click('#project-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-project-dialog][open]')");});
 scenario('Filtro confirmado preservado quando aparência obsoleta é reaplicada',()=>{
  const first=b('tab','list').tabs.find(t=>t.active).tabId;b('tab','new',origin);ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;
  b('tab',first);click('#project-filter-paused');b('wait','--fn',"document.querySelector('#project-filter-paused').getAttribute('aria-pressed')==='true'");
  b('tab',second);drawer();b('select','#drawer-theme',evaluate('document.documentElement.dataset.theme==="light"?"dark":"light"'));b('wait','[data-recovery=apply]:not([hidden])');click('[data-recovery=apply]');saved();b('press','Escape');nav('projects');assert.equal(evaluate('document.querySelector("#project-filter-paused").getAttribute("aria-pressed")'),'true');click('#project-filter-all');b('wait','--fn',"document.querySelector('#project-filter-all').getAttribute('aria-pressed')==='true'");b('tab','close',first);
 });
 scenario('Link de edição obsoleto após arquivamento abre aviso acessível com Escape e retorno',()=>{
  const first=b('tab','list').tabs.find(t=>t.active).tabId;b('tab','new',origin+'/projects');ready();const second=b('tab','list').tabs.find(t=>t.active).tabId;
  click('#project-archive-'+uidToken);b('wait','#project-restore-'+uidToken);b('tab',first);
  click('#project-edit-'+uidToken);b('wait','[data-project-dialog][open]');assert.match(evaluate('document.querySelector("#project-unavailable-message").textContent'),/somente leitura/);assert.equal(evaluate('document.querySelector("[data-project-dialog] form")'),null);assert.equal(evaluate('document.activeElement.getAttribute("aria-label")'),'Fechar aviso do projeto');
  b('press','Escape');b('wait','--fn',"document.activeElement.id==='project-edit-"+uidToken+"'");
  b('tab',second);click('#project-restore-'+uidToken);b('wait','#project-edit-'+uidToken);b('tab','close',first);
 });
 scenario('Foco de fallback fica visível quando um comando remove o card da seleção',()=>{
  click('#project-filter-active');b('wait','--fn',"document.querySelector('#project-filter-active').getAttribute('aria-pressed')==='true'");
  click('#project-status-'+uidToken);b('wait','--fn',"!document.getElementById('project-status-"+uidToken+"') && document.activeElement.id==='project-new'");
  b('wait','--fn',"(()=>{const r=document.getElementById('project-new').getBoundingClientRect(),m=document.querySelector('main').getBoundingClientRect();return r.top>=m.top && r.bottom<=m.bottom})()");
  click('#project-filter-all');b('wait','#project-status-'+uidToken);click('#project-status-'+uidToken);b('wait','--fn',"document.querySelector('#project-status-"+uidToken+"').textContent.includes('Pausar')");
 });
 proto('--args','--no-sandbox','open','http://127.0.0.1:3112/#/projects');proto('wait','.project-library');
 const comparison=[];
 for(const theme of ['dark','light']) {
  drawer();preference('#drawer-theme',theme);b('press','Escape');
  protoEval(`const state=JSON.parse(localStorage.getItem('accio-hub-p0.3-studio'));state.theme='${theme}';localStorage.setItem('accio-hub-p0.3-studio',JSON.stringify(state));true`);proto('reload');proto('wait','.project-library');
  for(const width of [320,390,768,1440,1920]) {
   b('set','viewport',String(width),'1000');proto('set','viewport',String(width),'1000');evaluate('document.fonts.ready');protoEval('document.fonts.ready');screenshot(`compare-rails-${theme}-${width}`);proto('screenshot',resolve(evidence,`compare-p04-${theme}-${width}.png`));
   const geometry="Array.from(document.querySelectorAll('.rail,.headbar,.music-zone,.project-library-heading,.project-card')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {key:el.className,x:r.x,y:r.y,width:r.width,height:r.height,font:s.fontFamily,fontSize:s.fontSize,borderRadius:s.borderRadius}})";
   const rails=evaluate(geometry),p04=protoEval(geometry);comparison.push({theme,width,rails,p04});
   scenario(`Comparação visual P0.4 ${theme} ${width}px`,()=>{for(const selector of ['.rail','.headbar','.music-zone']){const r=rails.find(item=>item.key.includes(selector.slice(1))),p=p04.find(item=>item.key.includes(selector.slice(1)));assert.ok(Math.abs(r.width-p.width)<=1 && Math.abs(r.height-p.height)<=1);assert.equal(r.font,p.font);}});
  }
 }
 writeFileSync(resolve(evidence,'visual-comparison.json'),JSON.stringify(comparison,null,2));
 scenario('Endereços diretos de formulários mantêm shell, cancelamento e URL da biblioteca',()=>{
  b('open',origin+'/projects/new');b('wait','[data-project-dialog][open]');assert.equal(evaluate('document.querySelectorAll(".rail").length'),1);assert.equal(evaluate('document.activeElement.id'),'project-name');b('press','Escape');b('wait','--fn',"location.pathname==='/projects' && !location.search && document.activeElement.id==='project-new'");
  b('open',origin+'/projects/new');b('wait','[data-project-dialog][open]');b('fill','#project-name','Projeto direto QA');click('#project-form [type=submit]');b('wait','--fn',"location.pathname==='/projects' && !location.search && !document.querySelector('[data-project-dialog][open]')");assert.match(evaluate('document.querySelector(".project-library").innerText'),/Projeto direto QA/);
  b('open',origin+legacyPath+'/edit');b('wait','[data-project-dialog][open]');assert.equal(evaluate('document.querySelector("#project-name").value'),'Legado Unicode QA');click('[aria-label="Fechar formulário de projeto"]');b('wait','--fn',"location.pathname==='/projects' && !location.search && !document.querySelector('[data-project-dialog][open]')");
 });
 scenario('Estado inexistente apresenta retorno acessível para a biblioteca',()=>{b('open',origin+'/projects/u-bm90LWV4aXN0aW5n');b('wait','#space-title');assert.match(evaluate('document.querySelector("#space-title").innerText'),/não encontrado/);assert.equal(evaluate('document.querySelector(".unavailable a").getAttribute("href")'),'/projects');});
 writeFileSync(resolve(evidence,'d1-browser-additional-results.json'),JSON.stringify(results,null,2));console.log(`${results.length} cenários adicionais PASS`);
} catch(error) {screenshot('additional-failure');console.log('DIAGNOSTIC',evaluate(`({url:location.href,clicks:window.__clicks,dialogs:Array.from(document.querySelectorAll('dialog')).map(d=>({id:d.id,open:d.open})),notice:document.querySelector('.project-feedback')?.textContent,errors:window.__qaErrors,library:!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('.project-library'),'project-library'),studio:(()=>{const s=window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio');return {version:s.version,initialized:s.initialized,failed:s.failed,pending:s.pending}})()})`));throw error} finally {b('close');proto('close')}
