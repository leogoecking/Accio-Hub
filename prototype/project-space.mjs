import {sameId, newId} from './state.mjs';
import {touchProjects} from './projects.mjs';

export const SPACE_TABS={overview:'Visão Geral',tasks:'Tarefas',knowledge:'Conhecimento',references:'Referências'};
// Contrato de composição local, independente do board; editor de widgets futuro.
export const SPACE_WIDGETS=[{id:'tasks',span:5},{id:'focus',span:3},{id:'info',span:4},{id:'notes',span:12}];
export function spaceRoute(hash) {
  const parts=hash.replace(/^#\//,'').split('/');
  if(parts[0]!=='projects'||!parts[1])return null;
  let id;try{id=decodeURIComponent(parts[1]);}catch{return {id:null,tab:'overview'};}
  return {id,tab:Object.hasOwn(SPACE_TABS,parts[2])?parts[2]:'overview'};
}
export const spaceHash=(id,tab='overview')=>`#/projects/${encodeURIComponent(id)}/${tab}`;
export function spaceRecords(state,id) {
  return {project:state.projects.find(p=>sameId(p.id,id)),tasks:state.tasks.filter(t=>sameId(t.projectId,id)),
    notes:state.notes.filter(n=>n.projectIds.some(p=>sameId(p,id))).slice().sort((a,b)=>(Date.parse(b.updatedAt||b.createdAt)||0)-(Date.parse(a.updatedAt||a.createdAt)||0)),
    references:state.references.filter(r=>sameId(r.projectId,id))};
}
function editable(state,id) {
  const p=state.projects.find(p=>sameId(p.id,id));
  if(!p)throw new Error('Projeto não encontrado.');
  if(p.status==='archived')throw new Error('Restaure o projeto na Biblioteca para editar este espaço.');
  return p.id;
}
function title(input) {
  const value=String(input.title??'').trim();if(!value||value.length>120)throw new Error('Informe um título de até 120 caracteres.');return value;
}
function idFor(state,createId) {
  let id;do{id=createId();}while([...state.projects,...state.tasks,...state.notes,...state.references].some(r=>sameId(r.id,id)));return id;
}
export function saveSpaceItem(state,projectId,kind,input,{id=null,createId=newId,now=Date.now()}={}) {
  projectId=editable(state,projectId);
  const collection=({task:state.tasks,note:state.notes,reference:state.references})[kind];
  if(!collection)throw new Error('Tipo inválido.');
  const current=id===null?null:collection.find(r=>sameId(r.id,id));
  if(id!==null&&(!current||(kind==='note'?!current.projectIds.some(p=>sameId(p,projectId)):!sameId(current.projectId,projectId))))throw new Error('Registro não pertence a este projeto.');
  let fields={title:title(input)};
  if(kind==='task') {
    if(!['Normal','Alta'].includes(input.priority)||typeof input.done!=='boolean')throw new Error('Tarefa inválida.');
    fields={...fields,projectId,priority:input.priority,done:input.done};
  } else if(kind==='note') {
    if(typeof input.body!=='string'||!Array.isArray(input.projectIds))throw new Error('Nota inválida.');
    const ids=[...input.projectIds,projectId].map(p=>state.projects.find(r=>sameId(r.id,p)));
    if(ids.some(p=>!p))throw new Error('Vínculo de projeto inválido.');
    const oldIds=current?.projectIds??[];
    if(ids.some(p=>p.status==='archived'&&!oldIds.some(id=>sameId(id,p.id))))throw new Error('Não é possível criar vínculo com projeto arquivado.');
    fields={...fields,body:input.body,projectIds:[...new Map(ids.map(p=>[String(p.id),p.id])).values()]};
  } else {
    const url=String(input.url??'').trim(),description=String(input.description??'').trim();
    if(!['link','material'].includes(input.kind)||description.length>2000)throw new Error('Referência inválida.');
    if(input.kind==='link'&&!url)throw new Error('Informe a URL do link.');
    if(url){let parsed;try{parsed=new URL(url);}catch{throw new Error('Informe uma URL completa (http ou https).');}if(!['http:','https:'].includes(parsed.protocol)||parsed.username||parsed.password)throw new Error('Use uma URL http ou https sem credenciais.');}
    fields={...fields,projectId,kind:input.kind,url,description};
  }
  const stamp=new Date(now).toISOString(),oldIds=current?.projectIds??[];
  const record=current??{id:idFor(state,createId),createdAt:stamp};
  Object.assign(record,fields,{updatedAt:stamp});if(!current)collection.unshift(record);
  touchProjects(state,[projectId,...oldIds,...(record.projectIds??[])],now);
  return record;
}
export function linkSpaceNote(state,projectId,noteId,now=Date.now()) {
  projectId=editable(state,projectId);const note=state.notes.find(n=>sameId(n.id,noteId));
  if(!note)throw new Error('Nota não encontrada.');
  if(!note.projectIds.some(id=>sameId(id,projectId))){note.projectIds.push(projectId);note.updatedAt=new Date(now).toISOString();touchProjects(state,note.projectIds,now);}
  return note;
}
