import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {migrateState,openState,STATE_KEY} from '../state.mjs';
import {createProject,updateProject,favoriteProject,changeProjectStatus,restoreProject,touchProjects,projectCounts,selectProjects} from '../projects.mjs';
const preamble=readFileSync(new URL('../app.js',import.meta.url),'utf8').split('function showStorageStatus')[0].replace(/^import .*;$/gm,'');
const defaults=JSON.parse(JSON.stringify(runInNewContext(preamble+';defaults')));
const schema1=JSON.parse(readFileSync(new URL('./fixtures/schema-1.json',import.meta.url),'utf8'));
const fresh=()=>migrateState(structuredClone(schema1),defaults);
const input={name:'Laboratório orbital',description:'Exploração de ideias',icon:'code',color:'#799cdb'};
const now=Date.parse('2026-10-10T12:00:00Z');
function storage(raw){const entries=new Map([[STATE_KEY,raw],[STATE_KEY+':backup:pre-schema-1','backup antigo']]);return {entries,writes:[],fail:false,getItem:k=>entries.get(k)??null,setItem(k,v){if(this.fail)throw Error('Quota');this.writes.push(k);entries.set(k,v);}};}
test('schema 1 real: preserva IDs, conteúdo, extras, preferências e backup anterior',()=>{
  const raw=JSON.stringify(schema1),s=storage(raw),session=openState({storage:s,defaults});
  assert.equal(session.state.schemaVersion,3);assert.equal(s.getItem(session.status.backupKey),raw);
  assert.equal(s.getItem(STATE_KEY+':backup:pre-schema-1'),'backup antigo');
  for(const key of Object.keys(schema1).filter(k=>!['schemaVersion','projects'].includes(k)))assert.deepEqual(session.state[key],schema1[key],key);
  session.state.projects.forEach((p,i)=>{for(const k of Object.keys(schema1.projects[i]))assert.deepEqual(p[k],schema1.projects[i][k]);assert.equal(p.status,'active');assert.equal(p.favorite,false);assert.equal(p.updatedAt,null);assert.equal(p.color,null);});
  const before=s.getItem(STATE_KEY),writes=s.writes.length;openState({storage:s,defaults});assert.equal(s.getItem(STATE_KEY),before);assert.equal(s.writes.length,writes);
});
test('backup de schema 1 obrigatório antes de qualquer alteração',()=>{
  const raw=JSON.stringify(schema1),s=storage(raw);s.fail=true;const session=openState({storage:s,defaults});assert.equal(s.getItem(STATE_KEY),raw);assert.equal(session.save(session.state),false);assert.equal(s.getItem(STATE_KEY),raw);
});
test('criação única com ID persistente, cor, ícone e datas; evita colisões',()=>{
  const state=fresh(),ids=[String(state.tasks[0].id),'novo-id'];const p=createProject(state,input,{createId:()=>ids.shift(),now});assert.equal(p.id,'novo-id');assert.equal(p.status,'active');assert.equal(p.createdAt,new Date(now).toISOString());assert.equal(p.updatedAt,p.createdAt);assert.equal(state.projects.length,5);assert.deepEqual(migrateState(state,defaults),state);
});
test('duplicação acidental é rejeitada antes de gerar ID; inclusive nome arquivado',()=>{
  const state=fresh(),p=createProject(state,input,{createId:()=> 'new',now});changeProjectStatus(state,p.id,'archived');const before=structuredClone(state);
  assert.throws(()=>createProject(state,{...input,name:'  LABORATÓRIO   ORBITAL '},{createId:()=>{throw Error('ID não deveria ser gerado');}}),/Já existe/);assert.deepEqual(state,before);
});
test('edição renomeia sem romper tarefas/notas, mantém extras e não duplica registros',()=>{
  const state=fresh(),p=state.projects.find(p=>p.name==='Accio Hub'),before=structuredClone(state),id=p.id;
  updateProject(state,id,{...input,name:'Hub renovado'},now);assert.equal(p.id,id);assert.equal(state.projects.length,before.projects.length);assert.deepEqual(state.tasks,before.tasks);assert.deepEqual(state.notes,before.notes);assert.deepEqual(projectCounts(state,id),{open:1,total:1,notes:1});
  const after=structuredClone(state);updateProject(state,id,{...input,name:'Hub renovado'},now+1000);assert.deepEqual(state,after);
  assert.throws(()=>updateProject(state,id,{...input,name:state.projects.find(x=>x.id!==id).name}),/Já existe/);assert.deepEqual(state,after);
});
test('arquivar/restaurar é idempotente, preserva conteúdo e retorna ao status pausado',()=>{
  const state=fresh(),p=state.projects.find(p=>p.name==='Accio Hub'),content=structuredClone({tasks:state.tasks,notes:state.notes});
  changeProjectStatus(state,p.id,'paused',now);changeProjectStatus(state,p.id,'archived',now+1);const archived=structuredClone(p);changeProjectStatus(state,p.id,'archived',now+2);assert.deepEqual(p,archived);assert.equal(p.archivedFrom,'paused');restoreProject(state,p.id,now+3);assert.equal(p.status,'paused');const restored=structuredClone(p);restoreProject(state,p.id,now+4);assert.deepEqual(p,restored);assert.deepEqual({tasks:state.tasks,notes:state.notes},content);
});
test('favoritos/status/cores/preferências persistem e seleção não altera a ordem original',()=>{
  const s=storage(JSON.stringify(schema1)),session=openState({storage:s,defaults}),state=session.state,p=state.projects[0];favoriteProject(state,p.id);changeProjectStatus(state,p.id,'paused',now);updateProject(state,p.id,{...input,name:p.name},now);state.projectLibrary={status:'paused',sort:'recent',favoritesOnly:true};assert.equal(session.save(state),true);const after=openState({storage:s,defaults}).state;assert.deepEqual(after,state);const order=state.projects.map(p=>p.id);assert.deepEqual(selectProjects(state).map(x=>x.id),[p.id]);assert.deepEqual(state.projects.map(p=>p.id),order);
});
test('pesquisa nome/descrição sem acentos, filtros independentes e ordenação recente',()=>{
  const state=fresh(),p=createProject(state,input,{createId:()=> 'lab',now});assert.equal(selectProjects(state,'exploracao')[0].id,p.id);assert.equal(selectProjects(state,'LABORATORIO')[0].id,p.id);assert.equal(selectProjects(state,'inexistente').length,0);assert.equal(selectProjects(state,'',{status:'all',sort:'recent',favoritesOnly:false})[0].id,p.id);changeProjectStatus(state,p.id,'archived',now+1);assert.equal(selectProjects(state,'',{status:'active',sort:'name',favoritesOnly:false}).length,4);assert.equal(selectProjects(state,'',{status:'archived',sort:'name',favoritesOnly:false})[0].id,p.id);
});
test('atividade considera vínculos por ID, favoritismo não inventa atividade',()=>{
  const state=fresh(),p=state.projects[0],other=state.projects[1];favoriteProject(state,p.id);assert.equal(p.updatedAt,null);touchProjects(state,[p.id,p.id],now);assert.equal(p.updatedAt,new Date(now).toISOString());assert.equal(other.updatedAt,null);assert.equal(state.projects.length,4);
});
test('biblioteca vazia permanece vazia até criação explícita',()=>{
  const state=migrateState({projects:[],tasks:[],notes:[]},defaults);assert.deepEqual(selectProjects(state),[]);createProject(state,input,{createId:()=> 'only',now});assert.equal(state.projects.length,1);assert.deepEqual(state.tasks,[]);assert.deepEqual(state.notes,[]);
});
test('campos inválidos não causam mutação parcial',()=>{
  for(const invalid of [{name:''},{name:'x'.repeat(81)},{description:'x'.repeat(501)},{icon:'__proto__'},{color:'red'}]){const state=fresh(),before=structuredClone(state);assert.throws(()=>createProject(state,{...input,...invalid}));assert.deepEqual(state,before);}
});
test('schema 3 inválido/futuro é protegido sem sobrescrita',()=>{
  for(const mutate of [s=>s.schemaVersion=99,s=>s.projects[0].status='deleted',s=>s.projects[0].favorite='yes',s=>s.projects[0].updatedAt='invalid',s=>s.projectLibrary.sort='unknown']){const state=fresh();mutate(state);const raw=JSON.stringify(state),s=storage(raw),session=openState({storage:s,defaults});assert.equal(session.status.code,'blocked');assert.equal(session.save(session.state),false);assert.equal(s.getItem(STATE_KEY),raw);assert.deepEqual(s.writes,[]);}
});
