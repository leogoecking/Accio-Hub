// Persistência do protótipo. Nenhuma operação acessa arquivos ou serviços externos.
import {prepareProject, validateProject, libraryDefaults, validateLibrary} from './projects.mjs';
export const STATE_KEY = 'accio-hub-p0.3-studio';
export const LEGACY_KEY = 'accio-hub-p0-v1';
export const SCHEMA_VERSION = 3;
export const newId = () => crypto.randomUUID();
export const sameId = (a, b) => a != null && b != null && String(a) === String(b);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const validId = id => (typeof id === 'string' && id.trim() !== '') || (typeof id === 'number' && Number.isFinite(id));
const copy = value => JSON.parse(JSON.stringify(value));
const own = (value, key) => Object.hasOwn(value, key);
const transient = {edit:false, modal:null, drawer:false, search:false, query:''};
export const snapshot = state => ({...state, ...transient});

function recognizeLegacy(input, defaults) {
  const known = [...Object.keys(defaults), 'projects', 'dockOrder', 'dockHidden', 'project'];
  if (Object.keys(input).length && !known.some(key => own(input, key))) throw new Error('Formato desconhecido');
}

function records(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some(item => !object(item))) throw new Error(`Coleção inválida: ${field}`);
  return value;
}
function uniqueIds(items, createId) {
  // Reservar todos os IDs existentes evita que um ID novo colida com um registro posterior.
  const reserved = new Set(items.filter(x => validId(x.id)).map(x => String(x.id)));
  const used = new Set();
  return items.map(item => {
    let id = item.id;
    if (!validId(id) || used.has(String(id))) {
      do { id = createId(); } while (!validId(id) || reserved.has(String(id)) || used.has(String(id)));
      reserved.add(String(id));
    }
    used.add(String(id));
    return {...item, id};
  });
}

// Migração pura: versões anteriores são validadas antes de acrescentar campos.
export function migrateState(input, defaults, createId = newId) {
  if (!object(input)) throw new Error('Estado não é um objeto');
  if (own(input, 'schemaVersion')) {
    if (input.schemaVersion === 1 || input.schemaVersion === 2) {
      validateState(input, defaults, input.schemaVersion);
      const next=copy(input);
      next.schemaVersion=SCHEMA_VERSION;
      next.projects=next.projects.map(prepareProject);
      next.projectLibrary=next.projectLibrary??libraryDefaults();
      next.references=own(next,'references')?next.references:[];
      validateState(next,defaults);
      return next;
    }
    if (input.schemaVersion !== SCHEMA_VERSION) throw new Error('Versão de schema desconhecida');
    validateState(input, defaults);
    return copy(input);
  }
  recognizeLegacy(input, defaults);
  const result = {...copy(defaults), ...copy(input), schemaVersion:SCHEMA_VERSION};
  // Projetos eram definições fixas no código. Não recolocar exemplos nas coleções do usuário.
  const projects = uniqueIds(records(input.projects === undefined ? defaults.projects : input.projects, 'projects'), createId)
    .map(p => ({description:'', icon:'grid', tint:'mint', ...p, name:p.name ?? 'Projeto sem título'}));
  const byName = new Map(projects.map(p => [p.name, p.id]));
  function projectForName(name) {
    if (byName.has(name)) {
      if (projects.filter(p => p.name === name).length > 1) throw new Error('Nome de projeto ambíguo');
      return byName.get(name);
    }
    if (name === undefined || name === null || name === '' || name === 'Pessoal') return null;
    if (typeof name !== 'string') throw new Error('Nome de projeto inválido');
    if (!byName.has(name)) {
      const definition = defaults.projects.find(p => p.name === name);
      let id = definition?.id;
      if (!validId(id) || projects.some(p => sameId(p.id, id))) {
        do { id = createId(); } while (projects.some(p => sameId(p.id, id)));
      }
      projects.push({description:'', icon:'grid', tint:'mint', ...definition, id, name});
      byName.set(name, id);
    }
    return byName.get(name);
  }
  function projectForId(id) {
    if (id === null) return null;
    if (!validId(id)) throw new Error('Vínculo de projeto inválido');
    if (!projects.some(p => sameId(p.id, id))) projects.push({id, name:'Projeto recuperado', description:'', icon:'grid', tint:'mint'});
    return id;
  }
  result.tasks = uniqueIds(records(input.tasks, 'tasks'), createId).map(task => {
    const {project, ...rest} = task;
    return {title:'', done:false, priority:'Normal', ...rest,
      projectId:own(task, 'projectId') ? projectForId(task.projectId) : projectForName(project)};
  });
  result.notes = uniqueIds(records(input.notes, 'notes'), createId).map(note => {
    const {project, projectId, ...rest} = note;
    let ids;
    if (own(note, 'projectIds')) {
      if (!Array.isArray(note.projectIds)) throw new Error('Vínculos da nota inválidos');
      ids = note.projectIds.map(projectForId).filter(id => id !== null);
    } else {
      const id = own(note, 'projectId') ? projectForId(projectId) : projectForName(project);
      ids = id === null ? [] : [id];
    }
    // Os textos Markdown permanecem exatamente como recebidos.
    return {title:'', body:'', ...rest, projectIds:[...new Map(ids.map(id => [String(id), id])).values()]};
  });
  result.projectId = own(input, 'projectId') ? projectForId(input.projectId)
    : own(input, 'project') ? projectForName(input.project) : projects[0]?.id ?? null;
  delete result.project;
  result.projects = projects.map(prepareProject);
  result.projectLibrary = input.projectLibrary ?? libraryDefaults();
  result.references = own(input,'references')?input.references:[];
  result.widgets = records(input.widgets === undefined ? defaults.widgets : input.widgets, 'widgets').map(w => {
    const suggested = defaults.widgets.find(x => x.id === w.id);
    return {span:suggested?.span ?? 4, visible:true, ...w};
  });
  result.dockOrder = input.dockOrder === undefined ? copy(defaults.dockOrder) : input.dockOrder;
  result.dockHidden = input.dockHidden === undefined ? [] : input.dockHidden;
  result.noteId = result.notes.some(n => sameId(n.id, input.noteId)) ? input.noteId : result.notes[0]?.id ?? null;
  validateState(result, defaults);
  return result;
}

