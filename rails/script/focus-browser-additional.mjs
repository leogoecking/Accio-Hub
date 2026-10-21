// Additional C integration, transport failures and targeted accessibility evidence.
import {execFileSync} from 'node:child_process'
import {readFileSync,writeFileSync} from 'node:fs'
import {resolve} from 'node:path'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),directory=readFileSync(resolve(root,'rails/tmp/p12e2-workspace'),'utf8').trim(),evidence=resolve(root,'docs/assets/p1.2e2')
assert.ok(directory.startsWith(resolve(root,'rails/tmp/p12e2-browser-')))
const credentials=JSON.parse(readFileSync(resolve(directory,'credentials.json'),'utf8')),ids=JSON.parse(readFileSync(resolve(directory,'state.json'),'utf8'))
const args=['--session',process.env.ACCIO_QA_SESSION || 'accio-p12e2-live','--json'],resume=Number(process.env.ACCIO_QA_RESUME||0),results=resume?JSON.parse(readFileSync(resolve(evidence,'browser-extra-results.json'),'utf8')).slice(0,resume):[];let index=0
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data}
const ev=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data.result}
const c=`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`,s=`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio')`
const wait=code=>b('wait','--fn',code),settle=()=>wait(`${c}.client.confirmed&&!${c}.client.sending&&!${c}.preparing&&!${c}.dialogPending`)
const activate=selector=>{b('snapshot','-i');b('focus',selector);b('press','Enter')}
const confirm=()=>{activate('[data-focus-target=dialogConfirm]');wait('!document.querySelector(".focus-dialog").open');settle()}
const snap=()=>ev(`${c}.client.snapshot`)
const navigate=path=>{b('open','http://127.0.0.1:3127'+path);settle()}
const drawer=()=>{activate('[data-open=customize]');wait('document.querySelector("#customize").open')}
const saved=()=>wait('document.querySelector("[data-save-status]").hidden')
const cancel=()=>{if(snap().session){activate('[data-focus-cancel]');confirm()}}
const scenario=(name,fn)=>{if(index++<resume)return;fn();results.push({name,result:'PASS'});writeFileSync(resolve(evidence,'browser-extra-results.json'),JSON.stringify(results,null,2)+'\n');console.log('PASS '+name)}
try{
 b('--args','--no-sandbox','open','http://127.0.0.1:3127/apps/focus');settle();cancel();if(resume<6){activate('[data-focus-primary]');settle()}const uid=snap().session?.uid
 scenario('Dock Widgets Music and hiding the focus widget preserve the global running session',()=>{
  navigate('/');const before=ev(`${s}.preferences`);drawer();b('uncheck','[data-visible=focus]');saved();b('select','[data-span=focus]','4');saved();activate('[data-order=dock][data-id=focus][data-direction="1"]');saved();b('press','Escape');assert.equal(ev('document.querySelector("[data-widget=focus]").hidden'),true)
  activate('[data-music-expand]');saved();assert.equal(snap().session.uid,uid);navigate('/apps/focus');assert.equal(snap().session.uid,uid);assert.equal(snap().session.status,'running')
  drawer();b('check','[data-visible=focus]');saved();b('select','[data-span=focus]',String(before.widgets.find(w=>w.id==='focus').span));saved();activate('[data-order=dock][data-id=focus][data-direction="-1"]');saved();b('press','Escape')
 })
 scenario('Logout and login preserve appearance preferences and same global focus UID',()=>{
  const before=ev(`${s}.preferences`);activate('.rail-avatar');b('wait','#password');b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);activate('.login-card [type=submit]');settle();assert.equal(snap().session.uid,uid);assert.deepEqual(ev(`${s}.preferences`),before)
 })
 scenario('Existing focus rejects another task context without changing history or UID',()=>{
  navigate('/tasks');activate('#task-focus-'+ids.task);assert.match(ev(`${c}.client.message`),/Já existe um Pomodoro global/);assert.equal(snap().session.uid,uid);assert.equal(snap().session.task_uid,null);navigate('/apps/focus')
 })
 scenario('503 retains exact command envelope and safe retry pauses once',()=>{
  ev(`window.__actualFetch=fetch;window.__attempts=[];window.fetch=(url,options)=>{if(String(url).includes('/commands')&&options?.method==='POST'){window.__attempts.push(options.body);if(window.__attempts.length===1)return Promise.resolve(new Response(JSON.stringify({error:'database_busy',message:'Armazenamento ocupado sintético. Tente novamente.'}),{status:503,headers:{'Content-Type':'application/json'}}))}return window.__actualFetch(url,options)};true`)
  activate('[data-focus-primary]');settle();assert.ok(ev(`${c}.client.pending`));assert.match(ev(`${c}.client.message`),/ocupado/);activate('[data-focus-target=retry]');settle();assert.equal(snap().session.status,'paused');assert.equal(ev('window.__attempts[0]===window.__attempts[1]'),true);ev('window.fetch=window.__actualFetch;true')
 })
 scenario('Request deadline exposes uncertainty then retries the identical command',()=>{
  activate('[data-focus-primary]');settle()
  ev(`window.__actualFetch=fetch;window.__attempts=[];window.fetch=(url,options)=>{if(String(url).includes('/commands')&&options?.method==='POST'){window.__attempts.push(options.body);if(window.__attempts.length===1)return new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new Error('Timeout sintético'))))}return window.__actualFetch(url,options)};true`)
  activate('[data-focus-primary]');wait(`${c}.client.pending&&!${c}.client.sending`);settle();assert.match(ev(`${c}.client.message`),/não confirmada/);assert.equal(snap().session.status,'running');activate('[data-focus-target=retry]');settle();assert.equal(snap().session.status,'paused');assert.equal(ev('window.__attempts[0]===window.__attempts[1]'),true);ev('window.fetch=window.__actualFetch;true');cancel()
 })
 scenario('Timer does not announce each second and reduced motion disables focus transitions',()=>{
  b('set','media','light','reduced-motion');assert.equal(ev('matchMedia("(prefers-reduced-motion: reduce)").matches'),true);assert.equal(ev('document.querySelector("[data-focus-clock]").closest("[aria-live]")===null'),true);assert.equal(ev('getComputedStyle(document.querySelector(".dial")).animationName'),'none');assert.equal(ev('getComputedStyle(document.querySelector(".dial")).transitionDuration'),'0s')
 })
 scenario('Close X and Back preserve preset and return focus to the triggering control',()=>{
  const preset=snap().preset_seconds
  for(const selector of ['[aria-label="Fechar diálogo do Pomodoro"]','.focus-dialog [autofocus]']){activate('[data-focus-preset]');wait('document.querySelector(".focus-dialog").open');activate(selector);wait('!document.querySelector(".focus-dialog").open');assert.equal(ev('document.activeElement.hasAttribute("data-focus-preset")'),true);assert.equal(snap().preset_seconds,preset)}
 })
 scenario('Polling preserves keyboard focus on an active control',()=>{
  b('focus','[data-focus-primary]');ev(`${c}.client.read().then(()=>true)`);settle();assert.equal(ev('document.activeElement.hasAttribute("data-focus-primary")'),true)
 })
 const measurements=[]
 for(const theme of ['dark','light']){
  for(const accent of ['#b1f07d','#8050b0','#777777']){
   scenario(`Contrast and dialog accessibility ${theme} ${accent}`,()=>{
    drawer();b('select','#drawer-theme',theme);saved();ev(`(()=>{const input=document.querySelector('#drawer-accent');input.value=${JSON.stringify(accent)};input.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);saved();b('press','Escape');ev(`${c}.paint();true`);activate('[data-focus-preset]');wait('document.querySelector(".focus-dialog").open')
    const result=ev(`(()=>{const button=document.querySelector('[data-focus-target=dialogConfirm]'),style=getComputedStyle(button);const rgb=value=>{const ctx=document.createElement('canvas').getContext('2d');ctx.fillStyle=value;ctx.fillRect(0,0,1,1);return [...ctx.getImageData(0,0,1,1).data].slice(0,3)};const l=rgb=>{const x=rgb.map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return x[0]*.2126+x[1]*.7152+x[2]*.0722};const fg=rgb(style.color),bg=rgb(style.backgroundColor),a=l(fg),b=l(bg);return {foreground:fg,background:bg,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)}})()`)
    assert.ok(result.ratio>=4.5,JSON.stringify(result));measurements.push({theme,accent,...result});const name=`dialog-${theme}-${accent.slice(1)}`;b('screenshot',resolve(evidence,name+'.png'));writeFileSync(resolve(evidence,'axe-'+name+'.json'),JSON.stringify(b('a11y','--json'),null,2)+'\n');b('press','Escape')
   })
  }
 }
 writeFileSync(resolve(evidence,'contrast-measurements.json'),JSON.stringify(measurements,null,2)+'\n');console.log(JSON.stringify({passed:results.length}))
}catch(error){console.error(error.stack);try{b('screenshot',resolve(evidence,'extra-failure-'+Date.now()+'.png'));console.error(JSON.stringify(b('snapshot','-i')))}catch{}process.exitCode=1}
