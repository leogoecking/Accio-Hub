// Local synthetic comparison of selector click, physical pointer and keyboard.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs'
import {resolve} from 'node:path'
import {execFileSync} from 'node:child_process'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),workspace=readFileSync(resolve(root,'rails/tmp/p12d3-workspace'),'utf8').trim()
assert.ok(workspace.startsWith(resolve(root,'rails/tmp/p12d3-browser-')))
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE);mkdirSync(evidence,{recursive:true})
const path=JSON.parse(readFileSync(process.env.ACCIO_QA_TRACE||resolve(evidence,'../original/trace.json'),'utf8')).state.path
assert.match(path,/^\/projects\/u-[A-Za-z0-9_-]+$/)
const credential=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8'))
const args=['--session',process.env.ACCIO_QA_SESSION,'--json'],origin='http://127.0.0.1:3126'
function b(...cmd){const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data}
function ev(code){const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data.result}
const wait=code=>b('wait','--fn',code),results=[]
const state=`(()=>{const a=document.querySelector('#task-new-context'),r=a.getBoundingClientRect();return {rect:{x:r.x,y:r.y,width:r.width,height:r.height},rects:[...a.getClientRects()].map(r=>({x:r.x,y:r.y,width:r.width,height:r.height})),hit:document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.tagName,scroll:document.querySelector('main').scrollTop,dialog:!!document.querySelector('[data-task-dialog][open]')}})()`
function record(name){results.push({name,state:ev(state),events:ev('window.__pointerTrace')});writeFileSync(resolve(evidence,'comparison.json'),JSON.stringify(results,null,2)+'\n');b('screenshot',resolve(evidence,name+'.png'))}
try{
 b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i');b('fill','#email_address',credential.email);ev(`document.querySelector('#password').value=${JSON.stringify(credential.password)};true`);b('click','.login-card [type=submit]');wait('!!document.querySelector("[data-controller=studio][data-ready=true]")');b('set','viewport','1440','1000');b('open',origin+path);wait('!!document.querySelector("#task-new-context")&&!!document.querySelector("[data-controller=studio][data-ready=true]")')
 ev(`window.__pointerTrace=[];for(const type of ['pointerdown','mousedown','mouseup','click','turbo:before-fetch-request','turbo:before-fetch-response','turbo:frame-load'])document.addEventListener(type,e=>{const a=document.querySelector('#task-new-context'),r=a.getBoundingClientRect();window.__pointerTrace.push({type,x:e.clientX,y:e.clientY,target:e.target.tagName,id:e.target.id,classes:String(e.target.className),anchor:e.target.closest?.('a')?.id,text:e.target.textContent?.trim().slice(0,80),trusted:e.isTrusted,url:String(e.detail?.url||e.detail?.fetchResponse?.response?.url||''),status:e.detail?.fetchResponse?.response?.status,rect:{x:r.x,y:r.y,width:r.width,height:r.height}})},true);true`)
 record('before');b('snapshot','-i');b('click','#task-new-context');record('selector-click')
 if(ev('window.__pointerTrace.some(e=>e.type==="turbo:before-fetch-request")')){wait('!!document.querySelector("[data-task-dialog][open]")');wait('document.querySelector("#task-modal").hasAttribute("complete")&&!document.querySelector("#task-modal").hasAttribute("busy")');record('selector-open')}
 if(ev('!!document.querySelector("[data-task-dialog][open]")')){b('press','Escape');wait('!document.querySelector("[data-task-dialog][open]")')}
 const r=ev(state).rect;b('mouse','move',String(Math.round(r.x+r.width/2)),String(Math.round(r.y+r.height/2)));b('mouse','down');b('mouse','up');wait('!!document.querySelector("[data-task-dialog][open]")');wait('document.querySelector("#task-modal").hasAttribute("complete")&&!document.querySelector("#task-modal").hasAttribute("busy")');record('physical-pointer-open');b('press','Escape');wait('!document.querySelector("[data-task-dialog][open]")')
 b('focus','#task-new-context');b('press','Enter');wait('!!document.querySelector("[data-task-dialog][open]")');record('keyboard-open');assert.deepEqual(b('errors').errors||[],[])
}catch(e){console.error(e.stack);process.exitCode=1}finally{b('close')}
