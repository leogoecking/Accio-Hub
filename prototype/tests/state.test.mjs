import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {migrateState, openState, STATE_KEY, LEGACY_KEY, SCHEMA_VERSION, sameId, snapshot} from '../state.mjs';

// Exercitar os mesmos dados iniciais passados pelo app, sem inicializar sua UI.
const preamble = readFileSync(new URL('../app.js', import.meta.url), 'utf8').split('function showStorageStatus')[0].replace(/^import .*;$/gm, '');
const defaults = JSON.parse(JSON.stringify(runInNewContext(`${preamble};defaults`)));
const fixture = JSON.parse(readFileSync(new URL('./fixtures/legacy-p03.json', import.meta.url), 'utf8'));
const clone = x => structuredClone(x);
function memory(initial = {}) {
  const entries = new Map(Object.entries(initial));
  return {entries, writes:[], fail:null,
    getItem(key) {if (this.fail === 'read') throw new Error('SecurityError'); return entries.get(key) ?? null;},
    setItem(key, value) {
      if (this.fail === 'write' || this.fail === key || (this.fail === 'backup' && key.includes(':backup:'))) throw new Error('QuotaExceededError');
      this.writes.push({key, value}); entries.set(key, value);
    }};
}
const load = storage => openState({storage, defaults});
const rawFixture = JSON.stringify(fixture);

test('sem dados: grava schema 2 com exemplos apenas na primeira inicialização e IDs persistentes', () => {
  const storage = memory(), first = load(storage);
  assert.equal(first.status.code, 'ok');
  assert.equal(first.state.schemaVersion, SCHEMA_VERSION);
  assert.equal(first.state.projects.length, 4);
  assert.equal(first.state.tasks.length, 4);
  assert.equal(first.state.notes.length, 2);
  const raw = storage.getItem(STATE_KEY);
  assert.deepEqual(load(storage).state, JSON.parse(raw));
  assert.equal(storage.writes.length, 1);
  assert.ok(first.state.tasks.every(t => first.state.projects.some(p => sameId(p.id, t.projectId))));
});

test('P0.3: preserva conteúdo, IDs, preferências, campos extras e backup byte a byte', () => {
  const storage = memory({[STATE_KEY]:rawFixture}), session = load(storage), state = session.state;
  assert.equal(session.status.code, 'ok');
  assert.equal(storage.getItem(session.status.backupKey), rawFixture);
  assert.ok(storage.writes[0].key.includes(':backup:'));
  assert.equal(storage.writes[1].key, STATE_KEY);
  assert.deepEqual(state.tasks.map(t => t.id), fixture.tasks.map(t => t.id));
  assert.deepEqual(state.notes.map(n => [n.id,n.title,n.body]), fixture.notes.map(n => [n.id,n.title,n.body]));
  for (const field of ['theme','wallpaper','accent','density','music','musicExpanded','widgets','dockOrder','dockHidden','focusMin','focusLeft','focusRuns','extension']) assert.deepEqual(state[field], fixture[field], field);
  assert.deepEqual(state.tasks[0].attachment, fixture.tasks[0].attachment);
  for (const t of state.tasks) assert.equal(state.projects.find(p => sameId(p.id,t.projectId)).name, fixture.tasks.find(old => sameId(old.id,t.id)).project);
  for (const n of state.notes) assert.equal(state.projects.find(p => sameId(p.id,n.projectIds[0])).name, fixture.notes.find(old => sameId(old.id,n.id)).project);
  assert.equal('project' in state.tasks[0], false);
  assert.equal('project' in state.notes[0], false);
});

test('migração pura e repetida: nenhum ID/registo/backup adicional', () => {
  const input = clone(fixture), migrated = migrateState(input, defaults);
  assert.deepEqual(input, fixture);
  assert.deepEqual(migrateState(migrated, defaults), migrated);
  const storage = memory({[STATE_KEY]:rawFixture});
  load(storage);
  const writes = storage.writes.length, raw = storage.getItem(STATE_KEY);
  for (let i=0;i<3;i++) load(storage);
  assert.equal(storage.writes.length, writes);
  assert.equal(storage.getItem(STATE_KEY), raw);
});

test('renomear/reordenar projetos preserva tarefa, nota e seleção vinculadas pelo ID', () => {
  const storage = memory({[STATE_KEY]:rawFixture}), session = load(storage);
  const project = session.state.projects.find(p => p.name === 'Accio Hub'), id = project.id;
  project.name = 'Hub renomeado'; session.state.projects.reverse();
  assert.equal(session.save(session.state), true);
  const after = load(storage).state;
  assert.equal(after.projects.find(p => sameId(p.id,id)).name, 'Hub renomeado');
  assert.ok(after.tasks.some(t => sameId(t.projectId,id)));
  assert.ok(after.notes.some(n => n.projectIds.some(ref => sameId(ref,id))));
  assert.equal(after.projects.length, 4);
});

