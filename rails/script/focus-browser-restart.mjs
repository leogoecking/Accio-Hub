import {execFileSync} from 'node:child_process'
import {readFileSync,writeFileSync} from 'node:fs'
import {resolve} from 'node:path'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),rails=resolve(root,'rails'),directory=readFileSync(resolve(rails,'tmp/p12e2-workspace'),'utf8').trim()
assert.ok(directory.startsWith(resolve(rails,'tmp/p12e2-browser-')))
const args=['--session',process.env.ACCIO_QA_SESSION || 'accio-p12e2-live','--json'],evidence=resolve(process.env.ACCIO_QA_EVIDENCE||resolve(root,'docs/assets/p1.2e2'))
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data}
const ev=code=>{const r=JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data.result}
const c=`window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=focus]'),'focus')`
const settle=()=>b('wait','--fn',`${c}.client.confirmed && !${c}.client.sending && !${c}.dialogPending && !${c}.preparing`)
const activate=selector=>{b('snapshot','-i');b('focus',selector);b('press','Enter')}
const rows=()=>JSON.parse(execFileSync('bin/rails',['runner',`require 'json';raise 'Synthetic only' unless ActiveRecord::Base.connection_db_config.database == File.join(ENV.fetch('E2_WORKSPACE'),'synthetic.sqlite3');puts [FocusSession,FocusCommand,UserPreference,Project,Task,ProjectReference].map{|model|model.order(:id).map(&:attributes)}.to_json`],{cwd:rails,env:{...process.env,RAILS_ENV:'development',E2_WORKSPACE:directory,ACCIO_DATABASE_PATH:resolve(directory,'synthetic.sqlite3')},encoding:'utf8'}))
if(process.argv[2]==='prepare'){
 b('--args','--no-sandbox','open','http://127.0.0.1:3127/apps/focus');settle();if(ev(`${c}.client.snapshot.session`)){activate('[data-focus-cancel]');activate('[data-focus-target=dialogConfirm]');settle()}assert.equal(ev(`${c}.client.snapshot.session`),null)
 activate('[data-focus-primary]');settle();const clockPath=resolve(directory,'clock.json'),clock=JSON.parse(readFileSync(clockPath));clock.wall=new Date(Date.parse(clock.wall)+20000).toISOString();clock.monotonic+=20;writeFileSync(clockPath,JSON.stringify(clock));ev(`${c}.client.read().then(()=>true)`)
 activate('[data-focus-primary]');settle();assert.equal(ev(`${c}.client.snapshot.session.elapsed_seconds`),20);activate('[data-focus-primary]');settle()
 writeFileSync(resolve(directory,'restart-expected.json'),JSON.stringify({rows:rows(),snapshot:ev(`${c}.client.snapshot`)}));console.log('Prepared running session with confirmed checkpoint 20; restart only the private QA server before verify.')
}else{
 const expected=JSON.parse(readFileSync(resolve(directory,'restart-expected.json')));ev(`${c}.client.read().then(()=>true)`);settle();const actual=ev(`${c}.client.snapshot`)
 assert.deepEqual(rows(),expected.rows);assert.equal(actual.session.uid,expected.snapshot.session.uid);assert.equal(actual.session.version,expected.snapshot.session.version);assert.equal(actual.session.elapsed_seconds,20);assert.equal(actual.session.status,'running');assert.equal(actual.timing.continuity,'unknown')
 activate('[data-focus-primary]');settle();assert.ok(ev(`${c}.client.snapshot.recovery.receipt_id`));b('screenshot',resolve(evidence,'restart-recovery.png'));activate('[data-focus-resolve=keep_checkpoint]');settle();assert.equal(ev(`${c}.client.snapshot.session.elapsed_seconds`),20)
 activate('[data-focus-cancel]');activate('[data-focus-target=dialogConfirm]');settle()
 const result={result:'PASS',same_uid:true,same_version:true,checkpoint_preserved:20,identical_database_after_restart_and_GET:true,recovery_after_process_change:true,kept_checkpoint:true};writeFileSync(resolve(evidence,'browser-restart.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result))
}
