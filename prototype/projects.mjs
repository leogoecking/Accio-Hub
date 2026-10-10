// Regras locais da biblioteca; nenhuma operação exclui tarefas ou notas.
export const PROJECT_STATUS = {active:'Ativo', paused:'Pausado', archived:'Arquivado'};
export const PROJECT_COLORS = {mint:'#8befcc', purple:'#c3b3ff', pink:'#ffbfce', blue:'#9fd4ff', orange:'#ffd8ad', gold:'#fcedb3'};
export const PROJECT_ICONS = {grid:'Blocos', code:'Código', book:'Livro', target:'Foco', rss:'Feed', calendar:'Calendário', cloud:'Nuvem', music:'Música', check:'Tarefas', mail:'Carta'};
export const libraryDefaults = () => ({status:'all', sort:'name', favoritesOnly:false});
const equalId = (a,b) => a != null && b != null && String(a) === String(b);
const normalizeName = name => name.normalize('NFKC').trim().replace(/\s+/g,' ').toLocaleLowerCase('pt-BR');
const searchText = value => value.normalize('NFD').replace(/\p{Diacritic}/gu,'').toLocaleLowerCase('pt-BR');
const dateValid = value => value === null || (typeof value === 'string' && Number.isFinite(Date.parse(value)));

export function prepareProject(project) {
  return {status:'active', favorite:false, color:null, createdAt:null, updatedAt:null, archivedFrom:null, ...project};
}
export function validateProject(project) {
  if (!Object.hasOwn(PROJECT_STATUS,project.status) || typeof project.favorite !== 'boolean' ||
      (project.color !== null && (typeof project.color!=='string'||!/^#[0-9a-f]{6}$/i.test(project.color))) ||
      !dateValid(project.createdAt) || !dateValid(project.updatedAt) ||
      ![null,'active','paused'].includes(project.archivedFrom)) throw new Error('Propriedades do projeto inválidas');
}
export function validateLibrary(preferences) {
  if (!preferences || !['all',...Object.keys(PROJECT_STATUS)].includes(preferences.status) ||
      !['name','recent'].includes(preferences.sort) || typeof preferences.favoritesOnly !== 'boolean')
    throw new Error('Preferências da biblioteca inválidas');
}
export const projectColor = project => project.color ?? PROJECT_COLORS[project.tint] ?? PROJECT_COLORS.mint;
export function projectInk(project) {
  const rgb=projectColor(project).slice(1).match(/../g).map(hex=>{const c=parseInt(hex,16)/255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4;});
  return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722>.179?'#101913':'#fff';
}
const findProject = (state,id) => {
  const project=state.projects.find(p=>equalId(p.id,id));
  if (!project) throw new Error('Projeto não encontrado.');
  return project;
};
function fields(state,input,id=null) {
  const name=String(input.name??'').trim().replace(/\s+/g,' '), description=String(input.description??'').trim();
  if (!name || name.length>80) throw new Error('Informe um nome de até 80 caracteres.');
  if (description.length>500) throw new Error('A descrição deve ter até 500 caracteres.');
  if (state.projects.some(p=>!equalId(p.id,id)&&normalizeName(p.name)===normalizeName(name)))
    throw new Error('Já existe um projeto com esse nome. Confira também os arquivados.');
  const existing=id===null?null:findProject(state,id);
  if (!Object.hasOwn(PROJECT_ICONS,input.icon) && input.icon!==existing?.icon) throw new Error('Escolha um ícone válido.');
  if (input.color!==null && (typeof input.color!=='string'||!/^#[0-9a-f]{6}$/i.test(input.color))) throw new Error('Escolha uma cor válida.');
  return {name,description,icon:input.icon,color:input.color};
}
export function createProject(state,input,{createId=()=>crypto.randomUUID(),now=Date.now()}={}) {
  const data=fields(state,input);
  let id;
  do {id=createId();} while (typeof id!=='string'||!id.trim()||[...state.projects,...state.tasks,...state.notes].some(p=>equalId(p.id,id)));
  const timestamp=new Date(now).toISOString();
  const project=prepareProject({id,tint:'mint',...data,createdAt:timestamp,updatedAt:timestamp});
  state.projects.push(project);
  return project;
}
export function updateProject(state,id,input,now=Date.now()) {
  const data=fields(state,input,id), project=findProject(state,id);
  if (Object.keys(data).some(key=>data[key]!==project[key])) Object.assign(project,data,{updatedAt:new Date(now).toISOString()});
  return project;
}
export function favoriteProject(state,id) {
  const project=findProject(state,id);project.favorite=!project.favorite;return project;
}
export function changeProjectStatus(state,id,status,now=Date.now()) {
  const project=findProject(state,id);
  if (!Object.hasOwn(PROJECT_STATUS,status)) throw new Error('Status inválido.');
  if (project.status===status) return project;
  if (status==='archived') project.archivedFrom=project.status;
  else project.archivedFrom=null;
  project.status=status;project.updatedAt=new Date(now).toISOString();return project;
}
export function restoreProject(state,id,now=Date.now()) {
  const project=findProject(state,id);
  if (project.status!=='archived') return project;
  return changeProjectStatus(state,id,project.archivedFrom??'active',now);
}
export function touchProjects(state,ids,now=Date.now()) {
  for (const project of state.projects) if (ids.some(id=>equalId(project.id,id))) project.updatedAt=new Date(now).toISOString();
}
export function projectCounts(state,id) {
  const tasks=state.tasks.filter(t=>equalId(t.projectId,id));
  return {open:tasks.filter(t=>!t.done).length, total:tasks.length,
    notes:state.notes.filter(n=>n.projectIds.some(ref=>equalId(ref,id))).length};
}
export function selectProjects(state,query='',preferences=state.projectLibrary) {
  const term=searchText(query.trim());
  return state.projects.filter(p=>(preferences.status==='all'||p.status===preferences.status)&&
    (!preferences.favoritesOnly||p.favorite)&&searchText(p.name+' '+p.description).includes(term))
    .sort((a,b)=> (preferences.sort==='recent' ? (Date.parse(b.updatedAt)||0)-(Date.parse(a.updatedAt)||0) : 0) ||
      a.name.localeCompare(b.name,'pt-BR',{sensitivity:'base',numeric:true}) || String(a.id).localeCompare(String(b.id)));
}
