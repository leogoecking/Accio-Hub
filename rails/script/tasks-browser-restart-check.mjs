import {readFileSync,writeFileSync} from 'node:fs';import {execFileSync} from 'node:child_process';import {resolve} from 'node:path';import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'../..'),workspace=readFileSync(resolve(root,'rails/tmp/p12d2-workspace'),'utf8').trim(),credentials=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8')),evidence=resolve(root,'docs/assets/p1.2d2');
const args=['--session','accio-d2-restart','--json'],env={...process.env,XDG_RUNTIME_DIR:'/tmp'};
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',env,timeout:45000}));assert.equal(r.success,true);return r.data;};
const ev=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',env,timeout:45000}));assert.equal(r.success,true);return r.data.result;};
const state=()=>ev(`({appearance:JSON.parse(document.querySelector('[data-controller=studio]').dataset.studioAppearanceValue),version:document.querySelector('[data-controller=studio]').dataset.studioVersionValue,tasks:Array.from(document.querySelectorAll('[data-task-uid]')).map(el=>({uid:el.dataset.taskUid,text:el.innerText,done:el.querySelector('[type=checkbox]').checked}))})`);
if(process.argv[2]==='capture'){
 b('--args','--no-sandbox','open','http://127.0.0.1:3125/tasks');b('wait','#password');b('fill','#email_address',credentials.email);ev('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';true');b('snapshot','-i');b('click','input[type=submit]');b('wait','[data-ready=true]');b('open','http://127.0.0.1:3125/tasks');b('wait','[data-ready=true]');b('wait','[data-task-uid]');
 const token=JSON.parse(readFileSync(resolve(workspace,'browser-progress.json'),'utf8')).personal;
 b('focus','#task-check-'+token);b('press','Space');b('wait','--fn',`document.querySelector('#task-check-${token}').checked && document.activeElement.id==='task-check-${token}'`);
 writeFileSync(resolve(evidence,'axe-completed-light.json'),JSON.stringify(b('a11y','--json'),null,2));b('screenshot',resolve(evidence,'completed-task-a11y.png'));
 b('focus','#task-check-'+token);b('press','Space');b('wait','--fn',`!document.querySelector('#task-check-${token}').checked && document.activeElement.id==='task-check-${token}'`);
 writeFileSync(resolve(workspace,'browser-before-restart.json'),JSON.stringify(state()));b('screenshot',resolve(evidence,'before-server-restart.png'));console.log('PASS before restart');
}else{
 b('reload');b('wait','[data-ready=true]');b('wait','[data-task-uid]');assert.deepEqual(state(),JSON.parse(readFileSync(resolve(workspace,'browser-before-restart.json'),'utf8')));b('screenshot',resolve(evidence,'after-server-restart.png'));writeFileSync(resolve(evidence,'browser-restart.json'),JSON.stringify({tasks_links_uids_preferences_and_authenticated_session_preserved:true},null,2));b('close');console.log('PASS real Rails restart');
}