export function validateState(state, defaults, version = SCHEMA_VERSION) {
  if (!object(state) || state.schemaVersion !== version) throw new Error('Schema inválido');
  for (const field of ['projects', 'tasks', 'notes']) {
    const list = records(state[field], field);
    if (!Array.isArray(state[field]) || list.some(x => !validId(x.id)) || new Set(list.map(x => String(x.id))).size !== list.length)
      throw new Error(`IDs inválidos: ${field}`);
  }
  const exists = id => id === null || state.projects.some(p => sameId(p.id, id));
  if (state.projects.some(p => typeof p.name !== 'string' || typeof p.description !== 'string' || typeof p.icon !== 'string' || typeof p.tint !== 'string')) throw new Error('Projeto inválido');
  if (version>=2) {state.projects.forEach(validateProject);validateLibrary(state.projectLibrary);}
  if (version>=3) {
    if (!Array.isArray(state.references) || state.references.some(r=>!object(r)||!validId(r.id)) || new Set(state.references.map(r=>String(r.id))).size!==state.references.length) throw new Error('Referências inválidas');
    for (const r of state.references) {
      if (r.projectId===null || !exists(r.projectId) || typeof r.title!=='string' || !r.title.trim() || !['link','material'].includes(r.kind) || typeof r.description!=='string' || typeof r.url!=='string' || (r.kind==='link'&&!r.url)) throw new Error('Referência inválida');
      if (r.url) {let url;try{url=new URL(r.url);}catch{throw new Error('URL inválida');}if(!['http:','https:'].includes(url.protocol)||url.username||url.password)throw new Error('URL inválida');}
    }
  }
  if (state.tasks.some(t => typeof t.title !== 'string' || typeof t.done !== 'boolean' || !exists(t.projectId))) throw new Error('Tarefa inválida');
  if (state.notes.some(n => typeof n.title !== 'string' || typeof n.body !== 'string' || !Array.isArray(n.projectIds) || n.projectIds.some(id => id === null || !exists(id)))) throw new Error('Nota inválida');
  if (!exists(state.projectId)) throw new Error('Seleção de projeto inválida');
  if (!Array.isArray(state.widgets) || state.widgets.some(w => !object(w) || typeof w.id !== 'string' || !Number.isInteger(w.span) || w.span < 1 || w.span > 12 || typeof w.visible !== 'boolean')) throw new Error('Widgets inválidos');
  for (const field of ['dockOrder', 'dockHidden']) if (!Array.isArray(state[field]) || state[field].some(x => typeof x !== 'string')) throw new Error('Dock inválida');
  for (const field of ['theme', 'wallpaper', 'accent', 'density', 'page']) if (typeof state[field] !== typeof defaults[field]) throw new Error(`Preferência inválida: ${field}`);
  for (const field of ['music', 'musicExpanded', 'focusRunning']) if (typeof state[field] !== 'boolean') throw new Error(`Preferência inválida: ${field}`);
  for (const field of ['focusMin', 'focusLeft', 'focusRuns']) if (!Number.isFinite(state[field]) || state[field] < 0 || (field === 'focusMin' && state[field] === 0)) throw new Error('Temporizador inválido');
  if (state.focusEnd !== null && !Number.isFinite(state.focusEnd)) throw new Error('Prazo de foco inválido');
}

