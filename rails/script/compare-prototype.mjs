import {execFileSync} from 'node:child_process';import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';import {resolve} from 'node:path';import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'../..'),out=resolve(root,'tmp/p11-verification');mkdirSync(out,{recursive:true});
const prefix=`accio-p11-compare-${process.pid}`;
const command=(session,...args)=>{const r=JSON.parse(execFileSync('agent-browser',['--session',session,'--json',...args],{encoding:'utf8',timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:'/tmp'}}));assert.ok(r.success,JSON.stringify(r));return r.data;};
const evaluate=(session,code)=>command(session,'eval','-b',Buffer.from(code).toString('base64')).result;
const geometry=()=>`Array.from(document.querySelectorAll('.rail,.headbar,.music-zone,.board-titleline,.app-dock,.widget-grid,[data-widget]')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {key:el.dataset.widget||el.className,x:r.x,y:r.y,width:r.width,height:r.height,font:s.fontFamily};})`;
const credentials=JSON.parse(readFileSync(resolve(root,'rails/tmp/p11-browser-credentials.json')));
const pairs=[];
try {
 command(prefix+'-rails','--args','--no-sandbox','open','http://127.0.0.1:3111/');command(prefix+'-rails','fill','#email_address',credentials.email);command(prefix+'-rails','fill','#password',credentials.password);command(prefix+'-rails','click','input[type=submit]');command(prefix+'-rails','wait','[data-ready=true]');
 // Reset only this isolated browser's encrypted appearance cookie through the real endpoint.
 evaluate(prefix+'-rails',`fetch('/appearance',{method:'PATCH',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({appearance:JSON.parse(document.querySelector('[data-studio-defaults-value]').dataset.studioDefaultsValue)})}).then(r=>r.json())`);
 command(prefix+'-rails','reload');command(prefix+'-rails','wait','[data-ready=true]');
 command(prefix+'-prototype','--args','--no-sandbox','open','http://127.0.0.1:3112/#/home');evaluate(prefix+'-prototype','localStorage.clear()');command(prefix+'-prototype','reload');command(prefix+'-prototype','wait','.board');
 for(const theme of ['dark','light']){
  evaluate(prefix+'-rails',`fetch('/appearance',{method:'PATCH',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({appearance:{...JSON.parse(document.querySelector('[data-studio-defaults-value]').dataset.studioDefaultsValue),theme:'${theme}'}})}).then(r=>r.json())`);command(prefix+'-rails','reload');command(prefix+'-rails','wait','[data-ready=true]');
  evaluate(prefix+'-prototype',`const s=JSON.parse(localStorage.getItem('accio-hub-p0.3-studio'));s.theme='${theme}';localStorage.setItem('accio-hub-p0.3-studio',JSON.stringify(s))`);command(prefix+'-prototype','reload');command(prefix+'-prototype','wait','.board');
  for(const width of [320,390,768,1440,1920]){
   for(const type of ['rails','prototype']){command(prefix+'-'+type,'set','viewport',String(width),'1000');evaluate(prefix+'-'+type,'document.fonts.ready');command(prefix+'-'+type,'screenshot',resolve(root,`docs/assets/p1.1/compare-${type}-${theme}-${width}.png`));}
   const rails=evaluate(prefix+'-rails',geometry()),prototype=evaluate(prefix+'-prototype',geometry());
   const differences=rails.flatMap(r=>{const p=prototype.find(p=>p.key===r.key);return p?['x','y','width','height'].filter(k=>Math.abs(r[k]-p[k])>1).map(k=>({key:r.key,metric:k,rails:r[k],prototype:p[k],delta:r[k]-p[k]})):[{key:r.key,missing:true}];});pairs.push({theme,width,differences,rails,prototype});console.log(theme,width,JSON.stringify(differences));
  }
 }
 writeFileSync(resolve(out,'comparison.json'),JSON.stringify(pairs,null,2));
}finally{command(prefix+'-rails','close');command(prefix+'-prototype','close');}
