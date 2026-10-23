// Synthetic QA only. No browser profile, personal data or P0.4 storage is imported.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const workspace=readFileSync(resolve(root,'rails/tmp/p12d3-workspace'),'utf8').trim();
assert.ok(workspace.startsWith(resolve(root,'rails/tmp/p12d3-browser-')),'Synthetic workspace required');
const credentials=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8'));
const output=resolve(process.env.ACCIO_QA_OUTPUT || resolve(root,'tmp/p12d3-verification'));mkdirSync(output,{recursive:true});
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,'docs/assets/p1.2d3'));mkdirSync(evidence,{recursive:true});
const session=process.env.ACCIO_QA_SESSION || `accio-p12d3-${process.pid}`;
const origin=process.env.ACCIO_QA_URL || 'http://127.0.0.1:3126';
assert.ok(['127.0.0.1','localhost'].includes(new URL(origin).hostname));
const args=['--session',session,'--json'];
const resume=Number(process.env.ACCIO_QA_RESUME || 0);let scenarioIndex=0;
const results=[];
const init=resolve(output,'init.js');writeFileSync(init,'window.__qaErrors=[];window.addEventListener("error",e=>window.__qaErrors.push(e.message));window.addEventListener("unhandledrejection",e=>window.__qaErrors.push(String(e.reason?.stack || e.reason)));');
function b(...cmd){const result=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(result.success,true,JSON.stringify(result));return result.data;}
const evaluate=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.equal(r.success,true);return r.data.result;};
const enterPassword=()=>evaluate('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';document.querySelector("#password").dispatchEvent(new Event("input",{bubbles:true}));true');
const ready=()=>b('wait','--fn',"document.querySelector('[data-controller=studio][data-ready=true]')?.dataset.page === (location.pathname.startsWith('/projects') ? 'projects' : location.pathname.startsWith('/tasks') ? 'tasks' : (location.pathname.split('/')[2] || 'home')) && !document.documentElement.hasAttribute('data-turbo-preview') && !document.documentElement.hasAttribute('aria-busy')");
const saved=()=>b('wait','--fn',"document.querySelector('[data-save-status]').hidden");
const screenshot=name=>b('screenshot',resolve(evidence,`${name}.png`));
function scenario(name,check){if(scenarioIndex++<resume)return;check();assert.deepEqual(evaluate('window.__qaErrors || []'),[]);results.push({name,result:'PASS'});writeFileSync(resolve(output,'bug-hunt-results.json'),JSON.stringify(results,null,2));console.log(`PASS ${name}`);}
const click=selector=>{
 b('snapshot','-i');b('scrollintoview',selector);
 evaluate('window.__qaStablePoint=null;true');
 b('wait','--fn',`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return false;const r=el.getBoundingClientRect(),key=[r.left,r.top,r.width,r.height].join('|'),old=window.__qaStablePoint;window.__qaStablePoint=key;return old===key && el.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()`);
 b('snapshot','-i');if(selector.startsWith('#task-check-')){b('focus',selector);b('press','Space');}else b('click',selector);
};
function nav(page){const path=page==='home'?'/':page==='projects'?'/projects':page==='tasks'?'/tasks':'/apps/'+page;click(`.rail-icons a[href='${path}']`);b('wait','--url',origin+path);ready();}
function drawer(){click('[data-open=customize]');b('wait','#customize[open]');}
function preference(selector,value){b('select',selector,value);saved();}

const formOpen=(selector='#reference-new')=>{click(selector);b('wait','[data-reference-dialog][open]');b('wait','--fn',"document.activeElement.id==='reference-title' && !!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-reference-dialog]'),'reference-form')");};
const formClose=()=>{b('press','Escape');b('wait','--fn',"!document.querySelector('[data-reference-dialog][open]')");};
const submit=()=>{click('#reference-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-reference-dialog][open]')");};
const newProject=name=>{nav('projects');click('#project-new');b('wait','[data-project-dialog][open]');b('fill','#project-name',name);click('#project-form [type=submit]');b('wait','--fn',"!document.querySelector('[data-project-dialog][open]')");return evaluate(`Array.from(document.querySelectorAll('.project-card')).find(el=>el.innerText.includes(${JSON.stringify(name)})).querySelector('[data-project-opener]').pathname.split('/')[2]`);};
const state=JSON.parse(readFileSync(resolve(workspace,'browser-state.json'),'utf8'));
try {
 b('--args','--no-sandbox','--init-script',init,'open',origin+'/session/new');b('wait','#email_address');b('fill','#email_address',credentials.email);enterPassword();click('.login-card [type=submit]');ready();saved();b('set','viewport','390','1000');b('open',origin+`/projects/${state.project}?tab=references`);ready();
 scenario('Trocar Link para Material não contorna protocolos perigosos e não grava conteúdo',()=>{
  formOpen();b('fill','#reference-title','Adversarial URL QA');b('select','#reference-kind','material');b('fill','#reference-url','javascript:alert(1)');click('#reference-form [type=submit]');b('wait','--fn',"document.querySelector('[data-reference-dialog] [data-project-notice]').textContent.includes('HTTP/HTTPS')");assert.equal(evaluate('document.querySelector("#reference-title").value'),'Adversarial URL QA');assert.equal(evaluate('document.querySelector("#reference-url").value'),'javascript:alert(1)');screenshot('adversarial-material-url');formClose();assert.equal(evaluate('document.querySelectorAll("[data-reference-uid]").length'),2);
 });
 scenario('Mesmo UID sob outro projeto retorna aviso 404 sem abrir editor',()=>{
  evaluate(`document.querySelector('#reference-modal').src='/projects/${state.other}/references/${state.link}/edit';true`);b('wait','[data-reference-dialog][open]');assert.match(evaluate('document.querySelector("[data-reference-dialog]").textContent'),/não encontrado/);assert.equal(evaluate('document.querySelector("#reference-form")'),null);screenshot('wrong-context-404');formClose();assert.equal(evaluate('document.querySelectorAll("[data-reference-uid]").length'),2);
 });
 scenario('Material sem URL depois de conversão abre edição fiel e preserva UID',()=>{
  formOpen('#reference-edit-'+state.material);assert.equal(evaluate('document.querySelector("#reference-kind").value'),'material');assert.equal(evaluate('document.querySelector("#reference-url").value'),'');assert.equal(evaluate('document.querySelector("#reference-description").value'),'Remota confirmada QA');formClose();assert.equal(evaluate(`document.querySelector('[data-reference-uid="${state.material}"]')!==null`),true);
 });
 writeFileSync(resolve(evidence,'bug-hunt-results.json'),JSON.stringify({charter:'Hipóteses adicionais D3, somente dados sintéticos, budget leve',results},null,2)+'\n');console.log('PASS 3 hipóteses adicionais');
} catch(error){console.error(error.stack);try{screenshot('bug-hunt-failure');}catch{}process.exitCode=1;}finally{b('close');}
