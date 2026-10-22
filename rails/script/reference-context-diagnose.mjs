// Instrument the first D3 scenario; optional HEAD baseline preserves the old actions.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs'
import {resolve} from 'node:path'
import {spawnSync,execFileSync} from 'node:child_process'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),rails=resolve(root,'rails')
const workspace=readFileSync(resolve(rails,'tmp/p12d3-workspace'),'utf8').trim()
assert.ok(workspace.startsWith(resolve(rails,'tmp/p12d3-browser-')))
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE);mkdirSync(evidence,{recursive:true})
const traceInit=`
window.__contextTrace=[];
window.__contextState=()=>{const a=document.querySelector('#task-new-context'),f=document.querySelector('#task-modal'),r=a?.getBoundingClientRect();return {path:location.pathname,preview:document.documentElement.hasAttribute('data-turbo-preview'),busy:document.documentElement.hasAttribute('aria-busy'),ready:document.querySelector('[data-controller=studio]')?.dataset.ready,anchor:a&&{id:a.id,href:a.getAttribute('href'),text:a.textContent,frame:a.dataset.turboFrame,connected:a.isConnected,rect:{x:r.x,y:r.y,width:r.width,height:r.height}},frame:f&&{src:f.getAttribute('src'),busy:f.hasAttribute('busy'),complete:f.hasAttribute('complete')},dialogs:[...document.querySelectorAll('dialog')].map(d=>({id:d.id,task:d.hasAttribute('data-task-dialog'),open:d.open})),focus:document.activeElement?.id}};
for(const type of ['pointerdown','mousedown','mouseup','click','turbo:click','turbo:before-visit','turbo:before-fetch-request','turbo:before-fetch-response','turbo:frame-render','turbo:frame-load','turbo:load'])document.addEventListener(type,e=>{const a=e.target.closest?.('a'),target=e.target;const item={type,at:performance.now(),target:target.id||target.tagName,classes:String(target.className),x:e.clientX,y:e.clientY,state:window.__contextState(),anchor:a?.id,href:a?.getAttribute('href'),trusted:e.isTrusted,prevented:e.defaultPrevented,url:String(e.detail?.url||e.detail?.fetchResponse?.response?.url||''),status:e.detail?.fetchResponse?.response?.status};if(a?.id==='task-new-context')item.state=window.__contextState();window.__contextTrace.push(item)},true);
`
let source=process.env.ACCIO_QA_BASELINE==='1'?execFileSync('git',['show','HEAD:rails/script/references-browser-check.mjs'],{cwd:root,encoding:'utf8'}):readFileSync(resolve(rails,'script/references-browser-check.mjs'),'utf8')
source=source.replace("const root=resolve(import.meta.dirname,'../..');",`const root=${JSON.stringify(root)};`)
source=source.replace('function b(...cmd)',`writeFileSync(init,readFileSync(init,'utf8')+${JSON.stringify(traceInit)});\nfunction b(...cmd)`)
const cut=source.indexOf(" scenario('Diálogo inicial")
assert.ok(cut>0)
source=source.slice(0,cut)+`\n writeFileSync(resolve(evidence,'completed.json'),JSON.stringify({firstScenarioCompleted:true,results}));\n}catch(error){console.error(error.stack);process.exitCode=1}finally{try{const trace=evaluate('({events:window.__contextTrace,state:window.__contextState(),errors:window.__qaErrors,resources:performance.getEntriesByType("resource").map(e=>({name:e.name,status:e.responseStatus}))})');writeFileSync(resolve(evidence,'trace.json'),JSON.stringify(trace,null,2)+'\\n');screenshot('context-final');writeFileSync(resolve(evidence,'snapshot.json'),JSON.stringify(b('snapshot','-i'),null,2)+'\\n')}finally{b('close')}}\n`
const file=resolve(workspace,'context-probe.mjs');writeFileSync(file,source)
const result=spawnSync('node',[file],{env:{...process.env,ACCIO_QA_EVIDENCE:evidence},encoding:'utf8',timeout:180000})
writeFileSync(resolve(evidence,'run.log'),(result.stdout||'')+(result.stderr||''))
console.log(JSON.stringify({exit:result.status,evidence}))
process.exitCode=result.status||0
