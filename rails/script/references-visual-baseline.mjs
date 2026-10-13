import {execFileSync} from 'node:child_process';import {writeFileSync} from 'node:fs';import {resolve} from 'node:path';import assert from 'node:assert/strict';
const evidence=resolve(import.meta.dirname,'../../docs/assets/p1.2d3'),args=['--session','accio-d3-p04-visual-'+process.pid,'--json'],env={...process.env,XDG_RUNTIME_DIR:'/tmp'};
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{env,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data;};
const ev=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{env,input:code,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data.result;};
const geometry=[];
try{
 b('--args','--no-sandbox','open','http://127.0.0.1:3112/#/projects');b('wait','.inner-page');b('snapshot','-i');const id=ev('JSON.parse(localStorage.getItem("accio-hub-p0.3-studio")).projects[0].id');b('open','http://127.0.0.1:3112/#/projects/'+encodeURIComponent(id)+'/references');b('wait','.project-space');
 for(const theme of ['dark','light']){
  ev(`const state=JSON.parse(localStorage.getItem('accio-hub-p0.3-studio'));state.theme=${JSON.stringify(theme)};localStorage.setItem('accio-hub-p0.3-studio',JSON.stringify(state));true`);b('reload');b('wait','.inner-page');
  for(const width of [320,390,768,1440,1920]){
   b('set','viewport',String(width),'1000');b('snapshot','-i');b('screenshot',resolve(evidence,`p04-references-${theme}-${width}.png`));b('snapshot','-i');b('click','[data-space-action=new-reference]');b('wait','#space-form');b('screenshot',resolve(evidence,`p04-form-${theme}-${width}.png`));b('press','Escape');geometry.push({theme,width,elements:ev(`Array.from(document.querySelectorAll('.rail,.headbar,.music-zone,.inner-page h1')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {class:el.className,width:r.width,height:r.height,font:s.fontFamily}})`)});
  }
 }
 writeFileSync(resolve(evidence,'p04-reference-geometry.json'),JSON.stringify(geometry,null,2));
}finally{b('close');}
