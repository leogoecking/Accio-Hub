// F08: contraste, região de busca e atalhos; somente dados sintéticos e loopback.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../',import.meta.url));
const origin=new URL(process.argv[2]??'http://127.0.0.1:4174');
assert.ok(['127.0.0.1','localhost'].includes(origin.hostname));
const before=process.argv.includes('--before'),phase=before?'before':'after';
const dir=`${root}/tmp/p04-f08-verification/${phase}`,key='accio-hub-p0.3-studio';
mkdirSync(dir,{recursive:true});
const args=['--namespace','accio-p04-f08','--session',`search-${phase}-${process.pid}`,'--json'];
if(process.env.ACCIO_BROWSER_NO_SANDBOX==='1')args.push('--args','--no-sandbox');
function b(...cmd){const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',env:{...process.env,XDG_RUNTIME_DIR:'/tmp'},timeout:45000}));assert.equal(r.success,true,JSON.stringify(r));return r.data;}
const ev=code=>b('eval','-b',Buffer.from(code).toString('base64')).result;
const save=(name,data)=>writeFileSync(`${dir}/${name}.json`,JSON.stringify(data,null,2));
let sequence=0;const snap=()=>save(`snapshot-${++sequence}`,b('snapshot','-i'));
const click=selector=>{snap();b('click',selector);};
const go=route=>{b('open',new URL(`/prototype/#/${route}`,origin).href);b('wait','.viewport');snap();};
const results=[],matrix=[];
function test(name,fn){fn();results.push({name,result:'PASS'});save('results',results);console.log('PASS '+name);}
function audit(name){const a=b('a11y');save(`axe-${name}`,a);if(!before)assert.deepEqual(a.violations,[],JSON.stringify(a.violations));return a;}
const measure=`(()=>{
 const panel=document.querySelector('.search-modal'),r=panel.getBoundingClientRect();
 const background=getComputedStyle(panel).backgroundColor;
 const rgb=s=>s.match(/[\\d.]+/g).slice(0,3).map(Number);
 const luminance=s=>rgb(s).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((n,v,i)=>n+v*[.2126,.7152,.0722][i],0);
 const contrast=(a,b)=>{const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)};
 const texts=[...document.querySelectorAll('.search-field > span,.search-results small')].map(e=>{const c=getComputedStyle(e);return {text:e.textContent,color:c.color,background,ratio:contrast(c.color,background),font:c.fontFamily,size:c.fontSize}});
 return {rect:{x:r.x,y:r.y,width:r.width,height:r.height},texts,searchRegion:!!panel.closest('search,[role=search]'),regionName:panel.getAttribute('aria-label'),focus:document.activeElement.id};
})()`;
try{
 go('home');const fixture=JSON.parse(readFileSync(new URL('./fixtures/schema-3.json',import.meta.url),'utf8'));
 fixture.notes[0].tags=['sintetica-f08'];fixture.notes[0].body+='\nConteúdo exclusivo: agulha-f08.';
 ev(`localStorage.clear();localStorage.setItem('${key}',${JSON.stringify(JSON.stringify(fixture))})`);b('reload');b('wait','.board');
 test(before?'Reprodução F08 nos dois temas e cinco larguras':'F08: contraste ≥ 4,5:1 e região nomeada nos dois temas e cinco larguras',()=>{
  for(const theme of ['light','dark'])for(const width of [320,390,768,1440,1920]){
   go('settings');snap();b('select','#theme-select',theme);b('set','viewport',String(width),'1000');go('home');click('[data-action=search]');b('wait','#command-search');
   save(`tree-${theme}-${width}`,b('snapshot'));const a=audit(`${theme}-${width}`),m=ev(measure);matrix.push({theme,width,...m});save('matrix',matrix);
   b('screenshot',`${dir}/search-${theme}-${width}.png`);
   if(before&&theme==='light'){assert.ok(m.texts.every(t=>t.ratio<4.5));assert.ok(a.violations.some(v=>v.id==='color-contrast'));assert.ok(a.violations.some(v=>v.id==='region'));}
   if(!before){assert.ok(m.texts.every(t=>t.ratio>=4.5));assert.equal(m.searchRegion,true);assert.ok(m.regionName);assert.equal(m.focus,'command-search');assert.ok(m.rect.x>=0&&m.rect.x+m.rect.width<=width);
    const prior=`${root}/tmp/p04-f08-verification/before/matrix.json`;if(existsSync(prior)){const old=JSON.parse(readFileSync(prior)).find(x=>x.theme===theme&&x.width===width);assert.deepEqual(m.rect,old.rect);assert.deepEqual(m.texts.map(t=>[t.text,t.font,t.size]),old.texts.map(t=>[t.text,t.font,t.size]));}
   }
   b('press','Escape');assert.equal(ev('document.querySelector(".search-modal")'),null);
  }
 });
 if(!before){
  test('Ctrl+K/Meta+K, foco inicial, Tab/Shift+Tab, Escape e navegação por resultado',()=>{
   for(const theme of ['light','dark']){
    go('settings');snap();b('select','#theme-select',theme);go('home');
    for(const shortcut of ['Control+k','Meta+k']){b('press',shortcut);assert.equal(ev('document.activeElement.id'),'command-search');b('press','Escape');assert.equal(ev('document.querySelector(".search-modal")'),null);}
    b('press','Control+k');snap();b('fill','#command-search','Projetos');b('press','Tab');assert.equal(ev('document.activeElement.dataset.result'),'page:projects');b('press','Shift+Tab');assert.equal(ev('document.activeElement.id'),'command-search');b('press','Tab');audit(`keyboard-${theme}`);b('press','Enter');assert.equal(ev('location.hash'),'#/projects');assert.equal(ev('document.querySelector(".search-modal")'),null);
   }
  });
  test('Notas encontradas por título, conteúdo e tags abrem o mesmo ID',()=>{
   for(const theme of ['light','dark'])for(const query of ['Ideias para o Accio Hub','agulha-f08','sintetica-f08']){
    go('settings');snap();b('select','#theme-select',theme);
    go('home');b('press','Control+k');snap();b('fill','#command-search',query);assert.equal(ev('[...document.querySelectorAll("[data-result]")].filter(e=>e.dataset.result==="note:1").length'),1);b('press','Tab');assert.equal(ev('document.activeElement.dataset.result'),'note:1');audit(`note-${theme}-${query==='agulha-f08'?'content':query==='sintetica-f08'?'tag':'title'}`);if(query==='agulha-f08')b('screenshot',`${dir}/note-result-${theme}.png`);b('press','Enter');assert.equal(ev('location.hash'),'#/knowledge/1');assert.match(ev('document.querySelector("#note-editor").value'),/agulha-f08/);
   }
  });
  test('Tarefa encontrada por título mantém navegação existente para Tarefas',()=>{
   for(const theme of ['light','dark']){go('settings');snap();b('select','#theme-select',theme);
   go('home');b('press','Control+k');snap();b('fill','#command-search','Tarefa pessoal preservada');assert.equal(ev('[...document.querySelectorAll("[data-result]")].filter(e=>e.dataset.result==="task:1").length'),1);b('press','Tab');audit(`task-${theme}`);b('screenshot',`${dir}/task-result-${theme}.png`);b('press','Enter');assert.equal(ev('location.hash'),'#/tasks');assert.ok(ev('document.body.textContent.includes("Tarefa pessoal preservada")'));}
  });
  test('Estado vazio acessível nos dois temas, Escape e reabertura sem consulta anterior',()=>{
   for(const theme of ['light','dark']){
    go('settings');snap();b('select','#theme-select',theme);go('home');b('press','Control+k');snap();b('fill','#command-search','sem-resultado-sintetico-f08');assert.equal(ev('document.querySelectorAll("[data-result]").length'),0);assert.match(ev('document.querySelector(".search-results").textContent'),/Nenhum resultado encontrado/);audit(`empty-${theme}`);b('screenshot',`${dir}/empty-${theme}.png`);b('press','Escape');b('press','Control+k');assert.equal(ev('document.querySelector("#command-search").value'),'');b('press','Escape');
   }
  });
 }
 const errors=b('errors');save('errors',errors);assert.deepEqual(errors.errors,[]);
}finally{b('close');}