test('legado incompleto: IDs ausentes/duplicados corrigidos, coleções ausentes vazias, sem novos exemplos', () => {
  const storage = memory({[STATE_KEY]:JSON.stringify({tasks:[{title:'Sem ID',project:'Projeto próprio'},{id:7,title:'A'},{id:7,title:'B'}], notes:[{title:'Sem corpo'}], widgets:[], dockOrder:[]})});
  const first = load(storage);
  assert.equal(first.status.code, 'ok');
  assert.equal(first.state.tasks.length,3);
  assert.equal(first.state.notes.length,1);
  assert.equal(first.state.notes[0].body,'');
  assert.equal(new Set(first.state.tasks.map(t=>String(t.id))).size,3);
  assert.equal(first.state.tasks[1].id,7);
  assert.equal(first.state.projects.filter(p=>p.name==='Projeto próprio').length,1);
  assert.deepEqual(first.state.widgets,[]);
  assert.deepEqual(first.state.dockOrder,[]);
  assert.deepEqual(load(storage).state,JSON.parse(storage.getItem(STATE_KEY)));
  const absent = load(memory({[STATE_KEY]:'{"theme":"light"}'})).state;
  assert.deepEqual(absent.tasks,[]);assert.deepEqual(absent.notes,[]);
});

test('geração de IDs reserva IDs de registros posteriores e distingue IDs DOM por valor', () => {
  const ids=['later','safe1','safe2'];
  const state=migrateState({tasks:[{title:'novo'},{id:'later',title:'antigo'},{id:'later',title:'duplicado'}]},defaults,()=>ids.shift());
  assert.deepEqual(state.tasks.map(t=>t.id),['safe1','later','safe2']);
  assert.ok(sameId(1,'1'));assert.equal(sameId(null,'null'),false);
});

test('notas aceitam múltiplos vínculos; IDs órfãos são recuperados sem mudar o ID', () => {
  const migrated=migrateState({tasks:[{id:'t',projectId:'orphan'}],notes:[{id:'n',projectIds:['orphan','orphan']}],projects:[]},defaults);
  assert.equal(migrated.projects[0].id,'orphan');
  assert.deepEqual(migrated.notes[0].projectIds,['orphan']);
  assert.deepEqual(migrateState(migrated,defaults),migrated);
});

test('Pessoal é ausência de vínculo, salvo quando existe um projeto explícito com esse nome', () => {
  const plain=migrateState({tasks:[{id:1,project:'Pessoal'}],notes:[{id:1,project:'Pessoal'}]},defaults);
  assert.equal(plain.tasks[0].projectId,null);assert.deepEqual(plain.notes[0].projectIds,[]);
  const explicit=migrateState({projects:[{id:'personal',name:'Pessoal'}],tasks:[{id:1,project:'Pessoal'}]},defaults);
  assert.equal(explicit.tasks[0].projectId,'personal');
});

test('chave mais antiga preservada; fallback somente para coleções ausentes da P0.3', () => {
  const storage=memory({[LEGACY_KEY]:rawFixture});const session=load(storage);
  assert.equal(storage.getItem(LEGACY_KEY),rawFixture);
  assert.equal(storage.getItem(session.status.backupKey),rawFixture);
  assert.equal(session.state.tasks.length,fixture.tasks.length);
  const mixed=load(memory({[STATE_KEY]:'{"theme":"light","tasks":[]}',[LEGACY_KEY]:rawFixture}));
  assert.deepEqual(mixed.state.tasks,[]);assert.equal(mixed.state.notes.length,2);
});

for (const raw of ['{inválido', 'null', '[]', '{"schemaVersion":99,"tasks":[]}', '{"schemaVersion":0}', '{"schemaVersion":"1"}', '{"unknown":"opaque"}', '{"tasks":"texto"}', '{"notes":[{"body":123}]}']) {
  test(`dados inválidos/desconhecidos protegidos: ${raw}`, () => {
    const storage=memory({[STATE_KEY]:raw,[LEGACY_KEY]:rawFixture}),session=load(storage);
    assert.equal(session.status.code,'blocked');
    assert.deepEqual(session.state.tasks,[]);assert.deepEqual(session.state.projects,[]);
    session.state.theme='light';assert.equal(session.save(session.state),false);
    assert.equal(storage.getItem(STATE_KEY),raw);assert.equal(storage.writes.length,0);
    assert.match(session.status.message,/não serão persistidas/);
  });
}

test('schema atual estruturalmente inválido também é preservado', () => {
  const current=migrateState(fixture,defaults);delete current.notes;
  const raw=JSON.stringify(current),storage=memory({[STATE_KEY]:raw});
  assert.equal(load(storage).status.code,'blocked');
  assert.equal(storage.getItem(STATE_KEY),raw);assert.equal(storage.writes.length,0);
});

