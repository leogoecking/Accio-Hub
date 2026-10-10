import {sameId} from './state.mjs';
import {PROJECT_STATUS,projectColor,projectInk} from './projects.mjs';
import {SPACE_TABS,SPACE_WIDGETS,spaceHash,spaceRecords,saveSpaceItem,linkSpaceNote} from './project-space.mjs';

export function createProjectSpace({state,esc,icon,persist,render,route,navigate,focusContent}) {
  let editing=null,pending=null,returnControl=null,feedback='';
  const records=()=>spaceRecords(state,route()?.id);
  const action=(name,label,id='')=>`<button type="button" class="button tertiary" data-space-action="${name}" data-space-id="${esc(id)}">${label}</button>`;
  const tabLink=(tab,label)=>`<a class="quiet-link" href="${spaceHash(route().id,tab)}">${label} ${icon('chevron',14)}</a>`;
  const empty=text=>`<p class="space-empty">${text}</p>`;
  const names=n=>n.projectIds.map(id=>state.projects.find(p=>sameId(p.id,id))?.name).filter(Boolean).join(' · ');
  function tasks(list,readonly=false) {
    return list.map(t=>`<div class="task-item ${t.done?'is-done':''}" data-space-task="${esc(t.id)}"><label class="task-label"><input type="checkbox" ${readonly?'disabled':`data-task="${esc(t.id)}"`} ${t.done?'checked':''}><span class="task-name">${esc(t.title)}<small>${esc(t.priority)} prioridade</small></span></label>${readonly?'':action('edit-task','Editar',t.id)}</div>`).join('')||empty('Nenhuma tarefa por aqui. Crie sua primeira atividade.');
  }
  function notes(list,readonly=false,summary=false) {
    return list.map(n=>`<article class="space-note" data-space-note="${esc(n.id)}"><div class="block-top"><h3>${esc(n.title)}</h3>${summary?tabLink('knowledge','Abrir'):readonly?'':action('edit-note','Editar nota',n.id)}</div><p class="muted">${esc(names(n))} ${n.projectIds.length>1?'· Nota compartilhada':''}</p>${summary?'':`<a class="quiet-link" href="#/knowledge/${encodeURIComponent(n.id)}">Abrir no Accio Knowledge ${icon('chevron',14)}</a><details><summary>Conteúdo Markdown</summary><pre>${esc(n.body||'Nota ainda sem conteúdo.')}</pre></details>`}</article>`).join('')||empty('Nenhuma nota vinculada. Capture uma ideia ou vincule uma nota existente.');
  }
  function panel(def,body,extra='') {
    const titles={tasks:['Tarefas pendentes','check','mint'],focus:['Pomodoro global','target','purple'],info:['Seu projeto','grid','blue'],notes:['Notas recentes','book','pink']},[label,ic,tint]=titles[def.id];
    return `<section class="panel panel-${def.id} span-${def.span}" data-space-widget="${def.id}" aria-label="${label}"><div class="panel-top"><div class="panel-heading"><span class="widget-icon tint-${tint}">${icon(ic,18)}</span><h2>${label}</h2></div>${extra}</div>${body}</section>`;
  }
  function view() {
    const {project,tasks:list,notes:ns,references:refs}=records(),r=route();
    if(!project)return `<div class="inner-page project-space"><a class="quiet-link" href="#/projects">← Biblioteca de Projetos</a><div class="inner-block unavailable"><h1 id="space-title" tabindex="-1">Projeto não encontrado</h1><p>Este endereço não corresponde a um projeto cadastrado neste navegador.</p><a class="button tertiary" href="#/projects">Voltar à Biblioteca</a></div></div>`;
    const readonly=project.status==='archived',open=list.filter(t=>!t.done);
    const info=`<div class="space-info"><p>${esc(project.description||'Seu próximo passo começa aqui.')}</p><dl><dt>Status</dt><dd>${PROJECT_STATUS[project.status]}</dd><dt>Tarefas</dt><dd>${open.length} pendente${open.length===1?'':'s'} de ${list.length}</dd><dt>Conhecimento</dt><dd>${ns.length} nota${ns.length===1?'':'s'}</dd><dt>Referências</dt><dd>${refs.length} registrada${refs.length===1?'':'s'}</dd></dl>${readonly?'':`<button class="button tertiary" data-project-action="edit" data-project-id="${esc(project.id)}">${icon('edit',16)} Editar projeto</button>`}</div>`;
    let content;
    if(r.tab==='overview') {
      const bodies={tasks:`<div class="space-panel-content">${tasks(open.slice(0,4),readonly)}${!readonly?action('new-task','+ Nova tarefa'):''}</div>`,focus:focusContent(),info,notes:`<div class="space-panel-content space-recent">${notes(ns.slice(0,3),readonly,true)}</div>`};
      content=`<div class="widget-grid space-grid">${SPACE_WIDGETS.map(def=>panel(def,bodies[def.id],def.id==='tasks'?tabLink('tasks','Ver todas'):def.id==='notes'?tabLink('knowledge','Conhecimento'):'')).join('')}</div>`;
    } else if(r.tab==='tasks')content=`<div class="inner-block"><div class="block-top"><h2>Atividades deste projeto</h2>${readonly?'':action('new-task','+ Nova tarefa')}</div>${tasks(list,readonly)}</div>`;
    else if(r.tab==='knowledge')content=`<div class="inner-block"><div class="block-top"><h2>Conhecimento deste projeto</h2><div class="space-actions">${readonly?'':action('link-note','Vincular nota existente')+action('new-note','+ Nova nota')}</div></div>${notes(ns,readonly)}</div>`;
    else content=`<div class="inner-block"><div class="block-top"><h2>Links e materiais</h2>${readonly?'':action('new-reference','+ Nova referência')}</div>${refs.map(ref=>`<article class="space-reference" data-space-reference="${esc(ref.id)}"><div class="block-top"><h3>${esc(ref.title)}</h3>${readonly?'':action('edit-reference','Editar',ref.id)}</div><small class="muted">${ref.kind==='link'?'LINK':'MATERIAL'}</small><p>${esc(ref.description)}</p>${ref.url?`<a href="${esc(ref.url)}" target="_blank" rel="noopener noreferrer">Abrir ${esc(ref.title)} ${icon('link',14)}</a>`:'<p class="muted">Material descrito neste espaço · sem arquivo anexado.</p>'}</article>`).join('')||empty('Nenhuma referência ainda. Reúna links e descrições de materiais para consultar depois.')}</div>`;
    return `<div class="inner-page project-space" style="--project-color:${projectColor(project)};--project-ink:${projectInk(project)}"><a class="quiet-link space-back" href="#/projects">← Biblioteca de Projetos</a><div class="project-library-heading space-heading"><span class="project-emblem">${icon(project.icon,28)}</span><div><div class="eyebrow">SEU ESPAÇO DE TRABALHO</div><h1 id="space-title" tabindex="-1">${esc(project.name)}<span class="title-stop">.</span></h1><p>${esc(project.description||'Ideias, atividades e referências no mesmo lugar.')}</p></div><span class="project-status status-${project.status}">${PROJECT_STATUS[project.status]}</span></div>${readonly?'<p class="space-archive" role="status">Projeto arquivado · tarefas, notas e referências preservadas. Restaure-o na Biblioteca para editar.</p>':''}<div class="space-tabs" role="tablist" aria-label="Áreas do projeto">${Object.entries(SPACE_TABS).map(([tab,label])=>`<button id="space-tab-${tab}" role="tab" aria-selected="${r.tab===tab}" aria-controls="space-content" tabindex="${r.tab===tab?'0':'-1'}" data-space-tab="${tab}">${label}</button>`).join('')}</div><p class="space-feedback" role="status">${esc(feedback)}</p><div id="space-content" role="tabpanel" aria-labelledby="space-tab-${r.tab}">${content}</div></div>`;
  }
  function dialog() {
    const {kind,id}=editing,{project}=records(),collection=kind==='task'?state.tasks:kind==='note'?state.notes:state.references;
    const item=id===null?null:collection.find(r=>sameId(r.id,id)),label=({task:'tarefa',note:'nota',reference:'referência',link:'vínculo de nota'})[kind];
    const title=kind==='link'?'Vincular nota existente':`${item?'Editar':'Nova'} ${label}`;
    let fields=kind==='link'?`<label for="space-note-link">Nota<select id="space-note-link" name="noteId" required><option value="">Selecione uma nota</option>${state.notes.filter(n=>!n.projectIds.some(id=>sameId(id,project.id))).map(n=>`<option value="${esc(n.id)}">${esc(n.title)}</option>`).join('')}</select></label><p>O conteúdo será compartilhado com este projeto, sem criar uma cópia.</p>`:`<label for="space-item-title">Título<input id="space-item-title" name="title" required maxlength="120" value="${esc(item?.title??'')}" autocomplete="off"></label>`;
    if(kind==='task')fields+=`<label for="space-priority">Prioridade<select id="space-priority" name="priority">${['Normal','Alta'].map(p=>`<option ${item?.priority===p?'selected':''}>${p}</option>`).join('')}</select></label><label class="space-check"><input type="checkbox" name="done" ${item?.done?'checked':''}> Concluída</label>`;
    if(kind==='note')fields+=`<label for="space-note-body">Conteúdo Markdown<textarea id="space-note-body" name="body" rows="7" spellcheck="false">${esc(item?.body??'')}</textarea></label><fieldset><legend>Projetos vinculados</legend>${state.projects.filter(p=>p.status!=='archived'||item?.projectIds.some(id=>sameId(id,p.id))).map(p=>`<label class="space-check"><input type="checkbox" name="projectIds" value="${esc(p.id)}" ${sameId(p.id,project.id)||item?.projectIds.some(id=>sameId(id,p.id))?'checked':''} ${sameId(p.id,project.id)?'disabled':''}>${esc(p.name)}${p.status==='archived'?' (arquivado)':''}</label>`).join('')}</fieldset>`;
    if(kind==='reference')fields+=`<label for="space-reference-kind">Tipo<select id="space-reference-kind" name="kind"><option value="link">Link</option><option value="material" ${item?.kind==='material'?'selected':''}>Material</option></select></label><label for="space-reference-url">URL <span class="project-optional">obrigatória para links</span><input id="space-reference-url" name="url" type="url" value="${esc(item?.url??'')}" placeholder="https://"></label><label for="space-reference-description">Descrição do material ou link<textarea id="space-reference-description" name="description" maxlength="2000" rows="3">${esc(item?.description??'')}</textarea></label>`;
    return `<div class="scrim"><div class="dialog project-dialog workspace-dialog" role="dialog" aria-modal="true" aria-labelledby="space-form-title" aria-describedby="space-form-hint"><form id="space-form"><div class="block-top"><h2 id="space-form-title">${title}</h2>${action('close','Fechar')}</div><p id="space-form-hint">${esc(project.name)} · ${kind==='note'?'Uma nota pode pertencer a vários projetos.':'O vínculo com este projeto será preservado.'}</p>${fields}<p id="space-form-error" class="project-form-error" role="alert"></p><div class="project-form-actions">${action('close','Cancelar')}<button class="button" type="submit">${kind==='link'?'Vincular nota':'Salvar '+label}</button></div></form></div></div>`;
  }
  function control(c) {return Array.from(document.querySelectorAll('[data-space-action]')).find(el=>el.dataset.spaceAction===c?.action&&el.dataset.spaceId===c?.id);}
  function close(){state.modal=null;editing=null;pending=returnControl;render();}
  function afterRender(){if(!pending)return;if(pending.dialog)document.querySelector('#space-item-title,#space-note-link')?.focus();else if(pending.tab)document.querySelector('#space-tab-'+pending.tab)?.focus({preventScroll:true});else (control(pending)??document.querySelector('#space-tab-'+route()?.tab))?.focus({preventScroll:true});pending=null;}
  function onClick(event) {
    if(state.modal==='space'&&event.target.classList.contains('scrim')){close();return true;}
    const tab=event.target.closest('[data-space-tab]');if(tab){pending={tab:tab.dataset.spaceTab};navigate(route().id,tab.dataset.spaceTab);return true;}
    const el=event.target.closest('[data-space-action]');if(!el)return false;
    const name=el.dataset.spaceAction;if(name==='close'){close();return true;}
    if(records().project?.status==='archived')return true;
    returnControl={action:name,id:el.dataset.spaceId};
    const [verb,kind]=name.split('-');editing={kind,id:verb==='edit'?el.dataset.spaceId:null};
    if(name==='link-note')editing.kind='link';
    state.modal='space';pending={dialog:true};render();return true;
  }
  function onSubmit(event){if(event.target.id!=='space-form')return false;event.preventDefault();if(state.modal!=='space')return true;const data=new FormData(event.target);
    try{const {kind,id}=editing;if(kind==='link')linkSpaceNote(state,route().id,data.get('noteId'));else saveSpaceItem(state,route().id,kind,{title:data.get('title'),priority:data.get('priority'),done:data.has('done'),body:data.get('body'),projectIds:data.getAll('projectIds'),kind:data.get('kind'),url:data.get('url'),description:data.get('description')},{id});feedback=persist()?'Alteração salva.':'Alteração somente nesta sessão; não foi persistida.';close();}
    catch(error){document.querySelector('#space-form-error').textContent=error.message;document.querySelector('#space-item-title,#space-note-link')?.focus();}return true;}
  function onKeydown(event) {
    if(state.modal==='space') {
      if(event.key==='Escape'){event.preventDefault();close();return true;}
      if(event.key==='Tab'){const controls=Array.from(document.querySelector('#space-form').querySelectorAll('button,input,select,textarea')).filter(el=>!el.disabled),first=controls[0],last=controls.at(-1);if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}}
      if((event.ctrlKey||event.metaKey)&&['k','n'].includes(event.key.toLowerCase()))event.preventDefault();return true;
    }
    if(event.target.matches('[data-space-tab]')&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const tabs=Object.keys(SPACE_TABS),index=tabs.indexOf(event.target.dataset.spaceTab),tab=tabs[event.key==='Home'?0:event.key==='End'?tabs.length-1:(index+(event.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length];pending={tab};navigate(route().id,tab);return true;}return false;
  }
  return {view,dialog,onClick,onSubmit,onKeydown,afterRender};
}
