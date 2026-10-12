// Build-time reuse of approved view fragments; never loads browser storage.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { createHash } from 'node:crypto';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = readFileSync(resolve(root, 'prototype/app.js'), 'utf8');
const slice = (from, to) => source.slice(source.indexOf(from), source.indexOf(to));
const code = [
  slice('const defaultProjects', 'function showStorageStatus'),
  slice('const esc=', 'const $='),
  slice('const icons=', 'const projectLibrary='),
  slice('const nav=', 'function board()'),
  'const state = structuredClone(defaults); const projectDefs = state.projects;',
  'for(const p of projectDefs) p.status="active";',
  'for(const t of state.tasks) t.projectId=projectDefs.find(p=>p.name===t.project)?.id;',
  'for(const n of state.notes) n.projectIds=[projectDefs.find(p=>p.name===n.project)?.id];',
  'const sameId=(a,b)=>String(a)===String(b); const projectName=id=>projectDefs.find(p=>sameId(p.id,id))?.name||"Pessoal";',
  'const noteProjects=n=>n.projectIds.map(projectName).join(", "); const knowledgeNotes=s=>s.notes;',
  'output({widgetDefs, nav, dock, labels, icons, widgets:Object.fromEntries(Object.keys(widgetDefs).map(id=>[id, widgetContent(id)]))});'
].join('\n');
let data;
runInNewContext(code, {structuredClone, output: value => { data = value; }});
const write = (path, content) => {
  const target=resolve(root,'rails',path);mkdirSync(dirname(target),{recursive:true});writeFileSync(target,content);
};
write('config/studio_fixture.json', JSON.stringify({widgets:data.widgetDefs,nav:data.nav,dock:data.dock,labels:data.labels,icons:data.icons},null,2)+'\n');
for (const [id, html] of Object.entries(data.widgets)) {
  const fragment = html.replace(/data-modal="(?:task|note)"/g,'data-demo="capture"')
    .replace(/data-action="focus-[^"]+"/g,'data-demo="focus"')
    .replace(/data-open-project="[^"]+"/g,'data-route="projects"')
    .replace(/data-note="[^"]+"/g,'data-route="knowledge"')
    .replace(/<input type="checkbox" data-task="[^"]+"/g,'<input type="checkbox" disabled aria-label="Tarefa demonstrativa"')
    .replace(/<button class="task-play tip" title="Abrir foco"/g,'<button class="task-play tip" aria-label="Abrir foco demonstrativo" title="Abrir foco"');
  write(`app/views/studio/widgets/_${id}.html.erb`, '<%# Approved P0.4 fragment, synthetic read-only fixture. %>\n'+fragment+'\n');
}
write('config/prototype_assets.json', JSON.stringify({baseline:'p0.4-approved',app_sha256:createHash('sha256').update(source).digest('hex'),css_sha256:createHash('sha256').update(readFileSync(resolve(root,'prototype/style.css'))).digest('hex')},null,2)+'\n');
write('app/assets/stylesheets/studio.css',readFileSync(resolve(root,'prototype/style.css')));
console.log('Reused seven widget fragments, icon/navigation fixture and approved CSS.');
