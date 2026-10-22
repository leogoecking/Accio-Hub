// F2a: synthetic local Rails only; external reference URLs are inspected, never followed.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),rails=resolve(root,'rails')
const workspace=readFileSync(resolve(rails,'tmp/p12d3-workspace'),'utf8').trim()
assert.ok(workspace.startsWith(resolve(rails,'tmp/p12d3-browser-')))
const credentials=JSON.parse(readFileSync(resolve(workspace,'credentials.json'),'utf8'))
const state=JSON.parse(readFileSync(resolve(workspace,'browser-state.json'),'utf8'))
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE||resolve(root,'docs/assets/p1.2f/f2a/browser'));mkdirSync(evidence,{recursive:true})
const session=process.env.ACCIO_QA_SESSION||'accio-f2a-urls',origin='http://127.0.0.1:3126',args=['--session',session,'--json'],results=[]
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data}
const ev=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data.result}
const wait=code=>b('wait','--fn',code),screen=name=>b('screenshot',resolve(evidence,name+'.png'))
const studio=`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=studio]'),'studio')`
const ready=()=>wait('!!document.querySelector("[data-controller=studio][data-ready=true]")&&!document.documentElement.hasAttribute("aria-busy")&&!document.documentElement.hasAttribute("data-turbo-preview")')
function click(selector){b('snapshot','-i');b('scrollintoview',selector);b('click',selector)}
const space=()=>{b('open',origin+'/projects/'+state.project+'?tab=references');ready();wait('!!document.querySelector("#reference-count")')}
const open=(selector='#reference-new')=>{click(selector);wait('!!document.querySelector("[data-reference-dialog][open]")&&document.activeElement.id==="reference-title"')}
const close=()=>{b('press','Escape');wait('!document.querySelector("[data-reference-dialog][open]")')}
const submit=()=>{click('#reference-form [type=submit]');wait('!document.querySelector("[data-reference-dialog][open]")')}
function sql(code){return JSON.parse(execFileSync('bin/rails',['runner',`require 'json';raise 'Synthetic only' unless ActiveRecord::Base.connection_db_config.database==File.join(ENV.fetch('ACCIO_QA_WORKSPACE'),'synthetic.sqlite3');${code}`],{cwd:rails,env:{...process.env,RAILS_ENV:'development',ACCIO_QA_WORKSPACE:workspace,ACCIO_DATABASE_PATH:resolve(workspace,'synthetic.sqlite3')},encoding:'utf8',timeout:45000}).trim())}
const project=`User.find_by!(email_address:'qa@example.test').projects.find_by!(uid:PublicUid.decode(${JSON.stringify(state.project)}))`
const api=(url,body)=>ev(`(async()=>{const r=await fetch(${JSON.stringify(url)},{method:'PATCH',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(${JSON.stringify(body)})});return {status:r.status,data:await r.json()}})()`)
const database=()=>sql(`u=User.find_by!(email_address:'qa@example.test');puts [u.project_references.order(:id).map(&:attributes),u.projects.order(:id).map(&:attributes),u.tasks.order(:id).map(&:attributes),AppearancePreferences.new(u).read,FocusSession.count,FocusCommand.count].to_json`)
function check(name,test){test();assert.deepEqual(b('errors').errors||[],[]);results.push({name,result:'PASS'});writeFileSync(resolve(evidence,'url-browser-results.json'),JSON.stringify(results,null,2)+'\n');console.log('PASS '+name)}
let legacy,created
try{
 b('--args','--no-sandbox','open',origin+'/session/new');b('snapshot','-i');b('fill','#email_address',credentials.email);ev(`document.querySelector('#password').value=${JSON.stringify(credentials.password)};true`);click('.login-card [type=submit]');ready();space();b('set','viewport','1440','1000')
 check('Canonical DNS with numeric labels creates and edits through the existing dialog',()=>{
  const before=database(),n=before[0].length;open();b('fill','#reference-title','F2a DNS legítimo');b('fill','#reference-url','https://3com.example.test/a?q=1#ref');submit();created=sql(`puts ${project}.project_references.find_by!(title:'F2a DNS legítimo').to_param.to_json`);assert.equal(database()[0].length,n+1)
  open('#reference-edit-'+created);b('fill','#reference-url','https://a.42.example/edited');submit();assert.equal(ev(`document.querySelector('[data-reference-uid="${created}"] a[target=_blank]').getAttribute('href')`),'https://a.42.example/edited');assert.equal(ev(`document.querySelector('[data-reference-uid="${created}"] a[target=_blank]').rel`),'noopener noreferrer');assert.equal(database()[4],0);assert.equal(database()[5],0);screen('valid-numeric-dns')
 })
 check('Ambiguous numeric URLs and empty port receive 422 while fields and database remain unchanged',()=>{
  const before=database();open();b('fill','#reference-title','F2a inválida mantida')
  for(const url of ['https://0x7f000001','https://0x7f.0.0.1','http://127.1','http://0177.0.0.1','https://example.test:']){
   b('fill','#reference-url',url);assert.equal(ev('document.querySelector("#reference-url").checkValidity()'),true);click('#reference-form [type=submit]');wait('document.querySelector("[data-reference-dialog] [data-project-notice]").textContent.includes("HTTP/HTTPS")');assert.equal(ev('document.querySelector("#reference-url").value'),url);assert.equal(ev('document.querySelector("#reference-title").value'),'F2a inválida mantida');assert.deepEqual(database(),before)
  }screen('ambiguous-url-rejected');close()
 })
 check('Synthetic legacy records keep Unicode UID original URL and show escaped text with no href',()=>{
  legacy=sql(`p=${project};u=p.user;values=[['legacy/α?%#项目','https://0x7f000001/legacy'],['legacy/html','https://example.123/<img src=x onerror=alert(1)>']];puts values.map{|uid,url|r=p.project_references.create!(user:u,uid:uid,title:'Legado F2a '+uid,kind:'link',url:'https://example.test/seed',description:'Conteúdo original',position:(p.project_references.maximum(:position)||-1)+1);r.update_columns(url:url);{uid:r.to_param,url:url}}.to_json`)
  const before=database();space();for(const row of legacy){assert.equal(ev(`document.querySelector('[data-reference-uid="${row.uid}"] [data-reference-url-incompatible]').textContent`),row.url);assert.equal(ev(`document.querySelector('[data-reference-uid="${row.uid}"] a[target=_blank]')`),null)}assert.equal(ev('document.querySelector(".space-reference img,.space-reference script")'),null);assert.deepEqual(database(),before);b('reload');ready();assert.deepEqual(database(),before);writeFileSync(resolve(workspace,'f2a-legacy.json'),JSON.stringify(legacy));screen('legacy-text-no-links')
 })
 check('Incompatible legacy text fits approved light and dark reference layouts',()=>{
  for(const theme of ['light','dark']){click('[data-open=customize]');b('select','#drawer-theme',theme);wait('document.querySelector("[data-save-status]").hidden');click('#customize [data-close]');for(const width of [320,390,1440]){b('set','viewport',String(width),'1000');assert.equal(ev('document.documentElement.scrollWidth<=innerWidth'),true);assert.equal(ev('document.querySelectorAll("[data-reference-url-incompatible]").length'),2);screen(`legacy-${theme}-${width}`)}}
 })
 check('Legacy edit preserves incompatible URL on rejected save then permits explicit repair without changing UID',()=>{
  b('set','viewport','1440','1000');const before=database();open('#reference-edit-'+legacy[0].uid);assert.equal(ev('document.querySelector("#reference-url").value'),legacy[0].url);b('fill','#reference-title','Legado revisado');click('#reference-form [type=submit]');wait('document.querySelector("[data-reference-dialog] [data-project-notice]").textContent.includes("HTTP/HTTPS")');assert.deepEqual(database(),before);b('fill','#reference-url','https://127.0.0.1/explicit-repair');submit();assert.equal(ev(`document.querySelector('[data-reference-uid="${legacy[0].uid}"] a[target=_blank]').getAttribute('href')`),'https://127.0.0.1/explicit-repair');assert.equal(ev(`document.querySelector('[data-reference-uid="${legacy[0].uid}"] [data-reference-url-incompatible]')`),null);screen('explicit-repair-same-uid')
 })
 check('Archived project preserves incompatible legacy text and blocks edits then restores safely',()=>{
  const refs=database()[0];let version=sql(`puts ${project}.lock_version.to_json`);assert.equal(api('/projects/'+state.project+'/command',{operation:'archive',version}).status,200);space();assert.equal(ev('document.querySelectorAll("[data-reference-opener]").length'),0);assert.equal(ev(`document.querySelector('[data-reference-uid="${legacy[1].uid}"] [data-reference-url-incompatible]').textContent`),legacy[1].url);assert.deepEqual(database()[0],refs);screen('archived-legacy-preserved');version=sql(`puts ${project}.lock_version.to_json`);assert.equal(api('/projects/'+state.project+'/command',{operation:'restore',version}).status,200);space();assert.deepEqual(database()[0],refs);assert.equal(ev('document.querySelector("#reference-new")!==null'),true)
 })
 check('Reading and presenting reference URLs sends no resource request to a reference destination',()=>{
  const resources=ev('performance.getEntriesByType("resource").map(e=>e.name)');assert.ok(resources.every(name=>name.startsWith(origin+'/')||name.startsWith('data:')),JSON.stringify(resources));writeFileSync(resolve(evidence,'reference-resources.json'),JSON.stringify({onlyApplicationResources:true,noReferenceDestinationResourceRequested:true,resources},null,2)+'\n');assert.equal(ev('location.origin'),origin)
 })
 console.log(JSON.stringify({passed:results.length,noReferenceNavigation:true}))
}catch(error){console.error(error.stack);try{screen('failure-'+Date.now());console.error(JSON.stringify(b('snapshot','-i')))}catch{}process.exitCode=1}finally{b('close')}
