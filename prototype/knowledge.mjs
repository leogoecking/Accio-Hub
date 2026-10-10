// Modelo local: IDs independentes de nomes/caminhos; corpo Markdown é a fonte textual.
import {touchProjects} from './projects.mjs';
const same=(a,b)=>a!=null&&b!=null&&String(a)===String(b);
const key=s=>s.normalize('NFD').replace(/\p{Diacritic}/gu,'').toLocaleLowerCase('pt-BR');
export const COLLECTIONS={recent:'Recentes',favorites:'Favoritos',capture:'Capturas',journal:'Diário'};
export const prepareNote=n=>({folderId:null,tags:[],favorite:false,collection:'notes',noteLinks:[],...n});
export function folderDescendants(state,id){const found=new Set([String(id)]);let added=true;while(added){added=false;for(const f of state.noteFolders)if(found.has(String(f.parentId))&&!found.has(String(f.id))){found.add(String(f.id));added=true;}}return found;}
export function folderPath(state,id){const names=[],seen=new Set();while(id!=null){if(seen.has(String(id)))throw new Error('Ciclo de pastas.');seen.add(String(id));const f=state.noteFolders.find(f=>same(f.id,id));if(!f)break;names.unshift(f.name);id=f.parentId;}return names.join(' / ')||'Sem pasta';}
export function validateKnowledge(state){
  const valid=id=>typeof id==='string'&&id.trim()!==''||typeof id==='number'&&Number.isFinite(id);
  if(!Array.isArray(state.noteFolders)||state.noteFolders.some(f=>!f||!valid(f.id)||typeof f.name!=='string'||!f.name.trim()||f.parentId!==null&&!state.noteFolders.some(p=>same(p.id,f.parentId)))||new Set(state.noteFolders.map(f=>String(f.id))).size!==state.noteFolders.length)throw new Error('Pastas inválidas.');
  for(const f of state.noteFolders)folderPath(state,f.id);
  for(const n of state.notes){if(n.folderId!==null&&!state.noteFolders.some(f=>same(f.id,n.folderId))||!Array.isArray(n.tags)||n.tags.some(t=>typeof t!=='string')||typeof n.favorite!=='boolean'||!['notes','capture','journal'].includes(n.collection)||!Array.isArray(n.noteLinks)||n.noteLinks.some(l=>!l||typeof l.label!=='string'||!state.notes.some(t=>same(t.id,l.targetId))))throw new Error('Propriedades de nota inválidas.');}
}
export function resolveNoteLinks(state,note){
  const links=[];for(const match of note.body.matchAll(/\[\[([^\]\n]+)\]\]/g)){const label=match[1].trim();if(links.some(l=>l.label===label))continue;const previous=note.noteLinks?.find(l=>l.label===label&&state.notes.some(n=>same(n.id,l.targetId)));const matches=state.notes.filter(n=>key(n.title.trim())===key(label));const targetId=previous?.targetId??(matches.length===1?matches[0].id:null);if(targetId!==null)links.push({label,targetId});}return links;
}
export function prepareKnowledge(state){if(!Object.hasOwn(state,'noteFolders'))state.noteFolders=[];const missing=new Set(state.notes.filter(n=>!Object.hasOwn(n,'noteLinks')).map(n=>String(n.id)));state.notes=state.notes.map(prepareNote);validateKnowledge(state);for(const n of state.notes)if(missing.has(String(n.id)))n.noteLinks=resolveNoteLinks(state,n);return state;}
export function knowledgeNotes(state,{collection='recent',folderId=null,projectId='',query=''}={}){
  const descendants=folderId===null?null:folderDescendants(state,folderId),q=key(query.trim());
  return state.notes.filter(n=>(collection!=='favorites'||n.favorite)&&(!['capture','journal'].includes(collection)||n.collection===collection)&&(!descendants||n.folderId!==null&&descendants.has(String(n.folderId)))&&(!projectId||n.projectIds.some(id=>same(id,projectId)))&&(!q||key([n.title,n.body,...n.tags].join('\n')).includes(q))).slice().sort((a,b)=>(Date.parse(b.updatedAt||b.createdAt)||0)-(Date.parse(a.updatedAt||a.createdAt)||0));
}
function uniqueId(state,createId){let id;do{id=createId();}while([...state.notes,...state.projects,...state.tasks,...state.references,...state.noteFolders].some(r=>same(r.id,id)));return id;}
export function saveNote(state,input,{id=null,createId=()=>crypto.randomUUID(),now=Date.now()}={}){
  const current=id===null?null:state.notes.find(n=>same(n.id,id));if(id!==null&&!current)throw new Error('Nota não encontrada.');
  const renaming=!current||Object.hasOwn(input,'title'),title=renaming?String(input.title??'').trim():current.title;if(renaming&&(!title||title.length>120))throw new Error('Informe um título de até 120 caracteres.');
  const values={...prepareNote(current??{}),...input,title},oldIds=current?.projectIds??[];
  if(typeof values.body!=='string'||!Array.isArray(values.projectIds))throw new Error('Nota inválida.');
  values.projectIds=values.projectIds.map(id=>{const p=state.projects.find(p=>same(p.id,id));if(!p||p.status==='archived'&&!oldIds.some(old=>same(old,p.id)))throw new Error('Vínculo de projeto inválido ou arquivado.');return p.id;});values.projectIds=[...new Map(values.projectIds.map(id=>[String(id),id])).values()];
  // Validar em cópia antes de tocar no registro compartilhado.
  const record={...values,id:current?.id??uniqueId(state,createId),createdAt:current?current.createdAt??null:new Date(now).toISOString(),updatedAt:new Date(now).toISOString()};
  const candidate={...state,notes:current?state.notes.map(n=>n===current?record:n):[record,...state.notes]};record.noteLinks=resolveNoteLinks(candidate,record);validateKnowledge(candidate);
  if(current)Object.assign(current,record);else state.notes.unshift(record);for(const n of state.notes)n.noteLinks=resolveNoteLinks(state,n);touchProjects(state,[...oldIds,...record.projectIds],now);return current??record;
}
export function saveFolder(state,{name,parentId=null},{id=null,createId=()=>crypto.randomUUID()}={}){
  name=String(name??'').trim();if(!name||name.length>80)throw new Error('Informe um nome de até 80 caracteres.');
  const current=id===null?null:state.noteFolders.find(f=>same(f.id,id));if(id!==null&&!current)throw new Error('Pasta não encontrada.');
  if(parentId!==null&&!state.noteFolders.some(f=>same(f.id,parentId)))throw new Error('Pasta superior inválida.');
  if(current&&folderDescendants(state,id).has(String(parentId)))throw new Error('Uma pasta não pode conter a si mesma.');
  if(state.noteFolders.some(f=>!same(f.id,id)&&same(f.parentId??'root',parentId??'root')&&key(f.name)===key(name)))throw new Error('Já existe uma pasta com esse nome neste nível.');
  const folder={...current,id:current?.id??uniqueId(state,createId),name,parentId};if(current)Object.assign(current,folder);else state.noteFolders.push(folder);return current??folder;
}