test('erro de acesso ao localStorage (getter/leitura) bloqueia qualquer gravação', () => {
  const storage=memory({[STATE_KEY]:rawFixture});storage.fail='read';
  assert.equal(load(storage).status.code,'blocked');assert.equal(storage.writes.length,0);
  const session=openState({storage:()=>{throw new Error('SecurityError');},defaults});
  assert.equal(session.status.code,'blocked');assert.equal(session.save(session.state),false);
});

test('falha ao criar backup impede sobrescrita da origem; repetição grava mesmos IDs', () => {
  const storage=memory({[STATE_KEY]:rawFixture});storage.fail='backup';
  const session=load(storage),ids=session.state.projects.map(p=>p.id);
  assert.equal(session.status.code,'write-failed');assert.equal(storage.getItem(STATE_KEY),rawFixture);
  assert.equal(storage.writes.length,0);
  storage.fail=null;assert.equal(session.save(session.state),true);
  assert.deepEqual(load(storage).state.projects.map(p=>p.id),ids);
});

test('falha após backup preserva ambos os JSONs; gravação pode ser repetida sem duplicar backup', () => {
  const storage=memory({[STATE_KEY]:rawFixture});storage.fail=STATE_KEY;
  const session=load(storage),backup=session.status.backupKey;
  assert.equal(session.status.code,'write-failed');assert.match(session.status.message,/não foram persistidas/);
  assert.equal(storage.getItem(STATE_KEY),rawFixture);assert.equal(storage.getItem(backup),rawFixture);
  storage.fail=null;assert.equal(session.save(session.state),true);
  assert.equal(storage.writes.filter(x=>x.key.includes(':backup:')).length,1);
});

test('backup anterior diferente nunca é sobrescrito', () => {
  const base=`${STATE_KEY}:backup:pre-schema-2`,storage=memory({[STATE_KEY]:rawFixture,[base]:'cópia anterior'});
  const session=load(storage);
  assert.notEqual(session.status.backupKey,base);assert.equal(storage.getItem(base),'cópia anterior');
  assert.equal(storage.getItem(session.status.backupKey),rawFixture);
});

test('falha de gravação normal mantém estado salvo e informa estado só em memória; recuperar permite salvar', () => {
  const storage=memory(),session=load(storage),raw=storage.getItem(STATE_KEY);
  storage.fail='write';session.state.notes[0].body='edição em memória';
  assert.equal(session.save(session.state),false);assert.equal(storage.getItem(STATE_KEY),raw);
  assert.equal(session.status.code,'write-failed');
  storage.fail=null;assert.equal(session.save(session.state),true);assert.equal(session.status.code,'ok');
  assert.equal(load(storage).state.notes[0].body,'edição em memória');
});

test('outra aba/versão futura bloqueia sessão antiga e preserva o valor novo', () => {
  const storage=memory(),session=load(storage),future='{"schemaVersion":99,"opaque":"do not touch"}';
  storage.entries.set(STATE_KEY,future);session.state.theme='light';
  assert.equal(session.save(session.state),false);assert.equal(session.status.code,'conflict');
  assert.equal(storage.getItem(STATE_KEY),future);
  assert.equal(session.save(session.state),false);
});

test('widgets desconhecidos e coleções vazias não são eliminados nem repovoados', () => {
  const state=load(memory({[STATE_KEY]:JSON.stringify({tasks:[],notes:[],projects:[],widgets:[{id:'futuro',span:6,visible:false,extra:42}],dockOrder:[],dockHidden:['futuro']})})).state;
  assert.deepEqual(state.tasks,[]);assert.deepEqual(state.notes,[]);assert.deepEqual(state.projects,[]);
  assert.equal(state.widgets[0].extra,42);assert.deepEqual(state.dockOrder,[]);
});

test('nomes ambíguos não ganham vínculos arbitrários', () => {
  const raw=JSON.stringify({projects:[{id:'a',name:'Igual'},{id:'b',name:'Igual'}],tasks:[{id:1,project:'Igual'}]}),storage=memory({[STATE_KEY]:raw});
  assert.equal(load(storage).status.code,'blocked');assert.equal(storage.getItem(STATE_KEY),raw);
});

test('estado transitório da UI não entra na persistência, sem afetar preferências', () => {
  const state=migrateState(fixture,defaults);state.modal='note';state.drawer=true;state.edit=true;state.query='busca';
  const persisted=snapshot(state);
  assert.equal(persisted.modal,null);assert.equal(persisted.drawer,false);assert.equal(persisted.edit,false);assert.equal(persisted.query,'');
  assert.equal(persisted.theme,fixture.theme);
});