// Uma sessão bloqueada nunca grava. Falhas de escrita permitem tentar novamente,
// desde que outro contexto não tenha alterado o valor lido inicialmente.
export function openState({storage, defaults, createId = newId, onStatus = () => {}}) {
  let target, expectedRaw, sourceRaw, sourceKey, needsBackup = false, backupKey = null, blocked = false;
  let status = {code:'ok', message:''};
  const report = (code, message) => {status = {code, message, backupKey}; onStatus(status);};
  let state;
  try {
    target = typeof storage === 'function' ? storage() : storage;
    expectedRaw = target.getItem(STATE_KEY);
    sourceKey = expectedRaw === null ? LEGACY_KEY : STATE_KEY;
    sourceRaw = expectedRaw === null ? target.getItem(LEGACY_KEY) : expectedRaw;
    if (sourceRaw === null) {
      state = migrateState(defaults, defaults, createId);
    } else {
      const parsed = JSON.parse(sourceRaw);
      if (object(parsed) && !own(parsed, 'schemaVersion')) recognizeLegacy(parsed, defaults);
      // Compatibilidade com o fallback real da P0.3: apenas coleções ausentes.
      if (sourceKey === STATE_KEY && object(parsed) && !own(parsed, 'schemaVersion') &&
          (!own(parsed, 'tasks') || !own(parsed, 'notes'))) {
        const olderRaw = target.getItem(LEGACY_KEY);
        if (olderRaw !== null) {
          const older = JSON.parse(olderRaw);
          if (!object(older) || own(older, 'schemaVersion')) throw new Error('Fallback legado desconhecido');
          for (const field of ['tasks', 'notes']) if (!own(parsed, field) && own(older, field)) parsed[field] = older[field];
        }
      }
      state = migrateState(parsed, defaults, createId);
      needsBackup = sourceKey !== STATE_KEY || parsed.schemaVersion !== SCHEMA_VERSION;
    }
  } catch (error) {
    blocked = true;
    state = migrateState({...defaults, tasks:[], notes:[], projects:[], projectId:null}, defaults, createId);
    report('blocked', 'Armazenamento protegido: não foi possível ler um estado compatível. Os dados existentes não foram alterados. Alterações nesta sessão não serão persistidas.');
  }
  function save(value) {
    if (blocked) return false;
    try {
      validateState(value, defaults);
      if (target.getItem(STATE_KEY) !== expectedRaw ||
          (sourceKey === LEGACY_KEY && sourceRaw !== null && target.getItem(LEGACY_KEY) !== sourceRaw)) {
        blocked = true;
        report('conflict', 'O armazenamento mudou em outra aba. Os dados salvos não foram sobrescritos. Alterações nesta sessão não foram persistidas; recarregue para ler a versão atual.');
        return false;
      }
      const raw = JSON.stringify(snapshot(value));
      if (needsBackup) {
        const base = `${STATE_KEY}:backup:pre-schema-${SCHEMA_VERSION}`;
        backupKey ??= base;
        while (target.getItem(backupKey) !== null && target.getItem(backupKey) !== sourceRaw)
          backupKey = `${base}:${createId()}`;
        if (target.getItem(backupKey) === null) target.setItem(backupKey, sourceRaw);
        if (target.getItem(backupKey) !== sourceRaw) throw new Error('Backup não confirmado');
      }
      if (raw !== expectedRaw) target.setItem(STATE_KEY, raw);
      expectedRaw = raw;
      needsBackup = false;
      report('ok', '');
      return true;
    } catch (error) {
      report('write-failed', 'Alterações não foram persistidas neste navegador. Elas permanecem apenas nesta sessão; verifique o armazenamento antes de fechar ou recarregar. O último estado salvo foi preservado.');
      return false;
    }
  }
  if (!blocked) save(state);
  return {state, save, get status() {return status;}};
}
