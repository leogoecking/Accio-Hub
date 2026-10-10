import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {migrateState,openState,STATE_KEY,validateState} from '../state.mjs';
import {saveSpaceItem,linkSpaceNote,spaceRecords,spaceRoute,spaceHash} from '../project-space.mjs';
import {changeProjectStatus,restoreProject,updateProject} from '../projects.mjs';
const schema2=JSON.parse(readFileSync(new URL('./fixtures/schema-2.json',import.meta.url)));
const fresh=()=>migrateState(schema2,schema2);
const hub='project-accio-hub',cad='project-accio-cad';
test('schema 2 real: migração pura adiciona apenas referências; origem copiada exatamente e reabertura idempotente',()=>{
  const raw=JSON.stringify(schema2),entries=new Map([[STATE_KEY,raw]]),storage={getItem:k=>entries.get(k)??null,setItem:(k,v)=>entries.set(k,v)};
  const session=openState({storage,defaults:schema2});assert.equal(session.state.schemaVersion,4);assert.deepEqual(session.state.references,[]);
  for(const key of Object.keys(schema2).filter(k=>!['schemaVersion','notes'].includes(k)))assert.deepEqual(session.state[key],schema2[key],key);
  schema2.notes.forEach((n,i)=>{for(const k of Object.keys(n))assert.deepEqual(session.state.notes[i][k],n[k]);});
  assert.equal(entries.get(session.status.backupKey),raw);assert.equal(entries.size,2);assert.deepEqual(openState({storage,defaults:schema2}).state,session.state);assert.equal(entries.size,2);
});
test('falha no backup de schema 2 impede substituição; schema 2 inválido não é promovido',()=>{
  for(const value of [schema2,{...schema2,projects:schema2.projects.map(p=>({...p,status:'deleted'}))}]){const raw=JSON.stringify(value),storage={getItem:k=>k===STATE_KEY?raw:null,setItem:()=>{throw Error('quota');}};const session=openState({storage,defaults:schema2});assert.equal(session.save(session.state),false);assert.equal(storage.getItem(STATE_KEY),raw);}
});
test('campo references pré-existente é preservado se compatível; conteúdo desconhecido protege a origem',()=>{
  const reference={id:'preserved',projectId:hub,title:'Material existente',kind:'material',url:'',description:'Texto preservado',extra:'campo adicional'};
  assert.deepEqual(migrateState({...schema2,references:[reference]},schema2).references,[reference]);
  const raw=JSON.stringify({...schema2,references:{opaque:'não sobrescrever'}}),storage={getItem:k=>k===STATE_KEY?raw:null,setItem:()=>{throw Error('não deve gravar');}},session=openState({storage,defaults:schema2});
  assert.equal(session.status.code,'blocked');assert.equal(session.save(session.state),false);assert.equal(storage.getItem(STATE_KEY),raw);
});
test('rotas usam IDs codificados e aceitam somente abas conhecidas; malformadas não quebram app',()=>{
  assert.deepEqual(spaceRoute(spaceHash('ID / especial','tasks')),{id:'ID / especial',tab:'tasks'});
  assert.equal(spaceRoute('#/projects'),null);assert.deepEqual(spaceRoute('#/projects/%ZZ'),{id:null,tab:'overview'});assert.equal(spaceRoute('#/projects/a/__proto__').tab,'overview');
});
test('tarefas contextualizadas: edição preserva ID, vínculo e extras, sem alterar outras tarefas',()=>{
  const state=fresh(),task=saveSpaceItem(state,hub,'task',{title:'Planejar',priority:'Alta',done:false},{createId:()=> 't-qa'});task.extra='preservar';const others=structuredClone(state.tasks.filter(t=>t.id!==task.id));
  saveSpaceItem(state,hub,'task',{title:'Planejar revisão',priority:'Normal',done:true},{id:task.id});assert.equal(task.projectId,hub);assert.equal(task.extra,'preservar');assert.deepEqual(state.tasks.filter(t=>t.id!==task.id),others);assert.ok(!spaceRecords(state,cad).tasks.some(t=>t.id===task.id));
  assert.throws(()=>saveSpaceItem(state,cad,'task',{title:'Outra',priority:'Alta',done:false},{id:task.id}),/não pertence/);
});
test('notas compartilhadas mantêm único registro e Markdown exato; edição propaga e atualiza ambas atividades',()=>{
  const state=fresh(),body='# Nota\n\n**Teste** <script>texto</script>',note=saveSpaceItem(state,hub,'note',{title:'Compartilhada',body,projectIds:[hub,cad,cad]},{createId:()=> 'n-qa'});
  assert.deepEqual(note.projectIds,[hub,cad]);assert.equal(spaceRecords(state,cad).notes[0],note);const count=state.notes.length;
  saveSpaceItem(state,cad,'note',{title:'Revisada',body:body+'\nFim',projectIds:[hub]},{id:note.id});assert.equal(state.notes.length,count);assert.equal(spaceRecords(state,hub).notes[0].body,body+'\nFim');assert.equal(state.projects.find(p=>p.id===hub).updatedAt,state.projects.find(p=>p.id===cad).updatedAt);
  linkSpaceNote(state,cad,note.id);assert.equal(state.notes.length,count);assert.equal(note.projectIds.length,2);
});
test('vincular nota existente funciona sem cópia; recentidade considera edição global ou contextual',()=>{
  const state=fresh(),note=state.notes[0],count=state.notes.length;linkSpaceNote(state,cad,note.id);assert.equal(state.notes.length,count);assert.equal(spaceRecords(state,cad).notes[0],note);linkSpaceNote(state,cad,note.id);assert.equal(note.projectIds.filter(id=>id===cad).length,1);
});
test('referências/materiais têm IDs estáveis e persistem; URLs executáveis/credenciais e dados inválidos não mutam estado',()=>{
  const state=fresh(),r=saveSpaceItem(state,hub,'reference',{title:'Guia',kind:'link',url:'https://example.com/guia',description:'Consulta'},{createId:()=> 'r-qa'});
  saveSpaceItem(state,hub,'reference',{title:'Livro',kind:'material',url:'',description:'Capítulo 4, edição impressa'},{id:r.id});assert.equal(r.id,'r-qa');assert.deepEqual(migrateState(state,schema2),state);
  for(const url of ['javascript:alert(1)','data:text/html,test','file:///tmp/test','https://user:password@example.com']){const before=structuredClone(state);assert.throws(()=>saveSpaceItem(state,hub,'reference',{title:'Falha',kind:'link',url,description:''}));assert.deepEqual(state,before);const corrupt=structuredClone(state);corrupt.references[0].url=url;assert.throws(()=>validateState(corrupt,schema2));}
});
test('renomear/arquivar/restaurar preserva todas coleções e rejeita escrita no espaço arquivado',()=>{
  const state=fresh();saveSpaceItem(state,hub,'reference',{title:'Guia',kind:'link',url:'https://example.com',description:''});const content=structuredClone({tasks:state.tasks,notes:state.notes,references:state.references});const p=state.projects.find(p=>p.id===hub);updateProject(state,hub,{name:'Hub renovado',description:p.description,icon:p.icon,color:p.color});changeProjectStatus(state,hub,'archived');
  assert.throws(()=>saveSpaceItem(state,hub,'task',{title:'Falha',priority:'Normal',done:false}),/Restaure/);assert.throws(()=>linkSpaceNote(state,hub,state.notes[0].id),/Restaure/);restoreProject(state,hub);assert.deepEqual({tasks:state.tasks,notes:state.notes,references:state.references},content);
});
test('projeto inexistente, vínculos inválidos, prioridade e título inválidos não causam mutação parcial',()=>{
  const state=fresh();for(const [id,kind,input] of [['missing','task',{title:'x'}],[hub,'task',{title:'x',priority:'unknown',done:false}],[hub,'note',{title:'x',body:'abc',projectIds:['missing']}],[hub,'reference',{title:'',url:'https://example.com',kind:'link',description:''}]]){const before=structuredClone(state);assert.throws(()=>saveSpaceItem(state,id,kind,input));assert.deepEqual(state,before);}
});
