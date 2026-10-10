import {spaceHash} from './project-space.mjs';
import {PROJECT_STATUS, PROJECT_ICONS, PROJECT_COLORS, projectColor, projectCounts, selectProjects,
  createProject, updateProject, favoriteProject, changeProjectStatus, restoreProject} from './projects.mjs';

// Somente a biblioteca e seu formulário; o shell continua sob responsabilidade do app.
export function createProjectLibrary({state,esc,icon,persist,render}) {
  let query='', feedback='', editingId=null, focusPending=null, returnFocus=null;
  const prefs=()=>state.projectLibrary;
  const projectById=id=>state.projects.find(p=>String(p.id)===String(id));
  const control=(action,id)=>Array.from(document.querySelectorAll('[data-project-action]'))
    .find(el=>el.dataset.projectAction===action && (id===undefined||el.dataset.projectId===String(id)));
  function card(project) {
    const counts=projectCounts(state,project.id), color=projectColor(project);
    const activity=project.updatedAt ? 'Atualizado em '+new Intl.DateTimeFormat('pt-BR',{day:'2-digit',month:'short'}).format(new Date(project.updatedAt)) : 'Sem atividade registrada';
    const button=(action,label,ic)=>`<button type="button" class="project-control" data-project-action="${action}" data-project-id="${esc(project.id)}" aria-label="${esc(label+' '+project.name)}">${icon(ic,15)} ${label}</button>`;
    return `<article class="project-card ${project.status==='archived'?'is-archived':''}" style="--project-color:${color}" data-project-card="${esc(project.id)}" aria-label="${esc(project.name)}">
      <div class="project-card-top"><span class="project-emblem">${icon(project.icon,25)}</span><span class="project-status status-${project.status}"><i></i>${PROJECT_STATUS[project.status]}</span><button type="button" class="project-favorite ${project.favorite?'is-favorite':''}" data-project-action="favorite" data-project-id="${esc(project.id)}" aria-pressed="${project.favorite}" aria-label="${esc((project.favorite?'Desfavoritar ':'Favoritar ')+project.name)}">${icon('star',19)}</button></div>
      <h2><a class="project-space-link" href="${spaceHash(project.id)}">${esc(project.name)} ${icon('chevron',16)}</a></h2><p class="project-description">${esc(project.description||'Um espaço pronto para suas próximas ideias.')}</p>
      <div class="project-relations"><span>${icon('check',15)} <strong>${counts.open}</strong> aberta${counts.open===1?'':'s'}</span><span>${icon('book',15)} <strong>${counts.notes}</strong> nota${counts.notes===1?'':'s'}</span></div>
      <div class="project-card-bottom"><span class="project-activity" title="Alterações do projeto e de tarefas/notas vinculadas, registradas a partir desta etapa">${activity}</span><div class="project-controls">${button('edit','Editar','edit')}${project.status==='archived'?button('restore','Restaurar','restore'):button(project.status==='active'?'pause':'activate',project.status==='active'?'Pausar':'Ativar',project.status==='active'?'pause':'play')+button('archive','Arquivar','archive')}</div></div>
    </article>`;
  }
  function results() {
    const projects=selectProjects(state,query), total=state.projects.length;
    const empty=total===0?'Seu próximo projeto começa aqui.':'Nenhum projeto nesta seleção.';
    const hint=total===0?'Crie um espaço com sua cor e reúna suas próximas ideias.':'Experimente outro termo ou altere os filtros da biblioteca.';
    return `<div class="project-results-label"><span id="project-count" role="status" aria-live="polite">${projects.length} de ${total} projeto${total===1?'':'s'}</span><span class="project-local-label">NO SEU NAVEGADOR</span></div>${projects.length?`<div class="project-library-grid">${projects.map(card).join('')}</div>`:`<div class="project-empty"><span class="project-empty-icon">${icon('grid',32)}</span><h2>${empty}</h2><p>${hint}</p><button class="button ${total?'tertiary':''}" data-project-action="${total?'clear':'new'}">${icon(total?'search':'plus',16)} ${total?'Limpar pesquisa e filtros':'Criar primeiro projeto'}</button></div>`}`;
  }
  function view() {
    return `<div class="inner-page project-library"><div class="project-library-heading"><div><div class="eyebrow">ACCIO HUB <span class="eyebrow-sep">/</span> SEUS ESPAÇOS</div><h1>Projetos<span class="title-stop">.</span></h1><p>Uma coleção do que você quer construir.</p></div><button class="button" data-project-action="new">${icon('plus',17)} Novo projeto</button></div>
      <div class="project-toolbar"><label class="project-search">${icon('search',18)}<input id="project-search" type="search" placeholder="Buscar por nome ou descrição" aria-label="Pesquisar projetos" value="${esc(query)}" autocomplete="off"></label><label class="project-order">Ordenar <select id="project-sort"><option value="name" ${prefs().sort==='name'?'selected':''}>Por nome</option><option value="recent" ${prefs().sort==='recent'?'selected':''}>Atividade recente</option></select></label></div>
      <div class="project-filter-row"><div class="project-filters" role="group" aria-label="Filtrar projetos por status">${[['all','Todos'],['active','Ativos'],['paused','Pausados'],['archived','Arquivados']].map(([value,label])=>`<button type="button" class="project-filter ${prefs().status===value?'selected':''}" data-project-filter="${value}" aria-pressed="${prefs().status===value}">${label}</button>`).join('')}</div><button type="button" class="project-filter favorite-filter ${prefs().favoritesOnly?'selected':''}" data-project-action="favorites" aria-pressed="${prefs().favoritesOnly}">${icon('star',16)} Favoritos</button></div>
      <p id="project-feedback" class="project-feedback" role="status" aria-live="polite">${esc(feedback)}</p><div id="project-results">${results()}</div></div>`;
  }
  function dialog() {
    const project=editingId===null?null:projectById(editingId);
    return `<div class="scrim"><div class="dialog project-dialog" role="dialog" aria-modal="true" aria-labelledby="project-dialog-title" aria-describedby="project-form-hint"><form id="project-form">
      <div class="block-top"><div><div class="eyebrow">SEU ESPAÇO, SEU JEITO</div><h2 id="project-dialog-title">${project?'Editar projeto':'Novo projeto'}</h2></div><button type="button" class="project-close" data-project-action="close" aria-label="Fechar formulário de projeto">${icon('x',19)}</button></div>
      <div id="project-preview" class="project-form-preview" style="--project-color:${project?projectColor(project):PROJECT_COLORS.mint}"><span class="project-emblem">${icon(project?.icon??'grid',24)}</span><strong>${esc(project?.name??'Seu próximo projeto')}</strong></div>
      <label for="project-name">Nome<input id="project-name" name="name" required maxlength="80" autocomplete="off" value="${esc(project?.name??'')}" placeholder="Dê um nome ao seu espaço"></label>
      <label for="project-description">Descrição <span class="project-optional">opcional</span><textarea id="project-description" name="description" maxlength="500" rows="3" placeholder="O que você quer explorar ou construir?">${esc(project?.description??'')}</textarea></label>
      <div class="project-form-properties"><label for="project-icon">Ícone<select id="project-icon" name="icon">${project&&!Object.hasOwn(PROJECT_ICONS,project.icon)?`<option value="${esc(project.icon)}">Ícone atual</option>`:''}${Object.entries(PROJECT_ICONS).map(([id,label])=>`<option value="${id}" ${project?.icon===id?'selected':''}>${label}</option>`).join('')}</select></label><label for="project-color">Cor<input id="project-color" name="color" type="color" value="${project?projectColor(project):PROJECT_COLORS.mint}"><input id="project-color-hex" aria-label="Cor hexadecimal" type="text" required pattern="#[0-9a-fA-F]{6}" maxlength="7" value="${project?projectColor(project):PROJECT_COLORS.mint}" spellcheck="false"></label></div>
      <p id="project-form-error" role="alert" class="project-form-error"></p><p id="project-form-hint">${project?'O ID e os vínculos com tarefas e notas serão preservados.':'Você poderá pausar, favoritar ou arquivar este espaço depois.'}</p>
      <div class="project-form-actions"><button type="button" class="button tertiary" data-project-action="close">Cancelar</button><button type="submit" class="button">${icon('check',16)} ${project?'Salvar alterações':'Criar projeto'}</button></div>
    </form></div></div>`;
  }
  function refresh(focus) {
    const scroll=document.querySelector('.viewport')?.scrollTop??0;
    focusPending=focus;render();if(!focus?.reveal)document.querySelector('.viewport')?.scrollTo({top:scroll,behavior:'instant'});
  }
  function commit(message,focus) {feedback=persist()?message:`${message} Alteração somente nesta sessão; não foi persistida.`;refresh(focus);}
  function open(id=null,trigger=null) {
    editingId=id;returnFocus=trigger?{action:trigger.dataset.projectAction,id:trigger.dataset.projectId}:null;
    state.modal='project';focusPending={dialog:true};render();
  }
  function close() {state.modal=null;refresh(returnFocus??{filter:prefs().status});}
  function afterRender() {
    if (!focusPending) return;
    if (focusPending.dialog) document.querySelector('#project-name')?.focus();
    else if (state.page==='projects') {
      const target=focusPending.filter?document.querySelector(`[data-project-filter="${focusPending.filter}"]`)
        :control(focusPending.action,focusPending.id);
      (target??document.querySelector('[data-project-filter="all"]'))?.focus({preventScroll:true});
      if(focusPending.reveal)target?.closest('[data-project-card]')?.scrollIntoView({block:'nearest',behavior:'instant'});
    }
    focusPending=null;
  }
  function onClick(event) {
    if(state.modal==='project'&&event.target.classList.contains('scrim')){close();return true;}
    const el=event.target.closest('[data-project-action],[data-project-filter]');if(!el)return false;
    if (el.dataset.projectFilter) {prefs().status=el.dataset.projectFilter;persist();refresh({filter:prefs().status});return true;}
    const action=el.dataset.projectAction,id=el.dataset.projectId;
    if(action==='new'){open(null,el);return true;}
    if(action==='edit'){state.projectId=projectById(id).id;persist();open(id,el);return true;}
    if(action==='close'){close();return true;}
    if(action==='clear'){query='';prefs().status='all';prefs().favoritesOnly=false;persist();refresh({filter:'all'});return true;}
    if(action==='favorites'){prefs().favoritesOnly=!prefs().favoritesOnly;persist();refresh({action});return true;}
    try {
      const project=projectById(id);
      if(action==='favorite'){favoriteProject(state,id);commit(project.favorite?'Projeto adicionado aos favoritos.':'Projeto removido dos favoritos.',{action,id});}
      else if(action==='restore'){restoreProject(state,id);commit(`Projeto restaurado como ${PROJECT_STATUS[project.status].toLowerCase()}.`,{action:'edit',id});}
      else {changeProjectStatus(state,id,({pause:'paused',activate:'active',archive:'archived'})[action]);commit(action==='archive'?'Projeto arquivado. Tarefas e notas foram preservadas.':`Projeto ${PROJECT_STATUS[project.status].toLowerCase()}.`,{action:'edit',id});}
    } catch(error) {feedback=error.message;refresh({filter:prefs().status});}
    return true;
  }
  function preview() {
    const form=document.querySelector('#project-form');if(!form)return;
    const data=new FormData(form), node=document.querySelector('#project-preview');
    node.style.setProperty('--project-color',data.get('color'));
    node.innerHTML=`<span class="project-emblem">${icon(data.get('icon'),24)}</span><strong>${esc(data.get('name')||'Seu próximo projeto')}</strong>`;
  }
  function onInput(event) {
    if(event.target.id==='project-search'){query=event.target.value;document.querySelector('#project-results').innerHTML=results();return true;}
    if(event.target.closest('#project-form')){if(event.target.id==='project-color')document.querySelector('#project-color-hex').value=event.target.value;if(event.target.id==='project-color-hex'&&/^#[0-9a-f]{6}$/i.test(event.target.value))document.querySelector('#project-color').value=event.target.value;preview();return true;}
    return false;
  }
  function onChange(event) {
    if(event.target.id==='project-sort'){prefs().sort=event.target.value;persist();refresh();document.querySelector('#project-sort')?.focus();return true;}
    if(event.target.closest('#project-form')){preview();return true;}
    return false;
  }
  function onSubmit(event) {
    if(event.target.id!=='project-form')return false;
    event.preventDefault();if(state.modal!=='project')return true;
    const data=new FormData(event.target), original=editingId===null?null:projectById(editingId);
    // Uma edição sem alterar a cor mantém o tint legado e a aparência do board.
    const color=original?.color===null && data.get('color')===projectColor(original)?null:data.get('color');
    try {
      const input={name:data.get('name'),description:data.get('description'),icon:data.get('icon'),color};
      const project=original?updateProject(state,editingId,input):createProject(state,input);
      state.projectId=project.id;state.modal=null;
      if(!original){query='';prefs().status='all';prefs().favoritesOnly=false;}
      commit(original?'Informações do projeto atualizadas.':'Projeto criado.',{action:'edit',id:project.id,reveal:!original});
    }catch(error){const message=document.querySelector('#project-form-error');message.textContent=error.message;document.querySelector('#project-name')?.focus();}
    return true;
  }
  function onKeydown(event) {
    if(state.modal!=='project')return false;
    if(event.key==='Escape'){event.preventDefault();close();return true;}
    if(event.key==='Tab') {
      const elements=Array.from(document.querySelector('#project-form').querySelectorAll('button,input,select,textarea')).filter(el=>!el.disabled);
      const first=elements[0],last=elements.at(-1);
      if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
    }
    // Evitar atalhos globais abrindo outro modal sobre um formulário em edição.
    if((event.ctrlKey||event.metaKey)&&['k','n'].includes(event.key.toLowerCase()))event.preventDefault();
    return true;
  }
  function reveal(id){query='';prefs().status='all';prefs().favoritesOnly=false;focusPending={action:'edit',id,reveal:true};}
  return {reveal,view,dialog,onClick,onInput,onChange,onSubmit,onKeydown,afterRender,close};
}
